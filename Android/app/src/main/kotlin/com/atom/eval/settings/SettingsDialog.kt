package com.atom.eval.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.atom.eval.R
import com.atom.eval.appSettings
import com.atom.eval.data.Accent
import com.atom.eval.data.AppSettings
import com.atom.eval.data.FormulaInputMode
import kotlin.math.roundToInt

/** « Réglages », as a full-screen dialog (iOS SettingsView). */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsDialog(onDismiss: () -> Unit) {
    val settings = LocalContext.current.appSettings
    val inputMode by settings.inputMode.collectAsStateWithLifecycle()
    val digits by settings.significantDigits.collectAsStateWithLifecycle()
    val lineNumbers by settings.lineNumbers.collectAsStateWithLifecycle()
    val accent by settings.accent.collectAsStateWithLifecycle()
    val warmBackground by settings.warmBackground.collectAsStateWithLifecycle()

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(stringResource(R.string.settings)) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) {
                            Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.close))
                        }
                    },
                )
            },
        ) { padding ->
            LazyColumn(Modifier.fillMaxSize(), contentPadding = padding) {
                item { Header(R.string.formula_input) }
                item { Choice(R.string.input_text, inputMode == FormulaInputMode.Text) { settings.setInputMode(FormulaInputMode.Text) } }
                item { Choice(R.string.input_math, inputMode == FormulaInputMode.Math) { settings.setInputMode(FormulaInputMode.Math) } }
                item { Footer(R.string.formula_input_footer) }

                item {
                    ListItem(
                        headlineContent = { Text(stringResource(R.string.significant_digits)) },
                        trailingContent = { Text(digits.toString(), style = MaterialTheme.typography.titleMedium) },
                        supportingContent = {
                            // 3 to 12 digits, one step at a time.
                            Slider(
                                value = digits.toFloat(),
                                onValueChange = { settings.setSignificantDigits(it.roundToInt()) },
                                valueRange = AppSettings.MINIMUM_DIGITS.toFloat()..AppSettings.MAXIMUM_DIGITS.toFloat(),
                                steps = AppSettings.MAXIMUM_DIGITS - AppSettings.MINIMUM_DIGITS - 1,
                            )
                        },
                        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                    )
                }
                item { Footer(R.string.significant_digits_footer) }

                item { Toggle(R.string.line_numbers, lineNumbers, settings::setLineNumbers) }
                item { Footer(R.string.line_numbers_footer) }

                item { Header(R.string.accent_color) }
                item { Choice(R.string.accent_orange, accent == Accent.Orange, swatch = Color(0xFFDD5500)) { settings.setAccent(Accent.Orange) } }
                item { Choice(R.string.accent_blue, accent == Accent.Blue, swatch = Color(0xFF0B57D0)) { settings.setAccent(Accent.Blue) } }

                item { Toggle(R.string.warm_background, warmBackground, settings::setWarmBackground) }
                item { Footer(R.string.warm_background_footer) }
            }
        }
    }
}

@Composable
private fun Header(text: Int) {
    Text(
        stringResource(text),
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.primary,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, top = 24.dp, bottom = 4.dp),
    )
}

@Composable
private fun Footer(text: Int) {
    Text(
        stringResource(text),
        style = MaterialTheme.typography.bodySmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(start = 16.dp, end = 16.dp, bottom = 16.dp),
    )
}

@Composable
private fun Choice(text: Int, selected: Boolean, swatch: Color? = null, onSelect: () -> Unit) {
    ListItem(
        headlineContent = { Text(stringResource(text)) },
        leadingContent = { RadioButton(selected = selected, onClick = null) },
        trailingContent = swatch?.let { { Box(Modifier.size(20.dp).background(it, CircleShape)) } },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.selectable(selected = selected, onClick = onSelect, role = Role.RadioButton),
    )
}

@Composable
private fun Toggle(text: Int, checked: Boolean, onChange: (Boolean) -> Unit) {
    ListItem(
        headlineContent = { Text(stringResource(text)) },
        trailingContent = { Switch(checked = checked, onCheckedChange = null) },
        colors = ListItemDefaults.colors(containerColor = Color.Transparent),
        modifier = Modifier.toggleable(value = checked, onValueChange = onChange, role = Role.Switch),
    )
}
