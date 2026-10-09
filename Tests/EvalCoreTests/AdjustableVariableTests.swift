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
        let step = variable.automaticStep
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: variable.value, steps: 1, step: step), 8.3)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: variable.value, steps: -1, step: step), 8.1)
        let integer = VariableAdjustmentRange.stepped(from: variable.value, steps: 8, step: step)
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
        let value = VariableAdjustmentRange.stepped(from: 1, steps: -8, step: variable.automaticStep)
        XCTAssertEqual(value, 0.92)
        XCTAssertEqual(variable.source(replacingValue: value), "x = 0,92")
        // A value one ulp away from the decimal still keeps the entered precision.
        XCTAssertEqual(variable.source(replacingValue: 0.9199999999999999), "x = 0,92")
        let quarter = try XCTUnwrap(AdjustableVariable(source: "x = 2,25"))
        XCTAssertEqual(quarter.source(replacingValue: VariableAdjustmentRange.stepped(from: 2.25, steps: -1, step: quarter.automaticStep)),
                       "x = 2,24")
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 0.3, steps: -3, step: 0.1), 0)
    }

    func testScrubbingKeepsTheEnteredPrecisionAcrossTheWholeRange() throws {
        let sources = ["x = 0,0", "x = 0,00", "x = 1,00", "x = 5,0", "x = 9,81", "x = 0,000",
                       "x = 12,5", "x = 3,14", "x = 5e-3 s", "x = 1,25e-3", "x = -7,2", "x = 2,5e3"]
        for source in sources {
            let variable = try XCTUnwrap(AdjustableVariable(source: source))
            for steps in -250...250 {
                let value = VariableAdjustmentRange.stepped(from: variable.value, steps: steps, step: variable.automaticStep)
                let written = try XCTUnwrap(variable.source(replacingValue: value))
                let reparsed = try XCTUnwrap(AdjustableVariable(source: written), written)
                XCTAssertEqual(reparsed.automaticStep, variable.automaticStep, written)
            }
        }
    }

    func testRelativeRulerFreezesItsOriginAndHasNoBounds() {
        // Each drag update uses total displacement, not the previous result.
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 8.2, steps: 3, step: 0.1), 8.5)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 8.2, steps: 1, step: 0.1), 8.3)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 8.2, steps: 0, step: 0.1), 8.2)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: -0.1, steps: 1, step: 0.1), 0)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 0, steps: -1, step: 0.1), -0.1)
        // Past twice the entered value, and below zero: nothing stops the ruler.
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 80, steps: 100, step: 1), 180)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 80, steps: 1_000_000, step: 1), 1_000_080)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 80, steps: -100, step: 1), -20)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 8.2, steps: 100, step: 0.1), 18.2)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: 8.2, steps: -100, step: 0.1), -1.8)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: -8.2, steps: -100, step: 0.1), -18.2)
        let huge = VariableAdjustmentRange.stepped(from: 1e250, steps: 1, step: 1e249)
        XCTAssertTrue(huge.isFinite)
        XCTAssertGreaterThan(huge, 1e250)
        XCTAssertGreaterThan(VariableAdjustmentRange.stepped(from: .leastNonzeroMagnitude, steps: 1, step: .leastNonzeroMagnitude),
                             .leastNonzeroMagnitude)
        // Double runs out: the value stops at its largest finite number instead of becoming infinite.
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: Double.greatestFiniteMagnitude, steps: 5, step: 1e300),
                       Double.greatestFiniteMagnitude)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: -Double.greatestFiniteMagnitude, steps: -5, step: 1e300),
                       -Double.greatestFiniteMagnitude)
    }

    func testSteppingAcrossZeroWritesDecimalSourcesWithoutBinaryNoise() throws {
        let variable = try XCTUnwrap(AdjustableVariable(source: "m = 0,3 kg # masse"))
        var written: [String] = []
        for steps in [-2, -3, -4, -13] {
            let value = VariableAdjustmentRange.stepped(from: variable.value, steps: steps, step: variable.automaticStep)
            written.append(try XCTUnwrap(variable.source(replacingValue: value)))
        }
        XCTAssertEqual(written, ["m = 0,1 kg # masse", "m = 0,0 kg # masse", "m = -0,1 kg # masse", "m = -1,0 kg # masse"])
        let negative = try XCTUnwrap(AdjustableVariable(source: "m = -0,1 kg"))
        XCTAssertEqual(negative.value, -0.1)
        XCTAssertEqual(VariableAdjustmentRange.stepped(from: negative.value, steps: 2, step: negative.automaticStep), 0.1)
        // The whole-number step also runs far past twice the entered number, and below zero.
        let mass = try XCTUnwrap(AdjustableVariable(source: "m = 80 kg"))
        XCTAssertEqual(mass.source(replacingValue: VariableAdjustmentRange.stepped(from: 80, steps: 500, step: mass.automaticStep)),
                       "m = 580 kg")
        XCTAssertEqual(mass.source(replacingValue: VariableAdjustmentRange.stepped(from: 80, steps: -500, step: mass.automaticStep)),
                       "m = -420 kg")
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

    func testExtremelySmallAndLargeValuesHaveFinitePlotIntervals() throws {
        for number in [Double.leastNonzeroMagnitude, -Double.leastNonzeroMagnitude,
                       1e-250, -1e-250, 1e250, -1e250,
                       Double.greatestFiniteMagnitude, -Double.greatestFiniteMagnitude] {
            let range = try XCTUnwrap(VariableAdjustmentRange.suggested(for: number), String(number))
            XCTAssertGreaterThan(range.step, 0)
            XCTAssertTrue(range.step.isFinite)
            XCTAssertLessThan(range.lowerBound, range.upperBound)
            let next = VariableAdjustmentRange.stepped(from: number, steps: 1, step: range.step)
            let previous = VariableAdjustmentRange.stepped(from: number, steps: -1, step: range.step)
            XCTAssertTrue(next.isFinite)
            XCTAssertTrue(previous.isFinite)
            XCTAssertGreaterThanOrEqual(next, number)
            XCTAssertLessThanOrEqual(previous, number)
        }
        XCTAssertNil(VariableAdjustmentRange.suggested(for: .nan))
        XCTAssertNil(VariableAdjustmentRange.suggested(for: .infinity))
    }

    func testInvalidRangesAreRejected() {
        let invalid: [(Double, Double, Double)] = [
            (0, 0, 1), (1, 0, 1), (0, 1, 0), (0, 1, -0.1),
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
