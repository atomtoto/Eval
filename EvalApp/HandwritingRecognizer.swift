import CoreGraphics
import EvalCore
import Foundation
import os
import Vision
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Reads handwritten or printed formulas in an image and writes them as lines of a
/// sheet. Vision reads the characters, and `RecognizedMath` rebuilds exponents and
/// fraction bars from where they lie. With Apple Intelligence (iOS 27 or later), the
/// on-device model also reads the image itself, fractions, exponents and roots
/// included; its reading is kept when it agrees with Vision's, since a model that
/// misses the image can make up plausible formulas. The image never leaves the device.
enum HandwritingRecognizer {
    enum Engine: Sendable {
        case appleIntelligence, textRecognition
    }

    struct Recognition: Sendable {
        let lines: [String]
        let engine: Engine
    }

    enum Failure: LocalizedError {
        case nothingRead

        var errorDescription: String? {
            String(localized: "Aucune formule n’a été reconnue. Écrivez plus grand, ou photographiez la page de plus près et bien éclairée.")
        }
    }

    private static let logger = Logger(subsystem: "com.atom.Eval", category: "Handwriting")

    /// Whether this device reads formulas at all: Vision's text recognition needs iOS 18.
    static var isSupported: Bool {
        if #available(iOS 18, *) { return true }
        return false
    }

    /// The engine a recognition would use now.
    static var engine: Engine {
        #if canImport(FoundationModels)
        if #available(iOS 27, *), SystemLanguageModel.default.isAvailable,
           SystemLanguageModel.default.capabilities.contains(.vision) {
            return .appleIntelligence
        }
        #endif
        return .textRecognition
    }

    /// The lines read in `image`, top to bottom. `bars` are fraction bars drawn as a
    /// single stroke, which a text recognizer does not read as characters.
    static func recognize(_ image: CGImage, bars: [RecognizedMath.Box] = []) async throws -> Recognition {
        guard #available(iOS 18, *) else { throw Failure.nothingRead }
        let fragments = try await readText(image)
        let barFragments = bars.map { RecognizedMath.Fragment(text: "—", box: $0) }
        let textLines = RecognizedMath.lines(from: fragments + barFragments)
        #if canImport(FoundationModels)
        if #available(iOS 27, *), engine == .appleIntelligence {
            do {
                let lines = try await readWithModel(image)
                if !lines.isEmpty, textLines.isEmpty || RecognizedMath.agreement(lines, textLines) >= 0.3 {
                    return Recognition(lines: lines, engine: .appleIntelligence)
                }
                logger.notice("Apple Intelligence's reading differs from the text recognizer's: kept the latter.")
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                logger.notice("Apple Intelligence could not read the image: \(error.localizedDescription, privacy: .public)")
            }
        }
        #endif
        guard !textLines.isEmpty else { throw Failure.nothingRead }
        return Recognition(lines: textLines, engine: .textRecognition)
    }

    // MARK: Vision

    @available(iOS 18, *)
    private static func readText(_ image: CGImage) async throws -> [RecognizedMath.Fragment] {
        var request = RecognizeTextRequest()
        request.recognitionLevel = .accurate
        // Formulas are not words: a dictionary would turn « mv » into « me ».
        request.usesLanguageCorrection = false
        request.recognitionLanguages = [Locale.Language(identifier: "fr-FR"), Locale.Language(identifier: "en-US")]
        let observations = try await request.perform(on: image, orientation: nil)
        return observations.compactMap { observation in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string
            let characters = text.indices.map { index in
                candidate.boundingBox(for: index..<text.index(after: index)).map { box($0.boundingBox) }
            }
            return RecognizedMath.Fragment(text: text, box: box(observation.boundingBox),
                                           characterBoxes: characters.contains(nil) ? nil : characters.compactMap { $0 })
        }
    }

    /// Vision's rectangle, whose origin is at the lower left, with y growing downward.
    @available(iOS 18, *)
    private static func box(_ rect: NormalizedRect) -> RecognizedMath.Box {
        let flipped = rect.verticallyFlipped()
        return RecognizedMath.Box(x: flipped.origin.x, y: flipped.origin.y, width: flipped.width, height: flipped.height)
    }

    // MARK: Apple Intelligence

    #if canImport(FoundationModels)
    @available(iOS 27, *)
    private static func readWithModel(_ image: CGImage) async throws -> [String] {
        let session = LanguageModelSession(instructions: instructions)
        let response = try await session.respond(generating: RecognizedSheet.self,
                                                  options: GenerationOptions(samplingMode: .greedy)) {
            "Recopie les formules de cette image."
            Attachment(image)
        }
        // The model sometimes cuts a formula after an operator.
        return RecognizedMath.joiningBrokenLines(response.content.lines.map(RecognizedMath.normalized))
    }

    // Short and without examples: a small model copies the examples of a long
    // prompt when it cannot read the image.
    private static let instructions = """
        Tu transcris fidèlement les formules visibles dans une image, pour une calculatrice, sans \
        rien inventer ni compléter. Chaque ligne écrite dans l’image donne une seule ligne de ta \
        réponse, entière, de haut en bas. Écris les exposants avec ^, les fractions avec / et des \
        parenthèses, la racine carrée avec sqrt(…), les décimaux avec une virgule. Ne calcule rien \
        et ne résous rien. Si l’image ne contient aucune formule, renvoie une liste vide.
        """
    #endif
}

#if canImport(FoundationModels)
@available(iOS 27, *)
@Generable(description: "Les lignes d’une feuille de calcul recopiées depuis une image")
private struct RecognizedSheet {
    @Guide(description: "Une ligne par ligne de l’image, de haut en bas", .maximumCount(60))
    var lines: [String]
}
#endif
