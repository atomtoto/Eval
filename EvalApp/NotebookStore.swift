import EvalCore
import SwiftUI

@MainActor
final class NotebookStore: ObservableObject {
    @Published var source: String {
        didSet {
            resultSelection.reconcile(source: source)
            defaults.set(source, forKey: Self.storageKey)
            saveSelection()
            scheduleEvaluation()
        }
    }
    @Published var editorMode: NotebookEditorMode {
        didSet { defaults.set(editorMode.rawValue, forKey: Self.editorModeKey) }
    }
    @Published private(set) var resultSelection: ResultSelection
    @Published private(set) var evaluation: NotebookEvaluation
    @Published private(set) var isEvaluating = false
    private var evaluationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let storageKey = "eval.notebook.source.v1"
    private static let selectionKey = "eval.notebook.resultSelection.v1"
    private static let editorModeKey = "eval.notebook.editorMode.v1"

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
        saveSelection()
    }

    private func saveSelection() {
        if let data = try? JSONEncoder().encode(resultSelection) {
            defaults.set(data, forKey: Self.selectionKey)
        }
    }

    private func scheduleEvaluation() {
        evaluationTask?.cancel()
        isEvaluating = true
        let snapshot = source
        evaluationTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(180))
            } catch {
                return
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
