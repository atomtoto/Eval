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

    func testNestedForwardReferencesAreIndependentOfDeclarationOrder() throws {
        let evaluation = engine.evaluate("x\nx = y*2\ny = z+1\nz = 3")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 8)
        XCTAssertEqual(evaluation.variables.count, 3)
    }

    func testDecimalCommaAndScientificNotation() throws {
        let evaluation = engine.evaluate("7,2\n2,5e3 mm\n1e-3 m")
        XCTAssertEqual(try successfulQuantity(evaluation.lines[0]).value, 7.2, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[1]).value, 2.5, accuracy: 1e-12)
        XCTAssertEqual(try successfulQuantity(evaluation.lines[2]).value, 0.001, accuracy: 1e-12)
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
