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
)

val LocalHadithlyColors = staticCompositionLocalOf { HadithlyColors() }

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
