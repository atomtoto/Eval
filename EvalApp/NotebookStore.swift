import EvalCore
import SwiftUI

@MainActor
final class NotebookStore: ObservableObject {
    @Published var source: String {
        didSet {
            defaults.set(source, forKey: Self.storageKey)
            scheduleEvaluation()
        }
    }
    @Published private(set) var evaluation: NotebookEvaluation
    @Published private(set) var isEvaluating = false
    private var evaluationTask: Task<Void, Never>?
    private let defaults: UserDefaults
    private static let storageKey = "eval.notebook.source.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let source = defaults.string(forKey: Self.storageKey) ?? NotebookExample.kineticEnergy.source
        self.source = source
        evaluation = NotebookEngine.evaluate(source)
    }

    func append(_ expression: String) {
        source += source.isEmpty || source.hasSuffix("\n") ? expression : "\n\(expression)"
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
