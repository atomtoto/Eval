import EvalCore
import Foundation
import Observation

/// The editing session of one sheet. Windows showing the same sheet share it.
///
/// Derived data is computed once per change of the source or the evaluation,
/// never while a view renders. Results are attached to the
/// identity of their line, so a line keeps showing its last value while it is
/// edited, moved or while lines are inserted above it.
@MainActor
@Observable
final class NotebookStore {
    let id: UUID

    var source: String {
        get { text }
        set { setSource(newValue, evaluatesImmediately: false) }
    }

    var customTitle: String? {
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

    /// Ends the automatic naming of the sheet: it takes `title` if it is still
    /// called « Nouvelle feuille » and was not named meanwhile. A nil title only
    /// records the attempt. The modification date does not change.
    func applyAutomaticTitle(_ title: String?) {
        guard !isClosed, !automaticTitleAttempted else { return }
        automaticTitleAttempted = true
        if let title, storedTitle == nil, SheetRecord.noteTitle(in: text) == nil {
            storedTitle = title
        }
        recordDidChange(updatesModificationDate: false)
    }

    private(set) var resultSelection: ResultSelection
    /// Constants used by the latest evaluation, which may describe an earlier text.
    private(set) var constants: [ConstantDefinition] = []
    /// Undeclared symbols the latest evaluation read as units, such as `T` as the tesla.
    private(set) var symbolUnits: [UnitDefinition] = []
    /// False until the first evaluation of this session finishes.
    private(set) var hasEvaluation = false
    /// True only while an evaluation takes noticeably long, for the progress indicator.
    private(set) var isEvaluating = false
    private(set) var adjustmentRanges: [UUID: VariableAdjustmentRange]
    private(set) var manualStepIDs: Set<UUID>
    private(set) var modifiedAt: Date
    private(set) var displayTitle: String

    // Derived data.
    /// The lines shown in the sheet: every line but blank ones, unless a blank
    /// line is being edited.
    private(set) var formulaLines: [IndexedFormulaLine] = []
    private(set) var adjustableVariables: [NotebookVariable] = []
    private(set) var variablesByLineID: [UUID: AdjustableVariable] = [:]
    /// The line whose ruler is open in a popover, at most one. A long press on its value opens it.
    var activeRulerLineID: UUID?
    /// Lines being edited in place, shown even while blank.
    private(set) var editingLineIDs: Set<UUID> = []
    /// A problem with the whole sheet, such as its length.
    private(set) var sheetIssue: String?
    private(set) var resultPreview: String?
    private(set) var spokenResultPreview: String?
    /// Names declared in the sheet, from the latest evaluation, for the insertion menu.
    private(set) var declaredNames: [String] = []
    /// Asks the sheet view to scroll to a line that was just added.
    private(set) var revealRequest: RevealRequest?

    private var text: String
    private var storedTitle: String?
    @ObservationIgnored private var automaticTitleAttempted: Bool
    private var resultsByLineID: [UUID: EvaluatedLine] = [:]
    @ObservationIgnored private let createdAt: Date
    @ObservationIgnored private var lineIndexByID: [UUID: Int] = [:]
    /// Parsing a declaration evaluates it; unchanged lines reuse the previous parse.
    @ObservationIgnored private var variableCache: [String: AdjustableVariable?] = [:]
    /// The simpler form of each line text met, nil when it is as simple as it gets.
    @ObservationIgnored private var simplificationCache: [String: String?] = [:]
    @ObservationIgnored private var rulerGesture: (state: SheetState, name: String)?
    @ObservationIgnored private var pendingSnapshot: Snapshot?
    @ObservationIgnored private var evaluationLoop: Task<Void, Never>?
    @ObservationIgnored private var loopIsWaiting = false
    @ObservationIgnored private var loopGeneration = 0
    @ObservationIgnored private var progressTask: Task<Void, Never>?
    @ObservationIgnored private var isClosed = false
    /// Set by a VoiceOver ruler adjustment: the next evaluation to finish is read aloud.
    @ObservationIgnored private var announcesNextEvaluation = false
    @ObservationIgnored private let onChange: @MainActor (SheetRecord) -> Void

    /// `onChange` receives the updated record after every edit; it is not
    /// called for the initial state. The first evaluation starts at once,
    /// away from the main thread.
    init(record: SheetRecord, onChange: @escaping @MainActor (SheetRecord) -> Void) {
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
        requestEvaluation(debounced: false)
    }

    var record: SheetRecord {
        SheetRecord(id: id, customTitle: storedTitle, automaticTitleAttempted: automaticTitleAttempted,
                    source: text, resultSelection: resultSelection,
                    adjustmentRanges: adjustmentRanges, manualStepIDs: manualStepIDs,
                    createdAt: createdAt, modifiedAt: modifiedAt)
    }

    /// The last result of a line, possibly computed for an earlier text of that line.
    func result(for lineID: UUID) -> EvaluatedLine? {
        resultsByLineID[lineID]
    }

    // MARK: Rulers

    /// The interval a plot covers, and the step of the ruler: the settings saved for
    /// the line, else an interval around the current value. The ruler itself has no bounds.
    func adjustmentRange(for id: UUID, variable: AdjustableVariable) -> VariableAdjustmentRange? {
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
    func rulerStep(for id: UUID, variable: AdjustableVariable) -> Double {
        if manualStepIDs.contains(id), let step = adjustmentRanges[id]?.step { return step }
        return variable.automaticStep
    }

    func setAdjustmentRange(_ range: VariableAdjustmentRange, for id: UUID, automaticStep: Bool = true) {
        adjustmentRanges[id] = range
        if automaticStep { manualStepIDs.remove(id) } else { manualStepIDs.insert(id) }
        recordDidChange()
    }

    /// Results follow the ruler: the evaluation starts without the typing delay.
    /// With `announcesResults`, the recalculated results are read aloud once they arrive.
    func adjustVariable(_ value: Double, lineID: UUID, announcesResults: Bool = false) {
        guard let index = lineIndexByID[lineID],
              let variable = variablesByLineID[lineID],
              value != variable.value,
              let updated = variable.source(replacingValue: value) else { return }
        resultSelection.updateSource(updated, at: index)
        if announcesResults { announcesNextEvaluation = true }
        setSource(joinedSource, evaluatesImmediately: true)
    }

    /// A ruler gesture, from touch down to release, is one undo step.
    func rulerEditingChanged(_ isEditing: Bool, name: String, undoManager: UndoManager?) {
        if isEditing {
            if rulerGesture == nil { rulerGesture = (state, String(localized: "Ajuster \(name)")) }
        } else if let gesture = rulerGesture {
            rulerGesture = nil
            registerUndo(restoring: gesture.state, named: gesture.name, undoManager: undoManager)
        }
    }

    // MARK: Lines

    /// Adds a line at the end and asks the sheet view to show it. By default the
    /// line asks for its value with a final `=`, so an inserted constant shows it.
    @discardableResult
    func append(_ expression: String, requestsResult: Bool = true) -> UUID? {
        let line = requestsResult ? LineSyntax(expression).addingResultRequest() : expression
        source += source.isEmpty || source.hasSuffix("\n") ? line : "\n\(line)"
        guard let id = resultSelection.entries.last?.id else { return nil }
        revealRequest = RevealRequest(lineID: id)
        return id
    }

    // MARK: Editing in place

    /// One editing session of a line, from the focus to its loss: one undo step.
    struct LineEditingSession: Equatable {
        let lineID: UUID
        /// True for a line created for this session, which disappears if left blank.
        let isNew: Bool
        fileprivate let before: SheetState
    }

    /// Starts editing a line: it stays visible while blank, and the ruler closes.
    func beginEditing(lineID: UUID) -> LineEditingSession? {
        guard lineIndexByID[lineID] != nil else { return nil }
        let session = LineEditingSession(lineID: lineID, isNew: false, before: state)
        activeRulerLineID = nil
        editingLineIDs.insert(lineID)
        return session
    }

    /// Inserts blank lines, or the given ones, after `lineID` (at the end for nil)
    /// and starts editing the last of them.
    func insertLines(_ sources: [String] = [""], after lineID: UUID?) -> LineEditingSession? {
        insertLines(sources, at: lineID.flatMap { lineIndexByID[$0] }.map { $0 + 1 })
    }

    /// Inserts lines at a position of the sheet (at the end for nil) and starts
    /// editing the last of them.
    func insertLines(_ sources: [String], at position: Int?) -> LineEditingSession? {
        let before = state
        // A blank last line, hidden in the sheet, takes the new text rather than staying above it.
        if position == nil, sources.count == 1, let last = resultSelection.entries.last,
           !editingLineIDs.contains(last.id), last.source.trimmingCharacters(in: .whitespaces).isEmpty {
            activeRulerLineID = nil
            editingLineIDs.insert(last.id)
            refreshLines()
            updateLine(sources[0], lineID: last.id)
            revealRequest = RevealRequest(lineID: last.id)
            return LineEditingSession(lineID: last.id, isNew: true, before: before)
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
        return LineEditingSession(lineID: lastID, isNew: true, before: before)
    }

    /// The live text of a line being edited. A single line only: see `splitLine`.
    func updateLine(_ text: String, lineID: UUID) {
        guard let index = lineIndexByID[lineID], resultSelection.entries[index].source != text,
              !text.contains(where: \.isNewline) else { return }
        resultSelection.updateSource(text, at: index)
        setSource(joinedSource, evaluatesImmediately: false)
    }

    /// Ends an editing session: a line left blank is removed, then the whole
    /// session becomes one undo step.
    func endEditing(_ session: LineEditingSession, undoManager: UndoManager?) {
        editingLineIDs.remove(session.lineID)
        guard let index = lineIndexByID[session.lineID] else {
            refreshLines()
            return
        }
        var removed = false
        if resultSelection.entries[index].source.trimmingCharacters(in: .whitespaces).isEmpty {
            resultSelection.removeEntry(at: index)
            removed = true
            setSource(joinedSource, evaluatesImmediately: false)
        }
        refreshLines()
        let name = session.isNew ? "Ajouter une ligne" : removed ? "Supprimer la ligne" : "Modifier la ligne"
        registerUndo(restoring: session.before, named: name, undoManager: undoManager)
    }

    func removeLine(id: UUID, undoManager: UndoManager? = nil) {
        guard let index = lineIndexByID[id] else { return }
        recording("Supprimer la ligne", undoManager: undoManager) {
            resultSelection.removeEntry(at: index)
            source = joinedSource
        }
    }

    /// Deletes the lines at these offsets of the visible lines.
    func removeLines(atOffsets offsets: IndexSet, undoManager: UndoManager? = nil) {
        let indices = offsets.compactMap { formulaLines.indices.contains($0) ? formulaLines[$0].index : nil }
        guard !indices.isEmpty else { return }
        recording(indices.count == 1 ? "Supprimer la ligne" : "Supprimer les lignes", undoManager: undoManager) {
            for index in indices.sorted(by: >) { resultSelection.removeEntry(at: index) }
            source = joinedSource
        }
    }

    /// Moves visible lines. Blank lines, which Formules mode hides, keep their
    /// position; the line identities, and so the choices and rulers, follow.
    func moveLines(fromOffsets offsets: IndexSet, toOffset destination: Int, undoManager: UndoManager? = nil) {
        guard let order = LineReordering.order(count: resultSelection.entries.count, visible: formulaLines.map(\.index),
                                               moving: offsets, to: destination),
              let moved = resultSelection.rearranged(by: order) else { return }
        recording(offsets.count == 1 ? "Déplacer la ligne" : "Déplacer les lignes", undoManager: undoManager) {
            resultSelection = moved
            source = joinedSource
        }
    }

    /// Copies a line right below itself and returns the copy, which the sheet
    /// opens for editing: a declaration's copy needs another name.
    @discardableResult
    func duplicateLine(id: UUID, undoManager: UndoManager? = nil) -> UUID? {
        guard let index = lineIndexByID[id],
              let inserted = resultSelection.inserting(ResultSelection.Entry(source: resultSelection.entries[index].source),
                                                       at: index + 1) else { return nil }
        let copyID = inserted.entries[index + 1].id
        recording("Dupliquer la ligne", undoManager: undoManager) {
            resultSelection = inserted
            source = joinedSource
            revealRequest = RevealRequest(lineID: copyID)
        }
        return copyID
    }

    /// Shows the result of a line in another unit with `→`, or in SI (nil), keeping
    /// the formula and the comment as written.
    func setDisplayUnit(_ symbol: String?, lineID: UUID, undoManager: UndoManager? = nil) {
        guard let index = lineIndexByID[lineID] else { return }
        let current = resultSelection.entries[index].source
        let updated = LineSyntax(current).replacingConversion(symbol)
        guard updated != current else { return }
        recording("Changer l’unité d’affichage", undoManager: undoManager) {
            resultSelection.updateSource(updated, at: index)
            source = joinedSource
        }
    }

    /// The line with its formula written more simply, or nil when it is as simple
    /// as it gets. Computed once per text.
    func simplification(of lineID: UUID) -> String? {
        guard let source = lineSource(of: lineID) else { return nil }
        if let cached = simplificationCache[source] { return cached }
        let simpler = FormulaSimplifier.simplifiedLine(source)
        if simplificationCache.count >= 1_000 { simplificationCache.removeAll() }
        simplificationCache[source] = .some(simpler)
        return simpler
    }

    /// Rewrites a line in its simpler form, as one undo step.
    func simplifyLine(id: UUID, undoManager: UndoManager? = nil) {
        guard let index = lineIndexByID[id], let simpler = simplification(of: id) else { return }
        recording("Simplifier la ligne", undoManager: undoManager) {
            resultSelection.updateSource(simpler, at: index)
            source = joinedSource
        }
    }

    /// Adds lines at the end of the sheet as one undo step, and shows the first of them.
    /// A blank last line gives way to them.
    func appendLines(_ sources: [String], undoManager: UndoManager? = nil) {
        let added = sources.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard !added.isEmpty else { return }
        recording(added.count == 1 ? "Ajouter une ligne" : "Ajouter des lignes", undoManager: undoManager) {
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
    func lineIndex(of lineID: UUID) -> Int? {
        lineIndexByID[lineID]
    }

    /// The text of a line, if it still exists.
    func lineSource(of lineID: UUID) -> String? {
        lineIndexByID[lineID].map { resultSelection.entries[$0].source }
    }

    /// The ruler variables a result can be plotted against: those it depends on,
    /// according to its last evaluation, except the line itself.
    func plotVariables(for lineID: UUID) -> [NotebookVariable] {
        let dependencies = resultsByLineID[lineID]?.dependencies ?? []
        return adjustableVariables.filter { $0.id != lineID && dependencies.contains($0.variable.name) }
    }

    /// Opens the ruler of a line, closing any other.
    func showRuler(lineID: UUID) {
        guard variablesByLineID[lineID] != nil else { return }
        activeRulerLineID = lineID
    }

    func clear(undoManager: UndoManager? = nil) {
        recording("Effacer la feuille", undoManager: undoManager) {
            source = ""
        }
    }

    /// The sheet as text, with the requested values as trailing notes.
    func sharedText(includingResults: Bool) -> String {
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
    struct SheetState: Sendable, Equatable {
        let source: String
        let resultSelection: ResultSelection
        let adjustmentRanges: [UUID: VariableAdjustmentRange]
        let manualStepIDs: Set<UUID>
    }

    private var state: SheetState {
        SheetState(source: text, resultSelection: resultSelection,
                   adjustmentRanges: adjustmentRanges, manualStepIDs: manualStepIDs)
    }

    /// Runs a change and, if it changed the sheet, registers one undo step for it.
    /// Pass the window's undo manager; nil makes the change without undo.
    func recording(_ name: String, undoManager: UndoManager?, _ change: () -> Void) {
        let before = state
        change()
        registerUndo(restoring: before, named: name, undoManager: undoManager)
    }

    /// Windows showing this sheet each have an undo manager, but a step restores a
    /// whole earlier state. A step therefore only applies while the sheet is still
    /// as that step left it; after an edit in another window it would erase that
    /// edit, so it is refused instead.
    private func registerUndo(restoring before: SheetState, named name: String, undoManager: UndoManager?) {
        guard let undoManager, before != state else { return }
        let after = state
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated {
                target.restore(before, ifCurrentIs: after, named: name, undoManager: undoManager)
            }
        }
        undoManager.setActionName(name)
    }

    /// Returns to an earlier state. The undo manager registers the opposite
    /// step as a redo (or an undo) because this runs while it undoes (or redoes).
    private func restore(_ earlier: SheetState, ifCurrentIs expected: SheetState, named name: String,
                         undoManager: UndoManager) {
        guard !isClosed, state == expected else {
            if !isClosed {
                VoiceOverAnnouncement.post(String(localized: "Action impossible : la feuille a été modifiée dans une autre fenêtre."))
            }
            return
        }
        let current = state
        // The ranges and the choice come first so that the new text matches
        // the lines already known and every line keeps its identity.
        resultSelection = earlier.resultSelection
        adjustmentRanges = earlier.adjustmentRanges
        manualStepIDs = earlier.manualStepIDs
        text = earlier.source
        refreshLines()
        recordDidChange()
        requestEvaluation(debounced: false)
        registerUndo(restoring: current, named: name, undoManager: undoManager)
    }

    /// Drops this sheet's undo steps, for instance when the text editor takes over.
    func removeUndoSteps(from undoManager: UndoManager?) {
        undoManager?.removeAllActions(withTarget: self)
        rulerGesture = nil
    }

    /// Stops background work once the sheet is deleted.
    func close() {
        isClosed = true
        pendingSnapshot = nil
        evaluationLoop?.cancel()
        evaluationLoop = nil
        progressTask?.cancel()
        progressTask = nil
    }

    // MARK: Changes

    private var joinedSource: String {
        resultSelection.entries.map(\.source).joined(separator: "\n")
    }

    private func setSource(_ newValue: String, evaluatesImmediately: Bool) {
        guard newValue != text else { return }
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
        refreshLines()
        recordDidChange()
        requestEvaluation(debounced: !evaluatesImmediately)
    }

    private func recordDidChange(updatesModificationDate: Bool = true) {
        guard !isClosed else { return }
        if updatesModificationDate { modifiedAt = Date() }
        let record = record
        if displayTitle != record.displayTitle { displayTitle = record.displayTitle }
        onChange(record)
    }

    /// Rebuilds what depends on the lines themselves, then the preview.
    private func refreshLines() {
        var cache: [String: AdjustableVariable?] = [:]
        var indices: [UUID: Int] = [:]
        var formulas: [IndexedFormulaLine] = []
        var variables: [NotebookVariable] = []
        var variablesByID: [UUID: AdjustableVariable] = [:]
        for (index, entry) in resultSelection.entries.enumerated() {
            indices[entry.id] = index
            if editingLineIDs.contains(entry.id) || !entry.source.trimmingCharacters(in: .whitespaces).isEmpty {
                formulas.append(IndexedFormulaLine(index: index, entry: entry))
            }
            let variable: AdjustableVariable?
            if let cached = cache[entry.source] ?? variableCache[entry.source] {
                variable = cached
            } else {
                variable = AdjustableVariable(source: entry.source)
            }
            cache[entry.source] = .some(variable)
            if let variable {
                variables.append(NotebookVariable(id: entry.id, variable: variable))
                variablesByID[entry.id] = variable
            }
        }
        variableCache = cache
        lineIndexByID = indices
        if formulaLines != formulas { formulaLines = formulas }
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
        if resultPreview != preview?.text { resultPreview = preview?.text }
        if spokenResultPreview != preview?.spoken { spokenResultPreview = preview?.spoken }
    }

    // MARK: Evaluation

    private struct Snapshot: Sendable {
        let source: String
        let lineIDs: [UUID]
    }

    /// Evaluations run one at a time, always on the latest text. While one runs,
    /// further edits only replace the pending text, so typing and dragging a
    /// ruler refresh the results continuously instead of piling up work.
    private func requestEvaluation(debounced: Bool) {
        guard !isClosed else { return }
        pendingSnapshot = Snapshot(source: text, lineIDs: resultSelection.entries.map(\.id))
        if evaluationLoop != nil {
            // A ruler does not wait for the end of the typing delay.
            guard !debounced && loopIsWaiting else { return }
            evaluationLoop?.cancel()
        }
        startEvaluationLoop(debounced: debounced)
    }

    private func startEvaluationLoop(debounced: Bool) {
        loopGeneration += 1
        let generation = loopGeneration
        loopIsWaiting = debounced
        evaluationLoop = Task { [weak self] in
            if debounced {
                do {
                    try await Task.sleep(for: .milliseconds(180))
                } catch {
                    return
                }
                // Cancellation can arrive just after the wait ends. Then a newer
                // loop owns the pending text, or the sheet is closed.
                guard !Task.isCancelled, self?.loopGeneration == generation else { return }
            }
            self?.loopIsWaiting = false
            self?.showProgressIfSlow(generation: generation)
            while let snapshot = self?.takePendingSnapshot() {
                let evaluation = await Self.evaluate(snapshot.source)
                // Past the wait, only closing the sheet cancels this task, and
                // publishing checks for that: a finished evaluation is never discarded.
                guard let self else { return }
                self.publish(evaluation, for: snapshot)
            }
            self?.evaluationLoopDidFinish(generation: generation)
        }
    }

    private func takePendingSnapshot() -> Snapshot? {
        defer { pendingSnapshot = nil }
        return pendingSnapshot
    }

    @concurrent
    private nonisolated static func evaluate(_ source: String) async -> NotebookEvaluation {
        NotebookEngine.evaluate(source)
    }

    private func publish(_ evaluation: NotebookEvaluation, for snapshot: Snapshot) {
        guard !isClosed else { return }
        if evaluation.lines.count == snapshot.lineIDs.count {
            resultsByLineID = Dictionary(zip(snapshot.lineIDs, evaluation.lines), uniquingKeysWith: { first, _ in first })
            sheetIssue = nil
        } else {
            // The engine refuses the whole sheet, for instance when it is too long.
            resultsByLineID = [:]
            sheetIssue = evaluation.lines.first?.message
        }
        constants = evaluation.constants
        symbolUnits = evaluation.symbolUnits
        let names = evaluation.variables.map(\.name).sorted()
        if declaredNames != names { declaredNames = names }
        hasEvaluation = true
        refreshPreview()
        // An evaluation that a newer edit already supersedes stays silent.
        if announcesNextEvaluation && pendingSnapshot == nil {
            announcesNextEvaluation = false
            announceResults()
        }
    }

    /// What a VoiceOver user cannot see change: the first requested results and
    /// errors, at most three. A ruler’s own line is left out, since its new value was just read.
    private func announceResults() {
        let phrases = resultSelection.entries.enumerated().compactMap { index, entry -> String? in
            guard let line = resultsByLineID[entry.id], line.source == entry.source,
                  variablesByLineID[entry.id] == nil else { return nil }
            if line.status == .error { return String(localized: "Erreur à la ligne \(index + 1)") }
            guard line.requestsValue, line.kind != .equation, let spoken = line.spokenResult else { return nil }
            return ResultText.spokenLine(source: entry.source, spokenValue: spoken)
        }
        guard !phrases.isEmpty else { return }
        VoiceOverAnnouncement.post(phrases.prefix(3).joined(separator: ". "))
    }

    /// Fast evaluations never flash the progress indicator.
    private func showProgressIfSlow(generation: Int) {
        progressTask?.cancel()
        progressTask = Task { [weak self] in
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch {
                return
            }
            guard let self, self.loopGeneration == generation, self.evaluationLoop != nil else { return }
            self.isEvaluating = true
        }
    }

    private func evaluationLoopDidFinish(generation: Int) {
        guard loopGeneration == generation else { return }
        evaluationLoop = nil
        progressTask?.cancel()
        progressTask = nil
        if isEvaluating { isEvaluating = false }
    }
}

/// Asks the sheet view to scroll to a line. Each request is distinct.
struct RevealRequest: Equatable {
    let id = UUID()
    let lineID: UUID
}

struct NotebookVariable: Identifiable {
    let id: UUID
    let variable: AdjustableVariable
}

struct IndexedFormulaLine: Identifiable, Equatable {
    var id: UUID { entry.id }
    let index: Int
    let entry: ResultSelection.Entry
}
