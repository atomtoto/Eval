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
        XCTAssertEqual(updated, "v=0.001 km/s // vitesse")
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

    func testFractionalLiteralsAndScientificSigns() throws {
        let examples: [(String, Double)] = [
            ("x = ,5", 0.5), ("x = -.5", -0.5), ("x = 2,5E+3 mm", 2_500),
            ("x = -2e−3 s", -0.002), ("x = 7. m", 7)
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
}
