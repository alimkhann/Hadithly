package com.hadithly.app.core.session

import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.network.serialization.errorMessage
import com.clerk.api.user.delete
import com.hadithly.app.core.data.ConvexRepository
import com.hadithly.app.core.data.GuestDataStore
import com.hadithly.app.core.data.GuestMergePlanner
import com.hadithly.app.core.data.UserLibraryModel
import com.hadithly.app.core.settings.AppSettings
import com.hadithly.app.core.preferences.PreferencesStore
import com.hadithly.app.core.preferences.toWireMap
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.purchases.PurchaseManager
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import dev.convex.android.AuthState
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.launchIn
import kotlinx.coroutines.flow.onEach
import kotlinx.coroutines.launch

/**
 * Owns the sign-in lifecycle: after a Clerk session becomes active it makes
 * sure the Convex user row exists, merges whatever the guest collected
 * on-device into Convex, and clears the local store. Idempotent — safe to
 * run again. Mirrors iOS AppEnvironment.completeSignIn.
 */
class SessionManager(
    private val scope: CoroutineScope,
    private val settings: AppSettings,
    private val preferences: PreferencesStore,
    private val repository: ConvexRepository,
    private val guestData: GuestDataStore,
    private val library: UserLibraryModel,
    private val push: PushNotificationManager,
    private val purchases: PurchaseManager,
) {

    private val _syncSummary = MutableStateFlow<String?>(null)
    val syncSummary: StateFlow<String?> = _syncSummary

    private val _canModerate = MutableStateFlow(false)
    val canModerate: StateFlow<Boolean> = _canModerate

    private var moderationJob: Job? = null

    private var launchSessionSynced = false
    private var syncInFlight = false

    fun start() {
        // Clerk restores its client asynchronously; gate on isInitialized
        // before reading the session or a restored sign-in is missed.
        scope.launch {
            Clerk.isInitialized.collect { initialized ->
                if (!initialized) return@collect
                if (!launchSessionSynced && isSignedIn()) {
                    launchSessionSynced = true
                    completeSignIn()
                }
            }
        }
        // Personal-data subscriptions follow the Convex session, not Clerk's.
        repository.authState
            .onEach { state ->
                when (state) {
                    is AuthState.Authenticated -> {
                        if (!launchSessionSynced && isSignedIn()) {
                            launchSessionSynced = true
                            completeSignIn()
                        }
                        library.refresh()
                        observeModeration()
                    }
                    else -> if (!isSignedIn()) {
                        library.refresh()
                        stopModeration()
                    }
                }
            }
            .launchIn(scope)
        // Signed-out detection: the session list empties.
        scope.launch {
            var hadSession = false
            Clerk.sessionsFlow.collect { sessions ->
                if (sessions.isNotEmpty()) {
                    hadSession = true
                } else if (hadSession) {
                    hadSession = false
                    handleSignOut()
                }
            }
        }
    }

    private fun isSignedIn(): Boolean = Clerk.sessionsFlow.value.isNotEmpty()

    suspend fun completeSignIn() {
        if (syncInFlight) return
        syncInFlight = true
        try {
            if (!waitForConvexAuthentication()) {
                _syncSummary.value = "Sign-in sync failed: Convex session never activated."
                library.refresh()
                return
            }

            try {
                repository.ensureCurrentUser(
                    settings.preferredLanguage.value,
                    preferences.preferences.value.toWireMap(),
                )
                // Adopt the authoritative stored preferences when another
                // device made the latest explicit change.
                runCatching { repository.getCurrentUserPreferences() }.getOrNull()
                    ?.readerPreferences
                    ?.let { preferences.adoptServer(it) }
            } catch (error: Exception) {
                _syncSummary.value = "Account sync failed: ${error.message}"
                library.refresh()
                return
            }
            Clerk.user?.id?.let(purchases::logIn)
            push.syncToken()

            val snapshot = guestData.snapshots()
            val payload = GuestMergePlanner.makePayload(
                bookmarks = snapshot.bookmarks,
                notes = snapshot.notes,
                favorites = snapshot.favorites,
                progress = snapshot.progress,
            )

            if (payload.isEmpty) {
                _syncSummary.value = "Signed in."
                library.refresh()
                return
            }

            try {
                val result = repository.mergeGuestData(payload)
                guestData.clearAll()
                _syncSummary.value = syncSummaryFor(result)
            } catch (error: Exception) {
                // Local data is deliberately kept so a later sign-in retries.
                _syncSummary.value = "Guest data merge failed: ${error.message}"
            }
            library.refresh()
        } finally {
            syncInFlight = false
        }
    }

    /** Called when the Clerk session ends; the guest store was already cleared. */
    fun handleSignOut() {
        library.refresh()
        stopModeration()
        _syncSummary.value = null
        purchases.logOut()
    }

    /** Delete backend data while authenticated, then delete the Clerk user. */
    suspend fun deleteAccount(): Result<Unit> = runCatching {
        repository.deleteCurrentUser()
        val user = Clerk.user ?: return@runCatching
        when (val result = user.delete()) {
            is ClerkResult.Success -> purchases.logOut()
            is ClerkResult.Failure -> error(result.errorMessage)
        }
    }

    private fun observeModeration() {
        if (moderationJob?.isActive == true) return
        moderationJob = scope.launch(Dispatchers.IO) {
            runCatching {
                repository.subscribe<Boolean>("community:canModerate")
                    .collect { _canModerate.value = it }
            }.onFailure { _canModerate.value = false }
        }
    }

    private fun stopModeration() {
        moderationJob?.cancel()
        moderationJob = null
        _canModerate.value = false
    }

    private fun syncSummaryFor(result: com.hadithly.app.core.data.GuestMergeResult): String {
        var summary =
            "Signed in. Merged ${result.bookmarksMerged.toInt()} bookmarks, " +
                "${result.favoritesMerged.toInt()} favorites, and ${result.notesMerged.toInt()} notes."
        if (result.progressMerged > 0) {
            summary += " Restored ${result.progressMerged} reading positions."
        }
        return summary
    }

    private suspend fun waitForConvexAuthentication(timeoutMs: Long = 15_000): Boolean {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (repository.isAuthenticated) return true
            delay(250)
        }
        return repository.isAuthenticated
    }
}
