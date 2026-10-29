import Foundation
import XCTest
@testable import EvalCore

final class SheetSessionTests: XCTestCase {
    private func makeSession(_ source: String, title: String? = nil,
                             onChange: @escaping (SheetRecord) -> Void = { _ in }) -> SheetSession {
        SheetSession(record: SheetRecord(customTitle: title, source: source), onChange: onChange)
    }

    private func lineID(_ session: SheetSession, _ index: Int) -> UUID {
        session.resultSelection.entries[index].id
    }

    private func lineIDs(_ session: SheetSession) -> [UUID] {
        session.resultSelection.entries.map(\.id)
    }

    /// Evaluates the current text and shows it, as the app does once the delay is over.
    private func evaluate(_ session: SheetSession) {
        XCTAssertTrue(session.apply(SheetSession.evaluate(session.evaluationRequest)))
    }

    // MARK: Editing in place

    func testAnEditingSessionIsOneUndoStep() throws {
        let sheet = makeSession("m = 2\nE = m * 3 =")
        let id = lineID(sheet, 1)
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: id))
        XCTAssertFalse(editing.isNew)
        sheet.updateLine("E = m * 4", lineID: id)
        sheet.updateLine("E = m * 4 =", lineID: id)
        XCTAssertFalse(sheet.canUndo)
        sheet.endEditing(editing)
        XCTAssertEqual(sheet.undoActionName, "Modifier la ligne")

        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "m = 2\nE = m * 3 =")
        XCTAssertEqual(lineID(sheet, 1), id)
        XCTAssertFalse(sheet.canUndo)
        XCTAssertEqual(sheet.redoActionName, "Modifier la ligne")
        XCTAssertTrue(sheet.redo())
        XCTAssertEqual(sheet.source, "m = 2\nE = m * 4 =")
        XCTAssertEqual(lineID(sheet, 1), id)
        XCTAssertEqual(sheet.undoActionName, "Modifier la ligne")
        XCTAssertFalse(sheet.canRedo)
    }

    func testAnEditingSessionWithoutChangeLeavesNoStep() throws {
        let sheet = makeSession("a = 1")
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: lineID(sheet, 0)))
        sheet.updateLine("a = 1", lineID: editing.lineID)
        sheet.endEditing(editing)
        XCTAssertFalse(sheet.canUndo)
        XCTAssertNil(sheet.beginEditing(lineID: UUID()))
    }

    func testANewLineIsShownWhileBlankAndAddedOnceWritten() throws {
        let sheet = makeSession("a = 1")
        let blank = try XCTUnwrap(sheet.insertLines(after: nil))
        XCTAssertTrue(blank.isNew)
        XCTAssertEqual(sheet.formulaLines.map(\.id), [lineID(sheet, 0), blank.lineID])
        XCTAssertEqual(sheet.revealRequest?.lineID, blank.lineID)
        XCTAssertTrue(sheet.editingLineIDs.contains(blank.lineID))
        sheet.endEditing(blank)
        XCTAssertEqual(sheet.source, "a = 1")
        XCTAssertTrue(sheet.editingLineIDs.isEmpty)
        XCTAssertFalse(sheet.canUndo)

        let added = try XCTUnwrap(sheet.insertLines(after: nil))
        sheet.updateLine("b = 2", lineID: added.lineID)
        sheet.endEditing(added)
        XCTAssertEqual(sheet.source, "a = 1\nb = 2")
        XCTAssertEqual(sheet.undoActionName, "Ajouter une ligne")
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "a = 1")
    }

    func testAnEmptySheetKeepsItsBlankLine() throws {
        let sheet = makeSession("")
        let blankID = lineID(sheet, 0)
        XCTAssertTrue(sheet.formulaLines.isEmpty)
        let editing = try XCTUnwrap(sheet.insertLines(after: nil))
        XCTAssertEqual(editing.lineID, blankID)
        XCTAssertEqual(sheet.formulaLines.map(\.id), [blankID])
        sheet.endEditing(editing)
        XCTAssertEqual(lineIDs(sheet), [blankID])
        XCTAssertTrue(sheet.formulaLines.isEmpty)
        XCTAssertFalse(sheet.canUndo)

        let written = try XCTUnwrap(sheet.insertLines(["a = 1"], at: nil))
        sheet.endEditing(written)
        let cleared = try XCTUnwrap(sheet.beginEditing(lineID: blankID))
        sheet.updateLine("", lineID: blankID)
        sheet.endEditing(cleared)
        XCTAssertEqual(sheet.source, "")
        XCTAssertEqual(sheet.undoActionName, "Supprimer la ligne")
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "a = 1")
    }

    func testLinesAreInsertedAfterALine() throws {
        let sheet = makeSession("a = 1\nc = 3")
        let first = lineID(sheet, 0)
        let editing = try XCTUnwrap(sheet.insertLines(["b = 2"], after: first))
        XCTAssertEqual(sheet.source, "a = 1\nb = 2\nc = 3")
        XCTAssertEqual(lineID(sheet, 1), editing.lineID)
        sheet.endEditing(editing)
        XCTAssertEqual(sheet.undoActionName, "Ajouter une ligne")
    }

    func testABlankLastLineTakesTheNewText() throws {
        let sheet = makeSession("a = 1\n")
        let blankID = lineID(sheet, 1)
        XCTAssertEqual(sheet.formulaLines.count, 1)
        let editing = try XCTUnwrap(sheet.insertLines(["b = 2"], at: nil))
        XCTAssertEqual(editing.lineID, blankID)
        XCTAssertTrue(editing.isNew)
        XCTAssertEqual(sheet.source, "a = 1\nb = 2")
        sheet.endEditing(editing)
        XCTAssertEqual(sheet.undoActionName, "Ajouter une ligne")
    }

    func testALineLeftBlankIsRemoved() throws {
        let sheet = makeSession("a = 1\nb = 2")
        let id = lineID(sheet, 1)
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: id))
        sheet.updateLine("", lineID: id)
        XCTAssertEqual(sheet.formulaLines.last?.id, id)
        sheet.endEditing(editing)
        XCTAssertEqual(sheet.source, "a = 1")
        XCTAssertEqual(sheet.undoActionName, "Supprimer la ligne")
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "a = 1\nb = 2")
        XCTAssertEqual(lineID(sheet, 1), id)
    }

    func testUpdatingALineRefusesLineBreaks() throws {
        let sheet = makeSession("a = 1")
        sheet.updateLine("a = 2\nb = 3", lineID: lineID(sheet, 0))
        XCTAssertEqual(sheet.source, "a = 1")
    }

    func testABreakMovesTheRestToNewLines() throws {
        let sheet = makeSession("a = 1")
        let first = lineID(sheet, 0)
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: first))
        let next = try XCTUnwrap(sheet.breakLine("a = 1\nb = 2\nc = 3", session: editing))
        XCTAssertEqual(sheet.source, "a = 1\nb = 2\nc = 3")
        XCTAssertEqual(lineID(sheet, 0), first)
        XCTAssertEqual(next.lineID, lineID(sheet, 2))
        XCTAssertTrue(next.isNew)
        XCTAssertFalse(sheet.editingLineIDs.contains(first))
        sheet.endEditing(next)
        XCTAssertEqual(sheet.undoActionName, "Ajouter une ligne")
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "a = 1")

        // A Return on a blank line only closes it.
        let blank = try XCTUnwrap(sheet.insertLines(after: nil))
        XCTAssertNil(sheet.breakLine("\n", session: blank))
        XCTAssertEqual(sheet.source, "a = 1")
        XCTAssertTrue(sheet.editingLineIDs.isEmpty)

        // Without a break, the line is only updated and stays edited.
        let edited = try XCTUnwrap(sheet.beginEditing(lineID: first))
        XCTAssertEqual(sheet.breakLine("a = 5", session: edited), edited)
        XCTAssertEqual(sheet.source, "a = 5")
    }

    func testABreakOnABlankLineGivesItsPlaceToTheNewLines() throws {
        let sheet = makeSession("a = 1\nc = 3")
        let blank = try XCTUnwrap(sheet.insertLines([""], at: 1))
        let next = try XCTUnwrap(sheet.breakLine("\nb = 2", session: blank))
        XCTAssertEqual(sheet.source, "a = 1\nb = 2\nc = 3")
        XCTAssertEqual(next.lineID, lineID(sheet, 1))
    }

    // MARK: Line actions

    func testLineActionsAreNamedUndoSteps() throws {
        let original = "a = 1\nb = 2\nc = a + b ="
        let sheet = makeSession(original)
        let ids = lineIDs(sheet)
        func undoes(_ name: String, file: StaticString = #filePath, line: UInt = #line) {
            XCTAssertEqual(sheet.undoActionName, name, file: file, line: line)
            XCTAssertTrue(sheet.undo(), file: file, line: line)
            XCTAssertEqual(sheet.source, original, file: file, line: line)
            XCTAssertEqual(lineIDs(sheet), ids, file: file, line: line)
        }

        sheet.removeLine(id: ids[0])
        XCTAssertEqual(sheet.source, "b = 2\nc = a + b =")
        undoes("Supprimer la ligne")
        sheet.removeLines(atOffsets: [0, 1])
        XCTAssertEqual(sheet.source, "c = a + b =")
        undoes("Supprimer les lignes")
        sheet.removeLines(atOffsets: [2])
        undoes("Supprimer la ligne")
        sheet.moveLines(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(sheet.source, "c = a + b =\na = 1\nb = 2")
        XCTAssertEqual(lineIDs(sheet), [ids[2], ids[0], ids[1]])
        undoes("Déplacer la ligne")
        sheet.moveLines(fromOffsets: [0, 1], toOffset: 3)
        XCTAssertEqual(sheet.source, "c = a + b =\na = 1\nb = 2")
        undoes("Déplacer les lignes")
        let copy = try XCTUnwrap(sheet.duplicateLine(id: ids[2]))
        XCTAssertEqual(sheet.source, original + "\nc = a + b =")
        XCTAssertEqual(lineIDs(sheet), ids + [copy])
        XCTAssertEqual(sheet.revealRequest?.lineID, copy)
        undoes("Dupliquer la ligne")
        sheet.appendLines(["d = 4", "  "])
        XCTAssertEqual(sheet.source, original + "\nd = 4")
        undoes("Ajouter une ligne")
        sheet.appendLines(["d = 4", "e = 5"])
        XCTAssertEqual(sheet.revealRequest?.lineID, lineID(sheet, 3))
        undoes("Ajouter des lignes")
        sheet.clear()
        XCTAssertEqual(sheet.source, "")
        XCTAssertTrue(sheet.formulaLines.isEmpty)
        undoes("Effacer la feuille")
        sheet.editAsText("x = 1")
        XCTAssertEqual(sheet.source, "x = 1")
        undoes("Modifier en texte")
        let added = try XCTUnwrap(sheet.appendFormula("g"))
        XCTAssertEqual(sheet.source, original + "\ng =")
        XCTAssertEqual(sheet.lineIndex(of: added), 3)
        undoes("Ajouter une formule")
        XCTAssertFalse(sheet.canUndo)
    }

    func testActionsThatChangeNothingLeaveNoStep() {
        let sheet = makeSession("a = 1\nb = 2")
        sheet.removeLine(id: UUID())
        sheet.removeLines(atOffsets: [5])
        sheet.moveLines(fromOffsets: [0], toOffset: 1)
        sheet.appendLines(["", " "])
        sheet.setDisplayUnit(nil, lineID: lineID(sheet, 0))
        sheet.simplifyLine(id: lineID(sheet, 0))
        XCTAssertFalse(sheet.canUndo)
    }

    func testAppendLinesReplacesABlankLastLine() {
        let sheet = makeSession("a = 1\n")
        sheet.appendLines(["b = 2"])
        XCTAssertEqual(sheet.source, "a = 1\nb = 2")
    }

    func testANewStepClearsRedo() {
        let sheet = makeSession("a = 1\nb = 2")
        sheet.removeLine(id: lineID(sheet, 1))
        XCTAssertTrue(sheet.undo())
        XCTAssertTrue(sheet.canRedo)
        sheet.appendLines(["c = 3"])
        XCTAssertFalse(sheet.canRedo)
        XCTAssertFalse(sheet.redo())
        XCTAssertEqual(sheet.undoActionName, "Ajouter une ligne")
    }

    func testAStepIsRefusedAfterAChangeWithoutStep() {
        let sheet = makeSession("a = 1\nb = 2")
        sheet.removeLine(id: lineID(sheet, 1))
        sheet.source = "z = 9"
        XCTAssertFalse(sheet.undo())
        XCTAssertFalse(sheet.canUndo)
        XCTAssertFalse(sheet.canRedo)
        XCTAssertEqual(sheet.source, "z = 9")
    }

    func testUndoKeepsTheLatestFiftySteps() {
        let sheet = makeSession("")
        for index in 0..<60 { sheet.appendLines(["x\(index) = \(index)"]) }
        var undone = 0
        while sheet.undo() { undone += 1 }
        XCTAssertEqual(undone, 50)
        XCTAssertEqual(sheet.resultSelection.entries.count, 10)
        sheet.levelsOfUndo = 3
        XCTAssertEqual(sheet.redoActionName, "Ajouter une ligne")
        var redone = 0
        while sheet.redo() { redone += 1 }
        XCTAssertEqual(redone, 3)
    }

    func testRemovingUndoStepsForgetsThem() {
        let sheet = makeSession("a = 1\nb = 2")
        sheet.removeLine(id: lineID(sheet, 1))
        sheet.removeAllUndoSteps()
        XCTAssertFalse(sheet.canUndo)
        XCTAssertNil(sheet.undoActionName)
    }

    // MARK: Line identity

    func testLinesKeepTheirIdentityAndResultsThroughEdits() throws {
        let sheet = makeSession("a = 2\na * 3 =")
        let a = lineID(sheet, 0)
        let b = lineID(sheet, 1)
        evaluate(sheet)
        XCTAssertEqual(sheet.result(for: b)?.formattedValue, "6")

        let inserted = try XCTUnwrap(sheet.insertLines(["c = 1"], at: 0))
        sheet.endEditing(inserted)
        XCTAssertEqual(lineIDs(sheet), [inserted.lineID, a, b])
        XCTAssertEqual(sheet.lineIndex(of: b), 2)
        // Inserting above keeps the result of the line, before any new evaluation.
        XCTAssertEqual(sheet.result(for: b)?.formattedValue, "6")
        XCTAssertFalse(sheet.isResultStale(for: b))

        sheet.moveLines(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(lineIDs(sheet), [b, inserted.lineID, a])
        XCTAssertEqual(sheet.lineSource(of: b), "a * 3 =")
        XCTAssertEqual(sheet.formulaLines.map(\.index), [0, 1, 2])

        let copy = try XCTUnwrap(sheet.duplicateLine(id: b))
        XCTAssertEqual(lineIDs(sheet), [b, copy, inserted.lineID, a])
        XCTAssertNil(sheet.result(for: copy))
        evaluate(sheet)
        XCTAssertEqual(sheet.result(for: copy)?.formattedValue, "6")
    }

    func testMovingEqualLinesSwapsTheirIdentities() {
        let sheet = makeSession("x + 1\nx + 1")
        let ids = lineIDs(sheet)
        evaluate(sheet)
        sheet.moveLines(fromOffsets: [0], toOffset: 2)
        XCTAssertEqual(sheet.source, "x + 1\nx + 1")
        XCTAssertEqual(lineIDs(sheet), [ids[1], ids[0]])
        XCTAssertEqual(sheet.formulaLines.map(\.id), [ids[1], ids[0]])
        XCTAssertEqual(sheet.lineIndex(of: ids[0]), 1)
        XCTAssertEqual(sheet.undoActionName, "Déplacer la ligne")
        XCTAssertTrue(sheet.needsEvaluation)
    }

    func testBlankLinesKeepTheirPlaceWhenLinesMove() {
        let sheet = makeSession("a = 1\n\nb = 2\nc = 3")
        XCTAssertEqual(sheet.formulaLines.map(\.index), [0, 2, 3])
        sheet.moveLines(fromOffsets: [2], toOffset: 0)
        XCTAssertEqual(sheet.source, "c = 3\n\na = 1\nb = 2")
        sheet.removeLines(atOffsets: [1])
        XCTAssertEqual(sheet.source, "c = 3\n\nb = 2")
    }

    // MARK: Display unit and simplification

    func testDisplayUnitIsOneStep() {
        let sheet = makeSession("v = 72 km/h\nv =")
        let id = lineID(sheet, 1)
        sheet.setDisplayUnit("m/s", lineID: id)
        XCTAssertEqual(sheet.lineSource(of: id), LineSyntax("v =").replacingConversion("m/s"))
        XCTAssertEqual(sheet.undoActionName, "Changer l’unité d’affichage")
        evaluate(sheet)
        XCTAssertEqual(sheet.result(for: id)?.formattedValue, "20 m/s")
        sheet.setDisplayUnit(nil, lineID: id)
        XCTAssertEqual(sheet.lineSource(of: id), "v =")
        XCTAssertEqual(lineID(sheet, 1), id)
        XCTAssertTrue(sheet.undo())
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "v = 72 km/h\nv =")
    }

    func testSimplificationRewritesTheLineAsOneStep() {
        let sheet = makeSession("m = 2 kg\nE = 0,5 * m * v^2 * 2 / m\nF = m")
        let id = lineID(sheet, 1)
        XCTAssertEqual(sheet.simplification(of: id), "E = v²")
        XCTAssertNil(sheet.simplification(of: lineID(sheet, 2)))
        XCTAssertNil(sheet.simplification(of: UUID()))
        sheet.simplifyLine(id: id)
        XCTAssertEqual(sheet.lineSource(of: id), "E = v²")
        XCTAssertEqual(sheet.undoActionName, "Simplifier la ligne")
        XCTAssertNil(sheet.simplification(of: id))
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.lineSource(of: id), "E = 0,5 * m * v^2 * 2 / m")
    }

    // MARK: Rulers

    func testARulerGestureIsOneStep() throws {
        let sheet = makeSession("v = 5 m/s\nd = v * 2 s =")
        let v = lineID(sheet, 0)
        let variable = try XCTUnwrap(sheet.variable(for: v))
        XCTAssertEqual(sheet.adjustableVariables.map(\.id), [v])
        XCTAssertEqual(sheet.rulerStep(for: v, variable: variable), 1)

        sheet.beginRulerGesture(lineID: v)
        sheet.adjustVariable(6, lineID: v)
        sheet.adjustVariable(7, lineID: v)
        XCTAssertFalse(sheet.canUndo)
        XCTAssertFalse(sheet.evaluationRequest.isDebounced)
        sheet.adjustVariable(8, lineID: v)
        sheet.endRulerGesture()
        XCTAssertEqual(sheet.source, "v = 8 m/s\nd = v * 2 s =")
        XCTAssertEqual(lineID(sheet, 0), v)
        XCTAssertEqual(sheet.undoActionName, "Ajuster v")
        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.source, "v = 5 m/s\nd = v * 2 s =")
        XCTAssertFalse(sheet.canUndo)

        // Outside a gesture, each adjustment is its own step.
        sheet.adjustVariable(9, lineID: v)
        XCTAssertEqual(sheet.source, "v = 9 m/s\nd = v * 2 s =")
        XCTAssertEqual(sheet.undoActionName, "Ajuster v")
        XCTAssertTrue(sheet.undo())
        XCTAssertFalse(sheet.canUndo)

        // A line that declares no number has no ruler.
        sheet.beginRulerGesture(lineID: lineID(sheet, 1))
        sheet.adjustVariable(3, lineID: lineID(sheet, 1))
        sheet.endRulerGesture()
        XCTAssertFalse(sheet.canUndo)
    }

    func testRulerSettingsAreOneStep() throws {
        let sheet = makeSession("v = 5 m/s\nd = v * 2 s =")
        let v = lineID(sheet, 0)
        let variable = try XCTUnwrap(sheet.variable(for: v))
        XCTAssertEqual(sheet.adjustmentRange(for: v, variable: variable),
                       VariableAdjustmentRange.suggested(for: 5, step: 1))
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 100, step: 5))

        sheet.setAdjustmentRange(range, for: v, automaticStep: false)
        XCTAssertEqual(sheet.undoActionName, "Régler le curseur de v")
        XCTAssertEqual(sheet.adjustmentRange(for: v, variable: variable), range)
        XCTAssertEqual(sheet.rulerStep(for: v, variable: variable), 5)
        XCTAssertEqual(sheet.record.manualStepIDs, [v])

        sheet.setAdjustmentRange(range, for: v)
        XCTAssertEqual(sheet.rulerStep(for: v, variable: variable), 1)
        XCTAssertEqual(sheet.adjustmentRange(for: v, variable: variable),
                       VariableAdjustmentRange(lowerBound: 0, upperBound: 100, step: 1))

        XCTAssertTrue(sheet.undo())
        XCTAssertEqual(sheet.rulerStep(for: v, variable: variable), 5)
        XCTAssertTrue(sheet.undo())
        XCTAssertTrue(sheet.adjustmentRanges.isEmpty)
        XCTAssertTrue(sheet.manualStepIDs.isEmpty)

        sheet.setAdjustmentRange(range, for: lineID(sheet, 1))
        XCTAssertFalse(sheet.canUndo)
    }

    func testARulerKeepsItsSettingsWhileItsValueChanges() throws {
        let sheet = makeSession("v = 5 m/s")
        let v = lineID(sheet, 0)
        let range = try XCTUnwrap(VariableAdjustmentRange(lowerBound: 0, upperBound: 100, step: 5))
        sheet.setAdjustmentRange(range, for: v, automaticStep: false)
        sheet.adjustVariable(10, lineID: v)
        XCTAssertEqual(sheet.adjustmentRanges[v], range)
        sheet.clear()
        XCTAssertEqual(sheet.adjustmentRanges[v], range)
    }

    func testEditingALineClosesTheRuler() throws {
        let sheet = makeSession("v = 5 m/s\nd = v * 2 s =")
        let v = lineID(sheet, 0)
        sheet.showRuler(lineID: lineID(sheet, 1))
        XCTAssertNil(sheet.activeRulerLineID)
        sheet.showRuler(lineID: v)
        XCTAssertEqual(sheet.activeRulerLineID, v)
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: lineID(sheet, 1)))
        XCTAssertNil(sheet.activeRulerLineID)
        sheet.endEditing(editing)

        // The ruler closes when its line no longer declares a number.
        sheet.showRuler(lineID: v)
        sheet.editAsText("v = 2 * 3 m/s\nd = v * 2 s =")
        XCTAssertNil(sheet.activeRulerLineID)
    }

    func testPlotVariablesAreTheRulersAResultDependsOn() {
        let sheet = makeSession("v = 5 m/s\nt = 2 s\nd = v * t =\nk = 3")
        let ids = lineIDs(sheet)
        XCTAssertTrue(sheet.plotVariables(for: ids[2]).isEmpty)
        evaluate(sheet)
        XCTAssertEqual(sheet.plotVariables(for: ids[2]).map(\.id), [ids[0], ids[1]])
        XCTAssertTrue(sheet.plotVariables(for: ids[0]).isEmpty)
    }

    // MARK: Evaluation

    func testEvaluationRequestsFollowChanges() throws {
        let sheet = makeSession("a = 2\nb = a * 3 =")
        XCTAssertTrue(sheet.needsEvaluation)
        XCTAssertFalse(sheet.hasEvaluation)
        XCTAssertFalse(sheet.evaluationRequest.isDebounced)
        XCTAssertEqual(sheet.evaluationRequest.lineIDs, lineIDs(sheet))
        evaluate(sheet)
        XCTAssertTrue(sheet.hasEvaluation)
        XCTAssertFalse(sheet.needsEvaluation)

        let revision = sheet.evaluationRequest.revision
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: lineID(sheet, 1)))
        sheet.updateLine("b = a * 4 =", lineID: editing.lineID)
        XCTAssertTrue(sheet.needsEvaluation)
        XCTAssertTrue(sheet.evaluationRequest.isDebounced)
        XCTAssertGreaterThan(sheet.evaluationRequest.revision, revision)
        sheet.endEditing(editing)

        // Undo and redo do not wait for the typing delay.
        XCTAssertTrue(sheet.undo())
        XCTAssertFalse(sheet.evaluationRequest.isDebounced)
        // Back to the text already shown.
        XCTAssertFalse(sheet.needsEvaluation)
    }

    func testAnEvaluationOfAnEarlierTextLeavesStaleResults() throws {
        let sheet = makeSession("a = 2\nb = a * 3 =")
        let b = lineID(sheet, 1)
        let first = SheetSession.evaluate(sheet.evaluationRequest)
        // Typing goes on while the first evaluation runs.
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: b))
        sheet.updateLine("b = a * 4 =", lineID: b)

        XCTAssertFalse(sheet.apply(first, onlyIfCurrent: true))
        XCTAssertNil(sheet.result(for: b))
        XCTAssertFalse(sheet.hasEvaluation)

        XCTAssertTrue(sheet.apply(first))
        XCTAssertEqual(sheet.result(for: b)?.formattedValue, "6")
        XCTAssertTrue(sheet.isResultStale(for: b))
        XCTAssertFalse(sheet.isResultStale(for: lineID(sheet, 0)))
        XCTAssertTrue(sheet.needsEvaluation)
        XCTAssertNil(sheet.resultPreview)
        XCTAssertEqual(sheet.declaredNames, ["a", "b"])

        let second = SheetSession.evaluate(sheet.evaluationRequest)
        XCTAssertTrue(sheet.apply(second, onlyIfCurrent: true))
        XCTAssertEqual(sheet.result(for: b)?.formattedValue, "8")
        XCTAssertFalse(sheet.isResultStale(for: b))
        XCTAssertFalse(sheet.needsEvaluation)
        XCTAssertEqual(sheet.resultPreview, "b = 8")
        XCTAssertNotNil(sheet.spokenResultPreview)

        // An earlier evaluation that finishes late never replaces a later one.
        XCTAssertFalse(sheet.apply(first))
        XCTAssertEqual(sheet.result(for: b)?.formattedValue, "8")
        sheet.endEditing(editing)
    }

    func testResultsOfRemovedLinesGoAway() {
        let sheet = makeSession("a = 2\nb = a * 3 =")
        let b = lineID(sheet, 1)
        sheet.removeLine(id: b)
        evaluate(sheet)
        XCTAssertNil(sheet.result(for: b))
        XCTAssertFalse(sheet.isResultStale(for: b))
    }

    func testConstantsAndUnitsComeFromTheEvaluation() {
        let sheet = makeSession("E = m * c^2 =\nm = 1 kg")
        evaluate(sheet)
        XCTAssertEqual(sheet.constants.map(\.symbol), ["c"])
        XCTAssertNil(sheet.sheetIssue)
    }

    func testARulerAdjustmentAnnouncesTheResultsOnce() throws {
        let sheet = makeSession("v = 5 m/s\nd = v * 2 s =")
        let v = lineID(sheet, 0)
        evaluate(sheet)
        sheet.adjustVariable(6, lineID: v, announcesResults: true)
        let outdated = SheetSession.evaluate(sheet.evaluationRequest)
        sheet.adjustVariable(7, lineID: v, announcesResults: true)
        XCTAssertTrue(sheet.apply(outdated))
        XCTAssertNil(sheet.takeAnnouncement())
        evaluate(sheet)
        let spoken = try XCTUnwrap(sheet.result(for: lineID(sheet, 1))?.spokenResult)
        XCTAssertEqual(sheet.takeAnnouncement(), ResultText.spokenLine(source: "d = v * 2 s =", spokenValue: spoken))
        XCTAssertNil(sheet.takeAnnouncement())

        sheet.adjustVariable(8, lineID: v)
        evaluate(sheet)
        XCTAssertNil(sheet.takeAnnouncement())
    }

    // MARK: Titles

    func testACustomTitleIsTrimmedAndEndsAutomaticNaming() {
        var records: [SheetRecord] = []
        let sheet = makeSession("x = 2") { records.append($0) }
        sheet.customTitle = "  Mécanique \n"
        XCTAssertEqual(sheet.customTitle, "Mécanique")
        XCTAssertEqual(sheet.displayTitle, "Mécanique")
        XCTAssertEqual(records.last?.customTitle, "Mécanique")
        XCTAssertEqual(records.last?.automaticTitleAttempted, true)
        sheet.customTitle = "Mécanique"
        XCTAssertEqual(records.count, 1)
        sheet.customTitle = "   "
        XCTAssertNil(sheet.customTitle)
        XCTAssertEqual(sheet.displayTitle, SheetRecord.untitledTitle)
        sheet.applyAutomaticTitle("Énergie")
        XCTAssertNil(sheet.customTitle)
        // A title is not an undoable change.
        XCTAssertFalse(sheet.canUndo)
    }

    func testAnAutomaticTitleNamesAnUntitledSheetOnce() {
        let modified = Date(timeIntervalSince1970: 1_000)
        let sheet = SheetSession(record: SheetRecord(source: "m = 2 kg\nv = 3 m/s\nE = 0,5 * m * v^2 =",
                                                     createdAt: modified))
        XCTAssertTrue(AutomaticSheetTitle.isEligible(sheet.record))
        sheet.applyAutomaticTitle("Énergie cinétique")
        XCTAssertEqual(sheet.customTitle, "Énergie cinétique")
        XCTAssertEqual(sheet.displayTitle, "Énergie cinétique")
        XCTAssertEqual(sheet.modifiedAt, modified)
        XCTAssertFalse(AutomaticSheetTitle.isEligible(sheet.record))
        sheet.applyAutomaticTitle("Autre")
        XCTAssertEqual(sheet.customTitle, "Énergie cinétique")
    }

    func testAnAutomaticTitleKeepsANoteTitle() {
        let sheet = makeSession("# Chute libre\nh = 2 m")
        sheet.applyAutomaticTitle("Autre")
        XCTAssertNil(sheet.customTitle)
        XCTAssertEqual(sheet.displayTitle, "Chute libre")
        XCTAssertTrue(sheet.record.automaticTitleAttempted)

        let unnamed = makeSession("x = 2")
        unnamed.applyAutomaticTitle(nil)
        XCTAssertNil(unnamed.customTitle)
        XCTAssertTrue(unnamed.record.automaticTitleAttempted)
    }

    func testRenamingToTheAutomaticTitleRestoresIt() {
        let sheet = makeSession("# Chute libre\nh = 2 m")
        sheet.rename(to: " Chute libre ")
        XCTAssertNil(sheet.customTitle)
        sheet.rename(to: "Projectile")
        XCTAssertEqual(sheet.customTitle, "Projectile")
        // Once named, the note title is a title like any other.
        sheet.rename(to: "Chute libre")
        XCTAssertEqual(sheet.customTitle, "Chute libre")
        sheet.rename(to: "")
        XCTAssertNil(sheet.customTitle)

        let untitled = makeSession("x = 2")
        untitled.rename(to: SheetRecord.untitledTitle)
        XCTAssertNil(untitled.customTitle)
    }

    func testTheTitleFollowsTheFirstNote() {
        let sheet = makeSession("x = 2")
        sheet.editAsText("# Optique\nn = 1,5")
        XCTAssertEqual(sheet.displayTitle, "Optique")
    }

    // MARK: Record

    func testChangesReachTheLibraryButNotTheInitialState() throws {
        var records: [SheetRecord] = []
        let original = SheetRecord(source: "a = 1", createdAt: Date(timeIntervalSince1970: 0))
        let sheet = SheetSession(record: original) { records.append($0) }
        XCTAssertTrue(records.isEmpty)
        XCTAssertEqual(sheet.record, original)

        sheet.appendLines(["b = 2"])
        let last = try XCTUnwrap(records.last)
        XCTAssertEqual(last.id, original.id)
        XCTAssertEqual(last.source, "a = 1\nb = 2")
        XCTAssertEqual(last.resultSelection, sheet.resultSelection)
        XCTAssertGreaterThan(last.modifiedAt, original.modifiedAt)

        sheet.close()
        let count = records.count
        sheet.appendLines(["c = 3"])
        sheet.applyAutomaticTitle("Titre")
        XCTAssertEqual(records.count, count)
        XCTAssertFalse(sheet.apply(SheetSession.evaluate(sheet.evaluationRequest)))
    }

    func testAppendAsksForTheValueWithoutAStep() throws {
        let sheet = makeSession("a = 1")
        let id = try XCTUnwrap(sheet.append("c"))
        XCTAssertEqual(sheet.source, "a = 1\nc =")
        XCTAssertEqual(sheet.revealRequest?.lineID, id)
        sheet.append("x = 2", requestsResult: false)
        XCTAssertEqual(sheet.source, "a = 1\nc =\nx = 2")
        XCTAssertFalse(sheet.canUndo)
    }

    // MARK: Shared text

    func testSharedTextAddsCurrentValuesAsNotes() throws {
        let sheet = makeSession("a = 2\nb = a * 3 =\nc = a * 4 = # déjà\n# Note")
        XCTAssertEqual(sheet.sharedText(includingResults: true), sheet.source)
        evaluate(sheet)
        XCTAssertEqual(sheet.sharedText(includingResults: true), "a = 2\nb = a * 3 =  # 6\nc = a * 4 = # déjà\n# Note")
        XCTAssertEqual(sheet.sharedText(includingResults: false), sheet.source)

        // A line edited since its evaluation is shared without its old value.
        let editing = try XCTUnwrap(sheet.beginEditing(lineID: lineID(sheet, 1)))
        sheet.updateLine("b = a * 5 =", lineID: editing.lineID)
        XCTAssertEqual(sheet.sharedText(includingResults: true), "a = 2\nb = a * 5 =\nc = a * 4 = # déjà\n# Note")
        sheet.endEditing(editing)
    }
}
