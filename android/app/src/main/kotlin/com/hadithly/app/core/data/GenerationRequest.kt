package com.hadithly.app.core.data

import android.content.Context
import android.util.Base64
import com.google.android.gms.tasks.Task
import com.google.android.play.core.integrity.IntegrityManagerFactory
import com.google.android.play.core.integrity.StandardIntegrityManager
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import java.security.MessageDigest
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

@Serializable
data class TranslationAllowance(val limit: Double, val remaining: Double, val retryAt: Double? = null)

@Serializable
data class ReaderDefaultTranslation(val hadithInternalId: String, val translation: StoredReaderTranslation? = null)

@Serializable
data class GenerationChallenge(
    val challengeId: String, val payload: String, val keyRegistered: Boolean,
    val allowUnavailable: Boolean, val playProjectNumber: String? = null,
)

/** Proof is requested on demand and is bound to the backend's one-use challenge. */
class GenerationRequest(context: Context) {
    private val manager = IntegrityManagerFactory.createStandard(context.applicationContext)
    private val prepareMutex = Mutex()
    private var provider: StandardIntegrityManager.StandardIntegrityTokenProvider? = null
    private var preparedProject: Long? = null

    suspend fun proof(challenge: GenerationChallenge): Map<String, String> {
        val project = challenge.playProjectNumber?.toLongOrNull()
        if (project == null) {
            check(challenge.allowUnavailable) { "AI_INTEGRITY_REQUIRED" }
            return mapOf("kind" to "unavailable")
        }
        try {
            val tokenProvider = prepareMutex.withLock {
                if (provider == null || preparedProject != project) {
                    provider = withTimeout(60_000) { manager.prepareIntegrityToken(
                        StandardIntegrityManager.PrepareIntegrityTokenRequest.builder().setCloudProjectNumber(project).build(),
                    ).awaitResult() }
                    preparedProject = project
                }
                requireNotNull(provider)
            }
            val hash = Base64.encodeToString(MessageDigest.getInstance("SHA-256").digest(challenge.payload.toByteArray(Charsets.UTF_8)), Base64.URL_SAFE or Base64.NO_WRAP or Base64.NO_PADDING)
            val token = withTimeout(30_000) { tokenProvider.request(
                StandardIntegrityManager.StandardIntegrityTokenRequest.builder().setRequestHash(hash).build(),
            ).awaitResult() }
            return mapOf("kind" to "play_integrity", "token" to token.token())
        } catch (error: Exception) {
            provider = null
            throw error
        }
    }
}

private suspend fun <T> Task<T>.awaitResult(): T = suspendCancellableCoroutine { continuation ->
    addOnSuccessListener { if (continuation.isActive) continuation.resume(it) }
    addOnFailureListener { if (continuation.isActive) continuation.resumeWithException(it) }
}
