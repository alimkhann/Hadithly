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

enum class ReaderPageTurn { PREVIOUS, NEXT }

enum class SwipeDirection { LEFT, RIGHT }

data class ReaderPagingPolicy(val pageDirection: PageDirection) {
    constructor(preferences: ReaderPreferences) : this(
        ReaderPreferencesValidator.directionMetadata(preferences).pageDirection,
    )

    val reverseLayout: Boolean get() = pageDirection == PageDirection.RTL

    fun turn(swipe: SwipeDirection): ReaderPageTurn = when (pageDirection to swipe) {
        PageDirection.LTR to SwipeDirection.LEFT,
        PageDirection.RTL to SwipeDirection.RIGHT -> ReaderPageTurn.NEXT
        PageDirection.LTR to SwipeDirection.RIGHT,
        PageDirection.RTL to SwipeDirection.LEFT -> ReaderPageTurn.PREVIOUS
        else -> error("Unhandled page direction and swipe pair")
    }

    fun destination(index: Int, pageCount: Int, turn: ReaderPageTurn): Int? {
        if (pageCount <= 0 || index !in 0 until pageCount) return null
        val candidate = if (turn == ReaderPageTurn.NEXT) index + 1 else index - 1
        return candidate.takeIf { it in 0 until pageCount }
    }

    val endControlOrder: List<ReaderPageTurn>
        get() = if (pageDirection == PageDirection.LTR) {
            listOf(ReaderPageTurn.PREVIOUS, ReaderPageTurn.NEXT)
        } else {
            listOf(ReaderPageTurn.NEXT, ReaderPageTurn.PREVIOUS)
        }
}

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
        const val DEFAULT_ARABIC_FONT_SIZE = 26f

        /** The accessible Arabic type ladder behind the A−/A+ stepper. */
        val ARABIC_FONT_SIZE_STEPS = listOf(18f, 22f, 26f, 30f, 34f, 40f)
    }

    /**
     * The layout-affecting projection used to recompute the layout signature
     * and re-anchor the semantic position when reading preferences change.
     */
    val layoutProjection: String
        get() = listOf(
            translationLocale,
            if (arabicVisible) "1" else "0",
            if (translationVisible) "1" else "0",
            arabicFont.wire,
            (arabicFontSize * 1000).toInt().toString(),
        ).joinToString("|")
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

/** Step helpers over the accessible Arabic type ladder. */
object ArabicTypeSize {
    fun nearest(size: Float): Float =
        ReaderPreferences.ARABIC_FONT_SIZE_STEPS.minByOrNull { kotlin.math.abs(it - size) }
            ?: ReaderPreferences.DEFAULT_ARABIC_FONT_SIZE

    fun stepUp(size: Float): Float =
        ReaderPreferences.ARABIC_FONT_SIZE_STEPS.firstOrNull { it > size + 0.5f }
            ?: ReaderPreferences.MAX_ARABIC_FONT_SIZE

    fun stepDown(size: Float): Float =
        ReaderPreferences.ARABIC_FONT_SIZE_STEPS.lastOrNull { it < size - 0.5f }
            ?: ReaderPreferences.MIN_ARABIC_FONT_SIZE
}

/** Convex wire encoding. All numbers travel as Double. */
fun ReaderPreferences.toWireMap(): Map<String, Any?> = mapOf(    "schemaVersion" to schemaVersion.toDouble(),
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
