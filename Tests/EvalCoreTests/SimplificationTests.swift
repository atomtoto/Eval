import XCTest
@testable import EvalCore

final class SimplificationTests: XCTestCase {
    private func simplified(_ source: String) -> String? {
        FormulaSimplifier.simplifiedLine(source)
    }

    func testLikeTermsAreCollected() {
        XCTAssertEqual(simplified("2x + 3x"), "5x")
        XCTAssertEqual(simplified("3x^2 + 2x - 3 + x^2 - x"), "4x² + x - 3")
        XCTAssertEqual(simplified("a + b - a"), "b")
    }

    func testCommonFactorsCancel() {
        XCTAssertEqual(simplified("E = 0,5 * m * v^2 * 2 / m"), "E = v²")
        XCTAssertEqual(simplified("(a * b) / a ="), "b =")
        XCTAssertEqual(simplified("x * x * x"), "x³")
        XCTAssertEqual(simplified("x^5 / x^2"), "x³")
    }

    func testNumbersAreComputedExactly() {
        XCTAssertEqual(simplified("6 / 3"), "2")
        XCTAssertEqual(simplified("0,1 + 0,2"), "0,3")
        XCTAssertEqual(simplified("2 * 3 * x"), "6x")
        XCTAssertEqual(simplified("x / 3 + x / 6"), "x / 2")
        XCTAssertEqual(simplified("sqrt(12)"), "2√3")
        XCTAssertEqual(simplified("sqrt(x) * sqrt(x)"), "x")
    }

    func testExpansionIsKeptOnlyWhenSimpler() {
        XCTAssertEqual(simplified("x(x + 1) - x^2"), "x")
        XCTAssertEqual(simplified("(a + b)^2 - a^2 - b^2"), "2a * b")
        XCTAssertNil(simplified("(a + b)^2"))
    }

    func testFractionsAreReduced() {
        XCTAssertEqual(simplified("(x^2 - 1) / (x - 1)"), "x + 1")
        XCTAssertEqual(simplified("1/x + 1/(2x)"), "3 / (2x)")
    }

    func testFunctionsTakeTheirObviousValues() {
        XCTAssertEqual(simplified("sin(x)^2 + cos(x)^2"), "1")
        XCTAssertEqual(simplified("ln(exp(t))"), "t")
        XCTAssertEqual(simplified("y = cos(0) * y0"), "y = y0")
    }

    func testSimpleFormulasAreLeftAlone() {
        XCTAssertNil(simplified("E = 0,5 * m * v²"))
        XCTAssertNil(simplified("m * v² / 2"))
        XCTAssertNil(simplified("m*v^2/2"))
        XCTAssertNil(simplified("x^2 + 1"))
        XCTAssertNil(simplified("v = 5 m/s"))
        XCTAssertNil(simplified("# note"))
        XCTAssertNil(simplified("v = ? m/s"))
        XCTAssertNil(simplified("h * c / lambda ="))
    }

    func testTheRestOfTheLineIsKept() {
        XCTAssertEqual(simplified("d = 2 * t * v / 2 → km = # trajet"), "d = t * v → km = # trajet")
        XCTAssertEqual(simplified("2x + 3x == 10"), "5x == 10")
    }

    func testUnitsStayUnits() {
        XCTAssertEqual(simplified("2 m + 3 m"), "5 m")
        XCTAssertEqual(simplified("5 m/s * t * 2"), "10 m/s * t")
    }

    func testTheResultEvaluatesLikeTheOriginal() throws {
        let cases = ["E = 0,5 * m * v^2 * 2 / m", "x(x + 1) - x^2", "(x^2 - 1) / (x - 1)", "x / 3 + x / 6",
                     "1/x + 1/(2x)", "5 m/s * t * 2"]
        for source in cases {
            let simpler = try XCTUnwrap(simplified(source), source)
            let context = ["m = 3 kg", "v = 2 m/s", "x = 1,7", "t = 4 s"]
            let before = NotebookEngine.evaluate((context + [source]).joined(separator: "\n")).lines.last
            let after = NotebookEngine.evaluate((context + [simpler]).joined(separator: "\n")).lines.last
            XCTAssertEqual(before?.status, .success, source)
            XCTAssertEqual(after?.status, .success, simpler)
            XCTAssertEqual(before?.quantity?.value ?? .nan, after?.quantity?.value ?? 0, accuracy: 1e-9, simpler)
            XCTAssertEqual(before?.quantity?.dimension, after?.quantity?.dimension, simpler)
        }
    }
}
