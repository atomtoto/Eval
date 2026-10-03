import Foundation

/// A numerical value stored in coherent SI units together with its dimension.
public struct Quantity: Hashable, Sendable {
    public let value: Double
    public let dimension: Dimension

    public init(value: Double, dimension: Dimension = .dimensionless) {
        self.value = value
        self.dimension = dimension
    }
}

public enum QuantityFormatter: Sendable {
    public static func string(_ quantity: Quantity) -> String {
        let value = number(quantity.value)
        guard !quantity.dimension.isDimensionless else { return value }
        let unit = UnitCatalog.preferredSymbol(for: quantity.dimension) ?? quantity.dimension.formatted
        return value + " " + unit
    }

    /// Ten significant digits, a French decimal comma, and readable scientific notation.
    public static func number(_ value: Double) -> String {
        if value.isNaN { return "indéfini" }
        if value == .infinity { return "∞" }
        if value == -.infinity { return "−∞" }
        if value == 0 { return "0" }

        let locale = Locale(identifier: "en_US_POSIX")
        let formatted = String(format: "%.9e", locale: locale, value).lowercased()
        let components = formatted.split(separator: "e")
        if components.count == 2, let exponent = Int(components[1]) {
            if exponent >= 9 || exponent < -4 {
                let mantissa = trimFraction(String(components[0])).replacingOccurrences(of: ".", with: ",")
                return mantissa + " × 10" + Dimension.superscript(String(exponent))
            }
            let decimalPlaces = max(0, 9 - exponent)
            return trimFraction(String(format: "%.*f", locale: locale, decimalPlaces, value))
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
