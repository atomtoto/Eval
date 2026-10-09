import XCTest
@testable import EvalCore

final class LineSyntaxTests: XCTestCase {
    func testCommentOnlyLinesHaveNoBody() {
        for source in ["# Titre", "  // note = 2 -> km", ""] {
            let line = LineSyntax(source)
            XCTAssertTrue(line.content.trimmingCharacters(in: .whitespaces).isEmpty, source)
            XCTAssertTrue(line.body.trimmingCharacters(in: .whitespaces).isEmpty, source)
            XCTAssertNil(line.conversion, source)
            XCTAssertNil(line.definitionName, source)
            XCTAssertFalse(line.isComparison, source)
        }
        XCTAssertEqual(LineSyntax("# Titre").comment, "# Titre")
        XCTAssertEqual(LineSyntax("  // note = 2 -> km").comment, "// note = 2 -> km")
        XCTAssertNil(LineSyntax("").comment)
    }

    func testArrowInsideACommentIsIgnored() {
        let line = LineSyntax("x = 3 # 3 -> km")
        XCTAssertEqual(line.content, "x = 3 ")
        XCTAssertEqual(line.body, "x = 3 ")
        XCTAssertNil(line.conversion)
        XCTAssertNil(line.conversionRange)
        XCTAssertEqual(line.arrowCount, 0)
        XCTAssertEqual(line.comment, "# 3 -> km")
        XCTAssertEqual(line.definitionName, "x")
    }

    func testDeclarationWithConversionAndComment() throws {
        let source = "v = 72 km/h -> m/s // vitesse"
        let line = LineSyntax(source)
        XCTAssertEqual(line.content, "v = 72 km/h -> m/s ")
        XCTAssertEqual(line.body, "v = 72 km/h ")
        XCTAssertEqual(line.conversion, "m/s")
        XCTAssertEqual(source[try XCTUnwrap(line.conversionRange)], "m/s")
        XCTAssertEqual(source[try XCTUnwrap(line.arrowRange)], "->")
        XCTAssertEqual(line.arrowCount, 1)
        XCTAssertEqual(line.comment, "// vitesse")
        XCTAssertEqual(line.definitionName, "v")
        XCTAssertFalse(line.isComparison)
        XCTAssertEqual(source[try XCTUnwrap(line.separatorRange)], "=")
    }

    func testSeveralArrowsAreReported() {
        let line = LineSyntax("a -> b -> c")
        XCTAssertEqual(line.arrowCount, 2)
        XCTAssertEqual(line.body, "a ")
        XCTAssertEqual(line.conversion, "b -> c")
        XCTAssertEqual(LineSyntax("a → b → c # d -> e").arrowCount, 2)
    }

    func testComparisonWithTypographicArrow() throws {
        let source = "F == m*a → kN"
        let line = LineSyntax(source)
        XCTAssertTrue(line.isComparison)
        XCTAssertNil(line.definitionName)
        XCTAssertEqual(line.body, "F == m*a ")
        XCTAssertEqual(line.conversion, "kN")
        XCTAssertEqual(source[try XCTUnwrap(line.separatorRange)], "==")
        XCTAssertEqual(line.separatorCount, 1)
    }

    func testMembersFollowTheEngineRules() {
        XCTAssertEqual(LineSyntax("  α_1 = 2 = 3").definitionName, "α_1")
        XCTAssertEqual(LineSyntax("  α_1 = 2 = 3").separatorCount, 2)
        XCTAssertNil(LineSyntax("2 = x").definitionName)
        XCTAssertEqual(LineSyntax("a === b").separatorCount, 2)
        XCTAssertTrue(LineSyntax("a === b").isComparison)
        XCTAssertNil(LineSyntax("a -> b = 3").separatorRange)
        // `x =` before a comment is a request: it leaves no separator.
        XCTAssertEqual(LineSyntax("x = # y = 2").separatorCount, 0)
        XCTAssertEqual(LineSyntax("x = 1 # y = 2").separatorCount, 1)
        // `x =` is a query of x, not a declaration with a missing value.
        XCTAssertNil(LineSyntax("x =").definitionName)
        XCTAssertTrue(LineSyntax("x =").requestsResult)
    }

    func testComparisonOperatorsAreNotResultRequests() {
        for source in ["a !=", "a <=", "a >=", "a != # c", "a<=", "a >= b <="] {
            let line = LineSyntax(source)
            XCTAssertFalse(line.requestsResult, source)
            XCTAssertNil(line.resultRequestRange, source)
        }
        for source in ["a <= b =", "a >= b = # c", "a ="] {
            XCTAssertTrue(LineSyntax(source).requestsResult, source)
        }
        for source in ["a = 1\na !=", "a = 1\na <=", "a = 1\na >="] {
            let line = NotebookEngine.evaluate(source).lines[1]
            XCTAssertEqual(line.status, .error, source)
            XCTAssertFalse(line.requestsValue, source)
        }
    }

    func testEmptyConversionKeepsItsPosition() throws {
        let source = "x = 3 ->   # c"
        let line = LineSyntax(source)
        XCTAssertEqual(line.conversion, "")
        let range = try XCTUnwrap(line.conversionRange)
        XCTAssertTrue(range.isEmpty)
        XCTAssertEqual(range.lowerBound, try XCTUnwrap(line.arrowRange).upperBound)
    }

    func testReplacingConversionAddsReplacesAndRemovesWhileKeepingTheComment() {
        XCTAssertEqual(LineSyntax("v = 72 km/h # vitesse").replacingConversion("m/s"),
                       "v = 72 km/h → m/s # vitesse")
        XCTAssertEqual(LineSyntax("v = 72 km/h").replacingConversion("m/s"), "v = 72 km/h → m/s")
        XCTAssertEqual(LineSyntax("v = 72 km/h// vitesse").replacingConversion("m/s"),
                       "v = 72 km/h → m/s // vitesse")
        XCTAssertEqual(LineSyntax("v = 72 km/h  ->  m/s  // vitesse").replacingConversion(" mm/s "),
                       "v = 72 km/h  ->  mm/s  // vitesse")
        XCTAssertEqual(LineSyntax("v = 72 km/h -> m/s // vitesse").replacingConversion(nil),
                       "v = 72 km/h // vitesse")
        XCTAssertEqual(LineSyntax("v = 72 km/h → m/s").replacingConversion(""), "v = 72 km/h")
        XCTAssertEqual(LineSyntax("a -> b -> c").replacingConversion("d"), "a -> d")
        XCTAssertEqual(LineSyntax("x = 3 -># c").replacingConversion("km"), "x = 3 -> km # c")
        XCTAssertEqual(LineSyntax("x = 3 ->").replacingConversion("km"), "x = 3 -> km")
        XCTAssertEqual(LineSyntax("x = 3 # c").replacingConversion(nil), "x = 3 # c")
        XCTAssertEqual(LineSyntax("v = 6 m/ -> s// c").replacingConversion(nil), "v = 6 m/ // c")
        XCTAssertEqual(LineSyntax("v = 6 m/ → s//c").replacingConversion(""), "v = 6 m/ //c")
        XCTAssertEqual(LineSyntax("x = 3 -> m//c").replacingConversion(nil), "x = 3//c")
        // A comment or a blank line has nothing to convert.
        XCTAssertEqual(LineSyntax("# c").replacingConversion("km"), "# c")
        XCTAssertEqual(LineSyntax("").replacingConversion("km"), "")
    }

    func testReplacingBodyKeepsTheSpacingConversionAndComment() {
        XCTAssertEqual(LineSyntax("  E = m*c²  -> MeV  # énergie").replacingBody("E = (m) / (2)"),
                       "  E = (m) / (2)  -> MeV  # énergie")
        XCTAssertEqual(LineSyntax("x = 3").replacingBody("x = 4"), "x = 4")
        XCTAssertEqual(LineSyntax("# c").replacingBody("x = 4"), "x = 4 # c")
        XCTAssertEqual(LineSyntax("-> km").replacingBody("x"), "x -> km")
    }

    func testArrowsAreHandledByTheEngineAndTheRenderers() {
        let evaluation = NotebookEngine.evaluate("v = 72 km/h -> m/s\nx = 3 → km\ny = 3 # 3 -> km")
        XCTAssertEqual(evaluation.lines[0].status, .success)
        XCTAssertEqual(evaluation.lines[0].displayUnit?.symbol, "m/s")
        XCTAssertEqual(evaluation.lines[0].kind, .definition)
        XCTAssertEqual(evaluation.lines[1].message,
                       "Conversion impossible : le résultat a pour dimension 1, alors que km a pour dimension m.")
        XCTAssertEqual(evaluation.lines[2].status, .success)
        XCTAssertNotNil(MathNotation.formula("v = 72 km/h -> m/s"))
        XCTAssertNotNil(AdjustableVariable(source: "v = 72 km/h -> m/s"))
        XCTAssertNotNil(MathNotation.formula("x = 3 # 3 -> km"))
        XCTAssertNotNil(AdjustableVariable(source: "x = 3 # 3 -> km"))
    }
}
