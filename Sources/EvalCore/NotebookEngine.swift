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
    /// The unit requested with `->` or `→`; the quantity itself stays in SI.
    public let displayUnit: DisplayUnit?
    /// True when `dimensionMessage` reports a dimension that was actually checked
    /// (a sum, a comparison or an equality), as opposed to merely derived.
    public let isHomogeneous: Bool
    /// True when the line asks to show its value: a final `=` (`E =`, `v → km/h =`),
    /// a display unit (`→ km/h`) or an unknown (`v = ? m/s`). A request on an
    /// equality is ignored, and comments and blank lines never request one.
    public let requestsValue: Bool
    /// The declared names this line reads, directly or through other declarations
    /// and the relations of unknowns. Constants and units that nothing declares
    /// are not listed, nor is the name a declaration defines. Empty for a sheet
    /// over the size limit.
    public let dependencies: Set<String>
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
    /// Undeclared symbols that were read as units, such as `T` as the tesla.
    /// Units written after a number (`5 m`, `72 km/h`) are not listed.
    public let symbolUnits: [UnitDefinition]
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
        guard source.count <= 100_000, sourceLines.count <= 500 else { return Self.overLimit(sourceLines) }

        var parsedLines = sourceLines.enumerated().map { ParsedLine(id: $0.offset, source: $0.element) }
        let resolver = Resolver(lines: parsedLines)
        resolver.resolveDeclarations()
        let dependencies = resolver.dependencies()
        for index in parsedLines.indices { parsedLines[index].dependencies = dependencies[index] }
        var results: [EvaluatedLine] = []

        for line in parsedLines {
            if line.kind == .empty || line.kind == .comment {
                results.append(line.result(status: .neutral))
                continue
            }
            do {
                if let name = line.name {
                    let quantity = try resolver.resolve(name, depth: 0).quantity
                    let note = dimensionNote(quantity, expression: line.left)
                    results.append(line.result(quantity: quantity, message: resolver.unknownNotes[name] ?? line.note,
                                               status: .success,
                                               dimensionMessage: note.message, isHomogeneous: note.isHomogeneous,
                                               displayUnit: try line.displayUnit(for: quantity) ?? line.unknown?.displayUnit))
                } else if let issue = line.issue {
                    throw issue
                } else if let left = line.left {
                    let lhs = try resolver.measure(left, depth: 0)
                    let quantity = lhs.quantity
                    if let right = line.right {
                        let rhs = try resolver.measure(right, depth: 0)
                        let other = rhs.quantity
                        guard quantity.dimension.isEquivalent(to: other.dimension) else {
                            throw CalculationError.invalid("Équation non homogène : le membre gauche a pour dimension \(quantity.dimension.formatted), le membre droit \(other.dimension.formatted).")
                        }
                        // A cancellation leaves a residue relative to its terms, not to its result.
                        let scale = max(abs(quantity.value), abs(other.value), lhs.scale, rhs.scale)
                        let equal = quantity.value == other.value
                            || abs(quantity.value - other.value) <= scale * 1e-10
                        let unit = try line.displayUnit(for: quantity)
                        let message = equal ? "Égalité vérifiée."
                            : "Égalité non vérifiée : \(QuantityFormatter.string(quantity, in: unit, significantDigits: QuantityFormatter.preciseDigits)) ≠ \(QuantityFormatter.string(other, in: unit, significantDigits: QuantityFormatter.preciseDigits))."
                        results.append(line.result(quantity: quantity, message: message,
                                                   status: equal ? .success : .error,
                                                   dimensionMessage: quantity.dimension.isDimensionless ? nil
                                                       : "Homogène · \(quantity.dimension.formatted)",
                                                   isHomogeneous: !quantity.dimension.isDimensionless,
                                                   displayUnit: unit))
                    } else {
                        let note = dimensionNote(quantity, expression: left)
                        results.append(line.result(quantity: quantity, message: line.note, status: .success,
                                                   dimensionMessage: note.message, isHomogeneous: note.isHomogeneous,
                                                   displayUnit: try line.displayUnit(for: quantity)))
                    }
                }
            } catch {
                results.append(line.result(message: error.localizedDescription, status: .error))
            }
        }

        let variables = resolver.orderedNames.compactMap { name -> ResolvedVariable? in
            guard let quantity = resolver.cache[name]?.quantity else { return nil }
            return ResolvedVariable(name: name, quantity: quantity)
        }
        return NotebookEvaluation(lines: results, constants: resolver.usedConstants, variables: variables,
                                  symbolUnits: resolver.usedUnits)
    }

    /// Keeps one unevaluated result per line, so results still pair with
    /// their rows, and reports the limit on the first formula line.
    private static func overLimit(_ sourceLines: [String]) -> NotebookEvaluation {
        let kinds = sourceLines.map { source -> LineKind in
            let line = LineSyntax(source)
            if line.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .comment
            }
            if line.definitionName != nil { return .definition }
            return line.separatorRange == nil ? .expression : .equation
        }
        let errorIndex = kinds.firstIndex { $0 != .empty && $0 != .comment }
            ?? kinds.firstIndex { $0 != .empty } ?? 0
        let lines = sourceLines.enumerated().map { index, source in
            let requests = kinds[index] != .empty && kinds[index] != .comment && LineSyntax(source).requestsValue
                && !(kinds[index] == .equation && LineSyntax(source).arrowRange == nil)
            guard index == errorIndex else {
                return EvaluatedLine(id: index, source: source, kind: kinds[index], quantity: nil,
                                     message: nil, status: .neutral, dimensionMessage: nil, displayUnit: nil,
                                     isHomogeneous: false, requestsValue: requests, dependencies: [])
            }
            // A comment would not be listed among the results.
            let kind = kinds[index] == .empty || kinds[index] == .comment ? .expression : kinds[index]
            return EvaluatedLine(id: index, source: source, kind: kind, quantity: nil,
                                 message: "Feuille trop longue (500 lignes et 100 000 caractères maximum).",
                                 status: .error, dimensionMessage: nil, displayUnit: nil, isHomogeneous: false,
                                 requestsValue: requests, dependencies: [])
        }
        return NotebookEvaluation(lines: lines, constants: [], variables: [], symbolUnits: [])
    }

    private func dimensionNote(_ quantity: Quantity, expression: Expression?) -> (message: String?, isHomogeneous: Bool) {
        guard !quantity.dimension.isDimensionless else { return (nil, false) }
        let checked = expression?.checksHomogeneity == true
        return ("\(checked ? "Homogène" : "Dimension") · \(quantity.dimension.formatted)", checked)
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
    /// An informational remark shown with a successful result.
    var note: String?
    /// The unit after the arrow. Its problems fail this line only: dependents
    /// read `issue`, never `conversionIssue`.
    var conversion: Expression?
    var conversionSymbol = ""
    var conversionIssue: CalculationError?
    /// Set for `name = ? unit`: the engine solves for `name` from one relation.
    var unknown: UnknownSpec?
    /// A final `=` asks to show the value. Ignored on an equality.
    private let requestsResult: Bool
    private let requestsConversionOrUnknown: Bool
    var dependencies: Set<String> = []

    /// Whether the line asks to show its value; nothing is requested of notes and blank lines.
    var requestsValue: Bool {
        guard kind != .empty, kind != .comment else { return false }
        return (requestsResult && kind != .equation) || requestsConversionOrUnknown
    }

    init(id: Int, source: String) {
        self.id = id
        self.source = source
        let syntax = LineSyntax(source)
        requestsResult = syntax.requestsResult
        requestsConversionOrUnknown = syntax.arrowRange != nil || syntax.unknownUnit != nil
        if syntax.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            kind = source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? .empty : .comment
            return
        }
        parseConversion(syntax)

        do {
            let content = syntax.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !content.isEmpty else {
                throw CalculationError.invalid("Il manque l’expression à convertir avant →.")
            }
            let separators = LineSyntax.separators(in: content[...])
            let lhs = separators.first.map { content[..<$0.lowerBound].trimmingCharacters(in: .whitespaces) } ?? ""
            let declares = separators.first.map { content[$0] == "=" } == true && ExpressionParser.isIdentifier(lhs)
            if declares {
                kind = .definition
                name = lhs
            }
            if separators.count > 1 {
                throw CalculationError.invalid("Une ligne doit contenir une seule déclaration ou égalité.")
            }
            if let separator = separators.first {
                let rhs = content[separator.upperBound...].trimmingCharacters(in: .whitespaces)
                if declares {
                    guard !rhs.isEmpty else { throw CalculationError.invalid("Il manque la valeur de « \(lhs) » après le signe =.") }
                    if let unit = syntax.unknownUnit {
                        unknown = try UnknownSpec(unit: unit)
                        return
                    }
                    var parser = try ExpressionParser(rhs)
                    left = try parser.parse()
                } else {
                    kind = .equation
                    guard !lhs.isEmpty, !rhs.isEmpty else {
                        throw CalculationError.invalid("Une égalité nécessite une expression de chaque côté.")
                    }
                    if content[separator] == "=", content[content.index(before: separator.lowerBound)] == "!" {
                        throw CalculationError.invalid("Utilisez == pour comparer ; ≠ n’est pas pris en charge.")
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
            if right == nil { note = left?.radianNote }
        } catch let error as CalculationError {
            issue = error
        } catch {
            issue = .invalid(error.localizedDescription)
        }
    }

    private mutating func parseConversion(_ syntax: LineSyntax) {
        guard syntax.arrowRange != nil else { return }
        guard syntax.arrowCount == 1 else {
            conversionIssue = .invalid("Une seule conversion → par ligne.")
            return
        }
        guard let target = syntax.conversion, !target.isEmpty else {
            conversionIssue = .invalid("Indiquez l’unité d’affichage après →, par exemple → km/h.")
            return
        }
        do {
            var parser = try ExpressionParser(target)
            conversion = try parser.parse()
            conversionSymbol = target.replacingOccurrences(of: "*", with: "·")
        } catch let error as CalculationError {
            conversionIssue = error
        } catch {
            conversionIssue = .invalid(error.localizedDescription)
        }
    }

    /// The unit requested for this result, checked against the result's dimension.
    func displayUnit(for quantity: Quantity) throws -> DisplayUnit? {
        if let conversionIssue { throw conversionIssue }
        guard let conversion else { return nil }
        let unit = try NotebookEngine.displayUnit(conversion, symbol: conversionSymbol, for: quantity.dimension)
        guard (quantity.value / unit.scale).isFinite else {
            throw CalculationError.invalid("Le résultat converti dépasse la plage numérique.")
        }
        return unit
    }

    func result(quantity: Quantity? = nil, message: String? = nil, status: LineStatus,
                dimensionMessage: String? = nil, isHomogeneous: Bool = false,
                displayUnit: DisplayUnit? = nil) -> EvaluatedLine {
        EvaluatedLine(id: id, source: source, kind: kind, quantity: quantity,
                      message: message, status: status, dimensionMessage: dimensionMessage,
                      displayUnit: displayUnit, isHomogeneous: isHomogeneous,
                      requestsValue: requestsValue, dependencies: dependencies)
    }
}

/// The unit written after `?` in `v = ? m/s`: it fixes the unknown's dimension
/// and the unit in which the solution is searched and shown.
private struct UnknownSpec {
    /// As typed, with `·` for `*`; empty for a dimensionless unknown.
    let symbol: String
    let unit: Quantity

    init(unit text: String) throws {
        guard !text.isEmpty else {
            symbol = ""
            unit = Quantity(value: 1)
            return
        }
        guard let quantity = NotebookEngine.unitQuantity(of: text), quantity.value.isFinite, quantity.value > 0 else {
            throw CalculationError.invalid("L’unité « \(text) » de l’inconnue n’est pas reconnue. Écrivez seulement une unité, par exemple v = ? m/s.")
        }
        symbol = text.replacingOccurrences(of: "*", with: "·")
        unit = quantity
    }

    /// The solution is shown in the unit that was asked for.
    var displayUnit: DisplayUnit? {
        symbol.isEmpty ? nil : DisplayUnit(symbol: symbol, scale: unit.value)
    }

    func formatted(_ value: Double) -> String {
        QuantityFormatter.number(value) + (symbol.isEmpty ? "" : (symbol == "°" ? "" : " ") + symbol)
    }
}

/// A catalogue entry that an undeclared name resolved to.
private struct Used {
    let key: String
    var constant: ConstantDefinition?
    var unit: UnitDefinition?

    init(_ constant: ConstantDefinition) {
        key = "c:" + constant.id
        self.constant = constant
    }

    init(_ unit: UnitDefinition) {
        key = "u:" + unit.symbol
        self.unit = unit
    }
}

private final class Resolver {
    private var definitions: [String: [ParsedLine]] = [:]
    private var visiting: [String] = []
    private var failures: [String: CalculationError] = [:]
    /// Constants and symbol units met while evaluating each remembered
    /// declaration. Replaying them on a cache hit lists them in order of first
    /// use in the sheet.
    private var constantTrails: [String: [Used]] = [:]
    /// Symbols met by the evaluations in progress, innermost last.
    private var trails: [[Used]] = [[]]
    private(set) var orderedNames: [String] = []
    private(set) var cache: [String: Measured] = [:]
    private let lines: [ParsedLine]
    /// The unknown being solved, so that a second one met meanwhile can be reported.
    private var solving: String?
    private var nestedUnknown: String?
    /// What was found besides the value: the other root, or a warning.
    private(set) var unknownNotes: [String: String] = [:]

    var usedConstants: [ConstantDefinition] { trails[0].compactMap(\.constant) }
    var usedUnits: [UnitDefinition] { trails[0].compactMap(\.unit) }

    init(lines: [ParsedLine]) {
        self.lines = lines
        for line in lines {
            guard let name = line.name else { continue }
            if definitions[name] == nil { orderedNames.append(name) }
            definitions[name, default: []].append(line)
        }
    }

    /// Resolves each declaration after the declarations it uses, with an
    /// explicit stack. Later lookups hit the cache, so declaration order never
    /// consumes the depth budget and recursion stays shallow.
    func resolveDeclarations() {
        var finished: [String: Bool] = [:] // false while its dependencies are pending
        for root in orderedNames {
            var stack = [(name: root, isReady: false)]
            while let entry = stack.popLast() {
                if entry.isReady {
                    trails.append([])
                    _ = try? resolve(entry.name, depth: 0)
                    trails.removeLast()
                    finished[entry.name] = true
                    continue
                }
                guard finished[entry.name] == nil, definitions[entry.name]?.count == 1,
                      let expression = definitions[entry.name]?.first?.left else { continue }
                finished[entry.name] = false
                stack.append((entry.name, true))
                for name in Self.references(in: expression) where finished[name] == nil {
                    stack.append((name, false))
                }
            }
        }
    }

    /// For each line, the declared names it reads and everything those read in turn.
    /// The unknown `v = ? m/s` reads what the relations that contain it read.
    /// The transitive reads of each declared name are computed once (see `closures(of:)`)
    /// and united per line.
    func dependencies() -> [Set<String>] {
        var reads: [String: Set<String>] = [:]
        func declared(_ expressions: [Expression]) -> Set<String> {
            var names = Set<String>()
            for expression in expressions {
                for name in Self.references(in: expression) where definitions[name] != nil { names.insert(name) }
            }
            return names
        }
        for (name, declarations) in definitions {
            var found = Set<String>()
            for declaration in declarations {
                if let expression = declaration.left { found.formUnion(declared([expression])) }
                if declaration.unknown != nil { found.formUnion(unknownReads(of: name)) }
            }
            reads[name] = found
        }
        let closure = Self.closures(of: reads)
        return lines.map { line in
            guard line.kind != .empty, line.kind != .comment else { return [] }
            var direct = declared([line.left, line.right].compactMap { $0 })
            if let name = line.name, line.unknown != nil { direct.formUnion(unknownReads(of: name)) }
            var result = Set<String>()
            for name in direct where !result.contains(name) {
                // A closure is transitively closed: a name already in `result` brought its own reads.
                result.insert(name)
                if let reached = closure[name] { result.formUnion(reached) }
            }
            // A declaration is not its own dependency, even through a cycle.
            if line.kind == .definition, let name = line.name { result.remove(name) }
            return result
        }
    }

    /// For each name, everything reachable through `reads` in one step or more; a name is in
    /// its own closure only on a cycle. Strongly connected components are found with an
    /// explicit stack (Tarjan), so a component shares one closure and cycles end.
    private static func closures(of reads: [String: Set<String>]) -> [String: Set<String>] {
        var order: [String: Int] = [:], low: [String: Int] = [:]
        var open: [String] = [], isOpen = Set<String>()
        var result: [String: Set<String>] = [:]
        for root in reads.keys where order[root] == nil {
            var frames: [(name: String, next: [String], position: Int)] = []
            func visit(_ name: String) {
                order[name] = order.count
                low[name] = order[name]
                open.append(name)
                isOpen.insert(name)
                frames.append((name, Array(reads[name] ?? []), 0))
            }
            visit(root)
            while !frames.isEmpty {
                let top = frames.count - 1
                let (name, next, position) = frames[top]
                if position < next.count {
                    frames[top].position += 1
                    let successor = next[position]
                    if order[successor] == nil {
                        visit(successor)
                    } else if isOpen.contains(successor) {
                        low[name] = min(low[name]!, order[successor]!)
                    }
                    continue
                }
                frames.removeLast()
                if let parent = frames.last?.name { low[parent] = min(low[parent]!, low[name]!) }
                guard low[name] == order[name] else { continue }
                var members = Set<String>()
                while let member = open.popLast() {
                    isOpen.remove(member)
                    members.insert(member)
                    if member == name { break }
                }
                var reached = Set<String>()
                if members.count > 1 || reads[name]?.contains(name) == true { reached = members }
                for member in members {
                    for successor in reads[member] ?? [] where !members.contains(successor) && !reached.contains(successor) {
                        reached.insert(successor)
                        reached.formUnion(result[successor] ?? [])
                    }
                }
                for member in members { result[member] = reached }
            }
        }
        return result
    }

    /// The declared names read by the relations (`==` lines) that contain an unknown
    /// or one of the declarations that depend on it.
    private func unknownReads(of name: String) -> Set<String> {
        let family = Set(dependents(of: name) + [name])
        var names = Set<String>()
        for line in lines where line.kind == .equation {
            guard let left = line.left, let right = line.right else { continue }
            let references = Self.references(in: left) + Self.references(in: right)
            guard !family.isDisjoint(with: references) else { continue }
            for reference in references where definitions[reference] != nil { names.insert(reference) }
        }
        return names
    }

    // resolve, reference and measure call one another for every dependency
    // and every level of an expression: diagnostics and arithmetic live in
    // separate functions to keep these stack frames small.

    func resolve(_ name: String, depth: Int) throws -> Measured {
        if let value = cache[name] {
            note(constantTrails[name] ?? [])
            return value
        }
        if let failure = failures[name] {
            note(constantTrails[name] ?? [])
            throw failure
        }
        guard definitions[name] != nil else { return try catalogValue(name) }
        if let declarations = definitions[name], declarations.count == 1, let unknown = declarations[0].unknown {
            return try resolveUnknown(name, declarations[0], unknown)
        }
        let expression = try declaredExpression(name, depth: depth)
        visiting.append(name)
        trails.append([])
        var remembers = false
        defer {
            visiting.removeLast()
            let trail = trails.removeLast()
            if remembers { constantTrails[name] = trail }
            note(trail)
        }
        do {
            let value = try measure(expression, depth: depth + 1)
            cache[name] = value
            remembers = true
            return value
        } catch let error as CalculationError {
            // Entered deeper, a declaration lies on a cycle: its error
            // depends on where evaluation started and is not remembered.
            if depth == 0, !error.isCircular {
                failures[name] = error
                remembers = true
            }
            throw error
        }
    }

    private func declaredExpression(_ name: String, depth: Int) throws -> Expression {
        let declarations = definitions[name] ?? []
        guard declarations.count == 1, let declaration = declarations.first else {
            let numbers = declarations.map { String($0.id + 1) }.joined(separator: ", ")
            throw CalculationError.invalid("« \(name) » est déclaré plusieurs fois (lignes \(numbers)). Conservez une seule déclaration.")
        }
        if let cycleStart = visiting.firstIndex(of: name) {
            let path = (Array(visiting[cycleStart...]) + [name]).joined(separator: " → ")
            throw CalculationError.circular("Dépendance circulaire : \(path).")
        }
        // Declarations resolve bottom-up first, so only a long cycle gets this deep.
        guard depth <= 100 else { throw CalculationError.circular("Dépendances trop imbriquées ou circulaires.") }
        if let issue = declaration.issue { throw issue }
        guard let expression = declaration.left else {
            throw CalculationError.invalid("La déclaration de « \(name) » ne contient pas d’expression valide.")
        }
        return expression
    }

    // MARK: - Unknowns

    /// Declarations that read each name, to find what depends on an unknown.
    private lazy var readers: [String: [String]] = {
        var table: [String: [String]] = [:]
        for (name, declarations) in definitions where declarations.count == 1 {
            guard let expression = declarations[0].left else { continue }
            for reference in Set(Self.references(in: expression)) { table[reference, default: []].append(name) }
        }
        return table
    }()

    /// The declarations that depend on `name`, each after what it reads.
    private func dependents(of name: String) -> [String] {
        var members: Set<String> = [name]
        var pending = [name]
        while let next = pending.popLast() {
            for reader in readers[next] ?? [] where members.insert(reader).inserted { pending.append(reader) }
        }
        members.remove(name)
        var order: [String] = []
        var done = Set<String>()
        for root in members.sorted() {
            var stack = [(name: root, isReady: false)]
            while let entry = stack.popLast() {
                if entry.isReady { order.append(entry.name); continue }
                guard done.insert(entry.name).inserted, let expression = definitions[entry.name]?.first?.left else { continue }
                stack.append((entry.name, true))
                for reference in Self.references(in: expression) where members.contains(reference) && !done.contains(reference) {
                    stack.append((reference, false))
                }
            }
        }
        return order
    }

    private func forget(_ names: [String]) {
        for name in names {
            cache[name] = nil
            failures[name] = nil
            constantTrails[name] = nil
        }
    }

    /// Solves `name = ? unit` from the one relation that reads it. A separate
    /// function keeps `resolve`, which recurses for every dependency, small.
    @inline(never)
    private func resolveUnknown(_ name: String, _ line: ParsedLine, _ spec: UnknownSpec) throws -> Measured {
        if let current = solving, current != name {
            nestedUnknown = name
            throw CalculationError.invalid("Une seule inconnue par relation.")
        }
        let dependents = dependents(of: name)
        let family = Set(dependents + [name])
        let relations = lines.filter { candidate in
            guard candidate.kind == .equation, let left = candidate.left, let right = candidate.right else { return false }
            return !family.isDisjoint(with: Self.references(in: left) + Self.references(in: right))
        }
        let saved = visiting
        visiting = []
        solving = name
        trails.append([])
        var outcome: Result<(value: Measured, note: String?), CalculationError>
        do {
            outcome = .success(try solve(name, spec, relations: relations, dependents: dependents))
        } catch let error as CalculationError {
            outcome = .failure(error)
        } catch {
            outcome = .failure(.invalid(error.localizedDescription))
        }
        solving = nil
        visiting = saved
        forget(dependents)
        cache[name] = nil
        let trail = trails.removeLast()
        let nested = nestedUnknown
        nestedUnknown = nil
        defer { note(trail) }
        switch outcome {
        case .success(let solution):
            cache[name] = solution.value
            constantTrails[name] = trail
            unknownNotes[name] = solution.note
            return solution.value
        case .failure(var error):
            if let nested {
                error = Self.severalUnknowns(name, nested)
            }
            if !error.isCircular { failures[name] = error }
            constantTrails[name] = trail
            throw error
        }
    }

    private static func severalUnknowns(_ name: String, _ other: String) -> CalculationError {
        .invalid("La relation de « \(name) » contient aussi l’inconnue « \(other) » : une seule inconnue par relation.")
    }

    private func solve(_ name: String, _ spec: UnknownSpec, relations: [ParsedLine],
                       dependents: [String]) throws -> (value: Measured, note: String?) {
        guard let relation = relations.first, let left = relation.left, let right = relation.right else {
            throw CalculationError.invalid("Aucune relation ne permet de calculer « \(name) ». Ajoutez une ligne avec == qui contient \(name), par exemple 1000 J == 0,5 * m * \(name)².")
        }
        guard relations.count == 1 else {
            let numbers = relations.map { String($0.id + 1) }.joined(separator: ", ")
            throw CalculationError.invalid("Plusieurs relations contiennent « \(name) » (lignes \(numbers)). Gardez une seule relation avec == pour le calculer.")
        }
        let others = Set(Self.references(in: left) + Self.references(in: right)).filter {
            $0 != name && definitions[$0]?.count == 1 && definitions[$0]?[0].unknown != nil
        }
        if let other = others.min() { throw Self.severalUnknowns(name, other) }
        let (dimension, scale) = (spec.unit.dimension, spec.unit.value)
        var firstError: CalculationError?
        var search = RootSearch { [self] trial in
            forget(dependents)
            let probe = trial * scale
            guard probe.isFinite else { return nil }
            cache[name] = Measured(Quantity(value: probe, dimension: dimension))
            for dependent in dependents { _ = try? resolve(dependent, depth: 0) }
            let sides: (Measured, Measured)
            do {
                sides = (try measure(left, depth: 0), try measure(right, depth: 0))
            } catch let error as CalculationError {
                firstError = firstError ?? error
                return nil
            }
            guard sides.0.dimension.isEquivalent(to: sides.1.dimension) else {
                let unit = spec.symbol.isEmpty ? "sans unité" : "en \(spec.symbol)"
                throw CalculationError.invalid("Équation non homogène : le membre gauche a pour dimension \(sides.0.dimension.formatted), le membre droit \(sides.1.dimension.formatted), avec \(name) \(unit).")
            }
            let difference = sides.0.value - sides.1.value
            return difference.isFinite ? difference : nil
        }
        let found = try search.run()
        guard found.valid > 0 else {
            let reason = firstError?.localizedDescription ?? "Aucune valeur n’a pu être calculée."
            throw CalculationError.invalid("La relation de la ligne \(relation.id + 1) ne peut pas être évaluée pour « \(name) » : \(reason)")
        }
        guard let root = found.positive ?? found.negative else {
            let unit = spec.symbol.isEmpty ? "" : " " + spec.symbol
            throw CalculationError.invalid("Aucune solution trouvée entre 10⁻¹² et 10¹²\(unit).")
        }
        var notes: [String] = []
        if found.positive != nil, let other = found.negative { notes.append("Autre solution : \(spec.formatted(other)).") }
        if found.hasMore { notes.append("D’autres solutions sont possibles ; la plus proche de zéro est affichée.") }
        return (Measured(Quantity(value: root * scale, dimension: dimension)), notes.isEmpty ? nil : notes.joined(separator: " "))
    }

    private func catalogValue(_ name: String) throws -> Measured {
        if let constant = ConstantCatalog.lookup(name) {
            note([Used(constant)])
            return Measured(constant.quantity)
        }
        if let unit = UnitCatalog.lookup(name) {
            // 35 % and 30° are notation, like a suffix after a number: not listed.
            if !Self.notationSymbols.contains(unit.symbol) { note([Used(unit)]) }
            return Measured(unit.quantity)
        }
        throw CalculationError.invalid(Diagnostics.unknownSymbol(name))
    }

    private static let notationSymbols: Set<String> = ["%", "deg"]

    private func note(_ symbols: [Used]) {
        for symbol in symbols where !trails[trails.count - 1].contains(where: { $0.key == symbol.key }) {
            trails[trails.count - 1].append(symbol)
        }
    }

    /// Identifiers in reading order, collected without recursion.
    private static func references(in expression: Expression) -> [String] {
        var names: [String] = []
        var pending = [expression]
        while let next = pending.popLast() {
            switch next {
            case .identifier(let name): names.append(name)
            case .unary(_, let argument), .factorial(let argument): pending.append(argument)
            case .function(_, let arguments): pending.append(contentsOf: arguments.reversed())
            case .binary(_, let left, let right): pending.append(contentsOf: [right, left])
            case .compactUnits(let units):
                names.append(contentsOf: unitSymbols(in: units))
                pending.append(units)
            case .number, .unit: break
            }
        }
        return names
    }

    private static func unitSymbols(in expression: Expression) -> [String] {
        var symbols: [String] = []
        var pending = [expression]
        while let next = pending.popLast() {
            switch next {
            case .unit(let symbol): symbols.append(symbol)
            case .binary(_, let left, let right): pending.append(contentsOf: [right, left])
            default: break
            }
        }
        return symbols
    }

    /// A compact chain with a declared symbol keeps its former reading as variables.
    private static func variables(_ units: Expression) -> Expression {
        switch units {
        case .unit(let symbol): return .identifier(symbol)
        case .binary(let operation, let left, let right):
            return .binary(operation, variables(left), operation == .power ? right : variables(right))
        default: return units
        }
    }

    func measure(_ expression: Expression, depth: Int) throws -> Measured {
        guard depth <= 200 else { throw Self.tooComplex }
        switch expression {
        case .number(let value):
            return Measured(Quantity(value: value))
        case .identifier(let name):
            return try reference(name, depth: depth + 1)
        case .unit(let symbol):
            return try Self.unit(symbol)
        case .unary(let operation, let argument):
            return Self.signed(try measure(argument, depth: depth + 1), negated: operation == .minus)
        case .binary(let operation, let left, let right):
            return try combine(operation, try measure(left, depth: depth + 1), try measure(right, depth: depth + 1),
                               base: left, exponent: right)
        case .function(let function, let arguments):
            return try call(function, arguments, depth: depth)
        case .factorial(let argument):
            return try factorial(try measure(argument, depth: depth + 1))
        case .compactUnits(let units):
            return try measure(compactReading(units), depth: depth + 1)
        }
    }

    private static let tooComplex = CalculationError.invalid("Expression trop complexe (200 niveaux maximum).")

    private func reference(_ name: String, depth: Int) throws -> Measured {
        do {
            return try resolve(name, depth: depth)
        } catch let error as CalculationError {
            throw attributed(error, to: name)
        }
    }

    /// A declaration's own diagnostic, and its column, belong to its line.
    private func attributed(_ error: CalculationError, to name: String) -> CalculationError {
        guard let declarations = definitions[name], declarations.count == 1, !error.isAttributed else { return error }
        return .dependency("La déclaration de « \(name) » (ligne \(declarations[0].id + 1)) contient une erreur.")
    }

    private static func unit(_ symbol: String) throws -> Measured {
        guard let unit = UnitCatalog.lookup(symbol) else {
            throw CalculationError.invalid("Unité « \(symbol) » inconnue.")
        }
        return Measured(unit.quantity)
    }

    private static func signed(_ operand: Measured, negated: Bool) -> Measured {
        Measured(Quantity(value: negated ? -operand.value : operand.value, dimension: operand.dimension),
                 scale: operand.scale)
    }

    /// 72km/h reads as units unless the sheet declares one of its symbols.
    private func compactReading(_ units: Expression) -> Expression {
        Self.unitSymbols(in: units).contains { definitions[$0] != nil } ? Self.variables(units) : units
    }

    private func combine(_ operation: Expression.BinaryOperator, _ lhs: Measured, _ rhs: Measured,
                         base: Expression, exponent: Expression) throws -> Measured {
        let (a, b) = (lhs.value, rhs.value)
        switch operation {
        case .add, .subtract:
            guard lhs.dimension.isEquivalent(to: rhs.dimension) else {
                throw CalculationError.invalid("Addition ou soustraction non homogène : impossible de combiner \(lhs.dimension.formatted) et \(rhs.dimension.formatted).")
            }
            let term = operation == .add ? b : -b
            let sum = a + term
            return try finite(sum, dimension: lhs.dimension,
                              scale: lhs.scale + rhs.scale + Self.rounding(sum, exact: Self.isExactSum(a, term, sum)))
        case .multiply:
            let product = a * b
            return try finite(product, dimension: lhs.dimension + rhs.dimension,
                              scale: abs(a) * rhs.scale + abs(b) * lhs.scale
                                  + Self.rounding(product, exact: (-product).addingProduct(a, b) == 0))
        case .divide:
            guard b != 0 else { throw CalculationError.invalid("Division par zéro.") }
            let quotient = a / b
            return try finite(quotient, dimension: lhs.dimension - rhs.dimension,
                              scale: (lhs.scale + abs(quotient) * rhs.scale) / abs(b)
                                  + Self.rounding(quotient, exact: (-a).addingProduct(quotient, b) == 0))
        case .power:
            // e^(−t/τ) means the exponential, but e is the elementary charge here.
            if case .identifier("e") = base, definitions["e"] == nil,
               !(exponent.isNumericExpression && Measured.isExactInteger(b)) {
                throw CalculationError.invalid("Ici, e désigne la charge élémentaire. Pour l’exponentielle, écrivez exp(…) ou euler^(…).")
            }
            guard rhs.dimension.isDimensionless else {
                throw CalculationError.invalid("Un exposant doit être sans dimension.")
            }
            guard !(a == 0 && b <= 0) else {
                throw CalculationError.invalid("Zéro ne peut pas être élevé à une puissance nulle ou négative.")
            }
            guard abs(b) <= 10_000 else {
                throw CalculationError.invalid("Exposant trop grand (valeur absolue maximale : 10 000).")
            }
            let power = Foundation.pow(a, b)
            // A base known within ε gives aᵇ within |b·aᵇ/a|·ε, or within εᵇ around 0.
            let propagated = a == 0
                ? Foundation.pow(lhs.scale * Self.unitRoundoff, b) / Self.unitRoundoff
                : abs(power) * (abs(b) * lhs.scale / abs(a) + abs(Foundation.log(abs(a))) * rhs.scale)
            let exact = b >= 0 && [a, b, power].allSatisfy(Measured.isExactInteger)
            return try finite(power, dimension: lhs.dimension.scaled(by: b),
                              scale: propagated + Self.rounding(power, exact: exact))
        }
    }

    /// Evaluates the arguments, then applies the function. A separate function
    /// keeps `measure`, which recurses for every nesting level, small.
    private func call(_ function: String, _ arguments: [Expression], depth: Int) throws -> Measured {
        var values: [Measured] = []
        values.reserveCapacity(arguments.count)
        for argument in arguments { values.append(try measure(argument, depth: depth + 1)) }
        return values.count == 1 ? try apply(function, to: values[0]) : try apply(function, to: values)
    }

    private func apply(_ function: String, to argument: Measured) throws -> Measured {
        let x = argument.value
        if function == "sqrt" {
            guard x >= 0 else { throw CalculationError.invalid("La racine carrée nécessite une valeur positive ou nulle.") }
            let root = Foundation.sqrt(x)
            // An argument known within ε gives √x within min(ε/(2√x), √ε).
            let bound = (argument.scale / Self.unitRoundoff).squareRoot()
            let propagated = root > 0 ? min(argument.scale / (2 * root), bound) : bound
            return try finite(root, dimension: argument.dimension.scaled(by: 0.5),
                              scale: propagated + Self.rounding(root, exact: (-x).addingProduct(root, root) == 0))
        }
        if function == "abs" {
            return Measured(Quantity(value: abs(x), dimension: argument.dimension), scale: argument.scale)
        }
        if function == "cbrt" { return try root(argument, index: 3) }
        guard argument.dimension.isDimensionless else { throw Diagnostics.dimensionalArgument(function) }
        let value: Double
        let slope: Double // |f′(x)| carries the argument's own magnitude.
        var exact = false
        switch function {
        case "sin", "cos", "tan":
            (value, exact) = try Self.trigonometric(function, x)
            slope = function == "tan" ? 1 + value * value : 1
        case "exp":
            value = Foundation.exp(x)
            slope = value
        case "ln", "log", "log10":
            guard x > 0 else { throw CalculationError.invalid("Un logarithme nécessite une valeur strictement positive.") }
            value = function == "ln" ? Foundation.log(x) : Foundation.log10(x)
            slope = function == "ln" ? 1 / x : 1 / (x * M_LN10)
        case "asin", "acos":
            guard abs(x) <= 1 else {
                throw CalculationError.invalid("\(function) nécessite une valeur comprise entre −1 et 1.")
            }
            value = function == "asin" ? Foundation.asin(x) : Foundation.acos(x)
            slope = 1 / (1 - x * x).squareRoot()
        case "atan":
            value = Foundation.atan(x)
            slope = 1 / (1 + x * x)
        case "sinh", "cosh", "tanh":
            value = function == "sinh" ? Foundation.sinh(x) : function == "cosh" ? Foundation.cosh(x) : Foundation.tanh(x)
            slope = function == "sinh" ? Foundation.cosh(x) : function == "cosh" ? abs(Foundation.sinh(x)) : 1 - value * value
        case "floor", "ceil", "round":
            // Rounding discontinuities are the user's choice: the result is exact.
            value = function == "floor" ? Foundation.floor(x) : function == "ceil" ? Foundation.ceil(x) : Foundation.round(x)
            slope = 0
            exact = true
        default:
            throw CalculationError.invalid("Fonction « \(function) » inconnue.")
        }
        return try finite(value, dimension: .dimensionless,
                          scale: abs(slope) * argument.scale + Self.rounding(value, exact: exact))
    }

    /// Functions of several arguments: min, max, atan2, root and log with a base.
    private func apply(_ function: String, to arguments: [Measured]) throws -> Measured {
        let first = arguments[0]
        switch function {
        case "min", "max":
            var best = first
            for other in arguments.dropFirst() {
                guard other.dimension.isEquivalent(to: first.dimension) else {
                    throw CalculationError.invalid("\(function) compare des grandeurs de même dimension : impossible de comparer \(first.dimension.formatted) et \(other.dimension.formatted).")
                }
                if function == "min" ? other.value < best.value : other.value > best.value { best = other }
            }
            return best
        case "atan2":
            let (y, x) = (first, arguments[1])
            guard y.dimension.isEquivalent(to: x.dimension) else {
                throw CalculationError.invalid("atan2(y; x) nécessite deux grandeurs de même dimension : \(y.dimension.formatted) et \(x.dimension.formatted).")
            }
            guard y.value != 0 || x.value != 0 else { throw CalculationError.invalid("atan2(0 ; 0) n’est pas défini.") }
            let value = Foundation.atan2(y.value, x.value)
            let sensitivity = (y.scale * abs(x.value) + x.scale * abs(y.value)) / (x.value * x.value + y.value * y.value)
            return try finite(value, dimension: .dimensionless, scale: sensitivity + Self.rounding(value, exact: false))
        case "root":
            let index = arguments[1]
            guard index.dimension.isDimensionless, Measured.isExactInteger(index.value),
                  (2...1000).contains(index.value) else {
                throw CalculationError.invalid("L’indice d’une racine doit être un entier sans dimension compris entre 2 et 1000.")
            }
            return try root(first, index: Int(index.value))
        default: // log(x; b)
            guard first.dimension.isDimensionless, arguments[1].dimension.isDimensionless else {
                throw Diagnostics.dimensionalArgument(function)
            }
            let (x, base) = (first.value, arguments[1].value)
            guard base > 0, base != 1 else {
                throw CalculationError.invalid("La base d’un logarithme doit être strictement positive et différente de 1.")
            }
            guard x > 0 else { throw CalculationError.invalid("Un logarithme nécessite une valeur strictement positive.") }
            let value = base == 2 ? Foundation.log2(x) : base == 10 ? Foundation.log10(x) : Foundation.log(x) / Foundation.log(base)
            let slope = 1 / (x * abs(Foundation.log(base)))
            return try finite(value, dimension: .dimensionless,
                              scale: slope * first.scale + Self.rounding(value, exact: false))
        }
    }

    /// The real nth root, so cbrt(−8 m³) is −2 m. The dimension is divided by n.
    private func root(_ argument: Measured, index: Int) throws -> Measured {
        let n = Double(index)
        let x = argument.value
        guard x >= 0 || index % 2 == 1 else {
            throw CalculationError.invalid("Une racine d’indice pair nécessite une valeur positive ou nulle.")
        }
        var root = Foundation.pow(abs(x), 1 / n)
        // Perfect powers come out exact (27 → 3, not 3.0000000000000004).
        let nearest = root.rounded()
        let exact = Foundation.pow(nearest, n) == abs(x)
        if exact { root = nearest }
        let value = x < 0 ? -root : root
        // A relative error ε on x gives ε/n on the root.
        let propagated = x == 0 ? Foundation.pow(argument.scale, 1 / n) : root * argument.scale / (n * abs(x))
        return try finite(value, dimension: argument.dimension.scaled(by: 1 / n),
                          scale: propagated + Self.rounding(value, exact: exact))
    }

    private func factorial(_ argument: Measured) throws -> Measured {
        let x = argument.value
        guard argument.dimension.isDimensionless, x == x.rounded(), (0...170).contains(x) else {
            throw CalculationError.invalid("La factorielle nécessite un entier sans dimension compris entre 0 et 170.")
        }
        var product = 1.0
        if x >= 2 { for factor in 2...Int(x) { product *= Double(factor) } }
        return try finite(product, dimension: .dimensionless, scale: Self.rounding(product, exact: x <= 22))
    }

    /// Multiples of a quarter turn are exact, so sin(π) and cos(90 deg) give 0
    /// rather than the rounding of π. Other angles keep the system functions.
    /// The snap tolerance is a few ulps of the turn count, not a relative error:
    /// a relative one would swallow real offsets such as 1e-4 near 1e9 turns.
    private static func trigonometric(_ function: String, _ x: Double) throws -> (value: Double, exact: Bool) {
        let quarters = x / (Double.pi / 2)
        let turn = quarters.rounded()
        if turn != 0, abs(turn) <= 1e9, abs(quarters - turn) <= 8 * quarters.ulp {
            let index = (Int(turn.truncatingRemainder(dividingBy: 4)) + 4) % 4
            switch function {
            case "sin": return ([0, 1, 0, -1][index], true)
            case "cos": return ([1, 0, -1, 0][index], true)
            default:
                guard index % 2 == 0 else { throw CalculationError.invalid("La tangente n’est pas définie pour cet angle.") }
                return (0, true)
            }
        }
        switch function {
        case "sin": return (Foundation.sin(x), false)
        case "cos": return (Foundation.cos(x), false)
        default:
            guard abs(Foundation.cos(x)) > 1e-14 else {
                throw CalculationError.invalid("La tangente n’est pas définie pour cet angle.")
            }
            return (Foundation.tan(x), false)
        }
    }

    private static let unitRoundoff = Double.ulpOfOne / 2

    /// The magnitude that rounding a result contributes, unless it was exact.
    private static func rounding(_ value: Double, exact: Bool) -> Double {
        exact ? 0 : abs(value)
    }

    /// Error-free transformation (TwoSum): the rounding error of a + b, exactly.
    private static func isExactSum(_ a: Double, _ b: Double, _ sum: Double) -> Bool {
        let virtualB = sum - a
        let virtualA = sum - virtualB
        return (a - virtualA) + (b - virtualB) == 0
    }

    private func finite(_ value: Double, dimension: Dimension, scale: Double) throws -> Measured {
        let exponents = [dimension.length, dimension.mass, dimension.time,
                         dimension.electricCurrent, dimension.temperature,
                         dimension.amount, dimension.luminousIntensity]
        guard value.isFinite, exponents.allSatisfy(\.isFinite) else {
            throw CalculationError.invalid("Résultat non réel ou dépassement de la plage numérique. Vérifiez les valeurs et les puissances.")
        }
        return Measured(Quantity(value: value, dimension: dimension), scale: scale)
    }
}

/// A value and the magnitude of the inexact terms it was computed from. Its
/// rounding error stays near 10⁻¹⁶ times that magnitude, so `==` absorbs the
/// residue of 0,1 + 0,2 − 0,3 (magnitude 0,9) but not the 10⁻⁵ left after
/// the exact cancellation in 10⁶ − 10⁶ + 10⁻⁵ (magnitude 10⁻⁵).
private struct Measured {
    let quantity: Quantity
    let scale: Double

    init(_ quantity: Quantity, scale: Double) {
        self.quantity = quantity
        // An unbounded estimate would accept any equality.
        self.scale = scale.isFinite ? scale : abs(quantity.value)
    }

    /// A literal, constant or unit factor: only whole numbers below 2⁵³ are exact.
    init(_ quantity: Quantity) {
        self.init(quantity, scale: Self.isExactInteger(quantity.value) ? 0 : abs(quantity.value))
    }

    var value: Double { quantity.value }
    var dimension: Dimension { quantity.dimension }

    static func isExactInteger(_ value: Double) -> Bool {
        value == value.rounded() && abs(value) <= 9_007_199_254_740_992
    }
}

// MARK: - Display units and standalone evaluation

extension NotebookEngine {
    /// Evaluates an expression that uses no sheet: literals, units and constants only.
    static func standaloneQuantity(_ expression: Expression) throws -> Quantity {
        try Resolver(lines: []).measure(expression, depth: 0).quantity
    }

    /// Parses and evaluates a unit expression such as `km/h` or `MeV/c²`.
    static func unitQuantity(of symbol: String) -> Quantity? {
        guard var parser = try? ExpressionParser(symbol), let expression = try? parser.parse() else { return nil }
        return try? targetQuantity(expression, depth: 0)
    }

    /// The unit requested after `->`, checked against the dimension of the result.
    static func displayUnit(_ target: Expression, symbol: String, for dimension: Dimension) throws -> DisplayUnit {
        let quantity = try targetQuantity(target, depth: 0)
        guard quantity.value.isFinite, quantity.value > 0 else {
            throw CalculationError.invalid("L’unité d’affichage \(symbol) a une valeur nulle ou hors de la plage de calcul.")
        }
        guard quantity.dimension.isEquivalent(to: dimension) else {
            throw CalculationError.invalid("Conversion impossible : le résultat a pour dimension \(dimension.formatted), alors que \(symbol) a pour dimension \(quantity.dimension.formatted).")
        }
        return DisplayUnit(symbol: symbol, scale: quantity.value)
    }

    private static let targetRule = CalculationError.invalid("Après →, indiquez seulement une unité, par exemple km/h, kWh ou MeV/c².")

    /// A unit expression: names (units first, then constants, never sheet
    /// variables), `*`, `/`, `^` with a numeric exponent, and a leading `1/`.
    private static func targetQuantity(_ expression: Expression, depth: Int) throws -> Quantity {
        guard depth <= 100 else { throw targetRule }
        switch expression {
        case .identifier(let name), .unit(let name):
            if let unit = UnitCatalog.lookup(name) { return unit.quantity }
            if let constant = ConstantCatalog.lookup(name) { return constant.quantity }
            if let message = Diagnostics.offsetTemperature(name) { throw CalculationError.invalid(message) }
            throw CalculationError.invalid("« \(name) » n’est pas une unité reconnue pour l’affichage après →.")
        case .binary(.power, let base, let exponent):
            guard exponent.isNumericExpression, let power = try? standaloneQuantity(exponent),
                  power.dimension.isDimensionless else { throw targetRule }
            let unit = try targetQuantity(base, depth: depth + 1)
            return Quantity(value: Foundation.pow(unit.value, power.value), dimension: unit.dimension.scaled(by: power.value))
        case .binary(.multiply, let left, let right):
            let (a, b) = (try targetQuantity(left, depth: depth + 1), try targetQuantity(right, depth: depth + 1))
            return Quantity(value: a.value * b.value, dimension: a.dimension + b.dimension)
        case .binary(.divide, let left, let right):
            let denominator = try targetQuantity(right, depth: depth + 1)
            if case .number(1) = left { return Quantity(value: 1 / denominator.value, dimension: .dimensionless - denominator.dimension) }
            let numerator = try targetQuantity(left, depth: depth + 1)
            return Quantity(value: numerator.value / denominator.value, dimension: numerator.dimension - denominator.dimension)
        default:
            throw targetRule
        }
    }
}

/// Messages for names the sheet cannot resolve.
enum Diagnostics {
    /// °C and °F are offset scales: a display-only conversion cannot tell an absolute
    /// temperature from a difference, so only the kelvin is supported.
    static func offsetTemperature(_ name: String) -> String? {
        guard ["°c", "degc", "°f", "degf", "celsius", "fahrenheit"].contains(name.lowercased()) else { return nil }
        return "Les températures en °C ou °F ne sont pas prises en charge (unités à décalage). Utilisez le kelvin : 20 °C correspondent à 293,15 K."
    }

    static func unknownSymbol(_ name: String) -> String {
        if let message = offsetTemperature(name) { return message }
        if name == "en" || name == "in" {
            return "« \(name) » n’est pas un mot-clé. Pour afficher un résultat dans une autre unité, écrivez par exemple E -> kJ ou E → kJ."
        }
        if ExpressionParser.isFunctionName(name) {
            return "Utilisez \(name)(expression) pour cette fonction, ou déclarez une variable \(name) = …."
        }
        let stem = String(name.reversed().drop { $0.isASCII && $0.isNumber }.reversed())
        if !stem.isEmpty, stem != name, UnitCatalog.lookup(stem) != nil {
            return "« \(name) » est inconnu. Pour une puissance d’unité, écrivez \(stem)² ou \(stem)^2 ; pour une variable, ajoutez une déclaration \(name) = …."
        }
        return "« \(name) » n’est ni une variable déclarée, ni une constante, ni une unité connue. Ajoutez une déclaration, par exemple \(name) = 7,2 m, ou consultez Références › Unités."
    }

    static func dimensionalArgument(_ function: String) -> CalculationError {
        switch function {
        case "sin", "cos", "tan":
            return .invalid("La fonction \(function) nécessite un argument sans dimension. Pour un angle, utilisez rad ou deg.")
        case "floor", "ceil", "round":
            return .invalid("La fonction \(function) nécessite un argument sans dimension ; divisez d’abord par une unité, par exemple \(function)(t / 1 s).")
        default:
            return .invalid("La fonction \(function) nécessite un argument sans dimension.")
        }
    }
}

extension Expression {
    /// A note for `sin(30)`-like calls: a whole number of degrees, between 15 and
    /// 360 and a multiple of 15, passed as a bare number is read in radians.
    /// Found on the expression itself, without resolving variables.
    var radianNote: String? {
        var pending = [self]
        while let next = pending.popLast() {
            switch next {
            case .function(let name, let arguments):
                if ["sin", "cos", "tan"].contains(name), arguments.count == 1, arguments[0].isNumericExpression,
                   let angle = try? NotebookEngine.standaloneQuantity(arguments[0]).value,
                   angle == angle.rounded(), (15...360).contains(abs(angle)), abs(angle).truncatingRemainder(dividingBy: 15) == 0 {
                    return "Angle interprété en radians. Pour des degrés, écrivez \(name)(\(Int(angle)) deg)."
                }
                pending.append(contentsOf: arguments)
            case .unary(_, let argument), .factorial(let argument), .compactUnits(let argument):
                pending.append(argument)
            case .binary(_, let left, let right):
                pending.append(contentsOf: [right, left])
            case .number, .identifier, .unit:
                break
            }
        }
        return nil
    }
}
