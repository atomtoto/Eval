import Charts
import EvalCore
import SwiftUI

/// A result plotted against one ruler variable, over the interval of its ruler.
/// The sheet is evaluated again for each sample, away from the main thread.
struct PlotView: View {
    let notebook: NotebookStore
    let request: PlotRequest
    @Environment(\.dismiss) private var dismiss
    @State private var variableID: UUID
    @State private var plot: SweepPlot?
    @State private var selectedX: Double?
    @ScaledMetric(relativeTo: .body) private var chartHeight = 260.0

    init(notebook: NotebookStore, request: PlotRequest) {
        self.notebook = notebook
        self.request = request
        _variableID = State(initialValue: request.variableLineID)
    }

    private var variables: [NotebookVariable] {
        notebook.plotVariables(for: request.resultLineID)
    }

    private var variable: AdjustableVariable? {
        notebook.variablesByLineID[variableID]
    }

    private var result: EvaluatedLine? {
        notebook.result(for: request.resultLineID)
    }

    private var resultName: String {
        let source = notebook.lineSource(of: request.resultLineID) ?? ""
        let name = ResultText.declaredName(in: source) ?? LineSyntax(source).body.trimmingCharacters(in: .whitespaces)
        return name.count > 24 ? String(name.prefix(24)) + "…" : name
    }

    private var resultUnit: String {
        guard let quantity = result?.quantity else { return "" }
        return QuantityFormatter.unitSymbol(for: quantity.dimension, in: result?.displayUnit)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Variable", selection: $variableID) {
                        ForEach(variables) { item in
                            Text(item.variable.name).tag(item.id)
                        }
                    }
                    .pickerStyle(.menu)
                }

                Section {
                    chartContent
                } footer: {
                    Text("L’intervalle tracé est celui du curseur de la variable : modifiez-le avec ses réglages pour tracer une autre plage. La ligne pointillée marque la valeur actuelle. Touchez le graphique pour lire une valeur.")
                }

                if let variable, let value = result?.formattedValue {
                    Section {
                        LabeledContent("\(variable.name) = \(valueText(variable.value, unit: variable.unit))", value: value)
                            .monospacedDigit()
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("\(variable.name) égale \(spokenText(variable.value, unit: variable.unit))")
                            .accessibilityValue(result?.spokenResult ?? value)
                    } header: {
                        Text("Valeur actuelle")
                    }
                }
            }
            .navigationTitle(Text("\(resultName) en fonction de \(variable?.name ?? "")"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .task(id: variableID) { await load() }
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chartContent: some View {
        if let variable, let plot, plot.variableID == variableID {
            if plot.segments.isEmpty {
                ContentUnavailableView("Aucune valeur calculable", systemImage: "chart.xyaxis.line",
                                       description: Text("Le résultat n’est défini pour aucune valeur de l’intervalle du curseur."))
            } else {
                chart(plot, variable: variable)
            }
        } else {
            ProgressView("Calcul du tracé…")
                .frame(maxWidth: .infinity, minHeight: chartHeight)
        }
    }

    private func chart(_ plot: SweepPlot, variable: AdjustableVariable) -> some View {
        let selected = selectedX.flatMap { plot.nearest(to: $0) }
        let xLabel = axisLabel(variable.name, unit: variable.unit)
        let yLabel = axisLabel(resultName, unit: resultUnit)
        return Chart {
            ForEach(Array(plot.segments.enumerated()), id: \.offset) { index, segment in
                ForEach(segment, id: \.index) { point in
                    LineMark(x: .value(xLabel, point.x), y: .value(yLabel, point.y),
                             series: .value("Segment", index))
                }
            }
            RuleMark(x: .value("Valeur actuelle", variable.value))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(.secondary)
                .accessibilityLabel("Valeur actuelle")
                .accessibilityValue(spokenText(variable.value, unit: variable.unit))
            if let selected {
                RuleMark(x: .value(xLabel, selected.x))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading) {
                            Text("\(variable.name) = \(valueText(selected.x, unit: variable.unit))")
                            Text("\(resultName) = \(valueText(selected.y, unit: resultUnit))")
                        }
                        .font(.caption.monospacedDigit())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(variable.name) égale \(spokenText(selected.x, unit: variable.unit)), \(resultName) égale \(spokenText(selected.y, unit: resultUnit))")
                        .padding(6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
                PointMark(x: .value(xLabel, selected.x), y: .value(yLabel, selected.y))
            }
        }
        .chartXSelection(value: $selectedX)
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxisLabel(xLabel)
        .chartYAxisLabel(yLabel)
        .frame(height: chartHeight)
        .padding(.vertical, 8)
    }

    private func axisLabel(_ name: String, unit: String) -> String {
        unit.isEmpty ? name : "\(name) (\(unit))"
    }

    private func valueText(_ value: Double, unit: String) -> String {
        QuantityFormatter.number(value) + (unit.isEmpty ? "" : (unit == "°" ? "" : " ") + unit)
    }

    private func spokenText(_ value: Double, unit: String) -> String {
        SpokenValue.text(value, unit: unit, fallback: valueText(value, unit: unit))
    }

    // MARK: Sampling

    private func load() async {
        selectedX = nil
        guard let variable, let index = notebook.lineIndex(of: request.resultLineID),
              let variableIndex = notebook.lineIndex(of: variableID),
              let range = notebook.adjustmentRange(for: variableID, variable: variable) else {
            plot = SweepPlot(variableID: variableID, points: [])
            return
        }
        let id = variableID
        let points = await Self.sample(source: notebook.source, variableIndex: variableIndex,
                                       resultIndex: index, range: range)
        guard !Task.isCancelled else { return }
        plot = SweepPlot(variableID: id, points: points)
    }

    @concurrent
    private nonisolated static func sample(source: String, variableIndex: Int, resultIndex: Int,
                                           range: VariableAdjustmentRange) async -> [SweepPoint] {
        VariableSweep.sample(source: source, variableLineIndex: variableIndex, resultLineIndex: resultIndex,
                             range: range, count: 161)
    }
}

/// The samples of one sweep, with the runs between gaps.
private struct SweepPlot {
    let variableID: UUID
    let points: [SweepPoint]
    let segments: [[SweepPoint]]

    init(variableID: UUID, points: [SweepPoint]) {
        self.variableID = variableID
        self.points = points
        segments = VariableSweep.segments(points)
    }

    func nearest(to x: Double) -> SweepPoint? {
        points.min { abs($0.x - x) < abs($1.x - x) }
    }
}
