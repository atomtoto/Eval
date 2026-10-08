import XCTest
@testable import EvalCore

final class NotebookEngineTests: XCTestCase {
    private let engine = NotebookEngine()

    func testDeclarationsResolveAboveAndBelowExpressions() throws {
        let above = engine.evaluate("a = 7,2 m/s²\nt = 3 s\na*t")
        let below = engine.evaluate("a*t\nt = 3 s\na = 7,2 m/s²")
        let first = try successfulQuantity(above.lines[2])
        let second = try successfulQuantity(below.lines[0])
        XCTAssertEqual(first.value, 21.6, accuracy: 1e-12)
        XCTAssertEqual(second.value, first.value, accuracy: 1e-12)
        XCTAssertTrue(second.dimension.isEquivalent(to: Dimension(length: 1, time: -1)))
    }

    func testMassVariableAndMetreUnitHaveSeparateNamespaces() throws {
        let evaluation = engine.evaluate("E = 0,5*m*v²\nm = 80 kg\nv = 5 m/s\nE")
        let energy = try successfulQuantity(evaluation.lines[0])
        let velocity = try successfulQuantity(evaluation.lines[2])
        XCTAssertEqual(energy.value, 1_000, accuracy: 1e-12)
        XCTAssertTrue(energy.dimension.isEquivalent(to: Dimension(length: 2, mass: 1, time: -2)))
        XCTAssertEqual(velocity.value, 5, accuracy: 1e-12)
        XCTAssertTrue(velocity.dimension.isEquivalent(to: Dimension(length: 1, time: -1)))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, energy.value)
    }

    func testSpacedUnitSuffixAndAdjacentVariableAreDisambiguated() throws {
        let evaluation = engine.evaluate("2m\n2 m\nm = 80 kg\n10N")
        let mass = try successfulQuantity(evaluation.lines[0])
        let length = try successfulQuantity(evaluation.lines[1])
        let force = try successfulQuantity(evaluation.lines[3])
        XCTAssertEqual(mass.value, 160)
        XCTAssertTrue(mass.dimension.isEquivalent(to: .mass))
        XCTAssertEqual(length.value, 2)
        XCTAssertTrue(length.dimension.isEquivalent(to: .length))
        XCTAssertEqual(force.value, 10)
        XCTAssertTrue(force.dimension.isEquivalent(to: Dimension(length: 1, mass: 1, time: -2)))
    }

    func testSpacedArithmeticEndsCompactUnitSuffix() throws {
        let evaluation = engine.evaluate("F = 2 m/s² * m\nm = 3 kg\nF\n2 kg*m/s²\n2 m/s² * h")
        let force = try successfulQuantity(evaluation.lines[0])
        let compactForce = try successfulQuantity(evaluation.lines[3])
        let planckProduct = try successfulQuantity(evaluation.lines[4])
        let forceDimension = Dimension(length: 1, mass: 1, time: -2)
        XCTAssertEqual(force.value, 6)
        XCTAssertTrue(force.dimension.isEquivalent(to: forceDimension))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 6)
        XCTAssertEqual(compactForce.value, 2)
        XCTAssertTrue(compactForce.dimension.isEquivalent(to: forceDimension))
        XCTAssertEqual(planckProduct.value, 2 * 6.62607015e-34)
        XCTAssertTrue(planckProduct.dimension.isEquivalent(to: Dimension(length: 3, mass: 1, time: -3)))
    }

    func testCompactUnitChainUsesUnitsNotConstants() throws {
        let evaluation = engine.evaluate("72km/h\n3g/cm³\nv = 72km/h\n9,81m/s²\n5m^2\n2kg*m/s²")
        let speed = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(speed.value, 20, accuracy: 1e-12)
        XCTAssertTrue(speed.dimension.isEquivalent(to: Dimension(length: 1, time: -1)))
        let density = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(density.value, 3_000, accuracy: 1e-9)
        XCTAssertTrue(density.dimension.isEquivalent(to: Dimension(length: -3, mass: 1)))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 20, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 9.81)
        XCTAssertTrue(try successfulQuantity(evaluation.lines[4]).dimension.isEquivalent(to: Dimension(length: 2)))
        XCTAssertTrue(try successfulQuantity(evaluation.lines[5]).dimension
            .isEquivalent(to: Dimension(length: 1, mass: 1, time: -2)))
        XCTAssertTrue(evaluation.constants.isEmpty, evaluation.constants.map(\.id).joined(separator: ", "))
    }

    func testCompactChainKeepsDeclaredVariables() throws {
        let evaluation = engine.evaluate("2m/s\nm = 80 kg\n72km/h\nh = 2 s")
        let flow = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(flow.value, 160)
        XCTAssertTrue(flow.dimension.isEquivalent(to: Dimension(mass: 1, time: -1)))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 36_000)
    }

    func testSingleCompactSymbolKeepsConstantPriority() throws {
        let evaluation = engine.evaluate("3g\n2e/h\n2h*c\n10N")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 3 * 9.80665, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 2 * 1.602176634e-19 / 6.62607015e-34,
                       accuracy: 1e3)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 2 * 6.62607015e-34 * 299_792_458,
                       accuracy: 1e-35)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 10)
        XCTAssertEqual(Set(evaluation.constants.map(\.id)), ["g", "e", "h", "c"])
    }

    func testNestedForwardReferencesAreIndependentOfDeclarationOrder() throws {
        let evaluation = engine.evaluate("x\nx = y*2\ny = z+1\nz = 3")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 8)
        XCTAssertEqual(evaluation.variables.count, 3)
    }

    func testDependencyChainsDoNotDependOnDeclarationOrderOrExpressionShape() throws {
        var chain = ["a0 = 1"]
        for index in 1...400 { chain.append("a\(index) = a\(index - 1) + 1") }
        let reversed = engine.evaluate(chain.reversed().joined(separator: "\n"))
        XCTAssertEqual(try successfulQuantity(reversed.lines[0]).value, 401)
        XCTAssertTrue(reversed.lines.allSatisfy { $0.status == .success })
        let ones = Array(repeating: "1", count: 100)
        let sum = engine.evaluate("x = 2\n" + (["x"] + ones).joined(separator: "+"))
        XCTAssertEqual(try successfulQuantity(sum.lines[1]).value, 102)
        // Constants and units are not dependencies: depth never limits them.
        let constant = engine.evaluate((["pi"] + ones).joined(separator: "+"))
        XCTAssertEqual(try successfulQuantity(constant.lines[0]).value, 100 + .pi, accuracy: 1e-9)
    }

    func testLongCyclesAndFailingChainsReportErrorsOnEveryLine() {
        let cycle = (0..<120).map { "c\($0) = c\(($0 + 1) % 120) + 1" }
        XCTAssertTrue(engine.evaluate(cycle.joined(separator: "\n")).lines.allSatisfy { $0.status == .error })
        var chain = ["b0 = 1 m + 1 s"]
        for index in 1...80 { chain.append("b\(index) = b\(index - 1) * 2") }
        let failing = engine.evaluate(chain.reversed().joined(separator: "\n"))
        XCTAssertTrue(failing.lines.allSatisfy { $0.status == .error })
        XCTAssertFalse(failing.lines.contains { $0.message?.contains("trop") == true },
                       failing.lines.compactMap(\.message).first ?? "")
    }

    func testLongSheetsEvaluateOnTheSmallStackOfASecondaryThread() {
        var chain = ["a0 = 1"]
        for index in 1...440 { chain.append("a\(index) = a\(index - 1) + 1") }
        // A long cycle and an expression deeper than the evaluation limit
        // reach the deepest recursion the engine allows.
        let cycle = (0..<40).map { "c\($0) = ((c\(($0 + 1) % 40) + 1))" }
        let deepSum = "s = 1 m + " + Array(repeating: "1 m", count: 300).joined(separator: " + ")
        let source = (chain.reversed() + cycle + [deepSum, "72km/h*" + Array(repeating: "m", count: 300).joined(separator: "*")])
            .joined(separator: "\n")
        let done = expectation(description: "Feuille évaluée")
        let thread = Thread {
            let evaluation = NotebookEngine.evaluate(source)
            XCTAssertEqual(evaluation.lines[0].quantity?.value, 441)
            XCTAssertTrue(evaluation.lines.dropFirst(441).allSatisfy { $0.status == .error })
            done.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [done], timeout: 30)
    }

    func testConstantsAreListedInOrderOfFirstUse() {
        let evaluation = engine.evaluate("2*g\nx = c*h\nx\nmu_0")
        XCTAssertEqual(evaluation.constants.map(\.id), ["g", "c", "h", "mu_0"])
    }

    func testDecimalCommaAndScientificNotation() throws {
        let evaluation = engine.evaluate("7,2\n2,5e3 mm\n1e-3 m")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 7.2, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 2.5, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 0.001, accuracy: 1e-12)
    }

    func testEnDashIsAMinusSignInScientificExponents() throws {
        let evaluation = engine.evaluate("2e–3\n2,5E–2 m")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 0.002)
        let length = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(length.value, 0.025)
        XCTAssertTrue(length.dimension.isEquivalent(to: .length))
    }

    func testReadableScientificNotationKeepsUnitsWhenASymbolIsDeclared() throws {
        let evaluation = engine.evaluate("x = 2 × 10³ m\ny = 2e3 m\nm = 5 kg")
        let readable = try successfulQuantity(evaluation.lines[0])
        let compact = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(readable.value, 2_000)
        XCTAssertEqual(readable.value, compact.value)
        XCTAssertTrue(readable.dimension.isEquivalent(to: .length))
        XCTAssertTrue(readable.dimension.isEquivalent(to: compact.dimension))
    }

    func testFormattedScientificResultCanBePastedBackIntoTheSheet() throws {
        let original = Quantity(value: 1e-6, dimension: .length)
        let formatted = QuantityFormatter.string(original)
        let evaluation = engine.evaluate(formatted + "\nm = 5 kg")
        let pasted = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(pasted.value, original.value, accuracy: 1e-18)
        XCTAssertTrue(pasted.dimension.isEquivalent(to: original.dimension))
    }

    func testImplicitMultiplicationAndParentheses() throws {
        let evaluation = engine.evaluate("2a\n3(a+1)\na = 4")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 8)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 15)
    }

    func testUnaryAndExponentPrecedence() throws {
        let evaluation = engine.evaluate("-2^2\n(-2)^2\n2^3^2\n2^-2")
        let expected = [-4.0, 4.0, 512.0, 0.25]
        for (line, value) in zip(evaluation.lines, expected) {
            XCTAssertEqual(try successfulQuantity(line).value, value, accuracy: 1e-12)
        }
    }

    func testConstantsAreResolvedAndReportedWithoutDeclarations() throws {
        let evaluation = engine.evaluate("2c\nc")
        let quantity = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(quantity.value, 599_584_916)
        XCTAssertTrue(quantity.dimension.isEquivalent(to: Dimension(length: 1, time: -1)))
        XCTAssertTrue(evaluation.constants.contains { $0.symbol == "c" })
        XCTAssertEqual(evaluation.constants.filter { $0.symbol == "c" }.count, 1)
    }

    func testExplicitDeclarationCanOverrideAConstant() throws {
        let evaluation = engine.evaluate("2c\nc = 12 m/s")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 24)
    }

    func testCompatibleUnitsAreConvertedBeforeAddition() throws {
        let evaluation = engine.evaluate("1 m + 20 cm\n36 km/h")
        let length = try successfulQuantity(evaluation.lines[0])
        let speed = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(length.value, 1.2, accuracy: 1e-12)
        XCTAssertTrue(length.dimension.isEquivalent(to: .length))
        XCTAssertEqual(speed.value, 10, accuracy: 1e-12)
        XCTAssertTrue(speed.dimension.isEquivalent(to: Dimension(length: 1, time: -1)))
    }

    func testDerivedUnitsPreservePhysicalDimensions() throws {
        let evaluation = engine.evaluate("2 N * 3 m\n6 J")
        let calculated = try successfulQuantity(evaluation.lines[0])
        let declared = try successfulQuantity(evaluation.lines[1])
        XCTAssertEqual(calculated.value, declared.value)
        XCTAssertTrue(calculated.dimension.isEquivalent(to: declared.dimension))
    }

    func testBareRadicalLeavesASpacedUnitOutsideTheRoot() throws {
        let evaluation = engine.evaluate("√2 m\n√(2) m\n√4 m²\n√(4 m²)\n√2^2")
        let bare = try successfulQuantity(evaluation.lines[0])
        let explicit = try successfulQuantity(evaluation.lines[1])
        XCTAssertTrue(bare.dimension.isEquivalent(to: .length), bare.dimension.formatted)
        XCTAssertEqual(bare.value, explicit.value)
        let area = try successfulQuantity(evaluation.lines[2])
        XCTAssertEqual(area.value, 2)
        XCTAssertTrue(area.dimension.isEquivalent(to: Dimension(length: 2)))
        let side = try successfulQuantity(evaluation.lines[3])
        XCTAssertEqual(side.value, 2)
        XCTAssertTrue(side.dimension.isEquivalent(to: .length))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[4]).value, 2)
    }

    func testRadicalAndDegreeSignsEndAnIdentifier() throws {
        let evaluation = engine.evaluate("a√2\na = 3\nsin(θ°)\nθ = 30\nsin(30°)\n2π√3\nx√2 = 3")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 3 * 2.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 0.5, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[4]).value, 0.5, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[5]).value, 2 * .pi * 3.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(evaluation.lines[6].kind, .equation)
        XCTAssertFalse(ExpressionParser.isIdentifier("x√2"))
        XCTAssertFalse(ExpressionParser.isIdentifier("θ°"))
        XCTAssertTrue(ExpressionParser.isIdentifier("θ_2"))
    }

    func testSquareRootTransformsTheDimension() throws {
        let evaluation = engine.evaluate("sqrt(9 m²)")
        let quantity = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(quantity.value, 3)
        XCTAssertTrue(quantity.dimension.isEquivalent(to: .length))
    }

    func testTrigonometricFunctionUsesDimensionlessArgument() throws {
        let evaluation = engine.evaluate("sin(pi/2)\nsin(1 m)")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 1, accuracy: 1e-12)
        assertError(evaluation.lines[1])
    }

    func testTrigonometryIsExactAtQuarterTurns() throws {
        let evaluation = engine.evaluate("""
        sin(pi)\ncos(90 deg)\nsin(180 deg)\nsin(pi/2)\nsin(3 pi/2)\ncos(270 deg)\nsin(-90 deg)
        cos(-pi)\ntan(pi)\ntan(-180 deg)\nsin(2*pi*f*t)\ncos(4 pi)\nf = 50 Hz\nt = 0,01 s
        """)
        let expected: [Double] = [0, 0, 0, 1, -1, 0, -1, -1, 0, 0, 0, 1]
        for (line, value) in zip(evaluation.lines, expected) {
            XCTAssertEqual(try successfulQuantity(line).value, value, line.source)
        }
    }

    func testQuarterTurnSnapToleranceDoesNotGrowWithTheTurnCount() throws {
        let evaluation = engine.evaluate("sin(1570796326.7948966 + 0,0001)\nsin(1570796326.7948966)\ncos(1e8 pi)\nsin(-pi)")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 1e-4, accuracy: 1e-6)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 0, accuracy: 1e-8)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 1)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 0)
    }

    func testTangentIsUndefinedAtOddQuarterTurns() {
        for line in engine.evaluate("tan(90 deg)\ntan(-pi/2)\ntan(270 deg)\ntan(5 pi/2)").lines {
            XCTAssertEqual(line.message, "La tangente n’est pas définie pour cet angle.", line.source)
        }
    }

    func testAnglesAwayFromQuarterTurnsKeepTheirResults() throws {
        let evaluation = engine.evaluate("sin(1e-13)\nsin(1e-20)\nsin(1e20)\nsin(30 deg)\ncos(3,14159)\ntan(45 deg)")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, Foundation.sin(1e-13))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 1e-20)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, Foundation.sin(1e20))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 0.5, accuracy: 1e-15)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[4]).value, Foundation.cos(3.14159))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[5]).value, 1, accuracy: 1e-15)
    }

    func testEquationsAgainstZeroAbsorbOnlyRoundingResidues() {
        let evaluation = engine.evaluate("""
        0,1 + 0,2 - 0,3 == 0\ncos(90 deg) == 0\nsin(pi) == 0\nFx == 0 N\nFx = F*cos(60 deg) - F*sin(30 deg)
        F = 10 N\n(0,1 + 0,2 - 0,3)^2 == 0\n1 m - 0,9 m - 0,1 m == 0 m
        1e6 - 1e6 + 1e-5 == 0\n1e6 m - 1e6 m + 1e-5 m == 0 m\nsin(3,14159) == 0\n0 == 1e-30\n1 == 1 + 1e-9
        """)
        for line in evaluation.lines.prefix(8) where line.kind == .equation {
            XCTAssertEqual(line.status, .success, "\(line.source) : \(line.message ?? "")")
        }
        for line in evaluation.lines.dropFirst(8) {
            XCTAssertEqual(line.status, .error, line.source)
        }
    }

    func testEquationTolerancePropagatesThroughUnitsFunctionsAndDeclarations() {
        let verified = ["36 km/h == 10 m/s", "sqrt(2)^2 == 2", "exp(ln(5)) == 5", "1/3 + 1/3 + 1/3 - 1 == 0",
                        "sin(45 deg)^2 + cos(45 deg)^2 == 1", "sqrt(0,1 + 0,2 - 0,3) == 0",
                        "F1 + F2 + F3 == 0 N\nF1 = 3,3 N\nF2 = -1,1 N\nF3 = -2,2 N",
                        "q*E == m*a\nq = e\nE = 1000 V/m\nm = m_e\na = q*E/m"]
        let refuted = ["sin(30 deg) == 0,5001", "2 == 2,000000001", "x - 1 == 0\nx = 1,0000001",
                       "cos(89 deg) == 0", "1e6 m - 1e6 m + 1 mm == 0 m"]
        for source in verified {
            XCTAssertEqual(engine.evaluate(source).lines[0].status, .success, source)
        }
        for source in refuted {
            XCTAssertEqual(engine.evaluate(source).lines[0].status, .error, source)
        }
    }

    func testExponentialWrittenWithElementaryChargeExplainsExp() {
        let evaluation = engine.evaluate("u = 12 V * e^(-t/tau)\nt = 2 s\ntau = 5 s\ne^0,5\ne^x\nx = 2\nu")
        for index in [0, 3, 4] {
            XCTAssertEqual(evaluation.lines[index].status, .error, evaluation.lines[index].source)
            XCTAssertTrue(evaluation.lines[index].message?.contains("exp(") == true, evaluation.lines[index].message ?? "")
        }
        XCTAssertEqual(evaluation.lines[6].message, "La déclaration de « u » (ligne 1) contient une erreur.")
    }

    func testIntegerPowersOfElementaryChargeRemainValid() throws {
        let evaluation = engine.evaluate("k_e*e^2/(1 nm)\ne²\ne^-1\n2e^2")
        let energy = try successfulQuantity(evaluation.lines[0])
        XCTAssertEqual(energy.value, 2.307e-19, accuracy: 1e-22)
        XCTAssertTrue(energy.dimension.isEquivalent(to: Dimension(length: 2, mass: 1, time: -2)))
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 1.602176634e-19 * 1.602176634e-19)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 1 / 1.602176634e-19, accuracy: 1e5)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 2 * 1.602176634e-19 * 1.602176634e-19)
    }

    func testDeclaredESupportsAnyExponent() throws {
        let evaluation = engine.evaluate("e = 3\ne^(0,5)\neuler^(-1)\nexp(-1)")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 3.0.squareRoot(), accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, Foundation.exp(-1), accuracy: 1e-15)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, Foundation.exp(-1))
    }

    func testIncompatibleAdditionReportsDimensionalError() {
        let evaluation = engine.evaluate("2 m + 3 s\nx = 2 kg + 1 m\nx")
        for line in evaluation.lines {
            assertError(line)
        }
    }

    func testDimensionedExponentsAreRejected() {
        assertError(engine.evaluate("(2 m)^(3 s)").lines[0])
    }

    func testEquationsCheckHomogeneity() {
        let evaluation = engine.evaluate("2 N = 2 kg*m/s²\n2 m == 2 s")
        XCTAssertEqual(evaluation.lines[0].kind, .equation)
        XCTAssertEqual(evaluation.lines[0].status, .success)
        XCTAssertNotNil(evaluation.lines[0].dimensionMessage)
        assertError(evaluation.lines[1])
    }

    func testEquationComparisonRetainsRelativePrecisionForSmallQuantities() {
        let evaluation = engine.evaluate("1e-20 J == 2e-20 J\n1e-20 J == 1e-20 J")
        assertError(evaluation.lines[0])
        XCTAssertEqual(evaluation.lines[1].status, .success)
    }

    func testEquationComparisonAllowsOrdinaryFloatingPointRounding() {
        let evaluation = engine.evaluate("0,1 + 0,2 == 0,3")
        XCTAssertEqual(evaluation.lines[0].status, .success)
    }

    func testUnitSuffixesDisambiguateGramAndHourFromConstants() throws {
        let evaluation = engine.evaluate("2 g\ng\n2 h\nh")
        let mass = try successfulQuantity(evaluation.lines[0])
        let gravity = try successfulQuantity(evaluation.lines[1])
        let duration = try successfulQuantity(evaluation.lines[2])
        let planck = try successfulQuantity(evaluation.lines[3])
        XCTAssertEqual(mass.value, 0.002)
        XCTAssertTrue(mass.dimension.isEquivalent(to: .mass))
        XCTAssertEqual(gravity.value, 9.80665)
        XCTAssertTrue(gravity.dimension.isEquivalent(to: Dimension(length: 1, time: -2)))
        XCTAssertEqual(duration.value, 7_200)
        XCTAssertTrue(duration.dimension.isEquivalent(to: .time))
        XCTAssertEqual(planck.value, 6.62607015e-34)
        XCTAssertTrue(planck.dimension.isEquivalent(to: Dimension(length: 2, mass: 1, time: -1)))
    }

    func testCyclesReportErrorsWithoutBlockingOtherLines() throws {
        let evaluation = engine.evaluate("a = b+1\nb = a+1\na\n2+2")
        for line in evaluation.lines.prefix(3) {
            assertError(line)
        }
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 4)
    }

    func testDependentLinesNameTheFailingDeclarationInsteadOfRepeatingItsError() throws {
        let evaluation = engine.evaluate("y = x*2\nx = 2 +\nz = y + 1\nw = 2*v\nv = (3\nu = q*2\nq = 2 m + 1 s\nx")
        let message = try XCTUnwrap(evaluation.lines[0].message)
        XCTAssertFalse(message.contains("colonne 4"), message)
        XCTAssertEqual(message, "La déclaration de « x » (ligne 2) contient une erreur.")
        XCTAssertEqual(evaluation.lines[1].message,
                       "Il manque un nombre, une variable ou une expression après l’opérateur. (colonne 4)")
        // Only the declaration at fault is named, however long the chain.
        XCTAssertEqual(evaluation.lines[2].message, message)
        XCTAssertEqual(evaluation.lines[3].message, "La déclaration de « v » (ligne 5) contient une erreur.")
        XCTAssertEqual(evaluation.lines[5].message, "La déclaration de « q » (ligne 7) contient une erreur.")
        XCTAssertTrue(evaluation.lines[6].message?.hasPrefix("Addition ou soustraction non homogène") == true)
        XCTAssertEqual(evaluation.lines[7].message, message)
    }

    func testCyclesAndDuplicatesKeepTheirOwnMessagesOnDependentLines() {
        let evaluation = engine.evaluate("x = a\na = b\nb = a\ny = d\nd = 1\nd = 2\nmissing*2")
        XCTAssertEqual(evaluation.lines[0].message, "Dépendance circulaire : a → b → a.")
        XCTAssertEqual(evaluation.lines[1].message, "Dépendance circulaire : a → b → a.")
        XCTAssertEqual(evaluation.lines[2].message, "Dépendance circulaire : b → a → b.")
        XCTAssertEqual(evaluation.lines[3].message,
                       "« d » est déclaré plusieurs fois (lignes 5, 6). Conservez une seule déclaration.")
        XCTAssertTrue(evaluation.lines[6].message?.hasPrefix("« missing » n’est ni une variable déclarée") == true)
    }

    func testOverLimitSheetKeepsOneResultPerLineAndShowsItsError() {
        let source = "# Titre\n\n" + (0..<501).map { "x\($0) = \($0)" }.joined(separator: "\n") + "\nx0"
        let evaluation = engine.evaluate(source)
        XCTAssertEqual(evaluation.lines.map(\.source), source.components(separatedBy: "\n"))
        XCTAssertEqual(evaluation.lines.map(\.id), Array(0..<504))
        XCTAssertEqual(evaluation.lines.first?.source, "# Titre")
        XCTAssertEqual(evaluation.lines[0].kind, .comment)
        XCTAssertEqual(evaluation.lines[1].kind, .empty)
        XCTAssertEqual(evaluation.lines[2].kind, .definition)
        XCTAssertEqual(evaluation.lines[2].status, .error)
        XCTAssertEqual(evaluation.lines[2].message, "Feuille trop longue (500 lignes et 100 000 caractères maximum).")
        XCTAssertEqual(evaluation.lines.last?.kind, .expression)
        XCTAssertEqual(evaluation.lines.filter { $0.status == .error }.count, 1)
        XCTAssertTrue(evaluation.lines.allSatisfy { $0.quantity == nil })
        // Without any formula, the first non-blank line carries the error and stays selectable.
        let comments = engine.evaluate("\n" + Array(repeating: "# note", count: 600).joined(separator: "\n"))
        XCTAssertEqual(comments.lines[1].status, .error)
        XCTAssertEqual(comments.lines[1].kind, .expression)
    }

    func testDuplicateDeclarationsAreRejected() {
        let evaluation = engine.evaluate("a = 2\na = 3\na")
        for line in evaluation.lines {
            assertError(line)
        }
    }

    func testUnknownSymbolsProduceActionableError() {
        let line = engine.evaluate("missing+2").lines[0]
        assertError(line)
        XCTAssertTrue(line.message?.contains("missing") == true)
    }

    func testNumericalAndSyntaxErrorsDoNotProduceNonFiniteResults() {
        for source in ["1/0", "sqrt(-1)", "ln(0)", "2 +", "(2+3", "sin()"] {
            let line = engine.evaluate(source).lines[0]
            assertError(line)
            XCTAssertNil(line.quantity, source)
        }
    }

    func testAdjacentNumbersAndRepeatedDecimalSeparatorsAreRejected() {
        for source in ["1 000 m", "2 3", "1,2,3", "2.3.4"] {
            let line = engine.evaluate(source).lines[0]
            assertError(line)
            XCTAssertNil(line.quantity, source)
        }
    }

    func testDimensionalOverflowIsRejectedEvenWithFiniteNumericalValue() throws {
        var declarations = ["d0 = 1 m"]
        for index in 1...78 {
            declarations.append("d\(index) = d\(index - 1)^10000")
        }
        let evaluation = engine.evaluate(declarations.joined(separator: "\n"))
        let finite = try successfulQuantity(evaluation.lines[77])
        XCTAssertEqual(finite.value, 1)
        XCTAssertTrue(finite.dimension.length.isFinite)
        assertError(evaluation.lines[78])
        XCTAssertNil(evaluation.lines[78].quantity)
    }

    func testUnicodeConstantAliasesAndSquareRootNotation() throws {
        let evaluation = engine.evaluate("ε₀\nsqrt(2)\n√2")
        let permittivity = try XCTUnwrap(ConstantCatalog.lookup("epsilon_0")).quantity
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, permittivity.value)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value,
                       try successfulQuantity(evaluation.lines[1]).value)
    }

    func testCommentsAndBlankLinesPreserveSourceIndices() throws {
        let evaluation = engine.evaluate("# Mouvement\n\na = 2 // accélération\na*3 # résultat")
        XCTAssertEqual(evaluation.lines.count, 4)
        XCTAssertEqual(evaluation.lines.map(\.id), [0, 1, 2, 3])
        XCTAssertEqual(evaluation.lines[0].kind, .comment)
        XCTAssertEqual(evaluation.lines[1].kind, .empty)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[3]).value, 6)
    }

    private func successfulQuantity(
        _ line: EvaluatedLine,
        file: StaticString = #filePath,
        line sourceLine: UInt = #line
    ) throws -> Quantity {
        XCTAssertEqual(line.status, .success, line.message ?? line.source, file: file, line: sourceLine)
        return try XCTUnwrap(line.quantity, line.message ?? line.source, file: file, line: sourceLine)
    }

    private func assertError(
        _ line: EvaluatedLine,
        file: StaticString = #filePath,
        line sourceLine: UInt = #line
    ) {
        XCTAssertEqual(line.status, .error, line.source, file: file, line: sourceLine)
        XCTAssertFalse(line.message?.isEmpty ?? true, file: file, line: sourceLine)
    }
}
