import Foundation
import Testing
@testable import EvalCore

@Suite("Sheet line editing")
struct SheetLineEditingTests {
    @Test func movingKeepsHiddenLinesInPlace() {
        // Entries: 0 "a", 1 "", 2 "b", 3 "c"; the blank entry 1 is hidden.
        let visible = [0, 2, 3]
        #expect(LineReordering.order(count: 4, visible: visible, moving: [2], to: 0) == [3, 1, 0, 2])
        #expect(LineReordering.order(count: 4, visible: visible, moving: [0], to: 3) == [2, 1, 3, 0])
        #expect(LineReordering.order(count: 4, visible: visible, moving: [0], to: 1) == [0, 1, 2, 3])
        #expect(LineReordering.order(count: 4, visible: visible, moving: [0, 1], to: 3) == [3, 1, 0, 2])
    }

    @Test func invalidMovesAreRejected() {
        #expect(LineReordering.order(count: 3, visible: [0, 1, 2], moving: [], to: 1) == nil)
        #expect(LineReordering.order(count: 3, visible: [0, 1, 2], moving: [3], to: 1) == nil)
        #expect(LineReordering.order(count: 3, visible: [0, 1, 2], moving: [0], to: 4) == nil)
        #expect(LineReordering.order(count: 2, visible: [0, 5], moving: [0], to: 1) == nil)
    }

    @Test func rearrangingKeepsIdentitiesAndChoices() throws {
        var selection = ResultSelection(source: "a\nb\nc")
        selection.setSelected(true, at: 1)
        let ids = selection.entries.map(\.id)
        let moved = try #require(selection.rearranged(by: [2, 0, 1]))
        #expect(moved.entries.map(\.source) == ["c", "a", "b"])
        #expect(moved.entries.map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(moved.entries.map(\.isSelected) == [false, false, true])
        #expect(selection.rearranged(by: [0, 0, 1]) == nil)
        #expect(selection.rearranged(by: [0, 1]) == nil)
    }

    @Test func dragReorderThenReconcileIsANoOp() throws {
        let selection = ResultSelection(source: "a\n\nb\nc")
        let order = try #require(LineReordering.order(count: 4, visible: [0, 2, 3], moving: [2], to: 0))
        var moved = try #require(selection.rearranged(by: order))
        let before = moved.entries
        moved.reconcile(source: moved.entries.map(\.source).joined(separator: "\n"))
        #expect(moved.entries == before)
    }

    @Test func insertingAddsAnIndependentEntry() throws {
        var selection = ResultSelection(source: "a\nb")
        selection.setSelected(true, at: 0)
        let copy = ResultSelection.Entry(source: "a")
        let inserted = try #require(selection.inserting(copy, at: 1))
        #expect(inserted.entries.map(\.source) == ["a", "a", "b"])
        #expect(inserted.entries[1].id == copy.id)
        #expect(inserted.entries[1].id != inserted.entries[0].id)
        #expect(inserted.entries.map(\.isSelected) == [true, false, false])
        #expect(try #require(selection.inserting(copy, at: 99)).entries.last?.source == "a")
    }

    @Test func resultLinesNameTheirValue() {
        #expect(ResultText.line(source: "E = 0,5 * m * v²", value: "1000 J") == "E = 1000 J")
        #expect(ResultText.line(source: "  m * v  # quantité", value: "400 kg·m·s⁻¹") == "m * v = 400 kg·m·s⁻¹")
        #expect(ResultText.line(source: "m * a == F", value: "14,4 N") == "m * a == F → 14,4 N")
        #expect(ResultText.line(source: "2 * (a = 3)", value: "6") == "2 * (a = 3) = 6")
        #expect(ResultText.line(source: "", value: "1") == "1")
    }

    @Test func resultLinesLeaveOutTheConversion() {
        #expect(ResultText.line(source: "E → kWh # note", value: "3 kWh") == "E = 3 kWh")
        #expect(ResultText.line(source: "v = 5 m/s -> km/h", value: "18 km/h") == "v = 18 km/h")
        #expect(ResultText.line(source: "v = ? m/s", value: "5 m/s") == "v = 5 m/s")
    }

    @Test func resultLinesOfRequests() {
        #expect(ResultText.line(source: "a =", value: "1000 J") == "a = 1000 J")
        #expect(ResultText.line(source: "E = 0,5 * m * v² =", value: "1000 J") == "E = 1000 J")
        #expect(ResultText.line(source: "v → km/h = # note", value: "18 km/h") == "v = 18 km/h")
        #expect(ResultText.line(source: "m * v =", value: "400 kg·m·s⁻¹") == "m * v = 400 kg·m·s⁻¹")
        #expect(ResultText.line(source: "F == m * a =", value: "14,4 N") == "F == m * a → 14,4 N")
        #expect(ResultText.declaredName(in: "a =") == nil)
        #expect(ResultText.declaredName(in: "E = 2 * m =") == "E")
        #expect(ResultText.spokenLine(source: "a =", spokenValue: "1000 joules") == "a égale 1000 joules")
    }

    @Test func declaredNames() {
        #expect(ResultText.declaredName(in: "E = 0,5 * m * v²  # énergie") == "E")
        #expect(ResultText.declaredName(in: "m = 80 kg") == "m")
        #expect(ResultText.declaredName(in: "m * a == F") == nil)
        #expect(ResultText.declaredName(in: "2 * m") == nil)
        #expect(ResultText.declaredName(in: "# x = 2") == nil)
    }

    @Test func sharedSheetAddsValuesAsComments() {
        let text = ResultText.sharedSheet([
            ("# Énergie", nil), ("E = 0,5 * m * v²  ", "1000 J"), ("m = 80 kg", nil), ("c # lumière", "299792458 m·s⁻¹"), ("", "1")
        ])
        #expect(text == "# Énergie\nE = 0,5 * m * v²  # 1000 J\nm = 80 kg\nc # lumière\n")
        let reopened = NotebookEngine.evaluate("E = 2 * 3 =  # 6\nE")
        #expect(reopened.lines.last?.quantity?.value == 6)
    }
}
