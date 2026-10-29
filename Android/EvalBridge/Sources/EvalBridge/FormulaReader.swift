import EvalCore
import Foundation

/// A run of text found in a photo by the text recognizer, with its box and, when
/// known, the box of each character: four numbers per character, `x`, `y`, `width`
/// and `height`. Boxes are normalized to 0…1, with `y` growing downward.
public struct TextFragment: Hashable, Sendable {
    public let text: String
    public let x: Double
    public let y: Double
    public let width: Double
    public let height: Double
    public let characterBoxes: [Double]

    public init(text: String, x: Double, y: Double, width: Double, height: Double, characterBoxes: [Double] = []) {
        self.text = text
        self.x = x
        self.y = y
        self.width = width
        self.height = height
        self.characterBoxes = characterBoxes
    }
}

/// The lines of a sheet read in a photo of formulas (iOS FormulaRecognizer and
/// FormulaScannerView): raised digits become exponents, bars with text above and
/// below become fractions, and the symbols are spelled as the sheet expects.
public final class FormulaReader {
    private init() {}

    /// The lines to add to a sheet whose declared names are `declared`, top to bottom.
    /// Pure: any thread.
    public static func lines(fragments: [TextFragment], declared: [String]) -> [String] {
        let read = RecognizedMath.lines(from: fragments.map { fragment in
            let boxes = stride(from: 0, to: fragment.characterBoxes.count - 3, by: 4).map {
                RecognizedMath.Box(x: fragment.characterBoxes[$0], y: fragment.characterBoxes[$0 + 1],
                                   width: fragment.characterBoxes[$0 + 2], height: fragment.characterBoxes[$0 + 3])
            }
            return RecognizedMath.Fragment(
                text: fragment.text,
                box: RecognizedMath.Box(x: fragment.x, y: fragment.y, width: fragment.width, height: fragment.height),
                characterBoxes: boxes.count == fragment.text.count ? boxes : nil)
        })
        let names = Set(declared)
        return RecognizedMath.clarifyingProducts(RecognizedMath.harmonizingCase(read, declared: names), declared: names)
    }
}
