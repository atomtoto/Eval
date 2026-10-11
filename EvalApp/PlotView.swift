import Charts
import EvalCore
import SwiftUI

/// A result plotted against one ruler variable, over its plot interval.
/// The sheet is evaluated again for each sample, away from the main thread.
struct PlotView: View {
    let notebook: NotebookStore
    let request: PlotRequest
    @Environment(\.dismiss) private var dismiss
    @State private var variableID: UUID
    /// The interval of a name that the sheet does not declare, which has no ruler to give one.
    @State private var lowerBound = -10.0
    @State private var upperBound = 10.0
    @State private var plot: SweepPlot?
    @State private var selectedX: Double?
    /// The unit of the result’s last value, kept while the current value is an error.
    @State private var lastResultUnit = ""
    @ScaledMetric(relativeTo: .body) private var chartHeight = 260.0

    init(notebook: NotebookStore, request: PlotRequest) {
        self.notebook = notebook
        self.request = request
        _variableID = State(initialValue: request.variableLineID ?? UUID())
    }

    private var freeVariable: String? {
        request.freeVariable
    }

    private var variableName: String {
        freeVariable ?? variable?.name ?? ""
    }

    private var variableUnit: String {
        freeVariable == nil ? variable?.unit ?? "" : ""
    }

    /// The interval the plot covers: the one typed for a free name, else the variable's own.
    private var plotRange: VariableAdjustmentRange? {
        if freeVariable != nil {
            return VariableAdjustmentRange(lowerBound: lowerBound, upperBound: upperBound,
                                           step: (upperBound - lowerBound) / 100)
        }
        return variable.flatMap { notebook.adjustmentRange(for: variableID, variable: $0) }
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
        guard let quantity = result?.quantity else { return lastResultUnit }
        return QuantityFormatter.unitSymbol(for: quantity.dimension, in: result?.displayUnit)
    }

    /// What a new sampling depends on: the variable, the sheet and the plot interval.
    private struct SamplingKey: Equatable {
        let variableID: UUID
        let source: String
        let range: VariableAdjustmentRange?
        let isFree: Bool
    }

    private var samplingKey: SamplingKey {
        SamplingKey(variableID: variableID, source: notebook.source, range: plotRange, isFree: freeVariable != nil)
    }

    var body: some View {
        NavigationStack {
            Form {
                if freeVariable == nil {
                    Section {
                        Picker("Variable", selection: $variableID) {
                            ForEach(variables) { item in
                                Text(item.variable.name).tag(item.id)
                            }
                        }
                        .pickerStyle(.menu)
                    }
                }

                Section {
                    chartContent
                } footer: {
                    if freeVariable == nil {
                        Text("L’intervalle tracé est l’intervalle du graphique de la variable : modifiez-le avec ses réglages pour tracer une autre plage. La ligne pointillée marque la valeur actuelle. Touchez le graphique pour lire une valeur.")
                    } else {
                        Text("\(variableName) n’est pas déclaré dans la feuille : le tracé le fait varier sur l’intervalle ci-dessous, sans rien ajouter à la feuille. Touchez le graphique pour lire une valeur.")
                    }
                }

                if let freeVariable {
                    Section("Intervalle de \(freeVariable)") {
                        LabeledContent("De") {
                            TextField("De", value: $lowerBound, format: .number)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                        LabeledContent("À") {
                            TextField("À", value: $upperBound, format: .number)
                                .keyboardType(.numbersAndPunctuation)
                                .multilineTextAlignment(.trailing)
                        }
                    }
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
            .warmPage()
            .navigationTitle(Text("\(resultName) en fonction de \(variableName)"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Terminé") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                        .tint(.primary)
                }
            }
            .task(id: samplingKey) {
                // A ruler being dragged changes the sheet often: sampling waits for a pause.
                if plot?.variableID == variableID {
                    do { try await Task.sleep(for: .milliseconds(200)) } catch { return }
                }
                await load()
            }
            .onChange(of: resultUnit, initial: true) { _, unit in
                if !unit.isEmpty || result?.quantity != nil { lastResultUnit = unit }
            }
        }
    }

    // MARK: Chart

    @ViewBuilder
    private var chartContent: some View {
        if let plot, plot.variableID == variableID, let failure = plot.failure {
            switch failure {
            case .missingLine:
                ContentUnavailableView("Tracé impossible", systemImage: "chart.xyaxis.line",
                                       description: Text("La ligne du résultat ou celle de la variable n’existe plus, ou la variable n’est plus un nombre réglable."))
            case .noRange:
                ContentUnavailableView("Tracé impossible", systemImage: "chart.xyaxis.line",
                                       description: freeVariable == nil
                                       ? Text("La variable n’a pas d’intervalle de graphique valide. Modifiez ses réglages.")
                                       : Text("L’intervalle est vide : « De » doit être plus petit que « À »."))
            case .undefined:
                ContentUnavailableView("Aucune valeur calculable", systemImage: "chart.xyaxis.line",
                                       description: Text("Le résultat n’est défini pour aucune valeur de l’intervalle du graphique."))
            }
        } else if let plot, plot.variableID == variableID, freeVariable != nil || variable != nil {
            chart(plot)
        } else {
            ProgressView("Calcul du tracé…")
                .frame(maxWidth: .infinity, minHeight: chartHeight)
        }
    }

    private func chart(_ plot: SweepPlot) -> some View {
        let variableName = variableName
        let variableUnit = variableUnit
        let selected = selectedX.flatMap { plot.nearest(to: $0) }
        let xLabel = axisLabel(variableName, unit: variableUnit)
        let yLabel = axisLabel(resultName, unit: resultUnit)
        return Chart {
            ForEach(Array(plot.segments.enumerated()), id: \.offset) { index, segment in
                if segment.count == 1, let point = segment.first {
                    // An isolated value has no neighbour to join: it is drawn as a point.
                    PointMark(x: .value(xLabel, point.x), y: .value(yLabel, point.y))
                        .symbolSize(20)
                        .foregroundStyle(.tint)
                } else {
                    ForEach(segment, id: \.index) { point in
                        LineMark(x: .value(xLabel, point.x), y: .value(yLabel, point.y),
                                 series: .value("Segment", index))
                        .foregroundStyle(.tint)
                    }
                }
            }
            if freeVariable == nil, let variable {
                RuleMark(x: .value("Valeur actuelle", variable.value))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Valeur actuelle")
                    .accessibilityValue(spokenText(variable.value, unit: variable.unit))
            }
            if let selected {
                RuleMark(x: .value(xLabel, selected.x))
                    .foregroundStyle(.tertiary)
                    .annotation(position: .top, spacing: 4,
                                overflowResolution: .init(x: .fit(to: .chart), y: .disabled)) {
                        VStack(alignment: .leading) {
                            Text("\(variableName) = \(valueText(selected.x, unit: variableUnit))")
                            Text("\(resultName) = \(valueText(selected.y, unit: resultUnit))")
                        }
                        .font(.caption.monospacedDigit())
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel("\(variableName) égale \(spokenText(selected.x, unit: variableUnit)), \(resultName) égale \(spokenText(selected.y, unit: resultUnit))")
                        .padding(6)
                        .background(.regularMaterial, in: .rect(cornerRadius: 8))
                    }
                PointMark(x: .value(xLabel, selected.x), y: .value(yLabel, selected.y))
                    .foregroundStyle(.tint)
            }
        }
        .chartXSelection(value: $selectedX)
        .chartXScale(domain: plot.range.lowerBound...plot.range.upperBound)
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
        let id = variableID
        if let freeVariable {
            guard let index = notebook.lineIndex(of: request.resultLineID) else {
                plot = SweepPlot(variableID: id, failure: .missingLine)
                return
            }
            guard let range = plotRange else {
                plot = SweepPlot(variableID: id, failure: .noRange)
                return
            }
            let points = await Self.sample(source: notebook.source, freeVariable: freeVariable,
                                           resultIndex: index, range: range)
            guard !Task.isCancelled else { return }
            plot = SweepPlot(variableID: id, range: range, points: points)
            return
        }
        guard let index = notebook.lineIndex(of: request.resultLineID),
              let variableIndex = notebook.lineIndex(of: variableID) else {
            plot = SweepPlot(variableID: variableID, failure: .missingLine)
            return
        }
        guard let range = plotRange else {
            plot = SweepPlot(variableID: variableID, failure: .noRange)
            return
        }
        let points = await Self.sample(source: notebook.source, variableIndex: variableIndex,
                                       resultIndex: index, range: range)
        guard !Task.isCancelled else { return }
        plot = SweepPlot(variableID: id, range: range, points: points)
    }

    @concurrent
    private nonisolated static func sample(source: String, freeVariable: String, resultIndex: Int,
                                           range: VariableAdjustmentRange) async -> [SweepPoint] {
        VariableSweep.sample(source: source, freeVariable: freeVariable, resultLineIndex: resultIndex,
                             range: range, count: 161)
    }

    @concurrent
    private nonisolated static func sample(source: String, variableIndex: Int, resultIndex: Int,
                                           range: VariableAdjustmentRange) async -> [SweepPoint] {
        VariableSweep.sample(source: source, variableLineIndex: variableIndex, resultLineIndex: resultIndex,
                             range: range, count: 161)
    }
}

/// The samples of one sweep, with the runs between gaps, or why there are none.
private struct SweepPlot {
    enum Failure {
        case missingLine, noRange, undefined
    }

    let variableID: UUID
    /// The plot interval, which the horizontal axis covers.
    let range: VariableAdjustmentRange
    let points: [SweepPoint]
    let segments: [[SweepPoint]]
    let failure: Failure?

    init(variableID: UUID, range: VariableAdjustmentRange, points: [SweepPoint]) {
        self.variableID = variableID
        self.range = range
        self.points = points
        segments = VariableSweep.segments(points)
        failure = segments.isEmpty ? .undefined : nil
    }

    init(variableID: UUID, failure: Failure) {
        self.variableID = variableID
        range = VariableAdjustmentRange(lowerBound: 0, upperBound: 1, step: 1)!
        points = []
        segments = []
        self.failure = failure
    }

    func nearest(to x: Double) -> SweepPoint? {
        points.min { abs($0.x - x) < abs($1.x - x) }
    }
}
