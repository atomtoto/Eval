import XCTest
@testable import EvalCore

final class AdjustableVariableTests: XCTestCase {
    func testDecimalCommaSignedLiteralAndCommentArePreserved() throws {
        let input = "  a\t=  -7,2 m/s²  # commentaire = inchangé"
        let variable = try XCTUnwrap(AdjustableVariable(source: input))
        XCTAssertEqual(variable.name, "a")
        XCTAssertEqual(variable.value, -7.2)
        XCTAssertEqual(variable.unit, "m/s²")
        XCTAssertEqual(variable.source(replacingValue: 8.5),
                       "  a\t=  8,5 m/s²  # commentaire = inchangé")
    }

    func testScientificNotationRetainsTheEnteredUnit() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "v=5e-3 km/s // vitesse"))
        XCTAssertEqual(variable.value, 0.005)
        XCTAssertEqual(variable.unit, "km/s")
        let updated = try XCTUnwrap(variable.source(replacingValue: 0.001))
        XCTAssertEqual(updated, "v=1e-3 km/s // vitesse")
        XCTAssertEqual(NotebookEngine.evaluate(updated).lines.first?.quantity?.value, 1)
    }

    func testZeroDimensionlessAndTemperatureVariables() throws {
        let zero = try XCTUnwrap(AdjustableVariable(source: "x = 0"))
        XCTAssertEqual(zero.value, 0)
        XCTAssertEqual(zero.unit, "")
        let temperature = try XCTUnwrap(AdjustableVariable(source: "T = 300 K"))
        XCTAssertEqual(temperature.unit, "K")
        XCTAssertEqual(temperature.value, 300)
    }

    func testAutomaticStepFollowsEnteredPrecisionRatherThanValueSize() throws {
        let examples: [(String, Double)] = [
            ("x = 6", 1), ("x = 8,2", 0.1), ("x = 8,25", 0.01),
            ("x = 8,20", 0.01), ("x = -0.005", 0.001),
            ("x = 6.0", 0.1), ("x = 1,2e3 kg", 100), ("x = 5e-3 s", 0.001),
            ("x = 0", 1), ("x = 0,00", 0.01)
        ]
        for (source, step) in examples {
            XCTAssertEqual(try XCTUnwrap(AdjustableVariable(source: source)).automaticStep, step, source)
        }
    }

    func testRelativeRulerUsesDecimalStepsAndKeepsPrecisionAtIntegers() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "a = 8,2 m/s² # conservé"))
        let range = try XCTUnwrap(VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep))
        XCTAssertEqual(range.adjustedValue(from: variable.value, steps: 1), 8.3)
        XCTAssertEqual(range.adjustedValue(from: variable.value, steps: -1), 8.1)
        let integer = range.adjustedValue(from: variable.value, steps: 8)
        XCTAssertEqual(integer, 9)
        let changed = try XCTUnwrap(variable.source(replacingValue: integer))
        XCTAssertEqual(changed, "a = 9,0 m/s² # conservé")
        XCTAssertEqual(try XCTUnwrap(AdjustableVariable(source: changed)).automaticStep, 0.1)
        let whole = try XCTUnwrap(AdjustableVariable(source: "x = 6"))
        XCTAssertEqual(whole.source(replacingValue: 7), "x = 7")
        XCTAssertEqual(try XCTUnwrap(AdjustableVariable(source: whole.source(replacingValue: 7)!)).automaticStep, 1)
    }

    func testRulerWritesDecimalValuesWithoutBinaryNoise() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "x = 1,00"))
        let range = try XCTUnwrap(VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep))
        let value = range.adjustedValue(from: 1, steps: -8)
        XCTAssertEqual(value, 0.92)
        XCTAssertEqual(variable.source(replacingValue: value), "x = 0,92")
        // A value one ulp away from the decimal still keeps the entered precision.
        XCTAssertEqual(variable.source(replacingValue: 0.9199999999999999), "x = 0,92")
        let quarter = try XCTUnwrap(AdjustableVariable(source: "x = 2,25"))
        let quarterRange = try XCTUnwrap(VariableAdjustmentRange.suggested(for: 2.25, step: quarter.automaticStep))
        XCTAssertEqual(quarter.source(replacingValue: quarterRange.adjustedValue(from: 2.25, steps: -1)), "x = 2,24")
        let symmetric = try XCTUnwrap(VariableAdjustmentRange(lowerBound: -10, upperBound: 10, step: 0.1))
        XCTAssertEqual(symmetric.adjustedValue(from: 0.3, steps: -3), 0)
    }

    func testScrubbingKeepsTheEnteredPrecisionAcrossTheWholeRange() throws {
        let sources = ["x = 0,0", "x = 0,00", "x = 1,00", "x = 5,0", "x = 9,81", "x = 0,000",
                       "x = 12,5", "x = 3,14", "x = 5e-3 s", "x = 1,25e-3", "x = -7,2", "x = 2,5e3"]
        for source in sources {
            let variable = try XCTUnwrap(AdjustableVariable(source: source))
            let range = try XCTUnwrap(VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep))
            for steps in -250...250 {
                let written = try XCTUnwrap(variable.source(replacingValue: range.adjustedValue(from: variable.value, steps: steps)))
                let reparsed = try XCTUnwrap(AdjustableVariable(source: written), written)
                XCTAssertEqual(reparsed.automaticStep, variable.automaticStep, written)
            }
        }
    }

    func testRelativeRulerFreezesItsOriginAndHonorsCustomBounds() throws {
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: -10, upperBound: 10, step: 0.1))
        // Each drag update uses total displacement, not the previous result.
        XCTAssertEqual(range.adjustedValue(from: 8.2, steps: 3), 8.5)
        XCTAssertEqual(range.adjustedValue(from: 8.2, steps: 1), 8.3)
        XCTAssertEqual(range.adjustedValue(from: 8.2, steps: 0), 8.2)
        XCTAssertEqual(range.adjustedValue(from: 8.2, steps: 100), 10)
        XCTAssertEqual(range.adjustedValue(from: -8.2, steps: -100), -10)
        XCTAssertEqual(range.adjustedValue(from: -0.1, steps: 1), 0)
        XCTAssertEqual(range.adjustedValue(from: 0, steps: -1), -0.1)
        let huge = try XCTUnwrap(VariableAdjustmentRange.suggested(for: 1e250, step: 1e249))
        XCTAssertTrue(huge.adjustedValue(from: 1e250, steps: 1).isFinite)
        XCTAssertGreaterThan(huge.adjustedValue(from: 1e250, steps: 1), 1e250)
        let tiny = try XCTUnwrap(VariableAdjustmentRange.suggested(for: .leastNonzeroMagnitude, step: .leastNonzeroMagnitude))
        XCTAssertGreaterThan(tiny.adjustedValue(from: .leastNonzeroMagnitude, steps: 1), .leastNonzeroMagnitude)
    }

    func testScientificNotationKeepsItsStepAfterScrubbing() throws {
        for (source, newValue, expected) in [("x = 1,2e3", 1_300.0, "x = 1,3e3"),
                                           ("x = 8.20", 9.0, "x = 9.00")] {
            let original = try XCTUnwrap(AdjustableVariable(source: source))
            let changed = try XCTUnwrap(original.source(replacingValue: newValue))
            XCTAssertEqual(changed, expected)
            XCTAssertEqual(try XCTUnwrap(AdjustableVariable(source: changed)).automaticStep, original.automaticStep)
        }
    }

    func testUnicodeSignsGreekNamesAndUnitPowers() throws {
        for source in ["α = −7,2 m/s²", "α = – 7,2 m/s²", "α = +7,2 m/s²"] {
            let variable = try XCTUnwrap(AdjustableVariable(source: source))
            XCTAssertEqual(variable.name, "α")
            XCTAssertEqual(abs(variable.value), 7.2)
            XCTAssertEqual(variable.unit, "m/s²")
        }
        for unit in ["µm", "μs", "Ω", "kg*m/s^2", "mol/L", "m⁻²", "m^0.5"] {
            XCTAssertNotNil(AdjustableVariable(source: "x = 2 \(unit)"), unit)
        }
    }

    func testCompactUnitChainIsAdjustable() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "v = 72km/h # vitesse"))
        XCTAssertEqual(variable.value, 72)
        XCTAssertEqual(variable.unit, "km/h")
        XCTAssertEqual(variable.source(replacingValue: 90), "v = 90km/h # vitesse")
        XCTAssertNil(AdjustableVariable(source: "v = 2m"))
    }

    func testFractionalLiteralsAndScientificSigns() throws {
        let examples: [(String, Double)] = [
            ("x = ,5", 0.5), ("x = -.5", -0.5), ("x = 2,5E+3 mm", 2_500),
            ("x = -2e−3 s", -0.002), ("x = 7. m", 7), ("x = –2e–3 s", -0.002)
        ]
        for (source, expected) in examples {
            XCTAssertEqual(try XCTUnwrap(AdjustableVariable(source: source)).value, expected, source)
        }
    }

    func testDependentAndCalculatedExpressionsAreNeverAdjustable() {
        let excluded = [
            "x=2*y", "x=1+2", "x=1/2", "x=2^3", "x=sqrt(2)", "x=(2)",
            "x=2 m * y", "x=2 m/s² * m", "x=2m", "x=2 m / s", "x=2 m^y", "x=2 m^pi",
            "x=2 m^2+3", "x=2 m*3", "x=2 m/s^2 * h", "x = c", "x = + + 2"
        ]
        for source in excluded { XCTAssertNil(AdjustableVariable(source: source), source) }
    }

    func testInvalidDefinitionsComparisonsAndUnitsAreRejected() {
        let excluded = [
            "", "# x=2", "2", "x == 2", "2 = 2", "x = 2 = 2", "x =",
            "x = NaN", "x = inf", "x = 1e309", "x = 2 unknown", "x = 2 °C",
            "x = 2 m^10001", "x = 2 mm^10000", "x = 2 m\ny = 3"
        ]
        for source in excluded { XCTAssertNil(AdjustableVariable(source: source), source) }
    }

    func testReplacementIsFiniteAndRoundTripsWithoutLostPrecision() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "x = 1,25  # précis"))
        for number in [Double.pi, 1.2345678901234567, 1e-250, -1e250, Double.leastNonzeroMagnitude] {
            let updated = try XCTUnwrap(variable.source(replacingValue: number))
            XCTAssertEqual(try XCTUnwrap(AdjustableVariable(source: updated)).value, number)
            XCTAssertTrue(updated.hasSuffix("  # précis"))
        }
        XCTAssertNil(variable.source(replacingValue: .infinity))
        XCTAssertNil(variable.source(replacingValue: .nan))
        let length = try XCTUnwrap(AdjustableVariable(source: "x = 2 km"))
        XCTAssertNil(length.source(replacingValue: Double.greatestFiniteMagnitude))
    }

    func testChangingValueRecalculatesForwardReferencesAndRetainsResultSelection() throws {
        let source = "E\nE = 0,5*m*v²\nv = 5 m/s # curseur\nm = 80 kg"
        var selection = ResultSelection(source: source, initiallySelectedLineIDs: [0, 2])
        let originalID = selection.entries[2].id
        let variable = try XCTUnwrap(AdjustableVariable(source: selection.entries[2].source))
        let replacement = try XCTUnwrap(variable.source(replacingValue: 10))
        selection.updateSource(replacement, at: 2)
        let changed = selection.entries.map(\.source).joined(separator: "\n")
        selection.reconcile(source: changed)
        XCTAssertEqual(selection.entries[2].id, originalID)
        XCTAssertTrue(selection.isSelected(at: 0))
        XCTAssertTrue(selection.isSelected(at: 2))
        let evaluation = NotebookEngine.evaluate(changed)
        XCTAssertEqual(evaluation.lines[0].quantity?.value, 4_000)
        XCTAssertTrue(evaluation.lines.allSatisfy { $0.status == .success })
    }

    func testSuggestedRangesForPositiveNegativeAndZero() throws {
        let positive = try XCTUnwrap(VariableAdjustmentRange.suggested(for: 7.2))
        XCTAssertEqual(positive.lowerBound, 0)
        XCTAssertEqual(positive.upperBound, 14.4)
        XCTAssertEqual(positive.step, 0.1)
        let negative = try XCTUnwrap(VariableAdjustmentRange.suggested(for: -7.2))
        XCTAssertEqual(negative.lowerBound, -14.4)
        XCTAssertEqual(negative.upperBound, 0)
        XCTAssertEqual(negative.step, 0.1)
        let zero = try XCTUnwrap(VariableAdjustmentRange.suggested(for: 0))
        XCTAssertEqual(zero.lowerBound, -10)
        XCTAssertEqual(zero.upperBound, 10)
        XCTAssertEqual(zero.step, 0.1)
    }

    func testNormalizedSliderValuesAreQuantizedAndClamped() throws {
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: -1, upperBound: 1, step: 0.3))
        XCTAssertEqual(range.value(at: 0), -1)
        XCTAssertEqual(range.value(at: 1), 1)
        XCTAssertEqual(range.value(at: 0.5), -0.1, accuracy: 1e-14)
        XCTAssertEqual(range.value(at: 0.999), 1)
        XCTAssertEqual(range.value(at: -1), -1)
        XCTAssertEqual(range.value(at: 2), 1)
        XCTAssertEqual(range.position(for: 0), 0.5)
        XCTAssertEqual(range.position(for: -2), 0)
        XCTAssertEqual(range.position(for: 2), 1)
        XCTAssertEqual(range.value(at: .nan), -1)
        XCTAssertEqual(range.position(for: .nan), 0)
    }

    func testExtremelySmallAndLargeValuesHaveFiniteSliderRanges() throws {
        for number in [Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude,
                       1e-250, -1e-250, 1e250, -1e250,
                       Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            let range = try XCTUnwrap(VariableAdjustmentRange.suggested(for: number), String(number))
            XCTAssertGreaterThan(range.step, 0)
            XCTAssertTrue(range.step.isFinite)
            XCTAssertTrue(range.value(at: 0.5).isFinite)
            XCTAssertEqual(range.value(at: 0), range.lowerBound)
            XCTAssertEqual(range.value(at: 1), range.upperBound)
            XCTAssertGreaterThanOrEqual(range.position(for: number), 0)
            XCTAssertLessThanOrEqual(range.position(for: number), 1)
        }
        XCTAssertNil(VariableAdjustmentRange.suggested(for: .nan))
        XCTAssertNil(VariableAdjustmentRange.suggested(for: .infinity))
    }

    func testAdjacentValuesFollowTheGridAndExactEndpoints() throws {
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: -1, upperBound: 1, step: 0.3))
        XCTAssertEqual(range.adjacentValue(to: 1, increasing: false), 0.8, accuracy: 1e-14)
        XCTAssertEqual(range.adjacentValue(to: 0.8, increasing: true), 1)
        XCTAssertEqual(range.adjacentValue(to: -1, increasing: true), -0.7, accuracy: 1e-14)
        XCTAssertEqual(range.adjacentValue(to: -1, increasing: false), -1)
        XCTAssertEqual(range.adjacentValue(to: 1, increasing: true), 1)
        XCTAssertEqual(range.adjacentValue(to: -0.1, increasing: true), 0.2, accuracy: 1e-14)
        XCTAssertEqual(range.adjacentValue(to: -0.1, increasing: false), -0.4, accuracy: 1e-14)
        let endpoint = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 1.nextUp, step: 1))
        XCTAssertEqual(endpoint.adjacentValue(to: endpoint.upperBound, increasing: false), 1)
    }

    func testAdjacentOffGridValuesUseTheNeighborsInEachDirection() throws {
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: -1, upperBound: 1, step: 0.3))
        XCTAssertEqual(range.adjacentValue(to: 0.7, increasing: true), 0.8, accuracy: 1e-14)
        XCTAssertEqual(range.adjacentValue(to: 0.7, increasing: false), 0.5, accuracy: 1e-14)
        XCTAssertEqual(range.adjacentValue(to: -0.8, increasing: true), -0.7, accuracy: 1e-14)
        XCTAssertEqual(range.adjacentValue(to: -0.8, increasing: false), -1)
        XCTAssertEqual(range.adjacentValue(to: .nan, increasing: false), -1)
        XCTAssertEqual(range.adjacentValue(to: .infinity, increasing: false), 0.8, accuracy: 1e-14)
    }

    func testRepeatedAdjacentAdjustmentsProgressToBothBounds() throws {
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: -1, upperBound: 1, step: 0.3))
        var value = range.lowerBound
        for _ in 0..<7 {
            let next = range.adjacentValue(to: value, increasing: true)
            XCTAssertGreaterThan(next, value)
            value = next
        }
        XCTAssertEqual(value, range.upperBound)
        for _ in 0..<7 {
            let previous = range.adjacentValue(to: value, increasing: false)
            XCTAssertLessThan(previous, value)
            value = previous
        }
        XCTAssertEqual(value, range.lowerBound)

        for number in [Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude,
                       Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            let extreme = try XCTUnwrap(VariableAdjustmentRange.suggested(for: number))
            let next = extreme.adjacentValue(to: extreme.lowerBound, increasing: true)
            let previous = extreme.adjacentValue(to: extreme.upperBound, increasing: false)
            XCTAssertTrue(next.isFinite)
            XCTAssertTrue(previous.isFinite)
            XCTAssertGreaterThan(next, extreme.lowerBound)
            XCTAssertLessThan(previous, extreme.upperBound)
        }
    }

    func testInvalidRangesAreRejected() {
        let invalid: [(Double, Double, Double)] = [
            (0, 0, 1), (1, 0, 1), (0, 1, 0), (0, 1, -0.1), (0, 1, 2),
            (0, .infinity, 1), (.nan, 1, 1), (0, 1, .nan),
            (-Double.greatestFiniteMagnitude, Double.greatestFiniteMagnitude, 1),
            (0, Double.greatestFiniteMagnitude, Double.leastNonzeroMagnitude)
        ]
        for (lower, upper, step) in invalid {
            XCTAssertNil(VariableAdjustmentRange(lowerBound: lower, upperBound: upper, step: step))
        }
    }

    func testRangePersistenceRoundTripsAndRejectsInvalidSavedValues() throws {
        let range = try XCTUnwrap(VariableAdjustmentRange.suggested(for: 7.2))
        let data = try JSONEncoder().encode(range)
        XCTAssertEqual(try JSONDecoder().decode(VariableAdjustmentRange.self, from: data), range)
        let invalid = Data(#"{"lowerBound":5,"upperBound":2,"step":1}"#.utf8)
        XCTAssertThrowsError(try JSONDecoder().decode(VariableAdjustmentRange.self, from: invalid))
    }

    /// The ruler no longer evaluates a whole sheet line per tick: its answer must
    /// still be the engine's, including overflow with a large unit.
    func testReplacementValidityMatchesTheEngineOverAGridOfValues() throws {
        let templates = ["x = 5 km", "x = 5 Mm", "v = 72 km/h", "x = 1,5e3 pc", "t = 2 h", "x = 7", "x = 3 µm",
                         "x = 2 ly", "v = 72 km/h -> m/s", "p = 5 bar"]
        let values: [Double] = [0, 1, -1, 1e-5, 1e308, -1e308, 1.7e307, 123_456.789, 5e-324, 1e22, 0.1 + 0.2, 8.99e307]
        for template in templates {
            let variable = try XCTUnwrap(AdjustableVariable(source: template), template)
            let literalEnd = template.firstIndex(of: "=").map { template.index(after: $0) }!
            let unitStart = template[literalEnd...].dropFirst().firstIndex(of: " ")
            let rest = unitStart.map { String(template[$0...]) } ?? ""
            let name = template[..<literalEnd]
            for value in values {
                let naive = "\(name) \(value)\(rest)"
                let expected = NotebookEngine.evaluate(naive).lines.first?.status == .success
                let replaced = variable.source(replacingValue: value)
                XCTAssertEqual(replaced != nil, expected, "\(template) ← \(value)")
                if let replaced {
                    XCTAssertEqual(NotebookEngine.evaluate(replaced).lines.first?.status, .success, replaced)
                }
            }
        }
        XCTAssertNil(try XCTUnwrap(AdjustableVariable(source: "x = 5 km")).source(replacingValue: 1e308))
    }

    func testOnlyEngineAcceptableLinesGetARuler() {
        let accepted = ["x = 5", "x = -5,5 m", "v = 72 km/h", "v = 72 km/h -> m/s # vitesse", "n = 1,5e3 pc", "x = 2 ml", "max = 5"]
        let rejected = ["h = 2km/h", "x = 5 m + 2 m", "x = y", "x = 5 foo", "x = 2 m -> s", "x = 5 -> ", "a == 5"]
        for source in accepted { XCTAssertNotNil(AdjustableVariable(source: source), source) }
        for source in rejected { XCTAssertNil(AdjustableVariable(source: source), source) }
    }

    func testConversionSuffixIsPreserved() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "v = 72 km/h -> m/s # vitesse"))
        XCTAssertEqual(variable.unit, "km/h")
        XCTAssertEqual(variable.source(replacingValue: 80), "v = 80 km/h -> m/s # vitesse")
    }
}
