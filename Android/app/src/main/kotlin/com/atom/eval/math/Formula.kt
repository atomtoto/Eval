package com.atom.eval.math

import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.LocalTextStyle
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.HorizontalAlignmentLine
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.Placeable
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import eval.bridge.MathNode
import kotlin.math.max
import kotlin.math.roundToInt

/** A formula in mathematical notation (EvalCore `MathFormula`), copied out of the bridge once. */
sealed interface Math {
    data class Atom(val text: String) : Math
    data class Row(val items: List<Math>) : Math
    data class Fraction(val numerator: Math, val denominator: Math) : Math
    data class Power(val base: Math, val exponent: Math) : Math
    data class Radical(val radicand: Math) : Math
    data class Root(val index: Math, val radicand: Math) : Math
    data class Parentheses(val content: Math) : Math
    /** The value of an adjustable declaration (`80 kg` in `m = 80 kg`). */
    data class Value(val content: Math) : Math

    companion object {
        /** The notation of a line, null for a note or a formula that does not parse. */
        fun of(source: String): Math? = MathNode.formula(source)?.toMath()
    }
}

private fun MathNode.toMath(): Math {
    val nodes = children.map { it.toMath() }
    return when (kind) {
        "row" -> Math.Row(nodes)
        "fraction" -> Math.Fraction(nodes[0], nodes[1])
        "power" -> Math.Power(nodes[0], nodes[1])
        "radical" -> Math.Radical(nodes[0])
        "root" -> Math.Root(nodes[0], nodes[1])
        "parentheses" -> Math.Parentheses(nodes[0])
        "value" -> Math.Value(nodes[0])
        else -> Math.Atom(text)
    }
}

/**
 * The line that the operators and fraction bars of a formula sit on, a little above
 * the baseline of the text. Every node reports where its own axis is, and a row
 * aligns them all on one line, as `VerticalAlignment.mathAxis` on iOS.
 */
val MathAxis = HorizontalAlignmentLine { first, _ -> first }

/** The size of formulas in a sheet, as the 21 pt of iOS. */
val FormulaSize = 20.sp

/** What the value of an adjustable declaration does: a tap edits the line, a long press opens its ruler. */
class ValueInteraction(val isSelected: Boolean, val onTap: () -> Unit, val onLongPress: () -> Unit)

private val LocalValueInteraction = compositionLocalOf<ValueInteraction?> { null }

/** A formula drawn with text and lines, at [size]; it never wraps. */
@Composable
fun FormulaContent(math: Math, size: TextUnit = FormulaSize, valueInteraction: ValueInteraction? = null) {
    CompositionLocalProvider(LocalValueInteraction provides valueInteraction) {
        Node(math, size)
    }
}

/**
 * A formula followed by an accessory, such as the value of the line, on its axis.
 * The accessory moves under the formula when the row is too narrow, and a formula
 * wider than the row scrolls, as on iOS.
 */
@Composable
fun FormulaLine(
    math: Math,
    modifier: Modifier = Modifier,
    size: TextUnit = FormulaSize,
    valueInteraction: ValueInteraction? = null,
    accessory: (@Composable () -> Unit)? = null,
) {
    val scroll = rememberScrollState()
    Layout(
        content = {
            Box(Modifier.horizontalScroll(scroll).padding(vertical = 4.dp)) {
                FormulaContent(math, size, valueInteraction)
            }
            accessory?.let { Box { it() } }
        },
        modifier = modifier,
    ) { measurables, constraints ->
        val bounded = constraints.copy(minWidth = 0, minHeight = 0)
        val gap = (size.toPx() * 0.3f).roundToInt()
        val natural = measurables[0].maxIntrinsicWidth(Constraints.Infinity)
        val accessoryPlaceable = measurables.getOrNull(1)?.measure(bounded)
        val accessoryWidth = accessoryPlaceable?.let { it.width + gap } ?: 0
        if (natural + accessoryWidth <= bounded.maxWidth) {
            // On one line, both on the axis of the formula.
            val formula = measurables[0].measure(bounded.copy(maxWidth = natural))
            val formulaAxis = formula.axis()
            val accessoryAxis = accessoryPlaceable?.let { it[FirstBaseline] - (size.toPx() * 0.25f).roundToInt() } ?: 0
            val axis = max(formulaAxis, accessoryAxis)
            val height = max(formula.height - formulaAxis, (accessoryPlaceable?.height ?: 0) - accessoryAxis) + axis
            layout(formula.width + accessoryWidth, height, mapOf(MathAxis to axis)) {
                formula.place(0, axis - formulaAxis)
                accessoryPlaceable?.place(formula.width + gap, axis - accessoryAxis)
            }
        } else {
            val formula = measurables[0].measure(bounded)
            val width = max(formula.width, accessoryPlaceable?.width ?: 0)
            layout(width, formula.height + (accessoryPlaceable?.height ?: 0)) {
                formula.place(0, 0)
                accessoryPlaceable?.place(0, formula.height)
            }
        }
    }
}

@Composable
private fun Node(math: Math, size: TextUnit) {
    when (math) {
        is Math.Atom -> MathText(math.text, size)
        is Math.Row -> AxisRow { math.items.forEach { Node(it, size) } }
        is Math.Parentheses -> AxisRow {
            MathText("(", size)
            Node(math.content, size)
            MathText(")", size)
        }
        is Math.Fraction -> FractionLayout(size, { Node(math.numerator, size * 0.9f) }, { Node(math.denominator, size * 0.9f) })
        is Math.Power -> PowerLayout(size, { Node(math.base, size) }, { Node(math.exponent, size * 0.65f) })
        is Math.Radical -> RadicalLayout(size, { Node(math.radicand, size) })
        is Math.Root -> RadicalLayout(size, { Node(math.radicand, size) }, index = { Node(math.index, size * 0.55f) })
        is Math.Value -> Value(math.content, size)
    }
}

/** Text whose axis lies a quarter of its size above the baseline. */
@Composable
internal fun MathText(text: String, size: TextUnit) {
    val style = LocalTextStyle.current.copy(fontFamily = FontFamily.Serif, fontSize = size, lineHeight = TextUnit.Unspecified)
    Layout(content = { Text(text, style = style, maxLines = 1, softWrap = false) }) { measurables, _ ->
        val text = measurables[0].measure(Constraints())
        val axis = text[FirstBaseline] - (size.toPx() * 0.25f).roundToInt()
        layout(text.width, text.height, mapOf(MathAxis to axis)) { text.place(0, 0) }
    }
}

/** Items side by side, their axes on one line. */
@Composable
internal fun AxisRow(content: @Composable () -> Unit) {
    Layout(content = content) { measurables, _ ->
        val placeables = measurables.map { it.measure(Constraints()) }
        val axis = placeables.maxOfOrNull { it.axis() } ?: 0
        val below = placeables.maxOfOrNull { it.height - it.axis() } ?: 0
        layout(placeables.sumOf { it.width }, axis + below, mapOf(MathAxis to axis)) {
            var x = 0
            for (placeable in placeables) {
                placeable.place(x, axis - placeable.axis())
                x += placeable.width
            }
        }
    }
}

/** A fraction whose bar is its axis. */
@Composable
internal fun FractionLayout(size: TextUnit, numerator: @Composable () -> Unit, denominator: @Composable () -> Unit) {
    val color = LocalContentColor.current
    Layout(content = {
        Box { numerator() }
        Box(Modifier.background(color))
        Box { denominator() }
    }) { measurables, _ ->
        val inner = (size.toPx() * 0.22f).roundToInt()
        val outer = (size.toPx() * 0.1f).roundToInt()
        val gap = (size.toPx() * 0.12f).roundToInt()
        val numerator = measurables[0].measure(Constraints())
        val denominator = measurables[2].measure(Constraints())
        val barWidth = max(numerator.width, denominator.width) + 2 * inner
        val bar = measurables[1].measure(Constraints.fixed(barWidth, max(1, 1.dp.roundToPx())))
        val barY = numerator.height + gap
        val denominatorY = barY + bar.height + gap
        layout(barWidth + 2 * outer, denominatorY + denominator.height, mapOf(MathAxis to barY + bar.height / 2)) {
            numerator.place(outer + (barWidth - numerator.width) / 2, 0)
            bar.place(outer, barY)
            denominator.place(outer + (barWidth - denominator.width) / 2, denominatorY)
        }
    }
}

/** The exponent is lifted above the axis; the base stays on the line of its neighbours. */
@Composable
internal fun PowerLayout(size: TextUnit, base: @Composable () -> Unit, exponent: @Composable () -> Unit) {
    Layout(content = {
        Box { base() }
        Box { exponent() }
    }) { measurables, _ ->
        val base = measurables[0].measure(Constraints())
        val exponent = measurables[1].measure(Constraints())
        val lift = (size.toPx() * 0.15f).roundToInt()
        val gap = (size.toPx() * 0.06f).roundToInt()
        val baseAxis = base.axis()
        val axis = max(baseAxis, exponent.height + lift)
        val baseY = axis - baseAxis
        val exponentY = axis - lift - exponent.height
        layout(base.width + gap + exponent.width, max(baseY + base.height, exponentY + exponent.height), mapOf(MathAxis to axis)) {
            base.place(0, baseY)
            exponent.place(base.width + gap, exponentY)
        }
    }
}

/** The radical sign is drawn behind the radicand, so it stretches with it; a root's index sits in its hook. */
@Composable
internal fun RadicalLayout(size: TextUnit, radicand: @Composable () -> Unit, index: (@Composable () -> Unit)? = null) {
    val color = LocalContentColor.current
    val density = LocalDensity.current
    val hook = with(density) { size.toPx() * 0.7f }
    Box {
        Box(
            Modifier
                .drawBehind {
                    val path = Path().apply {
                        moveTo(0f, this@drawBehind.size.height * 0.62f)
                        lineTo(hook * 0.25f, this@drawBehind.size.height * 0.55f)
                        lineTo(hook * 0.55f, this@drawBehind.size.height - 1f)
                        lineTo(hook, 1f)
                        lineTo(this@drawBehind.size.width, 1f)
                    }
                    drawPath(path, color, style = Stroke(1.2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
                }
                .padding(start = with(density) { (size * 0.75f).toDp() }, end = with(density) { (size * 0.1f).toDp() }, top = 3.dp),
        ) {
            radicand()
        }
        index?.let {
            Box(Modifier.padding(start = with(density) { (size * 0.04f).toDp() })) { it() }
        }
    }
}

/**
 * The value of an adjustable declaration: tinted and underlined, like the variables
 * of Notes, when it can be adjusted; plain otherwise.
 */
@OptIn(ExperimentalFoundationApi::class)
@Composable
private fun Value(content: Math, size: TextUnit) {
    val interaction = LocalValueInteraction.current ?: return Node(content, size)
    val tint = MaterialTheme.colorScheme.primary
    Box(
        Modifier
            .background(if (interaction.isSelected) tint.copy(alpha = 0.15f) else Color.Transparent, RoundedCornerShape(6.dp))
            .combinedClickable(onClick = interaction.onTap, onLongClick = interaction.onLongPress)
            .padding(horizontal = 3.dp)
            .drawBehind {
                val y = this.size.height - 1.dp.toPx()
                drawLine(tint.copy(alpha = 0.5f), Offset(0f, y), Offset(this.size.width, y), 1.5.dp.toPx(), StrokeCap.Round)
            },
    ) {
        CompositionLocalProvider(LocalContentColor provides tint) { Node(content, size) }
    }
}

/** The axis of a node, the middle of its height when it reports none. */
internal fun Placeable.axis(): Int = this[MathAxis].let { if (it == AlignmentLine.Unspecified) height / 2 else it }

/** The style of a value shown beside a formula: the formula's size, semibold. */
@Composable
fun formulaAccessoryStyle(size: TextUnit = FormulaSize) =
    LocalTextStyle.current.copy(fontSize = size, fontWeight = FontWeight.SemiBold)
