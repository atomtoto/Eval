import XCTest
@testable import EvalCore

final class MathFormulaTests: XCTestCase {
    func testFractionGroupsTheWholeNumeratorAndDenominator() {
        XCTAssertEqual(MathNotation.formula("m*a/(b+c)"), .fraction(
            .row([.atom("m"), .atom(" · "), .atom("a")]),
            .row([.atom("b"), .atom(" + "), .atom("c")])
        ))
        XCTAssertEqual(MathNotation.formula("(a+b)/(c-d)"), .fraction(
            .row([.atom("a"), .atom(" + "), .atom("b")]),
            .row([.atom("c"), .atom(" − "), .atom("d")])
        ))
    }

    func testDivisionAndMultiplicationRetainTheirGrouping() {
        XCTAssertEqual(MathNotation.formula("a/b*c"), .row([
            .fraction(.atom("a"), .atom("b")), .atom(" · "), .atom("c")
        ]))
        XCTAssertEqual(MathNotation.formula("a/(b/c)"), .fraction(
            .atom("a"), .fraction(.atom("b"), .atom("c"))
        ))
        XCTAssertEqual(MathNotation.formula("(a+b)*c"), .row([
            .parentheses(.row([.atom("a"), .atom(" + "), .atom("b")])),
            .atom(" · "), .atom("c")
        ]))
    }

    func testSubtractionAndUnaryMinusKeepSumGrouping() {
        let sum = MathFormula.row([.atom("b"), .atom(" + "), .atom("c")])
        XCTAssertEqual(MathNotation.formula("a-(b+c)"), .row([
            .atom("a"), .atom(" − "), .parentheses(sum)
        ]))
        XCTAssertEqual(MathNotation.formula("-(b+c)"), .row([
            .atom("−"), .parentheses(sum)
        ]))
        XCTAssertEqual(MathNotation.formula("-(-b)"), .row([
            .atom("−"), .parentheses(.row([.atom("−"), .atom("b")]))
        ]))
    }

    func testNegativeRightOperandsKeepTheirParentheses() {
        let negated = MathFormula.parentheses(.row([.atom("−"), .atom("b")]))
        XCTAssertEqual(MathNotation.formula("a-(-b)"), .row([.atom("a"), .atom(" − "), negated]))
        XCTAssertEqual(MathNotation.formula("a*-b"), .row([.atom("a"), .atom(" · "), negated]))
        XCTAssertEqual(MathNotation.formula("a·(−b)"), .row([.atom("a"), .atom(" · "), negated]))
        XCTAssertEqual(MathNotation.formula("a + -b"), .row([.atom("a"), .atom(" + "), negated]))
        // A leading sign and a fraction bar need no extra grouping.
        XCTAssertEqual(MathNotation.formula("-a*b"), .row([.atom("−"), .atom("a"), .atom(" · "), .atom("b")]))
        XCTAssertEqual(MathNotation.formula("a/-b"), .fraction(.atom("a"), .row([.atom("−"), .atom("b")])))
    }

    func testPowersKeepTheirBaseGroupingAndAssociativity() {
        XCTAssertEqual(MathNotation.formula("(a+b)^(c+d)"), .power(
            .parentheses(.row([.atom("a"), .atom(" + "), .atom("b")])),
            .row([.atom("c"), .atom(" + "), .atom("d")])
        ))
        XCTAssertEqual(MathNotation.formula("a^b^c"), .power(
            .atom("a"), .power(.atom("b"), .atom("c"))
        ))
        XCTAssertEqual(MathNotation.formula("(a^b)^c"), .power(
            .parentheses(.power(.atom("a"), .atom("b"))), .atom("c")
        ))
        XCTAssertEqual(MathNotation.formula("-2^2"), .row([
            .atom("−"), .power(.atom("2"), .atom("2"))
        ]))
        XCTAssertEqual(MathNotation.formula("(-2)^2"), .power(
            .parentheses(.row([.atom("−"), .atom("2")])), .atom("2")
        ))
    }

    func testEditorTemplatesDoNotKeepRedundantGrouping() {
        XCTAssertEqual(MathNotation.formula("(m*a) / (t)"), .fraction(
            .row([.atom("m"), .atom(" · "), .atom("a")]), .atom("t")
        ))
        XCTAssertEqual(MathNotation.formula("(v) ^ (2)"), .power(.atom("v"), .atom("2")))
        XCTAssertEqual(MathNotation.formula("sqrt((x+y))"), .radical(
            .row([.atom("x"), .atom(" + "), .atom("y")])
        ))
    }

    func testFunctionsAndUnicodeHaveMathematicalLayout() {
        XCTAssertEqual(MathNotation.formula("sqrt(a/b)"), .radical(.fraction(.atom("a"), .atom("b"))))
        XCTAssertEqual(MathNotation.formula("√(a/b)"), MathNotation.formula("sqrt(a/b)"))
        XCTAssertEqual(MathNotation.formula("v²"), .power(.atom("v"), .atom("2")))
        XCTAssertEqual(MathNotation.formula("sin(theta)"), .row([
            .atom("sin"), .parentheses(.atom("θ"))
        ]))
        XCTAssertEqual(MathNotation.formula("log10(x)"), .row([
            .atom("log₁₀"), .parentheses(.atom("x"))
        ]))
        XCTAssertEqual(MathNotation.formula("abs(a+b)"), .row([
            .atom("|"), .atom("a"), .atom(" + "), .atom("b"), .atom("|")
        ]))
    }

    func testScientificNumbersAndUnitsKeepTheirMeaning() {
        let scientific = MathFormula.row([
            .atom("1,25"), .atom(" × "), .power(.atom("10"), .atom("−3"))
        ])
        XCTAssertEqual(MathNotation.formula("1,25e-3 m"), .row([
            .atom("1,25"), .atom(" × "), .power(.atom("10"), .atom("−3")),
            .atom(" "), .atom("m")
        ]))
        XCTAssertEqual(MathNotation.formula("1.25e-3"), scientific)
        XCTAssertEqual(MathNotation.formula("(1,25e-3)^2"), .power(.parentheses(scientific), .atom("2")))
        XCTAssertEqual(MathNotation.formula("2 × 10³ m"), .row([
            .atom("2"), .atom(" · "), .power(.atom("10"), .atom("3")), .atom(" "), .atom("m")
        ]))
        XCTAssertEqual(MathNotation.formula("7,2 m/s²"), .row([
            .atom("7,2"), .atom(" "), .fraction(.atom("m"), .power(.atom("s"), .atom("2")))
        ]))
    }

    func testEnteredSpellingKeepsItsTrailingZeros() {
        XCTAssertEqual(MathNotation.formula("x = 8,0"), .row([.atom("x"), .atom(" = "), .atom("8,0")]))
        XCTAssertEqual(MathNotation.formula("a = 9,0 m/s²"), .row([
            .atom("a"), .atom(" = "), .atom("9,0"), .atom(" "),
            .fraction(.atom("m"), .power(.atom("s"), .atom("2")))
        ]))
        XCTAssertEqual(MathNotation.formula("1,0e3"), .row([
            .atom("1,0"), .atom(" × "), .power(.atom("10"), .atom("3"))
        ]))
        XCTAssertEqual(MathNotation.formula("8,00"), .atom("8,00"))
        XCTAssertEqual(MathNotation.formula("8"), .atom("8"))
    }

    func testEnDashIsAMinusSignInScientificExponents() {
        XCTAssertEqual(MathNotation.formula("2e–3 + 1"), .row([
            .atom("2"), .atom(" × "), .power(.atom("10"), .atom("−3")), .atom(" + "), .atom("1")
        ]))
    }

    func testBareRadicalKeepsASpacedUnitOutsideTheRoot() {
        XCTAssertEqual(MathNotation.formula("√2 m"), .row([.radical(.atom("2")), .atom(" "), .atom("m")]))
        XCTAssertEqual(MathNotation.formula("a√2"), .row([.atom("a"), .atom(" · "), .radical(.atom("2"))]))
        XCTAssertEqual(MathNotation.formula("√(4 m²)"), .radical(.row([
            .atom("4"), .atom(" "), .power(.atom("m"), .atom("2"))
        ])))
    }

    func testUnitAndVariableNamespacesRemainVisible() {
        XCTAssertEqual(MathNotation.formula("2m"), .row([.atom("2"), .atom(" · "), .atom("m")]))
        XCTAssertEqual(MathNotation.formula("2 m"), .row([.atom("2"), .atom(" "), .atom("m")]))
        XCTAssertEqual(MathNotation.formula("2 kg*m/s²"), .row([
            .atom("2"), .atom(" "), .fraction(
                .row([.atom("kg"), .atom(" · "), .atom("m")]), .power(.atom("s"), .atom("2"))
            )
        ]))
    }

    func testCompactUnitChainsDrawAsUnits() {
        XCTAssertEqual(MathNotation.formula("v = 72km/h"), .row([
            .atom("v"), .atom(" = "), .atom("72"), .atom(" "), .fraction(.atom("km"), .atom("h"))
        ]))
        XCTAssertEqual(MathNotation.formula("3g"), .row([.atom("3"), .atom(" · "), .atom("g")]))
    }

    func testDeclarationsEquationsAndInlineComments() {
        XCTAssertEqual(MathNotation.formula("F = m*a # force"), .row([
            .atom("F"), .atom(" = "), .atom("m"), .atom(" · "), .atom("a")
        ]))
        XCTAssertEqual(MathNotation.formula("2*a == b+c // comparaison"), .row([
            .atom("2"), .atom(" · "), .atom("a"), .atom(" = "),
            .atom("b"), .atom(" + "), .atom("c")
        ]))
        XCTAssertEqual(MathNotation.formula("sqrt = 2"), .row([.atom("sqrt"), .atom(" = "), .atom("2")]))
    }

    func testGreekAliasesDoNotAlterParserOrEvaluation() throws {
        XCTAssertEqual(MathNotation.formula("lambda = alpha*beta"), .row([
            .atom("λ"), .atom(" = "), .atom("α"), .atom(" · "), .atom("β")
        ]))
        XCTAssertEqual(MathNotation.formula("epsilon_0"), .atom("ε₀"))
        XCTAssertEqual(MathNotation.formula("lambdaRate"), .atom("lambdaRate"))
        let evaluation = NotebookEngine.evaluate("beta = 2\nlambda = beta+1\nlambda")
        XCTAssertEqual(try XCTUnwrap(evaluation.lines.last?.quantity).value, 3)
        XCTAssertEqual(evaluation.variables.map(\.name), ["beta", "lambda"])
    }

    func testIdentifierDigitsDoNotBecomeNumericSpellings() {
        XCTAssertEqual(MathNotation.formula("x2 + 3e2"), .row([
            .atom("x2"), .atom(" + "), .atom("3"), .atom(" × "), .power(.atom("10"), .atom("2"))
        ]))
        XCTAssertEqual(MathNotation.formula("ε₀ + 4²"), .row([
            .atom("ε₀"), .atom(" + "), .power(.atom("4"), .atom("2"))
        ]))
    }

    func testInvalidOrIncompleteSyntaxHasNoMisleadingPreview() {
        for source in ["", "  ", "# commentaire", "// commentaire", "a+", "(a+b", "sqrt()",
                       "a=", "=b", "a=b=c", "a===b", "1,2,3", "a@b", "2 3", "a\nb"] {
            XCTAssertNil(MathNotation.formula(source), source)
        }
        // Undefined variables and numerical errors still have a valid layout;
        // the evaluation layer is responsible for their separate diagnostics.
        XCTAssertNotNil(MathNotation.formula("unknown/0"))
    }

    func testComplexityBoundsReturnSafely() {
        XCTAssertNil(MathNotation.formula(String(repeating: "x", count: 2_001)))
        XCTAssertNil(MathNotation.formula(String(repeating: "(", count: 100) + "x" + String(repeating: ")", count: 100)))
        XCTAssertNil(MathNotation.formula(Array(repeating: "a", count: 300).joined(separator: "+")))
    }

    func testConversionArrowIsRendered() {
        XCTAssertEqual(MathNotation.formula("E = m*c² -> MeV"), .row([
            .atom("E"), .atom(" = "), .atom("m"), .atom(" · "), .power(.atom("c"), .atom("2")),
            .atom(" → "), .atom("MeV")
        ]))
        XCTAssertEqual(MathNotation.formula("v → km/h  # vitesse"), .row([
            .atom("v"), .atom(" → "), .fraction(.atom("km"), .atom("h"))
        ]))
        for source in ["v ->", "-> km", "v -> km -> m", "v -> 2 +"] {
            XCTAssertNil(MathNotation.formula(source), source)
        }
    }

    func testMultiArgumentFunctionRendersSemicolons() {
        XCTAssertEqual(MathNotation.formula("max(a; b)"), .row([
            .atom("max"), .parentheses(.row([.atom("a"), .atom(" ; "), .atom("b")]))
        ]))
        XCTAssertEqual(MathNotation.formula("log(8; 2)"), .row([
            .atom("log"), .parentheses(.row([.atom("8"), .atom(" ; "), .atom("2")]))
        ]))
        XCTAssertEqual(MathNotation.formula("atan2(y; x)"), .row([
            .atom("atan2"), .parentheses(.row([.atom("y"), .atom(" ; "), .atom("x")]))
        ]))
        XCTAssertNil(MathNotation.formula("max(a, b)"))
    }

    func testInverseFunctionsUseArcNamesAndRootsKeepTheirIndex() {
        XCTAssertEqual(MathNotation.formula("asin(x)"), .row([.atom("arcsin"), .parentheses(.atom("x"))]))
        XCTAssertEqual(MathNotation.formula("arccos(x)"), .row([.atom("arccos"), .parentheses(.atom("x"))]))
        XCTAssertEqual(MathNotation.formula("atan(x)"), .row([.atom("arctan"), .parentheses(.atom("x"))]))
        XCTAssertEqual(MathNotation.formula("cbrt(x)"), .root(index: .atom("3"), radicand: .atom("x")))
        XCTAssertEqual(MathNotation.formula("root(x; 4)"), .root(index: .atom("4"), radicand: .atom("x")))
    }

    func testFactorialAndPercentRender() {
        XCTAssertEqual(MathNotation.formula("n!"), .row([.atom("n"), .atom("!")]))
        XCTAssertEqual(MathNotation.formula("(a+b)!"), .row([
            .parentheses(.row([.atom("a"), .atom(" + "), .atom("b")])), .atom("!")
        ]))
        XCTAssertEqual(MathNotation.formula("35 %"), .row([.atom("35"), .atom(" "), .atom("%")]))
    }
}
