package com.hadithly.app

import android.app.Application
import com.clerk.api.Clerk
import com.hadithly.app.core.data.ConvexRepository
import com.hadithly.app.core.data.GuestDataStore
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.session.SessionManager
import com.hadithly.app.core.settings.AppSettings
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob

/**
 * Process-wide dependency graph. Views observe auth through Clerk flows;
 * personal data follows the Convex auth state, never Clerk's alone.
 */
class HadithlyApplication : Application() {

    val appScope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    lateinit var settings: AppSettings
        private set
    lateinit var repository: ConvexRepository
        private set
    lateinit var guestData: GuestDataStore
        private set
    lateinit var library: UserLibraryModel
        private set
    lateinit var session: SessionManager
        private set

    override fun onCreate() {
        super.onCreate()
        sharedInstance = this
        val publishableKey = BuildConfig.CLERK_PUBLISHABLE_KEY
        check(!publishableKey.startsWith("PLACEHOLDER")) {
            "Missing CLERK_PUBLISHABLE_KEY. Copy android/secrets.properties.example to android/secrets.properties."
        }
        Clerk.initialize(context = this, publishableKey = publishableKey)

        settings = AppSettings(this)
        repository = ConvexRepository(this)
        guestData = GuestDataStore(this)
        library = UserLibraryModel(
            repository = repository,
            guestData = guestData,
            scope = appScope,
            isSignedIn = { Clerk.sessionsFlow.value.isNotEmpty() },
        )
        session = SessionManager(
            scope = appScope,
            settings = settings,
            repository = repository,
            guestData = guestData,
            library = library,
        )
        session.start()
    }

    fun isSignedIn(): Boolean = Clerk.sessionsFlow.value.isNotEmpty()

    companion object {
        @Volatile
        private var sharedInstance: HadithlyApplication? = null

        fun instance(): HadithlyApplication =
            sharedInstance ?: error("HadithlyApplication not created yet")
    }
}
