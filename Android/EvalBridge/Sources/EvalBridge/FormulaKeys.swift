import EvalCore
import Foundation

/// A text with its caret, as positions in UTF-16 units, those of Kotlin strings.
public struct TextEdit: Hashable, Sendable {
    public let text: String
    public let caret: Int
}

/// The keys of the bar above the keyboard in text input (iOS `FormulaKeys`).
public final class FormulaKeys {
    /// Inserts a snippet at the caret or over the selection, adding only the spaces
    /// the syntax needs (`FormulaInsertion`). `kind` is `operator`, `literal`,
    /// `parentheses`, `function`, `name`, `unit`, `fraction` or `power`; `value` is
    /// the operator, text, function, name or unit. Pure: any thread.
    public static func insert(kind: String, value: String, into text: String,
                              selectionStart: Int, selectionEnd: Int) -> TextEdit {
        let snippet: FormulaInsertion.Snippet = switch kind {
        case "operator": .operator(value)
        case "parentheses": .parentheses
        case "function": .function(value)
        case "name": .name(value)
        case "unit": .unit(value)
        case "fraction": .fraction
        case "power": .power
        default: .literal(value)
        }
        let start = text.index(utf16Offset: selectionStart)
        let end = text.index(utf16Offset: max(selectionStart, selectionEnd))
        let result = FormulaInsertion.insert(snippet, into: text, replacing: start..<end)
        return TextEdit(text: result.text, caret: result.caret.utf16Offset(in: result.text))
    }
}

private extension String {
    /// The index at a UTF-16 offset, clamped to the text and moved back to a character boundary.
    func index(utf16Offset offset: Int) -> String.Index {
        let position = utf16.index(utf16.startIndex, offsetBy: min(max(0, offset), utf16.count))
        return position.samePosition(in: self) ?? rangeOfComposedCharacterSequence(at: position).lowerBound
    }
}
