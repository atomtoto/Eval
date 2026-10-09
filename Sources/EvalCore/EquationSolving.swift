import Foundation

/// The real solutions of an equation in one unknown, as `x =` shows them
/// after `3x² + 2x − 3 = 0`.
public struct EquationSolutions: Sendable, Equatable {
    /// The solutions in the order they are shown.
    public let values: [Quantity]
    /// The exact form when it says more than the decimals, such as `(−1 ± √10)/3`.
    public let exact: String?
    /// The solution that the rest of the sheet uses.
    public let principalIndex: Int

    public var principal: Quantity { values[principalIndex] }

    /// « (−1 ± √10)/3 ≈ 0,720759 ; −1,38743 ». A display unit shows the decimals only.
    public func formatted(in unit: DisplayUnit?) -> String {
        let decimals = values.map { QuantityFormatter.string($0, in: unit) }.joined(separator: " ; ")
        guard let exact, unit == nil else { return decimals }
        return exact + " ≈ " + decimals
    }

    /// The solutions read aloud, joined by « ou ».
    public func spoken(in unit: DisplayUnit?) -> String {
        values.map { QuantityFormatter.spokenString($0, in: unit) }.joined(separator: " ou ")
    }
}

/// The real roots of a polynomial with `Double` coefficients.
enum RealPolynomial {
    /// The distinct real roots of Σ cₖxᵏ (lowest degree first, leading coefficient
    /// non-zero), ascending, each with its multiplicity.
    static func roots(_ coefficients: [Double]) -> [(value: Double, multiplicity: Int)] {
        let found = distinctRoots(coefficients)
        return found.map { root in (root, multiplicity(of: root, in: coefficients)) }
    }

    private static func distinctRoots(_ c: [Double]) -> [Double] {
        let degree = c.count - 1
        switch degree {
        case ..<1:
            return []
        case 1:
            return [-c[0] / c[1]]
        case 2:
            return quadratic(c[2], c[1], c[0])
        default:
            break
        }
        let derivative = (1...degree).map { Double($0) * c[$0] }
        let critical = distinctRoots(derivative)
        let bound = 1 + (0..<degree).map { abs(c[$0] / c[degree]) }.max()!
        let points = [-bound] + critical.filter { abs($0) < bound } + [bound]
        var roots: [Double] = []
        for (a, b) in zip(points, points.dropFirst()) {
            let (fa, fb) = (value(c, at: a), value(c, at: b))
            if fa == 0 { roots.append(a) }
            if fa.sign != fb.sign, fa != 0, fb != 0 { roots.append(bisect(c, a, b, fa)) }
        }
        if value(c, at: bound) == 0 { roots.append(bound) }
        // A critical point where the polynomial vanishes is a multiple root.
        for point in critical where abs(value(c, at: point)) <= tolerance(c, at: point) { roots.append(point) }
        return deduplicated(roots.sorted())
    }

    /// The roots of ax² + bx + c, with the stable formula; a double root once.
    private static func quadratic(_ a: Double, _ b: Double, _ c: Double) -> [Double] {
        let discriminant = b * b - 4 * a * c
        if abs(discriminant) <= 1e-12 * max(b * b, abs(4 * a * c)) { return [-b / (2 * a)] }
        guard discriminant > 0 else { return [] }
        let q = -0.5 * (b + (b < 0 ? -1 : 1) * discriminant.squareRoot())
        let roots = [q / a, c / q]
        return roots.sorted()
    }

    static func value(_ c: [Double], at x: Double) -> Double {
        c.reversed().reduce(0) { $0 * x + $1 }
    }

    /// The size of the terms at x: a residue below a small part of it is a zero.
    private static func tolerance(_ c: [Double], at x: Double) -> Double {
        var magnitude = 0.0, power = 1.0
        for coefficient in c {
            magnitude += abs(coefficient) * power
            power *= abs(x)
        }
        return magnitude * 1e-9
    }

    private static func bisect(_ c: [Double], _ start: Double, _ end: Double, _ startValue: Double) -> Double {
        var (a, b, fa) = (start, end, startValue)
        for _ in 0..<200 {
            let middle = (a + b) / 2
            guard middle != a, middle != b else { break }
            let fm = value(c, at: middle)
            if fm == 0 { return middle }
            if fm.sign == fa.sign { (a, fa) = (middle, fm) } else { b = middle }
        }
        return (a + b) / 2
    }

    private static func deduplicated(_ sorted: [Double]) -> [Double] {
        var result: [Double] = []
        for root in sorted {
            if let last = result.last, abs(root - last) <= 1e-9 * max(1, abs(root)) { continue }
            result.append(root)
        }
        return result
    }

    private static func multiplicity(of root: Double, in coefficients: [Double]) -> Int {
        var current = coefficients
        var count = 1
        while current.count > 2 {
            current = (1..<current.count).map { Double($0) * current[$0] }
            guard abs(value(current, at: root)) <= tolerance(current, at: root) * 10 else { break }
            count += 1
        }
        return count
    }
}

/// The roots of a polynomial with whole coefficients, written exactly: rational
/// roots are found and divided out, and a remaining quadratic gives (−b ± s√d)/q.
struct ExactPolynomialRoots {
    /// A real root and its exact spelling, in the order shown.
    struct Root {
        let value: Double
        let multiplicity: Int
    }

    /// Rational roots, ascending, then the pair of an irrational quadratic factor.
    private(set) var roots: [Root] = []
    /// The spellings of the roots: one per rational root, one « ± » for a pair.
    private(set) var spellings: [String] = []
    /// Two complex roots, written exactly: « (−1 ± i√2)/3 ».
    private(set) var complexPair: String?

    /// Nil when a factor of degree three or more has no rational root, or on overflow.
    init?(_ coefficients: [Int]) {
        // Leading zeros are roots at zero: x³ − 2x is x · (x² − 2).
        let zeros = coefficients.prefix { $0 == 0 }.count
        guard zeros < coefficients.count else { return nil }
        var polynomial = UnivariatePolynomial(coefficients: coefficients.dropFirst(zeros).map { Rational($0) })
        var rational = [Rational](repeating: .zero, count: zeros)
        while polynomial.degree >= 3 {
            guard let root = Self.rationalRoot(of: polynomial),
                  let factor = Rational(-1).multiplied(by: root).map({ UnivariatePolynomial(coefficients: [$0, .one]) }),
                  let quotient = polynomial.dividing(by: factor) else { return nil }
            rational.append(root)
            polynomial = quotient
        }
        switch polynomial.degree {
        case 1:
            guard let root = polynomial.coefficients[0].negated?.divided(by: polynomial.coefficients[1]) else { return nil }
            rational.append(root)
        case 2:
            guard let quadratic = Self.quadratic(polynomial) else { return nil }
            switch quadratic {
            case .rational(let first, let second):
                rational.append(contentsOf: [first, second])
            case .pair(let spelling, let plus, let minus):
                spellings.append(spelling)
                roots += [Root(value: plus, multiplicity: 1), Root(value: minus, multiplicity: 1)]
            case .complex(let spelling):
                complexPair = spelling
            }
        default:
            break
        }
        // Rational roots first, ascending, with their multiplicity.
        var distinct: [(Rational, Int)] = []
        for root in rational.sorted(by: { $0.doubleValue < $1.doubleValue }) {
            if let last = distinct.last, last.0 == root { distinct[distinct.count - 1].1 += 1 } else { distinct.append((root, 1)) }
        }
        roots = distinct.map { Root(value: $0.0.doubleValue, multiplicity: $0.1) } + roots
        spellings = distinct.map { $0.0.formatted } + spellings
        allRational = spellings.count == distinct.count
        terminating = distinct.allSatisfy { $0.0.decimalMagnitude() != nil }
    }

    private(set) var allRational = true
    private(set) var terminating = true

    /// The exact form, when it says more than the decimals.
    var exactSpelling: String? {
        guard !roots.isEmpty, !(allRational && terminating) else { return nil }
        return spellings.joined(separator: " ; ")
    }

    private enum Quadratic {
        case rational(Rational, Rational)
        case pair(String, plus: Double, minus: Double)
        case complex(String)
    }

    /// ax² + bx + c with whole a > 0, b, c.
    private static func quadratic(_ polynomial: UnivariatePolynomial) -> Quadratic? {
        let coefficients = polynomial.coefficients
        guard coefficients.allSatisfy(\.isInteger) else { return nil }
        let (c, b, a) = (coefficients[0].numerator, coefficients[1].numerator, coefficients[2].numerator)
        let (bb, o1) = b.multipliedReportingOverflow(by: b)
        let (ac, o2) = a.multipliedReportingOverflow(by: c)
        let (four, o3) = ac.multipliedReportingOverflow(by: 4)
        let (discriminant, o4) = bb.subtractingReportingOverflow(four)
        let (twoA, o5) = a.multipliedReportingOverflow(by: 2)
        guard !(o1 || o2 || o3 || o4 || o5), b != .min else { return nil }
        let (outside, inside) = Term.perfectPower(of: abs(discriminant), root: 2)
        if inside == 1 || discriminant == 0 {
            let root = discriminant == 0 ? 0 : outside
            guard discriminant >= 0, let first = Rational(-b + root, twoA), let second = Rational(-b - root, twoA) else {
                return .complex(spelling(-b, outside, 1, twoA, imaginary: true))
            }
            return .rational(first, second)
        }
        if discriminant < 0 { return .complex(spelling(-b, outside, inside, twoA, imaginary: true)) }
        let radical = Double(outside) * Double(inside).squareRoot()
        return .pair(spelling(-b, outside, inside, twoA, imaginary: false),
                     plus: (Double(-b) + radical) / Double(twoA), minus: (Double(-b) - radical) / Double(twoA))
    }

    /// (p ± s√d)/q reduced: « (−1 ± √10)/3 », « ±√2/2 », « 1 ± 2i ».
    private static func spelling(_ p: Int, _ s: Int, _ d: Int, _ q: Int, imaginary: Bool) -> String {
        let divisor = Rational.gcd(Rational.gcd(p, s), q)
        let (p, s, q) = (p / divisor, s / divisor, q / divisor)
        let coefficient = s == 1 && !(d == 1 && !imaginary) ? "" : String(s)
        let radical = coefficient + (imaginary ? "i" : "") + (d == 1 ? "" : "√\(d)")
        let numerator = p == 0 ? "±" + radical : (p < 0 ? "−" : "") + "\(abs(p)) ± " + radical
        guard q != 1 else { return numerator }
        return (p == 0 ? numerator : "(" + numerator + ")") + "/\(q)"
    }

    /// A rational root p/q of the polynomial, with p dividing the constant term and
    /// q the leading coefficient. The constant term is not zero.
    private static func rationalRoot(of polynomial: UnivariatePolynomial) -> Rational? {
        guard polynomial.coefficients.allSatisfy(\.isInteger),
              let constant = polynomial.coefficients.first?.numerator, constant != 0,
              let constantDivisors = divisors(of: abs(constant)), let leadingDivisors = divisors(of: abs(polynomial.leading.numerator))
        else { return nil }
        var candidates = Set<Rational>()
        for p in constantDivisors {
            for q in leadingDivisors {
                guard let candidate = Rational(p, q) else { continue }
                candidates.insert(candidate)
                if let negative = candidate.negated { candidates.insert(negative) }
                guard candidates.count <= 4_000 else { return nil }
            }
        }
        return candidates.sorted { $0.doubleValue < $1.doubleValue }.first { isRoot($0, of: polynomial) }
    }

    private static func isRoot(_ x: Rational, of polynomial: UnivariatePolynomial) -> Bool {
        var value = Rational.zero
        for coefficient in polynomial.coefficients.reversed() {
            guard let product = value.multiplied(by: x), let sum = product.adding(coefficient) else { return false }
            value = sum
        }
        return value.isZero
    }

    private static func divisors(of value: Int) -> [Int]? {
        guard value > 0, value <= 1_000_000_000_000 else { return nil }
        var small: [Int] = [], large: [Int] = []
        var candidate = 1
        while candidate * candidate <= value {
            if value % candidate == 0 {
                small.append(candidate)
                if candidate * candidate != value { large.append(value / candidate) }
            }
            candidate += 1
        }
        return small + large.reversed()
    }
}
