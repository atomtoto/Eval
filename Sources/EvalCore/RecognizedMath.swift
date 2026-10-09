import Foundation

/// Turns text read in a photo or a drawing into lines of a sheet. A text
/// recognizer reads characters, not mathematics: exponents and fraction bars
/// are found from where the characters lie, and symbols are spelled as the
/// sheet expects.
public enum RecognizedMath {
    /// A rectangle in the image, normalized to 0…1, with y growing downward.
    public struct Box: Sendable, Equatable {
        public var x, y, width, height: Double

        public init(x: Double, y: Double, width: Double, height: Double) {
            self.x = x
            self.y = y
            self.width = width
            self.height = height
        }

        var maxX: Double { x + width }
        var maxY: Double { y + height }
        var midY: Double { y + height / 2 }

        func union(_ other: Box) -> Box {
            let (left, top) = (min(x, other.x), min(y, other.y))
            return Box(x: left, y: top, width: max(maxX, other.maxX) - left, height: max(maxY, other.maxY) - top)
        }

        /// The share of the narrower box that lies within the other one horizontally.
        func horizontalOverlap(with other: Box) -> Double {
            let overlap = min(maxX, other.maxX) - max(x, other.x)
            return max(0, overlap) / max(min(width, other.width), 1e-9)
        }
    }

    /// A run of text as the recognizer found it.
    public struct Fragment: Sendable, Equatable {
        public var text: String
        public var box: Box
        /// The box of each character of `text`, when known, to find exponents.
        public var characterBoxes: [Box]?

        public init(text: String, box: Box, characterBoxes: [Box]? = nil) {
            self.text = text
            self.box = box
            self.characterBoxes = characterBoxes
        }
    }

    /// The lines of the sheet, top to bottom: raised digits become exponents, a bar
    /// with text above and below becomes a fraction, and fragments side by side
    /// join into one line.
    public static func lines(from fragments: [Fragment]) -> [String] {
        var pieces = fragments.map { fragment in
            Fragment(text: withExponents(fragment), box: fragment.box)
        }.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        pieces = joiningFractions(pieces)
        return rows(of: pieces).map { row in
            normalized(row.sorted { $0.box.x < $1.box.x }.map(\.text).joined(separator: " "))
        }.filter { !$0.isEmpty }
    }

    /// One line spelled for the sheet: true operators and exponents kept, look-alike
    /// dashes, LaTeX commands and code fences removed.
    public static func normalized(_ line: String) -> String {
        var text = line.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") || text.hasSuffix("```") { text = text.replacingOccurrences(of: "```", with: "") }
        text = text.replacingOccurrences(of: "$", with: "")
        text = latexFree(text)
        let replacements: [(String, String)] = [
            ("−", "-"), ("–", "-"), ("—", "-"), ("**", "^"), ("⋅", "·"), ("∗", "*"),
            ("≡", "=="), ("：", ":"), ("‘", "’"), ("√ ", "√")
        ]
        for (from, to) in replacements { text = text.replacingOccurrences(of: from, with: to) }
        text = digitLookAlikes(text)
        // A trailing period ends a sentence, not a number.
        if text.hasSuffix("."), text.dropLast().last?.isNumber == false { text.removeLast() }
        return text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    /// Lines that a reader cut in the middle of a formula, joined again: a line that
    /// ends with an operator, or a line that starts with one, continues its
    /// neighbour (`2x =` then `4` give `2x = 4`). A join never makes two equalities.
    public static func joiningBrokenLines(_ lines: [String]) -> [String] {
        var result: [String] = []
        for line in lines.map({ $0.trimmingCharacters(in: .whitespaces) }) where !line.isEmpty {
            if let previous = result.last, !previous.hasPrefix("#"), !line.hasPrefix("#"),
               let end = previous.last, let start = line.first,
               "+-−*×·/÷^=(".contains(end) || "+-−*×·/÷^=)".contains(start) {
                let joined = previous + " " + line
                if LineSyntax.separators(in: joined[...]).count <= 1 {
                    result[result.count - 1] = joined
                    continue
                }
            }
            result.append(line)
        }
        return result
    }

    /// Lines where a number followed by a space and a declared name multiplies them:
    /// in the sheet, `0,5 m` would be half a metre, but written by hand beside
    /// `m = 80 kg` it is half the mass. `declared` holds the sheet's names; the
    /// lines' own declarations are added.
    public static func clarifyingProducts(_ lines: [String], declared: Set<String>) -> [String] {
        let names = declared.union(lines.compactMap { LineSyntax($0).definitionName })
        guard !names.isEmpty else { return lines }
        return lines.map { line in
            line.replacing(/(\d)[ \t]+([\p{L}_][\p{L}\p{N}_]*)/) { match in
                names.contains(String(match.2)) ? match.1 + " * " + match.2 : String(match.0)
            }
        }
    }

    /// How much two readings of one image agree, from 0 to 1: the share of letters
    /// and digits they have in common. A reading that invents its formulas shares
    /// almost none with another.
    public static func agreement(_ first: [String], _ second: [String]) -> Double {
        func signature(_ lines: [String]) -> [Character: Int] {
            var counts: [Character: Int] = [:]
            for line in lines where !line.hasPrefix("#") {
                for character in line {
                    let plain = superscripts.first { $0.value == character }?.key ?? character
                    guard plain.isLetter || plain.isNumber else { continue }
                    counts[Character(plain.lowercased()), default: 0] += 1
                }
            }
            return counts
        }
        let (a, b) = (signature(first), signature(second))
        let total = a.values.reduce(0, +) + b.values.reduce(0, +)
        guard total > 0 else { return 1 }
        let shared = a.reduce(0) { $0 + min($1.value, b[$1.key] ?? 0) }
        return 2 * Double(shared) / Double(total)
    }

    // MARK: Exponents

    private static let superscripts: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"
    ]

    /// Digits written smaller and higher than the character before them are an
    /// exponent: x2 with a raised 2 is x².
    static func withExponents(_ fragment: Fragment) -> String {
        let characters = Array(fragment.text)
        guard let boxes = fragment.characterBoxes, boxes.count == characters.count else { return fragment.text }
        var result = ""
        // The last full-size character that can carry an exponent; raised digits keep it.
        var base: Box?
        for (index, character) in characters.enumerated() {
            let box = boxes[index]
            if let reference = base, let raised = superscripts[character],
               box.maxY < reference.midY + reference.height * 0.1, box.height < reference.height * 0.8,
               character != "-" || (index + 1 < characters.count && characters[index + 1].isNumber) {
                result.append(raised)
                continue
            }
            result.append(character)
            if character.isLetter || character.isNumber || character == ")" {
                base = box
            } else if !character.isWhitespace {
                base = nil
            }
        }
        return result
    }

    // MARK: Fractions

    /// A fragment of dashes only, wider than tall, is a fraction bar.
    private static func isBar(_ fragment: Fragment) -> Bool {
        let text = fragment.text.trimmingCharacters(in: .whitespaces)
        return !text.isEmpty && text.allSatisfy { "-_—–−‒―".contains($0) } && fragment.box.width > fragment.box.height * 2
    }

    /// Bars with a fragment just above and one just below become `(a)/(b)`, placed
    /// on the bar's line so that `E =` written beside the bar joins it. Other bars go.
    private static func joiningFractions(_ fragments: [Fragment]) -> [Fragment] {
        var remaining = fragments
        let bars = remaining.indices.filter { isBar(remaining[$0]) }.sorted { remaining[$0].box.width < remaining[$1].box.width }
        var used = Set<Int>()
        var joined: [Fragment] = []
        for bar in bars where !used.contains(bar) {
            let line = remaining[bar].box
            func nearest(above: Bool) -> Int? {
                remaining.indices.filter { index in
                    guard index != bar, !used.contains(index), !isBar(remaining[index]) else { return false }
                    let box = remaining[index].box
                    let gap = above ? line.y - box.maxY : box.y - line.maxY
                    return box.horizontalOverlap(with: line) > 0.5 && gap > -box.height * 0.3 && gap < box.height * 1.2
                }.min { abs(remaining[$0].box.midY - line.midY) < abs(remaining[$1].box.midY - line.midY) }
            }
            guard let top = nearest(above: true), let bottom = nearest(above: false) else { continue }
            used.formUnion([bar, top, bottom])
            let numerator = remaining[top].text.trimmingCharacters(in: .whitespaces)
            let denominator = remaining[bottom].text.trimmingCharacters(in: .whitespaces)
            let text = parenthesized(numerator) + "/" + parenthesized(denominator)
            let box = Box(x: line.x, y: line.y - line.height, width: line.width, height: line.height * 3)
            joined.append(Fragment(text: text, box: box))
        }
        // A bar without text above and below is a minus already read, or a stray line.
        remaining = remaining.indices.filter { !used.contains($0) && !isBar(remaining[$0]) }.map { remaining[$0] }
        return remaining + joined
    }

    /// A numerator or denominator keeps its unity: a + b over c is (a + b)/c.
    private static func parenthesized(_ text: String) -> String {
        let operand = text.hasPrefix("√") ? String(text.dropFirst()) : text
        return ExpressionParser.isSingleOperand(operand) ? text : "(\(text))"
    }

    // MARK: Lines

    /// Fragments whose heights overlap by half form one line, top to bottom.
    private static func rows(of fragments: [Fragment]) -> [[Fragment]] {
        var rows: [(box: Box, members: [Fragment])] = []
        for fragment in fragments.sorted(by: { $0.box.midY < $1.box.midY }) {
            if let index = rows.indices.last(where: { overlapsVertically(rows[$0].box, fragment.box) }) {
                rows[index].members.append(fragment)
                rows[index].box = rows[index].box.union(fragment.box)
            } else {
                rows.append((fragment.box, [fragment]))
            }
        }
        return rows.sorted { $0.box.midY < $1.box.midY }.map(\.members)
    }

    private static func overlapsVertically(_ a: Box, _ b: Box) -> Bool {
        let overlap = min(a.maxY, b.maxY) - max(a.y, b.y)
        return overlap > 0.5 * min(a.height, b.height)
    }

    // MARK: Spelling

    /// \frac{a}{b}, \sqrt{x}, x^{2}, \cdot, \times, \pi… as the sheet writes them.
    private static func latexFree(_ text: String) -> String {
        guard text.contains("\\") || text.contains("{") else { return text }
        var result = text
        let commands: [(String, String)] = [
            ("\\cdot", "*"), ("\\times", "×"), ("\\div", "÷"), ("\\pi", "π"), ("\\left", ""), ("\\right", ""),
            ("\\,", " "), ("\\;", " "), ("\\!", ""), ("\\theta", "θ"), ("\\alpha", "α"), ("\\beta", "β"),
            ("\\lambda", "λ"), ("\\omega", "ω"), ("\\mu", "μ"), ("\\Delta", "Δ"), ("\\rho", "ρ"), ("\\sigma", "σ"),
            ("\\varepsilon", "ε"), ("\\epsilon", "ε"), ("\\hbar", "ℏ"), ("\\sin", "sin"), ("\\cos", "cos"),
            ("\\tan", "tan"), ("\\ln", "ln"), ("\\log", "log"), ("\\exp", "exp"), ("\\approx", "="), ("\\to", "→")
        ]
        for (command, replacement) in commands { result = result.replacingOccurrences(of: command, with: replacement) }
        // Innermost groups first, so nested fractions resolve from the inside.
        for _ in 0..<8 {
            let before = result
            result = result.replacing(/\\[dt]?frac\{([^{}]*)\}\{([^{}]*)\}/) { match in
                parenthesized(String(match.1)) + "/" + parenthesized(String(match.2))
            }
            result = result.replacing(/\\sqrt\[([^{}\]]*)\]\{([^{}]*)\}/) { match in "root(\(match.2); \(match.1))" }
            result = result.replacing(/\\sqrt\{([^{}]*)\}/) { match in "√" + parenthesized(String(match.1)) }
            result = result.replacing(/\^\{([^{}]*)\}/) { match in "^" + parenthesized(String(match.1)) }
            result = result.replacing(/_\{([^{}]*)\}/) { match in "_" + match.1 }
            if result == before { break }
        }
        result = result.replacingOccurrences(of: "\\", with: "")
        result = result.replacingOccurrences(of: "{", with: "(").replacingOccurrences(of: "}", with: ")")
        // In LaTeX, \frac{1}{2} m v^2 is a product: in the sheet, a space between a
        // number and a name would make the name a unit.
        return result.replacing(/([\d)])\s+(?=[\p{L}√(])/) { match in match.1 + " * " }
    }

    /// O between digits is a zero: 1O5 is 105.
    private static func digitLookAlikes(_ text: String) -> String {
        var characters = Array(text)
        for index in characters.indices.dropFirst().dropLast()
        where "Oo".contains(characters[index]) && characters[index - 1].isNumber && characters[index + 1].isNumber {
            characters[index] = "0"
        }
        return String(characters)
    }
}
