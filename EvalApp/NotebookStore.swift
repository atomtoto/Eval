import EvalCore
import Foundation
import Observation

/// The editing session of one sheet. Windows showing the same sheet share it.
///
/// Derived data is computed once per change of the source, the result choice
/// or the evaluation, never while a view renders. Results are attached to the
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
            recordDidChange()
        }
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
    private(set) var formulaLines: [IndexedFormulaLine] = []
    private(set) var adjustableVariables: [NotebookVariable] = []
    private(set) var variablesByLineID: [UUID: AdjustableVariable] = [:]
    /// Lines that can show a result: everything except empty lines and notes.
    private(set) var selectableLines: [LineResult] = []
    private(set) var displayedResults: [LineResult] = []
    /// Hidden lines whose last evaluation failed.
    private(set) var hiddenErrors: [LineResult] = []
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
    private var resultsByLineID: [UUID: EvaluatedLine] = [:]
    @ObservationIgnored private let createdAt: Date
    @ObservationIgnored private var lineIndexByID: [UUID: Int] = [:]
    /// Parsing a declaration evaluates it; unchanged lines reuse the previous parse.
    @ObservationIgnored private var variableCache: [String: AdjustableVariable?] = [:]
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
        SheetRecord(id: id, customTitle: storedTitle, source: text, resultSelection: resultSelection,
                    adjustmentRanges: adjustmentRanges, manualStepIDs: manualStepIDs,
                    createdAt: createdAt, modifiedAt: modifiedAt)
    }

    /// The last result of a line, possibly computed for an earlier text of that line.
    func result(for lineID: UUID) -> EvaluatedLine? {
        resultsByLineID[lineID]
    }

    // MARK: Rulers

    func adjustmentRange(for id: UUID, variable: AdjustableVariable) -> VariableAdjustmentRange? {
        if let range = adjustmentRanges[id] {
            if manualStepIDs.contains(id) { return range }
            return VariableAdjustmentRange(lowerBound: range.lowerBound, upperBound: range.upperBound,
                                           step: min(range.upperBound - range.lowerBound, variable.automaticStep))
                ?? VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep)
        }
        return VariableAdjustmentRange.suggested(for: variable.value, step: variable.automaticStep)
    }

    func setAdjustmentRange(_ range: VariableAdjustmentRange, for id: UUID, automaticStep: Bool = true) {
        adjustmentRanges[id] = range
        if automaticStep { manualStepIDs.remove(id) } else { manualStepIDs.insert(id) }
        recordDidChange()
    }

    /// Results follow the ruler: the evaluation starts without the typing delay.
    /// With `announcesResults`, the recalculated results are read aloud once they arrive.
    func adjustVariable(_ value: Double, lineID: UUID, range: VariableAdjustmentRange, announcesResults: Bool = false) {
        guard let index = lineIndexByID[lineID],
              let variable = variablesByLineID[lineID],
              value != variable.value,
              let updated = variable.source(replacingValue: value) else { return }
        adjustmentRanges[lineID] = range
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

    /// Adds a line at the end and asks the sheet view to show it.
    @discardableResult
    func append(_ expression: String, showsResult: Bool = true) -> UUID? {
        source += source.isEmpty || source.hasSuffix("\n") ? expression : "\n\(expression)"
        let index = resultSelection.entries.count - 1
        setResultDisplayed(showsResult, at: index)
        guard resultSelection.entries.indices.contains(index) else { return nil }
        let id = resultSelection.entries[index].id
        revealRequest = RevealRequest(lineID: id)
        return id
    }

    func saveFormula(_ expression: String, lineID: UUID?, showsResult: Bool, undoManager: UndoManager? = nil) {
        let isNew = lineID.flatMap { lineIndexByID[$0] } == nil
        recording(isNew ? "Ajouter une formule" : "Modifier la formule", undoManager: undoManager) {
            guard let lineID, let index = lineIndexByID[lineID] else {
                append(expression, showsResult: showsResult)
                return
            }
            resultSelection.updateSource(expression, at: index)
            source = joinedSource
            setResultDisplayed(showsResult, at: index)
        }
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

    /// Copies a formula or expression right below itself. A declaration is not
    /// duplicated, since a name can be declared only once: the editor handles it.
    func duplicateLine(id: UUID, undoManager: UndoManager? = nil) {
        guard let index = lineIndexByID[id],
              let inserted = resultSelection.inserting(ResultSelection.Entry(source: resultSelection.entries[index].source),
                                                       at: index + 1) else { return }
        recording("Dupliquer la ligne", undoManager: undoManager) {
            resultSelection = inserted
            source = joinedSource
            revealRequest = RevealRequest(lineID: inserted.entries[index + 1].id)
        }
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

    /// The position of a line in the sheet, if it still exists.
    func lineIndex(of lineID: UUID) -> Int? {
        lineIndexByID[lineID]
    }

    /// The text of a line, if it still exists.
    func lineSource(of lineID: UUID) -> String? {
        lineIndexByID[lineID].map { resultSelection.entries[$0].source }
    }

    /// The ruler variables a result can be plotted against: all but the line itself.
    func plotVariables(for lineID: UUID) -> [NotebookVariable] {
        adjustableVariables.filter { $0.id != lineID }
    }

    /// Evaluates the sheet with a draft in place of a line (or after the last
    /// one for a new line), away from the main thread, and returns that line.
    /// The editor uses it to know the dimension of a draft.
    func evaluatedLine(for draft: String, replacing lineID: UUID?) async -> EvaluatedLine? {
        var lines = resultSelection.entries.map(\.source)
        let index: Int
        if let lineID, let existing = lineIndexByID[lineID] {
            index = existing
            lines[index] = draft
        } else {
            index = lines.count
            lines.append(draft)
        }
        let evaluation = await Self.evaluate(lines.joined(separator: "\n"))
        return evaluation.lines.indices.contains(index) ? evaluation.lines[index] : nil
    }

    /// Whether the line is a declaration, whose copy would redeclare its name.
    func isDeclaration(lineID: UUID) -> Bool {
        guard let index = lineIndexByID[lineID] else { return false }
        return ResultText.declaredName(in: resultSelection.entries[index].source) != nil
    }

    func clear(undoManager: UndoManager? = nil) {
        recording("Effacer la feuille", undoManager: undoManager) {
            source = ""
        }
    }

    /// The sheet as text, with the displayed values as trailing notes.
    func sharedText(includingResults: Bool) -> String {
        let values: [UUID: String] = includingResults
            ? Dictionary(uniqueKeysWithValues: displayedResults.compactMap { item in
                guard item.isCurrent, let value = item.line?.formattedValue else { return nil }
                return (item.id, value)
            })
            : [:]
        return ResultText.sharedSheet(resultSelection.entries.map { (source: $0.source, value: values[$0.id]) })
    }

    // MARK: Results

    func setResultDisplayed(_ selected: Bool, lineID: UUID, undoManager: UndoManager? = nil) {
        guard let index = lineIndexByID[lineID] else { return }
        recording(selected ? "Afficher le résultat" : "Masquer le résultat", undoManager: undoManager) {
            setResultDisplayed(selected, at: index)
        }
    }

    func setResultDisplayed(_ selected: Bool, at index: Int) {
        guard resultSelection.entries.indices.contains(index),
              resultSelection.isSelected(at: index) != selected else { return }
        resultSelection.setSelected(selected, at: index)
        refreshResults()
        recordDidChange()
    }

    /// Selectable lines are known from the text alone, so no evaluation is needed.
    func selectAllResults(_ selected: Bool, undoManager: UndoManager? = nil) {
        recording(selected ? "Afficher tous les résultats" : "Masquer tous les résultats", undoManager: undoManager) {
            let indices = selectableLines.map(\.index)
            resultSelection.setAllSelected(selected, selectableLineIDs: Set(indices))
            refreshResults()
            recordDidChange()
        }
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

    private func recordDidChange() {
        guard !isClosed else { return }
        modifiedAt = Date()
        let record = record
        if displayTitle != record.displayTitle { displayTitle = record.displayTitle }
        onChange(record)
    }

    /// Rebuilds what depends on the lines themselves, then the results.
    private func refreshLines() {
        var cache: [String: AdjustableVariable?] = [:]
        var indices: [UUID: Int] = [:]
        var formulas: [IndexedFormulaLine] = []
        var variables: [NotebookVariable] = []
        var variablesByID: [UUID: AdjustableVariable] = [:]
        for (index, entry) in resultSelection.entries.enumerated() {
            indices[entry.id] = index
            if !entry.source.trimmingCharacters(in: .whitespaces).isEmpty {
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
        refreshResults()
    }

    /// Rebuilds the result lists from the current lines and their last results.
    private func refreshResults() {
        var selectable: [LineResult] = []
        var displayed: [LineResult] = []
        var errors: [LineResult] = []
        var preview: SheetRecord.ResultPreview?
        for (index, entry) in resultSelection.entries.enumerated() where Self.canShowResult(entry.source) {
            let item = LineResult(entry: entry, index: index, line: resultsByLineID[entry.id])
            selectable.append(item)
            if entry.isSelected {
                displayed.append(item)
                if preview == nil, item.isCurrent, let line = item.line {
                    preview = SheetRecord.previewWithSpeech(of: line)
                }
            } else if item.line?.status == .error {
                errors.append(item)
            }
        }
        selectableLines = selectable
        displayedResults = displayed
        hiddenErrors = errors
        if resultPreview != preview?.text { resultPreview = preview?.text }
        if spokenResultPreview != preview?.spoken { spokenResultPreview = preview?.spoken }
    }

    /// Mirrors the engine: a line without content outside its note has no result.
    private static func canShowResult(_ source: String) -> Bool {
        var end = source.endIndex
        if let marker = source.firstIndex(of: "#") { end = min(end, marker) }
        if let marker = source.range(of: "//")?.lowerBound { end = min(end, marker) }
        return source[..<end].contains { !$0.isWhitespace }
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
        refreshResults()
        // An evaluation that a newer edit already supersedes stays silent.
        if announcesNextEvaluation && pendingSnapshot == nil {
            announcesNextEvaluation = false
            announceResults()
        }
    }

    /// What a VoiceOver user cannot see change: the first chosen results, at most three.
    /// A ruler’s own line is left out, since its new value was just read.
    private func announceResults() {
        let phrases = displayedResults.compactMap { item -> String? in
            guard item.isCurrent, let line = item.line, variablesByLineID[item.id] == nil else { return nil }
            if line.status == .error { return String(localized: "Erreur à la ligne \(item.index + 1)") }
            guard let spoken = line.spokenResult else { return nil }
            return ResultText.spokenLine(source: item.entry.source, spokenValue: spoken)
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

/// A line that can show a result, with its last evaluation.
struct LineResult: Identifiable {
    let entry: ResultSelection.Entry
    /// The current position of the line in the sheet.
    let index: Int
    /// The last evaluation of this line; nil until the line is first evaluated.
    let line: EvaluatedLine?

    var id: UUID { entry.id }

    /// False while the shown value belongs to an earlier text of the line.
    var isCurrent: Bool { line?.source == entry.source }
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
