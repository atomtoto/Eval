package com.atom.eval.sheet

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.input.InputTransformation
import androidx.compose.foundation.text.input.TextFieldLineLimits
import androidx.compose.foundation.text.input.rememberTextFieldState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.border
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.compose.ui.res.stringResource
import com.atom.eval.R
import com.atom.eval.math.MathEditContent
import com.atom.eval.math.cursor
import com.atom.eval.math.tree
import eval.bridge.LineState
import eval.bridge.MathLineEditor
import kotlinx.coroutines.launch
import kotlin.math.abs

/** Blank characters with a width: deleting one is a backspace, moving over one moves the cursor. */
private const val SENTINEL = ' '
/** Sentinels on each side of the hidden caret: as many steps of a keyboard trackpad each way. */
private const val PADDING = 48
private val FILLER = SENTINEL.toString().repeat(2 * PADDING)

/**
 * The edited line in mathematical notation (iOS MathEditorView): the line is edited as
 * it is shown, `/` making a fraction and `^` an exponent. The keyboard types into a
 * hidden field whose changes become keys of the editor, which then empties it again.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun MathEditedLine(line: LineState, viewModel: SheetViewModel, field: EditedField) {
    var editor by remember(line.id) { mutableStateOf(MathLineEditor(line.source)) }
    // The text last written to the line: another one comes from elsewhere, such as undo.
    var written by remember(line.id) { mutableStateOf(line.source) }
    var revision by remember { mutableIntStateOf(0) }
    val hidden = rememberTextFieldState(FILLER, TextRange(PADDING))
    val scope = rememberCoroutineScope()
    val focusRequester = remember { FocusRequester() }
    var hadFocus by remember { mutableStateOf(false) }
    val tree = remember(editor, revision) { editor.tree() }
    val cursor = remember(editor, revision) { editor.cursor() }

    fun changed(writes: Boolean) {
        if (writes) {
            written = editor.source
            viewModel.updateEditedLine(written)
        }
        revision++
    }

    LaunchedEffect(line.source) {
        if (line.source != written) {
            editor = MathLineEditor(line.source)
            written = line.source
        }
    }

    // The keyboard bar and the picker of constants type into this editor.
    DisposableEffect(editor) {
        val actions = object : MathActions {
            override fun key(name: String) { if (editor.key(name)) changed(name !in MOVES) }
            override fun type(text: String) { editor.type(text); changed(true) }
            override fun insertName(name: String) { editor.insertName(name); changed(true) }
        }
        field.math = actions
        onDispose { if (field.math === actions) field.math = null }
    }
    LaunchedEffect(line.id, field.isPicking) { if (!field.isPicking) focusRequester.requestFocus() }

    /** Typed text and backspaces, taken from the hidden field in the order of the keys. */
    fun keyboardEdit(typed: String, deleted: Int) {
        if (typed.contains('\n')) {
            // Return validates the line and starts a new one below, still in math.
            repeat(deleted) { editor.deleteBackward() }
            editor.type(typed.substringBefore('\n'))
            written = editor.source
            viewModel.updateEditedLine(written + "\n")
            return
        }
        repeat(deleted) { editor.deleteBackward() }
        if (typed.isNotEmpty()) editor.type(typed)
        changed(true)
    }

    // The caret of the hidden field moved, as with the keyboard's trackpad: the cursor follows.
    LaunchedEffect(hidden) {
        snapshotFlow { hidden.selection }.collect { selection ->
            val steps = selection.start - PADDING
            if (steps != 0 && selection.collapsed) {
                repeat(abs(steps)) { editor.key(if (steps < 0) "left" else "right") }
                hidden.edit { this.selection = TextRange(PADDING) }
                changed(false)
            }
        }
    }

    val colors = MaterialTheme.colorScheme
    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
        Box(
            Modifier
                .fillMaxWidth()
                .border(2.dp, colors.primary, RoundedCornerShape(4.dp))
                .padding(horizontal = 12.dp, vertical = 6.dp)
                .semantics {
                    contentDescription = line.accessibilityLabel
                    stateDescription = editor.cursorDescription
                    customActions = listOf("fraction" to "Fraction", "power" to "Puissance", "radical" to "Racine carrée",
                        "left" to "Gauche", "right" to "Droite", "up" to "Monter", "down" to "Descendre").map { (key, label) ->
                        CustomAccessibilityAction(label) { field.math?.key(key); true }
                    }
                },
        ) {
            MathEditContent(tree, cursor, onPlace = { place ->
                if (editor.setCursor(place.path, place.offset)) changed(false)
                focusRequester.requestFocus()
            })
            if (tree.items.isEmpty()) {
                Text(stringResource(R.string.new_line), color = colors.onSurfaceVariant, modifier = Modifier.padding(start = 24.dp, top = 8.dp))
            }
            // The field that has the keyboard, out of sight.
            BasicTextField(
                state = hidden,
                // Each edit is read, then undone, so the field always holds its sentinels.
                inputTransformation = remember {
                    InputTransformation {
                        val changes = changes
                        val typed = StringBuilder()
                        var deleted = 0
                        for (index in 0 until changes.changeCount) {
                            val range = changes.getRange(index)
                            deleted += changes.getOriginalRange(index).length
                            typed.append(asCharSequence().subSequence(range.start, range.end))
                        }
                        revertAllChanges()
                        val text = typed.toString().filter { it != SENTINEL }
                        // Handled after the edit, in the order of the keys.
                        if (text.isNotEmpty() || deleted > 0) scope.launch { keyboardEdit(text, deleted) }
                    }
                },
                lineLimits = TextFieldLineLimits.SingleLine,
                keyboardOptions = KeyboardOptions(
                    capitalization = KeyboardCapitalization.None,
                    autoCorrectEnabled = false,
                    keyboardType = KeyboardType.Ascii,
                    imeAction = ImeAction.Next,
                ),
                onKeyboardAction = { keyboardEdit("\n", 0) },
                modifier = Modifier
                    .size(1.dp)
                    .alpha(0f)
                    .focusRequester(focusRequester)
                    .onFocusChanged {
                        if (it.isFocused) hadFocus = true
                        else if (hadFocus && !field.isPicking) viewModel.endEditing(line.id)
                    }
                    // The arrows of a hardware keyboard move the cursor through the structures.
                    .onPreviewKeyEvent { event ->
                        val key = when (event.key) {
                            Key.DirectionLeft -> "left"
                            Key.DirectionRight -> "right"
                            Key.DirectionUp -> "up"
                            Key.DirectionDown -> "down"
                            Key.MoveHome -> "start"
                            Key.MoveEnd -> "end"
                            else -> return@onPreviewKeyEvent false
                        }
                        if (event.type == KeyEventType.KeyDown && editor.key(key)) changed(false)
                        true
                    },
            )
        }
        if (editor.comment.isNotEmpty() && tree.items.isNotEmpty()) {
            Text(editor.comment.trim(), style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
        }
        if (line.editingNotes.isNotEmpty()) LineNotes(line.editingNotes, Modifier.padding(top = 4.dp))
    }
}

/** The moves of the cursor, which change nothing in the line. */
private val MOVES = setOf("left", "right", "up", "down", "start", "end")

/** What the keyboard bar and the picker can do in the math editor. */
interface MathActions {
    fun key(name: String)
    fun type(text: String)
    fun insertName(name: String)
}
