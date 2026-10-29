package com.atom.eval.sheet

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.atom.eval.data.SheetStore
import eval.bridge.ConstantItem
import eval.bridge.LineMenu
import eval.bridge.LineState
import eval.bridge.PlotInput
import eval.bridge.RulerRange
import eval.bridge.RulerState
import eval.bridge.SheetEditor
import eval.bridge.UnitItem
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** What the sheet screen shows, read back from the editor after each change. */
data class SheetUiState(
    val title: String = "",
    val lines: List<LineState> = emptyList(),
    val editingLineId: String? = null,
    val canUndo: Boolean = false,
    val canRedo: Boolean = false,
    val undoActionName: String? = null,
    val redoActionName: String? = null,
    val sheetIssue: String? = null,
    val constants: List<ConstantItem> = emptyList(),
    val symbolUnits: List<UnitItem> = emptyList(),
    /** The names declared in the sheet, for « Insérer ». */
    val declaredNames: List<String> = emptyList(),
    /** Shown once an evaluation takes longer than [SheetEditor.progressDelayMillis]. */
    val isEvaluating: Boolean = false,
    /** The ruler open under the sheet, if any. */
    val ruler: RulerState? = null,
    /** A line to scroll to; each request has its own id. */
    val revealRequestId: String? = null,
    val revealLineId: String? = null,
)

/**
 * One open sheet (iOS NotebookStore, through the bridge's SheetEditor). The editor
 * is used on the main thread only; evaluations run one at a time on a background
 * thread, after a pause in typing, as on iOS.
 */
class SheetViewModel(private val store: SheetStore, val sheetId: String) : ViewModel() {
    private val editor: SheetEditor? = store.requireLibrary().openEditor(sheetId)
    private val engine = Dispatchers.Default.limitedParallelism(1)
    private val _state = MutableStateFlow(SheetUiState())
    private var evaluation: Job? = null
    private var isEvaluating = false

    val state: StateFlow<SheetUiState> = _state.asStateFlow()

    init {
        publish()
        scheduleEvaluation()
    }

    // Editing in place

    fun beginEditing(lineId: String) = edit { beginEditing(lineId) }

    fun newLine() = edit { newLine() }

    /** The text of the edited line; a line break splits it, as Return does on iOS. */
    fun updateEditedLine(text: String) = edit { updateEditedLine(text) }

    /** Validates a line that lost its focus, unless another line is edited by now. */
    fun endEditing(lineId: String) {
        if (editor?.editingLineId == lineId) edit { endEditing() }
    }

    // Line actions

    fun removeLine(lineId: String) = edit { removeLine(lineId) }

    fun duplicateLine(lineId: String) = edit { duplicateLine(lineId) }

    fun setDisplayUnit(symbol: String?, lineId: String) = edit { setDisplayUnit(symbol, lineId) }

    fun simplifyLine(lineId: String) = edit { simplifyLine(lineId) }

    /** Moves a line up (-1) or down (+1) among the lines shown. */
    fun moveLine(lineId: String, by: Int) {
        val index = _state.value.lines.indexOfFirst { it.id == lineId }
        val target = index + by
        if (index < 0 || target !in _state.value.lines.indices) return
        // As in a list move, the destination is counted before the line leaves.
        edit { moveLines(listOf(index), if (by > 0) target + 1 else target) }
    }

    fun lineMenu(lineId: String): LineMenu? = editor?.lineMenu(lineId)

    /** Reads the sheet again, after a setting that changes how results are written. */
    fun refresh() {
        publish()
        store.changed()
    }

    /** Lines read by the scanner, below a line (its keyboard stays on the last one) or at the end. */
    fun insertScannedLines(lines: List<String>, afterLineId: String?) {
        if (afterLineId != null && _state.value.lines.any { it.id == afterLineId }) edit { insertLinesAfter(lines, afterLineId) }
        else edit { appendLines(lines) }
    }

    // Rulers

    fun showRuler(lineId: String) = edit { showRuler(lineId) }

    fun hideRuler() = edit { hideRuler() }

    fun beginRulerGesture(lineId: String) = editor?.beginRulerGesture(lineId)

    fun endRulerGesture() = edit { endRulerGesture() }

    fun adjustVariable(lineId: String, value: Double) = edit { adjustVariable(lineId, value, false) }

    fun stepVariable(lineId: String, steps: Int) = edit { stepVariable(lineId, steps) }

    fun setRulerSettings(lineId: String, lower: Double, upper: Double, step: Double, automatic: Boolean): Boolean {
        val saved = editor?.setRulerSettings(lineId, lower, upper, step, automatic) == true
        if (saved) refresh()
        return saved
    }

    fun suggestedRulerSettings(lineId: String): RulerRange? = editor?.suggestedRulerSettings(lineId)

    /** What the plot of a line needs; the interval only counts for a name the sheet does not declare. */
    fun plotInput(request: PlotRequest, lower: Double, upper: Double): PlotInput? {
        val editor = editor ?: return null
        request.variableLineId?.let { return editor.plotInput(request.resultLineId, it) }
        return request.freeVariable?.let { editor.freeVariablePlotInput(request.resultLineId, it, lower, upper) }
    }

    /** What TalkBack announces after a step of the ruler, once the results are in. */
    fun takeAnnouncement(): String? = editor?.takeAnnouncement()

    // Sheet actions

    fun undo() = edit { undo() }

    fun redo() = edit { redo() }

    fun rename(title: String) = edit { rename(title) }

    fun clear() = edit { clear() }

    fun sharedText(includingResults: Boolean): String = editor?.sharedText(includingResults).orEmpty()

    /** A copy of the sheet, listed first; returns its id. */
    fun duplicateSheet(): String? = store.requireLibrary().duplicateSheet(sheetId).also { store.changed() }

    override fun onCleared() {
        // Leaving the sheet validates the line being edited, as on iOS.
        if (editor?.editingLineId != null) {
            editor.endEditing()
            store.changed()
        }
    }

    private inline fun edit(change: SheetEditor.() -> Unit) {
        val editor = editor ?: return
        editor.change()
        publish()
        store.changed()
        scheduleEvaluation()
    }

    private fun publish() {
        val editor = editor ?: return
        val reveal = editor.revealRequest
        _state.update {
            it.copy(
                title = editor.title,
                lines = editor.lines(),
                editingLineId = editor.editingLineId,
                canUndo = editor.canUndo,
                canRedo = editor.canRedo,
                undoActionName = editor.undoActionName,
                redoActionName = editor.redoActionName,
                sheetIssue = editor.sheetIssue,
                constants = editor.recognizedConstants(),
                symbolUnits = editor.symbolUnits(),
                declaredNames = editor.declaredNames,
                ruler = editor.activeRulerLineId?.let(editor::ruler),
                revealRequestId = reveal?.id,
                revealLineId = reveal?.lineId,
            )
        }
    }

    /**
     * Evaluates the latest text: after [SheetEditor.typingDelayMillis] without typing,
     * one evaluation at a time, again at once while the text changed meanwhile.
     */
    private fun scheduleEvaluation() {
        val editor = editor ?: return
        // A running evaluation is followed by another one if the text changed.
        if (isEvaluating || !editor.needsEvaluation) return
        evaluation?.cancel()
        evaluation = viewModelScope.launch {
            while (editor.needsEvaluation) {
                val request = editor.evaluationRequest()
                // A newer change cancels this wait and starts a new one.
                if (request.isDebounced) delay(SheetEditor.typingDelayMillis)
                isEvaluating = true
                val progress = launch {
                    delay(SheetEditor.progressDelayMillis)
                    _state.update { it.copy(isEvaluating = true) }
                }
                val result = try {
                    withContext(engine) { SheetEditor.evaluate(request) }
                } finally {
                    isEvaluating = false
                    progress.cancel()
                }
                _state.update { it.copy(isEvaluating = false) }
                if (editor.applyEvaluation(result, false)) {
                    publish()
                    // The list shows the sheet's first result.
                    store.changed()
                }
            }
        }
    }
}
