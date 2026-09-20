package com.hadithly.app

import android.app.Application
import com.clerk.api.Clerk
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.ConvexRepository
import com.hadithly.app.core.data.GuestDataStore
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.data.CollectionProgressSummary
import com.hadithly.app.core.offline.OfflineStore
import com.hadithly.app.core.data.SavedSafetyPreferences
import com.hadithly.app.core.session.SessionManager
import com.hadithly.app.core.preferences.PreferencesStore
import com.hadithly.app.core.settings.AppSettings
import com.hadithly.app.core.push.DevicePushProfile
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.purchases.PurchaseManager
import com.hadithly.app.core.widgets.WidgetSnapshotStore
import com.hadithly.app.features.widgets.refreshContinueWidgets
import com.hadithly.app.features.widgets.refreshDailyWidgets
import com.google.firebase.FirebaseApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.collect
import com.hadithly.app.core.preferences.toWireMap

/**
 * Process-wide dependency graph. Views observe auth through Clerk flows;
 * personal data follows the Convex auth state, never Clerk's alone.
 */
class HadithlyApplication : Application() {

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    lateinit var settings: AppSettings
        private set
    lateinit var preferences: PreferencesStore
        private set
    lateinit var repository: ConvexRepository
        private set
    lateinit var guestData: GuestDataStore
        private set
    lateinit var library: UserLibraryModel
        private set
    lateinit var savedSafety: SavedSafetyPreferences
        private set
    lateinit var session: SessionManager
        private set
    lateinit var push: PushNotificationManager
        private set
    lateinit var purchases: PurchaseManager
        private set
    lateinit var offline: OfflineStore
        private set
    private var widgetProgressSummaries: Map<String, CollectionProgressSummary> = emptyMap()

    override fun onCreate() {
        super.onCreate()
        sharedInstance = this
        val publishableKey = BuildConfig.CLERK_PUBLISHABLE_KEY
        check(!publishableKey.startsWith("PLACEHOLDER")) {
            "Missing CLERK_PUBLISHABLE_KEY. Copy android/secrets.properties.example to android/secrets.properties."
        }
        Clerk.initialize(context = this, publishableKey = publishableKey)
        if (BuildConfig.FIREBASE_CONFIGURED) FirebaseApp.initializeApp(this)
        purchases = PurchaseManager(this, BuildConfig.REVENUECAT_API_KEY)

        settings = AppSettings(this)
        val sharedPreferences = getSharedPreferences("hadithly", MODE_PRIVATE)
        preferences = PreferencesStore(sharedPreferences)
        savedSafety = SavedSafetyPreferences(sharedPreferences)
        repository = ConvexRepository(this)
        guestData = GuestDataStore(this)
        library = UserLibraryModel(
            repository = repository,
            guestData = guestData,
            scope = appScope,
            isSignedIn = { Clerk.sessionsFlow.value.isNotEmpty() },
        )
        // W2: widgets receive a bounded display snapshot only. The private
        // R1 position stays in the library and is resolved after a generic tap.
        appScope.launch {
            library.progress.collect { rows ->
                val current = preferences.preferences.value
                val entry = rows.filter { it.hadith != null }.maxByOrNull { it.updatedAt }
                val summary = entry?.let { widgetProgressSummaries[it.collectionSlug] }
                val ordinal = entry?.hadith?.hadithNumber?.toDoubleOrNull()
                val total = summary?.totalHadiths
                WidgetSnapshotStore(this@HadithlyApplication).saveContinue(
                    entry,
                    locale = current.uiLocale,
                    translationVisible = current.translationVisible,
                    arabicVisible = current.arabicVisible,
                    progressFraction = if (ordinal != null && total != null && total > 0) (ordinal / total).coerceIn(0.0, 1.0) else null,
                    progressLabel = if (ordinal != null && total != null) "Hadith ${ordinal.toInt()} of ${total.toInt()}" else "Resume reading",
                )
                refreshContinueWidgets(this@HadithlyApplication)
            }
        }
        appScope.launch(Dispatchers.IO) {
            repository.subscribe<List<CollectionProgressSummary>>("library:listCollectionProgressSummaries").collect { summaries ->
                widgetProgressSummaries = summaries.associateBy { it.collectionSlug }
                val current = preferences.preferences.value
                val entry = library.continueReading
                val ordinal = entry?.hadith?.hadithNumber?.toDoubleOrNull()
                val total = entry?.let { widgetProgressSummaries[it.collectionSlug]?.totalHadiths }
                WidgetSnapshotStore(this@HadithlyApplication).saveContinue(entry, current.uiLocale, current.translationVisible, current.arabicVisible,
                    if (ordinal != null && total != null && total > 0) (ordinal / total).coerceIn(0.0, 1.0) else null,
                    if (ordinal != null && total != null) "Hadith ${ordinal.toInt()} of ${total.toInt()}" else "Resume reading")
                refreshContinueWidgets(this@HadithlyApplication)
            }
        }
        push = PushNotificationManager(
            context = this,
            repository = repository,
            scope = appScope,
            isSignedIn = { Clerk.sessionsFlow.value.isNotEmpty() },
            deviceProfile = {
                val current = preferences.preferences.value
                DevicePushProfile(
                    timezoneId = PushNotificationManager.timezoneId(),
                    uiLocale = current.uiLocale,
                    translationLocale = current.translationLocale,
                )
            },
        )
        offline = OfflineStore(
            root = java.io.File(filesDir, "offline"),
            appVersion = BuildConfig.VERSION_NAME,
            manifestProvider = { locale -> repository.getOfflineManifests(locale) },
            ioScope = appScope,
        )
        for ((slug, _) in Collections.all) {
            offline.setAnchorProvider(slug) { offlineAnchors(slug) }
        }
        session = SessionManager(
            scope = appScope,
            settings = settings,
            preferences = preferences,
            repository = repository,
            guestData = guestData,
            library = library,
            push = push,
            purchases = purchases,
        )
        session.start()
        push.start()

        // Explicit preference changes sync to Convex while signed in; while
        // signed out they stay device-local and merge on the next sign-in.
        preferences.onPreferencesChanged = { updated ->
            WidgetSnapshotStore(this).saveContinue(
                library.continueReading,
                locale = updated.uiLocale,
                translationVisible = updated.translationVisible,
                arabicVisible = updated.arabicVisible,
            )
            appScope.launch { refreshContinueWidgets(this@HadithlyApplication) }
            appScope.launch(Dispatchers.IO) {
                val payload = runCatching {
                    repository.getDailyWidgetPayload(
                        updated.translationLocale,
                        updated.arabicVisible,
                        updated.translationVisible,
                    )
                }.getOrNull()
                WidgetSnapshotStore(this@HadithlyApplication).saveDaily(payload)
                refreshDailyWidgets(this@HadithlyApplication)
            }
            if (isSignedIn()) {
                appScope.launch {
                    runCatching { repository.updateReaderPreferences(updated.toWireMap()) }
                    // N1: a locale change must also reach this device's push
                    // row so the next notification uses the new translation.
                    runCatching { push.syncToken() }
                }
            }
        }
    }

    fun isSignedIn(): Boolean = Clerk.sessionsFlow.value.isNotEmpty()

    /**
     * Canonical ids the O2 activation gate must find in a replacement dump
     * before the pointer flips: every Saved hadith (`sunnah_now` is the only
     * provider writing Saved rows today) plus every stored R1 position
     * anchor for the collection.
     */
    private fun offlineAnchors(slug: String): Set<String> {
        if (!::library.isInitialized) return emptySet()
        val anchors = mutableSetOf<String>()
        fun canonicalId(collectionSlug: String, hadithNumber: String?): String? {
            if (collectionSlug != slug || hadithNumber.isNullOrBlank()) return null
            return "sunnah_now:$slug:$hadithNumber"
        }
        for (item in library.savedItems.value) {
            canonicalId(item.hadith?.collectionSlug ?: "", item.hadith?.hadithNumber)?.let { anchors.add(it) }
        }
        for (list in listOf(library.bookmarks.value, library.favorites.value, library.notes.value)) {
            for (entry in list) {
                canonicalId(entry.hadith?.collectionSlug ?: "", entry.hadith?.hadithNumber)?.let { anchors.add(it) }
            }
        }
        for (entry in library.progress.value) {
            if (entry.collectionSlug != slug) continue
            val position = entry.position
            if (position != null) {
                anchors.add("${position.anchor.provider}:$slug:${position.anchor.providerHadithId}")
            } else {
                canonicalId(slug, entry.hadith?.hadithNumber)?.let { anchors.add(it) }
            }
        }
        return anchors
    }

    companion object {
        @Volatile
        private var sharedInstance: HadithlyApplication? = null

        fun instance(): HadithlyApplication =
            sharedInstance ?: error("HadithlyApplication not created yet")
    }
}
