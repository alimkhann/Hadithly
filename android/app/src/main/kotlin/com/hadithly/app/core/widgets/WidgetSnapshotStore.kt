package com.hadithly.app.core.widgets

import android.content.Context
import com.hadithly.app.core.data.ProgressEntry
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * A deliberately narrow, device-local cache for widgets. Saved notes,
 * account/profile fields, and folder names are not representable here.
 */
@Serializable
data class DailyWidgetSnapshot(
    val collectionSlug: String,
    val providerHadithId: String,
    val reference: String,
    val text: String,
    val arabicText: String = "",
    val locale: String,
    val arabicVisible: Boolean = true,
    val translationVisible: Boolean = true,
    val isAI: Boolean,
    val sourceScope: String,
    val localDate: String,
    val timezone: String,
    val isOffline: Boolean,
    val updatedAt: Long,
)

/** Public W1 payload; its shape cannot carry notes, accounts, or positions. */
@Serializable
data class DailyWidgetPayload(
    val collectionSlug: String,
    val providerHadithId: String,
    val reference: String,
    val text: String,
    val arabicText: String = "",
    val locale: String,
    val arabicVisible: Boolean = true,
    val translationVisible: Boolean = true,
    val isAI: Boolean,
    val sourceScope: String,
    val localDate: String,
    val timezone: String,
    val updatedAt: Double,
)

@Serializable
data class ContinueWidgetSnapshot(
    val reference: String,
    val arabicExcerpt: String,
    val translationExcerpt: String,
    val arabicVisible: Boolean,
    val translationVisible: Boolean,
    val progressFraction: Double? = null,
    val progressLabel: String,
    val locale: String,
    val updatedAt: Long,
)

data class ContinueWidgetPresentation(
    val reference: String,
    val arabicExcerpt: String,
    val translationExcerpt: String,
    val arabicVisible: Boolean,
    val translationVisible: Boolean,
    val progressFraction: Double?,
    val progressLabel: String,
    val locale: String,
) {
    val compactLines: List<String> get() = listOf(reference, progressLabel)
    val mediumExcerptLines: Int get() = 2
    val largeExcerptLines: Int get() = 4
    val accessoryInlineText: String get() = "Resume reading"
    val isRightToLeft: Boolean get() = locale.substringBefore('-') in setOf("ar", "fa", "ur")

    companion object {
        const val EMPTY_MESSAGE = "Read a hadith to continue here."
        const val LOCK_MESSAGE = "Unlock Hadithly to resume reading."
    }
}

class WidgetSnapshotStore(context: Context) {
    private val prefs = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun saveDaily(payload: DailyWidgetPayload?) {
        val snapshot = payload?.let {
            DailyWidgetSnapshot(
                collectionSlug = it.collectionSlug,
                providerHadithId = it.providerHadithId,
                reference = it.reference, text = it.text, arabicText = it.arabicText, locale = it.locale,
                arabicVisible = it.arabicVisible, translationVisible = it.translationVisible, isAI = it.isAI,
                sourceScope = it.sourceScope, localDate = it.localDate, timezone = it.timezone,
                isOffline = false, updatedAt = it.updatedAt.toLong(),
            )
        }
        prefs.edit().apply {
            if (snapshot == null) remove(DAILY) else putString(DAILY, json.encodeToString(snapshot))
        }.apply()
    }

    fun markDailyOffline(locale: String, timezone: String): Boolean {
        val snapshot = daily()
        if (snapshot == null || snapshot.locale != locale || snapshot.timezone != timezone) {
            saveDaily(null)
            return false
        }
        prefs.edit().putString(DAILY, json.encodeToString(snapshot.copy(isOffline = true))).apply()
        return true
    }

    fun saveContinue(entry: ProgressEntry?, locale: String, translationVisible: Boolean, arabicVisible: Boolean, progressFraction: Double? = null, progressLabel: String = "Resume reading") {
        val hadith = entry?.hadith
        val snapshot = if (entry != null && hadith != null) {
            ContinueWidgetSnapshot(
                reference = hadith.referenceDisplay,
                arabicExcerpt = boundedExcerpt(hadith.arabicText),
                translationExcerpt = boundedExcerpt(hadith.englishText ?: ""),
                arabicVisible = arabicVisible,
                translationVisible = translationVisible,
                progressFraction = progressFraction,
                progressLabel = progressLabel,
                locale = locale,
                updatedAt = entry.updatedAt.toLong(),
            )
        } else null
        prefs.edit().apply {
            if (snapshot == null) remove(CONTINUE) else putString(CONTINUE, json.encodeToString(snapshot))
        }.apply()
    }

    fun daily(): DailyWidgetSnapshot? = read(DAILY)
    fun continueReading(): ContinueWidgetSnapshot? = read(CONTINUE)

    private fun boundedExcerpt(text: String, limit: Int = 280): String =
        text.take(limit).trim()

    private inline fun <reified T> read(key: String): T? =
        prefs.getString(key, null)?.let { runCatching { json.decodeFromString<T>(it) }.getOrNull() }

    private companion object {
        const val PREFS = "hadithly.widgets"
        const val DAILY = "daily.v2"
        const val CONTINUE = "continue.v1"
        val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    }
}

object WidgetRefreshPolicy {
    const val MAX_AGE_MS = 36L * 60L * 60L * 1000L
    fun isStale(updatedAt: Long, now: Long = System.currentTimeMillis()): Boolean = now - updatedAt > MAX_AGE_MS
    fun isStale(snapshot: DailyWidgetSnapshot, now: Long = System.currentTimeMillis()): Boolean {
        val currentDay = java.time.LocalDate.now(java.time.ZoneId.of(snapshot.timezone)).toString()
        return snapshot.isOffline || snapshot.localDate != currentDay || isStale(snapshot.updatedAt, now)
    }
}
