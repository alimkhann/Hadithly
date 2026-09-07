package com.hadithly.app.core.data

import com.hadithly.app.BuildConfig
import android.content.Context
import com.clerk.convex.createClerkConvexClient
import dev.convex.android.AuthState
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import java.time.ZoneId

/**
 * Single gateway to Convex. The app talks only to Convex; Sunnah.now and
 * Gemini live behind Convex actions with server-side keys.
 *
 * Note on numbers: the client encodes Int/Long as the Convex `$integer`
 * wrapper, which `v.number()` validators reject (same trap as on iOS).
 * Numeric arguments travel as Double.
 */
class ConvexRepository(context: Context) {

    val convex: ConvexClientWithAuth<String> = createClerkConvexClient(
        deploymentUrl = BuildConfig.CONVEX_URL,
        context = context.applicationContext,
    )

    val authState: StateFlow<AuthState<String>> = convex.authState

    val isAuthenticated: Boolean
        get() = convex.authState.value is AuthState.Authenticated

    /** Observes a query with args, re-emitting on server updates. */
    inline fun <reified T> subscribe(name: String, args: Map<String, Any?> = emptyMap()): Flow<T> =
        convex.subscribe<T>(name, args).map { it.getOrThrow() }

    suspend fun mutation(name: String, args: Map<String, Any?> = emptyMap()) {
        withContext(Dispatchers.IO) { convex.mutation(name, args) }
    }

    // Reading

    suspend fun getCollectionOutline(collectionSlug: String): CollectionOutlineResult =
        withContext(Dispatchers.IO) {
            convex.action<CollectionOutlineResult>(
                "actions/hadithData:getCollectionOutline",
                mapOf("collectionSlug" to collectionSlug),
            )
        }

    suspend fun getReaderPage(
        collectionSlug: String,
        volumeId: String?,
        page: Int,
        targetHadithNumber: String? = null,
    ): ReaderPageResult {
        val args = mutableMapOf<String, Any?>(
            "collectionSlug" to collectionSlug,
            "page" to (page + 1).toDouble(),
        )
        if (!volumeId.isNullOrBlank()) args["volumeId"] = volumeId
        if (targetHadithNumber != null) args["targetHadithNumber"] = targetHadithNumber
        return withContext(Dispatchers.IO) {
            convex.action<ReaderPageResult>("actions/hadithData:getReaderPage", args)
        }
    }

    suspend fun translateHadith(hadithInternalId: String, targetLanguage: String): ReaderTranslation =
        withContext(Dispatchers.IO) {
            convex.action<ReaderTranslation>(
                "actions/ai:translateHadith",
                mapOf(
                    "hadithInternalId" to hadithInternalId,
                    "targetLanguage" to targetLanguage,
                ),
            )
        }

    suspend fun getDailyHadith(): DailyHadith? =
        withContext(Dispatchers.IO) {
            convex.action<DailyHadith?>(
                "actions/daily:getDailyHadith",
                mapOf("timezone" to ZoneId.systemDefault().id),
            )
        }

    suspend fun submitTranslation(
        hadithInternalId: String,
        language: String,
        proposedContent: String,
        replacesTranslationId: String?,
    ): TranslationSubmissionResult {
        val args = mutableMapOf<String, Any?>(
            "hadithInternalId" to hadithInternalId,
            "language" to language,
            "proposedContent" to proposedContent,
        )
        if (replacesTranslationId != null) args["replacesTranslationId"] = replacesTranslationId
        return withContext(Dispatchers.IO) {
            convex.action<TranslationSubmissionResult>("actions/ai:submitTranslation", args)
        }
    }

    suspend fun reportTranslation(translationId: String, reason: String): TranslationReportResult =
        withContext(Dispatchers.IO) {
            convex.action<TranslationReportResult>(
                "actions/ai:reportTranslation",
                mapOf("translationId" to translationId, "reason" to reason),
            )
        }

    // Account + guest merge

    suspend fun ensureCurrentUser(preferredLanguage: String, readerPreferences: Map<String, Any?>? = null) {
        val args = mutableMapOf<String, Any?>("preferredLanguage" to preferredLanguage)
        if (readerPreferences != null) args["readerPreferences"] = readerPreferences
        withContext(Dispatchers.IO) {
            convex.mutation<String>("users:ensureCurrentUser", args)
        }
    }

    suspend fun updateReaderPreferences(prefs: Map<String, Any?>) =
        mutation("users:updateReaderPreferences", mapOf("readerPreferences" to prefs))

    /** One-shot read so the device can adopt the authoritative stored state. */
    suspend fun getCurrentUserPreferences(): UserPreferencesResult? =
        withContext(Dispatchers.IO) {
            subscribe<UserPreferencesResult>("users:getCurrentUserPreferences").firstOrNull()
        }

    suspend fun deleteCurrentUser() {
        withContext(Dispatchers.IO) {
            convex.mutation<Boolean>("users:deleteCurrentUser", emptyMap())
        }
    }

    suspend fun mergeGuestData(payload: GuestMergePayload): GuestMergeResult {
        val args = mapOf<String, Any?>(
            "bookmarks" to payload.bookmarks.map {
                mapOf<String, Any?>("hadithId" to it.hadithId, "createdAt" to it.createdAt)
            },
            "notes" to payload.notes.map {
                mapOf<String, Any?>(
                    "hadithId" to it.hadithId,
                    "content" to it.content,
                    "createdAt" to it.createdAt,
                    "updatedAt" to it.updatedAt,
                )
            },
            "favorites" to payload.favorites.map {
                mapOf<String, Any?>("hadithId" to it.hadithId, "createdAt" to it.createdAt)
            },
            "readingProgress" to payload.readingProgress.map {
                mapOf<String, Any?>(
                    "collectionSlug" to it.collectionSlug,
                    "hadithId" to it.hadithId,
                    "updatedAt" to it.updatedAt,
                )
            },
        )
        return withContext(Dispatchers.IO) {
            convex.mutation<GuestMergeResult>("guestMerge:mergeGuestData", args)
        }
    }

    // Personal data (signed in)

    suspend fun toggleBookmark(hadithId: String) =
        mutation("library:toggleBookmark", mapOf("hadithId" to hadithId))

    suspend fun toggleFavorite(hadithId: String) =
        mutation("library:toggleFavorite", mapOf("hadithId" to hadithId))

    suspend fun upsertNote(hadithId: String, content: String) =
        mutation("library:upsertNote", mapOf("hadithId" to hadithId, "content" to content))

    suspend fun deleteNote(hadithId: String) =
        mutation("library:deleteNote", mapOf("hadithId" to hadithId))

    suspend fun saveReadingProgress(collectionSlug: String, hadithId: String) =
        mutation(
            "library:saveReadingProgress",
            mapOf("collectionSlug" to collectionSlug, "hadithId" to hadithId),
        )

    // Notifications + moderation

    suspend fun savePushToken(token: String, tzOffsetMinutes: Double) =
        mutation(
            "library:savePushToken",
            mapOf(
                "token" to token,
                "platform" to "android",
                "tzOffsetMinutes" to tzOffsetMinutes,
            ),
        )

    suspend fun setDailyNotification(enabled: Boolean, dailyTime: String, tzOffsetMinutes: Double) =
        withContext(Dispatchers.IO) {
            convex.mutation<Double>(
                "library:setDailyNotification",
                mapOf(
                    "enabled" to enabled,
                    "dailyTime" to dailyTime,
                    "tzOffsetMinutes" to tzOffsetMinutes,
                ),
            )
        }

    suspend fun approveSubmission(submissionId: String) =
        mutation("community:approveSubmission", mapOf("submissionId" to submissionId))
}
