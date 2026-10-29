import EvalCore
import Foundation

/// One open sheet, for the Android app: the iOS `NotebookStore` through
/// `SheetSession`, with the line editing of `NotebookView`, where one line at a
/// time is edited in place. Lines are identified by UUID strings.
///
/// Main thread only, except the static `evaluate(_:)` and `samplePlot(_:)`, which
/// run on any thread. Every call updates the state at once: read it back after it.
/// Changes reach the library immediately; its `flush()` writes them.
public final class SheetEditor {
    /// The pause iOS waits for after typing before it evaluates.
    public static let typingDelayMillis: Int64 = 180
    /// How long an evaluation runs before iOS shows its progress indicator.
    public static let progressDelayMillis: Int64 = 250
    /// The engine evaluates sheets of at most 500 lines and 100 000 characters; a
    /// longer one gets the error « Feuille trop longue (…) » on its first formula,
    /// and no other result. Nothing stops typing beyond, as on iOS.
    public static let maximumLineCount: Int = 500
    public static let maximumCharacterCount: Int = 100_000
    /// A longer line gets the error « Ligne trop longue ».
    public static let maximumLineLength: Int = 2_000

    let session: SheetSession
    /// The line edited in place, from the moment it is touched to the loss of its focus.
    private var editing: SheetSession.EditingSession?
    /// Spoken forms of line texts, which take a parse each.
    private var speechCache: [String: String] = [:]

    init(record: SheetRecord, library: SheetLibrary?) {
        session = SheetSession(record: record) { [weak library] updated in
            library?.update(updated)
        }
    }

    public var id: String { session.id.uuidString }
    /// The custom title, else the first note, else « Nouvelle feuille ».
    public var title: String { session.displayTitle }
    public var customTitle: String? { session.customTitle }
    /// The whole text, one line per formula.
    public var source: String { session.source }
    /// Milliseconds since 1970.
    public var modifiedAt: Int64 { session.modifiedAt.millisecondsSince1970 }
    /// True once the sheet is deleted: the editor no longer changes anything.
    public var isClosed: Bool { session.isClosed }
    /// No line to show: iOS shows « Feuille vide » instead.
    public var isEmpty: Bool { session.formulaLines.isEmpty }

    /// Renames the sheet with the rule of the library: an empty title, or the
    /// sheet's own note title, restores the automatic title.
    public func rename(_ title: String) {
        session.rename(to: title)
    }

    func close() {
        editing = nil
        session.close()
    }

    // MARK: Lines

    /// The lines shown, in order: every line but blank ones, unless a blank line
    /// is being edited.
    public func lines() -> [LineState] {
        session.formulaLines.map { lineState(index: $0.index, entry: $0.entry) }
    }

    public func line(id: String) -> LineState? {
        guard let lineID = UUID(uuidString: id), let index = session.lineIndex(of: lineID) else { return nil }
        return lineState(index: index, entry: session.resultSelection.entries[index])
    }

    /// Asks the sheet to scroll to a line that was just added; each request has its own id.
    public var revealRequest: RevealRequest? {
        session.revealRequest.map { RevealRequest(id: $0.id.uuidString, lineId: $0.lineID.uuidString) }
    }

    // MARK: Editing in place

    /// The line whose field has the keyboard, if any.
    public var editingLineId: String? { editing?.lineID.uuidString }

    /// Starts editing a line, as a tap on it does: the line edited before is
    /// validated (one undo step), and the ruler closes.
    @discardableResult
    public func beginEditing(lineId: String) -> Bool {
        guard let lineID = UUID(uuidString: lineId) else { return false }
        if editing?.lineID == lineID { return true }
        endEditing()
        editing = session.beginEditing(lineID: lineID)
        return editing != nil
    }

    /// Validates the edited line, as the loss of its focus does: one undo step,
    /// « Ajouter une ligne », « Modifier la ligne » or « Supprimer la ligne »
    /// when it is left blank.
    public func endEditing() {
        guard let current = editing else { return }
        editing = nil
        session.endEditing(current)
    }

    /// A blank line at the end of the sheet, edited at once: « Nouvelle ligne ».
    /// Returns its id.
    @discardableResult
    public func newLine() -> String? {
        insertLines([""], position: nil)
    }

    /// The text of the edited line as typed. A line break, from Return or a paste
    /// of several lines, splits it: the line keeps the text before the break, the
    /// rest goes to new lines below, and the last of them is edited. Returns the
    /// line edited afterwards, or nil when editing stops (Return on a blank line).
    @discardableResult
    public func updateEditedLine(_ text: String) -> String? {
        guard let current = editing else { return nil }
        guard text.contains(where: \.isNewline) else {
            session.updateLine(text, lineID: current.lineID)
            return current.lineID.uuidString
        }
        editing = session.breakLine(text, session: current)
        return editing?.lineID.uuidString
    }

    /// Inserts lines at a position of the sheet (the end for nil) and edits the
    /// last of them, as after a scan from the keyboard bar. Returns its id.
    @discardableResult
    public func insertLines(_ sources: [String], position: Int?) -> String? {
        endEditing()
        editing = session.insertLines(sources, at: position)
        return editing?.lineID.uuidString
    }

    /// Inserts lines below a line (at the end for nil) and edits the last of them.
    @discardableResult
    public func insertLinesAfter(_ sources: [String], lineId: String?) -> String? {
        let position = lineId.flatMap(UUID.init(uuidString:)).flatMap(session.lineIndex(of:)).map { $0 + 1 }
        return insertLines(sources, position: position)
    }

    // MARK: Line actions

    // Each action validates the edited line first, then is one undo step, and
    // does nothing when it would change nothing.

    /// « Supprimer ».
    public func removeLine(id: String) {
        guard let lineID = UUID(uuidString: id) else { return }
        endEditing()
        session.removeLine(id: lineID)
    }

    /// Deletes lines by their offsets in `lines()`, as a swipe does.
    public func removeLines(atOffsets offsets: [Int]) {
        let lineIDs = lineIDs(atOffsets: offsets)
        endEditing()
        session.removeLines(atOffsets: visibleOffsets(of: lineIDs))
    }

    /// Moves lines with the offsets of a list move in `lines()`: `toOffset` is the
    /// position before the move where they go. Blank lines keep their place.
    public func moveLines(fromOffsets offsets: [Int], toOffset destination: Int) {
        let lines = session.formulaLines
        let moving = lineIDs(atOffsets: offsets)
        let anchor = lines.indices.contains(destination) ? lines[destination].id : nil
        endEditing()
        let current = session.formulaLines
        let target = anchor.flatMap { id in current.firstIndex { $0.id == id } } ?? current.count
        session.moveLines(fromOffsets: visibleOffsets(of: moving), toOffset: target)
    }

    /// « Dupliquer »: a copy below the line, which iOS then edits (a declaration's
    /// copy needs another name). Returns the copy's id.
    @discardableResult
    public func duplicateLine(id: String) -> String? {
        guard let lineID = UUID(uuidString: id) else { return nil }
        endEditing()
        return session.duplicateLine(id: lineID)?.uuidString
    }

    /// « Afficher en »: the result in another unit with `→`, or in SI for nil.
    public func setDisplayUnit(_ symbol: String?, lineId: String) {
        guard let lineID = UUID(uuidString: lineId) else { return }
        endEditing()
        session.setDisplayUnit(symbol, lineID: lineID)
    }

    /// The line with its formula written more simply, or nil when it is as simple
    /// as it gets: « Forme simplifiée ».
    public func simplification(lineId: String) -> String? {
        UUID(uuidString: lineId).flatMap(session.simplification(of:))
    }

    /// « Simplifier ».
    public func simplifyLine(id: String) {
        guard let lineID = UUID(uuidString: id) else { return }
        endEditing()
        session.simplifyLine(id: lineID)
    }

    /// Lines added at the end, as from the scanner; blank ones are dropped.
    public func appendLines(_ sources: [String]) {
        endEditing()
        session.appendLines(sources)
    }

    /// A constant or a unit from the References tab, added at the end with `=`
    /// so that it shows its value: « Ajouter une formule ». Returns the new line's id.
    @discardableResult
    public func appendFormula(_ expression: String) -> String? {
        endEditing()
        return session.appendFormula(expression)?.uuidString
    }

    /// « Modifier en texte »: the whole text replaced at once.
    public func editAsText(_ source: String) {
        endEditing()
        session.editAsText(source)
    }

    /// « Effacer la feuille », which iOS confirms first.
    public func clear() {
        endEditing()
        session.clear()
    }

    /// The line's menu, as iOS builds it when it opens. Nil for an unknown line.
    public func lineMenu(lineId: String) -> LineMenu? {
        guard let lineID = UUID(uuidString: lineId), let source = session.lineSource(of: lineID) else { return nil }
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let isComment = Self.isComment(trimmed)
        let result = session.result(for: lineID)
        let current = result?.source == source ? result : nil
        var copyValue: String?
        var copyLine: String?
        var units: (current: String?, symbols: [String])?
        var freeVariable: String?
        var plotVariables: [PlotVariable] = []
        if !isComment {
            if let current, LineSyntax(source).requestsValue || current.kind == .equation,
               let value = current.formattedValue {
                copyValue = value
                copyLine = ResultText.line(source: source, value: value)
            }
            units = Self.displayUnits(of: current)
            if let current, let name = VariableSweep.freeVariable(in: current) {
                freeVariable = name
            } else if let current, current.status == .success, current.quantity != nil,
                      current.kind == .expression || current.kind == .definition {
                plotVariables = self.plotVariables(lineId: lineId)
            }
        }
        return LineMenu(lineId: lineId, isComment: isComment,
                        simplified: isComment ? nil : session.simplification(of: lineID),
                        copyValue: copyValue, copyLine: copyLine,
                        displayUnits: units?.symbols ?? [], currentDisplayUnit: units?.current,
                        plotFreeVariable: freeVariable, plotVariables: plotVariables,
                        hasRuler: !isComment && session.variable(for: lineID) != nil, formula: trimmed)
    }

    // MARK: Undo

    public var canUndo: Bool { session.canUndo }
    public var canRedo: Bool { session.canRedo }
    /// The step `undo()` reverts, such as « Modifier la ligne ».
    public var undoActionName: String? { session.undoActionName }
    public var redoActionName: String? { session.redoActionName }

    /// Validates the edited line, then reverts the last step, as iOS's Annuler
    /// (which it enables while a line is edited, even without a step yet).
    @discardableResult
    public func undo() -> Bool {
        endEditing()
        return session.undo()
    }

    @discardableResult
    public func redo() -> Bool {
        endEditing()
        return session.redo()
    }

    // MARK: Rulers

    /// The line whose ruler is open, at most one. Editing a line closes it.
    public var activeRulerLineId: String? { session.activeRulerLineID?.uuidString }

    /// Opens the ruler of a line that declares a number, closing any other: a
    /// long press on its value, or « Afficher la réglette ».
    public func showRuler(lineId: String) {
        guard let lineID = UUID(uuidString: lineId) else { return }
        session.showRuler(lineID: lineID)
    }

    public func hideRuler() {
        session.activeRulerLineID = nil
    }

    /// The ruler of a line that declares a number, else nil.
    public func ruler(lineId: String) -> RulerState? {
        guard let lineID = UUID(uuidString: lineId), let variable = session.variable(for: lineID),
              let range = session.adjustmentRange(for: lineID, variable: variable)
                ?? VariableAdjustmentRange.suggested(for: variable.value) else { return nil }
        let step = session.rulerStep(for: lineID, variable: variable)
        return RulerState(lineId: lineId, name: variable.name, value: variable.value, unit: variable.unit,
                          valueText: NumberText.format(variable.value, unit: variable.unit, precise: true),
                          spokenValue: NumberText.spoken(variable.value, unit: variable.unit, precise: true),
                          step: step, spokenStep: NumberText.spoken(step, unit: variable.unit, precise: true),
                          usesAutomaticStep: !session.manualStepIDs.contains(lineID),
                          automaticStep: variable.automaticStep,
                          lowerBound: range.lowerBound, upperBound: range.upperBound, rangeStep: range.step)
    }

    /// A drag of the ruler, from touch down to release, is one undo step, « Ajuster v ».
    public func beginRulerGesture(lineId: String) {
        guard let lineID = UUID(uuidString: lineId) else { return }
        session.beginRulerGesture(lineID: lineID)
    }

    public func endRulerGesture() {
        session.endRulerGesture()
    }

    /// Sets the number of a ruler line; the results follow without the typing
    /// delay. Outside a gesture it is its own undo step. With `announcesResults`,
    /// `takeAnnouncement()` returns the new results once they are applied.
    public func adjustVariable(lineId: String, value: Double, announcesResults: Bool = false) {
        guard let lineID = UUID(uuidString: lineId) else { return }
        session.adjustVariable(value, lineID: lineID, announcesResults: announcesResults)
    }

    /// Moves a ruler value by whole steps, as TalkBack's adjust actions do: one
    /// undo step, and the new results are announced.
    public func stepVariable(lineId: String, steps: Int) {
        guard let lineID = UUID(uuidString: lineId), let variable = session.variable(for: lineID) else { return }
        let value = VariableAdjustmentRange.stepped(from: variable.value, steps: steps,
                                                    step: session.rulerStep(for: lineID, variable: variable))
        session.adjustVariable(value, lineID: lineID, announcesResults: true)
    }

    /// The value `steps` graduations from `origin`, as the ruler computes it
    /// during a drag (anchored to the value at its start). Any thread.
    public static func steppedValue(from origin: Double, steps: Int, step: Double) -> Double {
        VariableAdjustmentRange.stepped(from: origin, steps: steps, step: step)
    }

    /// Saves the settings of a ruler, « Régler le curseur de v »: the plot interval
    /// and, unless automatic, the step. Returns false, saving nothing, when the
    /// maximum does not exceed the minimum, the step is not positive or a value is not finite.
    @discardableResult
    public func setRulerSettings(lineId: String, lowerBound: Double, upperBound: Double, step: Double,
                                 usesAutomaticStep: Bool) -> Bool {
        guard let lineID = UUID(uuidString: lineId), let variable = session.variable(for: lineID),
              let range = VariableAdjustmentRange(lowerBound: lowerBound, upperBound: upperBound,
                                                  step: usesAutomaticStep ? variable.automaticStep : step) else { return false }
        session.setAdjustmentRange(range, for: lineID, automaticStep: usesAutomaticStep)
        return true
    }

    /// The settings « Rétablir le réglage automatique » proposes.
    public func suggestedRulerSettings(lineId: String) -> RulerRange? {
        guard let variable = UUID(uuidString: lineId).flatMap(session.variable(for:)),
              let range = VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep) else { return nil }
        return RulerRange(lowerBound: range.lowerBound, upperBound: range.upperBound, step: range.step)
    }

    // MARK: Plots

    /// The ruler variables a result can be plotted against: those it depends on.
    public func plotVariables(lineId: String) -> [PlotVariable] {
        guard let lineID = UUID(uuidString: lineId) else { return [] }
        return session.plotVariables(for: lineID).map { PlotVariable(lineId: $0.id.uuidString, name: $0.variable.name) }
    }

    /// What `samplePlot(_:)` needs to plot a result against a ruler variable, over
    /// the plot interval of that variable.
    public func plotInput(resultLineId: String, variableLineId: String) -> PlotInput {
        let variable = UUID(uuidString: variableLineId).flatMap(session.variable(for:))
        let plot = PlotInput.Job(source: session.source,
                                 resultIndex: UUID(uuidString: resultLineId).flatMap(session.lineIndex(of:)),
                                 variableIndex: UUID(uuidString: variableLineId).flatMap(session.lineIndex(of:)),
                                 freeVariable: nil,
                                 range: UUID(uuidString: variableLineId).flatMap { id in
                                     variable.flatMap { session.adjustmentRange(for: id, variable: $0) }
                                 })
        return makePlotInput(resultLineId: resultLineId, variableName: variable?.name ?? "",
                             variableUnit: variable?.unit ?? "", currentValue: variable?.value,
                             job: variable == nil ? nil : plot)
    }

    /// The same for a name the sheet does not declare (`y = 2·x`), over the
    /// interval typed for it; nothing is added to the sheet.
    public func freeVariablePlotInput(resultLineId: String, freeVariable: String, lowerBound: Double,
                                      upperBound: Double) -> PlotInput {
        let plot = PlotInput.Job(source: session.source,
                                 resultIndex: UUID(uuidString: resultLineId).flatMap(session.lineIndex(of:)),
                                 variableIndex: nil, freeVariable: freeVariable,
                                 range: VariableAdjustmentRange(lowerBound: lowerBound, upperBound: upperBound,
                                                                step: (upperBound - lowerBound) / 100))
        return makePlotInput(resultLineId: resultLineId, variableName: freeVariable, variableUnit: "",
                             currentValue: nil, job: plot)
    }

    /// Evaluates the sheet for 161 values of the variable. Any thread: call it
    /// away from the main thread.
    public static func samplePlot(_ input: PlotInput) -> PlotData {
        guard let job = input.job, let resultIndex = job.resultIndex,
              job.freeVariable != nil || job.variableIndex != nil else { return PlotData(failure: "missingLine") }
        guard let range = job.range else { return PlotData(failure: "noRange") }
        let points: [SweepPoint]
        if let name = job.freeVariable {
            points = VariableSweep.sample(source: job.source, freeVariable: name, resultLineIndex: resultIndex,
                                          range: range, count: 161)
        } else {
            points = VariableSweep.sample(source: job.source, variableLineIndex: job.variableIndex ?? 0,
                                          resultLineIndex: resultIndex, range: range, count: 161)
        }
        let segments = VariableSweep.segments(points).map { PlotSegment(xs: $0.map(\.x), ys: $0.map(\.y)) }
        return PlotData(failure: segments.isEmpty ? "undefined" : nil, lowerBound: range.lowerBound,
                        upperBound: range.upperBound, segments: segments)
    }

    private func makePlotInput(resultLineId: String, variableName: String, variableUnit: String,
                               currentValue: Double?, job: PlotInput.Job?) -> PlotInput {
        let resultID = UUID(uuidString: resultLineId)
        let source = resultID.flatMap(session.lineSource(of:)) ?? ""
        let name = ResultText.declaredName(in: source) ?? LineSyntax(source).body.trimmingCharacters(in: .whitespaces)
        let result = resultID.flatMap(session.result(for:))
        return PlotInput(resultName: name.count > 24 ? String(name.prefix(24)) + "…" : name,
                         resultUnit: result?.quantity.map { QuantityFormatter.unitSymbol(for: $0.dimension, in: result?.displayUnit) },
                         currentResult: result?.formattedValue,
                         spokenCurrentResult: result?.spokenResult ?? result?.formattedValue,
                         variableName: variableName, variableUnit: variableUnit, currentValue: currentValue,
                         job: job)
    }

    // MARK: Evaluation

    /// True until an evaluation of the current text and lines is applied.
    public var needsEvaluation: Bool { session.needsEvaluation }

    /// A snapshot of the text to evaluate, taken on the main thread. Give it to
    /// `evaluate(_:)` away from the main thread, then the result to `applyEvaluation(_:)`.
    ///
    /// To behave as iOS: after a change whose request `isDebounced`, wait
    /// `typingDelayMillis` without a newer change (a request that is not debounced,
    /// such as a ruler's, ends the wait); run one evaluation at a time, always on the
    /// latest request; once applied, evaluate again at once while `needsEvaluation`;
    /// show progress only after `progressDelayMillis`.
    public func evaluationRequest() -> EvaluationRequest {
        EvaluationRequest(request: session.evaluationRequest)
    }

    /// Evaluates a request with the engine of iOS. Pure: any thread.
    public static func evaluate(_ request: EvaluationRequest) -> Evaluation {
        Evaluation(evaluation: SheetSession.evaluate(request.request))
    }

    /// Shows a finished evaluation and returns true. As on iOS, an evaluation of
    /// an earlier text is shown too: each line keeps its result by identity, and
    /// one edited since is marked stale until the next. Returns false, changing
    /// nothing, when the sheet is closed, a later evaluation is already shown, or,
    /// with `onlyIfCurrent`, the text changed since the request.
    @discardableResult
    public func applyEvaluation(_ evaluation: Evaluation, onlyIfCurrent: Bool = false) -> Bool {
        session.apply(evaluation.evaluation, onlyIfCurrent: onlyIfCurrent)
    }

    /// False until the first evaluation is applied.
    public var hasEvaluation: Bool { session.hasEvaluation }
    /// A problem with the whole sheet, when the engine returns no result per line;
    /// iOS shows it in red above the lines.
    public var sheetIssue: String? { session.sheetIssue }
    /// The preview of the sheet list, « E = 1000 J », and as read aloud.
    public var resultPreview: String? { session.resultPreview }
    public var spokenResultPreview: String? { session.spokenResultPreview }
    /// Names declared in the sheet, sorted, for the keyboard bar.
    public var declaredNames: [String] { session.declaredNames }

    /// « Constantes reconnues »: constants used without a declaration.
    public func recognizedConstants() -> [ConstantItem] {
        session.constants.map(ConstantItem.init)
    }

    /// « Symboles lus comme des unités »: undeclared symbols read as units, such as `T`.
    public func symbolUnits() -> [UnitItem] {
        session.symbolUnits.map(UnitItem.init)
    }

    /// What TalkBack should announce after `adjustVariable(…, announcesResults: true)`
    /// or `stepVariable`, once the results are applied; nil afterwards.
    public func takeAnnouncement() -> String? {
        session.takeAnnouncement()
    }

    // MARK: Sharing

    /// The sheet as text, with the current requested values as trailing notes
    /// (« Partager la feuille »), or without them.
    public func sharedText(includingResults: Bool) -> String {
        session.sharedText(includingResults: includingResults)
    }

    // MARK: Line state

    private func lineState(index: Int, entry: ResultSelection.Entry) -> LineState {
        let source = entry.source
        let trimmed = source.trimmingCharacters(in: .whitespaces)
        let isComment = Self.isComment(trimmed)
        let result = session.result(for: entry.id)
        let isCurrent = result?.source == source
        let syntax = LineSyntax(source)
        let variable = session.variable(for: entry.id)
        let isEditing = editing?.lineID == entry.id

        var value: String?
        if !isComment, syntax.requestsValue, let result, result.kind != .equation {
            value = result.formattedValue
        }
        var noteText: String?
        var isHeading = false
        if isComment {
            let text = trimmed.drop { $0 == "#" || $0 == "/" }.trimmingCharacters(in: .whitespaces)
            noteText = text.isEmpty ? trimmed : text
            isHeading = trimmed.hasPrefix("#") && text.count < 60
        }

        return LineState(
            id: entry.id.uuidString, index: index, source: source, isEditing: isEditing,
            isComment: isComment, noteText: noteText, isHeading: isHeading,
            kind: result?.kind.rawValue, status: result?.status.rawValue,
            value: value, valueLabel: value.map { syntax.requestsResult ? $0 : "= \($0)" },
            spokenValue: value.map { result?.spokenResult ?? $0 },
            message: result?.message, isStale: result != nil && !isCurrent,
            notes: isComment ? [] : notes(for: result, source: source),
            editingNotes: editingNotes(for: result, source: source),
            isAdjustable: variable != nil, variableName: variable?.name,
            isRulerOpen: session.activeRulerLineID == entry.id && !isEditing,
            accessibilityLabel: accessibilityLabel(index: index, source: source, trimmed: trimmed,
                                                   isComment: isComment, result: result, variable: variable),
            accessibilityValue: variable.map { NumberText.spoken($0.value, unit: $0.unit, precise: true) })
    }

    /// What the engine has to say under a line at rest: an error, the verdict of
    /// an equality, a remark, or a dimension it checked.
    private func notes(for line: EvaluatedLine?, source: String) -> [LineNote] {
        guard let line else { return [] }
        let isCurrent = line.source == source
        var notes: [LineNote] = []
        if let message = line.message {
            if line.status == .error {
                notes.append(LineNote(text: message,
                                      style: line.kind == .equation && line.quantity != nil ? "equalityError" : "error",
                                      spoken: "Erreur : \(message)"))
            } else if line.status == .success, isCurrent {
                notes.append(LineNote(text: message, style: line.kind == .equation ? "verified" : "info", spoken: message))
            }
        }
        if isCurrent, line.isHomogeneous, line.kind == .equation || LineSyntax(source).requestsValue,
           let dimension = line.dimensionMessage {
            notes.append(LineNote(text: dimension, style: "dimension", spoken: line.spokenDimensionMessage ?? dimension))
        }
        return notes
    }

    /// Under the edited line: its value, kept up to date, or the verdict of an
    /// equality. Errors wait for the end of the editing.
    private func editingNotes(for line: EvaluatedLine?, source: String) -> [LineNote] {
        guard let line else { return [] }
        if LineSyntax(source).requestsValue, line.kind != .equation, let value = line.formattedValue {
            return [LineNote(text: "= \(value)", style: line.source == source ? "value" : "staleValue",
                             spoken: "Résultat : \(line.spokenResult ?? value)")]
        }
        if line.kind == .equation, line.source == source, line.status == .success {
            return Array(notes(for: line, source: source).prefix(1))
        }
        return []
    }

    /// The formula and its value as one phrase; a declared number is read as its value.
    private func accessibilityLabel(index: Int, source: String, trimmed: String, isComment: Bool,
                                    result: EvaluatedLine?, variable: AdjustableVariable?) -> String {
        if isComment { return "Ligne \(index + 1), note : \(trimmed)" }
        var parts: [String] = []
        if let variable {
            parts.append("Valeur de \(variable.name)")
        } else {
            var phrase = spoken(source)
            let syntax = LineSyntax(source)
            if syntax.requestsValue, let result, result.kind != .equation, result.source == source,
               let value = result.spokenResult {
                phrase += syntax.requestsResult ? " \(value)" : " égale \(value)"
            }
            parts.append(phrase)
        }
        if let result, let message = result.message, result.status == .error || result.source == source {
            parts.append(result.status == .error ? "Erreur : \(message)" : message)
        }
        return parts.joined(separator: ". ")
    }

    private func spoken(_ source: String) -> String {
        if let cached = speechCache[source] { return cached }
        let text = MathSpeech.description(source) ?? source
        if speechCache.count >= 1_000 { speechCache.removeAll() }
        speechCache[source] = text
        return text
    }

    private static func isComment(_ trimmed: String) -> Bool {
        trimmed.hasPrefix("#") || trimmed.hasPrefix("//")
    }

    /// The units a line can be shown in, nil while it has no current value to convert.
    private static func displayUnits(of line: EvaluatedLine?) -> (current: String?, symbols: [String])? {
        guard let line, line.status == .success, line.kind != .equation, let quantity = line.quantity else { return nil }
        let current = line.displayUnit?.symbol
        var symbols = UnitCatalog.displaySuggestions(compatibleWith: quantity.dimension)
        if let current, !symbols.contains(current) { symbols.insert(current, at: 0) }
        return symbols.isEmpty ? nil : (current, symbols)
    }

    private func lineIDs(atOffsets offsets: [Int]) -> [UUID] {
        let lines = session.formulaLines
        return offsets.compactMap { lines.indices.contains($0) ? lines[$0].id : nil }
    }

    private func visibleOffsets(of lineIDs: [UUID]) -> IndexSet {
        let lines = session.formulaLines
        return IndexSet(lineIDs.compactMap { id in lines.firstIndex { $0.id == id } })
    }
}

/// A line of the sheet as iOS shows it.
public struct LineState: Hashable, Sendable {
    public let id: String
    /// The position among all the lines, blank ones included: the line number is `index + 1`.
    public let index: Int
    public let source: String
    /// True while the line is edited in place.
    public let isEditing: Bool
    /// A note (`# …` or `// …`), shown as text instead of a formula.
    public let isComment: Bool
    /// The text of a note without its marker.
    public let noteText: String?
    /// A short `#` note reads as a heading, any other as secondary text.
    public let isHeading: Bool
    /// The last result's kind: `expression`, `definition`, `equation`, `comment` or
    /// `empty`; nil before the first result.
    public let kind: String?
    /// The last result's status: `success`, `error` or `neutral`; nil before the first result.
    public let status: String?
    /// The value shown beside the formula, exactly when iOS shows it: the line asks
    /// for it (`=`, `→` or `?`) and is not an equality. Possibly stale.
    public let value: String?
    /// The value as displayed: `1000 J` after a final `=`, else `= 1000 J`.
    public let valueLabel: String?
    public let spokenValue: String?
    /// The last result's message: an error, a verdict or a remark.
    public let message: String?
    /// True when the result was computed for an earlier text of the line: iOS
    /// shows its value in secondary color until the new one arrives.
    public let isStale: Bool
    /// The notes under the line at rest, in order.
    public let notes: [LineNote]
    /// The notes under the line while it is edited.
    public let editingNotes: [LineNote]
    /// The line declares a number with a ruler: a long press on its value opens it.
    public let isAdjustable: Bool
    public let variableName: String?
    /// The ruler of this line is open.
    public let isRulerOpen: Bool
    /// The whole row as TalkBack reads it, and its value for a ruler line.
    public let accessibilityLabel: String
    public let accessibilityValue: String?
}

/// A line of text under a formula.
public struct LineNote: Hashable, Sendable {
    public let text: String
    /// `value` (tinted) or `staleValue` (secondary) while editing; `error` (red,
    /// warning icon), `equalityError` (red, cross icon), `verified` (green check),
    /// `info` (info icon) or `dimension` (caption with a check).
    public let style: String
    public let spoken: String
}

/// The menu of a line: each field says whether, and with what, an item appears.
public struct LineMenu: Hashable, Sendable {
    public let lineId: String
    public let isComment: Bool
    /// « Simplifier », with the simpler line, when there is one.
    public let simplified: String?
    /// « Copier la valeur », and « Copier la ligne » / « Partager le résultat » with `copyLine`.
    public let copyValue: String?
    public let copyLine: String?
    /// « Afficher en »: the units offered, empty for no menu; « Unités SI » comes first.
    public let displayUnits: [String]
    /// The unit chosen with `→`; nil for SI.
    public let currentDisplayUnit: String?
    /// « Tracer en fonction de x » for a name the sheet does not declare.
    public let plotFreeVariable: String?
    /// « Tracer en fonction de » with these ruler variables, when not empty.
    public let plotVariables: [PlotVariable]
    /// « Afficher la réglette ».
    public let hasRuler: Bool
    /// « Copier la formule »: the trimmed line.
    public let formula: String
}

public struct PlotVariable: Hashable, Sendable {
    public let lineId: String
    public let name: String
}

/// The ruler of a declared number. It moves the value in its entered unit, by
/// whole steps, without bounds.
public struct RulerState: Hashable, Sendable {
    public let lineId: String
    public let name: String
    public let value: Double
    public let unit: String
    /// « 80 kg », with the precise digits shown above the ruler.
    public let valueText: String
    public let spokenValue: String
    /// What one graduation adds or removes.
    public let step: Double
    public let spokenStep: String
    public let usesAutomaticStep: Bool
    /// The step that follows the entered precision: 6 → 1, 8,2 → 0,1.
    public let automaticStep: Double
    /// The settings of the line: the plot interval and its manual step.
    public let lowerBound: Double
    public let upperBound: Double
    public let rangeStep: Double
}

public struct RulerRange: Hashable, Sendable {
    public let lowerBound: Double
    public let upperBound: Double
    public let step: Double
}

/// Asks the sheet to scroll to a line: act on each new `id` once.
public struct RevealRequest: Hashable, Sendable {
    public let id: String
    public let lineId: String
}

/// A snapshot of the sheet to evaluate. It can cross threads.
public struct EvaluationRequest: Sendable {
    /// Orders the requests of a sheet: a later change has a larger revision.
    public var revision: Int64 { Int64(request.revision) }
    /// True after typing: wait `SheetEditor.typingDelayMillis` without a newer
    /// change before evaluating. False when the sheet opens, for a ruler, after undo or redo.
    public var isDebounced: Bool { request.isDebounced }
    public var source: String { request.source }
    let request: SheetSession.EvaluationRequest
}

/// A finished evaluation, for `SheetEditor.applyEvaluation(_:)`. It can cross threads.
public struct Evaluation: Sendable {
    public var revision: Int64 { Int64(evaluation.request.revision) }
    let evaluation: SheetSession.Evaluation
}

/// Everything a plot needs, taken from the sheet on the main thread.
public struct PlotInput: Sendable {
    /// The result's name, cut after 24 characters, for the title « E en fonction de v ».
    public let resultName: String
    /// The unit of the result's axis; nil while the result has no value.
    public let resultUnit: String?
    /// The result's value now, for « Valeur actuelle ».
    public let currentResult: String?
    public let spokenCurrentResult: String?
    public let variableName: String
    /// The unit of the variable's axis, empty for a free name.
    public let variableUnit: String
    /// The ruler's value now, marked on the plot; nil for a free name.
    public let currentValue: Double?
    let job: Job?

    struct Job: Sendable {
        let source: String
        let resultIndex: Int?
        let variableIndex: Int?
        let freeVariable: String?
        let range: VariableAdjustmentRange?
    }
}

/// The samples of a plot, in runs without gaps: draw each segment as its own
/// line, and a segment of one point as a dot.
public struct PlotData: Sendable {
    /// Why there is nothing to draw: `missingLine` (a line is gone, or the variable
    /// is no longer a number), `noRange` (no valid interval) or `undefined` (no value
    /// in the interval). Nil when there are segments.
    public let failure: String?
    /// The interval the horizontal axis covers.
    public let lowerBound: Double
    public let upperBound: Double
    public let segments: [PlotSegment]

    init(failure: String?, lowerBound: Double = 0, upperBound: Double = 1, segments: [PlotSegment] = []) {
        self.failure = failure
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.segments = segments
    }
}

/// Values of the variable, in its entered unit, and of the result, in SI or in its `→` unit.
public struct PlotSegment: Hashable, Sendable {
    public let xs: [Double]
    public let ys: [Double]
}
