import XCTest
@testable import EvalCore

final class FunctionTests: XCTestCase {
    private func line(_ source: String, _ index: Int = 0) -> EvaluatedLine {
        NotebookEngine.evaluate(source).lines[index]
    }

    private func quantity(_ source: String, _ index: Int = 0, file: StaticString = #filePath, line sourceLine: UInt = #line) throws -> Quantity {
        let result = line(source, index)
        XCTAssertEqual(result.status, .success, result.message ?? source, file: file, line: sourceLine)
        return try XCTUnwrap(result.quantity, source, file: file, line: sourceLine)
    }

    private func message(_ source: String, _ index: Int = 0) -> String {
        let result = line(source, index)
        XCTAssertEqual(result.status, .error, source)
        return result.message ?? ""
    }

    func testFunctionArgumentsUseSemicolon() throws {
        XCTAssertEqual(try quantity("min(2; 3)").value, 2)
        XCTAssertEqual(try quantity("max(2,5; 3)").value, 3)
        XCTAssertEqual(try quantity("max(1; 2; 7; 4)").value, 7)
        XCTAssertEqual(try quantity("max(2 * 2; min(9; 6))").value, 6)
        XCTAssertEqual(try quantity("max(1;2)").value, 2)
        XCTAssertEqual(try quantity("a = 4\nb = 9\nmax(a; b)", 2).value, 9)
    }

    func testMinuteUnitAndMinFunctionCoexist() throws {
        XCTAssertEqual(try quantity("5 min").value, 300)
        XCTAssertEqual(try quantity("min").value, 60)
        XCTAssertEqual(try quantity("t = 3 min(2)").value, 360)
        XCTAssertEqual(try quantity("min(2; 3)").value, 2)
        XCTAssertEqual(try quantity("2 * min(2; 3)").value, 4)
    }

    func testCommaInsideFunctionCallExplainsDecimalSeparator() {
        XCTAssertEqual(message("min(2,3)"),
                       "min attend au moins 2 arguments séparés par « ; », par exemple min(a; b). Attention : avec une virgule, 2,3 est un nombre décimal.")
        XCTAssertEqual(message("max(2, 3)"),
                       "Séparez les arguments de max par « ; » : la virgule est le séparateur décimal, par exemple max(2,5; 3). (colonne 6)")
        XCTAssertEqual(message("max(a, b)"),
                       "Séparez les arguments de max par « ; » : la virgule est le séparateur décimal, par exemple max(2,5; 3). (colonne 6)")
        XCTAssertEqual(message("sin(2, 3)"), "sin attend un seul argument ; la virgule est le séparateur décimal (2,5). (colonne 6)")
        XCTAssertEqual(message("sin(2; 3)"), "sin attend un seul argument.")
        XCTAssertEqual(message("atan2(1; 2; 3)"), "atan2 attend 2 arguments séparés par « ; », par exemple atan2(y; x).")
        XCTAssertEqual(message("log(1; 2; 3)"), "log attend 1 ou 2 arguments : log(x) ou log(x; b).")
        XCTAssertEqual(message("max(" + Array(repeating: "1", count: 51).joined(separator: "; ") + ")"),
                       "max accepte au plus 50 arguments.")
        // A single argument that is not a decimal comma number gets no such hint.
        XCTAssertEqual(message("max(5)"), "max attend au moins 2 arguments séparés par « ; », par exemple max(a; b).")
    }

    func testStraySemicolonAndCommaAreReported() {
        XCTAssertEqual(message("2;3"), "« ; » sépare les arguments d’une fonction, par exemple max(a; b). (colonne 2)")
        XCTAssertEqual(message("(2;3)"), "« ; » sépare les arguments d’une fonction, par exemple max(a; b). (colonne 3)")
        XCTAssertEqual(message("2,"),
                       "Virgule inattendue : la virgule est le séparateur décimal (2,5). Séparez les arguments d’une fonction par « ; ». (colonne 2)")
        XCTAssertEqual(message("(2, 3)"),
                       "Virgule inattendue : la virgule est le séparateur décimal (2,5). Séparez les arguments d’une fonction par « ; ». (colonne 3)")
        // Existing diagnostics are unchanged.
        XCTAssertTrue(message("1,2,3").hasPrefix("Un nombre ne peut contenir qu’un seul séparateur décimal"))
        XCTAssertTrue(message("1 000 m").hasPrefix("Deux nombres consécutifs"))
        XCTAssertEqual(try quantity("2,5 + ,5").value, 3)
    }

    func testFunctionNamesCanBeDeclaredAsVariables() throws {
        let length = try quantity("max = 10 m\nmax * 2", 1)
        XCTAssertEqual(length.value, 20)
        XCTAssertTrue(length.dimension.isEquivalent(to: .length))
        XCTAssertEqual(try quantity("floor = 3\nfloor + 1", 1).value, 4)
        XCTAssertEqual(try quantity("sin = 3\nsin", 1).value, 3)
        XCTAssertEqual(line("max = 3\nmax", 1).kind, .expression)
        XCTAssertEqual(line("max = 3").kind, .definition)
        XCTAssertEqual(line("max_1 = 3").status, .success)
        XCTAssertEqual(line("sinh1 = 3").status, .success)
    }

    func testANameIsACallOnlyWhenFollowedByAParenthesis() throws {
        XCTAssertEqual(try quantity("max = 3\nmax(1; 5)", 1).value, 5)
        XCTAssertEqual(try quantity("max = 3\nmax(1; 5) + max", 1).value, 8)
        XCTAssertEqual(try quantity("min = 2\nmin(4; 9) * min", 1).value, 8)
        XCTAssertEqual(try quantity("5 min").value, 300)
        XCTAssertTrue(message("sin").hasPrefix("Utilisez sin(expression) pour cette fonction"))
        XCTAssertTrue(message("2 * max").hasPrefix("Utilisez max(expression) pour cette fonction"))
    }

    func testInverseTrigonometryReturnsRadians() throws {
        XCTAssertEqual(try quantity("asin(0,5)").value, 0.5235987755982989, accuracy: 1e-15)
        XCTAssertEqual(try quantity("arcsin(0,5)").value, try quantity("asin(0,5)").value)
        XCTAssertEqual(try quantity("acos(0,5)").value, 1.0471975511965979, accuracy: 1e-15)
        XCTAssertEqual(try quantity("atan(1)").value, .pi / 4, accuracy: 1e-15)
        XCTAssertEqual(try quantity("arctan(1)").value, .pi / 4, accuracy: 1e-15)
        let degrees = line("acos(0,5) -> deg")
        XCTAssertEqual(QuantityFormatter.string(try XCTUnwrap(degrees.quantity), in: degrees.displayUnit), "60 deg")
        XCTAssertEqual(message("asin(2)"), "asin nécessite une valeur comprise entre −1 et 1.")
        XCTAssertEqual(message("acos(-1,5)"), "acos nécessite une valeur comprise entre −1 et 1.")
        XCTAssertEqual(message("asin(1 m)"), "La fonction asin nécessite un argument sans dimension.")
    }

    func testAtan2RequiresHomogeneousArguments() throws {
        XCTAssertEqual(try quantity("atan2(3 m; 4 m)").value, 0.6435011087932844, accuracy: 1e-15)
        XCTAssertEqual(try quantity("atan2(1; -1)").value, 3 * .pi / 4, accuracy: 1e-15)
        XCTAssertEqual(try quantity("atan2(30 cm; 0,4 m)").value, 0.6435011087932844, accuracy: 1e-15)
        XCTAssertEqual(message("atan2(3 m; 4 s)"), "atan2(y; x) nécessite deux grandeurs de même dimension : m et s.")
        XCTAssertEqual(message("atan2(0; 0)"), "atan2(0 ; 0) n’est pas défini.")
        XCTAssertEqual(line("atan2(3 m; 4 m)").dimensionMessage, nil)
    }

    func testHyperbolicFunctions() throws {
        XCTAssertEqual(try quantity("sinh(1)").value, 1.1752011936438014, accuracy: 1e-15)
        XCTAssertEqual(try quantity("cosh(0)").value, 1)
        XCTAssertEqual(try quantity("tanh(0)").value, 0)
        XCTAssertEqual(try quantity("tanh(1)").value, 0.7615941559557649, accuracy: 1e-15)
        XCTAssertTrue(message("sinh(1000)").hasPrefix("Résultat non réel ou dépassement"))
        XCTAssertEqual(message("cosh(1 s)"), "La fonction cosh nécessite un argument sans dimension.")
    }

    func testCubeAndNthRootsScaleDimensions() throws {
        let cube = try quantity("cbrt(-8 m³)")
        XCTAssertEqual(cube.value, -2)
        XCTAssertTrue(cube.dimension.isEquivalent(to: .length))
        XCTAssertEqual(try quantity("cbrt(27)").value, 3)
        XCTAssertEqual(try quantity("cbrt(64)").value, 4)
        let fourth = try quantity("root(16 m⁴; 4)")
        XCTAssertEqual(fourth.value, 2)
        XCTAssertTrue(fourth.dimension.isEquivalent(to: .length))
        XCTAssertEqual(try quantity("root(-32; 5)").value, -2)
        XCTAssertTrue(message("(-8)^(1/3)").hasPrefix("Résultat non réel"))
        XCTAssertEqual(message("root(-16; 4)"), "Une racine d’indice pair nécessite une valeur positive ou nulle.")
        let index = "L’indice d’une racine doit être un entier sans dimension compris entre 2 et 1000."
        XCTAssertEqual(message("root(16; 1)"), index)
        XCTAssertEqual(message("root(16; 2,5)"), index)
        XCTAssertEqual(message("root(16; 2 s)"), index)
        XCTAssertEqual(message("root(16; 1001)"), index)
        XCTAssertEqual(line("cbrt(27)").kind, .expression)
    }

    func testLogarithmWithBase() throws {
        XCTAssertEqual(try quantity("log(8; 2)").value, 3, accuracy: 1e-15)
        XCTAssertEqual(try quantity("log(1000)").value, 3, accuracy: 1e-15)
        XCTAssertEqual(try quantity("log(1000; 10)").value, 3, accuracy: 1e-15)
        XCTAssertEqual(try quantity("log(81; 3)").value, 4, accuracy: 1e-14)
        XCTAssertEqual(message("log(8; 1)"), "La base d’un logarithme doit être strictement positive et différente de 1.")
        XCTAssertEqual(message("log(8; -2)"), "La base d’un logarithme doit être strictement positive et différente de 1.")
        XCTAssertEqual(message("log(-8; 2)"), "Un logarithme nécessite une valeur strictement positive.")
        XCTAssertEqual(message("log(8 m; 2)"), "La fonction log nécessite un argument sans dimension.")
    }

    func testMinMaxKeepDimensionAndRejectMixedDimensions() throws {
        let longest = try quantity("max(2 m; 30 cm)")
        XCTAssertEqual(longest.value, 2)
        XCTAssertTrue(longest.dimension.isEquivalent(to: .length))
        XCTAssertEqual(line("max(2 m; 30 cm)").dimensionMessage, "Homogène · m")
        XCTAssertEqual(try quantity("min(2 m; 30 cm; 1 m)").value, 0.3, accuracy: 1e-15)
        XCTAssertEqual(message("max(2 m; 3 s)"), "max compare des grandeurs de même dimension : impossible de comparer m et s.")
        XCTAssertEqual(message("min(1 m; 1 m; 3 kg)"), "min compare des grandeurs de même dimension : impossible de comparer m et kg.")
    }

    func testRoundingFunctionsRequireDimensionlessArgument() throws {
        XCTAssertEqual(try quantity("floor(2,7)").value, 2)
        XCTAssertEqual(try quantity("floor(-2,5)").value, -3)
        XCTAssertEqual(try quantity("ceil(2,1)").value, 3)
        XCTAssertEqual(try quantity("round(2,5)").value, 3)
        XCTAssertEqual(try quantity("round(-2,5)").value, -3)
        XCTAssertEqual(try quantity("round(2,4)").value, 2)
        XCTAssertEqual(try quantity("round(7,5 s / 2 s)").value, 4)
        XCTAssertEqual(message("round(2 m)"),
                       "La fonction round nécessite un argument sans dimension ; divisez d’abord par une unité, par exemple round(t / 1 s).")
        XCTAssertTrue(message("floor(2 m)").contains("floor(t / 1 s)"))
    }

    func testAngleHintOnlyForTrigonometricFunctions() {
        XCTAssertEqual(message("sin(2 m)"), "La fonction sin nécessite un argument sans dimension. Pour un angle, utilisez rad ou deg.")
        XCTAssertEqual(message("exp(2 m)"), "La fonction exp nécessite un argument sans dimension.")
        XCTAssertEqual(message("ln(2 m)"), "La fonction ln nécessite un argument sans dimension.")
    }

    func testPercentIsDimensionlessHundredth() throws {
        XCTAssertEqual(try quantity("35 %").value, 0.35, accuracy: 1e-15)
        XCTAssertEqual(try quantity("35%").value, try quantity("35 %").value)
        XCTAssertEqual(try quantity("rendement = 35 %\nP = rendement * 2 kW\nP", 2).value, 700, accuracy: 1e-10)
        XCTAssertEqual(try quantity("50 % * 2").value, 1)
        XCTAssertEqual(try quantity("200 * 15 %").value, 30, accuracy: 1e-12)
        XCTAssertTrue(try quantity("35 %").dimension.isDimensionless)
    }

    func testPercentCannotBeDeclared() {
        XCTAssertEqual(line("% = 3").status, .error)
        XCTAssertEqual(line("% = 3").kind, .equation)
    }

    func testFactorialPrecedenceAndDomain() throws {
        XCTAssertEqual(try quantity("5!").value, 120)
        XCTAssertEqual(try quantity("0!").value, 1)
        XCTAssertEqual(try quantity("3!^2").value, 36)
        XCTAssertEqual(try quantity("2^3!").value, 64)
        XCTAssertEqual(try quantity("-3!").value, -6)
        XCTAssertEqual(try quantity("(2+1)!").value, 6)
        XCTAssertEqual(try quantity("n = 4\nn!", 1).value, 24)
        XCTAssertEqual(try quantity("3!!").value, 720)
        XCTAssertEqual(try quantity("170!").value, 7.257415615307994e306, accuracy: 1e292)
        let domain = "La factorielle nécessite un entier sans dimension compris entre 0 et 170."
        for source in ["171!", "2,5!", "(2 m)!", "(-1)!"] { XCTAssertEqual(message(source), domain, source) }
    }

    func testNotEqualsIsNotAnOperator() {
        XCTAssertEqual(message("3 != 4"), "Utilisez == pour comparer ; ≠ n’est pas pris en charge.")
        XCTAssertEqual(line("3! == 6").status, .success)
        XCTAssertEqual(line("3! = 6").status, .success)
    }

    func testMultiArgumentFunctionDependenciesAreFollowed() throws {
        let evaluation = NotebookEngine.evaluate("x = max(a; b)\na = 2 m\nb = 5 m\nx")
        XCTAssertEqual(evaluation.lines[0].quantity?.value, 5)
        XCTAssertEqual(evaluation.lines[3].quantity?.value, 5)
    }

    func testDeeplyNestedCallsEvaluateOnTheSmallStackOfASecondaryThread() {
        let nested = String(repeating: "max(1; ", count: 70) + "2" + String(repeating: ")", count: 70)
        let roots = String(repeating: "cbrt(", count: 70) + "1" + String(repeating: ")", count: 70)
        let many = "max(" + (1...50).map(String.init).joined(separator: "; ") + ")"
        let source = [nested, roots, "2 m -> " + String(repeating: "(", count: 70) + "m" + String(repeating: ")", count: 70),
                      many, "x = 3!!!!\nx"].joined(separator: "\n")
        let done = expectation(description: "Feuille évaluée")
        let thread = Thread {
            let evaluation = NotebookEngine.evaluate(source)
            XCTAssertEqual(evaluation.lines[0].quantity?.value, 2)
            XCTAssertEqual(evaluation.lines[1].quantity?.value, 1)
            XCTAssertEqual(evaluation.lines[2].status, .success)
            XCTAssertEqual(evaluation.lines[3].quantity?.value, 50)
            XCTAssertNotNil(MathNotation.formula(nested))
            done.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [done], timeout: 30)
    }

    func testNestedCallsAtTheGuardLimitDoNotOverflowTheSmallStack() {
        func nest(_ function: String, _ depth: Int) -> String {
            String(repeating: "\(function)(", count: depth) + "1" + String(repeating: ")", count: depth)
        }
        let allowed = nest("sin", 79), tooDeep = nest("sin", 80), tooDeepRoots = nest("sqrt", 200)
        let done = expectation(description: "Feuilles évaluées")
        let thread = Thread {
            let evaluation = NotebookEngine.evaluate([allowed, tooDeep, tooDeepRoots, "max(2; " + nest("abs", 78) + ")"].joined(separator: "\n"))
            XCTAssertEqual(evaluation.lines[0].status, .success)
            for index in 1...2 {
                XCTAssertTrue(evaluation.lines[index].message?.contains("trop imbriquée") == true, "ligne \(index)")
            }
            XCTAssertEqual(evaluation.lines[3].quantity?.value, 2)
            done.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [done], timeout: 30)
    }
}
