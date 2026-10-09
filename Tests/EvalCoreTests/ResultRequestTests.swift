import Foundation
import XCTest
@testable import EvalCore

/// The trailing `=` that asks a line to show its value (`E =`, `v → km/h =`).
final class ResultRequestTests: XCTestCase {
    // MARK: LineSyntax

    func testTrailingEqualsIsAResultRequest() throws {
        let line = LineSyntax("E = ")
        XCTAssertTrue(line.requestsResult)
        XCTAssertTrue(line.requestsValue)
        let range = try XCTUnwrap(line.resultRequestRange)
        XCTAssertEqual(String(line.source[range]), "=")
        XCTAssertEqual(line.body, "E ")
        XCTAssertNil(line.definitionName)
        XCTAssertNil(line.separatorRange)
        XCTAssertEqual(line.separatorCount, 0)
        XCTAssertNil(line.conversion)
    }

    func testRequestIsTheLastCharacterBeforeTheComment() {
        let line = LineSyntax("m * v =   # quantité de mouvement")
        XCTAssertTrue(line.requestsResult)
        XCTAssertEqual(line.body, "m * v ")
        XCTAssertEqual(line.comment, "# quantité de mouvement")
        XCTAssertTrue(LineSyntax("m * v = // note").requestsResult)
        // An `=` that belongs to the comment is not a request.
        XCTAssertFalse(LineSyntax("m * v # E =").requestsResult)
    }

    func testDoubleEqualsAndBareEqualsAreNotRequests() {
        for source in ["F == m * a", "F ==", "F==", "=", "  =  ", "a ===", "x = 2", "", "# a ="] {
            let line = LineSyntax(source)
            XCTAssertFalse(line.requestsResult, source)
            XCTAssertNil(line.resultRequestRange, source)
            XCTAssertFalse(line.requestsValue, source)
        }
    }

    func testDeclarationWithARequestStaysADeclaration() {
        let line = LineSyntax("E = 0,5 * m * v² =")
        XCTAssertTrue(line.requestsResult)
        XCTAssertEqual(line.definitionName, "E")
        XCTAssertEqual(line.separatorCount, 1)
        XCTAssertEqual(line.body, "E = 0,5 * m * v² ")
        XCTAssertFalse(line.isComparison)
    }

    func testRequestAfterAnEqualityIsKeptSyntactically() {
        let line = LineSyntax("F == m * a =")
        XCTAssertTrue(line.requestsResult)
        XCTAssertTrue(line.isComparison)
        XCTAssertEqual(line.separatorCount, 1)
        XCTAssertEqual(line.body, "F == m * a ")
    }

    func testConversionFormsWithARequest() throws {
        let after = LineSyntax("v → km/h =")
        XCTAssertTrue(after.requestsResult)
        XCTAssertEqual(after.body, "v ")
        XCTAssertEqual(after.conversion, "km/h")
        XCTAssertEqual(after.arrowCount, 1)

        let before = LineSyntax("v = → km/h")
        XCTAssertTrue(before.requestsResult)
        XCTAssertEqual(before.body, "v ")
        XCTAssertEqual(before.conversion, "km/h")
        XCTAssertEqual(before.separatorCount, 0)
        XCTAssertNil(before.definitionName)
        XCTAssertEqual(try XCTUnwrap(before.resultRequestRange).lowerBound, before.source.index(before.source.startIndex, offsetBy: 2))

        let ascii = LineSyntax("E -> kWh = # note")
        XCTAssertTrue(ascii.requestsResult)
        XCTAssertEqual(ascii.conversion, "kWh")
        XCTAssertEqual(ascii.comment, "# note")

        let declaration = LineSyntax("E = P * 2 h → kWh =")
        XCTAssertEqual(declaration.definitionName, "E")
        XCTAssertEqual(declaration.conversion, "kWh")
    }

    func testRequestsValueCombinesRequestArrowAndUnknown() {
        XCTAssertTrue(LineSyntax("a =").requestsValue)
        XCTAssertTrue(LineSyntax("v → km/h").requestsValue)
        XCTAssertTrue(LineSyntax("v = ? m/s").requestsValue)
        XCTAssertFalse(LineSyntax("v = 5 m/s").requestsValue)
        XCTAssertFalse(LineSyntax("m * v").requestsValue)
        XCTAssertFalse(LineSyntax("v → km/h").requestsResult)
    }

    func testReplacingTheConversionWritesTheArrowBeforeTheRequest() {
        XCTAssertEqual(LineSyntax("v =").replacingConversion("km/h"), "v → km/h =")
        XCTAssertEqual(LineSyntax("v=").replacingConversion("km/h"), "v → km/h =")
        XCTAssertEqual(LineSyntax("E = 0,5 * m * v² = # énergie").replacingConversion("kWh"),
                       "E = 0,5 * m * v² → kWh = # énergie")
        XCTAssertEqual(LineSyntax("v → m/s =").replacingConversion("km/h"), "v → km/h =")
        XCTAssertEqual(LineSyntax("v = → m/s").replacingConversion("km/h"), "v = → km/h")
        XCTAssertEqual(LineSyntax("v → =").replacingConversion("km/h"), "v → km/h =")
    }

    func testRemovingTheConversionKeepsTheRequest() {
        XCTAssertEqual(LineSyntax("v → km/h =").replacingConversion(nil), "v =")
        XCTAssertEqual(LineSyntax("v → km/h = # c").replacingConversion(""), "v = # c")
        XCTAssertEqual(LineSyntax("v = → km/h").replacingConversion(nil), "v =")
        XCTAssertEqual(LineSyntax("v = → km/h # c").replacingConversion(nil), "v = # c")
        XCTAssertEqual(LineSyntax("v → km/h").replacingConversion(nil), "v")
    }

    func testAddingAResultRequest() {
        XCTAssertEqual(LineSyntax("E = 0,5 * m * v²").addingResultRequest(), "E = 0,5 * m * v² =")
        XCTAssertEqual(LineSyntax("E → kWh").addingResultRequest(), "E → kWh =")
        XCTAssertEqual(LineSyntax("m * v   # note").addingResultRequest(), "m * v =   # note")
        XCTAssertEqual(LineSyntax("a =").addingResultRequest(), "a =")
        XCTAssertEqual(LineSyntax("# note").addingResultRequest(), "# note")
        XCTAssertEqual(LineSyntax("").addingResultRequest(), "")
    }

    func testReplacingTheBodyKeepsTheRequest() {
        XCTAssertEqual(LineSyntax("E = 1 =").replacingBody("E = 2"), "E = 2 =")
        XCTAssertEqual(LineSyntax("v → km/h =").replacingBody("w"), "w → km/h =")
    }

    // MARK: Engine

    func testQueryDoesNotDeclareTheName() throws {
        let evaluation = NotebookEngine.evaluate("a = 5\na =\nb = a * 2\nb =")
        XCTAssertTrue(evaluation.lines.allSatisfy { $0.status == .success }, evaluation.lines.compactMap(\.message).joined())
        XCTAssertEqual(evaluation.lines.map(\.kind), [.definition, .expression, .definition, .expression])
        XCTAssertEqual(evaluation.lines[1].quantity?.value, 5)
        XCTAssertEqual(evaluation.lines[3].quantity?.value, 10)
        XCTAssertEqual(evaluation.variables.map(\.name), ["a", "b"])
        XCTAssertEqual(evaluation.lines.map(\.requestsValue), [false, true, false, true])
    }

    func testQueryOfAnUndeclaredNameReportsIt() {
        let line = NotebookEngine.evaluate("zzz =").lines[0]
        XCTAssertEqual(line.status, .error)
        XCTAssertEqual(line.kind, .expression)
        XCTAssertTrue(line.requestsValue)
    }

    func testDeclarationWithARequestDefinesAndShows() throws {
        let evaluation = NotebookEngine.evaluate("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v² =\nE2 = E * 2")
        let line = evaluation.lines[2]
        XCTAssertEqual(line.kind, .definition)
        XCTAssertTrue(line.requestsValue)
        XCTAssertEqual(line.formattedValue, "1000 J")
        XCTAssertEqual(evaluation.lines[3].quantity?.value, 2000)
        XCTAssertFalse(evaluation.lines[3].requestsValue)
    }

    func testConversionFormsAreEvaluated() throws {
        let evaluation = NotebookEngine.evaluate("v = 20 m/s\nv → km/h =\nv = → km/h\nv * 1 s → m =")
        XCTAssertEqual(evaluation.lines[1].formattedValue, "72 km/h")
        XCTAssertEqual(evaluation.lines[2].formattedValue, "72 km/h")
        XCTAssertEqual(evaluation.lines[3].formattedValue, "20 m")
        XCTAssertTrue(evaluation.lines.dropFirst().allSatisfy { $0.requestsValue && $0.kind == .expression })
    }

    func testEquationIgnoresTheRequest() throws {
        let evaluation = NotebookEngine.evaluate("F = 14,4 N\nm = 2 kg\na = 7,2 m/s²\nF == m * a =\nF == m * a")
        XCTAssertEqual(evaluation.lines[3].kind, .equation)
        XCTAssertEqual(evaluation.lines[3].status, .success)
        XCTAssertEqual(evaluation.lines[3].message, "Égalité vérifiée.")
        XCTAssertFalse(evaluation.lines[3].requestsValue)
        XCTAssertFalse(evaluation.lines[4].requestsValue)
    }

    func testRequestsValueOfOtherLines() {
        let evaluation = NotebookEngine.evaluate("# note\n\nx = 2 m\nx * 2\nx → km\nw = ? m\nx * w == 6 m²")
        XCTAssertEqual(evaluation.lines.map(\.requestsValue), [false, false, false, false, true, true, false])
    }

    // MARK: Dependencies

    func testDependenciesAreTheTransitiveDeclaredNames() {
        let evaluation = NotebookEngine.evaluate("""
            m = 80 kg
            v = 5 m/s
            unused = 3 s
            E = 0,5 * m * v²
            F = E / 2 m
            F =
            E + c * 1 kg
            2 + 3
            # note
            """)
        let dependencies = evaluation.lines.map(\.dependencies)
        XCTAssertEqual(dependencies[0], [])
        XCTAssertEqual(dependencies[3], ["m", "v"])
        XCTAssertEqual(dependencies[4], ["E", "m", "v"])
        XCTAssertEqual(dependencies[5], ["F", "E", "m", "v"])
        XCTAssertEqual(dependencies[6], ["E", "m", "v"], "constants are not declared names")
        XCTAssertEqual(dependencies[7], [])
        XCTAssertEqual(dependencies[8], [])
        XCTAssertFalse(dependencies.contains { $0.contains("unused") })
    }

    func testDependenciesGoThroughTheRelationOfAnUnknown() {
        let evaluation = NotebookEngine.evaluate("""
            E = 1000 J
            m = 80 kg
            k = 3
            v = ? m/s
            E == 0,5 * m * v²
            w = v * k
            w =
            """)
        let dependencies = evaluation.lines.map(\.dependencies)
        XCTAssertEqual(dependencies[3], ["E", "m"], "the unknown itself is not a dependency of its line")
        XCTAssertEqual(dependencies[4], ["E", "m", "v"])
        XCTAssertEqual(dependencies[6], ["w", "v", "k", "E", "m"])
    }

    func testDependenciesHandleCyclesWithoutLooping() {
        let evaluation = NotebookEngine.evaluate("a = b\nb = a\nc = a + 1")
        XCTAssertEqual(evaluation.lines[0].dependencies, ["b"])
        XCTAssertEqual(evaluation.lines[2].dependencies, ["a", "b"])
    }

    func testDependenciesOfAQueryIncludeItsName() {
        let evaluation = NotebookEngine.evaluate("m = 2 kg\nv = 3 m/s\np = m * v\np =")
        XCTAssertEqual(evaluation.lines[3].dependencies, ["p", "m", "v"])
    }

    func testDependenciesOfCyclesAndTheirReaders() {
        let evaluation = NotebookEngine.evaluate("a = b + d\nb = c\nc = a\nd = 1\ne = b\nf = e + d\nf =")
        XCTAssertEqual(evaluation.lines[0].dependencies, ["b", "c", "d"], "a is not its own dependency")
        XCTAssertEqual(evaluation.lines[1].dependencies, ["a", "c", "d"])
        XCTAssertEqual(evaluation.lines[4].dependencies, ["a", "b", "c", "d"])
        XCTAssertEqual(evaluation.lines[5].dependencies, ["a", "b", "c", "d", "e"])
        XCTAssertEqual(evaluation.lines[6].dependencies, ["a", "b", "c", "d", "e", "f"])
    }

    func testDependenciesOfADenseSheet() {
        var lines = ["a0 = 1"]
        for index in 1..<500 {
            let reads = (max(0, index - 20)..<index).map { "a\($0)" }.joined(separator: " + ")
            lines.append("a\(index) = \(reads)")
        }
        let start = Date()
        let evaluation = NotebookEngine.evaluate(lines.joined(separator: "\n"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 20, "generous bound: the work must not be quadratic in the closures")
        XCTAssertEqual(evaluation.lines[499].dependencies.count, 499)
        XCTAssertEqual(evaluation.lines[250].dependencies.count, 250)
        XCTAssertEqual(evaluation.lines[0].dependencies, [])
    }

    func testOverLimitSheetsHaveNoDependencies() {
        let source = (0..<501).map { "a\($0) = 1" }.joined(separator: "\n")
        let evaluation = NotebookEngine.evaluate(source)
        XCTAssertTrue(evaluation.lines.allSatisfy { $0.dependencies.isEmpty })
    }

    func testDependenciesOfLongChainsOnTheSmallStack() {
        var chain = ["a0 = 1"]
        for index in 1...440 { chain.append("a\(index) = a\(index - 1) + 1") }
        chain.append("a440 =")
        let source = chain.joined(separator: "\n")
        let done = expectation(description: "Feuille évaluée")
        let thread = Thread {
            let evaluation = NotebookEngine.evaluate(source)
            XCTAssertEqual(evaluation.lines[441].dependencies.count, 441)
            XCTAssertEqual(evaluation.lines[440].dependencies.count, 440)
            done.fulfill()
        }
        thread.stackSize = 512 * 1024
        thread.start()
        wait(for: [done], timeout: 30)
    }

    // MARK: Notation and speech

    func testQueryRendersAsARowWithTheRequest() {
        XCTAssertEqual(MathNotation.formula("a ="), .row([.atom("a"), .atom(" =")]))
        XCTAssertEqual(MathNotation.formula("a=   # note"), .row([.atom("a"), .atom(" =")]))
        guard case .row(let converted)? = MathNotation.formula("v → km/h") else { return XCTFail("row expected") }
        XCTAssertEqual(MathNotation.formula("v → km/h ="), .row(converted + [.atom(" =")]))
        XCTAssertEqual(MathNotation.formula("v = → km/h"), MathNotation.formula("v → km/h ="))
    }

    func testDeclarationWithARequestEndsWithTheRequest() throws {
        let formula = try XCTUnwrap(MathNotation.formula("E = 0,5 * m * v² ="))
        let plain = try XCTUnwrap(MathNotation.formula("E = 0,5 * m * v²"))
        guard case .row(let children) = formula, case .row(let base) = plain else { return XCTFail("rows expected") }
        XCTAssertEqual(children, base + [.atom(" =")])
    }

    func testEqualityDropsTheIgnoredRequest() {
        XCTAssertEqual(MathNotation.formula("F == m * a ="), MathNotation.formula("F == m * a"))
    }

    func testQueryIsReadAloud() {
        XCTAssertEqual(MathSpeech.description("a ="), "a égale")
        XCTAssertEqual(MathSpeech.description("m * v ="), "m fois v égale")
        XCTAssertEqual(MathSpeech.description("v → km/h ="), "v, affiché en kilomètres par heure, égale")
        XCTAssertEqual(MathSpeech.description("v = → km/h"), "v, affiché en kilomètres par heure, égale")
        XCTAssertEqual(MathSpeech.description("v → km/h = # vitesse"), "v, affiché en kilomètres par heure, égale, note : vitesse")
        XCTAssertEqual(MathSpeech.description("m = 80 kg ="), "m égale 80 kilogrammes", "égale is not said twice")
        XCTAssertEqual(MathSpeech.description("m = 80 kg → g ="), "m égale 80 kilogrammes, affiché en grammes")
        XCTAssertEqual(MathSpeech.description("E = m * c² ="), MathSpeech.description("E = m * c²").map { $0 + " égale" })
        XCTAssertEqual(MathSpeech.description("F == m * a ="), MathSpeech.description("F == m * a"))
        XCTAssertEqual(MathSpeech.description("a = # note"), "a égale, note : note")
    }
}
