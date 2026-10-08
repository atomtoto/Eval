import XCTest
@testable import EvalCore

final class SolveTests: XCTestCase {
    private func evaluate(_ lines: String...) -> NotebookEvaluation {
        NotebookEngine.evaluate(lines.joined(separator: "\n"))
    }

    private func shown(_ line: EvaluatedLine) -> String {
        line.quantity.map { QuantityFormatter.string($0, in: line.displayUnit) } ?? "-"
    }

    func testKineticEnergyGivesBothSpeeds() {
        let result = evaluate("E = 1000 J", "m = 80 kg", "v = ? m/s", "E == 0,5 * m * v²")
        XCTAssertEqual(result.lines[2].status, .success)
        XCTAssertEqual(result.lines[2].kind, .definition)
        XCTAssertEqual(shown(result.lines[2]), "5 m/s")
        XCTAssertEqual(result.lines[2].quantity?.value ?? 0, 5, accuracy: 1e-11)
        XCTAssertEqual(result.lines[2].message, "Autre solution : −5 m/s.")
        // The relation then verifies by itself.
        XCTAssertEqual(result.lines[3].status, .success)
        XCTAssertEqual(result.lines[3].message, "Égalité vérifiée.")
        XCTAssertEqual(result.variables.first { $0.name == "v" }?.quantity.value ?? 0, 5, accuracy: 1e-11)
    }

    func testRelationMayComeBeforeTheUnknown() {
        let result = evaluate("E == 0,5 * m * v²", "E = 1000 J", "m = 80 kg", "v = ? m/s", "v")
        XCTAssertEqual(result.lines.map(\.status), [.success, .success, .success, .success, .success])
        XCTAssertEqual(result.lines[4].quantity?.value ?? 0, 5, accuracy: 1e-11)
    }

    func testPendulumLength() {
        let result = evaluate("T = 1 s", "l = ? m", "T == 2 * pi * sqrt(l / g)")
        XCTAssertEqual(shown(result.lines[1]), "0,248405 m")
        // Only the positive branch exists: no other solution is announced.
        XCTAssertNil(result.lines[1].message)
        XCTAssertEqual(result.lines[2].message, "Égalité vérifiée.")
    }

    func testHalfChargeTimeOfAnRCCircuit() {
        let result = evaluate("R = 10 kΩ", "C = 100 µF", "tau = R * C", "U0 = 12 V", "t = ? s",
                              "U0 / 2 == U0 * (1 - exp(-t / tau))")
        XCTAssertEqual(shown(result.lines[4]), "0,693147 s")
        XCTAssertEqual(result.lines[4].quantity?.value ?? 0, Foundation.log(2), accuracy: 1e-12)
        XCTAssertEqual(result.lines[5].status, .success)
    }

    func testTheUnknownIsShownInItsUnitUnlessAnArrowOverridesIt() {
        let result = evaluate("E = 1000 J", "m = 80 kg", "v = ? km/h", "E == 0,5 * m * v²",
                              "w = ? m/s → km/h", "E == 0,5 * m * w²")
        XCTAssertEqual(shown(result.lines[2]), "18 km/h")
        XCTAssertEqual(result.lines[2].displayUnit?.symbol, "km/h")
        XCTAssertEqual(result.lines[2].message, "Autre solution : −18 km/h.")
        XCTAssertEqual(result.lines.map(\.status), Array(repeating: .success, count: 6))
    }

    func testAConversionArrowOnTheUnknownLineOverridesTheUnit() {
        let result = evaluate("E = 1000 J", "m = 80 kg", "v = ? m/s → km/h", "E == 0,5 * m * v²")
        XCTAssertEqual(shown(result.lines[2]), "18 km/h")
    }

    func testAnUnknownWithoutUnitIsDimensionless() {
        let result = evaluate("x = ?", "x² == 2")
        XCTAssertEqual(result.lines[0].quantity?.value ?? 0, 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(result.lines[0].message, "Autre solution : −1,41421.")
        XCTAssertTrue(result.lines[0].quantity?.dimension.isDimensionless == true)
    }

    func testUnknownsReachedThroughOtherDeclarations() {
        let result = evaluate("v = ? m", "d = 2 * v", "x = d + 1 m", "x == 11 m", "d")
        XCTAssertEqual(result.lines.map(\.status), Array(repeating: .success, count: 5))
        XCTAssertEqual(result.lines[0].quantity?.value ?? 0, 5, accuracy: 1e-11)
        XCTAssertEqual(result.lines[4].quantity?.value ?? 0, 10, accuracy: 1e-10)
    }

    func testLongDependentChainsAreResolvedBottomUp() {
        var lines = ["v = ? m", "d0 = v"]
        for index in 1..<120 { lines.append("d\(index) = d\(index - 1) + 1 m") }
        lines.append("d119 == 130 m")
        let result = NotebookEngine.evaluate(lines.joined(separator: "\n"))
        XCTAssertEqual(result.lines[0].status, .success, result.lines[0].message ?? "")
        XCTAssertEqual(result.lines[0].quantity?.value ?? 0, 11, accuracy: 1e-10)
        XCTAssertEqual(result.lines.last?.status, .success)
    }

    func testPositiveRootComesFirstAndOthersAreAnnounced() {
        let result = evaluate("x = ?", "sin(x) == 0,5")
        XCTAssertEqual(result.lines[0].quantity?.value ?? 0, Foundation.asin(0.5), accuracy: 1e-12)
        XCTAssertEqual(result.lines[0].message,
                       "Autre solution : −3,66519. D’autres solutions sont possibles ; la plus proche de zéro est affichée.")
    }

    func testOnlyANegativeRootIsReturnedWhenNoPositiveOneExists() {
        let result = evaluate("x = ? m", "x == -3 m")
        XCTAssertEqual(result.lines[0].quantity?.value ?? 0, -3, accuracy: 1e-12)
        XCTAssertNil(result.lines[0].message)
    }

    func testNoSolutionAndPolesAreReported() {
        let none = evaluate("x = ? m", "x² == -1 m²")
        XCTAssertEqual(none.lines[0].message, "Aucune solution trouvée entre 10⁻¹² et 10¹² m.")
        XCTAssertEqual(none.lines[0].status, .error)
        // 1/(x − 5) changes sign at 5 without ever being zero.
        let pole = evaluate("x = ?", "1 / (x - 5) == 0")
        XCTAssertEqual(pole.lines[0].message, "Aucune solution trouvée entre 10⁻¹² et 10¹².")
        let outside = evaluate("x = ? m", "x == 1e15 m")
        XCTAssertEqual(outside.lines[0].message, "Aucune solution trouvée entre 10⁻¹² et 10¹² m.")
    }

    func testMissingAndMultipleRelationsAreExplained() {
        XCTAssertEqual(evaluate("v = ? m/s").lines[0].message,
                       "Aucune relation ne permet de calculer « v ». Ajoutez une ligne avec == qui contient v, par exemple 1000 J == 0,5 * m * v².")
        XCTAssertEqual(evaluate("v = 2 m/s\nv = ? m/s\nv == 1 m/s").lines[1].message,
                       "« v » est déclaré plusieurs fois (lignes 1, 2). Conservez une seule déclaration.")
        let several = evaluate("x = ? m", "x == 2 m", "x * 2 == 4 m")
        XCTAssertEqual(several.lines[0].message,
                       "Plusieurs relations contiennent « x » (lignes 2, 3). Gardez une seule relation avec == pour le calculer.")
        XCTAssertEqual(several.lines[1].status, .error)
        // A declaration is not a relation.
        XCTAssertEqual(evaluate("x = ? m", "y = x * 2").lines[0].status, .error)
    }

    func testDimensionsAreCheckedAgainstTheUnknownsUnit() {
        let wrongUnit = evaluate("E = 1000 J", "m = 80 kg", "v = ? m", "E == 0,5 * m * v²")
        XCTAssertEqual(wrongUnit.lines[2].message,
                       "Équation non homogène : le membre gauche a pour dimension kg·m²·s⁻², le membre droit kg·m², avec v en m.")
        let mismatch = evaluate("x = ? m", "x == 2 s")
        XCTAssertTrue(mismatch.lines[0].message?.hasPrefix("Équation non homogène") == true)
        XCTAssertEqual(mismatch.lines[1].status, .error)
        let nothingToEvaluate = evaluate("x = ? m", "sqrt(x) == foo")
        XCTAssertTrue(nothingToEvaluate.lines[0].message?.hasPrefix("La relation de la ligne 2 ne peut pas être évaluée pour « x » : ") == true,
                      nothingToEvaluate.lines[0].message ?? "")
    }

    func testUnitOfTheUnknownMustBeKnown() {
        XCTAssertEqual(evaluate("x = ? foo").lines[0].message,
                       "L’unité « foo » de l’inconnue n’est pas reconnue. Écrivez seulement une unité, par exemple v = ? m/s.")
    }

    func testTwoUnknownsInOneRelationAreRefused() {
        let result = evaluate("x = ? m", "y = ? m", "x + y == 3 m")
        XCTAssertEqual(result.lines[0].message, "La relation de « x » contient aussi l’inconnue « y » : une seule inconnue par relation.")
        XCTAssertEqual(result.lines[1].message, "La relation de « y » contient aussi l’inconnue « x » : une seule inconnue par relation.")
    }

    func testIndependentUnknownsAreSolvedSeparately() {
        let result = evaluate("x = ? m", "y = ? s", "x == 3 m", "y² == 4 s²")
        XCTAssertEqual(result.lines.map(\.status), Array(repeating: .success, count: 4))
        XCTAssertEqual(result.lines[0].quantity?.value ?? 0, 3, accuracy: 1e-12)
        XCTAssertEqual(result.lines[1].quantity?.value ?? 0, 2, accuracy: 1e-12)
    }

    func testConstantsUsedByTheRelationAreListed() {
        let result = evaluate("T = 1 s", "l = ? m", "T == 2 * pi * sqrt(l / g)")
        XCTAssertEqual(result.constants.map(\.id), ["pi", "g"])
    }

    func testUnknownLinesStayDefinitionsForSelectionAndIgnoreSliders() {
        XCTAssertNil(AdjustableVariable(source: "v = ? m/s"))
        XCTAssertNil(AdjustableVariable(source: "v = ?"))
        XCTAssertEqual(LineSyntax("v = ? m/s # vitesse").unknownUnit, "m/s")
        XCTAssertEqual(LineSyntax("v = ?").unknownUnit, "")
        XCTAssertEqual(LineSyntax("v = ? m/s -> km/h").unknownUnit, "m/s")
        XCTAssertNil(LineSyntax("v = 3 m").unknownUnit)
        XCTAssertNil(LineSyntax("v == ?").unknownUnit)
        XCTAssertNil(LineSyntax("v + 1 = ?").unknownUnit)
        XCTAssertNil(LineSyntax("? m").unknownUnit)
        var selection = ResultSelection(source: "v = ? m/s\nE == v", initiallySelectedLineIDs: [0])
        XCTAssertTrue(selection.isSelected(at: 0))
        // Changing the unit keeps the choice, as for any other declaration.
        selection.reconcile(source: "v = ? km/h\nE == v")
        XCTAssertTrue(selection.isSelected(at: 0))
        XCTAssertFalse(selection.isSelected(at: 1))
    }

    func testTheQuestionMarkIsDrawnAsAnAtomWithItsUnit() {
        XCTAssertEqual(MathNotation.formula("v = ?"), .row([.atom("v"), .atom(" = "), .atom("?")]))
        XCTAssertEqual(MathNotation.formula("v = ? m/s"),
                       .row([.atom("v"), .atom(" = "), .atom("?"), .atom(" "), .fraction(.atom("m"), .atom("s"))]))
        XCTAssertEqual(MathNotation.formula("t = ? s # durée"), .row([.atom("t"), .atom(" = "), .atom("?"), .atom(" "), .atom("s")]))
        XCTAssertEqual(MathNotation.formula("v = ? m/s → km/h"),
                       .row([.atom("v"), .atom(" = "), .atom("?"), .atom(" "), .fraction(.atom("m"), .atom("s")),
                             .atom(" → "), .fraction(.atom("km"), .atom("h"))]))
        XCTAssertNil(MathNotation.formula("1 + ?"))
    }

    func testEvaluationsAreBounded() throws {
        var count = 0
        // Periodic: infinitely many roots, yet only the nearest of each sign is refined.
        var search = RootSearch { x in count += 1; return Foundation.sin(x) - 0.5 }
        let periodic = try search.run()
        XCTAssertLessThanOrEqual(count, RootSearch.maxEvaluations)
        XCTAssertEqual(count, search.evaluations)
        XCTAssertEqual(try XCTUnwrap(periodic.positive), Foundation.asin(0.5), accuracy: 1e-12)
        XCTAssertTrue(periodic.hasMore)

        count = 0
        var hard = RootSearch { x in count += 1; return Foundation.pow(x - 3, 3) }
        let flat = try hard.run()
        XCTAssertLessThanOrEqual(count, RootSearch.maxEvaluations)
        XCTAssertEqual(try XCTUnwrap(flat.positive), 3, accuracy: 1e-3)

        count = 0
        var nowhere = RootSearch { _ in count += 1; return nil }
        XCTAssertEqual(try nowhere.run().valid, 0)
        XCTAssertEqual(count, 2 * RootSearch.pointsPerSign)
    }

    func testSolvingIsFast() {
        let source = "E = 1000 J\nm = 80 kg\nv = ? m/s\nE == 0,5 * m * v²\nT = 1 s\nl = ? m\nT == 2 * pi * sqrt(l / g)"
        let start = Date()
        for _ in 0..<20 { _ = NotebookEngine.evaluate(source) }
        XCTAssertLessThan(Date().timeIntervalSince(start) / 20, 0.05)
    }

    func testSolvingWorksOnTheSmallStackOfASecondaryThread() {
        var lines = ["v = ? m", "d0 = v"]
        for index in 1..<90 { lines.append("d\(index) = d\(index - 1) + 1 m") }
        lines.append("d89 == 100 m")
        let source = lines.joined(separator: "\n")
        let done = expectation(description: "Feuille évaluée")
        let thread = Thread {
            let evaluation = NotebookEngine.evaluate(source)
            XCTAssertEqual(evaluation.lines[0].quantity?.value ?? 0, 11, accuracy: 1e-10)
            done.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [done], timeout: 30)
    }

    func testIsHomogeneousReportsAnActualDimensionCheck() {
        let lines = NotebookEngine.evaluate("""
            2 m + 3 m
            2 m * 3 m
            a = 7,2 m/s²
            F = 14,4 N
            2 kg * a == F
            1 + 1 == 2
            max(2 m; 30 cm)
            5
            v = ? m
            v == 2 m
            """).lines
        XCTAssertEqual(lines.map(\.isHomogeneous), [true, false, false, false, true, false, true, false, false, true])
        XCTAssertEqual(lines.map { $0.dimensionMessage?.hasPrefix("Homogène") == true }.enumerated().filter { $0.element }.map(\.offset),
                       lines.enumerated().filter { $0.element.isHomogeneous }.map(\.offset))
    }
}
