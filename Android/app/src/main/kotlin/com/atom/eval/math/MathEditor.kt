package com.atom.eval.math

import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import eval.bridge.MathEditRow
import eval.bridge.MathLineEditor
import kotlin.math.roundToInt

/** A row of the math editor, copied out of the bridge once per change. */
data class EditRow(val items: List<EditItem>)

/** A symbol, or a structure (`fraction`, `power`, `radical`, `root`) with its rows. */
data class EditItem(val kind: String, val text: String, val slots: List<EditRow>)

/** Where the cursor is: pairs of item and slot indices from the outer row, and an offset. */
data class EditCursor(val path: List<Int>, val offset: Int)

fun MathLineEditor.tree(): EditRow = root.toRow()

fun MathLineEditor.cursor(): EditCursor = EditCursor(cursorPath, cursorOffset)

private fun MathEditRow.toRow(): EditRow = EditRow(items.map { EditItem(it.kind, it.text, it.slots.map { slot -> slot.toRow() }) })

/**
 * A formula as the math editor shows it (iOS MathEditorView): the structures of the
 * line with the cursor, empty places in a dotted frame, and a tap that places the
 * cursor on the side of the symbol touched.
 */
@Composable
fun MathEditContent(row: EditRow, cursor: EditCursor?, onPlace: (EditCursor) -> Unit, size: TextUnit = FormulaSize) {
    Box(Modifier.horizontalScroll(rememberScrollState()).padding(vertical = 6.dp)) {
        RowView(row, emptyList(), cursor, onPlace, size)
    }
}

@Composable
private fun RowView(row: EditRow, path: List<Int>, cursor: EditCursor?, onPlace: (EditCursor) -> Unit, size: TextUnit) {
    val cursorHere = cursor?.takeIf { it.path == path }?.offset
    if (row.items.isEmpty()) {
        EmptyPlace(size, hasCursor = cursorHere != null) { onPlace(EditCursor(path, 0)) }
        return
    }
    AxisRow {
        row.items.forEachIndexed { index, item ->
            if (cursorHere == index) Caret(size)
            ItemView(item, path, index, cursor, onPlace, size)
        }
        if (cursorHere == row.items.size) Caret(size)
    }
}

@Composable
private fun ItemView(item: EditItem, path: List<Int>, index: Int, cursor: EditCursor?, onPlace: (EditCursor) -> Unit, size: TextUnit) {
    fun slot(number: Int) = path + listOf(index, number)
    when (item.kind) {
        "symbol" -> Box(
            Modifier.pointerInput(path, index) {
                // The nearer side of the symbol touched.
                detectTapGestures { offset -> onPlace(EditCursor(path, if (offset.x < this.size.width / 2) index else index + 1)) }
            },
        ) {
            MathText(displayed(item.text), size)
        }
        "fraction" -> FractionLayout(
            size,
            { RowView(item.slots[0], slot(0), cursor, onPlace, size * 0.9f) },
            { RowView(item.slots[1], slot(1), cursor, onPlace, size * 0.9f) },
        )
        // An exponent follows its base in the row; it is lifted above the axis.
        "power" -> PowerLayout(size, {}, { RowView(item.slots[0], slot(0), cursor, onPlace, size * 0.65f) })
        "radical" -> RadicalLayout(size, { RowView(item.slots[0], slot(0), cursor, onPlace, size) })
        else -> RadicalLayout(
            size,
            { RowView(item.slots[1], slot(1), cursor, onPlace, size) },
            index = { RowView(item.slots[0], slot(0), cursor, onPlace, size * 0.55f) },
        )
    }
}

/** The symbols of the editor read as in the formula: `·` for `*`, `−` for `-`. */
private fun displayed(text: String) = when (text) {
    "*" -> "·"
    "-" -> "−"
    else -> text
}

/** The cursor: a thin bar in the accent color, on the axis of its row. */
@Composable
private fun Caret(size: TextUnit) {
    val color = MaterialTheme.colorScheme.primary
    Layout(content = { Box(Modifier.background(color)) }) { measurables, _ ->
        val height = (size.toPx() * 1.15f).roundToInt()
        val bar = measurables[0].measure(Constraints.fixed(1.5.dp.roundToPx(), height))
        layout(bar.width, height, mapOf(MathAxis to (height * 0.62f).roundToInt())) { bar.place(0, 0) }
    }
}

/** An empty place of a structure, in a dotted frame; touching it puts the cursor there. */
@Composable
private fun EmptyPlace(size: TextUnit, hasCursor: Boolean, onTap: () -> Unit) {
    val color = MaterialTheme.colorScheme.onSurfaceVariant
    val caret = MaterialTheme.colorScheme.primary
    Layout(
        content = {},
        modifier = Modifier
            .pointerInput(Unit) { detectTapGestures { onTap() } }
            .drawBehind {
                drawRoundRect(
                    color.copy(alpha = 0.6f),
                    cornerRadius = CornerRadius(3.dp.toPx()),
                    style = Stroke(1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 2.dp.toPx()))),
                )
                if (hasCursor) {
                    val x = this.size.width / 2
                    drawLine(caret, Offset(x, 3.dp.toPx()), Offset(x, this.size.height - 3.dp.toPx()), 1.5.dp.toPx())
                }
            },
    ) { _, _ ->
        val width = (size.toPx() * 0.6f).roundToInt()
        val height = (size.toPx() * 0.95f).roundToInt()
        layout(width, height, mapOf(MathAxis to height / 2)) {}
    }
}
