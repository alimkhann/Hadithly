package com.hadithly.app.core.data
import com.hadithly.app.BuildConfig
import com.hadithly.app.core.push.DevicePushProfile
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.widgets.DailyWidgetPayload

import android.content.Context
import com.clerk.convex.createClerkConvexClient
import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import dev.convex.android.AuthState
import dev.convex.android.ConvexClientWithAuth
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.firstOrNull
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import kotlin.coroutines.coroutineContext
import java.time.ZoneId

@kotlinx.serialization.Serializable
data class FolderDeletionResult(val name: String, val hadithIds: List<String>, val deletedAt: Double)

/**
 * Single gateway to Convex. The app talks only to Convex; Sunnah.now and
 * Gemini live behind Convex actions with server-side keys.
 *
 * Note on numbers: the client encodes Int/Long as the Convex `$integer`
 * wrapper, which `v.number()` validators reject (same trap as on iOS).
 * Numeric arguments travel as Double.
 */
class ConvexRepository(context: Context) {
    private val appContext = context.applicationContext

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

    suspend fun loadSavedPreview(ref: HadithRef): HadithRef {
        if (ref.arabicText.isNotBlank() && !ref.englishText.isNullOrBlank()) return ref
        val number = ref.hadithNumber ?: error("Saved reference is unavailable")
        val volume = ref.volumeId ?: getCollectionOutline(ref.collectionSlug).volumes.let { volumes ->
            var count = 0.0
            volumes.firstOrNull { volume ->
                count += volume.hadithCount
                (number.substringBefore('.').toDoubleOrNull() ?: Double.MAX_VALUE) <= count
            }?.volumeId
        }
        val hadith = getReaderPage(ref.collectionSlug, volume, 0, number).items
            .firstOrNull { it.providerHadithId == number } ?: error("Saved hadith is unavailable")
        return ref.copy(arabicText = hadith.arabicText, englishText = hadith.englishText)
    }

    suspend fun storedReaderTranslation(hadith: ReaderHadith, language: String): ReaderTranslation? = withContext(Dispatchers.IO) {
        subscribe<StoredReaderTranslation?>("translations:getDefaultForProviderRef", mapOf(
            "provider" to hadith.provider, "collectionSlug" to hadith.collectionSlug,
            "providerHadithId" to hadith.providerHadithId, "language" to language,
        )).firstOrNull()?.readerTranslation()
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

    suspend fun getDailyHadith(translationLocale: String): DailyHadith? =
        withContext(Dispatchers.IO) {
            convex.action<DailyHadith?>(
                "actions/daily:getDailyHadith",
                mapOf(
                    "timezone" to ZoneId.systemDefault().id,
                    "translationLocale" to translationLocale,
                ),
            )
        }

    suspend fun getDailyWidgetPayload(translationLocale: String, arabicVisible: Boolean = true, translationVisible: Boolean = true): DailyWidgetPayload? =
        withContext(Dispatchers.IO) {
            convex.action<DailyWidgetPayload?>(
                "actions/daily:getDailyWidgetPayload",
                mapOf(
                    "timezone" to ZoneId.systemDefault().id,
                    "translationLocale" to translationLocale,
                    "arabicVisible" to arabicVisible,
                    "translationVisible" to translationVisible,
                ),
            )
        }

    /**
     * R6 reader-menu search over cached provider English text only (no AI,
     * no generation). The backend owns the 1..25 clamp and returns [] for
     * blank text; this wrapper short-circuits blank input too so no
     * subscription opens, runs on Dispatchers.IO, and names its return
     * type explicitly (reified-call rule).
     */
    /**
     * O2: latest base manifests for every collection plus the packs for one
     * translation locale. Identity-free server side; one call drives the
     * storage screen without N+1 queries.
     */
    suspend fun getOfflineManifests(
        translationLocale: String?,
    ): com.hadithly.app.core.offline.OfflineManifestsResponse =
        withContext(Dispatchers.IO) {
            val args = mutableMapOf<String, Any?>()
            if (!translationLocale.isNullOrBlank()) args["translationLocale"] = translationLocale
            subscribe<com.hadithly.app.core.offline.OfflineManifestsResponse>(
                "offlineDumps:getOfflineManifests",
                args,
            ).firstOrNull() ?: com.hadithly.app.core.offline.OfflineManifestsResponse()
        }

    suspend fun searchEnglish(
        text: String,
        collectionSlug: String? = null,
        limit: Int = 10,
    ): List<EnglishSearchResult> {
        if (text.isBlank()) return emptyList()
        val args = mutableMapOf<String, Any?>(
            "text" to text,
            "limit" to limit.toDouble(),
        )
        if (!collectionSlug.isNullOrBlank()) args["collectionSlug"] = collectionSlug
        return withContext(Dispatchers.IO) {
            subscribe<List<EnglishSearchResult>>("hadiths:searchEnglish", args).firstOrNull()
                ?: emptyList()
        }
    }

    suspend fun createEvidenceDraft(
        hadithInternalId: String,
        language: String,
        proposedContent: String,
        replacesTranslationId: String?,
        legacySubmissionId: String?,
        draftKey: String,
        items: List<Map<String, Any?>>,
    ): EvidenceDraftView {
        val args = mutableMapOf<String, Any?>(
            "hadithInternalId" to hadithInternalId,
            "language" to language,
            "proposedContent" to proposedContent,
            "draftKey" to draftKey,
            "items" to items,
        )
        if (replacesTranslationId != null) args["replacesTranslationId"] = replacesTranslationId
        if (legacySubmissionId != null) args["legacySubmissionId"] = legacySubmissionId
        return withContext(Dispatchers.IO) {
            convex.mutation<EvidenceDraftView>("evidence:createEvidenceDraft", args)
        }
    }

    suspend fun getOwnEvidenceDraft(submissionId: String): EvidenceDraftView? = withContext(Dispatchers.IO) {
        subscribe<EvidenceDraftView>("evidence:getOwnEvidenceDraft", mapOf("submissionId" to submissionId)).firstOrNull()
    }

    fun observeEvidenceDraft(submissionId: String): Flow<EvidenceDraftView> =
        subscribe<EvidenceDraftView>("evidence:getOwnEvidenceDraft", mapOf("submissionId" to submissionId)).flowOn(Dispatchers.IO)

    suspend fun retryEvidenceProcessing(submissionId: String, itemId: String) = withContext(Dispatchers.IO) {
        convex.mutation<Boolean>("evidenceProcessing:retryOwnEvidenceProcessing", mapOf("submissionId" to submissionId, "itemId" to itemId))
    }

    suspend fun getOwnLegacyProposal(hadithInternalId: String, language: String): LegacyEvidenceProposal? = withContext(Dispatchers.IO) {
        subscribe<LegacyEvidenceProposal?>("evidence:getOwnLegacyProposal", mapOf("hadithInternalId" to hadithInternalId, "language" to language)).firstOrNull()
    }

    suspend fun replaceEvidenceSlot(submissionId: String, itemId: String, descriptor: Map<String, Any?>) = withContext(Dispatchers.IO) {
        convex.mutation<Boolean>("evidence:replaceEvidenceSlot", mapOf("submissionId" to submissionId, "itemId" to itemId, "descriptor" to descriptor))
    }

    suspend fun finalizeEvidenceDraft(submissionId: String): EvidenceSubmitResult = withContext(Dispatchers.IO) {
        convex.mutation<EvidenceSubmitResult>("evidence:finalizeEvidenceDraft", mapOf("submissionId" to submissionId, "contributionConsentVersion" to "e3-contribution-v1"))
    }

    suspend fun deleteEvidenceDraft(submissionId: String) = withContext(Dispatchers.IO) {
        convex.mutation<Boolean>("evidence:deleteEvidenceDraft", mapOf("submissionId" to submissionId))
    }

    suspend fun uploadEvidence(submissionId: String, itemId: String, mime: String, file: File, onProgress: (Double) -> Unit) = withContext(Dispatchers.IO) {
        require(EvidenceClientPolicy.acceptsFileSize(file.length())) { "Each evidence file must be 10 MB or smaller." }
        val token = when (val result = Clerk.auth.getToken()) {
            is ClerkResult.Success -> result.value
            is ClerkResult.Failure -> error("Sign in again to upload evidence.")
        }
        val cloud = BuildConfig.CONVEX_URL
        require(cloud.endsWith(".convex.cloud")) { "Upload endpoint is unavailable." }
        val endpoint = cloud.removeSuffix(".convex.cloud") + ".convex.site/evidence/upload"
        val connection = (URL(endpoint).openConnection() as HttpURLConnection).apply {
            requestMethod = "POST"
            doOutput = true
            connectTimeout = 15_000
            readTimeout = 60_000
            setFixedLengthStreamingMode(file.length())
            setRequestProperty("Authorization", "Bearer $token")
            setRequestProperty("Content-Type", mime)
            setRequestProperty("X-Evidence-Submission-Id", submissionId)
            setRequestProperty("X-Evidence-Item-Id", itemId)
        }
        try {
            file.inputStream().use { input ->
                connection.outputStream.use { output ->
                    val buffer = ByteArray(64 * 1024)
                    var sent = 0L
                    while (true) {
                        coroutineContext.ensureActive()
                        val count = input.read(buffer)
                        if (count < 0) break
                        output.write(buffer, 0, count)
                        sent += count
                        withContext(Dispatchers.Main) { onProgress(sent.toDouble() / file.length().toDouble()) }
                    }
                }
            }
            if (connection.responseCode != 200) error("Evidence upload failed (HTTP ${connection.responseCode}).")
        } finally {
            connection.disconnect()
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

    /** S1 subscription + quota status from the caller's own user row. */
    suspend fun getSubscriptionStatus(): SubscriptionStatusResult? =
        withContext(Dispatchers.IO) {
            subscribe<SubscriptionStatusResult>("users:getCurrentUser").firstOrNull()
        }

    /**
     * S1 portable export. Identity-scoped server side: contains only the
     * caller's own data. Callers show an explicit confirm dialog first; a
     * signed-out or expired session must sign in again (reauthentication).
     */
    suspend fun exportUserData(): ExportPayload? =
        withContext(Dispatchers.IO) {
            subscribe<ExportPayload>("users:exportCurrentUserData").firstOrNull()
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
                val position = it.readingPosition
                if (position != null) {
                    mapOf<String, Any?>("position" to position.toWireMap())
                } else {
                    mapOf<String, Any?>(
                        "collectionSlug" to it.collectionSlug,
                        "hadithId" to it.hadithId,
                        "updatedAt" to it.updatedAt,
                    )
                }
            },
            "savedFolders" to payload.savedFolders.map {
                mapOf<String, Any?>("localId" to it.localId, "name" to it.name, "createdAt" to it.createdAt)
            },
            "savedItems" to payload.savedItems.map {
                mapOf<String, Any?>(
                    "hadithId" to it.hadithId,
                    "bookmarkCreatedAt" to it.bookmarkCreatedAt,
                    "favoriteCreatedAt" to it.favoriteCreatedAt,
                    "noteContent" to it.noteContent,
                    "noteCreatedAt" to it.noteCreatedAt,
                    "noteUpdatedAt" to it.noteUpdatedAt,
                    "folderLocalId" to it.folderLocalId,
                    "createdAt" to it.createdAt,
                    "updatedAt" to it.updatedAt,
                ).filterValues { value -> value != null }
            },
        )
        return withContext(Dispatchers.IO) {
            convex.mutation<GuestMergeResult>("guestMerge:mergeGuestData", args)
        }
    }

    // Personal data (signed in)

    suspend fun toggleBookmark(hadithId: String) =
        mutation("library:toggleSavedBookmark", mapOf("hadithId" to hadithId))

    suspend fun toggleFavorite(hadithId: String) =
        mutation("library:toggleSavedFavorite", mapOf("hadithId" to hadithId))

    suspend fun upsertNote(hadithId: String, content: String) =
        mutation("library:upsertSavedNote", mapOf("hadithId" to hadithId, "content" to content))

    suspend fun deleteNote(hadithId: String) =
        mutation("library:deleteSavedNote", mapOf("hadithId" to hadithId))

    suspend fun restoreSavedFacet(hadithId: String, facet: String, createdAt: Double, content: String? = null, updatedAt: Double? = null) {
        val args = mutableMapOf<String, Any?>("hadithId" to hadithId, "facet" to facet, "createdAt" to createdAt)
        if (content != null) args["content"] = content
        if (updatedAt != null) args["updatedAt"] = updatedAt
        mutation("library:restoreSavedFacet", args)
    }

    suspend fun createSavedFolder(name: String) =
        mutation("library:createSavedFolder", mapOf("name" to name))

    suspend fun assignSavedFolder(hadithId: String, folderId: String?) =
        mutation("library:assignSavedFolder", mapOf("hadithId" to hadithId, "folderId" to folderId))

    suspend fun deleteSavedFolder(folderId: String): FolderDeletionResult =
        withContext(Dispatchers.IO) { convex.mutation<FolderDeletionResult>("library:deleteSavedFolder", mapOf("folderId" to folderId)) }

    suspend fun restoreSavedFolder(name: String, hadithIds: List<String>, deletedAt: Double) =
        mutation("library:restoreSavedFolder", mapOf("name" to name, "hadithIds" to hadithIds, "deletedAt" to deletedAt))

    suspend fun saveReadingProgress(position: ReadingPosition) =
        mutation(
            "library:saveReadingProgress",
            mapOf("position" to position.toWireMap()),
        )

    // Notifications

    suspend fun savePushToken(token: String, profile: DevicePushProfile) =
        mutation(
            "library:savePushToken",
            mapOf(
                "token" to token,
                "platform" to "android",
                "timezone" to profile.timezoneId,
                "uiLocale" to profile.uiLocale,
                "translationLocale" to profile.translationLocale,
                "tzOffsetMinutes" to PushNotificationManager.timezoneOffsetMinutes(),
            ),
        )

    suspend fun setDailyNotification(enabled: Boolean, dailyTime: String, profile: DevicePushProfile) =
        withContext(Dispatchers.IO) {
            convex.mutation<Double>(
                "library:setDailyNotification",
                mapOf(
                    "enabled" to enabled,
                    "dailyTime" to dailyTime,
                    "timezone" to profile.timezoneId,
                    "uiLocale" to profile.uiLocale,
                    "translationLocale" to profile.translationLocale,
                    "tzOffsetMinutes" to PushNotificationManager.timezoneOffsetMinutes(),
                ),
            )
        }
}
