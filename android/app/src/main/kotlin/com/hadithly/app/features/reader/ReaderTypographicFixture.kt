package com.hadithly.app.features.reader

import androidx.compose.foundation.background
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.preferences.ArabicFont
import com.hadithly.app.core.preferences.ArabicTypeSize
import com.hadithly.app.core.preferences.LocaleFallback
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.theme.ArabicTypefaces
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.ReaderPalettes

/**
 * Deterministic fixture for the R4 typography, theme, and visibility
 * screenshot and accessibility matrix (and the R3 paging tests). R3_*
 * variables keep their paging meaning; R4_* variables select the reader
 * chrome to render: theme, font, size, and whether the revealed chrome shows.
 */
@Composable
fun ReaderTypographicFixture(extras: android.os.Bundle?) {
    val preferences = ReaderPreferences(
        translationLocale = extras?.getString("R3_TRANSLATION_LOCALE") ?: "en",
        arabicVisible = extras?.getString("R3_ARABIC_VISIBLE") != "false",
        translationVisible = extras?.getString("R3_TRANSLATION_VISIBLE") != "false",
        theme = ReaderTheme.fromWire(extras?.getString("R4_THEME")) ?: ReaderTheme.DARK,
        arabicFont = ArabicFont.fromWire(extras?.getString("R4_FONT")),
        arabicFontSize = extras?.getString("R4_SIZE")?.toFloatOrNull()
            ?.coerceIn(ReaderPreferences.MIN_ARABIC_FONT_SIZE, ReaderPreferences.MAX_ARABIC_FONT_SIZE)
            ?: ReaderPreferences.DEFAULT_ARABIC_FONT_SIZE,
    )
    val showChrome = extras?.getString("R4_CHROME") == "true"
    val systemDark = isSystemInDarkTheme()
    val colors = ReaderPalettes.resolved(preferences.theme, systemDark)
    val policy = ReaderPagingPolicy(preferences)
    val pageCount = 3
    val pageIndex = 1

    CompositionLocalProvider(LocalHadithlyColors provides colors) {
        // The matrix drives the reading language directly, so the fixture
        // pins its layout direction to the translation script rather than
        // the device locale.
        CompositionLocalProvider(
            LocalLayoutDirection provides if (LocaleFallback.isRTL(preferences.translationLocale)) {
                LayoutDirection.Rtl
            } else {
                LayoutDirection.Ltr
            },
        ) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(colors.background),
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(24.dp),
                modifier = Modifier
                    .fillMaxSize()
                    .verticalScroll(rememberScrollState())
                    .padding(22.dp)
                    .testTag("r4.surface"),
            ) {
                if (showChrome) {
                    Text(
                        text = "Page ${pageIndex + 1} of $pageCount",
                        fontSize = 12.sp,
                        fontWeight = FontWeight.Medium,
                        color = colors.textSecondary,
                        modifier = Modifier
                            .background(colors.surface.copy(alpha = 0.96f), RoundedCornerShape(50))
                            .padding(horizontal = 12.dp, vertical = 7.dp)
                            .testTag("r4.progressPill"),
                    )
                } else {
                    Box(
                        modifier = Modifier
                            .statusBarsPadding()
                            .padding(top = 6.dp)
                            .fillMaxWidth()
                            .height(3.dp)
                            .background(colors.divider.copy(alpha = 0.6f), RoundedCornerShape(50))
                            .testTag("r4.compactProgressOuter"),
                    ) {
                        Box(
                            modifier = Modifier
                                .fillMaxWidth(((pageIndex + 1).toDouble() / pageCount).toFloat())
                                .height(3.dp)
                                .background(colors.interactive.copy(alpha = 0.8f), RoundedCornerShape(50))
                                .testTag("r4.compactProgress"),
                        )
                    }
                }

                Text(
                    text = "Page ${pageIndex + 1}",
                    fontSize = 17.sp,
                    fontWeight = FontWeight.Bold,
                    color = colors.textPrimary,
                    modifier = Modifier.testTag("r3.page"),
                )

                ReaderChapterHeader(title = "Kitab al-Iman")

                if (preferences.arabicVisible) {
                    val layoutDirection = LocalLayoutDirection.current
                    CompositionLocalProvider(LocalLayoutDirection provides LayoutDirection.Rtl) {
                        Text(
                            text = "إنما الأعمال بالنيات",
                            fontSize = preferences.arabicFontSize.sp,
                            fontFamily = ArabicTypefaces.forFont(preferences.arabicFont),
                            fontWeight = FontWeight.Medium,
                            color = colors.textPrimary,
                            lineHeight = (preferences.arabicFontSize * 1.75).sp,
                            textAlign = TextAlign.Center,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("r3.arabic"),
                        )
                    }
                }

                if (preferences.translationVisible) {
                    CompositionLocalProvider(
                        LocalLayoutDirection provides if (LocaleFallback.isRTL(preferences.translationLocale)) {
                            LayoutDirection.Rtl
                        } else {
                            LayoutDirection.Ltr
                        },
                    ) {
                        Text(
                            text = if (LocaleFallback.isRTL(preferences.translationLocale)) {
                                "اعمال کا دار و مدار نیتوں پر ہے"
                            } else {
                                "Actions are judged by intentions."
                            },
                            fontSize = 16.sp,
                            color = colors.textPrimary,
                            modifier = Modifier
                                .fillMaxWidth()
                                .testTag("r3.translation"),
                        )
                    }
                }

                Text(
                    text = "End of page",
                    fontSize = 14.sp,
                    color = colors.textSecondary,
                    modifier = Modifier.testTag("r3.end"),
                )

                ReaderEndNavigation(
                    policy = policy,
                    currentPageIndex = pageIndex,
                    pageCount = pageCount,
                    onTurn = {},
                )
            }
        }
        }
    }
}
