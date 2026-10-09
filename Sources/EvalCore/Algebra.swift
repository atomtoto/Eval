import Foundation

// MARK: - Exact fractions

/// An exact fraction of 64-bit integers, reduced, with a positive denominator.
/// Arithmetic that would overflow returns nil: the caller then keeps a `Double`.
struct Rational: Hashable, Sendable {
    let numerator: Int
    let denominator: Int

    static let zero = Rational(0)
    static let one = Rational(1)

    init(_ integer: Int) {
        numerator = integer
        denominator = 1
    }

    init?(_ numerator: Int, _ denominator: Int) {
        guard denominator != 0, numerator != .min, denominator != .min else { return nil }
        let divisor = Self.gcd(numerator, denominator)
        let sign = denominator < 0 ? -1 : 1
        self.numerator = sign * (numerator / divisor)
        self.denominator = abs(denominator) / divisor
    }

    /// The simplest fraction that gives back exactly this double, as typed: 0.1 is 1/10.
    init?(exactly value: Double, maximumDenominator: Int = 1_000_000_000) {
        guard value.isFinite else { return nil }
        if value == value.rounded() {
            guard abs(value) <= 9_007_199_254_740_992 else { return nil }
            self.init(Int(value))
            return
        }
        let target = abs(value)
        var x = target
        // Convergents of the continued fraction, until one rounds back to the value.
        var (previousP, previousQ, p, q) = (0, 1, 1, 0)
        for _ in 0..<40 {
            let whole = x.rounded(.down)
            guard whole < 1e15 else { return nil }
            let a = Int(whole)
            let (ap, o1) = a.multipliedReportingOverflow(by: p)
            let (nextP, o2) = ap.addingReportingOverflow(previousP)
            let (aq, o3) = a.multipliedReportingOverflow(by: q)
            let (nextQ, o4) = aq.addingReportingOverflow(previousQ)
            guard !(o1 || o2 || o3 || o4), nextQ <= maximumDenominator else { return nil }
            if Double(nextP) / Double(nextQ) == target {
                guard let found = Rational(value < 0 ? -nextP : nextP, nextQ) else { return nil }
                self = found
                return
            }
            (previousP, previousQ, p, q) = (p, q, nextP, nextQ)
            let fraction = x - whole
            guard fraction > 0 else { return nil }
            x = 1 / fraction
        }
        return nil
    }

    static func gcd(_ a: Int, _ b: Int) -> Int {
        var (a, b) = (abs(a), abs(b))
        while b != 0 { (a, b) = (b, a % b) }
        return a
    }

    var isInteger: Bool { denominator == 1 }
    var isZero: Bool { numerator == 0 }
    var isNegative: Bool { numerator < 0 }
    var doubleValue: Double { Double(numerator) / Double(denominator) }
    var magnitude: Rational { Rational(abs(numerator), denominator) ?? self }

    var negated: Rational? { numerator == .min ? nil : Rational(-numerator, denominator) }
    var reciprocal: Rational? { numerator == 0 ? nil : Rational(denominator, numerator) }

    func adding(_ other: Rational) -> Rational? {
        let divisor = Self.gcd(denominator, other.denominator)
        let (left, o1) = numerator.multipliedReportingOverflow(by: other.denominator / divisor)
        let (right, o2) = other.numerator.multipliedReportingOverflow(by: denominator / divisor)
        let (sum, o3) = left.addingReportingOverflow(right)
        let (common, o4) = denominator.multipliedReportingOverflow(by: other.denominator / divisor)
        guard !(o1 || o2 || o3 || o4) else { return nil }
        return Rational(sum, common)
    }

    func subtracting(_ other: Rational) -> Rational? {
        other.negated.flatMap(adding)
    }

    func multiplied(by other: Rational) -> Rational? {
        let first = Self.gcd(numerator, other.denominator), second = Self.gcd(other.numerator, denominator)
        let (top, o1) = (numerator / first).multipliedReportingOverflow(by: other.numerator / second)
        let (bottom, o2) = (denominator / second).multipliedReportingOverflow(by: other.denominator / first)
        guard !(o1 || o2) else { return nil }
        return Rational(top, bottom)
    }

    func divided(by other: Rational) -> Rational? {
        other.reciprocal.flatMap(multiplied)
    }

    func power(_ exponent: Int) -> Rational? {
        guard exponent != .min, var base = exponent < 0 ? reciprocal : self else { return nil }
        var result = Rational.one
        var remaining = abs(exponent)
        while remaining > 0 {
            if remaining & 1 == 1 {
                guard let next = result.multiplied(by: base) else { return nil }
                result = next
            }
            remaining >>= 1
            if remaining > 0 {
                guard let squared = base.multiplied(by: base) else { return nil }
                base = squared
            }
        }
        return result
    }

    /// The digits of the magnitude when it terminates within `maximumPlaces`, with a
    /// decimal comma: 3/8 gives « 0,375 ». Nil for 1/3.
    func decimalMagnitude(maximumPlaces: Int = 9) -> String? {
        var rest = denominator, twos = 0, fives = 0
        while rest % 2 == 0 { rest /= 2; twos += 1 }
        while rest % 5 == 0 { rest /= 5; fives += 1 }
        let places = max(twos, fives)
        guard rest == 1, places <= maximumPlaces else { return nil }
        var scale = 1
        for _ in 0..<places { scale *= 10 }
        let (scaled, overflow) = abs(numerator).multipliedReportingOverflow(by: scale / denominator)
        guard !overflow else { return nil }
        let digits = String(scaled)
        guard places > 0 else { return digits }
        let padded = String(repeating: "0", count: max(0, places + 1 - digits.count)) + digits
        return padded.dropLast(places) + "," + padded.suffix(places)
    }

    /// The magnitude as written in a formula: « 3 », « 0,375 », or « 1/3 ».
    func formattedMagnitude(prefersDecimals: Bool = true) -> String {
        if isInteger { return String(abs(numerator)) }
        if prefersDecimals, let decimal = decimalMagnitude() { return decimal }
        return "\(abs(numerator))/\(denominator)"
    }

    /// With the true minus sign, for results: « −1/3 ».
    var formatted: String {
        (isNegative ? "−" : "") + formattedMagnitude()
    }
}

/// A number that stays exact while it can, and falls back on `Double` otherwise.
enum Numeric: Hashable, Sendable {
    case exact(Rational)
    case approximate(Double)

    static let zero = Numeric.exact(.zero)
    static let one = Numeric.exact(.one)

    var doubleValue: Double {
        switch self {
        case .exact(let rational): rational.doubleValue
        case .approximate(let value): value
        }
    }

    var isZero: Bool { doubleValue == 0 }
    var isOne: Bool { self == .one }
    var isNegative: Bool { doubleValue < 0 }

    var term: Term {
        switch self {
        case .exact(let rational): .number(rational)
        case .approximate(let value): .real(value)
        }
    }

    static func + (lhs: Numeric, rhs: Numeric) -> Numeric {
        if case .exact(let a) = lhs, case .exact(let b) = rhs, let sum = a.adding(b) { return .exact(sum) }
        return .approximate(lhs.doubleValue + rhs.doubleValue)
    }

    static func * (lhs: Numeric, rhs: Numeric) -> Numeric {
        if case .exact(let a) = lhs, case .exact(let b) = rhs, let product = a.multiplied(by: b) { return .exact(product) }
        return .approximate(lhs.doubleValue * rhs.doubleValue)
    }

    var negated: Numeric {
        if case .exact(let rational) = self, let negated = rational.negated { return .exact(negated) }
        return .approximate(-doubleValue)
    }
}

// MARK: - Symbolic terms

/// A formula as an algebraic term. Sums and products are flat lists; a product
/// keeps at most one number, first; a quotient is a product with a power −1; and
/// √x is x^(1/2). Units stay apart from names, so `5 m` keeps its metre.
indirect enum Term: Hashable, Sendable {
    case number(Rational)
    /// A value that no small fraction represents exactly.
    case real(Double)
    case symbol(String)
    case unit(String)
    case sum([Term])
    case product([Term])
    case power(Term, Term)
    case function(String, [Term])
    case factorial(Term)

    static let zero = Term.number(.zero)
    static let one = Term.number(.one)
    static let minusOne = Term.number(Rational(-1))
    static let half = Term.number(Rational(1, 2)!)

    var numeric: Numeric? {
        switch self {
        case .number(let rational): .exact(rational)
        case .real(let value): .approximate(value)
        default: nil
        }
    }

    /// Whether `name` occurs as a name anywhere in the term.
    func contains(symbol name: String) -> Bool {
        switch self {
        case .symbol(let symbol): symbol == name
        case .number, .real, .unit: false
        case .sum(let terms), .product(let terms), .function(_, let terms):
            terms.contains { $0.contains(symbol: name) }
        case .power(let base, let exponent): base.contains(symbol: name) || exponent.contains(symbol: name)
        case .factorial(let argument): argument.contains(symbol: name)
        }
    }

    /// The names of the term, units excluded.
    var symbols: Set<String> {
        switch self {
        case .symbol(let name): [name]
        case .number, .real, .unit: []
        case .sum(let terms), .product(let terms), .function(_, let terms):
            terms.reduce(into: Set<String>()) { $0.formUnion($1.symbols) }
        case .power(let base, let exponent): base.symbols.union(exponent.symbols)
        case .factorial(let argument): argument.symbols
        }
    }

    /// The size of the numbers written in the term, to prefer 2√3 to √12.
    var numberWeight: Double {
        switch self {
        case .number(let rational): Double(abs(rational.numerator)) + Double(rational.denominator) - 1
        case .real(let value): abs(value)
        case .symbol, .unit: 0
        case .sum(let terms), .product(let terms), .function(_, let terms):
            terms.reduce(0) { $0 + $1.numberWeight }
        case .power(let base, let exponent): base.numberWeight + exponent.numberWeight
        case .factorial(let argument): argument.numberWeight
        }
    }

    /// The number of nodes, to keep expansions bounded.
    var size: Int {
        switch self {
        case .number, .real, .symbol, .unit: 1
        case .sum(let terms), .product(let terms), .function(_, let terms):
            terms.reduce(1) { $0 + $1.size }
        case .power(let base, let exponent): 1 + base.size + exponent.size
        case .factorial(let argument): 1 + argument.size
        }
    }

    /// A total order on terms, so that equal sums and products list their parts alike.
    fileprivate var canonicalKey: String {
        switch self {
        case .number(let rational): "0\(rational.numerator)/\(rational.denominator)"
        case .real(let value): "1\(value)"
        case .symbol(let name): "3\(name)"
        case .unit(let symbol): "4\(symbol)"
        case .power(let base, let exponent): base.canonicalKey + "^(" + exponent.canonicalKey + ")"
        case .function(let name, let arguments): "5\(name)(" + arguments.map(\.canonicalKey).joined(separator: ";") + ")"
        case .product(let factors): "6(" + factors.map(\.canonicalKey).joined(separator: "*") + ")"
        case .sum(let terms): "7(" + terms.map(\.canonicalKey).joined(separator: "+") + ")"
        case .factorial(let argument): "8(" + argument.canonicalKey + ")"
        }
    }

    fileprivate static func canonicalOrder(_ lhs: Term, _ rhs: Term) -> Bool {
        lhs.canonicalKey < rhs.canonicalKey
    }
}

// MARK: Conversion

extension Term {
    /// The term of a parsed expression, as written: nothing is simplified yet.
    /// `readingCompactUnits` decides how `72km/h` reads; without it such chains
    /// are not supported and the result is nil.
    init?(_ expression: Expression, readingCompactUnits: ((Expression) -> Expression)? = nil) {
        switch expression {
        case .number(let value):
            self = Rational(exactly: value).map(Term.number) ?? .real(value)
        case .identifier(let name):
            self = .symbol(name)
        case .unit(let symbol):
            self = .unit(symbol)
        case .unary(let operation, let argument):
            guard let inner = Term(argument, readingCompactUnits: readingCompactUnits) else { return nil }
            self = operation == .plus ? inner : .product([.minusOne, inner])
        case .binary(let operation, let left, let right):
            guard let lhs = Term(left, readingCompactUnits: readingCompactUnits),
                  let rhs = Term(right, readingCompactUnits: readingCompactUnits) else { return nil }
            switch operation {
            case .add: self = .sum([lhs, rhs])
            case .subtract: self = .sum([lhs, .product([.minusOne, rhs])])
            case .multiply: self = .product([lhs, rhs])
            case .divide: self = .product([lhs, .power(rhs, .minusOne)])
            case .power: self = .power(lhs, rhs)
            }
        case .function(let name, let arguments):
            var terms: [Term] = []
            for argument in arguments {
                guard let term = Term(argument, readingCompactUnits: readingCompactUnits) else { return nil }
                terms.append(term)
            }
            self = name == "sqrt" && terms.count == 1 ? .power(terms[0], .half) : .function(name, terms)
        case .factorial(let argument):
            guard let inner = Term(argument, readingCompactUnits: readingCompactUnits) else { return nil }
            self = .factorial(inner)
        case .compactUnits(let units):
            guard let readingCompactUnits,
                  let inner = Term(readingCompactUnits(units), readingCompactUnits: readingCompactUnits) else { return nil }
            self = inner
        }
    }

    /// The expression the engine evaluates for this term.
    var expression: Expression {
        switch self {
        case .number(let rational):
            let numerator = Expression.number(Double(abs(rational.numerator)))
            let magnitude = rational.isInteger ? numerator
                : .binary(.divide, numerator, .number(Double(rational.denominator)))
            return rational.isNegative ? .unary(.minus, magnitude) : magnitude
        case .real(let value):
            return value < 0 ? .unary(.minus, .number(-value)) : .number(value)
        case .symbol(let name):
            return .identifier(name)
        case .unit(let symbol):
            return .unit(symbol)
        case .sum(let terms):
            return terms.dropFirst().reduce(terms.first?.expression ?? .number(0)) { .binary(.add, $0, $1.expression) }
        case .product(let factors):
            return factors.dropFirst().reduce(factors.first?.expression ?? .number(1)) { .binary(.multiply, $0, $1.expression) }
        case .power(let base, .number(let exponent)) where exponent == Rational(1, 2):
            return .function("sqrt", [base.expression])
        case .power(let base, let exponent):
            return .binary(.power, base.expression, exponent.expression)
        case .function(let name, let arguments):
            return .function(name, arguments.map(\.expression))
        case .factorial(let argument):
            return .factorial(argument.expression)
        }
    }
}

// MARK: Automatic simplification

extension Term {
    /// Numbers computed, like terms collected (2x + 3x → 5x), like factors merged
    /// into powers (x·x → x², m·v²/m → v²), and the obvious values of functions.
    /// Sums and products are not expanded: see `expanded(budget:)`.
    var simplified: Term {
        switch self {
        case .number, .real, .symbol, .unit:
            return self
        case .sum(let terms):
            return Term.add(terms.map(\.simplified))
        case .product(let factors):
            return Term.multiply(factors.map(\.simplified))
        case .power(let base, let exponent):
            return Term.raise(base.simplified, exponent.simplified)
        case .function(let name, let arguments):
            return Term.call(name, arguments.map(\.simplified))
        case .factorial(let argument):
            return Term.factorial(of: argument.simplified)
        }
    }

    /// The number before a product and the rest: 3x² gives (3, x²).
    private var coefficientAndRest: (Numeric, Term) {
        if case .product(let factors) = self, let first = factors.first?.numeric {
            let rest = Array(factors.dropFirst())
            return (first, rest.count == 1 ? rest[0] : .product(rest))
        }
        return (.one, self)
    }

    private var baseAndExponent: (Term, Term) {
        if case .power(let base, let exponent) = self { return (base, exponent) }
        return (self, .one)
    }

    /// `rest` multiplied by a number, for a rest without one.
    private static func scaled(_ rest: Term, by coefficient: Numeric) -> Term {
        if coefficient.isOne { return rest }
        if coefficient.isZero { return .zero }
        if case .product(let factors) = rest { return .product([coefficient.term] + factors) }
        return .product([coefficient.term, rest])
    }

    /// The sum of simplified terms.
    static func add(_ operands: [Term]) -> Term {
        var constant = Numeric.zero
        var keys: [Term] = []
        var coefficients: [Term: Numeric] = [:]
        func absorb(_ term: Term) {
            switch term {
            case .sum(let inner):
                inner.forEach(absorb)
            case .number(let rational):
                constant = constant + .exact(rational)
            case .real(let value):
                constant = constant + .approximate(value)
            default:
                let (coefficient, rest) = term.coefficientAndRest
                if let existing = coefficients[rest] {
                    coefficients[rest] = existing + coefficient
                } else {
                    keys.append(rest)
                    coefficients[rest] = coefficient
                }
            }
        }
        operands.forEach(absorb)
        // sin²u + cos²u = 1, with the same coefficient on both.
        for key in keys {
            guard case .power(.function("sin", let arguments), .number(let two)) = key, two == Rational(2),
                  let coefficient = coefficients[key], !coefficient.isZero else { continue }
            let partner = Term.power(.function("cos", arguments), .number(Rational(2)))
            guard coefficients[partner] == coefficient else { continue }
            coefficients[key] = .zero
            coefficients[partner] = .zero
            constant = constant + coefficient
        }
        var terms: [Term] = []
        for key in keys {
            guard let coefficient = coefficients[key], !coefficient.isZero else { continue }
            terms.append(scaled(key, by: coefficient))
        }
        if !constant.isZero || terms.isEmpty { terms.append(constant.term) }
        if terms.count == 1 { return terms[0] }
        return .sum(terms.sorted(by: canonicalOrder))
    }

    /// The product of simplified factors.
    static func multiply(_ factors: [Term]) -> Term {
        multiply(factors, pass: 0)
    }

    private static func multiply(_ factors: [Term], pass: Int) -> Term {
        var coefficient = Numeric.one
        var bases: [Term] = []
        var exponents: [Term: Term] = [:]
        func absorb(_ factor: Term) {
            switch factor {
            case .product(let inner):
                inner.forEach(absorb)
            case .number(let rational):
                coefficient = coefficient * .exact(rational)
            case .real(let value):
                coefficient = coefficient * .approximate(value)
            default:
                let (base, exponent) = factor.baseAndExponent
                if let existing = exponents[base] {
                    exponents[base] = add([existing, exponent])
                } else {
                    bases.append(base)
                    exponents[base] = exponent
                }
            }
        }
        factors.forEach(absorb)
        if coefficient.isZero { return .zero }
        var rest: [Term] = []
        var regrouped: [Term] = []
        for base in bases {
            guard let exponent = exponents[base] else { continue }
            let raised = raise(base, exponent)
            switch raised {
            case .number(let rational): coefficient = coefficient * .exact(rational)
            case .real(let value): coefficient = coefficient * .approximate(value)
            case .product(let inner): regrouped.append(contentsOf: inner)
            default: rest.append(raised)
            }
        }
        // √12 became 2·√3: its parts may merge with the other factors.
        if !regrouped.isEmpty, pass < 3 {
            return multiply([coefficient.term] + rest + regrouped, pass: pass + 1)
        }
        rest.append(contentsOf: regrouped)
        if coefficient.isZero { return .zero }
        rest.sort(by: canonicalOrder)
        if rest.isEmpty { return coefficient.term }
        if coefficient.isOne { return rest.count == 1 ? rest[0] : .product(rest) }
        return .product([coefficient.term] + rest)
    }

    /// `base` to the power `exponent`, both simplified.
    static func raise(_ base: Term, _ exponent: Term) -> Term {
        if exponent == .zero { return .one }
        if exponent == .one { return base }
        if base == .one { return .one }
        if base == .zero, let value = exponent.numeric, value.doubleValue > 0 { return .zero }
        if let value = base.numeric, let power = exponent.numeric, let result = numericPower(value, power) {
            return result
        }
        if case .number(let integer) = exponent, integer.isInteger {
            switch base {
            case .power(let innerBase, let innerExponent):
                return raise(innerBase, multiply([innerExponent, exponent]))
            case .product(let factors):
                return multiply(factors.map { raise($0, exponent) })
            default:
                break
            }
        }
        return .power(base, exponent)
    }

    /// A numeric power, exact when it can be; nil to keep it written as a power.
    private static func numericPower(_ base: Numeric, _ exponent: Numeric) -> Term? {
        switch (base, exponent) {
        case (.exact(let b), .exact(let e)) where e.isInteger:
            if b.isZero && e.numerator <= 0 { return nil }
            if let exact = b.power(e.numerator) { return .number(exact) }
            let value = Foundation.pow(b.doubleValue, e.doubleValue)
            return value.isFinite ? .real(value) : nil
        case (.exact(let b), .exact(let e)) where b.numerator > 0:
            return root(of: b, power: e)
        case (.exact(let b), .exact) where b.isNegative:
            return nil
        default:
            let (b, e) = (base.doubleValue, exponent.doubleValue)
            guard b > 0 || e == e.rounded() else { return nil }
            let value = Foundation.pow(b, e)
            return value.isFinite && !(b == 0 && e <= 0) ? .real(value) : nil
        }
    }

    /// r^(p/q) for r > 0 with perfect powers taken out and the denominator made
    /// whole: √12 → 2√3, √(1/2) → √2/2, 8^(2/3) → 4.
    private static func root(of base: Rational, power exponent: Rational) -> Term? {
        let q = exponent.denominator
        var whole = exponent.numerator / q, rest = exponent.numerator % q
        if rest < 0 { rest += q; whole -= 1 }
        guard let wholePart = base.power(whole) else { return nil }
        // (n/d)^(s/q) = (n·d^(q−1))^(s/q) / d^s
        guard let denominatorPower = integerPower(base.denominator, q - 1) else { return nil }
        let (radicand, overflow) = base.numerator.multipliedReportingOverflow(by: denominatorPower)
        guard !overflow else { return nil }
        let (outside, inside) = perfectPower(of: radicand, root: q)
        guard let outsidePower = integerPower(outside, rest), let denominatorRest = integerPower(base.denominator, rest),
              let factor = Rational(outsidePower, denominatorRest),
              let coefficient = wholePart.multiplied(by: factor) else { return nil }
        if inside == 1 { return .number(coefficient) }
        let radical = Term.power(.number(Rational(inside)), .number(Rational(rest, q)!))
        return coefficient == .one ? radical : .product([.number(coefficient), radical])
    }

    private static func integerPower(_ base: Int, _ exponent: Int) -> Int? {
        guard exponent >= 0 else { return nil }
        var result = 1
        for _ in 0..<exponent {
            let (next, overflow) = result.multipliedReportingOverflow(by: base)
            guard !overflow else { return nil }
            result = next
        }
        return result
    }

    /// `value` as outside^root · inside, with the small perfect powers moved outside.
    static func perfectPower(of value: Int, root: Int) -> (outside: Int, inside: Int) {
        var outside = 1, inside = value, factor = 2
        while factor <= 100_000 {
            guard let power = integerPower(factor, root), power <= inside else { break }
            while inside % power == 0 {
                inside /= power
                let (next, overflow) = outside.multipliedReportingOverflow(by: factor)
                guard !overflow else { return (1, value) }
                outside = next
            }
            factor += 1
        }
        return (outside, inside)
    }

    /// A function of simplified arguments, with its obvious values: sin(0) = 0, ln(exp(x)) = x.
    static func call(_ name: String, _ arguments: [Term]) -> Term {
        let unchanged = Term.function(name, arguments)
        guard let argument = arguments.first else { return unchanged }
        if arguments.count == 1 {
            switch name {
            case "sqrt":
                return raise(argument, .half)
            case "abs":
                if let value = argument.numeric {
                    return value.isNegative ? value.negated.term : value.term
                }
                if case .function("abs", _) = argument { return argument }
            case "exp":
                if argument == .zero { return .one }
                if case .function("ln", let inner) = argument, inner.count == 1 { return inner[0] }
            case "ln", "log", "log10":
                if argument == .one { return .zero }
                if name == "ln", case .function("exp", let inner) = argument, inner.count == 1 { return inner[0] }
            case "sin", "tan", "asin", "atan", "sinh", "tanh":
                if argument == .zero { return .zero }
            case "cos", "cosh":
                if argument == .zero { return .one }
            case "acos":
                if argument == .one { return .zero }
            case "cbrt":
                if let root = integerRoot(of: argument, index: 3) { return root }
                if case .power(let base, .number(let three)) = argument, three == Rational(3) { return base }
            case "floor", "ceil", "round":
                if case .number(let rational) = argument {
                    let value = rational.doubleValue
                    let rounded = name == "floor" ? value.rounded(.down) : name == "ceil" ? value.rounded(.up) : value.rounded()
                    if abs(rounded) < 1e15 { return .number(Rational(Int(rounded))) }
                }
            default:
                break
            }
        }
        if name == "root", arguments.count == 2, case .number(let index) = arguments[1], index.isInteger,
           (2...1000).contains(index.numerator) {
            if let root = integerRoot(of: argument, index: index.numerator) { return root }
            if index.numerator % 2 == 1, case .power(let base, .number(let power)) = argument, power == index { return base }
        }
        if name == "min" || name == "max" {
            let values = arguments.compactMap(\.numeric)
            if values.count == arguments.count,
               let best = name == "min" ? values.min(by: { $0.doubleValue < $1.doubleValue })
                                        : values.max(by: { $0.doubleValue < $1.doubleValue }) {
                return best.term
            }
        }
        return unchanged
    }

    /// The exact real root of a fraction, odd roots of negatives included: cbrt(−8) = −2.
    private static func integerRoot(of term: Term, index: Int) -> Term? {
        guard case .number(let rational) = term, rational.isNegative ? index % 2 == 1 : true else { return nil }
        let magnitude = rational.magnitude
        let numerator = perfectPower(of: magnitude.numerator, root: index)
        let denominator = perfectPower(of: magnitude.denominator, root: index)
        guard numerator.inside == 1, denominator.inside == 1,
              let root = Rational(rational.isNegative ? -numerator.outside : numerator.outside, denominator.outside) else { return nil }
        return .number(root)
    }

    static func factorial(of argument: Term) -> Term {
        if case .number(let rational) = argument, rational.isInteger, (0...20).contains(rational.numerator) {
            return .number(Rational((1...max(1, rational.numerator)).reduce(1, *)))
        }
        return .factorial(argument)
    }
}

// MARK: Expansion and common denominators

extension Term {
    /// Products of sums distributed and whole powers of sums multiplied out, then
    /// simplified: x(x + 1) − x² gives x. Nil when the result would exceed `budget` terms.
    func expanded(budget: inout Int) -> Term? {
        switch self {
        case .number, .real, .symbol, .unit:
            return self
        case .sum(let terms):
            var parts: [Term] = []
            for term in terms {
                guard let part = term.expanded(budget: &budget) else { return nil }
                parts.append(part)
            }
            return Term.add(parts)
        case .product(let factors):
            var addends: [Term] = [.one]
            for factor in factors {
                guard let expanded = factor.expanded(budget: &budget) else { return nil }
                let pieces: [Term]
                if case .sum(let terms) = expanded { pieces = terms } else { pieces = [expanded] }
                budget -= addends.count * pieces.count
                guard budget >= 0 else { return nil }
                // Like terms merge at each step, so that (x + 1)¹⁰ stays eleven terms long.
                let merged = Term.add(addends.flatMap { addend in pieces.map { Term.multiply([addend, $0]) } })
                if case .sum(let terms) = merged { addends = terms } else { addends = [merged] }
            }
            return Term.add(addends)
        case .power(let base, let exponent):
            guard let expanded = base.expanded(budget: &budget) else { return nil }
            if case .sum = expanded, case .number(let power) = exponent, power.isInteger, (2...12).contains(power.numerator) {
                return Term.product(Array(repeating: expanded, count: power.numerator)).expanded(budget: &budget)
            }
            return Term.raise(expanded, exponent)
        case .function(let name, let arguments):
            var expanded: [Term] = []
            for argument in arguments {
                guard let term = argument.expanded(budget: &budget) else { return nil }
                expanded.append(term)
            }
            return Term.call(name, expanded)
        case .factorial(let argument):
            return argument.expanded(budget: &budget).map(Term.factorial(of:))
        }
    }

    /// The numerator and denominator of a simplified term: 2x/(3y²) gives (2x, 3y²).
    var fraction: (numerator: Term, denominator: Term) {
        var top: [Term] = [], bottom: [Term] = []
        let factors: [Term]
        if case .product(let parts) = self { factors = parts } else { factors = [self] }
        for factor in factors {
            switch factor {
            case .number(let rational):
                top.append(.number(Rational(rational.numerator)))
                bottom.append(.number(Rational(rational.denominator)))
            case .power(let base, .number(let exponent)) where exponent.isNegative:
                bottom.append(Term.raise(base, .number(exponent.negated ?? exponent)))
            default:
                top.append(factor)
            }
        }
        return (Term.multiply(top), Term.multiply(bottom))
    }

    /// The term over one denominator, with the common factor of numerator and
    /// denominator cancelled when both are polynomials in one name:
    /// (x² − 1)/(x − 1) gives x + 1, and 1/x + 1/(2x) gives 3/(2x).
    func combined(budget: inout Int) -> Term? {
        var numerator: Term, denominator: Term
        if case .sum(let terms) = self {
            let parts = terms.map(\.fraction)
            var denominators: [Term] = []
            for part in parts where part.denominator != .one && !denominators.contains(part.denominator) {
                denominators.append(part.denominator)
            }
            guard !denominators.isEmpty else { return nil }
            denominator = Term.multiply(denominators)
            var addends: [Term] = []
            for part in parts {
                let others = denominators.filter { $0 != part.denominator }
                addends.append(Term.multiply([part.numerator] + (part.denominator == .one ? denominators : others)))
            }
            numerator = Term.add(addends)
        } else {
            (numerator, denominator) = fraction
            guard denominator != .one else { return nil }
        }
        guard let top = numerator.expanded(budget: &budget), let bottom = denominator.expanded(budget: &budget) else {
            return nil
        }
        numerator = top
        denominator = bottom
        let names = numerator.symbols.union(denominator.symbols)
        if names.count == 1, let name = names.first,
           let p = UnivariatePolynomial(numerator, in: name), let q = UnivariatePolynomial(denominator, in: name),
           let common = p.greatestCommonDivisor(with: q), common.degree > 0,
           let reducedTop = p.dividing(by: common), let reducedBottom = q.dividing(by: common) {
            numerator = reducedTop.term(in: name)
            denominator = reducedBottom.term(in: name)
        }
        return Term.multiply([numerator, Term.raise(denominator, .minusOne)])
    }

    /// The simplest forms worth comparing for a formula, simplest first.
    static func simplificationCandidates(of term: Term) -> [Term] {
        let automatic = term.simplified
        var candidates = [automatic]
        var budget = 400
        if let expanded = automatic.expanded(budget: &budget) {
            candidates.append(expanded)
            var combinedBudget = 400
            if let combined = expanded.combined(budget: &combinedBudget) { candidates.append(combined) }
        }
        var combinedBudget = 400
        if let combined = automatic.combined(budget: &combinedBudget) { candidates.append(combined) }
        return candidates
    }
}

/// A polynomial in one name with exact coefficients, lowest degree first.
struct UnivariatePolynomial: Equatable {
    var coefficients: [Rational]

    init(coefficients: [Rational]) {
        var trimmed = coefficients
        while let last = trimmed.last, last.isZero { trimmed.removeLast() }
        self.coefficients = trimmed
    }

    /// The polynomial of an expanded term in `name`; nil when the term is not one.
    init?(_ term: Term, in name: String) {
        let terms: [Term]
        if case .sum(let parts) = term { terms = parts } else { terms = [term] }
        var coefficients: [Int: Rational] = [:]
        for part in terms {
            var coefficient = Rational.one, degree = 0
            let factors: [Term]
            if case .product(let inner) = part { factors = inner } else { factors = [part] }
            for factor in factors {
                switch factor {
                case .number(let rational):
                    coefficient = rational
                case .symbol(name):
                    degree += 1
                case .power(.symbol(name), .number(let power)) where power.isInteger && power.numerator > 0:
                    degree += power.numerator
                default:
                    return nil
                }
            }
            guard degree <= 40, let sum = (coefficients[degree] ?? .zero).adding(coefficient) else { return nil }
            coefficients[degree] = sum
        }
        let degree = coefficients.keys.max() ?? 0
        self.init(coefficients: (0...degree).map { coefficients[$0] ?? .zero })
    }

    var degree: Int { coefficients.count - 1 }
    var isZero: Bool { coefficients.isEmpty }
    var leading: Rational { coefficients.last ?? .zero }

    /// The quotient and remainder of the division by a non-zero polynomial.
    func divided(by divisor: UnivariatePolynomial) -> (quotient: UnivariatePolynomial, remainder: UnivariatePolynomial)? {
        guard !divisor.isZero else { return nil }
        var remainder = coefficients
        var quotient = [Rational](repeating: .zero, count: max(0, degree - divisor.degree + 1))
        while remainder.count >= divisor.coefficients.count, let last = remainder.last {
            guard let factor = last.divided(by: divisor.leading) else { return nil }
            let shift = remainder.count - divisor.coefficients.count
            quotient[shift] = factor
            for (index, coefficient) in divisor.coefficients.enumerated() {
                guard let product = coefficient.multiplied(by: factor),
                      let difference = remainder[index + shift].subtracting(product) else { return nil }
                remainder[index + shift] = difference
            }
            remainder.removeLast()
            while let top = remainder.last, top.isZero { remainder.removeLast() }
        }
        return (UnivariatePolynomial(coefficients: quotient), UnivariatePolynomial(coefficients: remainder))
    }

    func dividing(by divisor: UnivariatePolynomial) -> UnivariatePolynomial? {
        guard let division = divided(by: divisor), division.remainder.isZero else { return nil }
        return division.quotient
    }

    /// The monic greatest common divisor, by Euclid's algorithm.
    func greatestCommonDivisor(with other: UnivariatePolynomial) -> UnivariatePolynomial? {
        var (a, b) = (self, other)
        var steps = 0
        while !b.isZero {
            guard steps < 60, let division = a.divided(by: b) else { return nil }
            (a, b) = (b, division.remainder)
            steps += 1
        }
        guard let inverse = a.leading.reciprocal else { return nil }
        var monic: [Rational] = []
        for coefficient in a.coefficients {
            guard let scaled = coefficient.multiplied(by: inverse) else { return nil }
            monic.append(scaled)
        }
        return UnivariatePolynomial(coefficients: monic)
    }

    func term(in name: String) -> Term {
        var terms: [Term] = []
        for (degree, coefficient) in coefficients.enumerated() where !coefficient.isZero {
            let power = degree == 0 ? Term.one : degree == 1 ? Term.symbol(name)
                : Term.power(.symbol(name), .number(Rational(degree)))
            terms.append(Term.multiply([.number(coefficient), power]))
        }
        return Term.add(terms)
    }
}

// MARK: - Writing terms back

/// Writes a term in the syntax of the sheet, so that it parses back to the same
/// term: `3x² + 2x - 3`, `m * v² / 2`, `5 m/s * t`, `√(x + 1)`.
struct TermPrinter {
    /// The position of each name's first appearance in the original formula, to keep its order.
    var order: [String: Int] = [:]
    /// Coefficients that terminate are written as decimals (0,5 * m) rather than fractions (m / 2).
    var prefersDecimals = false

    private enum Precedence: Int, Comparable {
        case sum, product, negation, power, atom
        static func < (lhs: Precedence, rhs: Precedence) -> Bool { lhs.rawValue < rhs.rawValue }
    }

    func string(_ term: Term) -> String {
        render(term).text
    }

    /// The length of the written term without spaces, which measures how simple it looks.
    func length(_ term: Term) -> Int {
        string(term).filter { !$0.isWhitespace }.count
    }

    private func render(_ term: Term) -> (text: String, precedence: Precedence) {
        let (negative, magnitude) = Self.sign(of: term)
        if negative {
            let inner = render(magnitude)
            return ("-" + (inner.precedence < .negation ? "(\(inner.text))" : inner.text), .negation)
        }
        switch term {
        case .number(let rational):
            if rational.isInteger { return (String(rational.numerator), .atom) }
            let text = rational.formattedMagnitude(prefersDecimals: prefersDecimals)
            return (text, text.contains("/") ? .product : .atom)
        case .real(let value):
            let text = QuantityFormatter.number(value, significantDigits: QuantityFormatter.preciseDigits)
            return (text, text.contains(" ") ? .product : .atom)
        case .symbol(let name):
            return (name, .atom)
        case .unit:
            return renderProduct([term])
        case .sum(let terms):
            var flat: [Term] = []
            for part in terms {
                if case .sum(let inner) = part { flat.append(contentsOf: inner) } else { flat.append(part) }
            }
            var text = ""
            for (index, part) in sortedForSum(flat).enumerated() {
                let (isNegative, magnitude) = Self.sign(of: part)
                var piece = render(magnitude)
                if piece.precedence <= .sum { piece.text = "(\(piece.text))" }
                if index == 0 {
                    text = (isNegative ? "-" : "") + piece.text
                } else {
                    text += (isNegative ? " - " : " + ") + piece.text
                }
            }
            return (text, .sum)
        case .product(let factors):
            return renderProduct(factors)
        case .power(let base, let exponent):
            return renderPower(base, exponent)
        case .function(let name, let arguments):
            return ("\(name)(" + arguments.map { render($0).text }.joined(separator: "; ") + ")", .atom)
        case .factorial(let argument):
            let inner = render(argument)
            return ((inner.precedence == .atom && !inner.text.hasPrefix("-") ? inner.text : "(\(inner.text))") + "!", .power)
        }
    }

    /// Whether the term starts with a minus, and the term without it.
    private static func sign(of term: Term) -> (Bool, Term) {
        switch term {
        case .number(let rational) where rational.isNegative:
            return (true, .number(rational.negated ?? rational))
        case .real(let value) where value < 0:
            return (true, .real(-value))
        case .product(let factors):
            let numbers = factors.compactMap(\.numeric)
            let negatives = numbers.filter(\.isNegative).count
            guard negatives % 2 == 1 else { return (false, term) }
            var flipped = false
            var positive: [Term] = []
            for factor in factors {
                if !flipped, let value = factor.numeric, value.isNegative {
                    flipped = true
                    let magnitude = value.negated
                    if !magnitude.isOne || factors.count == 1 { positive.append(magnitude.term) }
                } else {
                    positive.append(factor)
                }
            }
            return (true, positive.count == 1 ? positive[0] : .product(positive))
        default:
            return (false, term)
        }
    }

    private func renderProduct(_ factors: [Term]) -> (text: String, precedence: Precedence) {
        var flat: [Term] = []
        func absorb(_ factor: Term) {
            if case .product(let inner) = factor { inner.forEach(absorb) } else { flat.append(factor) }
        }
        factors.forEach(absorb)
        var numbers: [Numeric] = []
        var numeratorUnits: [(String, Int)] = [], denominatorUnits: [(String, Int)] = []
        var numerator: [Term] = [], denominator: [Term] = []
        for factor in flat {
            if let value = factor.numeric {
                numbers.append(value)
                continue
            }
            switch factor {
            case .unit(let symbol):
                numeratorUnits.append((symbol, 1))
            case .power(.unit(let symbol), .number(let power)) where power.isInteger:
                if power.isNegative { denominatorUnits.append((symbol, -power.numerator)) }
                else { numeratorUnits.append((symbol, power.numerator)) }
            case .power(let base, .number(let power)) where power.isNegative:
                let positive = power.negated ?? power
                denominator.append(positive == .one ? base : .power(base, .number(positive)))
            case .power(let base, .real(let power)) where power < 0:
                denominator.append(.power(base, .real(-power)))
            default:
                numerator.append(factor)
            }
        }
        // The coefficient: one number, written as a decimal or split into a fraction.
        var head: [String] = []
        var denominatorNumber: String?
        if numbers.count == 1, case .exact(let rational) = numbers[0], !rational.isInteger,
           !(prefersDecimals && rational.decimalMagnitude() != nil) {
            if rational.numerator != 1 { head.append(String(rational.numerator)) }
            denominatorNumber = String(rational.denominator)
        } else {
            for number in numbers where !(number.isOne && numbers.count == 1) {
                head.append(render(number.term).text)
            }
        }
        let hasUnits = !numeratorUnits.isEmpty || !denominatorUnits.isEmpty
        if hasUnits {
            var chain = numeratorUnits.map { $0.0 + Self.superscript($0.1) }.joined(separator: "*")
            for (symbol, power) in denominatorUnits { chain += "/" + symbol + Self.superscript(power) }
            let number = head.isEmpty ? "1" : head.removeLast()
            head.append(number + " " + chain)
        }
        let parts = sortedForProduct(numerator).map { factor -> String in
            let piece = render(factor)
            return piece.precedence < .negation ? "(\(piece.text))" : piece.text
        }
        var text: String
        if head.count == 1, !hasUnits, let first = parts.first, Int(head[0]) != nil, Self.canFollowNumber(first) {
            text = ([head[0] + first] + parts.dropFirst()).joined(separator: " * ")
        } else {
            text = (head + parts).joined(separator: " * ")
        }
        var bottom = sortedForProduct(denominator).map { factor -> (String, Precedence) in
            let piece = render(factor)
            return piece.precedence < .negation ? ("(\(piece.text))", .atom) : (piece.text, piece.precedence)
        }
        if let denominatorNumber { bottom.insert((denominatorNumber, .atom), at: 0) }
        guard !bottom.isEmpty else {
            if text.isEmpty { text = "1" }
            return (text, flat.count == 1 && !hasUnits ? render(flat[0]).precedence : .product)
        }
        if text.isEmpty { text = "1" }
        let below: String
        if bottom.count == 1 && bottom[0].1 >= .power {
            below = bottom[0].0
        } else {
            var pieces = bottom.map(\.0)
            if pieces.count > 1, Int(pieces[0]) != nil, Self.canFollowNumber(pieces[1]) {
                pieces[0...1] = [pieces[0] + pieces[1]]
            }
            below = "(" + pieces.joined(separator: " * ") + ")"
        }
        return (text + " / " + below, .product)
    }

    private func renderPower(_ base: Term, _ exponent: Term) -> (text: String, precedence: Precedence) {
        if let value = exponent.numeric, value.isNegative { return renderProduct([.power(base, exponent)]) }
        if case .unit = base { return renderProduct([.power(base, exponent)]) }
        let inner = render(base)
        if case .number(let power) = exponent, power == Rational(1, 2) {
            let radicand = inner.precedence == .atom && !Self.isFraction(base) ? inner.text : "(\(inner.text))"
            return ("√" + radicand, .power)
        }
        let lower = inner.precedence == .atom && !Self.isFraction(base) ? inner.text : "(\(inner.text))"
        if case .number(let power) = exponent, power.isInteger {
            return (lower + Self.superscript(power.numerator), .power)
        }
        let upper = render(exponent)
        return (lower + "^" + (upper.precedence == .atom ? upper.text : "(\(upper.text))"), .power)
    }

    private static func isFraction(_ term: Term) -> Bool {
        if case .number(let rational) = term { return !rational.isInteger }
        if case .real = term { return true }
        return false
    }

    /// Names, powers of names, radicals and parentheses can follow a whole number
    /// directly (2x, 3x², 2√3, 4(a + b)); `e` and `E` cannot, since 2e3 is a number.
    private static func canFollowNumber(_ text: String) -> Bool {
        guard let first = text.first else { return false }
        if first == "(" || first == "√" { return true }
        guard first.isLetter, first != "e", first != "E" else { return false }
        let name = text.prefix { !"⁰¹²³⁴⁵⁶⁷⁸⁹⁻".contains($0) }
        return name.count == 1
    }

    static func superscript(_ value: Int) -> String {
        guard value != 1 else { return "" }
        let digits: [Character: Character] = [
            "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵", "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻"
        ]
        return String(String(value).compactMap { digits[$0] })
    }

    // MARK: Order

    /// The appearance of the term's first name, or nil for a term without names.
    private func rank(_ term: Term) -> Int? {
        term.symbols.compactMap { order[$0] ?? Int.max / 2 }.min()
    }

    private func degree(_ term: Term, of name: String) -> Double {
        switch term {
        case .symbol(name): return 1
        case .power(.symbol(name), let exponent): return exponent.numeric?.doubleValue ?? 1
        case .product(let factors): return factors.reduce(0) { $0 + degree($1, of: name) }
        default: return 0
        }
    }

    /// Terms by their first name in the formula, highest powers first, numbers last:
    /// 3x² + 2x - 3, v0 + a * t.
    private func sortedForSum(_ terms: [Term]) -> [Term] {
        terms.enumerated().sorted { lhs, rhs in
            let (a, b) = (rank(lhs.element), rank(rhs.element))
            if a != b { return (a ?? .max) < (b ?? .max) }
            if let a, let name = order.first(where: { $0.value == a })?.key {
                let (da, db) = (degree(lhs.element, of: name), degree(rhs.element, of: name))
                if da != db { return da > db }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    /// Factors by their first name in the formula; numeric radicals such as √2 first.
    private func sortedForProduct(_ factors: [Term]) -> [Term] {
        factors.enumerated().sorted { lhs, rhs in
            let (a, b) = (rank(lhs.element) ?? -1, rank(rhs.element) ?? -1)
            return a != b ? a < b : lhs.offset < rhs.offset
        }.map(\.element)
    }
}

extension Term {
    /// The position of each name's first appearance, reading the expression from the left.
    static func appearanceOrder(of expression: Expression) -> [String: Int] {
        var order: [String: Int] = [:]
        func visit(_ expression: Expression) {
            switch expression {
            case .identifier(let name):
                if order[name] == nil { order[name] = order.count }
            case .unary(_, let argument), .factorial(let argument), .compactUnits(let argument):
                visit(argument)
            case .binary(_, let left, let right):
                visit(left)
                visit(right)
            case .function(_, let arguments):
                arguments.forEach(visit)
            case .number, .unit:
                break
            }
        }
        visit(expression)
        return order
    }
}

// MARK: - Simplifying a line

/// Simplification on request: the same formula, written more simply.
public enum FormulaSimplifier {
    /// The line with a simpler, equivalent formula, keeping its declared name, its
    /// conversion, its request `=` and its comment; nil when nothing is simpler.
    /// Both sides of an equality are simplified separately.
    public static func simplifiedLine(_ source: String) -> String? {
        guard source.count <= 1_000 else { return nil }
        let syntax = LineSyntax(source)
        guard syntax.unknownUnit == nil, syntax.separatorCount <= 1 else { return nil }
        let body = syntax.body.trimmingCharacters(in: .whitespaces)
        guard !body.isEmpty else { return nil }
        if let separator = syntax.separatorRange {
            let left = source[..<separator.lowerBound].trimmingCharacters(in: .whitespaces)
            let right = source[separator.upperBound..<syntax.bodyRange.upperBound].trimmingCharacters(in: .whitespaces)
            let sign = String(source[separator])
            guard !left.isEmpty, !right.isEmpty else { return nil }
            if let name = syntax.definitionName {
                guard let simpler = simplified(right) else { return nil }
                return syntax.replacingBody("\(name) \(sign) \(simpler)")
            }
            let simplerLeft = simplified(left), simplerRight = simplified(right)
            guard simplerLeft != nil || simplerRight != nil else { return nil }
            return syntax.replacingBody("\(simplerLeft ?? left) \(sign) \(simplerRight ?? right)")
        }
        return simplified(body).map(syntax.replacingBody)
    }

    /// The simplest equivalent of an expression, or nil when it is already as simple.
    static func simplified(_ source: String) -> String? {
        guard var parser = try? ExpressionParser(source), let expression = try? parser.parse(),
              let written = Term(expression), written.size <= 300 else { return nil }
        let printer = TermPrinter(order: Term.appearanceOrder(of: expression),
                                  prefersDecimals: containsDecimal(source))
        // Shorter first, then smaller numbers: √12 and 2√3 have the same length.
        func score(_ term: Term) -> (Int, Double) { (printer.length(term), term.numberWeight) }
        let original = score(written)
        var best: (term: Term, score: (Int, Double))?
        for candidate in Term.simplificationCandidates(of: written) {
            let candidateScore = score(candidate)
            if best.map({ candidateScore < $0.score }) ?? true { best = (candidate, candidateScore) }
        }
        guard let best, best.score < original else { return nil }
        let text = printer.string(best.term)
        guard text != printer.string(written) else { return nil }
        // The text must read back as the same term.
        guard var check = try? ExpressionParser(text), let reparsed = try? check.parse(),
              Term(reparsed)?.simplified == best.term.simplified else { return nil }
        return text
    }

    private static func containsDecimal(_ source: String) -> Bool {
        let characters = Array(source)
        return characters.indices.dropFirst().dropLast().contains { index in
            (characters[index] == "," || characters[index] == ".")
                && characters[index - 1].isNumber && characters[index + 1].isNumber
        }
    }
}
