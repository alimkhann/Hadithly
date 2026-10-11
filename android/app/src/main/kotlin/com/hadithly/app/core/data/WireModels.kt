package com.hadithly.app.core.data

import com.hadithly.app.core.preferences.ReaderPreferences
import kotlinx.serialization.Serializable

@Serializable
data class AuthenticityClaim(
    val kind: String,
    val normalizedGrade: String? = null,
    val claimScope: String,
    val sourceLabel: String,
    val sourceName: String,
    val sourceUrl: String,
    val verificationMethod: String,
) {
    val displayLabel: String
        get() {
            val grade = normalizedGrade?.replaceFirstChar { it.uppercase() }
            return when {
                claimScope == "hadith" && grade != null -> "$grade hadith · $sourceName"
                claimScope == "collection" && grade != null -> "$grade collection scope · $sourceName"
                else -> "Authenticity not verified · $sourceName"
            }
        }
}

/**
 * Wire types for the reader, decoded straight from Convex action results.
 * Mirrors ios/Hadithly/Features/Reader/ReaderModels.swift.
 */
@Serializable
data class ReaderHadith(
    val _id: String,
    val provider: String,
    val canonicalId: String,
    val providerHadithId: String,
    val collectionSlug: String,
    val volumeId: String? = null,
    val chapterId: String? = null,
    val arabicText: String,
    val englishText: String? = null,
    val narrator: String? = null,
    // R6 round 3: Arabic narrator line from the provider's Arabic language
    // map. Optional so rows cached before this field existed keep decoding;
    // a missing value stays hidden in Arabic-only mode.
    val narratorAr: String? = null,
    val referenceDisplay: String,
    val collectionName: String,
    val chapterName: String? = null,
    val authenticity: AuthenticityClaim,
) {
    /** Internal id used by actions/ai:translateHadith. */
    val internalId: String
        get() = canonicalId
}

@Serializable
data class ReaderPageResult(
    val items: List<ReaderHadith> = emptyList(),
    // Convex numbers travel as floats on the wire (7.0), so numeric fields
    // must be Double or decoding fails.
    val page: Double = 0.0,
    val pageSize: Double = 0.0,
    val totalPages: Double = 0.0,
    val hasMore: Boolean = false,
    val contentVersion: String = "legacy",
    val paginationVersion: Double = 1.0,
    val pageKey: String = "legacy",
) {
    /** Skipped-by-jump pages start as page == 0 sentinels and load on demand. */
    val isPlaceholder: Boolean get() = page == 0.0
    val pageNumber: Int get() = page.toInt()
    val totalPagesInt: Int get() = totalPages.toInt()
}

@Serializable
data class OutlineChapter(
    val chapterId: String? = null,
    val title: String,
    val arabicTitle: String? = null,
    val hadithCount: Double = 0.0,
    val firstProviderHadithId: String,
)

@Serializable
data class OutlineVolume(
    val volumeId: String,
    val title: String,
    val firstChapterTitle: String? = null,
    val hadithCount: Double = 0.0,
    // R5: source-provided chapters. Optional so outlines cached before R5
    // still decode; fresh outlines always include it. Never synthesized.
    val chapters: List<OutlineChapter> = emptyList(),
)

@Serializable
data class CollectionOutlineResult(
    val volumes: List<OutlineVolume> = emptyList(),
)

@Serializable
data class CollectionProgressSummary(
    val collectionSlug: String,
    val state: String,
    val totalHadiths: Double? = null,
    val readOrdinal: Double? = null,
)

@Serializable
data class ReaderCitation(
    val url: String,
    val title: String? = null,
    val domain: String? = null,
)

@Serializable
data class ReaderTranslation(
    val translationId: String,
    val translation: String,
    val confidence: Double? = null,
    val riskFlags: List<String> = emptyList(),
    val glossaryNotes: List<String> = emptyList(),
    val source: String,
    val sourceLabel: String,
    val aiModel: String? = null,
    val groundingUsed: Boolean = false,
    val citations: List<ReaderCitation> = emptyList(),
    val sourceReferenceUrl: String? = null,
    val cached: Boolean = false,
)

@Serializable
data class StoredReaderTranslation(
    val _id: String, val content: String, val source: String, val sourceLabel: String,
    val aiModel: String? = null, val confidence: Double? = null, val riskFlags: List<String> = emptyList(),
    val groundingUsed: Boolean = false, val citations: List<ReaderCitation> = emptyList(), val sourceReferenceUrl: String? = null,
) {
    fun readerTranslation() = ReaderTranslation(_id, content, confidence, riskFlags, emptyList(), source, sourceLabel, aiModel, groundingUsed, citations, sourceReferenceUrl, true)
}

@Serializable
data class DailyTranslation(
    val text: String,
    val language: String,
    val source: String,
    val sourceLabel: String,
    val isAI: Boolean,
)

@Serializable
data class DailyHadith(
    val _id: String,
    val provider: String,
    val canonicalId: String,
    val providerHadithId: String,
    val collectionSlug: String,
    val collectionName: String,
    val volumeId: String? = null,
    val arabicText: String,
    val englishText: String? = null,
    val translation: DailyTranslation? = null,
    val referenceDisplay: String,
    val authenticity: AuthenticityClaim,
)

@Serializable
data class TranslationAIReview(
    val model: String,
    val score: Double,
    val riskFlags: List<String> = emptyList(),
    val missingMeaning: List<String>? = null,
    val addedMeaning: List<String>? = null,
    val glossaryIssues: List<String>? = null,
    val recommendation: String,
) {
    val reviewNotes: List<String>
        get() = riskFlags +
            (missingMeaning ?: emptyList()).map { "Missing meaning: $it" } +
            (addedMeaning ?: emptyList()).map { "Added meaning: $it" } +
            (glossaryIssues ?: emptyList()).map { "Terminology: $it" }
}

@Serializable
data class TranslationSubmissionResult(
    val submissionId: String,
    val aiReview: TranslationAIReview,
    val status: String,
)

@Serializable
data class TranslationReportResult(val ok: Boolean)

@Serializable
data class AdminSubmissionHadith(
    val referenceDisplay: String,
    val arabicText: String,
    val englishText: String? = null,
)

@Serializable
data class AdminSubmissionContributor(
    val displayName: String? = null,
    val email: String? = null,
)

@Serializable
data class AdminTranslationSubmission(
    val _id: String,
    val language: String,
    val proposedContent: String,
    val aiReview: TranslationAIReview,
    val status: String,
    val createdAt: Double,
    val hadith: AdminSubmissionHadith? = null,
    val contributor: AdminSubmissionContributor? = null,
)

/**
 * Maps Convex action failures to reader-facing states. The backend reports
 * the quota wall with the literal message "AI_GENERATION_QUOTA_EXCEEDED"
 * (convex/quotas.ts) and guests fail requireIdentity with "Unauthenticated".
 */
sealed interface TranslationFailure {
    data object QuotaExceeded : TranslationFailure
    data object RequiresSignIn : TranslationFailure
    data class Failed(val message: String) : TranslationFailure

    val retryAt: Double?
        get() = (this as? Failed)?.message?.let { message ->
            Regex("""retryAt["\\\s]*[:=]\s*([0-9]+)""").find(message)?.groupValues?.get(1)?.toDoubleOrNull()
        }

    companion object {
        fun of(message: String): TranslationFailure = when {
            message.contains("AI_GENERATION_QUOTA_EXCEEDED") -> QuotaExceeded
            message.lowercase().contains("unauthenticated") -> RequiresSignIn
            else -> Failed(message)
        }
    }
}

/**
 * The seven collections, in reading order. Mirrors
 * DEFAULT_COLLECTION_ORDER in backend/convex/lib/sunnahNow.ts.
 */
object Collections {
    val all: List<Pair<String, String>> = listOf(
        "bukhari" to "Sahih al-Bukhari",
        "muslim" to "Sahih Muslim",
        "sunan-nasai" to "Sunan an-Nasa'i",
        "abu-dawood" to "Abu Dawood",
        "tirmidhi" to "Jami` at-Tirmidhi",
        "ibn-majah" to "Ibn Majah",
        "mishkat-al-masabih" to "Mishkat al-Masabih",
    )

    /** Reverse lookup used by guest-side saved items, which only store the name. */
    fun slugForName(name: String?): String =
        all.firstOrNull { name != null && it.second.equals(name, ignoreCase = true) }?.first
            ?: "bukhari"
}

/** Languages the app actively supports for translations. Mirrors iOS SupportedLanguages. */
object SupportedLanguages {
    val all: List<Pair<String, String>> = listOf(
        "en" to "English",
        "kk" to "Қазақша",
        "ru" to "Русский",
        "uz" to "Oʻzbekcha",
        "tr" to "Türkçe",
        "id" to "Bahasa Indonesia",
        "ur" to "اردو",
        "ar" to "العربية",
    )
}

/** One-shot reader preference adoption payload (F2). */
@Serializable
data class UserPreferencesResult(
    val readerPreferences: ReaderPreferences? = null,
)

/** Subscription + quota fields from the `users:getCurrentUser` row (S1). */
@Serializable
data class SubscriptionStatusResult(
    val subscriptionTier: String? = null,
    val entitlementExpiresAt: Double? = null,
)

/**
 * Portable export from `users:exportCurrentUserData` (S1). Only the caller's
 * own data: account summary, preferences, Saved material joined to canonical
 * hadith identity, reading progress, legacy rows, and own contributions.
 * Tolerant defaults so future fields cannot break decoding.
 */
@Serializable
data class ExportHadithRef(
    val hadithId: String? = null,
    val canonicalId: String? = null,
    val collectionSlug: String? = null,
    val providerHadithId: String? = null,
    val referenceDisplay: String? = null,
    val missing: Boolean? = null,
)

@Serializable
data class ExportPayload(
    val generatedAt: Double = 0.0,
    val account: ExportAccount? = null,
    val savedFolders: List<ExportFolder> = emptyList(),
    val savedItems: List<ExportItem> = emptyList(),
    val readingProgress: List<ExportProgress> = emptyList(),
    val submissions: List<ExportSubmission> = emptyList(),
)

@Serializable
data class ExportAccount(
    val email: String? = null,
    val displayName: String? = null,
    val subscriptionTier: String? = null,
    val createdAt: Double? = null,
)

@Serializable
data class ExportFolder(
    val name: String? = null,
    val createdAt: Double? = null,
    val updatedAt: Double? = null,
)

@Serializable
data class ExportItem(
    val hadith: ExportHadithRef? = null,
    val bookmarkCreatedAt: Double? = null,
    val favoriteCreatedAt: Double? = null,
    val noteContent: String? = null,
    val noteUpdatedAt: Double? = null,
    val folderName: String? = null,
    val updatedAt: Double? = null,
)

@Serializable
data class ExportProgress(
    val collectionSlug: String? = null,
    val hadith: ExportHadithRef? = null,
    val updatedAt: Double? = null,
)

@Serializable
data class ExportSubmission(
    val language: String? = null,
    val proposedContent: String? = null,
    val status: String? = null,
    val createdAt: Double? = null,
)

/**
 * One R6 reader-menu English search hit (`hadiths:searchEnglish`, cached
 * provider English only). Defaults keep decoding tolerant; blank queries
 * never reach the backend (the repository returns [] first).
 */
@Serializable
data class EnglishSearchResult(
    val hadithId: String = "",
    val canonicalId: String = "",
    val collectionSlug: String = "",
    val providerHadithId: String = "",
    val referenceDisplay: String = "",
    val snippet: String = "",
)
