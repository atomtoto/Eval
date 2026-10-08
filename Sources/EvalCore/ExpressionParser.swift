import Foundation

/// The syntax tree keeps unit suffixes separate from variable names: in
/// `m = 80 kg; v = 5 m/s`, the second `m` remains the metre.
indirect enum Expression: Sendable {
    case number(Double)
    case identifier(String)
    case unit(String)
    case unary(UnaryOperator, Expression)
    case binary(BinaryOperator, Expression, Expression)
    /// A call with its canonical name and arguments separated by `;` in the source.
    case function(String, [Expression])
    /// `n!`, a postfix factorial that binds tighter than `^` and a unary minus.
    case factorial(Expression)
    /// An unspaced unit chain after a number, such as 72km/h: units unless
    /// the sheet declares one of its symbols.
    case compactUnits(Expression)

    enum UnaryOperator: Sendable { case plus, minus }
    enum BinaryOperator: Sendable { case add, subtract, multiply, divide, power }

    var checksHomogeneity: Bool {
        switch self {
        case .binary(let operation, let left, let right):
            return operation == .add || operation == .subtract
                || left.checksHomogeneity || right.checksHomogeneity
        case .function(let name, let arguments):
            return ["min", "max", "atan2"].contains(name) || arguments.contains { $0.checksHomogeneity }
        case .unary(_, let expression), .factorial(let expression):
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
        case .unary(_, let argument), .factorial(let argument):
            return argument.isNumericExpression
        case .function(_, let arguments):
            return arguments.allSatisfy(\.isNumericExpression)
        case .binary(_, let left, let right):
            return left.isNumericExpression && right.isNumericExpression
        case .identifier, .unit, .compactUnits: return false
        }
    }
}

enum CalculationError: Error, LocalizedError, Sendable {
    case invalid(String)
    /// A cycle, or a depth limit reached along one: the message depends on
    /// where evaluation started, so it is shown unchanged and never remembered.
    case circular(String)
    /// Names the declaration at fault instead of repeating its own diagnostic.
    case dependency(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message), .circular(let message), .dependency(let message): return message
        }
    }

    var isCircular: Bool {
        if case .circular = self { return true }
        return false
    }

    /// Errors that already describe the identifier itself or its root cause.
    var isAttributed: Bool {
        switch self {
        case .circular, .dependency: return true
        case .invalid: return false
        }
    }
}

/// A bounded recursive-descent parser for the notebook's mathematical syntax.
/// Exponentiation is right-associative and has precedence over a unary minus.
struct ExpressionParser {
    private enum TokenKind: Equatable {
        case number(Double), identifier(String)
        case plus, minus, multiply, divide, power, leftParenthesis, rightParenthesis
        /// `;` separates function arguments; a `,` not followed by a digit is a stray comma.
        case semicolon, comma, factorial
        case end
    }

    private struct Token {
        let kind: TokenKind
        let column: Int
        var hasLeadingWhitespace = false
        /// A number written with a decimal comma, such as 2,3.
        var hasDecimalComma = false
    }

    /// A function's canonical name and the number of arguments it accepts.
    struct FunctionSpec {
        let name: String
        let arity: ClosedRange<Int>
        let example: String
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
            try rejectSeparator()
            throw error("Symbole inattendu ; vérifiez les opérateurs et les parenthèses.")
        }
        return expression
    }

    /// A `;` or `,` that is not inside a function call.
    private func rejectSeparator() throws {
        if current == .semicolon { throw error("« ; » sépare les arguments d’une fonction, par exemple max(a; b).") }
        if current == .comma {
            throw error("Virgule inattendue : la virgule est le séparateur décimal (2,5). Séparez les arguments d’une fonction par « ; ».")
        }
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
                try rejectConsecutiveNumbers()
                expression = .binary(.multiply, expression, try parseUnary())
            } else {
                return expression
            }
        }
    }

    // The recursive path (addition → … → primary → call → addition) runs once per
    // nesting level, on stacks as small as 512 KB in debug builds. Its functions
    // therefore stay lean: bulky or rarely taken code lives in `@inline(never)`
    // helpers, whose frames are gone before the recursion goes deeper.
    @inline(never)
    private func rejectConsecutiveNumbers() throws {
        if case .number = current, case .number = tokens[position - 1].kind {
            throw error("Deux nombres consécutifs nécessitent un opérateur. Les séparateurs de milliers ne sont pas pris en charge.")
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
        while current == .factorial {
            advance()
            expression = .factorial(expression)
        }
        if current == .power {
            advance()
            expression = .binary(.power, expression, try parseUnary(allowUnitSuffix: false))
        }
        return try parseUnitSuffix(expression, allowUnitSuffix: allowUnitSuffix)
    }

    /// `3 m`, `72km/h`, `3g/cm³`: units written after a numeric expression.
    @inline(never)
    private mutating func parseUnitSuffix(_ expression: Expression, allowUnitSuffix: Bool) throws -> Expression {
        if allowUnitSuffix, expression.isNumericExpression,
           tokens[position].hasLeadingWhitespace, isUnitToken(current) {
            return .binary(.multiply, expression, try parseUnitProduct())
        }
        // 72km/h or 3g/cm³: an unspaced chain joined by an operator reads as
        // units, whereas a lone 3g keeps the variable namespace.
        if allowUnitSuffix, expression.isNumericExpression, !tokens[position].hasLeadingWhitespace,
           isUnitToken(current), position + 2 < tokens.count,
           [.multiply, .divide, .power].contains(tokens[position + 1].kind),
           !tokens[position + 1].hasLeadingWhitespace, !tokens[position + 2].hasLeadingWhitespace {
            let start = position
            let units = try parseUnitProduct()
            if position - start > 1 { return .binary(.multiply, expression, .compactUnits(units)) }
            position = start
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
            if current == .leftParenthesis, let function = Self.function(named: name) {
                advance()
                return try parseCall(name, function)
            }
            return try parseBareIdentifier(name)
        case .leftParenthesis:
            advance()
            let expression = try parseAddition()
            try closeParenthesis()
            return expression
        default:
            throw primaryError()
        }
    }

    /// A name not followed by `(`: a variable or unit, or `√`.
    @inline(never)
    private mutating func parseBareIdentifier(_ name: String) throws -> Expression {
        let function = Self.function(named: name)
        if function?.name == "sqrt", name == "√" {
            // A spaced unit stays outside the root: √2 m is (√2)·m.
            return .function("sqrt", [try parseUnary(allowUnitSuffix: false)])
        }
        // A function name is a call only when followed by `(`. Otherwise it is an
        // ordinary name: a variable called max, or the unit min. When nothing
        // declares it, the engine suggests the call syntax.
        return .identifier(name)
    }

    @inline(never)
    private mutating func closeParenthesis() throws {
        guard current == .rightParenthesis else {
            try rejectSeparator()
            throw error("Parenthèse fermante manquante.")
        }
        advance()
    }

    @inline(never)
    private func primaryError() -> CalculationError {
        switch current {
        case .end: return error("Il manque un nombre, une variable ou une expression après l’opérateur.")
        case .rightParenthesis: return error("La parenthèse ne contient pas d’expression valide.")
        default: return error("Un nombre, une variable ou une parenthèse est attendu.")
        }
    }

    /// The arguments after `name(`, separated by `;`. The decimal comma makes `,`
    /// ambiguous, so it is explained instead of guessed.
    private mutating func parseCall(_ name: String, _ function: FunctionSpec) throws -> Expression {
        let start = position
        var arguments = [try parseAddition()]
        while current == .semicolon {
            advance()
            arguments.append(try parseAddition())
        }
        try closeCall(name, function, count: arguments.count, start: start)
        return .function(function.name, arguments)
    }

    @inline(never)
    private mutating func closeCall(_ name: String, _ function: FunctionSpec, count: Int, start: Int) throws {
        if current == .comma {
            if function.arity.upperBound == 1 {
                throw error("\(name) attend un seul argument ; la virgule est le séparateur décimal (2,5).")
            }
            throw error("Séparez les arguments de \(name) par « ; » : la virgule est le séparateur décimal, par exemple \(name)(2,5; 3).")
        }
        guard current == .rightParenthesis else {
            throw error("La fonction \(name) attend un argument entre parenthèses.")
        }
        advance()
        guard function.arity.contains(count) else {
            var message = Self.arityMessage(name, function, count: count)
            if count == 1, tokens[start].hasDecimalComma, position - start == 2 {
                message += " Attention : avec une virgule, 2,3 est un nombre décimal."
            }
            throw CalculationError.invalid(message)
        }
    }

    private static func arityMessage(_ name: String, _ function: FunctionSpec, count: Int) -> String {
        let arity = function.arity
        if arity.upperBound == 1 { return "\(name) attend un seul argument." }
        if arity.lowerBound == 1 { return "\(name) attend 1 ou 2 arguments : \(name)(x) ou \(function.example)." }
        if count > arity.upperBound, arity.lowerBound != arity.upperBound {
            return "\(name) accepte au plus \(arity.upperBound) arguments."
        }
        let amount = arity.lowerBound == arity.upperBound ? "\(arity.lowerBound) arguments" : "au moins \(arity.lowerBound) arguments"
        return "\(name) attend \(amount) séparés par « ; », par exemple \(function.example)."
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

    /// Functions by spelling. `log10` keeps its own name; the inverse trigonometric
    /// functions accept the arc spellings.
    static func function(named name: String) -> FunctionSpec? {
        func spec(_ canonical: String, _ arity: ClosedRange<Int> = 1...1, _ example: String = "") -> FunctionSpec {
            FunctionSpec(name: canonical, arity: arity, example: example)
        }
        switch name {
        case "sqrt", "√": return spec("sqrt")
        case "arcsin": return spec("asin")
        case "arccos": return spec("acos")
        case "arctan": return spec("atan")
        case "sin", "cos", "tan", "asin", "acos", "atan", "sinh", "cosh", "tanh", "abs", "exp", "ln", "log10",
             "cbrt", "floor", "ceil", "round":
            return spec(name)
        case "log": return spec(name, 1...2, "log(x; b)")
        case "atan2": return spec(name, 2...2, "atan2(y; x)")
        case "root": return spec(name, 2...2, "root(x; n)")
        case "min", "max": return spec(name, 2...50, "\(name)(a; b)")
        default: return nil
        }
    }

    /// Whether the name is a function, which a call `name(…)` reaches even if a variable shares it.
    static func isFunctionName(_ name: String) -> Bool {
        name != "√" && function(named: name) != nil
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

    /// √ and ° end a name: a√2 is a·√2 and θ° is θ·°.
    private static func isIdentifierContinuation(_ character: Character) -> Bool {
        (isIdentifierStart(character) && character != "√" && character != "°")
            || "0123456789₀₁₂₃₄₅₆₇₈₉".contains(character)
    }

    private static let superscriptDigits: [Character: Character] = [
        "⁰": "0", "¹": "1", "²": "2", "³": "3", "⁴": "4",
        "⁵": "5", "⁶": "6", "⁷": "7", "⁸": "8", "⁹": "9",
        "⁻": "-", "⁺": "+"
    ]

    private static func tokenize(_ source: String) throws -> [Token] {
        let characters = Array(source)
        guard characters.count <= 2_000 else {
            throw CalculationError.invalid("Ligne trop longue (2 000 caractères maximum).")
        }
        var result: [Token] = []
        var index = 0
        let superscripts = Self.superscriptDigits

        func isASCIIDigit(_ character: Character) -> Bool { "0123456789".contains(character) }
        // A comma is decimal only before a digit: 2,5 is a number, max(2, 3) has a comma.
        func isDecimalComma(at position: Int) -> Bool {
            position + 1 < characters.count && characters[position] == "," && isASCIIDigit(characters[position + 1])
        }

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
            case ";": simple = .semicolon
            case ",": simple = isDecimalComma(at: index) ? nil : .comma
            case "!": simple = .factorial
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
            } else if character == "%" {
                result.append(Token(kind: .identifier("%"), column: column,
                                    hasLeadingWhitespace: index > 0 && characters[index - 1].isWhitespace))
                index += 1
            } else if isASCIIDigit(character) || character == "." || isDecimalComma(at: index) {
                let start = index
                var decimalSeen = false
                var hasComma = false
                var digits = 0
                while index < characters.count {
                    let next = characters[index]
                    if isASCIIDigit(next) { digits += 1; index += 1 }
                    else if next == "." || isDecimalComma(at: index), !decimalSeen {
                        decimalSeen = true
                        hasComma = next == ","
                        index += 1
                    } else { break }
                }
                guard digits > 0 else {
                    throw CalculationError.invalid("Nombre décimal invalide (colonne \(column)).")
                }
                if index < characters.count, characters[index] == "." || isDecimalComma(at: index) {
                    throw CalculationError.invalid("Un nombre ne peut contenir qu’un seul séparateur décimal (colonne \(index + 1)).")
                }
                // An e/E is a scientific exponent only when followed by digits.
                if index < characters.count, characters[index] == "e" || characters[index] == "E" {
                    var end = index + 1
                    if end < characters.count, "+-−–".contains(characters[end]) {
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
                    .replacingOccurrences(of: "–", with: "-")
                guard let value = Double(literal), value.isFinite else {
                    throw CalculationError.invalid("Ce nombre dépasse la plage de calcul (colonne \(column)).")
                }
                result.append(Token(kind: .number(value), column: column, hasDecimalComma: hasComma))
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
