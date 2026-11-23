package com.atom.eval.sheet

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.TextRange
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.TextFieldValue
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.atom.eval.R

/**
 * « Modifier en texte »: the whole sheet in one multiline field (iOS TextSheetEditor).
 * Terminé applies the text as one undo step; Annuler leaves the sheet as it was.
 * The keyboard bar inserts at the caret, as while a line is edited.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun TextSheetEditorDialog(
    source: String,
    declaredNames: List<String>,
    onApply: (String) -> Unit,
    onDismiss: () -> Unit,
) {
    val field = remember { EditedField() }
    val state = remember { mutableStateOf(TextFieldValue(source, TextRange(source.length))) }
    field.state = state
    val focusRequester = remember { FocusRequester() }
    val focusManager = LocalFocusManager.current
    var isFocused by rememberSaveable { mutableStateOf(true) }
    var isPicking by rememberSaveable { mutableStateOf(false) }

    // As on iOS, the dialog does not dismiss while the text differs from the sheet's.
    Dialog(
        onDismissRequest = { if (state.value.text == source) onDismiss() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.text_editor_title)) },
                    navigationIcon = {
                        TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) }
                    },
                    actions = {
                        TextButton(onClick = { onApply(state.value.text) }) {
                            Text(stringResource(R.string.done), color = MaterialTheme.colorScheme.primary)
                        }
                    },
                )
            },
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).imePadding()) {
                OutlinedTextField(
                    value = state.value,
                    onValueChange = { state.value = it },
                    label = { Text(stringResource(R.string.text_editor_field)) },
                    modifier = Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .focusRequester(focusRequester)
                        .onFocusChanged { isFocused = it.isFocused },
                    textStyle = MaterialTheme.typography.bodyMedium.copy(fontFamily = FontFamily.Monospace),
                    keyboardOptions = KeyboardOptions(
                        capitalization = KeyboardCapitalization.None,
                        autoCorrectEnabled = false,
                    ),
                )
                Text(
                    stringResource(R.string.text_editor_footer),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 16.dp, vertical = 8.dp),
                )
                if (isFocused) {
                    KeyboardBar(
                        variableNames = declaredNames,
                        math = null,
                        onInsert = { kind, value -> field.insert(kind, value) },
                        onShowReferences = { isPicking = true },
                        onScan = null,
                        onDone = { focusManager.clearFocus() },
                        modifier = Modifier.padding(bottom = 10.dp),
                    )
                }
            }
        }
    }

    if (isPicking) {
        SymbolPicker(
            onPick = { kind, value ->
                field.insert(kind, value)
                isPicking = false
            },
            onDismiss = { isPicking = false },
        )
    }

    LaunchedEffect(focusRequester) { focusRequester.requestFocus() }
}
