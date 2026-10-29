import EvalCore
import Foundation

/// Settings shared by every sheet. Any thread.
public final class EvalSettings {
    /// The significant digits of the values shown, 6 by default, clamped to 3…12.
    /// Values are formatted when read: read the lines again after a change.
    public static var significantDigits: Int {
        get { QuantityFormatter.significantDigits }
        set { QuantityFormatter.significantDigits = newValue }
    }

    public static let defaultSignificantDigits: Int = QuantityFormatter.defaultDigits
    public static let minimumSignificantDigits: Int = QuantityFormatter.minimumDigits
    public static let maximumSignificantDigits: Int = QuantityFormatter.maximumDigits

    private init() {}
}

/// Numbers written and read as the iOS app does, with a decimal comma. Any thread.
public final class NumberText {
    private init() {}

    /// A value and its unit: with the significant digits of the settings, as on a
    /// plot (`°` attached), or with ten digits, as above a ruler.
    public static func format(_ value: Double, unit: String, precise: Bool) -> String {
        let number = QuantityFormatter.number(value, significantDigits: precise ? QuantityFormatter.preciseDigits
                                                                                : QuantityFormatter.significantDigits)
        guard !unit.isEmpty else { return number }
        return number + (!precise && unit == "°" ? "" : " ") + unit
    }

    /// The same in words, with the unit named: « 81 kilogrammes ».
    public static func spoken(_ value: Double, unit: String, precise: Bool) -> String {
        let fallback = format(value, unit: unit, precise: precise)
        guard value.isFinite else { return fallback }
        return MathSpeech.description(unit.isEmpty ? String(value) : "\(value) \(unit)") ?? fallback
    }

    /// A number typed in a settings field: a comma or a point, and `−` for minus.
    public static func parse(_ text: String) -> Double? {
        Double(text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-"))
    }

    /// A plain decimal number to edit, without grouping or exponent: « 0,05 ».
    public static func editable(_ value: Double) -> String {
        let text = String(format: "%.15g", value)
        let plain = text.contains("e") ? Decimal(string: text).map { "\($0)" } ?? text : text
        return plain.replacingOccurrences(of: ".", with: ",")
    }
}

/// Inserts symbols, names and units into a line being typed, adding only the
/// spaces the syntax needs, as the keyboard bar of iOS. Any thread.
public final class FormulaInserter {
    private init() {}

    /// `kind` is `operator`, `literal`, `function`, `name` or `unit`, each with its
    /// text in `argument` (`+`, `²`, `sqrt`, `π`, `km/h`), or `parentheses`,
    /// `fraction` or `power`, which ignore it. The selection, in UTF-16 offsets as
    /// in a Compose `TextFieldValue`, is replaced. Nil for an unknown kind.
    public static func insert(kind: String, argument: String = "", text: String, selectionStart: Int,
                              selectionEnd: Int) -> TextInsertion? {
        let snippet: FormulaInsertion.Snippet
        switch kind {
        case "operator": snippet = .operator(argument)
        case "literal": snippet = .literal(argument)
        case "function": snippet = .function(argument)
        case "name": snippet = .name(argument)
        case "unit": snippet = .unit(argument)
        case "parentheses": snippet = .parentheses
        case "fraction": snippet = .fraction
        case "power": snippet = .power
        default: return nil
        }
        let lower = index(text, utf16Offset: min(selectionStart, selectionEnd))
        let upper = index(text, utf16Offset: max(selectionStart, selectionEnd))
        let result = FormulaInsertion.insert(snippet, into: text, replacing: lower..<upper)
        return TextInsertion(text: result.text, caret: result.caret.utf16Offset(in: result.text))
    }

    /// The character boundary at or before an offset, clamped to the text.
    private static func index(_ text: String, utf16Offset offset: Int) -> String.Index {
        var found = text.startIndex
        for index in text.indices {
            guard index.utf16Offset(in: text) <= offset else { return found }
            found = index
        }
        return offset >= text.utf16.count ? text.endIndex : found
    }
}

/// A line after an insertion, with the caret as a UTF-16 offset.
public struct TextInsertion: Hashable, Sendable {
    public let text: String
    public let caret: Int
}
