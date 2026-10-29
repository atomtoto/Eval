package com.atom.eval.data

import android.content.Context
import androidx.core.content.edit
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

/** How a line is edited when it is touched, as on iOS. */
enum class FormulaInputMode(val key: String) { Text("text"), Math("math") }

/** The accent color of the whole app, as on iOS. */
enum class Accent(val key: String) { Orange("orange"), Blue("blue") }

/**
 * The preferences of « Réglages », shared by every sheet, under the keys iOS uses.
 * The number of significant digits goes to the engine, which formats the results.
 */
class AppSettings(context: Context) {
    private val preferences = context.getSharedPreferences("settings", Context.MODE_PRIVATE)

    private val _inputMode = MutableStateFlow(
        FormulaInputMode.entries.firstOrNull { it.key == preferences.getString(INPUT_MODE, null) } ?: FormulaInputMode.Text
    )
    private val _significantDigits = MutableStateFlow(
        preferences.getInt(SIGNIFICANT_DIGITS, DEFAULT_DIGITS).coerceIn(MINIMUM_DIGITS, MAXIMUM_DIGITS)
    )
    private val _lineNumbers = MutableStateFlow(preferences.getBoolean(LINE_NUMBERS, false))
    private val _accent = MutableStateFlow(Accent.entries.firstOrNull { it.key == preferences.getString(ACCENT, null) } ?: Accent.Orange)
    private val _warmBackground = MutableStateFlow(preferences.getBoolean(WARM_BACKGROUND, true))

    val inputMode: StateFlow<FormulaInputMode> = _inputMode.asStateFlow()
    val significantDigits: StateFlow<Int> = _significantDigits.asStateFlow()
    val lineNumbers: StateFlow<Boolean> = _lineNumbers.asStateFlow()
    val accent: StateFlow<Accent> = _accent.asStateFlow()
    val warmBackground: StateFlow<Boolean> = _warmBackground.asStateFlow()

    init {
        eval.bridge.EvalSettings.significantDigits = _significantDigits.value
    }

    fun setInputMode(mode: FormulaInputMode) {
        _inputMode.value = mode
        preferences.edit { putString(INPUT_MODE, mode.key) }
    }

    fun setSignificantDigits(digits: Int) {
        val clamped = digits.coerceIn(MINIMUM_DIGITS, MAXIMUM_DIGITS)
        eval.bridge.EvalSettings.significantDigits = clamped
        _significantDigits.value = clamped
        preferences.edit { putInt(SIGNIFICANT_DIGITS, clamped) }
    }

    fun setLineNumbers(shown: Boolean) {
        _lineNumbers.value = shown
        preferences.edit { putBoolean(LINE_NUMBERS, shown) }
    }

    fun setAccent(accent: Accent) {
        _accent.value = accent
        preferences.edit { putString(ACCENT, accent.key) }
    }

    fun setWarmBackground(warm: Boolean) {
        _warmBackground.value = warm
        preferences.edit { putBoolean(WARM_BACKGROUND, warm) }
    }

    companion object {
        const val MINIMUM_DIGITS = 3
        const val MAXIMUM_DIGITS = 12
        const val DEFAULT_DIGITS = 6
        private const val INPUT_MODE = "eval.formulaInput.v1"
        private const val SIGNIFICANT_DIGITS = "eval.significantDigits.v1"
        private const val LINE_NUMBERS = "eval.lineNumbers.v1"
        private const val ACCENT = "eval.accent.v1"
        private const val WARM_BACKGROUND = "eval.warmBackground.v1"
    }
}
