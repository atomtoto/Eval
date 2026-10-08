import XCTest
@testable import EvalCore

/// Pins the number and dimension formatting against the former implementation,
/// which formatted through an explicit en_US_POSIX locale, at any digit count,
/// and pins the six-digit default shown in the sheet.
final class FormattingGoldenTests: XCTestCase {
    private static let locale = Locale(identifier: "en_US_POSIX")

    /// The reference text, with the true minus sign for negative values.
    private func referenceNumber(_ value: Double, digits: Int = 10) -> String {
        let text = unsignedReferenceNumber(value, digits: digits)
        return text.hasPrefix("-") ? "−" + text.dropFirst() : text
    }

    private func unsignedReferenceNumber(_ value: Double, digits: Int) -> String {
        if value.isNaN { return "indéfini" }
        if value == .infinity { return "∞" }
        if value == -.infinity { return "−∞" }
        if value == 0 { return "0" }
        let formatted = String(format: "%.*e", locale: Self.locale, digits - 1, value).lowercased()
        let components = formatted.split(separator: "e")
        func trim(_ number: String) -> String {
            guard number.contains(".") else { return number }
            var trimmed = number
            while trimmed.last == "0" { trimmed.removeLast() }
            if trimmed.last == "." { trimmed.removeLast() }
            return trimmed
        }
        if components.count == 2, let exponent = Int(components[1]) {
            if exponent >= 9 || exponent < -4 {
                return trim(String(components[0])).replacingOccurrences(of: ".", with: ",")
                    + " × 10" + Dimension.superscript(String(exponent))
            }
            return trim(String(format: "%.*f", locale: Self.locale, max(0, digits - 1 - exponent), value))
                .replacingOccurrences(of: ".", with: ",")
        }
        return formatted.replacingOccurrences(of: ".", with: ",")
    }

    private func referenceValues() -> [Double] {
        var values: [Double] = [1e-5, 9.99999999995e8, 1e9, 7.2, -7.2, 0.1 + 0.2, 123_456_789.123, 1e-4,
                                99_999.999_999_5, -1e-30, 6.62607015e-34, 299_792_458, .pi, -.pi * 1e12,
                                Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude,
                                Double.leastNormalMagnitude, 0.5, 2.5e-5, 1_000_000_000.4, .nan, .infinity, -.infinity]
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<600 {
            let exponent = Int.random(in: -40...40, using: &generator)
            values.append(Double.random(in: -10...10, using: &generator) * Foundation.pow(10, Double(exponent)))
        }
        for exponent in -12...14 { values.append(Foundation.pow(10, Double(exponent))) }
        return values
    }

    func testNumberFormattingMatchesTheLocaleFormattedReference() {
        for value in referenceValues() {
            XCTAssertEqual(QuantityFormatter.number(value, significantDigits: 10), referenceNumber(value, digits: 10), "\(value)")
            XCTAssertEqual(QuantityFormatter.number(value, significantDigits: QuantityFormatter.preciseDigits),
                           referenceNumber(value), "\(value)")
        }
    }

    func testDefaultFormattingShowsSixSignificantDigits() {
        XCTAssertEqual(QuantityFormatter.significantDigits, 6)
        XCTAssertEqual(QuantityFormatter.preciseDigits, 10)
        for value in referenceValues() {
            XCTAssertEqual(QuantityFormatter.number(value), referenceNumber(value, digits: 6), "\(value)")
            XCTAssertEqual(QuantityFormatter.number(value, significantDigits: 6), QuantityFormatter.number(value), "\(value)")
        }
    }

    func testSixDigitRoundingAndTrailingZeros() {
        XCTAssertEqual(QuantityFormatter.number(.pi), "3,14159")
        XCTAssertEqual(QuantityFormatter.number(2.718281828), "2,71828")
        XCTAssertEqual(QuantityFormatter.number(1.0000004), "1")
        XCTAssertEqual(QuantityFormatter.number(1.5), "1,5")
        XCTAssertEqual(QuantityFormatter.number(0.1 + 0.2), "0,3")
        XCTAssertEqual(QuantityFormatter.number(7.2), "7,2")
        XCTAssertEqual(QuantityFormatter.number(12.34567), "12,3457")
        XCTAssertEqual(QuantityFormatter.number(0.000123456789), "0,000123457")
        XCTAssertEqual(QuantityFormatter.number(99_999.999_9), "100000")
        XCTAssertEqual(QuantityFormatter.number(0.99999999), "1")
        // The explicit digit count overrides the default.
        XCTAssertEqual(QuantityFormatter.number(.pi, significantDigits: 3), "3,14")
        XCTAssertEqual(QuantityFormatter.number(.pi, significantDigits: 10), "3,141592654")
        XCTAssertEqual(QuantityFormatter.number(.pi, significantDigits: 15), "3,14159265358979")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: .pi, dimension: .length)), "3,14159 m")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: .pi, dimension: .length), significantDigits: 10), "3,141592654 m")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: .pi, dimension: .length),
                                                in: DisplayUnit(symbol: "cm", scale: 0.01), significantDigits: 4), "314,2 cm")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: .pi, dimension: .length),
                                                in: DisplayUnit(symbol: "cm", scale: 0.01)), "314,159 cm")
    }

    func testScientificNotationStartsAtTenToTheNinthAndBelowTenToTheMinusFour() {
        XCTAssertEqual(QuantityFormatter.number(1e-4), "0,0001")
        XCTAssertEqual(QuantityFormatter.number(1.23456789e-4), "0,000123457")
        XCTAssertEqual(QuantityFormatter.number(1e-5), "1 × 10⁻⁵")
        XCTAssertEqual(QuantityFormatter.number(1.23456789e-5), "1,23457 × 10⁻⁵")
        XCTAssertEqual(QuantityFormatter.number(9.99999e8), "999999000")
        XCTAssertEqual(QuantityFormatter.number(1e9), "1 × 10⁹")
        XCTAssertEqual(QuantityFormatter.number(1_234_567_890), "1,23457 × 10⁹")
        XCTAssertEqual(QuantityFormatter.number(6.62607015e-34), "6,62607 × 10⁻³⁴")
        XCTAssertEqual(QuantityFormatter.number(-1.6e-19), "−1,6 × 10⁻¹⁹")
        XCTAssertEqual(QuantityFormatter.number(1.5e12), "1,5 × 10¹²")
    }

    func testWholeNumbersBelowTenToTheNinthKeepEveryDigit() {
        XCTAssertEqual(QuantityFormatter.number(299_792_458), "299792458")
        XCTAssertEqual(QuantityFormatter.number(123_456_789), "123456789")
        XCTAssertEqual(QuantityFormatter.number(1_234_567), "1234567")
        XCTAssertEqual(QuantityFormatter.number(100_000), "100000")
        XCTAssertEqual(QuantityFormatter.number(-987_654_321), "−987654321")
        XCTAssertEqual(QuantityFormatter.number(999_999_000), "999999000")
        // Rounded to six digits, the last value below 10⁹ reaches the scientific threshold.
        XCTAssertEqual(QuantityFormatter.number(999_999_999), "1 × 10⁹")
        XCTAssertEqual(QuantityFormatter.number(1000), "1000")
        XCTAssertEqual(QuantityFormatter.number(1000, significantDigits: 2), "1000")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: 299_792_458, dimension: Dimension(length: 1, time: -1))), "299792458 m·s⁻¹")
    }

    func testDimensionFormattingMatchesTheLocaleFormattedReference() {
        let exponents: [Double] = [1, -1, 2, -2, 3, -3, 10, -12, 0.5, -0.5, 1.5, 1 / 3.0, 2.000_000_000_01, -4]
        for length in exponents {
            for time in exponents {
                let dimension = Dimension(length: length, mass: 1, time: time)
                var parts: [String] = []
                for (symbol, exponent) in [("kg", 1.0), ("m", length), ("s", time)] {
                    if abs(exponent - 1) <= 1e-10 { parts.append(symbol); continue }
                    if abs(exponent - exponent.rounded()) <= 1e-10 {
                        let power = String(format: "%.0f", locale: Self.locale, exponent)
                        parts.append(symbol + Dimension.superscript(power))
                    } else {
                        parts.append(symbol + "^(" + referenceNumber(exponent) + ")")
                    }
                }
                XCTAssertEqual(dimension.formatted, parts.joined(separator: "·"), "\(length) \(time)")
            }
        }
        XCTAssertEqual(Dimension(length: 1, time: -2).formatted, "m·s⁻²")
        XCTAssertEqual(Dimension.dimensionless.formatted, "1")
    }

    func testFormattingIsIndependentOfTheCurrentLocale() {
        XCTAssertEqual(QuantityFormatter.number(1234.5678, significantDigits: 10), "1234,5678")
        XCTAssertEqual(QuantityFormatter.number(1234.5678), "1234,57")
        XCTAssertEqual(QuantityFormatter.number(-0.5), "−0,5")
        XCTAssertEqual(QuantityFormatter.number(1.5e12), "1,5 × 10¹²")
    }

    func testNegativeNumbersUseTheTrueMinusSignAndReadBack() throws {
        XCTAssertEqual(QuantityFormatter.number(-2.5e-7), "−2,5 × 10⁻⁷")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: -3, dimension: .length)), "−3 m")
        XCTAssertFalse(QuantityFormatter.number(-12345.678).contains("-"))
        XCTAssertEqual(QuantityFormatter.number(-12345.678), "−12345,7")
        // The displayed text pastes back as input and gives the same value.
        for value in [-0.5, -1234.5678, -2.5e-7, -1.5e12] {
            let precise = QuantityFormatter.number(value, significantDigits: 10)
            let line = try XCTUnwrap(NotebookEngine.evaluate("x = \(precise)").lines.first)
            let parsed = try XCTUnwrap(line.quantity?.value)
            XCTAssertEqual(parsed, value, accuracy: abs(value) * 1e-9, precise)
            // The six-digit text reads back to six significant digits.
            let shown = QuantityFormatter.number(value)
            let shortLine = try XCTUnwrap(NotebookEngine.evaluate("x = \(shown)").lines.first)
            let shortParsed = try XCTUnwrap(shortLine.quantity?.value)
            XCTAssertEqual(shortParsed, value, accuracy: abs(value) * 1e-5, shown)
        }
        // Read aloud, the sign is still spoken.
        XCTAssertEqual(MathSpeech.number(-0.5), "moins 0,5")
        XCTAssertEqual(MathSpeech.number(-2.5e-7), "moins 2,5 fois 10 puissance moins 7")
    }

    func testQuantityFormatterShowsTheDisplayUnitOrSI() {
        let speed = Quantity(value: 20, dimension: Dimension(length: 1, time: -1))
        XCTAssertEqual(QuantityFormatter.string(speed, in: nil), QuantityFormatter.string(speed))
        XCTAssertEqual(QuantityFormatter.string(speed, in: DisplayUnit(symbol: "km/h", scale: 1 / 3.6)), "72 km/h")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: .pi / 6), in: DisplayUnit(symbol: "°", scale: .pi / 180)), "30°")
        XCTAssertEqual(QuantityFormatter.string(Quantity(value: 0.35), in: DisplayUnit(symbol: "%", scale: 0.01)), "35 %")
    }

    func testInverseSecondsAreNotLabelledHertz() {
        let rate = Quantity(value: 2, dimension: .dimensionless - .time)
        XCTAssertEqual(QuantityFormatter.string(rate), "2 s⁻¹")
        for source in ["2 rad/s", "omega = 2*pi*50 Hz", "1 Bq", "60 / 1 min"] {
            let line = NotebookEngine.evaluate(source).lines[0]
            XCTAssertEqual(line.status, .success, source)
            XCTAssertNil(line.quantity.flatMap { UnitCatalog.preferredSymbol(for: $0.dimension) }, source)
        }
        XCTAssertEqual(QuantityFormatter.string(rate, in: DisplayUnit(symbol: "Hz", scale: 1)), "2 Hz")
    }
}
