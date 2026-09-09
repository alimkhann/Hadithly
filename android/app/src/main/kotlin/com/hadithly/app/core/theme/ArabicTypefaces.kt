package com.hadithly.app.core.theme

import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import com.hadithly.app.R
import com.hadithly.app.core.preferences.ArabicFont

/**
 * Licensed Arabic faces (R4). Binaries live in res/font with the OFL license
 * text in assets/font-licenses; records in docs/FONT_LICENSES.md. The system
 * fallback keeps the preference contract safe when a face is unavailable.
 */
object ArabicTypefaces {
    val amiri = FontFamily(Font(R.font.amiri_regular))
    val scheherazadeNew = FontFamily(Font(R.font.scheherazade_new_regular))
    val notoNaskhArabic = FontFamily(Font(R.font.noto_naskh_arabic_regular))
    val system = FontFamily.Default

    fun forFont(font: ArabicFont): FontFamily = when (font) {
        ArabicFont.SYSTEM -> system
        ArabicFont.AMIRI -> amiri
        ArabicFont.SCHEHERAZADE_NEW -> scheherazadeNew
        ArabicFont.NOTO_NASKH_ARABIC -> notoNaskhArabic
    }
}
