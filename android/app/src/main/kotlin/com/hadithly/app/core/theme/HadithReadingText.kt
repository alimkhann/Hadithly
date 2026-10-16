package com.hadithly.app.core.theme

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.core.preferences.LocaleFallback

/** Shared card-free rendering for Arabic original and supplied translation. */
@Composable
fun HadithReadingText(
    arabicText: String,
    translation: String?,
    translationLanguage: String?,
    textColor: Color,
    arabicVisible: Boolean = true,
    translationVisible: Boolean = true,
    arabicFontSize: TextUnit = 28.sp,
    arabicFontFamily: FontFamily = ArabicTypefaces.amiri,
    arabicLineHeight: TextUnit = (arabicFontSize.value * 1.75f).sp,
    translationLineLimit: Int = Int.MAX_VALUE,
    translationFontSize: TextUnit = 16.sp,
    translationLineHeight: TextUnit = 22.sp,
    modifier: Modifier = Modifier,
) {
    Column(modifier = modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(13.dp)) {
        if (arabicVisible) {
            Text(
                text = arabicText,
                style = MaterialTheme.typography.headlineMedium.copy(
                    fontFamily = arabicFontFamily,
                    fontSize = arabicFontSize,
                    lineHeight = arabicLineHeight,
                    textAlign = TextAlign.Start,
                    textDirection = TextDirection.Rtl,
                ),
                color = textColor,
                maxLines = translationLineLimit,
                modifier = Modifier.fillMaxWidth().testTag("hadith.text.arabic"),
            )
        }
        if (translationVisible && translation != null) {
            Text(
                text = translation,
                modifier = Modifier.testTag("hadith.text.translation"),
                style = MaterialTheme.typography.bodyLarge.copy(
                    fontSize = translationFontSize,
                    lineHeight = translationLineHeight,
                    textAlign = TextAlign.Start,
                    textDirection = if (translationLanguage?.let { LocaleFallback.isRTL(it) } == true) TextDirection.Rtl else TextDirection.Ltr,
                ),
                color = textColor,
                maxLines = translationLineLimit,
            )
        }
    }
}
