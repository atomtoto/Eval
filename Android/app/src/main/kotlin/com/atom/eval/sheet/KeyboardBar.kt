package com.atom.eval.sheet

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.AddCircleOutline
import androidx.compose.material.icons.outlined.DocumentScanner
import androidx.compose.material.icons.outlined.LibraryBooks
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.PopupProperties
import com.atom.eval.R
import com.atom.eval.ui.SearchField
import eval.bridge.FormulaKeys
import eval.bridge.ReferenceCatalog

/**
 * The field of the line being edited, shared with the keyboard bar: the bar inserts
 * at its caret, and a picker opened from the bar does not end the editing.
 */
class EditedField {
    /** The text and selection of the edited line's field, set by that field. */
    var state: MutableState<TextFieldValue>? = null
    /** True while « Constantes et unités… » is open: the line stays edited meanwhile. */
    var isPicking by mutableStateOf(false)

    /** Inserts a key at the caret or over the selection (`FormulaInsertion`); returns the new text. */
    fun insert(kind: String, value: String = ""): String? {
        val state = state ?: return null
        val current = state.value
        val edit = FormulaKeys.insert(kind, value, current.text, current.selection.min, current.selection.max)
        state.value = TextFieldValue(edit.text, TextRange(edit.caret))
        return edit.text
    }
}

/**
 * The bar above the keyboard while a line is edited (iOS LineKeyboardBar): the
 * scanner, the « Insérer » menu, the common operators and « Terminé ».
 */
@Composable
fun KeyboardBar(
    variableNames: List<String>,
    onInsert: (kind: String, value: String) -> Unit,
    onShowReferences: () -> Unit,
    onScan: (() -> Unit)?,
    onDone: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // A floating capsule, like the toolbars of Material 3 and the bar of iOS.
    Surface(
        shape = CircleShape,
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        tonalElevation = 3.dp,
        shadowElevation = 3.dp,
        modifier = modifier,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.padding(horizontal = 8.dp)) {
            onScan?.let {
                IconButton(onClick = it) {
                    Icon(Icons.Outlined.DocumentScanner, contentDescription = stringResource(R.string.scan_formula))
                }
            }
            InsertMenu(variableNames, onInsert, onShowReferences)
            Key("+", stringResource(R.string.key_plus)) { onInsert("operator", "+") }
            Key("−", stringResource(R.string.key_minus)) { onInsert("operator", "-") }
            Key("×", stringResource(R.string.key_times)) { onInsert("operator", "*") }
            Key("( )", stringResource(R.string.key_parentheses)) { onInsert("parentheses", "") }
            TextButton(onClick = onDone) { Text(stringResource(R.string.done), fontWeight = FontWeight.SemiBold) }
        }
    }
}

@Composable
private fun Key(title: String, label: String, onClick: () -> Unit) {
    TextButton(onClick = onClick, modifier = Modifier.semantics { contentDescription = label }) {
        Text(title, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.onSurface)
    }
}

/** « Insérer »: templates that wrap the selection, symbols, the sheet's names and the references. */
@Composable
private fun InsertMenu(variableNames: List<String>, onInsert: (String, String) -> Unit, onShowReferences: () -> Unit) {
    var isExpanded by remember { mutableStateOf(false) }
    Box {
        IconButton(onClick = { isExpanded = true }) {
            Icon(Icons.Outlined.AddCircleOutline, contentDescription = stringResource(R.string.insert))
        }
        // Not focusable, so that the line keeps its keyboard while the menu is open.
        DropdownMenu(expanded = isExpanded, onDismissRequest = { isExpanded = false }, properties = PopupProperties(focusable = false)) {
            @Composable
            fun Item(text: String, kind: String, value: String = "") =
                DropdownMenuItem(text = { Text(text) }, onClick = { isExpanded = false; onInsert(kind, value) })

            Item(stringResource(R.string.insert_fraction), "fraction")
            Item(stringResource(R.string.insert_power), "power")
            Item(stringResource(R.string.insert_root), "function", "sqrt")
            HorizontalDivider()
            Item(stringResource(R.string.insert_equal), "operator", "=")
            Item(stringResource(R.string.insert_divide), "operator", "/")
            Item(stringResource(R.string.insert_exponent), "literal", "^")
            Item(stringResource(R.string.insert_squared), "literal", "²")
            Item(stringResource(R.string.insert_cubed), "literal", "³")
            Item(stringResource(R.string.insert_inverse), "literal", "⁻¹")
            HorizontalDivider()
            Item("π", "name", "π")
            Item(stringResource(R.string.insert_degrees), "unit", "deg")
            if (variableNames.isNotEmpty()) {
                HorizontalDivider()
                Text(
                    stringResource(R.string.sheet_variables),
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 8.dp),
                )
                variableNames.forEach { Item(it, "name", it) }
            }
            HorizontalDivider()
            DropdownMenuItem(
                text = { Text(stringResource(R.string.constants_and_units)) },
                leadingIcon = { Icon(Icons.Outlined.LibraryBooks, contentDescription = null) },
                onClick = { isExpanded = false; onShowReferences() },
            )
        }
    }
}

/** « Constantes et unités… »: a searchable list whose choice is inserted into the line. */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SymbolPicker(onPick: (kind: String, value: String) -> Unit, onDismiss: () -> Unit) {
    var query by remember { mutableStateOf("") }
    val constants = remember(query) { ReferenceCatalog.constantSections(query, null).flatMap { it.constants } }
    val units = remember(query) { ReferenceCatalog.units(query) }
    ModalBottomSheet(onDismissRequest = onDismiss) {
        SearchField(query, { query = it }, stringResource(R.string.search_references), Modifier.padding(horizontal = 16.dp))
        LazyColumn(Modifier.fillMaxWidth()) {
            if (constants.isNotEmpty()) item { PickerHeader(stringResource(R.string.constants)) }
            items(constants, key = { "c-" + it.id }) { constant ->
                ListItem(
                    headlineContent = { Text(constant.symbol) },
                    supportingContent = { Text(constant.name) },
                    trailingContent = { Text(constant.valueText, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                    modifier = Modifier.clickable { onPick("name", constant.id) },
                )
            }
            if (units.isNotEmpty()) item { PickerHeader(stringResource(R.string.units)) }
            items(units, key = { "u-" + it.symbol }) { unit ->
                ListItem(
                    headlineContent = { Text(unit.symbol) },
                    supportingContent = { Text(unit.name) },
                    trailingContent = { Text(unit.valueText, color = MaterialTheme.colorScheme.onSurfaceVariant) },
                    modifier = Modifier.clickable { onPick("unit", unit.symbol) },
                )
            }
        }
    }
}

@Composable
private fun PickerHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 16.dp, bottom = 4.dp),
    )
}
