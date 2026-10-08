import Foundation
import XCTest
@testable import EvalCore

final class ResultSelectionTests: XCTestCase {
    func testInsertionKeepsTheChosenResultAndLeavesNewLinesUnselected() {
        var selection = ResultSelection(source: "a = 2\na*3", initiallySelectedLineIDs: [1])
        let chosenID = selection.entries[1].id
        selection.reconcile(source: "b = 5\na = 2\na*3\nb*4")
        XCTAssertEqual(selection.entries[2].id, chosenID)
        XCTAssertEqual(selectedIndexes(selection), [2])
    }

    func testDeletionRemovesOnlyTheDeletedChoice() {
        var selection = ResultSelection(source: "a = 2\na*3\na*4", initiallySelectedLineIDs: [1, 2])
        let survivingID = selection.entries[2].id
        selection.reconcile(source: "a = 2\na*4")
        XCTAssertEqual(selection.entries.count, 2)
        XCTAssertEqual(selection.entries[1].id, survivingID)
        XCTAssertEqual(selectedIndexes(selection), [1])
    }

    func testReorderingMovesIdentityAndSelectionWithTheFormula() {
        var selection = ResultSelection(source: "a = 2\na*3\na*4", initiallySelectedLineIDs: [1])
        let previousIDs = selection.entries.map(\.id)
        selection.reconcile(source: "a*4\na*3\na = 2")
        XCTAssertEqual(selection.entries.map(\.id), [previousIDs[2], previousIDs[1], previousIDs[0]])
        XCTAssertEqual(selectedIndexes(selection), [1])
    }

    func testNamedDefinitionKeepsChoiceAfterAnEditAndAMove() {
        var selection = ResultSelection(source: "E = m*c²\nm = 1 kg\nE", initiallySelectedLineIDs: [0])
        let chosenID = selection.entries[0].id
        selection.reconcile(source: "m = 2 kg\nE\nE = m*c²/2")
        XCTAssertEqual(selection.entries[2].id, chosenID)
        XCTAssertEqual(selectedIndexes(selection), [2])
    }

    func testEditedFormulaKeepsItsChoiceBetweenUnchangedLines() {
        var selection = ResultSelection(source: "a = 2\na*3\na*4", initiallySelectedLineIDs: [1])
        let chosenID = selection.entries[1].id
        selection.reconcile(source: "a = 2\na*5/2\na*4")
        XCTAssertEqual(selection.entries[1].id, chosenID)
        XCTAssertEqual(selectedIndexes(selection), [1])
    }

    func testSimultaneousInsertionAndFormulaEditDoNotSelectTheInsertedFormula() {
        var selection = ResultSelection(source: "a = 2\na*t\nt = 3", initiallySelectedLineIDs: [1])
        let chosenID = selection.entries[1].id
        selection.reconcile(source: "a = 2\nc²\na*t/2\nt = 3")
        XCTAssertEqual(selection.entries[2].id, chosenID)
        XCTAssertEqual(selectedIndexes(selection), [2])
    }

    func testDuplicateLinesMatchDeterministicallyInOccurrenceOrder() {
        var selection = ResultSelection(source: "a\na\nb", initiallySelectedLineIDs: [1])
        let previousIDs = selection.entries.map(\.id)
        selection.reconcile(source: "b\na\na\na")
        XCTAssertEqual(selection.entries[0].id, previousIDs[2])
        XCTAssertEqual(selection.entries[1].id, previousIDs[0])
        XCTAssertEqual(selection.entries[2].id, previousIDs[1])
        XCTAssertEqual(selectedIndexes(selection), [2])
    }

    func testTypedDeletionOfOneDuplicateKeepsTheSurvivorsOwnChoice() {
        var selection = ResultSelection(source: "x = 1\ny*2\nz\ny*2", initiallySelectedLineIDs: [1])
        let survivor = selection.entries[3].id
        selection.reconcile(source: "x = 1\nz\ny*2")
        XCTAssertEqual(selection.entries[2].id, survivor)
        XCTAssertFalse(selection.isSelected(at: 2))

        var mirror = ResultSelection(source: "a*2\nb\na*2", initiallySelectedLineIDs: [2])
        let chosen = mirror.entries[2].id
        mirror.reconcile(source: "b\na*2")
        XCTAssertEqual(mirror.entries[1].id, chosen)
        XCTAssertEqual(selectedIndexes(mirror), [1])
    }

    func testCutThenPasteRestoresIdentityAndChoice() {
        var selection = ResultSelection(source: "v = 5 m/s\nt = 2 s\nd = v*t\nd", initiallySelectedLineIDs: [3])
        let moved = selection.entries[3].id
        selection.reconcile(source: "v = 5 m/s\nt = 2 s\nd = v*t\n")
        XCTAssertFalse(selection.entries.contains { $0.id == moved })
        XCTAssertTrue(selection.retainedIDs.contains(moved))
        selection.reconcile(source: "d\nv = 5 m/s\nt = 2 s\nd = v*t\n")
        XCTAssertEqual(selection.entries[0].id, moved)
        XCTAssertEqual(selectedIndexes(selection), [0])

        // A declaration keeps its identity too, so data keyed by it can follow.
        let declaration = selection.entries[1].id
        selection.reconcile(source: "d\nt = 2 s\nd = v*t\n")
        XCTAssertTrue(selection.retainedIDs.contains(declaration))
        selection.reconcile(source: "d\nt = 2 s\nd = v*t\nv = 5 m/s")
        XCTAssertEqual(selection.entries[3].id, declaration)
        XCTAssertEqual(selection.retainedIDs, Set(selection.entries.map(\.id)))
    }

    func testRetypedDeclarationRecoversItsIdentity() {
        var selection = ResultSelection(source: "m = 80 kg\nm*g", initiallySelectedLineIDs: [0])
        let original = selection.entries[0].id
        selection.reconcile(source: "m\nm*g")
        XCTAssertNotEqual(selection.entries[0].id, original)
        selection.reconcile(source: "m = 90 kg\nm*g")
        XCTAssertEqual(selection.entries[0].id, original)
        XCTAssertTrue(selection.isSelected(at: 0))
    }

    func testRemovedLinesAreRememberedWithinABound() {
        let source = (0..<30).map { "x*\($0)" }.joined(separator: "\n")
        var selection = ResultSelection(source: source)
        let ids = selection.entries.map(\.id)
        selection.removeEntry(at: 0)
        selection.reconcile(source: (1..<30).map { "x*\($0)" }.joined(separator: "\n"))
        XCTAssertTrue(selection.retainedIDs.contains(ids[0]))
        selection.reconcile(source: "# vide\n")
        XCTAssertEqual(selection.retainedIDs.count, 22)
        XCTAssertTrue(selection.retainedIDs.isSuperset(of: ids.suffix(20)))
        XCTAssertFalse(selection.retainedIDs.contains(ids[0]))
        // Blank lines and comments are not worth remembering.
        selection.reconcile(source: "")
        XCTAssertEqual(selection.retainedIDs.count, 21)
    }

    func testRemovedLinesSurviveCodingAndEarlierDataStillDecodes() throws {
        var selection = ResultSelection(source: "a*2\nb*3", initiallySelectedLineIDs: [0])
        let removed = selection.entries[0].id
        selection.reconcile(source: "b*3")
        let restored = try JSONDecoder().decode(ResultSelection.self, from: JSONEncoder().encode(selection))
        XCTAssertEqual(restored, selection)
        XCTAssertTrue(restored.retainedIDs.contains(removed))

        let id = UUID()
        let legacy = Data(#"{"entries":[{"id":"\#(id.uuidString)","source":"x*2","isSelected":true}]}"#.utf8)
        let decoded = try JSONDecoder().decode(ResultSelection.self, from: legacy)
        XCTAssertEqual(decoded.entries.map(\.id), [id])
        XCTAssertEqual(decoded.retainedIDs, [id])
    }

    func testExplicitDeletionOfOneDuplicateKeepsTheSurvivorsOwnChoice() {
        var selection = ResultSelection(source: "2+2\n2+2", initiallySelectedLineIDs: [0])
        let survivingID = selection.entries[1].id
        selection.removeEntry(at: 0)
        selection.reconcile(source: "2+2")
        XCTAssertEqual(selection.entries[0].id, survivingID)
        XCTAssertEqual(selectedIndexes(selection), [])
    }

    func testExplicitEditIntoADuplicateKeepsBothOriginalIdentitiesAndChoices() {
        var selection = ResultSelection(source: "2+2\n3+3", initiallySelectedLineIDs: [1])
        let previousIDs = selection.entries.map(\.id)
        selection.updateSource("3+3", at: 0)
        selection.reconcile(source: "3+3\n3+3")
        XCTAssertEqual(selection.entries.map(\.id), previousIDs)
        XCTAssertEqual(selectedIndexes(selection), [1])
    }

    func testExplicitDefinitionRenameKeepsIdentityWhileCommentClearsItsChoice() {
        var selection = ResultSelection(source: "a = 2", initiallySelectedLineIDs: [0])
        let originalID = selection.entries[0].id
        selection.updateSource("b = 3", at: 0)
        selection.reconcile(source: "b = 3")
        XCTAssertEqual(selection.entries[0].id, originalID)
        XCTAssertTrue(selection.isSelected(at: 0))
        selection.updateSource("# b = 3", at: 0)
        selection.reconcile(source: "# b = 3")
        XCTAssertEqual(selection.entries[0].id, originalID)
        XCTAssertFalse(selection.isSelected(at: 0))
    }

    func testExplicitRemovalOfLastFormulaReconcilesToAnEmptySheet() {
        var selection = ResultSelection(source: "2+2", initiallySelectedLineIDs: [0])
        selection.removeEntry(at: 0)
        selection.reconcile(source: "")
        XCTAssertEqual(selection.entries.map(\.source), [""])
        XCTAssertEqual(selectedIndexes(selection), [])
    }

    func testADeclarationRenamedIntoAnUnrelatedOneStartsUnselected() {
        var selection = ResultSelection(source: "a = 2", initiallySelectedLineIDs: [0])
        let oldID = selection.entries[0].id
        selection.reconcile(source: "b = 3")
        XCTAssertNotEqual(selection.entries[0].id, oldID)
        XCTAssertFalse(selection.isSelected(at: 0))
    }

    func testCommentOrBlankReplacingAResultDoesNotKeepItsChoice() {
        for source in ["# a*3", ""] {
            var selection = ResultSelection(source: "a*3", initiallySelectedLineIDs: [0])
            selection.reconcile(source: source)
            XCTAssertFalse(selection.isSelected(at: 0))
        }
    }

    func testLineEndingsMatchNotebookEngineIndexes() {
        let source = "a = 2\r\na*3\r\n\r# commentaire\n"
        let selection = ResultSelection(source: source, initiallySelectedLineIDs: [1])
        XCTAssertEqual(selection.entries.map(\.source), NotebookEngine.evaluate(source).lines.map(\.source))
        XCTAssertEqual(selectedIndexes(selection), [1])
    }

    func testCodableRoundTripPreservesChoicesAndReconcilesLaterEdits() throws {
        let original = ResultSelection(source: "a = 2\na*3", initiallySelectedLineIDs: [1])
        let data = try JSONEncoder().encode(original)
        var restored = try JSONDecoder().decode(ResultSelection.self, from: data)
        XCTAssertEqual(restored, original)
        restored.reconcile(source: "# Exercice\na = 4\na*3")
        XCTAssertEqual(restored.entries[2].id, original.entries[1].id)
        XCTAssertEqual(selectedIndexes(restored), [2])
    }

    func testSelectionOperationsIgnoreInvalidIndexesAndLimitBulkChoice() {
        var selection = ResultSelection(source: "# Exemple\na = 2\na*3\n")
        let original = selection
        selection.updateSource("b = 2", at: -1)
        selection.updateSource("b = 2", at: 4)
        selection.updateSource("a = 2\nb = 3", at: 1)
        selection.removeEntry(at: -1)
        selection.removeEntry(at: 4)
        XCTAssertEqual(selection, original)
        selection.setSelected(true, at: -1)
        selection.setSelected(true, at: 4)
        XCTAssertEqual(selectedIndexes(selection), [])
        selection.setSelected(true, at: 2)
        XCTAssertEqual(selectedIndexes(selection), [2])
        selection.setAllSelected(true, selectableLineIDs: [1, 2, 99])
        XCTAssertEqual(selectedIndexes(selection), [1, 2])
        selection.setAllSelected(false, selectableLineIDs: [1, 2])
        XCTAssertEqual(selectedIndexes(selection), [])
        XCTAssertFalse(selection.isSelected(at: -1))
        XCTAssertFalse(selection.isSelected(at: 4))
    }

    func testReconciliationWithoutChangesDoesNotRegenerateIdentities() {
        var selection = ResultSelection(source: "a = 2\na*3", initiallySelectedLineIDs: [1])
        let previous = selection
        selection.reconcile(source: "a = 2\na*3")
        XCTAssertEqual(selection, previous)
    }

    func testMovingALineKeepsTheMemoryOfRemovedLines() throws {
        var selection = ResultSelection(source: "a = 1\nb = 2\na * b\na + b", initiallySelectedLineIDs: [2])
        let cutID = selection.entries[2].id
        selection.reconcile(source: "a = 1\nb = 2\na + b")               // cut "a * b"
        var moved = try XCTUnwrap(selection.rearranged(by: [1, 0, 2]))    // reorder in Formules mode
        XCTAssertTrue(moved.retainedIDs.contains(cutID))
        moved.reconcile(source: "b = 2\na = 1\na + b\na * b")             // pasted back
        XCTAssertEqual(moved.entries[3].id, cutID)
        XCTAssertTrue(moved.entries[3].isSelected)
        // Inserting a line keeps the memory too.
        var inserted = try XCTUnwrap(selection.inserting(ResultSelection.Entry(source: "c = 3"), at: 1))
        XCTAssertTrue(inserted.retainedIDs.contains(cutID))
        inserted.reconcile(source: "a = 1\nc = 3\nb = 2\na + b\na * b")
        XCTAssertEqual(inserted.entries[4].id, cutID)
    }

    func testLargePasteStaysResponsive() {
        // 500 lines replaced by 499 unrelated formulas: every pair used to be compared.
        let old = (0..<500).map { "f\($0) * g + h\($0) / k" }.joined(separator: "\n")
        let new = (0..<499).map { "p\($0) + q * r\($0) - s" }.joined(separator: "\n")
        var selection = ResultSelection(source: old)
        var start = Date()
        selection.reconcile(source: new)
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
        XCTAssertEqual(selection.entries.count, 499)

        // Same size: lines are paired by position and kind, without similarity search.
        selection = ResultSelection(source: old)
        start = Date()
        selection.reconcile(source: (0..<500).map { "p\($0) + q * r\($0) - s" }.joined(separator: "\n"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)

        // A paste in the middle of a big sheet, with one line edited.
        let lines = (0..<500).map { "x\($0) = \($0) m" }
        selection = ResultSelection(source: lines.joined(separator: "\n"))
        var edited = lines
        edited.insert(contentsOf: (0..<40).map { "y\($0) + z\($0)" }, at: 250)
        edited[10] = "x10 = 1000 m"
        start = Date()
        selection.reconcile(source: edited.joined(separator: "\n"))
        XCTAssertLessThan(Date().timeIntervalSince(start), 0.5)
    }

    func testSmallEditsStillKeepTheirChoiceAfterTheOptimisation() {
        var selection = ResultSelection(source: "a = 2\nm * v^2\nm * v", initiallySelectedLineIDs: [1])
        let chosenID = selection.entries[1].id
        selection.reconcile(source: "a = 2\nb = 3\nm * v^2 / 2\nm * v")
        XCTAssertEqual(selection.entries[2].id, chosenID)
        XCTAssertEqual(selectedIndexes(selection), [2])
    }

    private func selectedIndexes(_ selection: ResultSelection) -> Set<Int> {
        Set(selection.entries.indices.filter { selection.isSelected(at: $0) })
    }
}
