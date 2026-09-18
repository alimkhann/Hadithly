package com.hadithly.app

import android.app.Application
import com.clerk.api.Clerk
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.ConvexRepository
import com.hadithly.app.core.data.GuestDataStore
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.offline.OfflineStore
import com.hadithly.app.core.data.SavedSafetyPreferences
import com.hadithly.app.core.session.SessionManager
import com.hadithly.app.core.preferences.PreferencesStore
import com.hadithly.app.core.settings.AppSettings
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.purchases.PurchaseManager
import com.google.firebase.FirebaseApp
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
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
        push = PushNotificationManager(
            context = this,
            repository = repository,
            scope = appScope,
            isSignedIn = { Clerk.sessionsFlow.value.isNotEmpty() },
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
            if (isSignedIn()) {
                appScope.launch {
                    runCatching { repository.updateReaderPreferences(updated.toWireMap()) }
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
