package com.atom.eval.sheet

import androidx.compose.animation.core.Animatable
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.ListItem
import androidx.compose.material3.ListItemDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import com.atom.eval.R
import eval.bridge.RulerState
import eval.bridge.SheetEditor
import kotlinx.coroutines.launch
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToInt

/**
 * The ruler of a declared number, under the sheet (iOS VariableSliderView): the value
 * in words, the ruler and its settings. The results above follow the drag.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun RulerSheet(ruler: RulerState, viewModel: SheetViewModel, onDismiss: () -> Unit) {
    var showsSettings by rememberSaveable { mutableStateOf(false) }
    // Without a scrim, so that the lines and their results stay in view.
    ModalBottomSheet(onDismissRequest = onDismiss, scrimColor = Color.Transparent) {
        Column(Modifier.padding(start = 16.dp, end = 16.dp, bottom = 24.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    "${ruler.name} = ${ruler.valueText}",
                    style = MaterialTheme.typography.titleLarge,
                    modifier = Modifier.weight(1f),
                )
                IconButton(onClick = { showsSettings = true }) {
                    Icon(Icons.Outlined.Tune, contentDescription = stringResource(R.string.ruler_settings))
                }
            }
            Ruler(
                value = ruler.value,
                step = ruler.step,
                label = ruler.name,
                spokenValue = ruler.spokenValue,
                onStart = { viewModel.beginRulerGesture(ruler.lineId) },
                onChange = { viewModel.adjustVariable(ruler.lineId, it) },
                onEnd = viewModel::endRulerGesture,
                onStep = { viewModel.stepVariable(ruler.lineId, it) },
            )
            Text(
                stringResource(if (ruler.usesAutomaticStep) R.string.ruler_step_automatic else R.string.ruler_step, ruler.spokenStep),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
    if (showsSettings) RulerSettingsDialog(ruler, viewModel) { showsSettings = false }
}

/**
 * A relative ruler: its indicator stays in the middle while the graduations follow
 * the finger, with no bounds; each graduation moves the value by one step, and
 * dragging left increases it, as on the dial of Photos.
 */
@Composable
private fun Ruler(
    value: Double,
    step: Double,
    label: String,
    spokenValue: String,
    onStart: () -> Unit,
    onChange: (Double) -> Unit,
    onEnd: () -> Unit,
    onStep: (Int) -> Unit,
) {
    val tickSpacing = with(LocalDensity.current) { 16.dp.toPx() }
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val translation = remember { Animatable(0f) }
    val increase = stringResource(R.string.ruler_increase)
    val decrease = stringResource(R.string.ruler_decrease)
    val tint = MaterialTheme.colorScheme.primary
    val ticks = MaterialTheme.colorScheme.onSurface
    // The gesture outlives a composition: it reads the value and step of the moment.
    val currentValue by rememberUpdatedState(value)
    val currentStep by rememberUpdatedState(step)

    Surface(shape = CircleShape, color = MaterialTheme.colorScheme.surfaceContainerHigh, modifier = Modifier.fillMaxWidth().height(52.dp)) {
        var origin by remember { mutableStateOf(0.0) }
        var gestureStep by remember { mutableStateOf(1.0) }
        var dragged by remember { mutableStateOf(0f) }
        var lastSteps by remember { mutableStateOf(0) }
        Canvas(
            Modifier
                .fillMaxWidth()
                .clip(CircleShape)
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            // A drag is anchored to the value at its start, with the step of that moment.
                            origin = currentValue
                            gestureStep = currentStep
                            dragged = 0f
                            lastSteps = 0
                            onStart()
                        },
                        onDragEnd = {
                            onEnd()
                            // The graduations settle on the nearest one.
                            scope.launch { translation.animateTo(0f) }
                        },
                        onDragCancel = {
                            onEnd()
                            scope.launch { translation.snapTo(0f) }
                        },
                    ) { change, amount ->
                        change.consume()
                        dragged += amount
                        scope.launch { translation.snapTo(dragged) }
                        val steps = (-dragged / tickSpacing).roundToInt()
                        if (steps != lastSteps) {
                            lastSteps = steps
                            haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
                            onChange(SheetEditor.steppedValue(origin, steps, gestureStep))
                        }
                    }
                }
                .clearAndSetSemantics {
                    contentDescription = label
                    stateDescription = spokenValue
                    customActions = listOf(
                        CustomAccessibilityAction(increase) { onStep(1); true },
                        CustomAccessibilityAction(decrease) { onStep(-1); true },
                    )
                },
        ) {
            // Only the distance to the nearest graduation is drawn, so the ruler never runs out.
            val phase = translation.value - (translation.value / tickSpacing).roundToInt() * tickSpacing
            val count = ceil(size.width / tickSpacing / 2).toInt() + 1
            for (index in -count..count) {
                val x = size.width / 2 + index * tickSpacing + phase
                val distance = abs(x - size.width / 2) / max(size.width / 2, 1f)
                drawLine(
                    ticks.copy(alpha = max(0.12f, 0.65f * (1 - distance))),
                    Offset(x, size.height * 0.28f),
                    Offset(x, size.height * 0.72f),
                    strokeWidth = 3.dp.toPx(),
                    cap = StrokeCap.Round,
                )
            }
            drawLine(tint, Offset(size.width / 2, size.height * 0.12f), Offset(size.width / 2, size.height * 0.88f), 3.dp.toPx(), StrokeCap.Round)
        }
    }
}

/** « Réglages de la réglette »: an automatic or manual step, and the interval of the plot. */
@Composable
private fun RulerSettingsDialog(ruler: RulerState, viewModel: SheetViewModel, onDismiss: () -> Unit) {
    var automatic by rememberSaveable { mutableStateOf(ruler.usesAutomaticStep) }
    var step by rememberSaveable { mutableStateOf(number(ruler.step)) }
    var lower by rememberSaveable { mutableStateOf(number(ruler.lowerBound)) }
    var upper by rememberSaveable { mutableStateOf(number(ruler.upperBound)) }
    var invalid by rememberSaveable { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text(stringResource(R.string.ruler_settings)) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                ListItem(
                    headlineContent = { Text(stringResource(R.string.ruler_automatic_step)) },
                    trailingContent = { Switch(checked = automatic, onCheckedChange = { automatic = it }) },
                    colors = ListItemDefaults.colors(containerColor = Color.Transparent),
                )
                if (!automatic) NumberField(R.string.ruler_manual_step, step) { step = it }
                Text(stringResource(R.string.plot_interval), style = MaterialTheme.typography.titleSmall)
                NumberField(R.string.plot_minimum, lower) { lower = it }
                NumberField(R.string.plot_maximum, upper) { upper = it }
                if (invalid) Text(stringResource(R.string.ruler_settings_invalid), color = MaterialTheme.colorScheme.error)
                TextButton(onClick = {
                    viewModel.suggestedRulerSettings(ruler.lineId)?.let {
                        automatic = true
                        lower = number(it.lowerBound)
                        upper = number(it.upperBound)
                        step = number(it.step)
                    }
                }) { Text(stringResource(R.string.ruler_restore)) }
            }
        },
        confirmButton = {
            TextButton(onClick = {
                val saved = viewModel.setRulerSettings(
                    ruler.lineId,
                    parse(lower) ?: Double.NaN,
                    parse(upper) ?: Double.NaN,
                    if (automatic) ruler.automaticStep else parse(step) ?: Double.NaN,
                    automatic,
                )
                if (saved) onDismiss() else invalid = true
            }) { Text(stringResource(R.string.ok)) }
        },
        dismissButton = { TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel)) } },
    )
}

@Composable
private fun NumberField(label: Int, value: String, onChange: (String) -> Unit) {
    OutlinedTextField(
        value = value,
        onValueChange = onChange,
        label = { Text(stringResource(label)) },
        singleLine = true,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal),
        modifier = Modifier.fillMaxWidth(),
    )
}

/** A number as French text, with a decimal comma. */
private fun number(value: Double): String =
    if (value == value.roundToLongOrNull()?.toDouble()) value.toLong().toString() else value.toString().replace('.', ',')

private fun Double.roundToLongOrNull(): Long? = if (isFinite() && abs(this) < 1e15) kotlin.math.round(this).toLong() else null

/** A number typed with a comma or a point; null when it is not one. */
private fun parse(text: String): Double? = text.trim().replace(',', '.').replace('−', '-').toDoubleOrNull()
