import Foundation
import Testing
@testable import EvalCore

@Suite("Formula insertion")
struct FormulaInsertionTests {
    /// Inserts at the characters `from..<to` and returns the text with `|` at the caret.
    private func insert(_ snippet: FormulaInsertion.Snippet, _ text: String, _ from: Int, _ to: Int? = nil) -> String {
        let lower = text.index(text.startIndex, offsetBy: from)
        let upper = text.index(text.startIndex, offsetBy: to ?? from)
        let result = FormulaInsertion.insert(snippet, into: text, replacing: lower..<upper)
        var marked = result.text
        marked.insert("|", at: result.caret)
        return marked
    }

    @Test func operatorsAreSpacedWithoutDoubling() {
        #expect(insert(.operator("*"), "m", 1) == "m * |")
        #expect(insert(.operator("*"), "m ", 2) == "m * |")
        #expect(insert(.operator("+"), "a b", 1) == "a + |b")
        #expect(insert(.operator("-"), "(", 1) == "(- |")
        #expect(insert(.operator("="), "", 0) == "= |")
        #expect(insert(.operator("*"), "a\n\nb", 1) == "a *|\n\nb")
    }

    @Test func literalsAreInsertedExactly() {
        #expect(insert(.literal("²"), "v", 1) == "v²|")
        #expect(insert(.literal("^"), "x y", 1) == "x^| y")
    }

    @Test func parenthesesWrapSelectionOrOpenEmpty() {
        #expect(insert(.parentheses, "a + b", 0, 5) == "(a + b)|")
        #expect(insert(.parentheses, "2 ", 2) == "2 (|)")
        #expect(insert(.function("sqrt"), "L / g", 0, 5) == "sqrt(L / g)|")
        #expect(insert(.function("sqrt"), "x = ", 4) == "x = sqrt(|)")
    }

    @Test func selectionIsReplaced() {
        #expect(insert(.name("π"), "2 * x", 4, 5) == "2 * π|")
        #expect(insert(.operator("/"), "a b", 1, 2) == "a / |b")
    }

    @Test func namesNeverFuseWithTheirNeighbours() {
        #expect(insert(.name("π"), "2", 1) == "2 * π|")
        #expect(insert(.name("π"), "2 ", 2) == "2 π|")
        #expect(insert(.name("π"), "r", 0) == "π |r")
        #expect(insert(.name("m"), "(a)", 3) == "(a) * m|")
        #expect(insert(.name("g"), "", 0) == "g|")
        #expect(insert(.name("epsilon_0"), "4 * ", 4) == "4 * epsilon_0|")
        #expect(insert(.name("v"), "x²", 2) == "x² * v|")
    }

    @Test func unitsFollowANumberAfterASpace() {
        #expect(insert(.unit("m/s"), "5", 1) == "5 m/s|")
        #expect(insert(.unit("kg"), "5 ", 2) == "5 kg|")
        #expect(insert(.unit("s"), "(a + b)", 7) == "(a + b) s|")
        #expect(insert(.unit("N"), "", 0) == "N|")
        #expect(insert(.unit("m"), "5", 0) == "m |5")
    }

    @Test func rangeIsClampedToTheText() {
        let text = "abc"
        let result = FormulaInsertion.insert(.literal("x"), into: text, replacing: text.endIndex..<text.endIndex)
        #expect(result.text == "abcx")
        #expect(result.text[..<result.caret] == "abcx")
    }

    @Test func insertedTextParsesAsASheet() {
        let built = FormulaInsertion.insert(.name("π"), into: "2", replacing: "2".endIndex..<"2".endIndex).text
        let result = NotebookEngine.evaluate(built).lines.first
        #expect(result?.status == .success)
    }
}
