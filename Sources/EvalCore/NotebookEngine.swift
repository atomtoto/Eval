import Foundation

public enum LineKind: String, Sendable, Codable {
    case expression, definition, equation, comment, empty
}

public enum LineStatus: String, Sendable, Codable {
    case success, error, neutral
}

public struct EvaluatedLine: Identifiable, Sendable {
    public let id: Int
    public let source: String
    public let kind: LineKind
    public let quantity: Quantity?
    public let message: String?
    public let status: LineStatus
    public let dimensionMessage: String?
}

public struct ResolvedVariable: Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let quantity: Quantity
}

public struct NotebookEvaluation: Sendable {
    public let lines: [EvaluatedLine]
    /// Physical constants actually used without an explicit declaration.
    public let constants: [ConstantDefinition]
    public let variables: [ResolvedVariable]
}

/// Evaluates a whole sheet with a dependency graph, so definitions may appear
/// above or below the formulas that use them. No mutable state survives a run.
public struct NotebookEngine: Sendable {
    public init() {}

    public static func evaluate(_ source: String) -> NotebookEvaluation {
        Self().evaluate(source)
    }

    public func evaluate(_ source: String) -> NotebookEvaluation {
        let sourceLines = source.replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n").components(separatedBy: "\n")
        guard source.count <= 100_000, sourceLines.count <= 500 else {
            return NotebookEvaluation(lines: [EvaluatedLine(
                id: 0, source: "", kind: .expression, quantity: nil,
                message: "Feuille trop longue (500 lignes et 100 000 caractères maximum).",
                status: .error, dimensionMessage: nil
            )], constants: [], variables: [])
        }

        let parsedLines = sourceLines.enumerated().map { ParsedLine(id: $0.offset, source: $0.element) }
        let resolver = Resolver(lines: parsedLines)
        var results: [EvaluatedLine] = []

        for line in parsedLines {
            if line.kind == .empty || line.kind == .comment {
                results.append(line.result(status: .neutral))
                continue
            }
            do {
                if let name = line.name {
                    let quantity = try resolver.resolve(name, depth: 0)
                    results.append(line.result(quantity: quantity, status: .success,
                                               dimensionMessage: dimensionMessage(quantity, expression: line.left)))
                } else if let issue = line.issue {
                    throw issue
                } else if let left = line.left {
                    let quantity = try resolver.evaluate(left, depth: 0)
                    if let right = line.right {
                        let other = try resolver.evaluate(right, depth: 0)
                        guard quantity.dimension.isEquivalent(to: other.dimension) else {
                            throw CalculationError.invalid("Équation non homogène : le membre gauche a pour dimension \(quantity.dimension.formatted), le membre droit \(other.dimension.formatted).")
                        }
                        let scale = max(abs(quantity.value), abs(other.value))
                        let equal = quantity.value == other.value
                            || abs(quantity.value - other.value) <= scale * 1e-10
                        let message = equal ? "Égalité vérifiée."
                            : "Égalité non vérifiée : \(QuantityFormatter.string(quantity)) ≠ \(QuantityFormatter.string(other))."
                        results.append(line.result(quantity: quantity, message: message,
                                                   status: equal ? .success : .error,
                                                   dimensionMessage: quantity.dimension.isDimensionless ? nil
                                                       : "Homogène · \(quantity.dimension.formatted)"))
                    } else {
                        results.append(line.result(quantity: quantity, status: .success,
                                                   dimensionMessage: dimensionMessage(quantity, expression: left)))
                    }
                }
            } catch {
                results.append(line.result(message: error.localizedDescription, status: .error))
            }
        }

        let variables = resolver.orderedNames.compactMap { name -> ResolvedVariable? in
            guard let quantity = resolver.cache[name] else { return nil }
            return ResolvedVariable(name: name, quantity: quantity)
        }
        return NotebookEvaluation(lines: results, constants: resolver.usedConstants, variables: variables)
    }

    private func dimensionMessage(_ quantity: Quantity, expression: Expression?) -> String? {
        guard !quantity.dimension.isDimensionless else { return nil }
        let label = expression?.checksHomogeneity == true ? "Homogène" : "Dimension"
        return "\(label) · \(quantity.dimension.formatted)"
    }
}

private struct ParsedLine {
    let id: Int
    let source: String
    var kind: LineKind = .expression
    var name: String?
    var left: Expression?
    var right: Expression?
    var issue: CalculationError?

    init(id: Int, source: String) {
        self.id = id
        self.source = source
        let uncommented = Self.removeComment(source)
        let content = uncommented.trimmingCharacters(in: .whitespacesAndNewlines)
        if content.isEmpty {
            kind = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .comment
            return
        }

        do {
            let separators = Self.equalitySeparators(content)
            if let separator = separators.first, !separator.isComparison {
                let lhs = String(content[..<separator.start]).trimmingCharacters(in: .whitespaces)
                if ExpressionParser.isIdentifier(lhs) {
                    kind = .definition
                    name = lhs
                }
            }
            if separators.count > 1 {
                throw CalculationError.invalid("Une ligne doit contenir une seule déclaration ou égalité.")
            }
            if let separator = separators.first {
                let lhs = String(content[..<separator.start]).trimmingCharacters(in: .whitespaces)
                let rhs = String(content[separator.end...]).trimmingCharacters(in: .whitespaces)
                if !separator.isComparison, ExpressionParser.isIdentifier(lhs) {
                    kind = .definition
                    name = lhs
                    guard !rhs.isEmpty else { throw CalculationError.invalid("Il manque la valeur de « \(lhs) » après le signe =.") }
                    var parser = try ExpressionParser(rhs)
                    left = try parser.parse()
                } else {
                    kind = .equation
                    guard !lhs.isEmpty, !rhs.isEmpty else {
                        throw CalculationError.invalid("Une égalité nécessite une expression de chaque côté.")
                    }
                    var leftParser = try ExpressionParser(lhs)
                    var rightParser = try ExpressionParser(rhs)
                    left = try leftParser.parse()
                    right = try rightParser.parse()
                }
            } else {
                var parser = try ExpressionParser(content)
                left = try parser.parse()
            }
        } catch let error as CalculationError {
            issue = error
        } catch {
            issue = .invalid(error.localizedDescription)
        }
    }

    func result(quantity: Quantity? = nil, message: String? = nil, status: LineStatus,
                dimensionMessage: String? = nil) -> EvaluatedLine {
        EvaluatedLine(id: id, source: source, kind: kind, quantity: quantity,
                      message: message, status: status, dimensionMessage: dimensionMessage)
    }

    private struct EqualitySeparator {
        let start: String.Index
        let end: String.Index
        let isComparison: Bool
    }

    private static func equalitySeparators(_ source: String) -> [EqualitySeparator] {
        var result: [EqualitySeparator] = []
        var index = source.startIndex
        while index < source.endIndex {
            if source[index] == "=" {
                let next = source.index(after: index)
                let comparison = next < source.endIndex && source[next] == "="
                result.append(EqualitySeparator(start: index,
                                                end: comparison ? source.index(after: next) : next,
                                                isComparison: comparison))
                index = comparison ? source.index(after: next) : next
            } else {
                index = source.index(after: index)
            }
        }
        return result
    }

    private static func removeComment(_ source: String) -> String {
        var end = source.endIndex
        if let marker = source.firstIndex(of: "#") { end = min(end, marker) }
        if let marker = source.range(of: "//")?.lowerBound { end = min(end, marker) }
        return String(source[..<end])
    }
}

private final class Resolver {
    private var definitions: [String: [ParsedLine]] = [:]
    private var visiting: [String] = []
    private var constantIDs: Set<String> = []
    private(set) var orderedNames: [String] = []
    private(set) var cache: [String: Quantity] = [:]
    private(set) var usedConstants: [ConstantDefinition] = []

    init(lines: [ParsedLine]) {
        for line in lines {
            guard let name = line.name else { continue }
            if definitions[name] == nil { orderedNames.append(name) }
            definitions[name, default: []].append(line)
        }
    }

    func resolve(_ name: String, depth: Int) throws -> Quantity {
        guard depth <= 100 else { throw CalculationError.invalid("Chaîne de dépendances trop longue (100 niveaux maximum).") }
        if let value = cache[name] { return value }
        if let declarations = definitions[name] {
            guard declarations.count == 1, let declaration = declarations.first else {
                let numbers = declarations.map { String($0.id + 1) }.joined(separator: ", ")
                throw CalculationError.invalid("« \(name) » est déclaré plusieurs fois (lignes \(numbers)). Conservez une seule déclaration.")
            }
            if let cycleStart = visiting.firstIndex(of: name) {
                let path = (Array(visiting[cycleStart...]) + [name]).joined(separator: " → ")
                throw CalculationError.invalid("Dépendance circulaire : \(path).")
            }
            if let issue = declaration.issue { throw issue }
            guard let expression = declaration.left else {
                throw CalculationError.invalid("La déclaration de « \(name) » ne contient pas d’expression valide.")
            }
            visiting.append(name)
            defer { visiting.removeLast() }
            let value = try evaluate(expression, depth: depth + 1)
            cache[name] = value
            return value
        }
        if let constant = ConstantCatalog.lookup(name) {
            if constantIDs.insert(constant.id).inserted { usedConstants.append(constant) }
            return constant.quantity
        }
        if let unit = UnitCatalog.lookup(name) { return unit.quantity }
        throw CalculationError.invalid("Variable « \(name) » inconnue. Ajoutez une déclaration, par exemple \(name) = 7,2 m.")
    }

    func evaluate(_ expression: Expression, depth: Int) throws -> Quantity {
        guard depth <= 200 else { throw CalculationError.invalid("Expression trop complexe (200 niveaux maximum).") }
        switch expression {
        case .number(let value):
            return Quantity(value: value)
        case .identifier(let name):
            return try resolve(name, depth: depth + 1)
        case .unit(let symbol):
            guard let unit = UnitCatalog.lookup(symbol) else {
                throw CalculationError.invalid("Unité « \(symbol) » inconnue.")
            }
            return unit.quantity
        case .unary(let operation, let argument):
            let quantity = try evaluate(argument, depth: depth + 1)
            return Quantity(value: operation == .minus ? -quantity.value : quantity.value,
                            dimension: quantity.dimension)
        case .binary(let operation, let left, let right):
            let lhs = try evaluate(left, depth: depth + 1)
            let rhs = try evaluate(right, depth: depth + 1)
            switch operation {
            case .add, .subtract:
                guard lhs.dimension.isEquivalent(to: rhs.dimension) else {
                    throw CalculationError.invalid("Addition ou soustraction non homogène : impossible de combiner \(lhs.dimension.formatted) et \(rhs.dimension.formatted).")
                }
                return try finite(operation == .add ? lhs.value + rhs.value : lhs.value - rhs.value,
                                  dimension: lhs.dimension)
            case .multiply:
                return try finite(lhs.value * rhs.value, dimension: lhs.dimension + rhs.dimension)
            case .divide:
                guard rhs.value != 0 else { throw CalculationError.invalid("Division par zéro.") }
                return try finite(lhs.value / rhs.value, dimension: lhs.dimension - rhs.dimension)
            case .power:
                guard rhs.dimension.isDimensionless else {
                    throw CalculationError.invalid("Un exposant doit être sans dimension.")
                }
                guard !(lhs.value == 0 && rhs.value <= 0) else {
                    throw CalculationError.invalid("Zéro ne peut pas être élevé à une puissance nulle ou négative.")
                }
                guard abs(rhs.value) <= 10_000 else {
                    throw CalculationError.invalid("Exposant trop grand (valeur absolue maximale : 10 000).")
                }
                return try finite(Foundation.pow(lhs.value, rhs.value),
                                  dimension: lhs.dimension.scaled(by: rhs.value))
            }
        case .function(let function, let argument):
            let quantity = try evaluate(argument, depth: depth + 1)
            if function == "sqrt" {
                guard quantity.value >= 0 else { throw CalculationError.invalid("La racine carrée nécessite une valeur positive ou nulle.") }
                return try finite(Foundation.sqrt(quantity.value), dimension: quantity.dimension.scaled(by: 0.5))
            }
            if function == "abs" { return Quantity(value: abs(quantity.value), dimension: quantity.dimension) }
            guard quantity.dimension.isDimensionless else {
                throw CalculationError.invalid("La fonction \(function) nécessite un argument sans dimension. Pour un angle, utilisez rad ou deg.")
            }
            let value: Double
            switch function {
            case "sin": value = Foundation.sin(quantity.value)
            case "cos": value = Foundation.cos(quantity.value)
            case "tan":
                guard abs(Foundation.cos(quantity.value)) > 1e-14 else {
                    throw CalculationError.invalid("La tangente n’est pas définie pour cet angle.")
                }
                value = Foundation.tan(quantity.value)
            case "exp": value = Foundation.exp(quantity.value)
            case "ln", "log", "log10":
                guard quantity.value > 0 else { throw CalculationError.invalid("Un logarithme nécessite une valeur strictement positive.") }
                value = function == "ln" ? Foundation.log(quantity.value) : Foundation.log10(quantity.value)
            default:
                throw CalculationError.invalid("Fonction « \(function) » inconnue.")
            }
            return try finite(value, dimension: .dimensionless)
        }
    }

    private func finite(_ value: Double, dimension: Dimension) throws -> Quantity {
        let exponents = [dimension.length, dimension.mass, dimension.time,
                         dimension.electricCurrent, dimension.temperature,
                         dimension.amount, dimension.luminousIntensity]
        guard value.isFinite, exponents.allSatisfy(\.isFinite) else {
            throw CalculationError.invalid("Résultat non réel ou dépassement de la plage numérique. Vérifiez les valeurs et les puissances.")
        }
        return Quantity(value: value, dimension: dimension)
    }
}
