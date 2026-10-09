import Foundation

/// Finds roots of a function of one real variable by scanning magnitudes from
/// 10⁻¹² to 10¹² in log space on both signs, then refining a sign change with
/// Brent's method. The function returns `nil` where it is undefined, and a sign
/// change is never taken across such a gap. The evaluation count stays bounded.
struct RootSearch {
    /// 0,2 decade between scan points: 121 per sign.
    static let pointsPerSign = 121
    static let maxEvaluations = 600
    /// A pole flips the sign too; a root leaves a residual far below the scanned values.
    private static let residualRatio = 1e-6
    private static let relativeTolerance = 1e-13

    struct Outcome {
        /// The smallest positive root and the negative root of smallest magnitude.
        var positive: Double?
        var negative: Double?
        /// More sign changes were found beyond the ones refined.
        var hasMore = false
        /// Every root refined, ascending, when the search collects them all.
        var roots: [Double] = []
        /// Evaluations that returned a value, and all evaluations.
        var valid = 0
        var evaluations = 0
    }

    private let function: (Double) throws -> Double?
    /// Refines every sign change instead of the first one on each side, with a larger budget.
    private let collectsAll: Bool
    private let budget: Int
    private(set) var evaluations = 0
    private(set) var valid = 0

    init(collectsAll: Bool = false, _ function: @escaping (Double) throws -> Double?) {
        self.function = function
        self.collectsAll = collectsAll
        budget = collectsAll ? 3 * Self.maxEvaluations : Self.maxEvaluations
    }

    private struct Bracket {
        let a: Double, fa: Double, b: Double, fb: Double
    }

    mutating func run() throws -> Outcome {
        var outcome = Outcome()
        for sign in [1.0, -1.0] {
            let brackets = try scan(sign: sign)
            for (index, bracket) in brackets.enumerated() {
                guard let root = try refine(bracket) else {
                    if collectsAll, evaluations >= budget { outcome.hasMore = true }
                    continue
                }
                if collectsAll {
                    outcome.roots.append(root)
                    continue
                }
                if sign > 0 { outcome.positive = root } else { outcome.negative = root }
                if brackets.count > index + 1 { outcome.hasMore = true }
                break
            }
        }
        outcome.roots.sort()
        outcome.valid = valid
        outcome.evaluations = evaluations
        return outcome
    }

    private mutating func value(_ x: Double) throws -> Double? {
        evaluations += 1
        let result = try function(x)
        if result != nil { valid += 1 }
        return result
    }

    private mutating func scan(sign: Double) throws -> [Bracket] {
        var brackets: [Bracket] = []
        var previous: (x: Double, f: Double)?
        for step in 0..<Self.pointsPerSign {
            let x = sign * Foundation.pow(10, -12 + 0.2 * Double(step))
            guard let fx = try value(x) else { previous = nil; continue }
            if fx == 0 {
                brackets.append(Bracket(a: x, fa: 0, b: x, fb: 0))
            } else if let before = previous, before.f != 0, (before.f < 0) != (fx < 0) {
                brackets.append(Bracket(a: before.x, fa: before.f, b: x, fb: fx))
            }
            previous = (x, fx)
        }
        return brackets
    }

    /// Brent's method on a bracket; `nil` for a pole, a gap or an exhausted budget.
    private mutating func refine(_ bracket: Bracket) throws -> Double? {
        if bracket.fa == 0 { return bracket.a }
        var (a, b, fa, fb) = (bracket.a, bracket.b, bracket.fa, bracket.fb)
        var (c, fc) = (b, fb)
        var d = b - a
        var e = d
        let largest = max(abs(fa), abs(fb))
        // Multiple roots make plain Brent crawl; bisect when the bracket stops halving.
        var width = abs(c - b)
        var stalled = 0
        for _ in 0..<150 {
            guard evaluations < budget else { return nil }
            if (fb > 0) == (fc > 0) { (c, fc) = (a, fa); d = b - a; e = d }
            if abs(fc) < abs(fb) { (a, b, c) = (b, c, b); (fa, fb, fc) = (fb, fc, fb) }
            let tolerance = 2 * Double.ulpOfOne * abs(b) + 0.5 * Self.relativeTolerance * abs(b)
            let half = 0.5 * (c - b)
            if abs(half) <= tolerance || fb == 0 {
                return abs(fb) <= Self.residualRatio * largest ? b : nil
            }
            if abs(c - b) <= width / 2 { width = abs(c - b); stalled = 0 } else { stalled += 1 }
            if abs(e) >= tolerance, abs(fa) > abs(fb), stalled < 3 {
                var p: Double, q: Double
                let s = fb / fa
                if a == c {
                    p = 2 * half * s
                    q = 1 - s
                } else {
                    let ratio = fa / fc, r = fb / fc
                    p = s * (2 * half * ratio * (ratio - r) - (b - a) * (r - 1))
                    q = (ratio - 1) * (r - 1) * (s - 1)
                }
                if p > 0 { q = -q }
                p = abs(p)
                if 2 * p < min(3 * half * q - abs(tolerance * q), abs(e * q)) {
                    e = d
                    d = p / q
                } else {
                    d = half
                    e = d
                }
            } else {
                d = half
                e = d
            }
            (a, fa) = (b, fb)
            b += abs(d) > tolerance ? d : (half > 0 ? tolerance : -tolerance)
            guard let next = try value(b) else { return nil }
            fb = next
        }
        return nil
    }
}
