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

    private func selectedIndexes(_ selection: ResultSelection) -> Set<Int> {
        Set(selection.entries.indices.filter { selection.isSelected(at: $0) })
    }
}
