package com.atom.eval.ui.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color

// The accent leads; the other roles are warm tones that keep it the only strong color.
// In light mode the page is the warm cream of the iOS sheets (surface and background),
// and surfaceContainerLowest is the lighter warm row drawn on it.
private val LightColors = lightColorScheme(
    primary = AccentLight,
    onPrimary = Color.White,
    primaryContainer = Color(0xFFFFDBCB),
    onPrimaryContainer = Color(0xFF6B2500),
    inversePrimary = Color(0xFFFFB590),
    secondary = Color(0xFF765749),
    onSecondary = Color.White,
    secondaryContainer = Color(0xFFF6DED3),
    onSecondaryContainer = Color(0xFF2C160C),
    tertiary = Color(0xFF66602F),
    onTertiary = Color.White,
    tertiaryContainer = Color(0xFFEDE5A8),
    onTertiaryContainer = Color(0xFF1F1C00),
    background = WarmBackground,
    onBackground = WarmText,
    surface = WarmBackground,
    onSurface = WarmText,
    surfaceVariant = Color(0xFFEDE4DC),
    onSurfaceVariant = WarmSecondaryText,
    surfaceTint = AccentLight,
    inverseSurface = Color(0xFF34302C),
    inverseOnSurface = Color(0xFFF7EFEA),
    outline = Color(0xFF85746A),
    outlineVariant = Color(0xFFD8CDC4),
    surfaceBright = WarmRow,
    surfaceDim = Color(0xFFE1DCD3),
    surfaceContainerLowest = WarmRow,
    surfaceContainerLow = WarmContainerLow,
    surfaceContainer = WarmContainer,
    surfaceContainerHigh = WarmContainerHigh,
    surfaceContainerHighest = WarmContainerHighest,
)

private val DarkColors = darkColorScheme(
    primary = AccentDark,
    onPrimary = Color(0xFF451800),
    primaryContainer = Color(0xFF7A2E00),
    onPrimaryContainer = Color(0xFFFFDBCB),
    inversePrimary = AccentLight,
    secondary = Color(0xFFE6BEAD),
    onSecondary = Color(0xFF442A1F),
    secondaryContainer = Color(0xFF5B4034),
    onSecondaryContainer = Color(0xFFFFDBCE),
    tertiary = Color(0xFFD1C98E),
    onTertiary = Color(0xFF363105),
    tertiaryContainer = Color(0xFF4D481A),
    onTertiaryContainer = Color(0xFFEDE5A8),
    background = DarkBackground,
    onBackground = DarkText,
    surface = DarkBackground,
    onSurface = DarkText,
    surfaceVariant = Color(0xFF52463E),
    onSurfaceVariant = DarkSecondaryText,
    surfaceTint = AccentDark,
    inverseSurface = DarkText,
    inverseOnSurface = Color(0xFF34302C),
    outline = Color(0xFF9F8E85),
    outlineVariant = Color(0xFF52463E),
    surfaceBright = Color(0xFF3B3835),
    surfaceDim = DarkBackground,
    surfaceContainerLowest = DarkContainerLowest,
    surfaceContainerLow = DarkContainerLow,
    surfaceContainer = DarkContainer,
    surfaceContainerHigh = DarkContainerHigh,
    surfaceContainerHighest = DarkContainerHighest,
)

/** Eval's Material theme: the orange accent, light or dark like the system, default typography. */
@Composable
fun EvalTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
    MaterialTheme(colorScheme = if (darkTheme) DarkColors else LightColors, content = content)
}
