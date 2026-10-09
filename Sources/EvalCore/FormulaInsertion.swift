import Foundation

/// Inserts symbols, names and units into formula text at the caret or over a
/// selection, adding only the spaces that the syntax needs. The text is a
/// single formula or a whole sheet; the helper never looks beyond the
/// characters next to the insertion point.
public enum FormulaInsertion {
    public enum Snippet: Sendable, Equatable {
        /// A binary operator, separated from its neighbours by spaces.
        case `operator`(String)
        /// Text inserted exactly as given, such as `^` or `²`.
        case literal(String)
        /// `( )`. A selection is wrapped, otherwise the caret ends up inside.
        case parentheses
        /// `name( )`, such as `sqrt`. A selection becomes the argument.
        case function(String)
        /// A variable, constant or symbol such as `π`. It never fuses with a
        /// neighbouring name or number.
        case name(String)
        /// A unit symbol, written after a number: `5 m/s`.
        case unit(String)
        /// A fraction template. A selection becomes the numerator and the caret
        /// waits in the denominator: `(a + b)/(|)`; otherwise `(|)/()`.
        case fraction
        /// An exponent template: a selection becomes the base, `(a + b)^(|)`;
        /// otherwise the exponent applies to what precedes the caret, `v^(|)`.
        case power
    }

    public struct Result: Sendable, Equatable {
        public var text: String
        /// The caret in `text`, after the inserted snippet.
        public var caret: String.Index
    }

    /// Replaces `range` with the snippet. The range is clamped to the text.
    public static func insert(_ snippet: Snippet, into text: String, replacing range: Range<String.Index>) -> Result {
        let lower = max(text.startIndex, min(range.lowerBound, text.endIndex))
        let upper = max(lower, min(range.upperBound, text.endIndex))
        let before = text[..<lower]
        let selected = String(text[lower..<upper])
        let after = text[upper...]

        var lead = ""
        var core: String
        var trail = ""
        var caretInCore: Int?
        var skipsFollowingSpace = false

        switch snippet {
        case .literal(let literal):
            core = literal
        case .operator(let symbol):
            core = symbol
            if let last = before.last, !last.isWhitespace, last != "(" { lead = " " }
            if after.first == " " {
                skipsFollowingSpace = true
            } else if after.first?.isNewline != true {
                trail = " "
            }
        case .parentheses:
            core = "(" + selected + ")"
            if selected.isEmpty { caretInCore = 1 }
        case .function(let name):
            core = name + "(" + selected + ")"
            if selected.isEmpty { caretInCore = name.count + 1 }
        case .name(let name):
            core = name
            if let last = before.last, joinsNames(last) || last == ")" { lead = " * " }
            if let first = after.first, joinsNames(first) { trail = " " }
        case .unit(let symbol):
            core = symbol
            if let last = before.last, joinsNames(last) || last == ")" { lead = " " }
            if let first = after.first, joinsNames(first) { trail = " " }
        case .fraction:
            if selected.trimmingCharacters(in: .whitespaces).isEmpty {
                core = "()/()"
                caretInCore = 1
                if let last = before.last, joinsNames(last) || last == ")" { lead = " * " }
            } else {
                core = operand(selected) + "/()"
                caretInCore = core.count - 1
            }
            if let first = after.first, joinsNames(first) || first == "(" { trail = " " }
        case .power:
            core = (selected.trimmingCharacters(in: .whitespaces).isEmpty ? "" : operand(selected)) + "^()"
            caretInCore = core.count - 1
            if let first = after.first, joinsNames(first) || first == "(" { trail = " " }
        }

        let prefixCount = before.count + lead.count
        let caretOffset = prefixCount + (caretInCore ?? core.count + trail.count) + (skipsFollowingSpace ? 1 : 0)
        let result = String(before) + lead + core + trail + String(after)
        let caret = result.index(result.startIndex, offsetBy: min(caretOffset, result.count))
        return Result(text: result, caret: caret)
    }

    /// The selection as one operand: a name, a number or a parenthesised group stays
    /// as it is, anything else is wrapped in parentheses.
    private static func operand(_ text: String) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.allSatisfy(joinsNames) || isWrapped(trimmed) { return trimmed }
        return "(" + trimmed + ")"
    }

    /// Whether the outer parentheses of `text` enclose all of it, as in `(a + b)`
    /// but not `(a) + (b)`.
    private static func isWrapped(_ text: String) -> Bool {
        guard text.first == "(", text.last == ")" else { return false }
        var depth = 0
        for (offset, character) in text.enumerated() {
            if character == "(" { depth += 1 }
            if character == ")" {
                depth -= 1
                if depth == 0 { return offset == text.count - 1 }
            }
        }
        return false
    }

    /// Letters, digits, underscores and decimal points continue a name or number.
    private static func joinsNames(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_" || character == "."
    }
}
