package com.hadithly.app.features.reader

import androidx.test.core.app.ApplicationProvider
import androidx.test.core.app.ActivityScenario
import androidx.test.platform.app.InstrumentationRegistry
import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import com.hadithly.app.BuildConfig
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.MainActivity
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.ReaderDefaultTranslation
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File

class TranslationQ1LiveTest {
    @Serializable data class Target(val canonicalId: String, val language: String)
    @Serializable data class Allowance(val used: Double, val remaining: Double)
    @Test fun signedOutCacheReadNeedsNoGenerationOrQuota() = runBlocking(Dispatchers.IO) {
        assumeTrue(InstrumentationRegistry.getArguments().getString("q1GuestLive") == "1")
        val activity = ActivityScenario.launch(MainActivity::class.java)
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        try {
            withTimeout(20_000) { Clerk.isInitialized.first { it } }
            assertTrue(Clerk.sessionsFlow.value.isEmpty())
            val target = Json.decodeFromString<Target>(File(app.filesDir, "q1-native-target.json").readText())
            val rows = withTimeout(20_000) { app.repository.subscribe<List<ReaderDefaultTranslation>>("translations:getReaderDefaults",
                mapOf("hadithInternalIds" to listOf(target.canonicalId), "language" to target.language)).first() }
            assertTrue(rows.first().translation?.content?.isNotBlank() == true)
            val other = app.repository.subscribe<List<ReaderDefaultTranslation>>("translations:getReaderDefaults",
                mapOf("hadithInternalIds" to listOf(target.canonicalId), "language" to "ur")).first()
            assertNull(other.first().translation)
            val denied = runCatching { app.repository.convex.action<ReaderTranslation>("actions/ai:translateHadith",
                mapOf("hadithInternalId" to target.canonicalId, "targetLanguage" to target.language)) }
            assertTrue(denied.isFailure)
        } finally { activity.close() }
    }

    @Test fun explicitAuthenticatedGenerationAndCacheReuse() = runBlocking(Dispatchers.IO) {
        assumeTrue(InstrumentationRegistry.getArguments().getString("q1Live") == "1")
        assertTrue(BuildConfig.CONVEX_URL.contains("festive-cobra-664"))
        val activity = ActivityScenario.launch(MainActivity::class.java)
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        try {
            withTimeout(20_000) { Clerk.isInitialized.first { it } }
            val ticketFile = File(app.filesDir, "q1-signin-ticket")
            if (Clerk.sessionsFlow.value.isEmpty() && ticketFile.exists()) {
                try {
                    val result = Clerk.auth.signInWithTicket(ticketFile.readText().trim())
                    check(result is ClerkResult.Success) { "Temporary development sign-in failed" }
                    result.value.createdSessionId?.let { check(Clerk.auth.setActive(it) is ClerkResult.Success) { "Temporary activation failed" } }
                } finally { ticketFile.delete() }
            }
            assertTrue("Existing signed-in development session required", Clerk.sessionsFlow.value.isNotEmpty())
            val repository = app.repository
            repository.convex.loginFromCache()
            withTimeout(20_000) { repository.authState.first { repository.isAuthenticated } }
            repository.convex.mutation<String>("users:ensureCurrentUser", emptyMap())
            val target = Json.decodeFromString<Target>(File(app.filesDir, "q1-native-target.json").readText())
            val before = repository.subscribe<Allowance>("quotas:getTranslationAllowance").first()
            val args = mapOf("hadithInternalId" to target.canonicalId, "targetLanguage" to target.language)
            val rejected = runCatching { repository.convex.action<ReaderTranslation>("actions/ai:translateHadith", args) }
            assertTrue(rejected.isFailure)
            assertTrue(rejected.exceptionOrNull().toString().contains("AI_INTEGRITY_REQUIRED"))
            val generated = repository.translateHadith(target.canonicalId, target.language)
            assertFalse(generated.cached); assertFalse(generated.groundingUsed); assertTrue(generated.translation.isNotBlank())
            val reused = repository.convex.action<ReaderTranslation>("actions/ai:translateHadith", args)
            assertTrue(reused.cached); assertEquals(generated.translationId, reused.translationId)
            val after = repository.subscribe<Allowance>("quotas:getTranslationAllowance").first()
            assertEquals(before.used + 1, after.used, 0.0)
        } finally { activity.close() }
    }
}
