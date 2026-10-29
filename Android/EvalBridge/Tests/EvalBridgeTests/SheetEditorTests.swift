import EvalCore
import Foundation
import Testing
@testable import EvalBridge

@Suite struct SheetEditorTests {
    private func makeEditor(_ source: String) -> SheetEditor {
        SheetEditor(record: SheetRecord(source: source), library: nil)
    }

    /// Evaluates the current text and shows it, as the app does once the delay is over.
    private func evaluate(_ editor: SheetEditor) {
        #expect(editor.applyEvaluation(SheetEditor.evaluate(editor.evaluationRequest())))
    }

    // MARK: Lines

    @Test func linesShowWhatIOSShows() throws {
        let editor = makeEditor("# Énergie\nE = 0,5 * m * v²\nm = 80 kg\nv = 5 m/s\n\nE =\nv → km/h\n1 km == 1000 m")
        #expect(!editor.hasEvaluation)
        evaluate(editor)
        let lines = editor.lines()
        // The blank line is hidden; indexes still count it.
        #expect(lines.map(\.index) == [0, 1, 2, 3, 5, 6, 7])
        #expect(lines[0].isComment && lines[0].isHeading && lines[0].noteText == "Énergie")
        #expect(lines[0].notes.isEmpty && lines[0].value == nil)
        #expect(lines[1].value == nil)
        #expect(lines[1].kind == "definition" && lines[1].status == "success")
        #expect(lines[2].isAdjustable && lines[2].variableName == "m")
        #expect(lines[4].value == "1000 J" && lines[4].valueLabel == "1000 J" && !lines[4].isStale)
        #expect(lines[5].valueLabel == "= 18 km/h")
        // An equality shows its verdict, never a value.
        #expect(lines[6].value == nil && lines[6].kind == "equation")
        #expect(lines[6].notes.first?.style == "verified")
        #expect(lines[6].notes.first?.text == "Égalité vérifiée.")
        #expect(editor.line(id: lines[4].id) == lines[4])
        #expect(editor.line(id: "inconnue") == nil)
    }

    @Test func notesAndSpokenLabelsFollowTheLine() {
        let editor = makeEditor("1 km == 2 m\n2 m + 3 s =\n// une remarque\nm = 2 kg")
        evaluate(editor)
        let lines = editor.lines()
        #expect(lines[0].notes.first?.style == "equalityError")
        #expect(lines[1].status == "error" && lines[1].notes.first?.style == "error")
        #expect(lines[1].accessibilityLabel.contains("Erreur : "))
        #expect(lines[2].isComment && !lines[2].isHeading && lines[2].noteText == "une remarque")
        #expect(lines[2].accessibilityLabel == "Ligne 3, note : // une remarque")
        #expect(lines[3].accessibilityLabel == "Valeur de m")
        #expect(lines[3].accessibilityValue?.contains("kilogramme") == true)
    }

    @Test func aLongSheetReportsTheLimitOnItsFirstFormula() {
        let editor = makeEditor(String(repeating: "x = 1\n", count: SheetEditor.maximumLineCount) + "y = x =")
        evaluate(editor)
        let first = editor.lines()[0]
        #expect(first.status == "error")
        #expect(first.message?.hasPrefix("Feuille trop longue") == true)
    }

    // MARK: Evaluation

    @Test func evaluationIsHandedOffToAnotherThread() async {
        let editor = makeEditor("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v² =")
        #expect(editor.needsEvaluation)
        let request = editor.evaluationRequest()
        #expect(!request.isDebounced)
        let evaluation = await Task.detached { SheetEditor.evaluate(request) }.value
        #expect(evaluation.revision == request.revision)
        #expect(editor.applyEvaluation(evaluation))
        #expect(!editor.needsEvaluation)
        #expect(editor.lines()[2].value == "1000 J")
        #expect(editor.resultPreview == "E = 1000 J")
    }

    @Test func anEditedLineKeepsItsStaleValueUntilTheNextEvaluation() throws {
        let editor = makeEditor("m = 2\nE = m * 3 =")
        evaluate(editor)
        let line = editor.lines()[1]
        #expect(editor.beginEditing(lineId: line.id))
        #expect(editor.updateEditedLine("E = m * 4 =") == line.id)
        #expect(editor.evaluationRequest().isDebounced)
        #expect(editor.needsEvaluation)
        let edited = try #require(editor.line(id: line.id))
        #expect(edited.isEditing && edited.isStale && edited.value == "6")
        #expect(edited.editingNotes.map(\.style) == ["staleValue"])

        evaluate(editor)
        let updated = try #require(editor.line(id: line.id))
        #expect(!updated.isStale && updated.value == "8")
        #expect(updated.editingNotes.map(\.text) == ["= 8"])
        editor.endEditing()
        #expect(editor.undoActionName == "Modifier la ligne")
    }

    @Test func lateEvaluationsAreIgnored() {
        let editor = makeEditor("m = 2\nE = m * 3 =")
        let older = SheetEditor.evaluate(editor.evaluationRequest())
        editor.editAsText("m = 3\nE = m * 3 =")
        let newer = SheetEditor.evaluate(editor.evaluationRequest())
        #expect(newer.revision > older.revision)
        #expect(editor.applyEvaluation(newer))
        #expect(!editor.applyEvaluation(older))
        #expect(editor.lines()[1].value == "9")
        // The iOS default shows an evaluation of an earlier text; on request it is refused.
        let stale = SheetEditor.evaluate(editor.evaluationRequest())
        editor.editAsText("m = 4\nE = m * 3 =")
        #expect(!editor.applyEvaluation(stale, onlyIfCurrent: true))
        #expect(editor.applyEvaluation(stale))
        #expect(editor.needsEvaluation)
    }

    @Test func constantsAndSymbolsReadAsUnitsAreListed() {
        let editor = makeEditor("p = 101325 Pa\nV = 24 L\nn = 1 mol\np*V/(n*R*T) =")
        evaluate(editor)
        #expect(editor.recognizedConstants().map(\.id) == ["R"])
        #expect(editor.recognizedConstants().first?.name == "Constante des gaz parfaits")
        let units = editor.symbolUnits()
        #expect(units.map(\.symbol) == ["T"])
        #expect(units.first?.name == "Tesla")
        #expect(editor.declaredNames == ["V", "n", "p"])
    }

    @Test func sharedTextCarriesTheCurrentValues() {
        let editor = makeEditor("m = 2 kg\nm * 3 =")
        evaluate(editor)
        #expect(editor.sharedText(includingResults: true) == "m = 2 kg\nm * 3 =  # 6 kg")
        #expect(editor.sharedText(includingResults: false) == "m = 2 kg\nm * 3 =")
    }

    // MARK: Editing in place

    @Test func returnSplitsTheEditedLineAndEndsOnABlankOne() throws {
        let editor = makeEditor("a = 1")
        let first = try #require(editor.newLine())
        #expect(editor.editingLineId == first)
        #expect(editor.lines().last?.id == first)

        let next = try #require(editor.updateEditedLine("b = 2\nc = b * 3 ="))
        #expect(next != first)
        #expect(editor.editingLineId == next)
        #expect(editor.source == "a = 1\nb = 2\nc = b * 3 =")
        #expect(editor.revealRequest?.lineId == next)

        // Return at the end of a line opens a blank one; Return there stops editing.
        let blank = try #require(editor.updateEditedLine("c = b * 3 =\n"))
        #expect(editor.lines().last?.id == blank)
        #expect(editor.updateEditedLine("\n") == nil)
        #expect(editor.editingLineId == nil)
        #expect(editor.source == "a = 1\nb = 2\nc = b * 3 =")

        #expect(editor.undoActionName == "Ajouter une ligne")
        #expect(editor.undo())
        #expect(editor.source == "a = 1\nb = 2")
        #expect(editor.redoActionName == "Ajouter une ligne")
        #expect(editor.redo())
        #expect(editor.source == "a = 1\nb = 2\nc = b * 3 =")
    }

    @Test func undoValidatesTheEditedLineFirst() throws {
        let editor = makeEditor("x = 1")
        #expect(editor.beginEditing(lineId: editor.lines()[0].id))
        editor.updateEditedLine("x = 2")
        #expect(!editor.canUndo)
        #expect(editor.undo())
        #expect(editor.source == "x = 1")
        #expect(editor.editingLineId == nil)
        #expect(editor.canRedo && editor.redoActionName == "Modifier la ligne")
        #expect(!editor.beginEditing(lineId: "inconnue"))
    }

    @Test func insertedLinesAreEditedBelowTheirAnchor() throws {
        let editor = makeEditor("a = 1\nc = 3")
        let anchor = editor.lines()[0].id
        let inserted = try #require(editor.insertLinesAfter(["b = 2", "b2 = 4"], lineId: anchor))
        #expect(editor.editingLineId == inserted)
        #expect(editor.source == "a = 1\nb = 2\nb2 = 4\nc = 3")
        editor.endEditing()
        #expect(editor.undoActionName == "Ajouter une ligne")
        let atStart = try #require(editor.insertLines(["z = 0"], position: 0))
        #expect(editor.lines()[0].id == atStart)
    }

    // MARK: Line actions

    @Test func lineActionsAreNamedUndoSteps() throws {
        let editor = makeEditor("a = 1\n\nb = 2\nc = a + b =")
        let ids = editor.lines().map(\.id)
        #expect(ids.count == 3)

        // Blank lines keep their place, identities follow their lines.
        editor.moveLines(fromOffsets: [2], toOffset: 0)
        #expect(editor.source == "c = a + b =\n\na = 1\nb = 2")
        #expect(editor.lines().map(\.id) == [ids[2], ids[0], ids[1]])
        #expect(editor.undoActionName == "Déplacer la ligne")

        let copy = try #require(editor.duplicateLine(id: ids[0]))
        #expect(editor.source == "c = a + b =\n\na = 1\na = 1\nb = 2")
        #expect(editor.revealRequest?.lineId == copy)
        #expect(editor.undoActionName == "Dupliquer la ligne")

        editor.removeLines(atOffsets: [1, 2])
        #expect(editor.source == "c = a + b =\n\nb = 2")
        #expect(editor.undoActionName == "Supprimer les lignes")
        editor.removeLine(id: ids[1])
        #expect(editor.undoActionName == "Supprimer la ligne")
        #expect(editor.undo())
        #expect(editor.source == "c = a + b =\n\nb = 2")

        editor.clear()
        #expect(editor.isEmpty)
        #expect(editor.undoActionName == "Effacer la feuille")
    }

    @Test func aRemovedEditedLineDoesNotShiftOffsets() {
        let editor = makeEditor("a = 1\nb = 2\nc = 3")
        let ids = editor.lines().map(\.id)
        _ = editor.insertLines([""], position: 1)
        #expect(editor.lines().count == 4)
        // The blank edited line goes away when its editing ends, before the deletion.
        editor.removeLines(atOffsets: [2])
        #expect(editor.source == "a = 1\nc = 3")
        #expect(editor.lines().map(\.id) == [ids[0], ids[2]])
    }

    @Test func theLineMenuOffersWhatIOSOffers() throws {
        let editor = makeEditor("v = 5 m/s =\n(a * b) / a =\n# Note")
        evaluate(editor)
        let lines = editor.lines()
        let menu = try #require(editor.lineMenu(lineId: lines[0].id))
        #expect(menu.copyValue == "5 m·s⁻¹")
        #expect(menu.copyLine == "v = 5 m·s⁻¹")
        #expect(menu.displayUnits.contains("km/h") && menu.currentDisplayUnit == nil)
        #expect(menu.hasRuler && menu.formula == "v = 5 m/s =")

        editor.setDisplayUnit("km/h", lineId: lines[0].id)
        #expect(editor.undoActionName == "Changer l’unité d’affichage")
        evaluate(editor)
        #expect(editor.line(id: lines[0].id)?.value == "18 km/h")
        #expect(editor.lineMenu(lineId: lines[0].id)?.currentDisplayUnit == "km/h")
        editor.setDisplayUnit(nil, lineId: lines[0].id)
        #expect(editor.source.hasPrefix("v = 5 m/s =\n"))

        #expect(editor.lineMenu(lineId: lines[1].id)?.simplified == "b =")
        #expect(editor.simplification(lineId: lines[1].id) == "b =")
        editor.simplifyLine(id: lines[1].id)
        #expect(editor.line(id: lines[1].id)?.source == "b =")
        #expect(editor.undoActionName == "Simplifier la ligne")

        let note = try #require(editor.lineMenu(lineId: lines[2].id))
        #expect(note.isComment && note.simplified == nil && note.displayUnits.isEmpty && !note.hasRuler)
    }

    @Test func formulasAndLinesAreAppendedAtTheEnd() throws {
        let editor = makeEditor("x = 1\n")
        let id = try #require(editor.appendFormula("c"))
        #expect(editor.source == "x = 1\nc =")
        #expect(editor.undoActionName == "Ajouter une formule")
        #expect(editor.revealRequest?.lineId == id)
        editor.appendLines(["y = 2", " ", "z = 3"])
        #expect(editor.source == "x = 1\nc =\ny = 2\nz = 3")
        #expect(editor.undoActionName == "Ajouter des lignes")
    }

    // MARK: Rulers

    @Test func aRulerGestureIsOneUndoStep() throws {
        let editor = makeEditor("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v² =")
        evaluate(editor)
        let mass = editor.lines()[0].id
        let ruler = try #require(editor.ruler(lineId: mass))
        #expect(ruler.name == "m" && ruler.value == 80 && ruler.unit == "kg")
        #expect(ruler.step == 1 && ruler.usesAutomaticStep && ruler.valueText == "80 kg")
        #expect(ruler.lowerBound == 0 && ruler.upperBound == 160)
        #expect(editor.ruler(lineId: editor.lines()[2].id) == nil)

        editor.showRuler(lineId: mass)
        #expect(editor.activeRulerLineId == mass && editor.lines()[0].isRulerOpen)
        editor.beginRulerGesture(lineId: mass)
        editor.adjustVariable(lineId: mass, value: SheetEditor.steppedValue(from: 80, steps: 2, step: ruler.step))
        #expect(!editor.evaluationRequest().isDebounced)
        editor.adjustVariable(lineId: mass, value: 83)
        editor.endRulerGesture()
        #expect(editor.source.hasPrefix("m = 83 kg\n"))
        #expect(editor.undoActionName == "Ajuster m")
        #expect(editor.undo())
        #expect(editor.source.hasPrefix("m = 80 kg\n"))

        // Editing a line closes the ruler.
        #expect(editor.beginEditing(lineId: editor.lines()[1].id))
        #expect(editor.activeRulerLineId == nil)
        editor.endEditing()
    }

    @Test func aStepIsAnnouncedOnceItsResultsArrive() throws {
        let editor = makeEditor("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v² =")
        evaluate(editor)
        let mass = editor.lines()[0].id
        editor.stepVariable(lineId: mass, steps: -1)
        #expect(editor.source.hasPrefix("m = 79 kg\n"))
        #expect(editor.undoActionName == "Ajuster m")
        #expect(editor.takeAnnouncement() == nil)
        evaluate(editor)
        let announcement = try #require(editor.takeAnnouncement())
        #expect(announcement.contains("987,5"))
        #expect(editor.takeAnnouncement() == nil)
    }

    @Test func rulerSettingsAreCheckedAndUndoable() throws {
        let editor = makeEditor("m = 80 kg")
        let mass = editor.lines()[0].id
        #expect(!editor.setRulerSettings(lineId: mass, lowerBound: 10, upperBound: 5, step: 1, usesAutomaticStep: true))
        #expect(!editor.setRulerSettings(lineId: mass, lowerBound: 0, upperBound: 10, step: 0, usesAutomaticStep: false))
        #expect(!editor.canUndo)
        #expect(editor.setRulerSettings(lineId: mass, lowerBound: 0, upperBound: 200, step: 5, usesAutomaticStep: false))
        let ruler = try #require(editor.ruler(lineId: mass))
        #expect(ruler.step == 5 && !ruler.usesAutomaticStep && ruler.upperBound == 200)
        #expect(editor.undoActionName == "Régler le curseur de m")
        let suggested = try #require(editor.suggestedRulerSettings(lineId: mass))
        #expect(suggested.lowerBound == 0 && suggested.upperBound == 160 && suggested.step == 1)
    }

    // MARK: Plots

    @Test func aResultIsPlottedAgainstARulerVariable() async throws {
        let editor = makeEditor("m = 80 kg\nv = 5 m/s\nE = 0,5 * m * v² =")
        evaluate(editor)
        let lines = editor.lines()
        let menu = try #require(editor.lineMenu(lineId: lines[2].id))
        #expect(menu.plotVariables.map(\.name) == ["m", "v"])
        #expect(menu.plotFreeVariable == nil)

        let input = editor.plotInput(resultLineId: lines[2].id, variableLineId: lines[1].id)
        #expect(input.resultName == "E" && input.resultUnit == "J" && input.currentResult == "1000 J")
        #expect(input.variableName == "v" && input.variableUnit == "m/s" && input.currentValue == 5)
        let plot = await Task.detached { SheetEditor.samplePlot(input) }.value
        #expect(plot.failure == nil)
        #expect(plot.lowerBound == 0 && plot.upperBound == 10)
        #expect(plot.segments.count == 1 && plot.segments[0].xs.count == 161)
        #expect(plot.segments[0].ys.last == 4000)

        let missing = editor.plotInput(resultLineId: lines[2].id, variableLineId: lines[2].id)
        #expect(SheetEditor.samplePlot(missing).failure == "missingLine")
    }

    @Test func anUndeclaredNameIsPlottedOverATypedInterval() throws {
        let editor = makeEditor("y = 2 * x =")
        evaluate(editor)
        let line = editor.lines()[0].id
        #expect(editor.lineMenu(lineId: line)?.plotFreeVariable == "x")
        let input = editor.freeVariablePlotInput(resultLineId: line, freeVariable: "x", lowerBound: -10, upperBound: 10)
        #expect(input.currentValue == nil && input.variableUnit == "")
        let plot = SheetEditor.samplePlot(input)
        #expect(plot.segments.first?.ys.first == -20)
        let empty = editor.freeVariablePlotInput(resultLineId: line, freeVariable: "x", lowerBound: 1, upperBound: 1)
        #expect(SheetEditor.samplePlot(empty).failure == "noRange")
    }
}

@Suite struct MathNodeTests {
    @Test func kineticEnergyIsARowWithAPowerAndAValue() throws {
        let node = try #require(MathNode.formula("E = 0,5 * m * v²"))
        #expect(node.kind == "row")
        #expect(node.children.contains { $0.kind == "atom" && $0.text == " = " })
        func kinds(_ node: MathNode) -> [String] { [node.kind] + node.children.flatMap(kinds) }
        #expect(kinds(node).contains("power"))
        #expect(MathNode.formula("m = 80 kg").map(kinds)?.contains("value") == true)
        #expect(MathNode.formula("# Note") == nil)
    }
}
