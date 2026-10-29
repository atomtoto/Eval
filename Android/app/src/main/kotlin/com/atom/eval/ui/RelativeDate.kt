package com.atom.eval.ui

import android.icu.text.RelativeDateTimeFormatter
import android.icu.text.RelativeDateTimeFormatter.RelativeDateTimeUnit
import android.text.format.DateUtils
import java.util.Locale

private val formatter = RelativeDateTimeFormatter.getInstance(Locale.FRENCH)
private const val YEAR_IN_MILLIS = 365 * DateUtils.DAY_IN_MILLIS

/**
 * « il y a 5 minutes », « hier », « la semaine dernière »: a modification date as
 * the iOS sheet list writes it. Always in French, like the rest of the app, which
 * DateUtils would not be on a device in another language.
 */
fun relativeDate(millis: Long, now: Long): String {
    val elapsed = (now - millis).coerceAtLeast(0)
    val (amount, unit) = when {
        elapsed < DateUtils.MINUTE_IN_MILLIS -> 0L to RelativeDateTimeUnit.SECOND
        elapsed < DateUtils.HOUR_IN_MILLIS -> elapsed / DateUtils.MINUTE_IN_MILLIS to RelativeDateTimeUnit.MINUTE
        elapsed < DateUtils.DAY_IN_MILLIS -> elapsed / DateUtils.HOUR_IN_MILLIS to RelativeDateTimeUnit.HOUR
        elapsed < DateUtils.WEEK_IN_MILLIS -> elapsed / DateUtils.DAY_IN_MILLIS to RelativeDateTimeUnit.DAY
        elapsed < 30 * DateUtils.DAY_IN_MILLIS -> elapsed / DateUtils.WEEK_IN_MILLIS to RelativeDateTimeUnit.WEEK
        elapsed < YEAR_IN_MILLIS -> elapsed / (30 * DateUtils.DAY_IN_MILLIS) to RelativeDateTimeUnit.MONTH
        else -> elapsed / YEAR_IN_MILLIS to RelativeDateTimeUnit.YEAR
    }
    return formatter.format(-amount.toDouble(), unit)
}
