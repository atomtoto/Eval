import Foundation

/// The syntax tree keeps unit suffixes separate from variable names: in
/// `m = 80 kg; v = 5 m/s`, the second `m` remains the metre.
indirect enum Expression: Sendable {
    case number(Double)
    case identifier(String)
    case unit(String)
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    case function(String, Expression)

    enum UnaryOperator: Sendable { case plus, minus }
    enum BinaryOperator: Sendable { case add, subtract, multiply, divide, power }

    var checksHomogeneity: Bool {
        switch self {
        case .binary(let operation, let left, let right):
            return operation == .add || operation == .subtract
                || left.checksHomogeneity || right.checksHomogeneity
        case .unary(_, let expression), .function(_, let expression):
            return expression.checksHomogeneity
        default:
            return false
        }
    }

    /// Scientific notation such as `2 × 10³ m` may end a numeric power with
    /// a unit suffix. Variable expressions retain their own name resolution.
    var isNumericExpression: Bool {
        switch self {
        case .number: return true
        case .unary(_, let argument), .function(_, let argument):
            return argument.isNumericExpression
        case .binary(_, let left, let right):
            return left.isNumericExpression && right.isNumericExpression
        case .identifier, .unit: return false
        }
    }
}

enum CalculationError: Error, LocalizedError, Sendable {
    case invalid(String)

    var errorDescription: String? {
        switch self { case .invalid(let message): return message }
    }
}

/// A bounded recursive-descent parser for the notebook's mathematical syntax.
/// Exponentiation is right-associative and has precedence over a unary minus.
struct ExpressionParser {
    private enum TokenKind: Equatable {
        case number(Double), identifier(String)
        case plus, minus, multiply, divide, power, leftParenthesis, rightParenthesis
        case end
    }

    private struct Token {
        let kind: TokenKind
        let column: Int
        var hasLeadingWhitespace = false
    }

    private let tokens: [Token]
    private var position = 0
    private var nesting = 0

    init(_ source: String) throws {
        tokens = try Self.tokenize(source)
    }

    mutating func parse() throws -> Expression {
        guard current != .end else { throw error("Il manque une expression.") }
        let expression = try parseAddition()
        guard current == .end else {
            if current == .rightParenthesis { throw error("Parenthèse fermante inattendue.") }
            throw error("Symbole inattendu ; vérifiez les opérateurs et les parenthèses.")
        }
        return expression
    }

    private var current: TokenKind { tokens[position].kind }

    private mutating func advance() { position += 1 }

    private func error(_ message: String) -> CalculationError {
        .invalid("\(message) (colonne \(tokens[position].column))")
    }

    private mutating func enter() throws {
        nesting += 1
        guard nesting <= 80 else { throw error("Expression trop imbriquée (80 niveaux maximum).") }
    }

    private mutating func parseAddition() throws -> Expression {
        var expression = try parseMultiplication()
        while current == .plus || current == .minus {
            let operation: Expression.BinaryOperator = current == .plus ? .add : .subtract
            advance()
            expression = .binary(operation, expression, try parseMultiplication())
        }
        return expression
    }

    private mutating func parseMultiplication() throws -> Expression {
        var expression = try parseUnary()
        while true {
            if current == .multiply || current == .divide {
                let operation: Expression.BinaryOperator = current == .multiply ? .multiply : .divide
                advance()
                expression = .binary(operation, expression, try parseUnary())
            } else if startsPrimary(current) {
                if case .number = current, case .number = tokens[position - 1].kind {
                    throw error("Deux nombres consécutifs nécessitent un opérateur. Les séparateurs de milliers ne sont pas pris en charge.")
                }
                expression = .binary(.multiply, expression, try parseUnary())
            } else {
                return expression
            }
        }
    }

    private mutating func parseUnary(allowUnitSuffix: Bool = true) throws -> Expression {
        try enter()
        defer { nesting -= 1 }
        if current == .plus || current == .minus {
            let operation: Expression.UnaryOperator = current == .plus ? .plus : .minus
            advance()
            return .unary(operation, try parseUnary(allowUnitSuffix: allowUnitSuffix))
        }
        return try parsePower(allowUnitSuffix: allowUnitSuffix)
    }

    private mutating func parsePower(allowUnitSuffix: Bool) throws -> Expression {
        var expression = try parsePrimary()
        if current == .power {
            advance()
            expression = .binary(.power, expression, try parseUnary(allowUnitSuffix: false))
        }
        if allowUnitSuffix, expression.isNumericExpression,
           tokens[position].hasLeadingWhitespace, isUnitToken(current) {
            return .binary(.multiply, expression, try parseUnitProduct())
        }
        return expression
    }

    private mutating func parsePrimary() throws -> Expression {
        switch current {
        case .number(let value):
            advance()
            return .number(value)
        case .identifier(let name):
            advance()
            let function = Self.functionName(name)
            if let function, current == .leftParenthesis {
                advance()
                let argument = try parseAddition()
                guard current == .rightParenthesis else {
                    throw error("La fonction \(name) attend un argument entre parenthèses.")
                }
                advance()
                return .function(function, argument)
            }
            if function == "sqrt", name == "√" {
                return .function("sqrt", try parseUnary())
            }
            if function != nil {
                throw error("Utilisez \(name)(expression) pour cette fonction.")
            }
            return .identifier(name)
        case .leftParenthesis:
            advance()
            let expression = try parseAddition()
            guard current == .rightParenthesis else { throw error("Parenthèse fermante manquante.") }
            advance()
            return expression
        case .end:
            throw error("Il manque un nombre, une variable ou une expression après l’opérateur.")
        case .rightParenthesis:
            throw error("La parenthèse ne contient pas d’expression valide.")
        default:
            throw error("Un nombre, une variable ou une parenthèse est attendu.")
        }
    }

    /// Only known units are consumed here. `5 m * a` therefore leaves `a` in
    /// the variable namespace, while `5 kg*m/s²` uses SI units throughout.
    private mutating func parseUnitProduct() throws -> Expression {
        var expression = try parseUnitPower()
        while true {
            if (current == .multiply || current == .divide),
               position + 1 < tokens.count,
               !tokens[position].hasLeadingWhitespace,
               !tokens[position + 1].hasLeadingWhitespace,
               isUnitToken(tokens[position + 1].kind) {
                let operation: Expression.BinaryOperator = current == .multiply ? .multiply : .divide
                advance()
                expression = .binary(operation, expression, try parseUnitPower())
            } else if isUnitToken(current) {
                expression = .binary(.multiply, expression, try parseUnitPower())
            } else {
                return expression
            }
        }
    }

    private mutating func parseUnitPower() throws -> Expression {
        guard case .identifier(let symbol) = current else { throw error("Une unité est attendue.") }
        advance()
        let unit = Expression.unit(symbol)
        if current == .power {
            advance()
            return .binary(.power, unit, try parseUnary(allowUnitSuffix: false))
        }
        return unit
    }

    private func isUnitToken(_ token: TokenKind) -> Bool {
        if case .identifier(let name) = token { return UnitCatalog.lookup(name) != nil }
        return false
    }

    private func startsPrimary(_ token: TokenKind) -> Bool {
        switch token {
        case .number, .identifier, .leftParenthesis: return true
        default: return false
        }
    }

    private static func functionName(_ name: String) -> String? {
        switch name {
        case "sqrt", "√": return "sqrt"
        case "sin", "cos", "tan", "abs", "exp", "ln", "log", "log10": return name
        default: return nil
        }
    }

    static func isIdentifier(_ source: String) -> Bool {
        guard let first = source.first, isIdentifierStart(first), first != "√" else { return false }
        return source.dropFirst().allSatisfy { isIdentifierContinuation($0) }
    }

    private static func isIdentifierStart(_ character: Character) -> Bool {
        character.isLetter || character == "_" || character == "°"
            || character == "µ" || character == "Ω" || character == "ℏ"
            || character == "π" || character == "√"
    }

    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        isIdentifierStart(character) || "0123456789₀₁₂₃₄₅₆₇₈₉".contains(character)
    }

    private static func tokenize(_ source: String) throws -> [Token] {
        let characters = Array(source)
        guard characters.count <= 2_000 else {
            throw CalculationError.invalid("Ligne trop longue (2 000 caractères maximum).")
        }
        var result: [Token] = []
        var index = 0
        let superscripts: [Character: Character] = [
            "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
            "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
            "⁻": "-", "⁺": "+"
        ]

        func isASCIIDigit(_ character: Character) -> Bool { "0123456789".contains(character) }

        while index < characters.count {
            let character = characters[index]
            let column = index + 1
            if character.isWhitespace { index += 1; continue }
            let simple: TokenKind?
            switch character {
            case "+": simple = .plus
            case "-", "−", "–": simple = .minus
            case "*", "×", "·", "⋅": simple = .multiply
            case "/", "÷": simple = .divide
            case "^": simple = .power
            case "(": simple = .leftParenthesis
            case ")": simple = .rightParenthesis
            default: simple = nil
            }
            if let simple {
                result.append(Token(kind: simple, column: column,
                                    hasLeadingWhitespace: index > 0 && characters[index - 1].isWhitespace))
                index += 1
            } else if superscripts[character] != nil {
                var exponent = ""
                while index < characters.count, let digit = superscripts[characters[index]] {
                    exponent.append(digit)
                    index += 1
                }
                guard let number = Double(exponent), number.isFinite else {
                    throw CalculationError.invalid("Exposant en indice supérieur invalide (colonne \(column)).")
                }
                result.append(Token(kind: .power, column: column))
                result.append(Token(kind: .number(number), column: column))
            } else if character == "√" {
                result.append(Token(kind: .identifier("√"), column: column))
                index += 1
            } else if isASCIIDigit(character) || character == "." || character == "," {
                let start = index
                var decimalSeen = false
                var digits = 0
                while index < characters.count {
                    let next = characters[index]
                    if isASCIIDigit(next) { digits += 1; index += 1 }
                    else if (next == "." || next == ","), !decimalSeen {
                        decimalSeen = true; index += 1
                    } else { break }
                }
                guard digits > 0 else {
                    throw CalculationError.invalid("Nombre décimal invalide (colonne \(column)).")
                }
                if index < characters.count, characters[index] == "." || characters[index] == "," {
                    throw CalculationError.invalid("Un nombre ne peut contenir qu’un seul séparateur décimal (colonne \(index + 1)).")
                }
                // An e/E is a scientific exponent only when followed by digits.
                if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                    var end = index + 1
                    if end < characters.count, characters[end] == "+" || characters[end] == "-" || characters[end] == "−" {
                        end += 1
                    }
                    if end < characters.count, isASCIIDigit(characters[end]) {
                        index = end + 1
                        while index < characters.count, isASCIIDigit(characters[index]) { index += 1 }
                    }
                }
                let literal = String(characters[start..<index])
                    .replacingOccurrences(of: ",", with: ".")
                    .replacingOccurrences(of: "−", with: "-")
                guard let value = Double(literal), value.isFinite else {
                    throw CalculationError.invalid("Ce nombre dépasse la plage de calcul (colonne \(column)).")
                }
                result.append(Token(kind: .number(value), column: column))
            } else if isIdentifierStart(character) {
                let start = index
                index += 1
                while index < characters.count, isIdentifierContinuation(characters[index]) {
                    index += 1
                }
                result.append(Token(kind: .identifier(String(characters[start..<index])), column: column,
                                    hasLeadingWhitespace: start > 0 && characters[start - 1].isWhitespace))
            } else {
                throw CalculationError.invalid("Caractère « \(character) » non reconnu (colonne \(column)).")
            }
            guard result.count <= 1_000 else {
                throw CalculationError.invalid("Expression trop longue (1 000 éléments maximum).")
            }
        }
        result.append(Token(kind: .end, column: characters.count + 1))
        return result
    }
}
