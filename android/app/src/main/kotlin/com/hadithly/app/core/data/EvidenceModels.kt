package com.hadithly.app.core.data

import android.content.Context
import kotlinx.serialization.Serializable
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import java.io.File
import java.net.URI

@Serializable
data class EvidenceDraftView(
    val submissionId: String,
    val status: String,
    val proposedContent: String,
    val expiresAt: Double? = null,
    val items: List<EvidenceItemView>,
    val citations: List<EvidenceCitation> = emptyList(),
)

@Serializable
data class EvidenceCitation(val url: String, val title: String, val location: String)

@Serializable
data class EvidenceItemView(
    val itemId: String,
    val clientItemKey: String,
    val kind: String,
    val state: String,
    val retryable: Boolean = false,
    val url: String? = null,
    val displayName: String? = null,
    val declaredMime: String? = null,
    val declaredSize: Double? = null,
    val size: Double? = null,
)

@Serializable
data class EvidenceSubmitResult(val status: String)

@Serializable
data class LegacyEvidenceProposal(val submissionId: String, val proposedContent: String)

object EvidenceClientPolicy {
    const val MAX_FILE_BYTES = 10_000_000L

    fun acceptsFileSize(size: Long): Boolean = size in 1..MAX_FILE_BYTES

    fun httpsURL(raw: String): URI? {
        val uri = runCatching { URI(raw.trim()) }.getOrNull() ?: return null
        if (uri.scheme != "https" || uri.host.isNullOrBlank() || uri.userInfo != null) return null
        return uri
    }
}

@Serializable
data class LocalEvidenceChoice(
    val id: String,
    val kind: String,
    val label: String,
    val url: String? = null,
    val filePath: String? = null,
    val mime: String? = null,
    val size: Long? = null,
    val sha256: String? = null,
)

@Serializable
data class LocalEvidenceDraft(
    val submissionId: String? = null,
    val draftKey: String,
    val proposedContent: String,
    val urlInput: String,
    val choices: List<LocalEvidenceChoice>,
    val legacySubmissionId: String? = null,
    val createdAt: Long,
)

object EvidenceLocalDrafts {
    const val PREFERENCES_NAME = "hadithly.evidence.drafts"

    fun clearForAccount(context: Context, accountId: String) {
        val prefs = context.getSharedPreferences(PREFERENCES_NAME, Context.MODE_PRIVATE)
        val prefix = "evidence.draft.$accountId."
        val directory = runCatching { File(context.filesDir, "evidenceDrafts").canonicalFile }.getOrNull()
        val editor = prefs.edit()
        for ((key, value) in prefs.all) {
            if (!key.startsWith(prefix)) continue
            val draft = (value as? String)?.let { runCatching { Json.decodeFromString<LocalEvidenceDraft>(it) }.getOrNull() }
            draft?.choices?.forEach { choice ->
                choice.filePath?.let { path ->
                    val file = File(path)
                    if (directory != null && runCatching { file.parentFile?.canonicalFile == directory }.getOrDefault(false)) file.delete()
                }
            }
            editor.remove(key)
        }
        editor.apply()
    }
}
