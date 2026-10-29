package com.atom.eval.sheet

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.atom.eval.R
import eval.bridge.NumberText
import eval.bridge.PlotData
import eval.bridge.PlotInput
import eval.bridge.SheetEditor
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.log10
import kotlin.math.pow

/** A plot asked from the menu of a line: against a ruler variable, or a name the sheet does not declare. */
data class PlotRequest(val resultLineId: String, val variableLineId: String? = null, val freeVariable: String? = null)

/**
 * « Tracer en fonction de » (iOS PlotView): the result of a line over the plot interval
 * of a variable, a dashed line at its current value, and a touch that reads a value.
 * Points where the calculation fails leave a gap in the curve.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun PlotDialog(request: PlotRequest, viewModel: SheetViewModel, onDismiss: () -> Unit) {
    // The interval of a name the sheet does not declare is chosen here.
    var lower by rememberSaveable { mutableStateOf("-10") }
    var upper by rememberSaveable { mutableStateOf("10") }
    var interval by rememberSaveable { mutableStateOf(-10.0 to 10.0) }
    val input = remember(request, interval) { viewModel.plotInput(request, interval.first, interval.second) }
    var data by remember(input) { mutableStateOf<PlotData?>(null) }
    LaunchedEffect(input) { data = input?.let { withContext(Dispatchers.Default) { SheetEditor.samplePlot(it) } } }

    Dialog(onDismissRequest = onDismiss, properties = DialogProperties(usePlatformDefaultWidth = false)) {
        Scaffold(
            topBar = {
                TopAppBar(
                    title = { Text(input?.let { stringResource(R.string.plot_title, it.resultName, it.variableName) }.orEmpty()) },
                    navigationIcon = {
                        IconButton(onClick = onDismiss) { Icon(Icons.Outlined.Close, contentDescription = stringResource(R.string.close)) }
                    },
                )
            },
        ) { padding ->
            Column(Modifier.fillMaxSize().padding(padding).padding(16.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                input?.currentResult?.let { Text(it, style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.primary) }
                if (request.freeVariable != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        OutlinedTextField(lower, { lower = it }, Modifier.weight(1f), label = { Text(stringResource(R.string.plot_minimum)) },
                            singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                        OutlinedTextField(upper, { upper = it }, Modifier.weight(1f), label = { Text(stringResource(R.string.plot_maximum)) },
                            singleLine = true, keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Decimal))
                    }
                    Button(onClick = {
                        val from = NumberText.parse(lower)
                        val to = NumberText.parse(upper)
                        if (from != null && to != null && to > from) interval = from to to
                    }) { Text(stringResource(R.string.plot_draw)) }
                }
                val plot = data
                when {
                    input == null -> {}
                    plot == null -> Text(stringResource(R.string.plot_computing), color = MaterialTheme.colorScheme.onSurfaceVariant)
                    plot.failure != null -> Text(plot.failure!!, color = MaterialTheme.colorScheme.error)
                    else -> Chart(input, plot, Modifier.fillMaxWidth().weight(1f))
                }
            }
        }
    }
}

/** The curve in its frame: graduated axes with their units, the current value, the value read. */
@Composable
private fun Chart(input: PlotInput, data: PlotData, modifier: Modifier) {
    val colors = MaterialTheme.colorScheme
    val measurer = rememberTextMeasurer()
    val labelStyle = MaterialTheme.typography.labelSmall.copy(color = colors.onSurfaceVariant)
    val segments = remember(data) { data.segments.map { it.xs.zip(it.ys) } }
    val points = remember(segments) { segments.flatten() }
    val yRange = remember(points) { niceRange(points.minOfOrNull { it.second } ?: 0.0, points.maxOfOrNull { it.second } ?: 1.0) }
    val xRange = data.lowerBound to data.upperBound
    var selectedX by remember(data) { mutableStateOf<Double?>(null) }
    val xTitle = axisTitle(input.variableName, input.variableUnit)
    val yTitle = axisTitle(input.resultName, input.resultUnit.orEmpty())
    val selected = selectedX?.let { x -> points.minByOrNull { abs(it.first - x) } }
    val description = stringResource(R.string.plot_title, input.resultName, input.variableName)

    Column(modifier) {
        Text(
            selected?.let { "${input.variableName} = ${number(it.first, input.variableUnit)}   ${input.resultName} = ${number(it.second, input.resultUnit.orEmpty())}" }
                ?: stringResource(R.string.plot_touch_hint),
            style = MaterialTheme.typography.bodyMedium,
            color = if (selected != null) colors.onSurface else colors.onSurfaceVariant,
            modifier = Modifier.height(24.dp),
        )
        Canvas(
            Modifier
                .fillMaxWidth()
                .weight(1f)
                .semantics { contentDescription = description }
                .pointerInput(data) {
                    val left = 56.dp.toPx()
                    val right = size.width - 8.dp.toPx()
                    fun read(x: Float) {
                        selectedX = xRange.first + ((x - left) / (right - left)).coerceIn(0f, 1f) * (xRange.second - xRange.first)
                    }
                    detectTapGestures { read(it.x) }
                }
                .pointerInput(data) {
                    val left = 56.dp.toPx()
                    val right = size.width - 8.dp.toPx()
                    detectDragGestures { change, _ ->
                        selectedX = xRange.first + ((change.position.x - left) / (right - left)).coerceIn(0f, 1f) * (xRange.second - xRange.first)
                    }
                },
        ) {
            val left = 56.dp.toPx()
            val right = size.width - 8.dp.toPx()
            val top = 20.dp.toPx()
            val bottom = size.height - 40.dp.toPx()
            fun px(x: Double) = (left + (x - xRange.first) / (xRange.second - xRange.first) * (right - left)).toFloat()
            fun py(y: Double) = (bottom - (y - yRange.first) / (yRange.second - yRange.first) * (bottom - top)).toFloat()

            // Graduations and their values.
            for (y in ticks(yRange.first, yRange.second)) {
                drawLine(colors.outlineVariant, Offset(left, py(y)), Offset(right, py(y)), 1.dp.toPx())
                label(measurer, number(y, ""), Offset(4.dp.toPx(), py(y) - 7.dp.toPx()), labelStyle)
            }
            for (x in ticks(xRange.first, xRange.second)) {
                drawLine(colors.outlineVariant, Offset(px(x), top), Offset(px(x), bottom), 1.dp.toPx())
                label(measurer, number(x, ""), Offset(px(x) - 10.dp.toPx(), bottom + 4.dp.toPx()), labelStyle)
            }
            label(measurer, yTitle, Offset(4.dp.toPx(), 0f), labelStyle)
            label(measurer, xTitle, Offset(right - measurer.measure(xTitle, labelStyle).size.width, bottom + 20.dp.toPx()), labelStyle)

            // The current value, dashed.
            input.currentValue?.takeIf { it in xRange.first..xRange.second }?.let { current ->
                drawLine(colors.onSurfaceVariant, Offset(px(current), top), Offset(px(current), bottom), 1.5.dp.toPx(),
                    pathEffect = PathEffect.dashPathEffect(floatArrayOf(6.dp.toPx(), 4.dp.toPx())))
            }
            // The curve, one stroke per segment: failures leave gaps.
            for (segment in segments) {
                if (segment.size == 1) {
                    drawCircle(colors.primary, 2.5.dp.toPx(), Offset(px(segment[0].first), py(segment[0].second)))
                    continue
                }
                val path = Path()
                segment.forEachIndexed { index, (x, y) ->
                    if (index == 0) path.moveTo(px(x), py(y)) else path.lineTo(px(x), py(y))
                }
                drawPath(path, colors.primary, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
            selected?.let { (x, y) ->
                drawLine(colors.primary.copy(alpha = 0.5f), Offset(px(x), top), Offset(px(x), bottom), 1.dp.toPx())
                drawCircle(colors.primary, 5.dp.toPx(), Offset(px(x), py(y)))
            }
        }
    }
}

private fun androidx.compose.ui.graphics.drawscope.DrawScope.label(measurer: TextMeasurer, text: String, at: Offset, style: TextStyle) {
    drawText(measurer, text, at, style)
}

private fun axisTitle(name: String, unit: String) = if (unit.isEmpty()) name else "$name ($unit)"

/** A value as the sheet writes it, with its unit. */
private fun number(value: Double, unit: String) = NumberText.format(value, unit, false)

/** A range rounded out to graduations, never empty. */
private fun niceRange(minimum: Double, maximum: Double): Pair<Double, Double> {
    if (minimum == maximum) return (minimum - 1) to (maximum + 1)
    val step = tickStep(minimum, maximum)
    return floor(minimum / step) * step to ceil(maximum / step) * step
}

/** About five graduations, at 1, 2 or 5 times a power of ten. */
private fun tickStep(minimum: Double, maximum: Double): Double {
    val rough = (maximum - minimum) / 5
    val power = 10.0.pow(floor(log10(rough)))
    return listOf(1.0, 2.0, 5.0, 10.0).map { it * power }.first { it >= rough }
}

private fun ticks(minimum: Double, maximum: Double): List<Double> {
    val step = tickStep(minimum, maximum)
    val first = ceil(minimum / step) * step
    return generateSequence(first) { it + step }.takeWhile { it <= maximum + step * 1e-9 }.map { if (abs(it) < step * 1e-9) 0.0 else it }.toList()
}
