package com.hadithly.app.features.reader

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.platform.app.InstrumentationRegistry
import com.clerk.api.Clerk
import com.clerk.api.network.serialization.ClerkResult
import com.hadithly.app.BuildConfig
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.MainActivity
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import org.junit.Assert.*
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.util.UUID

class EvidenceReviewLiveTest {
    @Serializable private data class Translation(val content: String, val source: String, val citations: List<Citation> = emptyList(), val aiModel: String? = null)
    @Serializable private data class Citation(val url: String)

    @Test fun signedInEvidencePublishesThroughBothReviewsAndMaterializesForReader() = runBlocking {
        assumeTrue(InstrumentationRegistry.getArguments().getString("e3Live") == "1")
        check(BuildConfig.CONVEX_URL.contains("festive-cobra-664"))
        val activity = ActivityScenario.launch(MainActivity::class.java)
        val app = ApplicationProvider.getApplicationContext<HadithlyApplication>()
        withTimeout(20_000) { Clerk.isInitialized.first { it } }
        val ticketFile = File(app.filesDir, "e3-signin-ticket")
        if (Clerk.sessionsFlow.value.isEmpty() && ticketFile.exists()) {
            try {
                val result = Clerk.auth.signInWithTicket(ticketFile.readText().trim())
                check(result is ClerkResult.Success) { "Temporary test sign-in failed" }
                result.value.createdSessionId?.let { sessionId ->
                    check(Clerk.auth.setActive(sessionId) is ClerkResult.Success) { "Temporary test activation failed" }
                }
            } finally { ticketFile.delete() }
        }
        assertTrue("An existing signed-in development session is required", Clerk.sessionsFlow.value.isNotEmpty())
        val repository = app.repository; repository.convex.loginFromCache()
        withTimeout(20_000) { repository.authState.first { repository.isAuthenticated } }
        val phrase = "This is a test text."
        val image = File.createTempFile("e3-native-", ".png", app.cacheDir)
        try {
            val bitmap = Bitmap.createBitmap(900, 180, Bitmap.Config.ARGB_8888)
            val paint = Paint().apply { color = Color.BLACK; textSize = 36f }
            Canvas(bitmap).apply { drawColor(Color.WHITE); drawText(phrase, 30f, 85f, paint) }
            image.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
            val hash = MessageDigest.getInstance("SHA-256").digest(image.readBytes()).joinToString("") { "%02x".format(it) }
            val draft = repository.createEvidenceDraft("local_dump:e3_fixture:9002", "en", phrase, null, null, UUID.randomUUID().toString(), listOf(mapOf("kind" to "file", "clientItemKey" to "e3_native_fixture", "declaredMime" to "image/png", "declaredSize" to image.length().toDouble(), "declaredSha256" to hash, "displayName" to "e3-verification.png")))
            repository.uploadEvidence(draft.submissionId, draft.items.single().itemId, "image/png", image) {}
            repository.finalizeEvidenceDraft(draft.submissionId)
            val final = withTimeout(240_000) { repository.observeEvidenceDraft(draft.submissionId).first { it.status in setOf("approved", "rejected", "review_unavailable", "processing_failed", "infected") } }
            assertEquals("approved", final.status); assertEquals("ready", final.items.single().state); assertTrue(final.citations.isNotEmpty())
            val materialized: Translation? = kotlinx.coroutines.withContext(kotlinx.coroutines.Dispatchers.IO) {
                repository.subscribe<Translation?>("translations:getDefaultForProviderRef", mapOf("provider" to "local_dump", "collectionSlug" to "e3_fixture", "providerHadithId" to "9002", "language" to "en")).first { it != null }
            }
            assertNotNull(materialized); assertEquals(phrase, materialized?.content); assertEquals("community", materialized?.source); assertNull(materialized?.aiModel); assertTrue(materialized?.citations?.isNotEmpty() == true)
        } finally { image.delete(); activity.close() }
    }
}
