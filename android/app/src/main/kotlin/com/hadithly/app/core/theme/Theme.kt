package com.hadithly.app.core.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Design tokens adapted from the Sajda-style reader reference:
 * near-black canvas, elevated dark surfaces, emerald accent. Mirrors
 * ios/Hadithly/Core/Theme/Theme.swift — keep the two in sync.
 */
object ThemeColors {
    val Background = Color(0xFF0D0D0D)
    val Surface = Color(0xFF1A1A1A)
    val SurfaceElevated = Color(0xFF2A2A2C)

    val TextPrimary = Color(0xFFF2F2F2)
    val TextSecondary = Color(0xFF98989E)

    val Accent = Color(0xFF10B981)
    val AccentSoft = Color(0xFF10B981).copy(alpha = 0.18f)

    val Bookmark = Color(0xFFF59E0B)
    val Favorite = Color(0xFFEC4899)
    val Destructive = Color(0xFFEF4444)
}

data class HadithlyColors(
    val background: Color = ThemeColors.Background,
    val surface: Color = ThemeColors.Surface,
    val surfaceElevated: Color = ThemeColors.SurfaceElevated,
    val textPrimary: Color = ThemeColors.TextPrimary,
    val textSecondary: Color = ThemeColors.TextSecondary,
    val accent: Color = ThemeColors.Accent,
    val accentSoft: Color = ThemeColors.AccentSoft,
    val bookmark: Color = ThemeColors.Bookmark,
    val favorite: Color = ThemeColors.Favorite,
    val destructive: Color = ThemeColors.Destructive,
    val divider: Color = ThemeColors.SurfaceElevated,
)

val LocalHadithlyColors = staticCompositionLocalOf { HadithlyColors() }

/**
 * Reader-scoped palettes (R4). The reader honors the F2 `ReaderTheme`
 * preference: System follows the OS appearance; Light, Paper, and Dark are
 * explicit. Mirrors ios/Hadithly/Core/Theme/ReaderPalette.swift.
 */
object ReaderPalettes {
    val light = HadithlyColors(
        background = Color(0xFFFFFFFF),
        surface = Color(0xFFF4F4F2),
        surfaceElevated = Color(0xFFE9E9E6),
        textPrimary = Color(0xFF1C1C1E),
        textSecondary = Color(0xFF6B6B70),
        divider = Color(0xFFD9D9D6),
    )

    val paper = HadithlyColors(
        background = Color(0xFFF6EFDF),
        surface = Color(0xFFEFE6D0),
        surfaceElevated = Color(0xFFE5DABE),
        textPrimary = Color(0xFF33301F),
        textSecondary = Color(0xFF7A7357),
        divider = Color(0xFFD6C9A4),
    )

    val dark = HadithlyColors()

    /** Resolves the stored preference against the current OS appearance. */
    fun resolved(theme: com.hadithly.app.core.preferences.ReaderTheme, systemDark: Boolean): HadithlyColors =
        when (theme) {
            com.hadithly.app.core.preferences.ReaderTheme.SYSTEM -> if (systemDark) dark else light
            com.hadithly.app.core.preferences.ReaderTheme.LIGHT -> light
            com.hadithly.app.core.preferences.ReaderTheme.PAPER -> paper
            com.hadithly.app.core.preferences.ReaderTheme.DARK -> dark
        }
}

/**
 * The app's vertical rhythm. Auth screens and onboarding standardize on
 * these steps so pages share one consistent spacing scale.
 */
object Spacing {
    val xs = 4.dp
    val sm = 8.dp
    val md = 12.dp
    val lg = 16.dp
    val xl = 24.dp
    val xxl = 32.dp
}

private val darkScheme = darkColorScheme(
    primary = ThemeColors.Accent,
    onPrimary = Color.Black,
    background = ThemeColors.Background,
    onBackground = ThemeColors.TextPrimary,
    surface = ThemeColors.Surface,
    onSurface = ThemeColors.TextPrimary,
    surfaceVariant = ThemeColors.SurfaceElevated,
    onSurfaceVariant = ThemeColors.TextSecondary,
    error = ThemeColors.Destructive,
)

@Composable
fun HadithlyTheme(content: @Composable () -> Unit) {
    // The app is a dark, quiet book — dark scheme regardless of system setting.
    isSystemInDarkTheme()
    androidx.compose.runtime.CompositionLocalProvider(LocalHadithlyColors provides HadithlyColors()) {
        MaterialTheme(
            colorScheme = darkScheme,
            content = content,
        )
    }
}
