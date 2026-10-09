import Foundation

/// A directly entered number that can be adjusted without rewriting a formula.
/// Its value stays in the entered unit: `v = 5 km/s` exposes 5, not 5,000.
public struct AdjustableVariable: Sendable {
    public let name: String
    public let value: Double
    public let unit: String
    /// Resolution of the entered literal, including significant trailing zeros.
    /// 6 → 1; 8,2 → 0.1; 8,20 → 0.01; 1,2e3 → 100.
    public let automaticStep: Double
    /// The number, sign included, in the source given to `init(source:)`.
    /// A line may end with the request `=` (`m = 80 kg =`) and stays adjustable.
    public let literalRange: Range<String.Index>

    private let prefix: String
    private let suffix: String
    private let usesDecimalComma: Bool
    private let fractionalDigits: Int
    private let literalExponent: Int
    private let usesScientificNotation: Bool
    /// SI size of the entered unit, so the engine need not re-check each new value.
    private let unitScale: Double
    /// A display conversion adds a check on the converted value.
    private let hasConversion: Bool

    /// Accepts a single signed literal and an optional, unambiguous unit suffix.
    /// Expressions, comparisons, dependent variables and invalid units are excluded.
    public init?(source: String) {
        guard source.count <= 2_000, source.rangeOfCharacter(from: .newlines) == nil else { return nil }
        let line = LineSyntax(source)
        guard line.separatorCount == 1, !line.isComparison, let identifier = line.definitionName,
              let separator = line.separatorRange else { return nil }
        // The value ends the body; a display conversion and a comment stay in `suffix`.
        let contentEnd = line.bodyRange.upperBound
        guard let literalStart = source[separator.upperBound..<contentEnd].firstIndex(where: { !$0.isWhitespace }) else {
            return nil
        }
        let rightHandSide = String(source[literalStart..<contentEnd])
        let pattern = #"^[+\-−–]?\h*(?:[0-9]+(?:[.,][0-9]*)?|[.,][0-9]+)(?:[eE][+\-−–]?[0-9]+)?"#
        guard let literalRange = rightHandSide.range(of: pattern, options: .regularExpression) else { return nil }
        let literal = String(rightHandSide[literalRange])
        let normalized = literal.filter { !$0.isWhitespace }
            .replacingOccurrences(of: ",", with: ".")
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: "–", with: "-")
        guard let number = Double(normalized), number.isFinite,
              var parser = try? ExpressionParser(rightHandSide),
              let expression = try? parser.parse(), Self.isLiteralWithUnits(expression),
              !Self.compactChainUses(identifier, in: expression),
              (try? NotebookEngine.standaloneQuantity(expression)) != nil,
              // The converted display is checked by the engine itself, which is rare enough.
              line.arrowRange == nil || NotebookEngine.evaluate(source).lines.first?.status == .success,
              let scale = Self.scale(ofUnitsIn: expression) else { return nil }

        let literalEnd = source.index(literalStart, offsetBy: literal.count)
        let unitSuffix = source[literalEnd..<contentEnd].trimmingCharacters(in: .whitespaces)
        self.literalRange = literalStart..<literalEnd
        unitScale = scale
        hasConversion = line.arrowRange != nil
        name = identifier
        value = number
        unit = unitSuffix
        prefix = String(source[..<literalStart])
        suffix = String(source[literalEnd...])
        usesDecimalComma = literal.contains(",")
        let components = normalized.lowercased().split(separator: "e", omittingEmptySubsequences: false)
        let mantissa = String(components[0])
        fractionalDigits = mantissa.firstIndex(of: ".").map { mantissa.distance(from: mantissa.index(after: $0), to: mantissa.endIndex) } ?? 0
        literalExponent = components.count == 2 ? Int(components[1]) ?? 0 : 0
        usesScientificNotation = components.count == 2
        automaticStep = Self.step(decimalExponent: literalExponent - fractionalDigits)
    }

    /// Replaces only the number, retaining spacing, units, conversion and comment verbatim.
    /// Swift's shortest round-trip representation avoids rounding the input value.
    public func source(replacingValue value: Double) -> String? {
        guard value.isFinite else { return nil }
        var literal = String(value)
        // Preserve the entered resolution whenever it represents the new value
        // exactly. Arbitrary replacements still retain their full precision.
        let scaled = usesScientificNotation ? value / Self.step(decimalExponent: literalExponent) : value
        if scaled.isFinite, fractionalDigits <= 16 {
            let candidate = String(format: "%.*f", fractionalDigits, scaled)
                + (usesScientificNotation ? "e\(literalExponent)" : "")
            // One ulp of tolerance absorbs a binary sum such as 0.9199999999999999.
            if let parsed = Double(candidate),
               parsed == value || parsed != 0 && (parsed.nextUp == value || parsed.nextDown == value) {
                literal = candidate
            }
        }
        if usesDecimalComma { literal = literal.replacingOccurrences(of: ".", with: ",") }
        let result = prefix + literal + suffix
        // The engine accepts a finite literal whose product with the unit stays finite.
        guard let parsed = Double(literal.replacingOccurrences(of: ",", with: ".")), parsed.isFinite,
              (parsed * unitScale).isFinite,
              !hasConversion || NotebookEngine.evaluate(result).lines.first?.status == .success else { return nil }
        return result
    }

    /// The size in SI of the unit suffix, 1 without one. A zero or infinite factor
    /// cannot be adjusted reliably.
    private static func scale(ofUnitsIn expression: Expression) -> Double? {
        var node = expression
        while case .unary(_, let operand) = node { node = operand }
        guard case .binary(.multiply, _, let units) = node else { return 1 }
        guard let scale = (try? NotebookEngine.standaloneQuantity(units))?.value, scale > 0, scale.isFinite else { return nil }
        return scale
    }

    /// `h = 2km/h` reads `h` as a variable inside its own compact unit chain: a cycle.
    private static func compactChainUses(_ name: String, in expression: Expression) -> Bool {
        var node = expression
        while case .unary(_, let operand) = node { node = operand }
        guard case .binary(.multiply, _, .compactUnits(let units)) = node else { return false }
        var pending = [units]
        while let next = pending.popLast() {
            switch next {
            case .unit(let symbol): if symbol == name { return true }
            case .binary(_, let left, let right): pending.append(contentsOf: [left, right])
            default: break
            }
        }
        return false
    }

    private static func step(decimalExponent: Int) -> Double {
        let power = pow(10.0, Double(min(308, max(-323, decimalExponent))))
        return decimalExponent < -323 ? .leastNonzeroMagnitude : power
    }

    static func isLiteralWithUnits(_ expression: Expression) -> Bool {
        switch expression {
        case .number:
            return true
        case .unary(_, let operand):
            return isLiteralWithUnits(operand)
        case .binary(.multiply, let number, let units):
            // The parser tags only suffix units as .unit. Ordinary identifiers
            // might denote a declared variable, even when their spelling is m or s.
            return isSignedNumber(number) && isUnitExpression(units)
        default:
            return false
        }
    }

    private static func isSignedNumber(_ expression: Expression) -> Bool {
        switch expression {
        case .number: return true
        case .unary(_, let number): return isSignedNumber(number)
        default: return false
        }
    }

    private static func isUnitExpression(_ expression: Expression) -> Bool {
        switch expression {
        case .unit: return true
        case .compactUnits(let units): return isUnitExpression(units)
        case .binary(.multiply, let left, let right), .binary(.divide, let left, let right):
            return isUnitExpression(left) && isUnitExpression(right)
        case .binary(.power, let units, let exponent):
            return isUnitExpression(units) && isSignedNumber(exponent)
        default: return false
        }
    }
}

/// A finite adjustment interval mapped onto the system slider's 0...1 range.
public struct VariableAdjustmentRange: Codable, Equatable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    public let step: Double

    public init?(lowerBound: Double, upperBound: Double, step: Double) {
        let span = upperBound - lowerBound
        guard lowerBound.isFinite, upperBound.isFinite, step.isFinite,
              span.isFinite, span > 0, step > 0, step <= span,
              (span / step).isFinite else { return nil }
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.step = step
    }

    public static func suggested(for value: Double, step requestedStep: Double? = nil) -> Self? {
        guard value.isFinite else { return nil }
        let lower: Double
        let upper: Double
        if value == 0 {
            lower = -10
            upper = 10
        } else if value > 0 {
            lower = 0
            let doubled = value * 2
            upper = doubled.isFinite ? doubled : value
        } else {
            let doubled = value * 2
            lower = doubled.isFinite ? doubled : value
            upper = 0
        }
        let span = upper - lower
        if let requestedStep {
            return Self(lowerBound: lower, upperBound: upper, step: min(span, requestedStep))
        }
        let targetStep = max(span / 200, Double.leastNonzeroMagnitude)
        let scale = Foundation.pow(10, Foundation.floor(Foundation.log10(targetStep)))
        let step: Double
        if scale > 0, scale.isFinite {
            let ratio = targetStep / scale
            let factor: Double = ratio <= 1 ? 1 : ratio <= 2 ? 2 : ratio <= 5 ? 5 : 10
            step = min(span, max(factor * scale, Double.leastNonzeroMagnitude))
        } else {
            step = Double.leastNonzeroMagnitude
        }
        return Self(lowerBound: lower, upperBound: upper, step: step)
    }

    /// Quantizes to the chosen step; both endpoints remain exactly reachable.
    public func value(at position: Double) -> Double {
        let position = position.isNaN ? 0 : min(1, max(0, position))
        if position == 0 { return lowerBound }
        if position == 1 { return upperBound }
        let span = upperBound - lowerBound
        let increment = ((position * span) / step).rounded() * step
        let value = lowerBound + increment
        return min(upperBound, max(lowerBound, value))
    }

    public func position(for value: Double) -> Double {
        let value = value.isNaN ? lowerBound : min(upperBound, max(lowerBound, value))
        return (value - lowerBound) / (upperBound - lowerBound)
    }

    /// Relative scrubbing is anchored to the value at the start of a gesture.
    /// Decimal arithmetic keeps a decimal step from producing binary artifacts
    /// such as 8.299999999999999 in the saved source.
    public func adjustedValue(from origin: Double, steps: Int) -> Double {
        guard origin.isFinite else { return lowerBound }
        let bounded = min(upperBound, max(lowerBound, origin))
        if steps == 0 { return bounded }
        let locale = Locale(identifier: "en_US_POSIX")
        var result = bounded + Double(steps) * step
        // Decimal covers a narrower range than Double; use it only when both
        // operands survive the round trip. Double(String) rounds correctly,
        // unlike NSDecimalNumber.doubleValue.
        if let start = Decimal(string: String(bounded), locale: locale),
           let increment = Decimal(string: String(step), locale: locale),
           Double(start.description) == bounded, Double(increment.description) == step {
            let decimal = start + Decimal(steps) * increment
            if !decimal.isNaN, let candidate = Double(decimal.description), candidate.isFinite {
                result = candidate
            }
        }
        // A requested step may be smaller than Double's spacing at this value.
        if result == bounded {
            result = steps > 0 ? bounded.nextUp : bounded.nextDown
        }
        return min(upperBound, max(lowerBound, result))
    }

    /// Moves to the next point of the slider's grid, including an upper bound
    /// that is not a whole number of steps from the lower bound.
    public func adjacentValue(to value: Double, increasing: Bool) -> Double {
        let value = value.isNaN ? lowerBound : min(upperBound, max(lowerBound, value))
        if increasing && value == upperBound { return upperBound }
        if !increasing && value == lowerBound { return lowerBound }
        if !increasing && value == upperBound {
            let lastIndex = Foundation.floor((upperBound - lowerBound) / step)
            let lastGridValue = lowerBound + lastIndex * step
            let candidate = lastGridValue < upperBound ? lastGridValue
                : lowerBound + (lastIndex - 1) * step
            return candidate < value ? max(lowerBound, candidate) : max(lowerBound, value.nextDown)
        }

        let index = (value - lowerBound) / step
        let nearest = index.rounded()
        // A decimal grid point may not divide back to an exact integer in Double.
        let tolerance = max(1, abs(index)) * Double.ulpOfOne * 4
        let isGridPoint = abs(index - nearest) <= tolerance
        let adjacentIndex: Double
        if increasing {
            adjacentIndex = isGridPoint ? nearest + 1 : Foundation.floor(index) + 1
        } else {
            adjacentIndex = isGridPoint ? nearest - 1 : Foundation.ceil(index) - 1
        }
        let candidate = min(upperBound, max(lowerBound, lowerBound + adjacentIndex * step))
        if increasing {
            // Very small steps may be below the representable spacing at this magnitude.
            return candidate > value ? candidate : min(upperBound, value.nextUp)
        }
        return candidate < value ? candidate : max(lowerBound, value.nextDown)
    }

    private enum CodingKeys: String, CodingKey { case lowerBound, upperBound, step }

    public init(from decoder: any Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        let lower = try values.decode(Double.self, forKey: .lowerBound)
        let upper = try values.decode(Double.self, forKey: .upperBound)
        let step = try values.decode(Double.self, forKey: .step)
        guard let range = Self(lowerBound: lower, upperBound: upper, step: step) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath,
                debugDescription: "The variable adjustment bounds and step must form a finite increasing interval."))
        }
        self = range
    }
}
