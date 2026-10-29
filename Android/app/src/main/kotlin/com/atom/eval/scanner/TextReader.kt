package com.atom.eval.scanner

import android.graphics.Bitmap
import android.graphics.Rect
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import eval.bridge.FormulaReader
import eval.bridge.TextFragment
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * Reads the formulas of a picture on the device (iOS FormulaRecognizer with Vision):
 * ML Kit finds the characters and their boxes, and the engine rebuilds exponents and
 * fractions from where they lie. Returns the lines to add, top to bottom.
 */
suspend fun readFormulas(image: Bitmap, declared: List<String>): List<String> {
    val recognizer = TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    try {
        val text = suspendCancellableCoroutine { continuation ->
            recognizer.process(InputImage.fromBitmap(image, 0))
                .addOnSuccessListener { continuation.resume(it) }
                .addOnFailureListener { continuation.resumeWithException(it) }
        }
        val width = image.width.toDouble()
        val height = image.height.toDouble()
        val fragments = text.textBlocks.flatMap { it.lines }.mapNotNull { line ->
            val box = line.boundingBox ?: return@mapNotNull null
            // The text and a box per character, spaces between words included.
            val characters = StringBuilder()
            val boxes = mutableListOf<Double>()
            var previous: Rect? = null
            for (element in line.elements) {
                val elementBox = element.boundingBox ?: continue
                previous?.let { before ->
                    characters.append(' ')
                    boxes += normalized(Rect(before.right, elementBox.top, elementBox.left, elementBox.bottom), width, height)
                }
                for (symbol in element.symbols) {
                    val symbolBox = symbol.boundingBox ?: elementBox
                    characters.append(symbol.text)
                    repeat(symbol.text.length) { boxes += normalized(symbolBox, width, height) }
                }
                previous = elementBox
            }
            val (x, y, w, h) = normalized(box, width, height)
            TextFragment(characters.toString(), x, y, w, h, boxes)
        }
        return withContext(Dispatchers.Default) { FormulaReader.lines(fragments, declared) }
    } finally {
        recognizer.close()
    }
}

/** A box in the picture as x, y, width and height from 0 to 1, y growing downward. */
private fun normalized(rect: Rect, width: Double, height: Double): List<Double> =
    listOf(rect.left / width, rect.top / height, maxOf(0, rect.width()) / width, maxOf(0, rect.height()) / height)
