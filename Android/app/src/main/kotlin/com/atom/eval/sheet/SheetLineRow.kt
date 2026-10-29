package com.atom.eval.sheet

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.AutoFixHigh
import androidx.compose.material.icons.outlined.Cancel
import androidx.compose.material.icons.outlined.Check
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.ContentCopy
import androidx.compose.material.icons.outlined.ContentPaste
import androidx.compose.material.icons.outlined.ControlPointDuplicate
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.Edit
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.KeyboardArrowDown
import androidx.compose.material.icons.outlined.KeyboardArrowUp
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material.icons.outlined.Straighten
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.unit.dp
import com.atom.eval.R
import com.atom.eval.data.FormulaInputMode
import com.atom.eval.math.FormulaLine
import com.atom.eval.math.Math
import com.atom.eval.math.ValueInteraction
import com.atom.eval.math.formulaAccessoryStyle
import com.atom.eval.ui.rememberCopyAction
import com.atom.eval.ui.shareText
import eval.bridge.LineMenu
import eval.bridge.LineNote
import eval.bridge.LineState

/**
 * One line of the sheet (iOS FormulaRowView): the formula with its value at rest,
 * a text field while it is edited, and the menu of the line on a long press.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
fun SheetLineRow(
    line: LineState,
    viewModel: SheetViewModel,
    isReordering: Boolean,
    isFirst: Boolean,
    isLast: Boolean,
    field: EditedField,
    showsLineNumber: Boolean,
    inputMode: FormulaInputMode,
    modifier: Modifier = Modifier,
) {
    var menu by remember { mutableStateOf<LineMenu?>(null) }
    val actionsLabel = stringResource(R.string.line_actions)

    Box(modifier) {
        if (line.isEditing) {
            if (inputMode == FormulaInputMode.Math) MathEditedLine(line, viewModel, field) else EditedLine(line, viewModel, field)
        } else {
            ListItem(
                headlineContent = { LineText(line) },
                supportingContent = line.notes.takeIf { it.isNotEmpty() }?.let { notes -> { LineNotes(notes) } },
                leadingContent = if (showsLineNumber) {
                    { LineNumber(line.index + 1) }
                } else null,
                trailingContent = if (isReordering) {
                    { ReorderButtons(isFirst, isLast) { viewModel.moveLine(line.id, it) } }
                } else null,
                colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                modifier = Modifier
                    .combinedClickable(
                        enabled = !isReordering,
                        onLongClickLabel = actionsLabel,
                        onLongClick = { menu = viewModel.lineMenu(line.id) },
                        onClick = { viewModel.beginEditing(line.id) },
                    )
                    // The formula is read as a whole, not symbol by symbol.
                    .clearAndSetSemantics {
                        contentDescription = line.accessibilityLabel
                        line.accessibilityValue?.let { stateDescription = it }
                    },
            )
        }
        menu?.let { LineMenuDropdown(it, viewModel) { menu = null } }
    }
}

/** The formula, a heading or a note, with the value on the same line when it is shown. */
@Composable
private fun LineText(line: LineState, valueInteraction: ValueInteraction? = null) {
    val colors = MaterialTheme.colorScheme
    when {
        line.isHeading -> Text(line.noteText.orEmpty(), style = MaterialTheme.typography.titleMedium)
        line.isComment -> Text(line.noteText.orEmpty(), color = colors.onSurfaceVariant)
        else -> {
            val math = remember(line.source) { Math.of(line.source) }
            // A value computed for an earlier text stays grayed until the next one.
            val valueColor = if (line.isStale) colors.onSurfaceVariant else colors.primary
            val accessory: (@Composable () -> Unit)? = line.valueLabel?.let { label ->
                { Text(label, style = formulaAccessoryStyle(), color = valueColor) }
            }
            Column {
                if (math != null) {
                    FormulaLine(math, valueInteraction = valueInteraction, accessory = accessory)
                    trailingComment(line.source)?.let {
                        Text(it, style = MaterialTheme.typography.bodySmall, color = colors.onSurfaceVariant)
                    }
                } else {
                    // Without notation (a formula being written), the text itself, as on iOS.
                    Text(line.source.trim(), fontFamily = FontFamily.Monospace, style = MaterialTheme.typography.bodyLarge)
                    accessory?.invoke()
                }
            }
        }
    }
}

/** The number of a line, at the left of the sheet when « Numéros de ligne » is on. */
@Composable
private fun LineNumber(number: Int) {
    Text(
        number.toString(),
        style = MaterialTheme.typography.labelMedium,
        fontFamily = FontFamily.Monospace,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

/** The `# …` or `// …` note that ends a formula line. */
private fun trailingComment(source: String): String? =
    listOf(source.indexOf('#'), source.indexOf("//")).filter { it >= 0 }.minOrNull()?.let { source.substring(it) }

/** The text field of the edited line: Return validates it and starts a new line below. */
@Composable
private fun EditedLine(line: LineState, viewModel: SheetViewModel, field: EditedField) {
    val value = remember(line.id) { mutableStateOf(TextFieldValue(line.source, TextRange(line.source.length))) }
    val focusRequester = remember { FocusRequester() }
    var hadFocus by remember { mutableStateOf(false) }

    fun change(newValue: TextFieldValue) {
        value.value = newValue
        if (newValue.text != line.source) viewModel.updateEditedLine(newValue.text)
    }

    // The keyboard bar inserts into this field.
    DisposableEffect(value) {
        field.state = value
        onDispose { if (field.state === value) field.state = null }
    }
    // Focused when it appears, and again when the picker of the keyboard bar closes.
    LaunchedEffect(line.id, field.isPicking) { if (!field.isPicking) focusRequester.requestFocus() }

    Column(Modifier.fillMaxWidth().padding(horizontal = 16.dp, vertical = 4.dp)) {
        OutlinedTextField(
            value = value.value,
            onValueChange = ::change,
            singleLine = true,
            placeholder = { Text(stringResource(R.string.new_line)) },
            keyboardOptions = KeyboardOptions(
                capitalization = KeyboardCapitalization.None,
                autoCorrectEnabled = false,
                imeAction = ImeAction.Next,
            ),
            keyboardActions = KeyboardActions(onNext = {
                // Splits the line at the cursor, like Return on iOS.
                val current = value.value
                val cursor = current.selection.end
                change(TextFieldValue(current.text.substring(0, cursor) + "\n" + current.text.substring(cursor)))
            }),
            modifier = Modifier
                .fillMaxWidth()
                .focusRequester(focusRequester)
                .onFocusChanged {
                    if (it.isFocused) hadFocus = true
                    else if (hadFocus && !field.isPicking) viewModel.endEditing(line.id)
                },
        )
        if (line.editingNotes.isNotEmpty()) LineNotes(line.editingNotes, Modifier.padding(top = 4.dp))
    }
}

/** The lines of text under a formula: its value while it is edited, errors, verdicts and remarks. */
@Composable
internal fun LineNotes(notes: List<LineNote>, modifier: Modifier = Modifier) {
    val colors = MaterialTheme.colorScheme
    val success = if (isSystemInDarkTheme()) Color(0xFF81C995) else Color(0xFF1E8E3E)
    Column(modifier, verticalArrangement = Arrangement.spacedBy(2.dp)) {
        for (note in notes) {
            val (icon, color) = when (note.style) {
                "value" -> null to colors.primary
                "staleValue" -> null to colors.onSurfaceVariant
                "error" -> Icons.Outlined.Warning to colors.error
                "equalityError" -> Icons.Outlined.Cancel to colors.error
                "verified" -> Icons.Outlined.CheckCircle to success
                "info" -> Icons.Outlined.Info to colors.onSurfaceVariant
                else -> Icons.Outlined.Check to colors.onSurfaceVariant
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(4.dp),
                verticalAlignment = Alignment.Top,
                modifier = Modifier.semantics(mergeDescendants = true) { contentDescription = note.spoken },
            ) {
                icon?.let { Icon(it, contentDescription = null, tint = color, modifier = Modifier.size(16.dp).padding(top = 2.dp)) }
                Text(
                    note.text,
                    // The check of a verified equality is green, its text stays secondary.
                    color = if (note.style == "verified") colors.onSurfaceVariant else color,
                    style = if (note.style == "dimension") MaterialTheme.typography.labelSmall else MaterialTheme.typography.bodyMedium,
                )
            }
        }
    }
}

@Composable
private fun ReorderButtons(isFirst: Boolean, isLast: Boolean, onMove: (Int) -> Unit) {
    Row {
        IconButton(onClick = { onMove(-1) }, enabled = !isFirst) {
            Icon(Icons.Outlined.KeyboardArrowUp, contentDescription = stringResource(R.string.move_up))
        }
        IconButton(onClick = { onMove(1) }, enabled = !isLast) {
            Icon(Icons.Outlined.KeyboardArrowDown, contentDescription = stringResource(R.string.move_down))
        }
    }
}

/** The menu of a line (iOS LineActions), and its « Afficher en » list of units. */
@Composable
private fun LineMenuDropdown(menu: LineMenu, viewModel: SheetViewModel, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val copy = rememberCopyAction()
    var showsUnits by remember { mutableStateOf(false) }

    DropdownMenu(expanded = true, onDismissRequest = onDismiss) {
        if (showsUnits) {
            // « Unités SI » first, then the units of the same dimension; the current one is checked.
            DropdownMenuItem(
                text = { Text(stringResource(R.string.si_units)) },
                leadingIcon = { if (menu.currentDisplayUnit == null) Icon(Icons.Outlined.Check, contentDescription = null) },
                onClick = { onDismiss(); viewModel.setDisplayUnit(null, menu.lineId) },
            )
            for (unit in menu.displayUnits) {
                DropdownMenuItem(
                    text = { Text(unit) },
                    leadingIcon = { if (menu.currentDisplayUnit == unit) Icon(Icons.Outlined.Check, contentDescription = null) },
                    onClick = { onDismiss(); viewModel.setDisplayUnit(unit, menu.lineId) },
                )
            }
        } else {
            LineActions(menu, viewModel, onDismiss, onShowUnits = { showsUnits = true }, copy = copy) {
                context.shareText(it)
            }
        }
    }
}

@Composable
private fun LineActions(
    menu: LineMenu,
    viewModel: SheetViewModel,
    onDismiss: () -> Unit,
    onShowUnits: () -> Unit,
    copy: (String) -> Unit,
    share: (String) -> Unit,
) {
    @Composable
    fun Item(text: String, icon: ImageVector, detail: String? = null, color: Color? = null, action: () -> Unit) {
        DropdownMenuItem(
            text = {
                Column {
                    Text(text, color = color ?: Color.Unspecified)
                    detail?.let { Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant) }
                }
            },
            leadingIcon = { Icon(icon, contentDescription = null, tint = color ?: MaterialTheme.colorScheme.onSurfaceVariant) },
            onClick = { onDismiss(); action() },
        )
    }

    // « Simplifier » comes first, with the simpler form, as above the iOS menu.
    menu.simplified?.let { simpler ->
        Item(stringResource(R.string.simplify), Icons.Outlined.AutoFixHigh, detail = simpler) { viewModel.simplifyLine(menu.lineId) }
        HorizontalDivider()
    }
    menu.copyValue?.let { Item(stringResource(R.string.copy_value), Icons.Outlined.ContentCopy) { copy(it) } }
    menu.copyLine?.let { Item(stringResource(R.string.copy_line), Icons.Outlined.ContentPaste) { copy(it) } }
    if (!menu.isComment) Item(stringResource(R.string.copy_formula), Icons.Outlined.ContentCopy) { copy(menu.formula) }
    menu.copyLine?.let { Item(stringResource(R.string.share_result), Icons.Outlined.Share) { share(it) } }
    if (menu.displayUnits.isNotEmpty()) {
        DropdownMenuItem(
            text = { Text(stringResource(R.string.show_in)) },
            leadingIcon = { Icon(Icons.Outlined.Straighten, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant) },
            trailingIcon = { Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null) },
            onClick = onShowUnits,
        )
    }
    // A note has no copy or unit items to separate from the editing ones.
    if (!menu.isComment) HorizontalDivider()
    Item(stringResource(R.string.edit), Icons.Outlined.Edit) { viewModel.beginEditing(menu.lineId) }
    Item(stringResource(R.string.duplicate), Icons.Outlined.ControlPointDuplicate) { viewModel.duplicateLine(menu.lineId) }
    Item(stringResource(R.string.delete), Icons.Outlined.Delete, color = MaterialTheme.colorScheme.error) {
        viewModel.removeLine(menu.lineId)
    }
}
