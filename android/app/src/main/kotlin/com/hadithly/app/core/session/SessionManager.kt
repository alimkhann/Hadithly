package com.hadithly.app.core.session

import android.content.Context
import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.network.serialization.errorMessage
import com.clerk.api.session.Session
import com.clerk.api.user.delete
import com.hadithly.app.core.data.*
import com.hadithly.app.core.preferences.PreferencesStore
import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.core.preferences.toWireMap
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.purchases.PurchaseManager
import dev.convex.android.AuthState
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine

fun currentLibrarySession(): LibrarySyncSession? {
    if (!Clerk.isInitialized.value) return null
    val session = Clerk.session ?: return null
    if (session.status != Session.SessionStatus.ACTIVE) return null
    val subject = session.user?.id ?: return null
    return LibrarySyncSession(session.id, subject)
}

/** Owns activation for the captured active Clerk session. LibrarySync owns data. */
class SessionManager(
    private val context: Context,
    scope: CoroutineScope,
    private val preferences: PreferencesStore,
    private val repository: ConvexRepository,
    private val guestData: GuestDataStore,
    private val library: UserLibraryModel,
    private val sync: LibrarySync,
    private val push: PushNotificationManager,
    private val purchases: PurchaseManager,
) {
    private val scope = CoroutineScope(scope.coroutineContext + Dispatchers.Main.immediate)
    private val _syncSummary = MutableStateFlow<String?>(null)
    val syncSummary: StateFlow<String?> = _syncSummary
    private var observedSession: LibrarySyncSession? = null
    private var initializedSession: LibrarySyncSession? = null
    private var completingSession: LibrarySyncSession? = null
    private var completing: Deferred<Unit>? = null

    fun start() {
        if (com.hadithly.app.BuildConfig.DEBUG && System.getProperty("hadithly.disableAutomaticLibrarySync") == "true") return
        scope.launch {
            combine(Clerk.sessionFlow, Clerk.isInitialized) { _, _ -> currentLibrarySession() }.collect { current ->
                if (current == observedSession) return@collect
                completing?.cancel(); completing = null
                sync.deactivate(); initializedSession = null; observedSession = current
                library.refresh()
                if (current != null) scope.launch { completeSignIn() } else handleSignOut()
            }
        }
        scope.launch {
            repository.authState.collect { state ->
                library.refresh()
                if (state is AuthState.Authenticated && currentLibrarySession() != null) scope.launch { completeSignIn() }
            }
        }
    }

    suspend fun completeSignIn() = withContext(Dispatchers.Main.immediate) {
        val session = currentLibrarySession() ?: return@withContext
        if (completingSession == session) completing?.let { it.await(); return@withContext }
        completing?.cancel()
        val task = scope.async(start = CoroutineStart.LAZY) { complete(session) }
        completingSession = session; completing = task
        task.start(); task.await()
        if (completing === task) completing = null
    }

    private suspend fun complete(session: LibrarySyncSession) {
        if (!waitForConvexAuthentication(session) || currentLibrarySession() != session) return
        sync.activate(session)
        if (currentLibrarySession() != session || sync.owner.value?.subject != session.subject) return
        if (initializedSession == session) { library.refresh(); return }
        try {
            val captured = sync.captureWriteContext()
            val capability = sync.capability(captured)
            repository.ensureCurrentUser(preferences.preferences.value.translationLocale, preferences.preferences.value.toWireMap(), capability)
            if (currentLibrarySession() != session) return
            repository.getCurrentUserPreferences(capability)?.readerPreferences?.let {
                if (currentLibrarySession() == session) preferences.adoptServer(it)
            }
            if (currentLibrarySession() != session) return
            purchases.logIn(session.subject)
            initializedSession = session
            _syncSummary.value = null
            library.refresh()
            push.syncToken()
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (_: Exception) { if (currentLibrarySession() == session) _syncSummary.value = context.nativeText("Saved items could not load") }
    }

    fun handleSignOut() {
        sync.deactivate()
        (context.applicationContext as com.hadithly.app.HadithlyApplication).analytics.clearPending()
        library.refresh(); _syncSummary.value = null; initializedSession = null
        if (currentLibrarySession() == null) purchases.logOut()
    }

    suspend fun deleteAccount(captured: LibrarySyncSession): Result<Unit> = withContext(Dispatchers.Main.immediate) {
        try {
            if (currentLibrarySession() != captured) throw LibrarySyncFailure.SessionChanged
            val user = Clerk.session?.user ?: throw LibrarySyncFailure.SessionChanged
            if (user.id != captured.subject) throw LibrarySyncFailure.SessionChanged
            val flow = LibraryAccountDeletion(guestData, repository.namespace, ::currentLibrarySession,
                invalidate = {
                    (context.applicationContext as com.hadithly.app.HadithlyApplication).analytics.setSharing(false)
                    sync.deactivate(); library.refresh()
                }, prepare = repository::prepareAccountDeletion, erase = repository::deleteCurrentUser,
                cleanup = { subject -> EvidenceLocalDrafts.clearForAccount(context, subject) },
                deleteIdentity = { expected ->
                    if (currentLibrarySession() != expected) throw LibrarySyncFailure.SessionChanged
                    when (val result = user.delete()) {
                        is ClerkResult.Success -> Unit
                        is ClerkResult.Failure -> error(result.errorMessage)
                    }
                })
            flow.run(captured)
            if (currentLibrarySession() == null) handleSignOut()
            Result.success(Unit)
        } catch (cancelled: CancellationException) { throw cancelled }
        catch (error: Exception) { Result.failure(error) }
    }

    private suspend fun waitForConvexAuthentication(session: LibrarySyncSession, timeoutMs: Long = 15_000): Boolean {
        val deadline = android.os.SystemClock.elapsedRealtime() + timeoutMs
        while (android.os.SystemClock.elapsedRealtime() < deadline && currentLibrarySession() == session) {
            if (repository.isAuthenticated) return true
            repository.convex.loginFromCache()
            delay(250)
        }
        return repository.isAuthenticated && currentLibrarySession() == session
    }
}
