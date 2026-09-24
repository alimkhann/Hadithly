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

object DailyWidgetCopy {
    fun title(locale: String): String = when (locale.substringBefore('-')) {
        "ar" -> "الحديث اليومي"
        "ur" -> "آج کی حدیث"
        else -> "Daily Hadith"
    }
    fun empty(locale: String): String = when (locale.substringBefore('-')) {
        "ar" -> "افتح حديثلي لتحضير حديث اليوم."
        "ur" -> "آج کی حدیث تیار کرنے کے لیے حدیثلی کھولیں۔"
        else -> "Open Hadithly to prepare today’s hadith."
    }
    fun locked(locale: String): String = when (locale.substringBefore('-')) {
        "ar" -> "افتح قفل الجهاز لعرض حديث اليوم."
        "ur" -> "آج کی حدیث دیکھنے کے لیے آلہ کھولیں۔"
        else -> "Unlock Hadithly to view today’s hadith."
    }
}

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
    val progressFraction: Double? = null,
    val progressOrdinal: Int? = null,
    val progressTotal: Int? = null,
    val locale: String,
    val updatedAt: Long,
)

data class ContinueWidgetPresentation(
    val reference: String,
    val progressFraction: Double?,
    val progressOrdinal: Int?,
    val progressTotal: Int?,
    val locale: String,
) {
    private val language: String get() = locale.substringBefore('-')
    val title: String get() = when (language) { "ar" -> "متابعة القراءة"; "ur" -> "مطالعہ جاری رکھیں"; else -> "Continue Reading" }
    val resumeText: String get() = when (language) { "ar" -> "استئناف القراءة"; "ur" -> "مطالعہ جاری رکھیں"; else -> "Resume reading" }
    val progressLabel: String get() = if (progressOrdinal != null && progressTotal != null && progressTotal > 0) {
        when (language) {
            "ar" -> "الحديث $progressOrdinal من $progressTotal"
            "ur" -> "حدیث $progressOrdinal، کل $progressTotal"
            else -> "Hadith $progressOrdinal of $progressTotal"
        }
    } else resumeText
    val localizedReference: String get() = when (language) {
        "ar" -> reference.replace("Hadith ", "الحديث ")
        "ur" -> reference.replace("Hadith ", "حدیث ")
        else -> reference
    }
    val compactLines: List<String> get() = listOf(localizedReference, progressLabel)
    val accessoryInlineText: String get() = resumeText
    val isRightToLeft: Boolean get() = locale.substringBefore('-') in setOf("ar", "fa", "ur")
    val emptyMessage: String get() = when (language) { "ar" -> "اقرأ حديثًا للمتابعة هنا."; "ur" -> "یہاں سے جاری رکھنے کے لیے حدیث پڑھیں۔"; else -> EMPTY_MESSAGE }
    val lockMessage: String get() = when (language) { "ar" -> "افتح قفل الجهاز لمتابعة القراءة."; "ur" -> "مطالعہ جاری رکھنے کے لیے آلہ کھولیں۔"; else -> LOCK_MESSAGE }
    val staleMessage: String get() = when (language) { "ar" -> "سيُتحقق من الموضع عند الفتح"; "ur" -> "کھولنے پر مقام کی جانچ ہوگی"; else -> "Position will be checked when opened" }

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

    fun saveContinue(entry: ProgressEntry?, locale: String, progressFraction: Double? = null, progressOrdinal: Int? = null, progressTotal: Int? = null) {
        val hadith = entry?.hadith
        val snapshot = if (entry != null && hadith != null) {
            ContinueWidgetSnapshot(
                reference = hadith.referenceDisplay,
                progressFraction = progressFraction,
                progressOrdinal = progressOrdinal,
                progressTotal = progressTotal,
                locale = locale,
                updatedAt = entry.updatedAt.toLong(),
            )
        } else null
        prefs.edit().apply {
            remove(LEGACY_CONTINUE)
            if (snapshot == null) remove(CONTINUE) else putString(CONTINUE, json.encodeToString(snapshot))
        }.apply()
    }

    fun daily(): DailyWidgetSnapshot? = read(DAILY)
    fun continueReading(): ContinueWidgetSnapshot? {
        prefs.edit().remove(LEGACY_CONTINUE).apply()
        return read(CONTINUE)
    }

    private inline fun <reified T> read(key: String): T? =
        prefs.getString(key, null)?.let { runCatching { json.decodeFromString<T>(it) }.getOrNull() }

    private companion object {
        const val PREFS = "hadithly.widgets"
        const val DAILY = "daily.v2"
        const val CONTINUE = "continue.v2"
        const val LEGACY_CONTINUE = "continue.v1"
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
