package com.hadithly.app

import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.signin.SignIn
import com.clerk.api.signin.prepareSecondFactor
import com.clerk.api.signin.attemptSecondFactor
import com.clerk.api.signup.sendEmailCode
import com.clerk.api.signup.verifyCode
import com.clerk.api.auth.types.VerificationType
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ReadingPosition
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class LibrarySyncLiveTest {
    @Serializable private data class Configuration(
        val phase: String, val runId: String, val email: String, val password: String,
        val secondEmail: String, val secondPassword: String,
        val hadithId: String, val collectionName: String, val referenceDisplay: String,
        val volumeId: String, val providerHadithId: String, val expiresAt: Double,
    )

    private suspend fun waitFor(label: String, predicate: suspend () -> Boolean) {
        println("A2 live check: $label")
        try { withTimeout(30_000) { while (!predicate()) delay(100) } }
        catch (_: TimeoutCancellationException) { throw AssertionError("A2 live check timed out: $label") }
    }

    private suspend fun authenticate(email: String, secret: String) {
        check(email.endsWith("+clerk_test@example.com"))
        if (Clerk.session != null) {
            check(Clerk.user?.primaryEmailAddress?.emailAddress == email) { "Refusing to replace another account session" }
            return
        }
        val result = Clerk.auth.signInWithPassword { identifier = email; password = secret }
        check(result is ClerkResult.Success) { "Development test authentication failed; credentials redacted" }
        var signedIn = result.value
        if (signedIn.status == SignIn.Status.NEEDS_SECOND_FACTOR || signedIn.status == SignIn.Status.NEEDS_CLIENT_TRUST) {
            val factor = checkNotNull(signedIn.supportedSecondFactors?.firstOrNull { it.strategy == "email_code" }) { "Test email second factor unavailable" }
            val prepared = signedIn.prepareSecondFactor(emailAddressId = factor.emailAddressId)
            check(prepared is ClerkResult.Success) { "Development email-code preparation failed" }
            val verified = prepared.value.attemptSecondFactor(SignIn.AttemptSecondFactorParams.EmailCode("424242"))
            check(verified is ClerkResult.Success) { "Development email-code verification failed" }
            signedIn = verified.value
        }
        val sessionId = checkNotNull(signedIn.createdSessionId) { "Development sign-in did not complete: ${signedIn.status}" }
        check(Clerk.auth.setActive(sessionId) is ClerkResult.Success) { "Development activation failed" }
        waitFor("Expected test account") { Clerk.user?.primaryEmailAddress?.emailAddress == email }
    }

    private suspend fun activate(app: HadithlyApplication) {
        app.repository.convex.loginFromCache()
        withTimeout(20_000) { app.repository.authState.first { app.repository.isAuthenticated } }
        app.session.completeSignIn()
        waitFor("Production library ready") { app.librarySync.owner.value != null && app.library.loadState.value == com.hadithly.app.core.data.UserLibraryModel.LoadState.Ready }
    }

    private suspend fun createSecondAccount(config: Configuration) {
        val created = Clerk.auth.signUp {
            email = config.secondEmail; password = config.secondPassword
            username = config.secondEmail.substringBefore('+')
        }
        check(created is ClerkResult.Success) { "Second development test account creation failed" }
        var signUp = created.value
        if (signUp.createdSessionId == null) {
            val prepared = signUp.sendEmailCode()
            check(prepared is ClerkResult.Success) { "Second test account email-code preparation failed" }
            val verified = prepared.value.verifyCode("424242", VerificationType.EMAIL)
            check(verified is ClerkResult.Success) { "Second test account email-code verification failed" }
            signUp = verified.value
        }
        val sessionId = checkNotNull(signUp.createdSessionId) { "Second test account signup incomplete: ${signUp.status}" }
        check(Clerk.auth.setActive(sessionId) is ClerkResult.Success)
        waitFor("Second test account active") { Clerk.user?.primaryEmailAddress?.emailAddress == config.secondEmail }
    }

    private suspend fun settled(app: HadithlyApplication, hadithId: String, content: String) {
        waitFor("Owned server snapshot") {
            val owner = app.librarySync.owner.value ?: return@waitFor false
            val state = app.guestData.syncPartition(owner) ?: return@waitFor false
            state.pending.isEmpty() && state.frozen == null && state.acknowledgement == null &&
                state.savedSnapshot?.items?.any { it.hadithId == hadithId && it.noteContent == content } == true
        }
    }

    @Test fun developmentCrossDeviceLibraryPhase() = runBlocking(Dispatchers.IO) {
        assumeTrue(InstrumentationRegistry.getArguments().getString("a2Live") == "1")
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        val file = File(app.filesDir, "a2-live-config.json")
        assumeTrue(file.exists())
        val config = Json { ignoreUnknownKeys = true }.decodeFromString<Configuration>(file.readText())
        assumeTrue(config.expiresAt > System.currentTimeMillis() / 1000.0 && config.phase.startsWith("android-"))
        assertTrue(java.net.URI(BuildConfig.CONVEX_URL).host in setOf("festive-cobra-664.convex.cloud", "festive-cobra-664.eu-west-1.convex.cloud"))
        assertTrue(BuildConfig.CLERK_PUBLISHABLE_KEY.startsWith("pk_test_"))
        val activity = ActivityScenario.launch(MainActivity::class.java)
        try {
            withTimeout(20_000) { Clerk.isInitialized.first { it } }
            authenticate(config.email, config.password); activate(app)
            val model = app.library
            val ref = HadithRef(config.hadithId, "bukhari", config.collectionName, config.volumeId, config.providerHadithId, "", null, config.referenceDisplay)
            if (config.phase == "android-read-write") {
                settled(app, ref.hadithId, "A2 iOS " + config.runId)
                assertTrue(model.isBookmarked(ref.hadithId)); assertTrue(model.isFavorite(ref.hadithId))
                assertNotNull(model.savedItems.value.first { it.hadithId == ref.hadithId }.folderId)
                assertEquals(config.providerHadithId, model.continueReading?.position?.anchor?.providerHadithId)
                val createdAt = model.bookmarks.value.first().createdAt
                withContext(Dispatchers.Main) {
                    assertTrue(model.saveNote(ref, "A2 Android " + config.runId).await())
                    assertTrue(model.toggleBookmark(ref).await())
                    model.restoreBookmark(ref, createdAt)
                }
                waitFor("Bookmark Undo") { model.isBookmarked(ref.hadithId) }
                val folder = model.folders.value.first { it.name == "A2 study " + config.runId }
                withContext(Dispatchers.Main) { model.deleteFolder(folder, "Test folder removed", model.actionScope) }
                waitFor("Folder Undo offered") { model.undo.notice.value != null }
                withContext(Dispatchers.Main) { model.undo.undo() }
                waitFor("Folder restored") { model.folders.value.any { it.name == folder.name } && model.savedItems.value.first { it.hadithId == ref.hadithId }.folderId != null }
                val position = requireNotNull(ReadingPosition.legacy(collectionSlug = "bukhari", providerHadithId = config.providerHadithId, volumeId = config.volumeId, updatedAt = System.currentTimeMillis().toDouble())).copy(normalizedOffset = 0.5)
                withContext(Dispatchers.Main) { model.saveProgress(position, ref) }
                settled(app, ref.hadithId, "A2 Android " + config.runId)
                waitFor("Updated server reading position") {
                    val owner = app.librarySync.owner.value ?: return@waitFor false
                    app.guestData.syncPartition(owner)?.positionsSnapshot?.rows?.firstOrNull()?.position?.normalizedOffset == 0.5
                }
            } else if (config.phase == "android-final" || config.phase == "android-provision-second") {
                settled(app, ref.hadithId, "A2 Android " + config.runId)
                if (config.phase == "android-final") assertFalse(model.isBookmarked(ref.hadithId))
                val oldScope = model.actionScope
                check(Clerk.auth.signOut() is ClerkResult.Success)
                withContext(Dispatchers.Main) { app.session.handleSignOut() }
                if (config.phase == "android-provision-second") createSecondAccount(config)
                else authenticate(config.secondEmail, config.secondPassword)
                activate(app)
                withContext(Dispatchers.Main) { model.assignFolder(ref.hadithId, null, oldScope) }
                delay(500)
                assertTrue(model.savedItems.value.isEmpty())
                val owner = requireNotNull(app.librarySync.owner.value)
                val state = requireNotNull(app.guestData.syncPartition(owner))
                assertTrue(state.pending.isEmpty()); assertNull(state.frozen)
                assertTrue(state.savedSnapshot?.items?.isEmpty() == true)
                check(Clerk.auth.signOut() is ClerkResult.Success)
                withContext(Dispatchers.Main) { app.session.handleSignOut() }
                assertTrue(model.savedItems.value.isEmpty())
            } else error("Unknown opt-in Android phase")
        } finally { activity.close() }
    }
}
