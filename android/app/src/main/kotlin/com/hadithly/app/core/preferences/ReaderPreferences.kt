package com.hadithly.app.core.preferences

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder

/**
 * Reader preference contracts (F2). Mirrors backend/convex/lib/preferences.ts
 * and the iOS Core/Preferences port. The wire shape is flat JSON; numbers are
 * encoded as Double because Convex `v.number()` rejects integer wrappers.
 */

@Serializable
enum class ReadingDirection(val wire: String) {
    @SerialName("auto") AUTO("auto"),
    @SerialName("rtl") RTL("rtl"),
    @SerialName("ltr") LTR("ltr");

    companion object {
        fun fromWire(raw: String?): ReadingDirection? =
            raw?.let { wire -> entries.firstOrNull { it.wire == wire } }
    }
}

@Serializable
enum class ReaderTheme(val wire: String) {
    @SerialName("system") SYSTEM("system"),
    @SerialName("light") LIGHT("light"),
    @SerialName("paper") PAPER("paper"),
    @SerialName("dark") DARK("dark");

    companion object {
        fun fromWire(raw: String?): ReaderTheme? =
            raw?.let { wire -> entries.firstOrNull { it.wire == wire } }
    }
}

/** Licensed Arabic font ids (docs/FONT_LICENSES.md). Unknown ids fall back. */
enum class ArabicFont(val wire: String) {
    SYSTEM("system"),
    AMIRI("amiri"),
    SCHEHERAZADE_NEW("scheherazade-new"),
    NOTO_NASKH_ARABIC("noto-naskh-arabic");

    companion object {
        fun fromWire(raw: String?): ArabicFont =
            raw?.let { wire -> entries.firstOrNull { it.wire == wire } } ?: SYSTEM
    }
}

/** Lenient decode: a newer build's font id falls back to system, matching iOS. */
object ArabicFontSerializer : KSerializer<ArabicFont> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("ArabicFont", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: ArabicFont) =
        encoder.encodeString(value.wire)

    override fun deserialize(decoder: Decoder): ArabicFont =
        ArabicFont.fromWire(decoder.decodeString())
}

enum class PageDirection { RTL, LTR }

/** Direction metadata consumed by R3 paging and R4 layout. */
data class DirectionMetadata(
    val pageDirection: PageDirection,
    /** Arabic blocks always lay out RTL, including inside mixed pages. */
    val arabicBlocksRtl: Boolean = true,
)

sealed class PreferencesException(message: String) : Exception(message) {
    class InvalidLocale(tag: String) :
        PreferencesException("INVALID_LOCALE: $tag")
    class InvalidArabicFont(id: String) :
        PreferencesException("INVALID_ARABIC_FONT: $id")
    class AllHiddenVisibility :
        PreferencesException("VISIBILITY_ALL_HIDDEN: Arabic and translation visibility cannot both be disabled")
}

@Serializable
data class ReaderPreferences(
    val schemaVersion: Int = SCHEMA_VERSION,
    val uiLocale: String = "en",
    val translationLocale: String = "en",
    val readingDirection: ReadingDirection = ReadingDirection.AUTO,
    val theme: ReaderTheme = ReaderTheme.SYSTEM,
    @Serializable(with = ArabicFontSerializer::class)
    val arabicFont: ArabicFont = ArabicFont.SYSTEM,
    val arabicFontSize: Float = 26f,
    val arabicVisible: Boolean = true,
    val translationVisible: Boolean = true,
    val updatedAt: Double = 0.0,
) {
    companion object {
        const val SCHEMA_VERSION = 1
        const val MIN_ARABIC_FONT_SIZE = 18f
        const val MAX_ARABIC_FONT_SIZE = 40f
    }
}

object ReaderPreferencesValidator {

    /**
     * Normalizes a preference object at the boundary. Rejects the all-hidden
     * visibility state in shared domain logic; clamps the font size.
     */
    fun validated(preferences: ReaderPreferences): ReaderPreferences {
        val ui = LocaleFallback.canonicalizeLocaleTag(preferences.uiLocale)
            ?: throw PreferencesException.InvalidLocale(preferences.uiLocale)
        val translation = LocaleFallback.canonicalizeLocaleTag(preferences.translationLocale)
            ?: throw PreferencesException.InvalidLocale(preferences.translationLocale)
        if (!preferences.arabicFont.wire.matches(Regex("^[A-Za-z0-9_-]{1,64}$"))) {
            throw PreferencesException.InvalidArabicFont(preferences.arabicFont.wire)
        }
        if (!preferences.arabicVisible && !preferences.translationVisible) {
            throw PreferencesException.AllHiddenVisibility()
        }
        return preferences.copy(
            schemaVersion = ReaderPreferences.SCHEMA_VERSION,
            uiLocale = ui,
            translationLocale = translation,
            arabicFontSize = preferences.arabicFontSize
                .coerceIn(ReaderPreferences.MIN_ARABIC_FONT_SIZE, ReaderPreferences.MAX_ARABIC_FONT_SIZE),
        )
    }

    /**
     * Resolves `auto` direction: RTL for Arabic-only reading, the
     * translation script for translation-only and mixed pages.
     */
    fun directionMetadata(preferences: ReaderPreferences): DirectionMetadata = when (preferences.readingDirection) {
        ReadingDirection.RTL -> DirectionMetadata(PageDirection.RTL)
        ReadingDirection.LTR -> DirectionMetadata(PageDirection.LTR)
        ReadingDirection.AUTO -> {
            val arabicOnly = preferences.arabicVisible && !preferences.translationVisible
            if (arabicOnly) {
                DirectionMetadata(PageDirection.RTL)
            } else {
                val translationRtl = LocaleFallback.isRTL(preferences.translationLocale)
                DirectionMetadata(if (translationRtl) PageDirection.RTL else PageDirection.LTR)
            }
        }
    }
}

/** Convex wire encoding. All numbers travel as Double. */
fun ReaderPreferences.toWireMap(): Map<String, Any?> = mapOf(
    "schemaVersion" to schemaVersion.toDouble(),
    "uiLocale" to uiLocale,
    "translationLocale" to translationLocale,
    "readingDirection" to readingDirection.wire,
    "theme" to theme.wire,
    "arabicFont" to arabicFont.wire,
    "arabicFontSize" to arabicFontSize.toDouble(),
    "arabicVisible" to arabicVisible,
    "translationVisible" to translationVisible,
    "updatedAt" to updatedAt,
)
