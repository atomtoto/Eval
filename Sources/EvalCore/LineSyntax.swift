import Foundation

/// The parts of one sheet line: `body -> conversion # comment`.
/// A comment starts at the first `#` or `//`. Before it, the first `->` or `→`
/// introduces a display conversion: the engine evaluates the body and shows its
/// result in the unit after the arrow. All ranges are indexes into `source`.
public struct LineSyntax: Sendable, Equatable {
    public let source: String
    /// Text before the comment, spacing included.
    public let contentRange: Range<String.Index>
    /// Content before the conversion arrow, spacing included.
    public let bodyRange: Range<String.Index>
    /// The first arrow outside the comment.
    public let arrowRange: Range<String.Index>?
    /// Trimmed text after the first arrow; empty right after the arrow when no unit follows.
    public let conversionRange: Range<String.Index>?
    /// Arrows outside the comment. A meaningful line has at most one.
    public let arrowCount: Int
    /// The comment with its marker.
    public let commentRange: Range<String.Index>?
    /// The first `=` or `==` of the body.
    public let separatorRange: Range<String.Index>?
    /// Every `=` or `==` of the body. The engine accepts at most one.
    public let separatorCount: Int
    /// The declared name when the first separator is a single `=` after an identifier.
    public let definitionName: String?
    /// For `name = ? unit`, the text after the question mark (empty without a unit).
    /// The engine then solves for `name`; every other line has none.
    public let unknownUnit: String?

    public init(_ source: String) {
        self.source = source
        var contentEnd = source.endIndex
        if let marker = source.firstIndex(of: "#") { contentEnd = marker }
        if let marker = source.range(of: "//")?.lowerBound { contentEnd = min(contentEnd, marker) }
        contentRange = source.startIndex..<contentEnd
        commentRange = contentEnd < source.endIndex ? contentEnd..<source.endIndex : nil

        let arrows = Self.arrows(in: source[contentRange])
        arrowRange = arrows.first
        arrowCount = arrows.count
        let bodyEnd = arrows.first?.lowerBound ?? contentEnd
        bodyRange = source.startIndex..<bodyEnd
        conversionRange = arrows.first.map { arrow in
            let target = source[arrow.upperBound..<contentEnd]
            guard let start = target.firstIndex(where: { !$0.isWhitespace }),
                  let last = target.lastIndex(where: { !$0.isWhitespace }) else {
                return arrow.upperBound..<arrow.upperBound
            }
            return start..<source.index(after: last)
        }

        let separators = Self.separators(in: source[bodyRange])
        separatorRange = separators.first
        separatorCount = separators.count
        if let separator = separators.first, source[separator] == "=" {
            let name = source[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            definitionName = ExpressionParser.isIdentifier(name) ? name : nil
        } else {
            definitionName = nil
        }
        if definitionName != nil, separators.count == 1, let separator = separators.first {
            let value = source[separator.upperBound..<bodyEnd].trimmingCharacters(in: .whitespacesAndNewlines)
            unknownUnit = value.hasPrefix("?") ? String(value.dropFirst()).trimmingCharacters(in: .whitespaces) : nil
        } else {
            unknownUnit = nil
        }
    }

    /// True when the line itself asks for its value: it names a unit to show it in
    /// (`→ km/h`) or an unknown to solve (`v = ? m/s`). Such a line shows its value
    /// by default, even when it is a declaration.
    public var requestsValue: Bool { arrowRange != nil || unknownUnit != nil }

    public var content: String { String(source[contentRange]) }
    public var body: String { String(source[bodyRange]) }
    public var conversion: String? { conversionRange.map { String(source[$0]) } }
    public var comment: String? { commentRange.map { String(source[$0]) } }
    /// `==` asks for a comparison; a single `=` declares or states an equality.
    public var isComparison: Bool { separatorRange.map { source[$0] == "==" } ?? false }

    /// Adds, replaces or removes (`nil` or blank) the display conversion, keeping
    /// the body, the spacing and the comment verbatim. A blank body gains none.
    public func replacingConversion(_ symbol: String?) -> String {
        let symbol = symbol?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let bodyEnd = trimmedBody?.upperBound ?? bodyRange.lowerBound
        guard let arrowRange, let conversionRange else {
            guard !symbol.isEmpty, trimmedBody != nil else { return source }
            return Self.joined(String(source[..<bodyEnd]) + " → " + symbol, source[bodyEnd...])
        }
        if symbol.isEmpty {
            let body = String(source[..<bodyEnd]), rest = source[conversionRange.upperBound...]
            // A body ending in "/" must not fuse with a "//" comment into "///".
            return body.hasSuffix("/") && rest.first == "/" ? body + " " + rest : body + rest
        }
        if conversionRange.isEmpty {
            return Self.joined(String(source[..<arrowRange.upperBound]) + " " + symbol, source[arrowRange.upperBound...])
        }
        return String(source[..<conversionRange.lowerBound]) + symbol + source[conversionRange.upperBound...]
    }

    /// Replaces the body's text, keeping its surrounding spacing, the conversion
    /// and the comment verbatim. Editors use it to change only the formula.
    public func replacingBody(_ body: String) -> String {
        let body = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let trimmedBody else { return Self.joined(body, source[bodyRange.upperBound...]) }
        return String(source[..<trimmedBody.lowerBound]) + body + source[trimmedBody.upperBound...]
    }

    private var trimmedBody: Range<String.Index>? {
        let body = source[bodyRange]
        guard let first = body.firstIndex(where: { !$0.isWhitespace }),
              let last = body.lastIndex(where: { !$0.isWhitespace }) else { return nil }
        return first..<source.index(after: last)
    }

    /// Keeps at least one space before a following conversion or comment.
    private static func joined(_ text: String, _ rest: Substring) -> String {
        guard let next = rest.first, !next.isWhitespace, !text.isEmpty else { return text + rest }
        return text + " " + rest
    }

    private static func arrows(in text: Substring) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            let next = text.index(after: index)
            if text[index] == "→" {
                result.append(index..<next)
            } else if text[index] == "-", next < text.endIndex, text[next] == ">" {
                result.append(index..<text.index(after: next))
                index = text.index(after: next)
                continue
            }
            index = next
        }
        return result
    }

    /// `=` and `==` in reading order; `===` counts as `==` followed by `=`.
    static func separators(in text: Substring) -> [Range<String.Index>] {
        var result: [Range<String.Index>] = []
        var index = text.startIndex
        while index < text.endIndex {
            var next = text.index(after: index)
            if text[index] == "=" {
                if next < text.endIndex, text[next] == "=" { next = text.index(after: next) }
                result.append(index..<next)
            }
            index = next
        }
        return result
    }
}
