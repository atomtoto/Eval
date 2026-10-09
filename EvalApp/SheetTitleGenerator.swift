import EvalCore
import Foundation
import os
import UIKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Whether untitled sheets are named automatically. On by default.
enum AutomaticTitleSetting {
    static let storageKey = "eval.automaticTitles.v1"

    static var isEnabled: Bool {
        UserDefaults.standard.object(forKey: storageKey) as? Bool ?? true
    }
}

/// Names sheets with the on-device model of Apple Intelligence (iOS 26 or later).
/// The sheet and the prompt never leave the device.
enum SheetTitleGenerator {
    enum Outcome: Sendable {
        case title(String)
        /// The model answered nothing usable: the sheet is not offered a title again.
        case noTitle
        /// The request could not run now, for instance in the background: it is tried
        /// again the next time the sheet is left.
        case retryLater
    }

    /// What the Réglages say about automatic titles.
    enum Availability: Equatable {
        case available
        /// Apple Intelligence is missing or not ready; the text says why.
        case unavailable(LocalizedStringResource)
    }

    private static let logger = Logger(subsystem: "com.atom.Eval", category: "Titles")

    /// Nil before iOS 26, where the setting is not shown.
    @MainActor
    static var availability: Availability? {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *) else { return nil }
        switch SystemLanguageModel.default.availability {
        case .available:
            return .available
        case .unavailable(.deviceNotEligible):
            return .unavailable("Nécessite Apple Intelligence, que cet appareil ne prend pas en charge.")
        case .unavailable(.appleIntelligenceNotEnabled):
            return .unavailable("Nécessite Apple Intelligence. Activez-la dans Réglages › Apple Intelligence et Siri.")
        case .unavailable(.modelNotReady):
            return .unavailable("Nécessite Apple Intelligence, dont le modèle est en cours de préparation. Réessayez plus tard.")
        case .unavailable:
            return .unavailable("Nécessite Apple Intelligence.")
        }
        #else
        return nil
        #endif
    }

    @MainActor
    static var isAvailable: Bool {
        availability == .available
    }

    /// A short French title for the sheet `content`. Call it away from the main actor.
    static func title(for content: String) async -> Outcome {
        #if canImport(FoundationModels)
        guard #available(iOS 26, *), SystemLanguageModel.default.availability == .available else {
            return .retryLater
        }
        do {
            let session = LanguageModelSession(instructions: instructions)
            let response = try await session.respond(
                to: "Voici la feuille, une formule, une déclaration ou une note par ligne :\n\n\(content)",
                generating: SheetTitleProposal.self,
                options: GenerationOptions(samplingMode: .greedy))
            return AutomaticSheetTitle.sanitized(response.content.title).map(Outcome.title) ?? .noTitle
        } catch is CancellationError {
            return .retryLater
        } catch {
            logger.notice("No automatic title: \(error.localizedDescription, privacy: .public)")
            // Requests from an app in the background are refused: they wait for another visit.
            let isActive = await MainActor.run { UIApplication.shared.applicationState == .active }
            return isActive ? .noTitle : .retryLater
        }
        #else
        return .retryLater
        #endif
    }

    private static let instructions = """
        Tu donnes un titre aux feuilles d’une calculatrice de physique. Une feuille contient des \
        formules, des déclarations de grandeurs avec leurs unités (m = 80 kg) et des constantes (c, g, h).
        Réponds par un titre en français de 2 à 5 mots qui nomme le phénomène, la situation ou la \
        grandeur calculée, comme « Chute libre », « Énergie d’un photon », « Loi d’Ohm » ou \
        « Période d’un pendule ». Écris-le comme un titre : majuscule initiale, sans guillemets, \
        sans point final, sans emoji. Ne recopie pas de formule et n’ajoute rien qui ne soit pas \
        dans la feuille.
        """
}

#if canImport(FoundationModels)
@available(iOS 26, *)
@Generable(description: "Le titre d’une feuille de calcul de physique")
private struct SheetTitleProposal {
    @Guide(description: "Titre court en français, de 2 à 5 mots, sans guillemets ni point final, par exemple « Chute libre » ou « Énergie d’un photon »")
    var title: String
}
#endif
