import XCTest
@testable import EvalCore

final class EquationTests: XCTestCase {
    private func evaluate(_ lines: String...) -> NotebookEvaluation {
        NotebookEngine.evaluate(lines.joined(separator: "\n"))
    }

    func testQuadraticGivesItsExactAndDecimalSolutions() {
        let result = evaluate("3x^2 + 2x - 3 = 0", "x =")
        let line = result.lines[1]
        XCTAssertEqual(line.status, .success, line.message ?? "")
        XCTAssertEqual(line.formattedValue, "(−1 ± √10)/3 ≈ 0,720759 ; −1,38743")
        XCTAssertEqual(line.quantity?.value ?? 0, (-1 + 10.0.squareRoot()) / 3, accuracy: 1e-12)
        XCTAssertEqual(line.solutions?.values.count, 2)
        // The equation then holds with the value the sheet uses.
        XCTAssertEqual(result.lines[0].message, "Égalité vérifiée.")
    }

    func testTheRequestMayComeFirst() {
        let result = evaluate("x =", "x² = 2")
        XCTAssertEqual(result.lines[0].formattedValue, "±√2 ≈ 1,41421 ; −1,41421")
    }

    func testRationalSolutionsNeedNoApproximation() {
        XCTAssertEqual(evaluate("x^2 - 5x + 6 = 0", "x =").lines[1].formattedValue, "2 ; 3")
        XCTAssertEqual(evaluate("2x = 3", "x =").lines[1].formattedValue, "1,5")
        XCTAssertEqual(evaluate("3x = 2", "x =").lines[1].formattedValue, "2/3 ≈ 0,666667")
        XCTAssertEqual(evaluate("x^3 - 6x^2 + 11x - 6 = 0", "x =").lines[1].formattedValue, "1 ; 2 ; 3")
        XCTAssertEqual(evaluate("x^3 = 2x", "x =").lines[1].formattedValue, "0 ; ±√2 ≈ 0 ; 1,41421 ; −1,41421")
    }

    func testADoubleRootIsSaidOnce() {
        let line = evaluate("x^2 - 2x + 1 = 0", "x =").lines[1]
        XCTAssertEqual(line.formattedValue, "1")
        XCTAssertEqual(line.message, "Solution double.")
    }

    func testNoRealSolutionGivesTheComplexOnes() {
        let line = evaluate("3x^2 + 2x + 1 = 0", "x =").lines[1]
        XCTAssertEqual(line.status, .error)
        XCTAssertEqual(line.message, "Aucune solution réelle : les solutions sont complexes, x = (−1 ± i√2)/3.")
    }

    func testDeclaredValuesAndUnitsAreUsed() {
        let result = evaluate("m = 80 kg", "1000 J = 0,5 * m * v^2", "v =")
        let line = result.lines[2]
        XCTAssertEqual(line.status, .success, line.message ?? "")
        XCTAssertEqual(line.formattedValue, "−5 m·s⁻¹ ; 5 m·s⁻¹")
        XCTAssertEqual(line.quantity?.value ?? 0, 5, accuracy: 1e-12)
        XCTAssertEqual(line.quantity?.dimension, Dimension(length: 1, time: -1))
    }

    func testAConversionShowsTheDecimalsInItsUnit() {
        let result = evaluate("1000 J = 0,5 * 80 kg * v^2", "v → km/h =")
        XCTAssertEqual(result.lines[1].formattedValue, "−18 km/h ; 18 km/h")
    }

    func testCoefficientsFromDeclarationsStayExactWhenSmall() {
        let result = evaluate("a = 3", "a x^2 + 2x - 3 = 0", "x =")
        XCTAssertEqual(result.lines[2].formattedValue, "(−1 ± √10)/3 ≈ 0,720759 ; −1,38743")
    }

    func testTheUnknownMayBeReadThroughADeclaration() {
        let result = evaluate("y = 2x + 1", "y^2 = 9", "x =", "y =")
        XCTAssertEqual(result.lines[2].formattedValue, "−2 ; 1")
        XCTAssertEqual(result.lines[2].message, "Les autres lignes utilisent x = 1.")
        XCTAssertEqual(result.lines[3].quantity?.value ?? 0, 3, accuracy: 1e-12)
    }

    func testOtherEquationsAreSolvedNumerically() {
        let line = evaluate("exp(x) = 2", "x =").lines[1]
        XCTAssertEqual(line.status, .success, line.message ?? "")
        XCTAssertEqual(line.quantity?.value ?? 0, Foundation.log(2), accuracy: 1e-12)
        XCTAssertNil(line.solutions)

        // The dimension of d follows from the equation; l would be the litre.
        let pendulum = evaluate("2 s = 2 * pi * sqrt(d / g)", "d =").lines[1]
        XCTAssertEqual(pendulum.status, .success, pendulum.message ?? "")
        XCTAssertEqual(pendulum.formattedValue, "0,993621 m")
    }

    func testPowersOfSumsAreExpanded() {
        XCTAssertEqual(evaluate("(x - 1)^10 = 0", "x =").lines[1].message, "Solution de multiplicité 10.")
        XCTAssertEqual(evaluate("(x + 1)^2 = 4", "x =").lines[1].formattedValue, "−3 ; 1")
    }

    func testHigherDegreesAreSolvedNumerically() {
        let line = evaluate("x^3 + x - 1 = 0", "x =").lines[1]
        XCTAssertEqual(line.status, .success, line.message ?? "")
        XCTAssertEqual(line.quantity?.value ?? 0, 0.6823278038280193, accuracy: 1e-12)
    }

    func testUndeclaredNamesWithoutRequestKeepTheirError() {
        let result = evaluate("F == m * acc", "m = 2 kg", "F = 4 N")
        XCTAssertEqual(result.lines[0].status, .error)
        XCTAssertEqual(result.lines[0].message,
                       "« acc » est inconnu. Pour résoudre l’équation, ajoutez une ligne acc = ; pour une valeur connue, déclarez-la, par exemple acc = 2.")
    }

    func testRequestsNeedExactlyOneEquation() {
        XCTAssertEqual(evaluate("x =").lines[0].message,
                       "Aucune équation ne contient « x ». Écrivez-en une sur une ligne, par exemple 2x + 1 = 0, ou déclarez x = ….")
        XCTAssertEqual(evaluate("x + 1 = 2", "2x = 2", "x =").lines[2].message,
                       "Plusieurs équations contiennent « x » (lignes 1, 2). Gardez-en une seule pour le calculer.")
        XCTAssertEqual(evaluate("x + y = 2", "x =", "y =").lines[1].message,
                       "La relation de « x » contient aussi l’inconnue « y » : une seule inconnue par relation.")
    }

    func testDegenerateEquationsAreExplained() {
        XCTAssertEqual(evaluate("x - x = 1", "x =").lines[1].message,
                       "L’équation de la ligne 1 n’a pas de solution : « x » disparaît en la simplifiant.")
        XCTAssertEqual(evaluate("2x = x + x", "x =").lines[1].message,
                       "L’équation de la ligne 1 est vérifiée pour toute valeur de « x » : elle ne permet pas de le calculer.")
    }

    func testConstantsAndUnitsAreNotUnknowns() {
        // c is the speed of light, so `c =` shows it rather than solving.
        let result = evaluate("c = ", "2c = 6")
        XCTAssertEqual(result.lines[0].kind, .expression)
        XCTAssertNil(result.lines[0].solutions)
    }

    func testDependenciesIncludeTheEquationsNames() {
        let result = evaluate("a = 3", "a x^2 + 2x - 3 = 0", "x =")
        XCTAssertEqual(result.lines[2].dependencies, ["a"])
    }
}
