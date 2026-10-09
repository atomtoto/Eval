import Foundation
import os

/// A numerical value stored in coherent SI units together with its dimension.
public struct Quantity: Hashable, Sendable {
    public let value: Double
    public let dimension: Dimension

    public init(value: Double, dimension: Dimension = .dimensionless) {
        self.value = value
        self.dimension = dimension
    }
}

/// A unit chosen to display a result, as in `E -> kWh`: the symbol as typed
/// (with `·` for `*`) and the size of one such unit in SI.
public struct DisplayUnit: Hashable, Sendable {
    public let symbol: String
    public let scale: Double

    public init(symbol: String, scale: Double) {
        self.symbol = symbol
        self.scale = scale
    }
}

public enum QuantityFormatter: Sendable {
    public static func string(_ quantity: Quantity, significantDigits: Int = significantDigits) -> String {
        let value = number(quantity.value, significantDigits: significantDigits)
        guard !quantity.dimension.isDimensionless else { return value }
        let unit = UnitCatalog.preferredSymbol(for: quantity.dimension) ?? quantity.dimension.formatted
        return value + " " + unit
    }

    /// The value expressed in `unit`, followed by its symbol (attached for `°`).
    /// Without a unit, the result is in SI as with `string(_:)`.
    public static func string(_ quantity: Quantity, in unit: DisplayUnit?,
                              significantDigits: Int = significantDigits) -> String {
        guard let unit else { return string(quantity, significantDigits: significantDigits) }
        return number(quantity.value / unit.scale, significantDigits: significantDigits) + (unit.symbol == "°" ? "" : " ") + unit.symbol
    }

    /// The unit written after a value: the requested one, else the SI unit of the
    /// dimension. Empty for a dimensionless quantity, for axis labels.
    public static func unitSymbol(for dimension: Dimension, in unit: DisplayUnit? = nil) -> String {
        if let unit { return unit.symbol }
        return dimension.isDimensionless ? "" : UnitCatalog.preferredSymbol(for: dimension) ?? dimension.formatted
    }

    /// The significant digits shown for results, 6 by default and clamped to 3...12.
    /// Calculations keep the full `Double`. Safe to read and write from any thread.
    public static var significantDigits: Int {
        get { digitsStorage.withLock { $0 } }
        set { digitsStorage.withLock { $0 = min(maximumDigits, max(minimumDigits, newValue)) } }
    }
    public static let defaultDigits = 6
    public static let minimumDigits = 3
    public static let maximumDigits = 12
    private static let digitsStorage = OSAllocatedUnfairLock(initialState: defaultDigits)
    /// For text that must tell close values apart, such as an entered number or an exponent.
    public static let preciseDigits = 10

    /// Six significant digits, a French decimal comma, readable scientific notation,
    /// and the true minus sign `−` (U+2212), which the parser reads back.
    /// Whole numbers below 10⁹ keep every integer digit, so `c` reads 299792458.
    public static func number(_ value: Double, significantDigits: Int = significantDigits) -> String {
        let text = plainNumber(value, digits: significantDigits)
        return text.hasPrefix("-") ? "−" + text.dropFirst() : text
    }

    private static func plainNumber(_ value: Double, digits: Int) -> String {
        if value.isNaN { return "indéfini" }
        if value == .infinity { return "∞" }
        if value == -.infinity { return "−∞" }
        if value == 0 { return "0" }

        // No locale: the C formatting keeps the decimal point and is much faster.
        let formatted = String(format: "%.*e", digits - 1, value).lowercased()
        let components = formatted.split(separator: "e")
        if components.count == 2, let exponent = Int(components[1]) {
            if exponent >= 9 || exponent < -4 {
                let mantissa = trimFraction(String(components[0])).replacingOccurrences(of: ".", with: ",")
                return mantissa + " × 10" + Dimension.superscript(String(exponent))
            }
            let decimalPlaces = max(0, digits - 1 - exponent)
            return trimFraction(String(format: "%.*f", decimalPlaces, value))
                .replacingOccurrences(of: ".", with: ",")
        }
        return formatted.replacingOccurrences(of: ".", with: ",")
    }

    private static func trimFraction(_ number: String) -> String {
        guard number.contains(".") else { return number }
        var trimmed = number
        while trimmed.last == "0" { trimmed.removeLast() }
        if trimmed.last == "." { trimmed.removeLast() }
        return trimmed
    }
}

extension EvaluatedLine {
    /// The value as the sheet shows it: in the unit requested with `→` when
    /// there is one, else in SI. Nil for a line without a value.
    public var formattedValue: String? {
        quantity.map { QuantityFormatter.string($0, in: displayUnit) }
    }
}
