import Foundation

/// The seven SI base dimensions. Adding dimensions multiplies their units.
public struct Dimension: Hashable, Sendable {
    public let length: Double
    public let mass: Double
    public let time: Double
    public let electricCurrent: Double
    public let temperature: Double
    public let amount: Double
    public let luminousIntensity: Double

    public init(
        length: Double = 0,
        mass: Double = 0,
        time: Double = 0,
        electricCurrent: Double = 0,
        temperature: Double = 0,
        amount: Double = 0,
        luminousIntensity: Double = 0
    ) {
        self.length = length
        self.mass = mass
        self.time = time
        self.electricCurrent = electricCurrent
        self.temperature = temperature
        self.amount = amount
        self.luminousIntensity = luminousIntensity
    }

    public static let dimensionless = Dimension()
    public static let length = Dimension(length: 1)
    public static let mass = Dimension(mass: 1)
    public static let time = Dimension(time: 1)
    public static let electricCurrent = Dimension(electricCurrent: 1)
    public static let temperature = Dimension(temperature: 1)
    public static let amount = Dimension(amount: 1)
    public static let luminousIntensity = Dimension(luminousIntensity: 1)

    public static func + (lhs: Self, rhs: Self) -> Self {
        Self(
            length: lhs.length + rhs.length,
            mass: lhs.mass + rhs.mass,
            time: lhs.time + rhs.time,
            electricCurrent: lhs.electricCurrent + rhs.electricCurrent,
            temperature: lhs.temperature + rhs.temperature,
            amount: lhs.amount + rhs.amount,
            luminousIntensity: lhs.luminousIntensity + rhs.luminousIntensity
        )
    }

    public static func - (lhs: Self, rhs: Self) -> Self {
        lhs + rhs.scaled(by: -1)
    }

    public func scaled(by exponent: Double) -> Self {
        Self(
            length: length * exponent,
            mass: mass * exponent,
            time: time * exponent,
            electricCurrent: electricCurrent * exponent,
            temperature: temperature * exponent,
            amount: amount * exponent,
            luminousIntensity: luminousIntensity * exponent
        )
    }

    public var isDimensionless: Bool {
        isEquivalent(to: .dimensionless)
    }

    /// A small tolerance accounts for rounding when fractional powers cancel.
    public func isEquivalent(to other: Self) -> Bool {
        zip(exponents, other.exponents).allSatisfy { abs($0 - $1) <= 1e-10 }
    }

    /// SI base units, with superscript integer powers and explicit fractional powers.
    public var formatted: String {
        let units: [(String, Double)] = [
            ("kg", mass), ("m", length), ("s", time), ("A", electricCurrent),
            ("K", temperature), ("mol", amount), ("cd", luminousIntensity)
        ]
        let parts = units.compactMap { symbol, exponent -> String? in
            guard abs(exponent) > 1e-10 else { return nil }
            if abs(exponent - 1) <= 1e-10 { return symbol }
            if exponent.isFinite, abs(exponent - exponent.rounded()) <= 1e-10 {
                let power = abs(exponent) < 1e15 ? String(Int(exponent.rounded())) : String(format: "%.0f", exponent)
                return symbol + Self.superscript(power)
            }
            return symbol + "^(" + QuantityFormatter.number(exponent, significantDigits: QuantityFormatter.preciseDigits) + ")"
        }
        return parts.isEmpty ? "1" : parts.joined(separator: "·")
    }

    private var exponents: [Double] {
        [length, mass, time, electricCurrent, temperature, amount, luminousIntensity]
    }

    private static let superscriptDigits: [Character: Character] = [
        "0": "⁰", "1": "¹", "2": "²", "3": "³", "4": "⁴", "5": "⁵",
        "6": "⁶", "7": "⁷", "8": "⁸", "9": "⁹", "-": "⁻", "+": "⁺"
    ]

    static func superscript(_ value: String) -> String {
        String(value.map { superscriptDigits[$0] ?? $0 })
    }
}
