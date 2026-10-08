import Foundation

/// Mathematical layout, independent of the view used to draw it.
/// Atoms include symbols and spacing; structured nodes keep fractions and
/// exponents unambiguous without altering the calculation syntax.
public indirect enum MathFormula: Sendable, Equatable {
    case atom(String)
    case row([MathFormula])
    case fraction(MathFormula, MathFormula)
    case power(MathFormula, MathFormula)
    case radical(MathFormula)
    /// A radical with its index tucked at the upper left, as in ∛x.
    case root(index: MathFormula, radicand: MathFormula)
    case parentheses(MathFormula)
}

public enum MathNotation {
    /// Formats a single notebook line using the calculator's existing parser.
    /// Invalid or incomplete input has no mathematical preview, so the editor
    /// can keep showing the original source and its diagnostic instead.
    public static func formula(_ source: String) -> MathFormula? {
        guard source.count <= 2_000, !source.contains(where: \.isNewline) else { return nil }
        let line = LineSyntax(source)
        guard line.arrowCount <= 1 else { return nil }
        let body = line.body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }

        do {
            var result: MathFormula
            if let separator = line.separatorRange {
                // A single '=' and '==' both display as a mathematical equality.
                guard line.separatorCount == 1 else { return nil }
                let leftSource = source[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
                let rightSource = source[separator.upperBound..<line.bodyRange.upperBound]
                    .trimmingCharacters(in: .whitespaces)
                guard !leftSource.isEmpty, !rightSource.isEmpty else { return nil }
                // A declaration's name is not parsed as an expression: the
                // engine also accepts names that coincide with function names.
                let left = try line.definitionName.map { MathFormula.atom(symbol($0)) } ?? parse(leftSource)
                if let unit = line.unknownUnit {
                    // The unknown is drawn as a question mark, followed by its unit.
                    result = row([left, .atom(" = "), .atom("?")] + (unit.isEmpty ? [] : [.atom(" "), try parse(unit)]))
                } else {
                    result = row([left, .atom(" = "), try parse(rightSource)])
                }
            } else {
                result = try parse(body)
            }
            if line.arrowRange != nil {
                guard let target = line.conversion, !target.isEmpty else { return nil }
                result = row([result, .atom(" → "), try parse(target)])
            }
            return result
        } catch {
            return nil
        }
    }

    private static func parse(_ source: String) throws -> MathFormula {
        var parser = try ExpressionParser(source)
        let expression = try parser.parse()
        var renderer = Renderer(numberSpellings: numberSpellings(in: source))
        return try renderer.render(expression)
    }

    private enum RenderingError: Error { case tooDeep }

    private struct Renderer {
        let numberSpellings: [String]
        private var numberIndex = 0

        init(numberSpellings: [String]) {
            self.numberSpellings = numberSpellings
        }

        mutating func render(_ expression: Expression, depth: Int = 0) throws -> MathFormula {
            // Long sums can form a deep tree even though the parser bounds
            // parenthesis nesting. Bound the visual conversion independently.
            guard depth <= 200 else { throw RenderingError.tooDeep }
            switch expression {
            case .number(let value):
                let spelling = numberIndex < numberSpellings.count ? numberSpellings[numberIndex] : nil
                numberIndex += 1
                return number(value, spelling: spelling)
            case .identifier(let name):
                return .atom(symbol(name))
            case .unit(let unit):
                return .atom(unit)
            case .compactUnits(let units):
                return try render(units, depth: depth + 1)
            case .unary(let operation, let argument):
                let child = try render(argument, depth: depth + 1)
                let grouped: MathFormula
                switch argument {
                case .binary(.add, _, _), .binary(.subtract, _, _), .unary:
                    grouped = .parentheses(child)
                default:
                    grouped = child
                }
                return row([.atom(operation == .minus ? "−" : "+"), grouped])
            case .function(let name, let arguments):
                var children: [MathFormula] = []
                for argument in arguments { children.append(try render(argument, depth: depth + 1)) }
                return function(name, children)
            case .factorial(let argument):
                let child = try render(argument, depth: depth + 1)
                switch argument {
                case .binary, .unary:
                    return row([.parentheses(child), .atom("!")])
                case .number where isRow(child):
                    return row([.parentheses(child), .atom("!")])
                default:
                    return row([child, .atom("!")])
                }
            case .binary(let operation, let left, let right):
                let lhs = try render(left, depth: depth + 1)
                let rhs = try render(right, depth: depth + 1)
                switch operation {
                case .add:
                    return row([lhs, .atom(" + "), grouped(right, formula: rhs)])
                case .subtract:
                    return row([lhs, .atom(" − "), grouped(right, formula: rhs)])
                case .multiply:
                    let separator = left.isNumericExpression && isUnitExpression(right) ? " " : " · "
                    return row([groupedSum(left, formula: lhs), .atom(separator), grouped(right, formula: rhs)])
                case .divide:
                    // A fraction bar already groups its whole numerator and
                    // denominator, including sums and nested fractions.
                    return .fraction(lhs, rhs)
                case .power:
                    let base: MathFormula
                    switch left {
                    case .number(let value) where value < 0:
                        base = .parentheses(lhs)
                    case .number where isRow(lhs):
                        // A scientific literal draws as a product, so it
                        // needs grouping when the whole number is powered.
                        base = .parentheses(lhs)
                    case .unary, .binary:
                        base = .parentheses(lhs)
                    default:
                        base = lhs
                    }
                    return .power(base, rhs)
                }
            }
        }
    }

    /// Roots keep their index at the upper left of the radical. Other functions list their
    /// arguments separated by « ; », as they are typed.
    private static func function(_ name: String, _ arguments: [MathFormula]) -> MathFormula {
        switch name {
        case "sqrt": return .radical(arguments[0])
        case "abs": return row([.atom("|"), arguments[0], .atom("|")])
        case "cbrt": return .root(index: .atom("3"), radicand: arguments[0])
        case "root": return .root(index: arguments[1], radicand: arguments[0])
        default:
            let display = ["log10": "log₁₀", "asin": "arcsin", "acos": "arccos", "atan": "arctan"][name] ?? name
            var list: [MathFormula] = []
            for (index, argument) in arguments.enumerated() {
                if index > 0 { list.append(.atom(" ; ")) }
                list.append(argument)
            }
            return row([.atom(display), .parentheses(row(list))])
        }
    }

    private static func groupedSum(_ expression: Expression, formula: MathFormula) -> MathFormula {
        switch expression {
        case .binary(.add, _, _), .binary(.subtract, _, _): return .parentheses(formula)
        default: return formula
        }
    }

    /// A right operand also keeps its sign apart: a − (−b), not a − −b.
    private static func grouped(_ expression: Expression, formula: MathFormula) -> MathFormula {
        if case .unary = expression { return .parentheses(formula) }
        return groupedSum(expression, formula: formula)
    }

    static func isUnitExpression(_ expression: Expression) -> Bool {
        switch expression {
        case .unit: return true
        case .compactUnits(let units): return isUnitExpression(units)
        case .binary(.multiply, let left, let right), .binary(.divide, let left, let right):
            return isUnitExpression(left) && isUnitExpression(right)
        case .binary(.power, let base, let exponent):
            return isUnitExpression(base) && exponent.isNumericExpression
        default: return false
        }
    }

    private static func row(_ formulas: [MathFormula]) -> MathFormula {
        let flattened = formulas.flatMap { formula -> [MathFormula] in
            if case .row(let children) = formula { return children }
            return [formula]
        }
        return flattened.count == 1 ? flattened[0] : .row(flattened)
    }

    private static func isRow(_ formula: MathFormula) -> Bool {
        if case .row = formula { return true }
        return false
    }

    static let greek: [String: String] = [
        "alpha": "α", "beta": "β", "gamma": "γ", "delta": "δ", "epsilon": "ε",
        "zeta": "ζ", "eta": "η", "theta": "θ", "iota": "ι", "kappa": "κ",
        "lambda": "λ", "mu": "μ", "nu": "ν", "xi": "ξ", "omicron": "ο",
        "pi": "π", "rho": "ρ", "sigma": "σ", "tau": "τ", "upsilon": "υ",
        "phi": "φ", "chi": "χ", "psi": "ψ", "omega": "ω",
        "Gamma": "Γ", "Delta": "Δ", "Theta": "Θ", "Lambda": "Λ", "Xi": "Ξ",
        "Pi": "Π", "Sigma": "Σ", "Upsilon": "Υ", "Phi": "Φ", "Psi": "Ψ", "Omega": "Ω",
        "hbar": "ℏ"
    ]

    private static func symbol(_ identifier: String) -> String {
        if let exact = greek[identifier] { return exact }
        let pieces = identifier.split(separator: "_", omittingEmptySubsequences: false)
        if pieces.count == 2, let base = greek[String(pieces[0])], !pieces[1].isEmpty,
           pieces[1].allSatisfy({ "0123456789".contains($0) }) {
            let subscripts = Array("₀₁₂₃₄₅₆₇₈₉")
            let suffix = pieces[1].compactMap { $0.wholeNumberValue }.map { String(subscripts[$0]) }.joined()
            return base + suffix
        }
        return identifier
    }

    /// Recover only numeric spelling, never grammar or precedence. The AST
    /// remains authoritative; each spelling is checked against its value.
    private static let numberPattern = try? NSRegularExpression(
        pattern: #"(?<![\p{L}\p{N}_°µΩℏπ])[0-9]+(?:[.,][0-9]*)?(?:[eE][+\-−–]?[0-9]+)?|(?<![\p{L}\p{N}_°µΩℏπ])[.,][0-9]+(?:[eE][+\-−–]?[0-9]+)?|[⁰¹²³⁴⁵⁶⁷⁸⁹⁻⁺]+"#)

    private static let superscripts: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4", "⁵": "5",
        "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9", "⁻": "-", "⁺": "+"
    ]

    private static func numberSpellings(in source: String) -> [String] {
        guard let regex = numberPattern else { return [] }
        return regex.matches(in: source, range: NSRange(source.startIndex..., in: source)).compactMap { match in
            guard let range = Range(match.range, in: source) else { return nil }
            return String(source[range].map { superscripts[$0] ?? $0 })
        }
    }

    private static func number(_ value: Double, spelling: String?) -> MathFormula {
        let normalized = spelling?.replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-").replacingOccurrences(of: "–", with: "-")
        let validated = normalized.flatMap { Double($0) == value ? $0 : nil }
        // The entered spelling is kept verbatim, trailing zeros included:
        // the ruler writes 9,0 on purpose to keep its step.
        var literal = validated ?? String(value)
        if validated == nil, literal.hasSuffix(".0") { literal.removeLast(2) }
        let scientific = literal.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        if scientific.count == 2, let exponent = Int(scientific[1]) {
            return row([.atom(decimal(String(scientific[0]))), .atom(" × "),
                        .power(.atom("10"), .atom(String(exponent).replacingOccurrences(of: "-", with: "−")))])
        }
        return .atom(decimal(literal))
    }

    private static func decimal(_ literal: String) -> String {
        literal.replacingOccurrences(of: ".", with: ",").replacingOccurrences(of: "-", with: "−")
    }
}
