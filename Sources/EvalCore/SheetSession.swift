import Foundation

/// The editing session of one sheet, without any user interface: the logic of
/// the iOS `NotebookStore`, for apps that cannot share its SwiftUI code.
///
/// Results are attached to the identity of their line, so a line keeps showing
/// its last value while it is edited, moved or while lines are inserted above it.
/// The session keeps its own undo steps, one per action, named as on iOS.
///
/// A session is not thread-safe: use it from one thread, the main one of the app.
/// Only `evaluate(_:)` runs elsewhere; its result comes back through `apply(_:onlyIfCurrent:)`.
public final class SheetSession {
    public let id: UUID
    public let createdAt: Date

    /// The text of the sheet. Setting it makes no undo step: wrap it in
    /// `recording(_:_:)`, or use `editAsText(_:)`.
    public var source: String {
        get { text }
        set { setSource(newValue, evaluatesImmediately: false) }
    }

    /// A title chosen by the user, trimmed; empty means none. Setting it ends automatic naming.
    public var customTitle: String? {
        get { storedTitle }
        set {
            let title = newValue?.trimmingCharacters(in: .whitespacesAndNewlines)
            let normalized = title?.isEmpty == false ? title : nil
            guard normalized != storedTitle else { return }
            storedTitle = normalized
            // A sheet the user has named is never named automatically.
            automaticTitleAttempted = true
            recordDidChange()
        }
    }

    /// Renames the sheet as the library does: an empty title, or the sheet's own
    /// note title, restores the automatic title.
    public func rename(to title: String) {
        customTitle = Self.customTitle(renaming: record, to: title)
    }

    /// The custom title a sheet gets when renamed to `title`.
    public static func customTitle(renaming record: SheetRecord, to title: String) -> String? {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let automaticTitle = SheetRecord.noteTitle(in: record.source) ?? SheetRecord.untitledTitle
        return trimmed.isEmpty || (record.customTitle == nil && trimmed == automaticTitle) ? nil : trimmed
    }

    /// Ends the automatic naming of the sheet: it takes `title` if it is still
    /// called « Nouvelle feuille » and was not named meanwhile. A nil title only
    /// records the attempt. The modification date does not change.
    public func applyAutomaticTitle(_ title: String?) {
        guard !isClosed, !automaticTitleAttempted else { return }
        automaticTitleAttempted = true
        if let title, storedTitle == nil, SheetRecord.noteTitle(in: text) == nil {
            storedTitle = title
        }
        recordDidChange(updatesModificationDate: false)
    }

    public private(set) var resultSelection: ResultSelection
    /// Constants used by the latest evaluation, which may describe an earlier text.
    public private(set) var constants: [ConstantDefinition] = []
    /// Undeclared symbols the latest evaluation read as units, such as `T` as the tesla.
    public private(set) var symbolUnits: [UnitDefinition] = []
    /// False until the first evaluation of this session is applied.
    public private(set) var hasEvaluation = false
    public private(set) var adjustmentRanges: [UUID: VariableAdjustmentRange]
    public private(set) var manualStepIDs: Set<UUID>
    public private(set) var modifiedAt: Date
    public private(set) var displayTitle: String
    /// Set by `close()`: the session no longer reports changes nor applies evaluations.
    public private(set) var isClosed = false

    // Derived data.
    /// The lines shown in the sheet: every line but blank ones, unless a blank
    /// line is being edited.
    public private(set) var formulaLines: [FormulaLine] = []
    public private(set) var adjustableVariables: [Variable] = []
    public private(set) var variablesByLineID: [UUID: AdjustableVariable] = [:]
    /// The last result of each line, by line identity. See `result(for:)`.
    public private(set) var resultsByLineID: [UUID: EvaluatedLine] = [:]
    /// The line whose ruler is open, at most one. Editing a line closes it.
    public var activeRulerLineID: UUID?
    /// Lines being edited in place, shown even while blank.
    public private(set) var editingLineIDs: Set<UUID> = []
    /// A problem with the whole sheet, such as its length.
    public private(set) var sheetIssue: String?
    /// The preview of the sheet list: the first requested value that is current.
    public private(set) var resultPreview: String?
    public private(set) var spokenResultPreview: String?
    /// Names declared in the sheet, from the latest evaluation, for the insertion menu.
    public private(set) var declaredNames: [String] = []
    /// Asks the sheet view to scroll to a line that was just added.
    public private(set) var revealRequest: RevealRequest?

    private var text: String
    private var storedTitle: String?
    private var automaticTitleAttempted: Bool
    private var lineIndexByID: [UUID: Int] = [:]
    /// The line identities `formulaLines` and `lineIndexByID` describe.
    private var refreshedLineIDs: [UUID] = []
    /// Parsing a declaration evaluates it; unchanged lines reuse the previous parse.
    private var variableCache: [String: AdjustableVariable?] = [:]
    /// The simpler form of each line text met, nil when it is as simple as it gets.
    private var simplificationCache: [String: String?] = [:]
    private var rulerGesture: (state: State, name: String)?
    private var revision = 0
    private var evaluationIsDebounced = false
    private var shownRequest: EvaluationRequest?
    /// Set by a ruler adjustment for a screen reader: the next current evaluation is announced.
    private var announcesNextEvaluation = false
    private var pendingAnnouncement: String?
    private let onChange: (SheetRecord) -> Void

    /// `onChange` receives the updated record after every edit; it is not
    /// called for the initial state. The session starts out needing an
    /// evaluation, without the typing delay.
    public init(record: SheetRecord, onChange: @escaping (SheetRecord) -> Void = { _ in }) {
        id = record.id
        text = record.source
        storedTitle = record.customTitle
        automaticTitleAttempted = record.automaticTitleAttempted
        createdAt = record.createdAt
        modifiedAt = record.modifiedAt
        displayTitle = record.displayTitle
        resultSelection = record.resultSelection
        adjustmentRanges = record.adjustmentRanges
        manualStepIDs = record.manualStepIDs
        self.onChange = onChange
        refreshLines()
    }

    public var record: SheetRecord {
        SheetRecord(id: id, customTitle: storedTitle, automaticTitleAttempted: automaticTitleAttempted,
                    source: text, resultSelection: resultSelection,
                    adjustmentRanges: adjustmentRanges, manualStepIDs: manualStepIDs,
                    createdAt: createdAt, modifiedAt: modifiedAt)
    }

    /// The last result of a line, possibly computed for an earlier text of that line.
    public func result(for lineID: UUID) -> EvaluatedLine? {
        resultsByLineID[lineID]
    }

    /// True when the result of a line was computed for an earlier text of it:
    /// iOS shows such a value grayed until the new one arrives.
    public func isResultStale(for lineID: UUID) -> Bool {
        guard let line = resultsByLineID[lineID], let source = lineSource(of: lineID) else { return false }
        return line.source != source
    }

    /// Stops reporting changes once the sheet is deleted.
    public func close() {
        isClosed = true
        rulerGesture = nil
    }

    // MARK: Rulers

    /// The interval a plot covers, and the step of the ruler: the settings saved for
    /// the line, else an interval around the current value. The ruler itself has no bounds.
    public func adjustmentRange(for id: UUID, variable: AdjustableVariable) -> VariableAdjustmentRange? {
        if let range = adjustmentRanges[id] {
            if manualStepIDs.contains(id) { return range }
            return VariableAdjustmentRange(lowerBound: range.lowerBound, upperBound: range.upperBound,
                                           step: variable.automaticStep)
                ?? VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep)
        }
        return VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep)
    }

    /// How far one graduation of the ruler moves the value: the entered precision,
    /// or the step chosen in the line’s settings.
    public func rulerStep(for id: UUID, variable: AdjustableVariable) -> Double {
        if manualStepIDs.contains(id), let step = adjustmentRanges[id]?.step { return step }
        return variable.automaticStep
    }

    /// Saves the settings of a line's ruler as one undo step, « Régler le curseur de v »,
    /// like the iOS settings popover.
    public func setAdjustmentRange(_ range: VariableAdjustmentRange, for id: UUID, automaticStep: Bool = true) {
        guard let variable = variablesByLineID[id] else { return }
        recording("Régler le curseur de \(variable.name)") {
            adjustmentRanges[id] = range
            if automaticStep { manualStepIDs.remove(id) } else { manualStepIDs.insert(id) }
            recordDidChange()
        }
    }

    /// Results follow the ruler: the evaluation request skips the typing delay.
    /// Within a gesture the change joins its undo step; otherwise it is one step,
    /// « Ajuster v », as an accessibility increment on iOS. With `announcesResults`,
    /// `takeAnnouncement()` returns the recalculated results once they arrive.
    public func adjustVariable(_ value: Double, lineID: UUID, announcesResults: Bool = false) {
        guard let index = lineIndexByID[lineID],
              let variable = variablesByLineID[lineID],
              value != variable.value,
              let updated = variable.source(replacingValue: value) else { return }
        let before = rulerGesture == nil ? state : nil
        resultSelection.updateSource(updated, at: index)
        if announcesResults { announcesNextEvaluation = true }
        setSource(joinedSource, evaluatesImmediately: true)
        if let before { registerUndo(restoring: before, named: "Ajuster \(variable.name)") }
    }

    /// A ruler gesture, from touch down to release, is one undo step, « Ajuster v ».
    public func beginRulerGesture(lineID: UUID) {
        guard rulerGesture == nil, let variable = variablesByLineID[lineID] else { return }
        rulerGesture = (state, "Ajuster \(variable.name)")
    }

    public func endRulerGesture() {
        guard let gesture = rulerGesture else { return }
        rulerGesture = nil
        registerUndo(restoring: gesture.state, named: gesture.name)
    }

    /// Opens the ruler of a line, closing any other.
    public func showRuler(lineID: UUID) {
        guard variablesByLineID[lineID] != nil else { return }
        activeRulerLineID = lineID
    }

    /// The ruler variable of a line, if it declares an adjustable number.
    public func variable(for lineID: UUID) -> AdjustableVariable? {
        variablesByLineID[lineID]
    }

    // MARK: Lines

    /// Adds a line at the end and asks the sheet view to show it, without an undo
    /// step: see `appendFormula(_:)`. By default the line asks for its value with
    /// a final `=`, so an inserted constant shows it.
    @discardableResult
    public func append(_ expression: String, requestsResult: Bool = true) -> UUID? {
        let line = requestsResult ? LineSyntax(expression).addingResultRequest() : expression
        source += source.isEmpty || source.hasSuffix("\n") ? line : "\n\(line)"
        guard let id = resultSelection.entries.last?.id else { return nil }
        revealRequest = RevealRequest(lineID: id)
        return id
    }

    /// Adds a formula from the catalog at the end, as one undo step « Ajouter une formule ».
    @discardableResult
    public func appendFormula(_ expression: String) -> UUID? {
        var lineID: UUID?
        recording("Ajouter une formule") {
            lineID = append(expression)
        }
        return lineID
    }

    /// Replaces the whole text, as the text editor does: one undo step « Modifier en texte ».
    public func editAsText(_ newSource: String) {
        recording("Modifier en texte") {
            source = newSource
        }
    }

    // MARK: Editing in place

    /// One editing session of a line, from the focus to its loss: one undo step.
    public struct EditingSession: Equatable, Sendable {
        public let lineID: UUID
        /// True for a line created for this session, which disappears if left blank.
        public let isNew: Bool
        let before: State
    }

    /// Starts editing a line: it stays visible while blank, and the ruler closes.
    public func beginEditing(lineID: UUID) -> EditingSession? {
        guard lineIndexByID[lineID] != nil else { return nil }
        let session = EditingSession(lineID: lineID, isNew: false, before: state)
        activeRulerLineID = nil
        editingLineIDs.insert(lineID)
        return session
    }

    /// Inserts blank lines, or the given ones, after `lineID` (at the end for nil)
    /// and starts editing the last of them.
    public func insertLines(_ sources: [String] = [""], after lineID: UUID?) -> EditingSession? {
        insertLines(sources, at: lineID.flatMap { lineIndexByID[$0] }.map { $0 + 1 })
    }

    /// Inserts lines at a position of the sheet (at the end for nil) and starts
    /// editing the last of them.
    public func insertLines(_ sources: [String], at position: Int?) -> EditingSession? {
        let before = state
        // A blank last line, hidden in the sheet, takes the new text rather than staying above it.
        if position == nil, sources.count == 1, let last = resultSelection.entries.last,
           !editingLineIDs.contains(last.id), last.source.trimmingCharacters(in: .whitespaces).isEmpty {
            activeRulerLineID = nil
            editingLineIDs.insert(last.id)
            refreshLines()
            updateLine(sources[0], lineID: last.id)
            revealRequest = RevealRequest(lineID: last.id)
            return EditingSession(lineID: last.id, isNew: true, before: before)
        }
        var index = min(position ?? resultSelection.entries.count, resultSelection.entries.count)
        var lastID: UUID?
        for line in sources {
            let entry = ResultSelection.Entry(source: line)
            guard let inserted = resultSelection.inserting(entry, at: index) else { continue }
            resultSelection = inserted
            lastID = entry.id
            index += 1
        }
        guard let lastID else { return nil }
        activeRulerLineID = nil
        editingLineIDs.insert(lastID)
        setSource(joinedSource, evaluatesImmediately: false)
        revealRequest = RevealRequest(lineID: lastID)
        return EditingSession(lineID: lastID, isNew: true, before: before)
    }

    /// The live text of a line being edited. A single line only: see `breakLine(_:session:)`.
    public func updateLine(_ text: String, lineID: UUID) {
        guard let index = lineIndexByID[lineID], resultSelection.entries[index].source != text,
              !text.contains(where: \.isNewline) else { return }
        resultSelection.updateSource(text, at: index)
        setSource(joinedSource, evaluatesImmediately: false)
    }

    /// Ends an editing session: a line left blank is removed, then the whole
    /// session becomes one undo step, « Ajouter une ligne », « Supprimer la ligne »
    /// or « Modifier la ligne ».
    public func endEditing(_ session: EditingSession) {
        editingLineIDs.remove(session.lineID)
        guard let index = lineIndexByID[session.lineID] else {
            refreshLines()
            return
        }
        var removed = false
        if resultSelection.entries[index].source.trimmingCharacters(in: .whitespaces).isEmpty {
            removed = true
            // An empty sheet keeps its one blank line, hidden, with its identity.
            if resultSelection.entries.count > 1 {
                resultSelection.removeEntry(at: index)
                setSource(joinedSource, evaluatesImmediately: false)
            }
        }
        refreshLines()
        let name = session.isNew ? "Ajouter une ligne" : removed ? "Supprimer la ligne" : "Modifier la ligne"
        registerUndo(restoring: session.before, named: name)
    }

    /// A Return, or a paste of several lines, in the edited line: the line keeps
    /// the text before the break, the rest goes to new lines below, and the last
    /// of them is edited. Returns the session to continue with: the new one, or
    /// nil when editing stops, as after a Return on a blank line. `session` is
    /// then over. A text without a line break only updates the line.
    public func breakLine(_ text: String, session: EditingSession) -> EditingSession? {
        let parts = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).map(String.init)
        guard parts.count > 1, let position = lineIndexByID[session.lineID] else {
            updateLine(text, lineID: session.lineID)
            return session
        }
        let rest = Array(parts.dropFirst())
        let isBlank = { (line: String) in line.trimmingCharacters(in: .whitespaces).isEmpty }
        updateLine(parts[0], lineID: session.lineID)
        endEditing(session)
        if isBlank(parts[0]) && rest.allSatisfy(isBlank) { return nil }
        // A blank first part has just been removed, so the new lines take its place.
        let removed = lineIndexByID[session.lineID] == nil
        return insertLines(rest, at: removed ? position : position + 1)
    }

    public func removeLine(id: UUID) {
        guard let index = lineIndexByID[id] else { return }
        recording("Supprimer la ligne") {
            resultSelection.removeEntry(at: index)
            source = joinedSource
        }
    }

    /// Deletes the lines at these offsets of `formulaLines`.
    public func removeLines(atOffsets offsets: IndexSet) {
        let indices = offsets.compactMap { formulaLines.indices.contains($0) ? formulaLines[$0].index : nil }
        guard !indices.isEmpty else { return }
        recording(indices.count == 1 ? "Supprimer la ligne" : "Supprimer les lignes") {
            for index in indices.sorted(by: >) { resultSelection.removeEntry(at: index) }
            source = joinedSource
        }
    }

    /// Moves lines of `formulaLines`, with the offsets of a list move. Blank lines,
    /// which are hidden, keep their position; the line identities, and so the
    /// rulers, follow.
    public func moveLines(fromOffsets offsets: IndexSet, toOffset destination: Int) {
        guard let order = LineReordering.order(count: resultSelection.entries.count, visible: formulaLines.map(\.index),
                                               moving: offsets, to: destination),
              let moved = resultSelection.rearranged(by: order) else { return }
        recording(offsets.count == 1 ? "Déplacer la ligne" : "Déplacer les lignes") {
            resultSelection = moved
            source = joinedSource
        }
    }

    /// Copies a line right below itself and returns the copy, which the sheet
    /// opens for editing: a declaration's copy needs another name.
    @discardableResult
    public func duplicateLine(id: UUID) -> UUID? {
        guard let index = lineIndexByID[id],
              let inserted = resultSelection.inserting(ResultSelection.Entry(source: resultSelection.entries[index].source),
                                                       at: index + 1) else { return nil }
        let copyID = inserted.entries[index + 1].id
        recording("Dupliquer la ligne") {
            resultSelection = inserted
            source = joinedSource
            revealRequest = RevealRequest(lineID: copyID)
        }
        return copyID
    }

    /// Shows the result of a line in another unit with `→`, or in SI (nil), keeping
    /// the formula and the comment as written.
    public func setDisplayUnit(_ symbol: String?, lineID: UUID) {
        guard let index = lineIndexByID[lineID] else { return }
        let current = resultSelection.entries[index].source
        let updated = LineSyntax(current).replacingConversion(symbol)
        guard updated != current else { return }
        recording("Changer l’unité d’affichage") {
            resultSelection.updateSource(updated, at: index)
            source = joinedSource
        }
    }

    /// The line with its formula written more simply, or nil when it is as simple
    /// as it gets. Computed once per text.
    public func simplification(of lineID: UUID) -> String? {
        guard let source = lineSource(of: lineID) else { return nil }
        if let cached = simplificationCache[source] { return cached }
        let simpler = FormulaSimplifier.simplifiedLine(source)
        if simplificationCache.count >= 1_000 { simplificationCache.removeAll() }
        simplificationCache[source] = .some(simpler)
        return simpler
    }

    /// Rewrites a line in its simpler form, as one undo step.
    public func simplifyLine(id: UUID) {
        guard let index = lineIndexByID[id], let simpler = simplification(of: id) else { return }
        recording("Simplifier la ligne") {
            resultSelection.updateSource(simpler, at: index)
            source = joinedSource
        }
    }

    /// Adds lines at the end of the sheet as one undo step, and shows the first of them.
    /// A blank last line gives way to them.
    public func appendLines(_ sources: [String]) {
        let added = sources.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !added.isEmpty else { return }
        recording(added.count == 1 ? "Ajouter une ligne" : "Ajouter des lignes") {
            if let last = resultSelection.entries.last, !editingLineIDs.contains(last.id),
               last.source.trimmingCharacters(in: .whitespaces).isEmpty {
                resultSelection.removeEntry(at: resultSelection.entries.count - 1)
            }
            var firstID: UUID?
            for line in added {
                let entry = ResultSelection.Entry(source: line)
                guard let inserted = resultSelection.inserting(entry, at: resultSelection.entries.count) else { continue }
                resultSelection = inserted
                firstID = firstID ?? entry.id
            }
            source = joinedSource
            if let firstID { revealRequest = RevealRequest(lineID: firstID) }
        }
    }

    /// The position of a line in the sheet, if it still exists.
    public func lineIndex(of lineID: UUID) -> Int? {
        lineIndexByID[lineID]
    }

    /// The text of a line, if it still exists.
    public func lineSource(of lineID: UUID) -> String? {
        lineIndexByID[lineID].map { resultSelection.entries[$0].source }
    }

    /// The ruler variables a result can be plotted against: those it depends on,
    /// according to its last evaluation, except the line itself.
    public func plotVariables(for lineID: UUID) -> [Variable] {
        let dependencies = resultsByLineID[lineID]?.dependencies ?? []
        return adjustableVariables.filter { $0.id != lineID && dependencies.contains($0.variable.name) }
    }

    public func clear() {
        recording("Effacer la feuille") {
            source = ""
        }
    }

    /// The sheet as text, with the requested values as trailing notes.
    public func sharedText(includingResults: Bool) -> String {
        ResultText.sharedSheet(resultSelection.entries.map { entry in
            guard includingResults, let line = resultsByLineID[entry.id], line.source == entry.source,
                  line.requestsValue, line.kind != .equation, line.status == .success else {
                return (source: entry.source, value: nil)
            }
            return (source: entry.source, value: line.formattedValue)
        })
    }

    // MARK: Undo

    /// Everything an edit can change besides the evaluation, which follows from it.
    struct State: Sendable, Equatable {
        let source: String
        let resultSelection: ResultSelection
        let adjustmentRanges: [UUID: VariableAdjustmentRange]
        let manualStepIDs: Set<UUID>
    }

    /// A step restores a whole earlier state, and only applies while the sheet
    /// is still as the step left it.
    private struct UndoStep {
        let restoring: State
        let expected: State
        let name: String
    }

    private var undoSteps: [UndoStep] = []
    private var redoSteps: [UndoStep] = []

    /// The steps kept in each direction, as the iOS sheet sets on its undo manager. 0 keeps all.
    public var levelsOfUndo = 50 {
        didSet {
            Self.trim(&undoSteps, to: levelsOfUndo)
            Self.trim(&redoSteps, to: levelsOfUndo)
        }
    }

    public var canUndo: Bool { !undoSteps.isEmpty }
    public var canRedo: Bool { !redoSteps.isEmpty }
    /// The name of the step `undo()` reverts, such as « Modifier la ligne ».
    public var undoActionName: String? { undoSteps.last?.name }
    public var redoActionName: String? { redoSteps.last?.name }

    private var state: State {
        State(source: text, resultSelection: resultSelection,
              adjustmentRanges: adjustmentRanges, manualStepIDs: manualStepIDs)
    }

    /// Runs a change and, if it changed the sheet, records one undo step for it.
    /// A new step clears the redo steps.
    public func recording(_ name: String, _ change: () -> Void) {
        let before = state
        change()
        registerUndo(restoring: before, named: name)
    }

    /// Reverts the last step. End any editing session first, as iOS does: a step
    /// is refused, and dropped, when the sheet changed since without a step of its own.
    @discardableResult
    public func undo() -> Bool {
        guard let step = undoSteps.popLast(), restore(step) else { return false }
        redoSteps.append(UndoStep(restoring: step.expected, expected: step.restoring, name: step.name))
        Self.trim(&redoSteps, to: levelsOfUndo)
        return true
    }

    @discardableResult
    public func redo() -> Bool {
        guard let step = redoSteps.popLast(), restore(step) else { return false }
        undoSteps.append(UndoStep(restoring: step.expected, expected: step.restoring, name: step.name))
        Self.trim(&undoSteps, to: levelsOfUndo)
        return true
    }

    /// Drops this sheet's undo steps, for instance when another sheet takes over the window.
    public func removeAllUndoSteps() {
        undoSteps.removeAll()
        redoSteps.removeAll()
        rulerGesture = nil
    }

    private func registerUndo(restoring before: State, named name: String) {
        let after = state
        guard !isClosed, before != after else { return }
        undoSteps.append(UndoStep(restoring: before, expected: after, name: name))
        Self.trim(&undoSteps, to: levelsOfUndo)
        redoSteps.removeAll()
    }

    /// Returns to an earlier state if the sheet is still as the step left it.
    private func restore(_ step: UndoStep) -> Bool {
        guard !isClosed, state == step.expected else { return false }
        let earlier = step.restoring
        // The ranges and the choice come first so that the new text matches
        // the lines already known and every line keeps its identity.
        resultSelection = earlier.resultSelection
        adjustmentRanges = earlier.adjustmentRanges
        manualStepIDs = earlier.manualStepIDs
        text = earlier.source
        linesDidChange(evaluatesImmediately: true)
        return true
    }

    private static func trim(_ steps: inout [UndoStep], to levels: Int) {
        if levels > 0, steps.count > levels { steps.removeFirst(steps.count - levels) }
    }

    // MARK: Evaluation

    /// A text to evaluate, with the identities its lines had then.
    public struct EvaluationRequest: Sendable, Equatable {
        public let source: String
        public let lineIDs: [UUID]
        /// Orders the requests of a session: a later change has a larger revision.
        public let revision: Int
        /// True after typing: iOS waits `typingDelay` without a newer change before
        /// evaluating. False when the sheet opens, for a ruler, and after undo or redo.
        public let isDebounced: Bool
    }

    /// A finished evaluation, for `apply(_:onlyIfCurrent:)`.
    public struct Evaluation: Sendable {
        public let request: EvaluationRequest
        public let result: NotebookEvaluation
    }

    /// The pause iOS waits for after typing before it evaluates, in seconds.
    public static let typingDelay = 0.18
    /// How long an evaluation runs before iOS shows its progress indicator, in seconds.
    public static let progressDelay = 0.25

    /// The current text and line identities, to evaluate while `needsEvaluation`.
    public var evaluationRequest: EvaluationRequest {
        EvaluationRequest(source: text, lineIDs: resultSelection.entries.map(\.id),
                          revision: revision, isDebounced: evaluationIsDebounced)
    }

    /// True until an evaluation of the current text and lines is applied.
    public var needsEvaluation: Bool {
        guard let shownRequest else { return true }
        return !isCurrent(shownRequest)
    }

    /// Evaluates a request. Pure: call it from any thread.
    public static func evaluate(_ request: EvaluationRequest) -> Evaluation {
        Evaluation(request: request, result: NotebookEngine.evaluate(request.source))
    }

    /// Shows a finished evaluation and returns true. As on iOS, an evaluation of
    /// an earlier text is shown too: results go to the lines by the identities of
    /// the request, and a line edited since keeps a stale result (`isResultStale`)
    /// until the next one. Returns false, changing nothing, when the session is
    /// closed, when a later request is already shown, or, with `onlyIfCurrent`,
    /// when the text or its lines changed since the request.
    @discardableResult
    public func apply(_ evaluation: Evaluation, onlyIfCurrent: Bool = false) -> Bool {
        let request = evaluation.request
        guard !isClosed, request.revision >= shownRequest?.revision ?? .min else { return false }
        let isCurrent = isCurrent(request)
        if onlyIfCurrent && !isCurrent { return false }
        let result = evaluation.result
        if result.lines.count == request.lineIDs.count {
            resultsByLineID = Dictionary(zip(request.lineIDs, result.lines), uniquingKeysWith: { first, _ in first })
            sheetIssue = nil
        } else {
            // The engine refuses the whole sheet, for instance when it is too long.
            resultsByLineID = [:]
            sheetIssue = result.lines.first?.message
        }
        constants = result.constants
        symbolUnits = result.symbolUnits
        declaredNames = result.variables.map(\.name).sorted()
        hasEvaluation = true
        shownRequest = request
        refreshPreview()
        // An evaluation that a newer edit already supersedes stays silent.
        if announcesNextEvaluation && isCurrent {
            announcesNextEvaluation = false
            pendingAnnouncement = announcement()
        }
        return true
    }

    /// What a screen reader user cannot see change after a ruler adjustment made
    /// with `announcesResults`, once its evaluation is applied; nil afterwards.
    public func takeAnnouncement() -> String? {
        defer { pendingAnnouncement = nil }
        return pendingAnnouncement
    }

    private func isCurrent(_ request: EvaluationRequest) -> Bool {
        request.source == text && request.lineIDs == refreshedLineIDs
    }

    /// The first requested results and errors, at most three. A ruler’s own line
    /// is left out, since its new value was just read.
    private func announcement() -> String? {
        let phrases = resultSelection.entries.enumerated().compactMap { index, entry -> String? in
            guard let line = resultsByLineID[entry.id], line.source == entry.source,
                  variablesByLineID[entry.id] == nil else { return nil }
            if line.status == .error { return "Erreur à la ligne \(index + 1)" }
            guard line.requestsValue, line.kind != .equation, let spoken = line.spokenResult else { return nil }
            return ResultText.spokenLine(source: entry.source, spokenValue: spoken)
        }
        return phrases.isEmpty ? nil : phrases.prefix(3).joined(separator: ". ")
    }

    // MARK: Changes

    private var joinedSource: String {
        resultSelection.entries.map(\.source).joined(separator: "\n")
    }

    private func setSource(_ newValue: String, evaluatesImmediately: Bool) {
        // Equal lines that swap change the identities without the text.
        guard newValue != text || resultSelection.entries.map(\.id) != refreshedLineIDs else { return }
        text = newValue
        resultSelection.reconcile(source: text)
        // A line cut and pasted back keeps its ruler, so detached lines count.
        let lineIDs = resultSelection.retainedIDs
        if adjustmentRanges.keys.contains(where: { !lineIDs.contains($0) }) {
            adjustmentRanges = adjustmentRanges.filter { lineIDs.contains($0.key) }
        }
        if !manualStepIDs.isSubset(of: lineIDs) {
            manualStepIDs.formIntersection(lineIDs)
        }
        linesDidChange(evaluatesImmediately: evaluatesImmediately)
    }

    private func linesDidChange(evaluatesImmediately: Bool) {
        refreshLines()
        recordDidChange()
        revision += 1
        evaluationIsDebounced = !evaluatesImmediately
    }

    private func recordDidChange(updatesModificationDate: Bool = true) {
        guard !isClosed else { return }
        if updatesModificationDate { modifiedAt = Date() }
        let record = record
        displayTitle = record.displayTitle
        onChange(record)
    }

    /// Rebuilds what depends on the lines themselves, then the preview.
    private func refreshLines() {
        var cache: [String: AdjustableVariable?] = [:]
        var indices: [UUID: Int] = [:]
        var formulas: [FormulaLine] = []
        var variables: [Variable] = []
        var variablesByID: [UUID: AdjustableVariable] = [:]
        for (index, entry) in resultSelection.entries.enumerated() {
            indices[entry.id] = index
            if editingLineIDs.contains(entry.id) || !entry.source.trimmingCharacters(in: .whitespaces).isEmpty {
                formulas.append(FormulaLine(index: index, entry: entry))
            }
            let variable: AdjustableVariable?
            if let cached = cache[entry.source] ?? variableCache[entry.source] {
                variable = cached
            } else {
                variable = AdjustableVariable(source: entry.source)
            }
            cache[entry.source] = .some(variable)
            if let variable {
                variables.append(Variable(id: entry.id, variable: variable))
                variablesByID[entry.id] = variable
            }
        }
        variableCache = cache
        lineIndexByID = indices
        refreshedLineIDs = resultSelection.entries.map(\.id)
        formulaLines = formulas
        adjustableVariables = variables
        variablesByLineID = variablesByID
        if let ruler = activeRulerLineID, variablesByID[ruler] == nil { activeRulerLineID = nil }
        refreshPreview()
    }

    /// The preview of the sheet list: the first line that asks for its value and has a current one.
    private func refreshPreview() {
        var preview: SheetRecord.ResultPreview?
        for entry in resultSelection.entries {
            guard let line = resultsByLineID[entry.id], line.source == entry.source,
                  line.requestsValue, line.kind != .equation,
                  let found = SheetRecord.previewWithSpeech(of: line) else { continue }
            preview = found
            break
        }
        resultPreview = preview?.text
        spokenResultPreview = preview?.spoken
    }
}

extension SheetSession {
    /// A line shown in the sheet, with its position among all the lines.
    public struct FormulaLine: Identifiable, Equatable, Sendable {
        public var id: UUID { entry.id }
        public let index: Int
        public let entry: ResultSelection.Entry
    }

    /// A line that declares an adjustable number.
    public struct Variable: Identifiable, Sendable {
        public let id: UUID
        public let variable: AdjustableVariable
    }

    /// Asks the sheet view to scroll to a line. Each request is distinct.
    public struct RevealRequest: Equatable, Sendable {
        public let id = UUID()
        public let lineID: UUID
    }
}
