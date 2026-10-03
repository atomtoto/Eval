import EvalCore
import SwiftUI

@MainActor
final class NotebookStore: ObservableObject {
    @Published var source: String {
        didSet {
            resultSelection.reconcile(source: source)
            let existingIDs = Set(resultSelection.entries.map(\.id))
            adjustmentRanges = adjustmentRanges.filter { existingIDs.contains($0.key) }
            manualStepIDs.formIntersection(existingIDs)
            defaults.set(source, forKey: Self.storageKey)
            saveSelection()
            saveAdjustmentRanges()
            scheduleEvaluation()
        }
    }
    @Published var editorMode: NotebookEditorMode {
        didSet { defaults.set(editorMode.rawValue, forKey: Self.editorModeKey) }
    }
    @Published private(set) var resultSelection: ResultSelection
    @Published private(set) var evaluation: NotebookEvaluation
    @Published private(set) var isEvaluating = false
    @Published private(set) var adjustmentRanges: [UUID: VariableAdjustmentRange] = [:]
    @Published private(set) var manualStepIDs: Set<UUID> = []
    private var evaluationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let storageKey = "eval.notebook.source.v1"
    private static let selectionKey = "eval.notebook.resultSelection.v1"
    private static let editorModeKey = "eval.notebook.editorMode.v1"
    private static let adjustmentRangesKey = "eval.notebook.adjustmentRanges.v1"
    private static let manualStepKey = "eval.notebook.manualStep.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let source = defaults.string(forKey: Self.storageKey) ?? NotebookExample.kineticEnergy.source
        self.source = source
        let evaluation = NotebookEngine.evaluate(source)
        self.evaluation = evaluation
        editorMode = defaults.string(forKey: Self.editorModeKey)
            .flatMap(NotebookEditorMode.init(rawValue:)) ?? .formulas
        if let data = defaults.data(forKey: Self.selectionKey),
           var selection = try? JSONDecoder().decode(ResultSelection.self, from: data) {
            selection.reconcile(source: source)
            resultSelection = selection
        } else {
            let explicitExpressions = Set(evaluation.lines.filter {
                $0.kind == .expression || $0.kind == .equation
            }.map(\.id))
            resultSelection = ResultSelection(source: source, initiallySelectedLineIDs: explicitExpressions)
        }
        if let data = defaults.data(forKey: Self.adjustmentRangesKey),
           let saved = try? JSONDecoder().decode([UUID: VariableAdjustmentRange].self, from: data) {
            let existingIDs = Set(resultSelection.entries.map(\.id))
            adjustmentRanges = saved.filter { id, range in
                existingIDs.contains(id) && VariableAdjustmentRange(
                    lowerBound: range.lowerBound, upperBound: range.upperBound, step: range.step
                ) != nil
            }
        }
        if let data = defaults.data(forKey: Self.manualStepKey),
           let saved = try? JSONDecoder().decode(Set<UUID>.self, from: data) {
            manualStepIDs = saved.intersection(Set(adjustmentRanges.keys))
        }
    }

    var selectableLines: [EvaluatedLine] {
        evaluation.lines.filter { line in
            line.kind != .empty && line.kind != .comment
                && resultSelection.entries.indices.contains(line.id)
                && resultSelection.entries[line.id].source == line.source
        }
    }

    var displayedResultLines: [EvaluatedLine] {
        selectableLines.filter { resultSelection.isSelected(at: $0.id) }
    }

    var adjustableVariables: [NotebookVariable] {
        resultSelection.entries.compactMap { entry in
            guard let variable = AdjustableVariable(source: entry.source) else { return nil }
            return NotebookVariable(id: entry.id, variable: variable)
        }
    }

    func adjustmentRange(for id: UUID, variable: AdjustableVariable) -> VariableAdjustmentRange? {
        if let range = adjustmentRanges[id] {
            if manualStepIDs.contains(id) { return range }
            return VariableAdjustmentRange(lowerBound: range.lowerBound, upperBound: range.upperBound,
                                           step: min(range.upperBound - range.lowerBound, variable.automaticStep))
                ?? VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep)
        }
        return VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep)
    }

    func setAdjustmentRange(_ range: VariableAdjustmentRange, for id: UUID, automaticStep: Bool = true) {
        adjustmentRanges[id] = range
        if automaticStep { manualStepIDs.remove(id) } else { manualStepIDs.insert(id) }
        saveAdjustmentRanges()
    }

    func adjustVariable(_ value: Double, lineID: UUID, range: VariableAdjustmentRange) {
        guard let index = resultSelection.entries.firstIndex(where: { $0.id == lineID }),
              let variable = AdjustableVariable(source: resultSelection.entries[index].source),
              value != variable.value,
              let updated = variable.source(replacingValue: value) else { return }
        adjustmentRanges[lineID] = range
        resultSelection.updateSource(updated, at: index)
        source = resultSelection.entries.map(\.source).joined(separator: "\n")
        scheduleEvaluation(debounced: false)
    }

    func append(_ expression: String, showsResult: Bool = true) {
        source += source.isEmpty || source.hasSuffix("\n") ? expression : "\n\(expression)"
        setResultDisplayed(showsResult, at: resultSelection.entries.count - 1)
    }

    func saveFormula(_ expression: String, lineID: UUID?, showsResult: Bool) {
        guard let lineID,
              let index = resultSelection.entries.firstIndex(where: { $0.id == lineID }) else {
            append(expression, showsResult: showsResult)
            return
        }
        resultSelection.updateSource(expression, at: index)
        source = resultSelection.entries.map(\.source).joined(separator: "\n")
        setResultDisplayed(showsResult, at: index)
    }

    func removeLine(id: UUID) {
        guard let index = resultSelection.entries.firstIndex(where: { $0.id == id }) else { return }
        resultSelection.removeEntry(at: index)
        source = resultSelection.entries.map(\.source).joined(separator: "\n")
    }

    func setResultDisplayed(_ selected: Bool, at index: Int) {
        resultSelection.setSelected(selected, at: index)
        saveSelection()
    }

    func selectAllResults(_ selected: Bool) {
        let currentLines = NotebookEngine.evaluate(source).lines.filter {
            $0.kind != .empty && $0.kind != .comment
        }
        resultSelection.setAllSelected(selected, selectableLineIDs: Set(currentLines.map(\.id)))
        saveSelection()
    }

    func loadExample(_ example: NotebookExample) {
        source = example.source
        let lines = NotebookEngine.evaluate(source).lines
        resultSelection = ResultSelection(source: source, initiallySelectedLineIDs: Set(lines.filter {
            $0.kind == .expression || $0.kind == .equation
        }.map(\.id)))
        adjustmentRanges = [:]
        manualStepIDs = []
        saveSelection()
        saveAdjustmentRanges()
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(resultSelection) {
            defaults.set(data, forKey: Self.selectionKey)
        }
    }

    private func saveAdjustmentRanges() {
        if let data = try? JSONEncoder().encode(adjustmentRanges) {
            defaults.set(data, forKey: Self.adjustmentRangesKey)
        }
        if let data = try? JSONEncoder().encode(manualStepIDs) {
            defaults.set(data, forKey: Self.manualStepKey)
        }
    }

    private func scheduleEvaluation(debounced: Bool = true) {
        evaluationTask?.cancel()
        isEvaluating = true
        let snapshot = source
        evaluationTask = Task { [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch {
                    return
                }
            }
            let result = await Task.detached(priority: .userInitiated) {
                NotebookEngine.evaluate(snapshot)
            }.value
            guard !Task.isCancelled, let self, self.source == snapshot else { return }
            self.evaluation = result
            self.isEvaluating = false
        }
    }
}

struct NotebookVariable: Identifiable {
    let id: UUID
    let variable: AdjustableVariable
}

enum NotebookEditorMode: String, CaseIterable, Identifiable {
    case formulas = "Formules"
    case text = "Texte"
    var id: String { rawValue }
}

enum NotebookExample: String, CaseIterable, Identifiable {
    case kineticEnergy
    case freeFall
    case light
    case dimensions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .kineticEnergy: "Énergie cinétique"
        case .freeFall: "Chute libre"
        case .light: "Énergie et lumière"
        case .dimensions: "Vérifier les dimensions"
        }
    }

    var source: String {
        switch self {
        case .kineticEnergy:
            """
            # Énergie cinétique
            E = 0,5 * m * v²
            m = 80 kg
            v = 5 m/s

            E
            # La vitesse de la lumière est reconnue
            c
            """
        case .freeFall:
            """
            # Distance parcourue depuis le repos
            d = 0,5 * a * t²
            t = 3 s
            a = 7,2 m/s²

            d
            # g est l’accélération standard de la pesanteur
            g * t
            """
        case .light:
            """
            # Énergie d’un photon
            E = h * c / lambda
            lambda = 550 nm

            E
            # h et c sont des constantes reconnues
            c / lambda
            """
        case .dimensions:
            """
            # Les deux côtés ont la dimension d’une force
            m * a == F
            F = 14,4 N
            a = 7,2 m/s²
            m = 2 kg

            # Cette addition est impossible physiquement
            2 m + 3 s
            """
        }
    }
}
