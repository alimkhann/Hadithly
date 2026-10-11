package com.hadithly.app.features.reader

import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.R
import com.hadithly.app.core.data.EvidenceCitation
import com.clerk.api.Clerk
import com.hadithly.app.core.data.EvidenceDraftView
import com.hadithly.app.core.data.EvidenceClientPolicy
import com.hadithly.app.core.data.EvidenceLocalDrafts
import com.hadithly.app.core.data.LocalEvidenceChoice
import com.hadithly.app.core.data.LocalEvidenceDraft
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.theme.LocalHadithlyColors
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.collect
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import kotlinx.serialization.json.Json
import java.io.File
import java.security.MessageDigest
import java.util.UUID

private fun evidenceError(failure: Throwable): String {
    val message = failure.message.orEmpty()
    if ("Unauthenticated" in message) return "Sign-in is reconnecting. Retry in a moment."
    val serverReason = Regex("Uncaught Error: ([^\\n]+)").find(message)?.groupValues?.get(1)
    return (serverReason ?: message.takeUnless { "Server Error" in it }?.lineSequence()?.firstOrNull())
        ?.take(180) ?: "Evidence could not be submitted. Please retry."
}

@Composable
internal fun EvidenceProcessingStatusContent(status: String, retryItems: List<String>, citations: List<EvidenceCitation> = emptyList(), onRetry: (String) -> Unit) {
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    Column(verticalArrangement = Arrangement.spacedBy(10.dp)) {
        if (status == "awaiting_processing") {
            CircularProgressIndicator(modifier = Modifier.testTag("submission.processing").semantics { contentDescription = "Processing evidence" })
            Text("Evidence received; awaiting checks.", color = colors.textPrimary, fontSize = 18.sp)
            Text("Processing evidence. Your suggestion stays private and has not been reviewed or published.", color = colors.textSecondary)
        } else if (status in setOf("under_review", "approved", "held", "rejected", "review_unavailable")) {
            val title = when (status) {
                "under_review" -> R.string.e3_reviewing
                "approved" -> R.string.e3_published
                "held" -> R.string.e3_exception
                "rejected" -> R.string.e3_rejected
                else -> R.string.e3_unavailable
            }
            val message = when (status) {
                "under_review" -> R.string.e3_reviewing_message
                "approved" -> R.string.e3_published_message
                "held" -> R.string.e3_exception_message
                "rejected" -> R.string.e3_rejected_message
                else -> R.string.e3_unavailable_message
            }
            Text(stringResource(title), color = colors.textPrimary, fontSize = 18.sp, modifier = Modifier.testTag("submission.$status"))
            Text(stringResource(message), color = colors.textSecondary)
            if (status == "under_review") CircularProgressIndicator()
        } else if (status == "evidence_ready") {
            Text("Evidence checks complete", color = colors.textPrimary, fontSize = 18.sp, modifier = Modifier.testTag("submission.ready"))
            Text(stringResource(R.string.e3_waiting), color = colors.textSecondary)
        } else {
            Text(if (status == "infected") "Evidence cannot be used" else "Evidence processing failed", color = colors.textPrimary, fontSize = 18.sp,
                modifier = Modifier.testTag(if (status == "infected") "submission.infected" else "submission.failed"))
            Text("Your suggestion remains private. Withdraw it and submit different evidence if needed.", color = colors.textSecondary)
        }
        if (status in setOf("awaiting_processing", "processing_failed")) retryItems.forEach { itemId ->
            TextButton(onClick = { onRetry(itemId) }, modifier = Modifier.testTag("submission.retryProcessing")) { Text("Retry evidence") }
        }
        if (citations.isNotEmpty()) {
            Text(stringResource(R.string.e3_sources), color = colors.textPrimary)
            citations.forEachIndexed { index, citation ->
                if (EvidenceClientPolicy.httpsURL(citation.url) != null) {
                    TextButton(onClick = { uriHandler.openUri(citation.url) }, modifier = Modifier.fillMaxWidth().testTag("submission.citation.$index")) {
                        Column(modifier = Modifier.fillMaxWidth()) {
                            Text(citation.title, color = colors.textPrimary)
                            Text(citation.location, color = colors.textSecondary)
                        }
                    }
                }
            }
        }
    }
}

@Composable
fun TranslationSubmissionSheet(
    viewModel: ReaderViewModel,
    hadith: ReaderHadith,
    existingTranslation: ReaderTranslation?,
    initialContent: String,
    onDone: () -> Unit,
) {
    val app = HadithlyApplication.instance()
    val repository = app.repository
    val context = LocalContext.current
    val colors = LocalHadithlyColors.current
    val scope = rememberCoroutineScope()
    val sessions by Clerk.sessionsFlow.collectAsState()
    val readerState by viewModel.state.collectAsState()
    val accountId = if (sessions.isNotEmpty()) Clerk.user?.id else null
    val localKey = "evidence.draft.${accountId ?: "guest"}.${hadith.internalId}.${readerState.language}"
    val localPrefs = remember { context.getSharedPreferences(EvidenceLocalDrafts.PREFERENCES_NAME, 0) }
    var content by remember(localKey) { mutableStateOf(initialContent) }
    var urlInput by remember(localKey) { mutableStateOf("") }
    val choices = remember(localKey) { mutableStateListOf<LocalEvidenceChoice>() }
    var draft by remember(localKey) { mutableStateOf<EvidenceDraftView?>(null) }
    var legacySubmissionId by remember(localKey) { mutableStateOf<String?>(null) }
    var draftKey by remember(localKey) { mutableStateOf(UUID.randomUUID().toString()) }
    var localCreatedAt by remember(localKey) { mutableStateOf(System.currentTimeMillis()) }
    var localLoaded by remember(localKey) { mutableStateOf(false) }
    var replacingItemKey by remember(localKey) { mutableStateOf<String?>(null) }
    var progress by remember(localKey) { mutableStateOf(0.0) }
    var uploading by remember(localKey) { mutableStateOf(false) }
    var error by remember(localKey) { mutableStateOf<String?>(null) }
    var uploadJob by remember(localKey) { mutableStateOf<Job?>(null) }

    fun persistRemoteDraft(remote: EvidenceDraftView, selected: List<LocalEvidenceChoice>) {
        val saved = LocalEvidenceDraft(
            submissionId = remote.submissionId, draftKey = draftKey,
            proposedContent = content, urlInput = urlInput, choices = selected,
            legacySubmissionId = legacySubmissionId, createdAt = localCreatedAt,
        )
        check(localPrefs.edit().putString(localKey, Json.encodeToString(saved)).commit()) {
            "Could not save this evidence draft on the device."
        }
    }

    DisposableEffect(localKey) {
        onDispose { uploadJob?.cancel() }
    }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null || (choices.size >= 3 && replacingItemKey == null)) return@rememberLauncherForActivityResult
        scope.launch {
            runCatching {
                withContext(Dispatchers.IO) {
                    val mime = context.contentResolver.getType(uri) ?: kotlin.error("Choose a JPEG, PNG, WebP, or PDF.")
                    require(mime in setOf("image/jpeg", "image/png", "image/webp", "application/pdf")) { "Choose a JPEG, PNG, WebP, or PDF." }
                    val id = replacingItemKey ?: UUID.randomUUID().toString()
                    val directory = File(context.filesDir, "evidenceDrafts").apply { mkdirs() }
                    val copy = File(directory, UUID.randomUUID().toString())
                    var total = 0L
                    val digest = MessageDigest.getInstance("SHA-256")
                    try {
                        context.contentResolver.openInputStream(uri)?.use { input ->
                            copy.outputStream().use { output ->
                                val buffer = ByteArray(64 * 1024)
                                while (true) {
                                    val count = input.read(buffer)
                                    if (count < 0) break
                                    total += count
                                    require(total <= EvidenceClientPolicy.MAX_FILE_BYTES) { "Each file must be 10 MB or smaller." }
                                    output.write(buffer, 0, count)
                                    digest.update(buffer, 0, count)
                                }
                            }
                        } ?: kotlin.error("Could not open the selected file.")
                        require(EvidenceClientPolicy.acceptsFileSize(total)) { "The selected file is empty." }
                    } catch (failure: Exception) {
                        copy.delete()
                        throw failure
                    }
                    val sha256 = digest.digest().joinToString("") { byte -> (byte.toInt() and 0xff).toString(16).padStart(2, '0') }
                    LocalEvidenceChoice(id, "file", "Evidence file ${choices.size + 1}", filePath = copy.absolutePath, mime = mime, size = total, sha256 = sha256)
                }
            }.onSuccess {
                choices.firstOrNull { old -> old.id == it.id }?.filePath?.let(::File)?.delete()
                choices.removeAll { old -> old.id == it.id }
                choices.add(it)
                replacingItemKey = null
                error = null
            }
                .onFailure { error = it.message ?: "Could not add this file." }
        }
    }

    LaunchedEffect(localKey) {
        localLoaded = false
        draft = null
        choices.clear()
        content = initialContent
        urlInput = ""
        legacySubmissionId = null
        draftKey = UUID.randomUUID().toString()
        localCreatedAt = System.currentTimeMillis()
        val saved = localPrefs.getString(localKey, null)?.let { runCatching { Json.decodeFromString<LocalEvidenceDraft>(it) }.getOrNull() }
        val active = saved?.takeUnless { it.submissionId == null && System.currentTimeMillis() - it.createdAt > 7 * 24 * 60 * 60 * 1000L }
        if (saved != null && active == null) {
            saved.choices.forEach { it.filePath?.let(::File)?.delete() }
            localPrefs.edit().remove(localKey).apply()
        }
        if (active != null && viewModel.canContribute && accountId != null) {
            draftKey = active.draftKey
            localCreatedAt = active.createdAt
            content = active.proposedContent
            urlInput = active.urlInput
            choices.addAll(active.choices)
            legacySubmissionId = active.legacySubmissionId
            active.submissionId?.let { id -> runCatching { repository.getOwnEvidenceDraft(id) }
                .onSuccess { remote ->
                    if (remote != null) {
                        draft = remote
                        content = remote.proposedContent
                    }
                }
                .onFailure { error = "This draft could not be loaded. Retry after the connection returns." }
            }
        }
        if (active == null && viewModel.canContribute && accountId != null) {
            runCatching { repository.getOwnLegacyProposal(hadith.internalId, viewModel.state.value.language) }
                .getOrNull()?.let { legacy ->
                    legacySubmissionId = legacy.submissionId
                    content = legacy.proposedContent
                }
        }
        localLoaded = true
    }

    LaunchedEffect(localKey, localLoaded, content, urlInput, choices.toList(), draft?.submissionId, legacySubmissionId) {
        if (!localLoaded || !viewModel.canContribute || accountId == null) return@LaunchedEffect
        if (draft == null && content.isEmpty() && urlInput.isEmpty() && choices.isEmpty()) {
            localPrefs.edit().remove(localKey).apply()
        } else {
            localPrefs.edit().putString(localKey, Json.encodeToString(LocalEvidenceDraft(
                submissionId = draft?.submissionId, draftKey = draftKey,
                proposedContent = content, urlInput = urlInput,
                choices = choices.toList(), legacySubmissionId = legacySubmissionId,
                createdAt = localCreatedAt,
            ))).apply()
        }
    }

    LaunchedEffect(localKey, draft?.submissionId) {
        val submissionId = draft?.submissionId ?: return@LaunchedEffect
        try {
            repository.observeEvidenceDraft(submissionId).collect { remote -> draft = remote }
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            error = "Evidence status is unavailable. Try again when connected."
        }
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(14.dp),
        modifier = Modifier.fillMaxWidth().navigationBarsPadding().verticalScroll(rememberScrollState()).padding(20.dp),
    ) {
        Row(modifier = Modifier.fillMaxWidth()) {
            Text("Suggest a translation", fontSize = 20.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
            TextButton(onClick = { uploadJob?.cancel(); onDone() }) { Text("Done", color = colors.interactive) }
        }
        when {
            !viewModel.canContribute || accountId == null -> Text("Sign in from Settings to suggest a translation with evidence.", color = colors.textSecondary, modifier = Modifier.testTag("submission.signInRequired"))
            draft?.status == "expired" -> Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.testTag("submission.expired")) {
                Text("Evidence expired", color = colors.textPrimary, fontSize = 18.sp)
                Text("The private files were removed before processing. You can start a new suggestion.", color = colors.textSecondary)
                TextButton(onClick = {
                    draft?.submissionId?.let { id -> scope.launch {
                        runCatching { repository.deleteEvidenceDraft(id) }
                        localPrefs.edit().remove(localKey).apply()
                        choices.forEach { it.filePath?.let(::File)?.delete() }
                        choices.clear(); draft = null; content = ""; urlInput = ""; legacySubmissionId = null
                        draftKey = UUID.randomUUID().toString(); localCreatedAt = System.currentTimeMillis(); error = null
                    } }
                }) { Text("Start a new suggestion") }
            }
            draft?.status in setOf("awaiting_processing", "evidence_ready", "processing_failed", "infected", "under_review", "approved", "held", "rejected", "review_unavailable") -> Column(verticalArrangement = Arrangement.spacedBy(10.dp), modifier = Modifier.testTag("submission.confirmation")) {
                EvidenceProcessingStatusContent(
                    status = draft?.status ?: "processing_failed",
                    retryItems = draft?.items?.filter { it.state == "failed" && it.retryable }?.map { it.itemId }.orEmpty(),
                    citations = draft?.citations.orEmpty(),
                    onRetry = { itemId ->
                        draft?.submissionId?.let { submissionId -> scope.launch {
                            runCatching { repository.retryEvidenceProcessing(submissionId, itemId) }
                                .onFailure { error = "Evidence could not be retried right now." }
                        } }
                    },
                )
                error?.let { Text(it, color = colors.textSecondary, modifier = Modifier.testTag("submission.error")) }
                if (draft?.status != "approved") TextButton(onClick = {
                    draft?.submissionId?.let { id -> scope.launch {
                        runCatching { repository.deleteEvidenceDraft(id) }
                            .onSuccess {
                                localPrefs.edit().remove(localKey).apply()
                                choices.forEach { it.filePath?.let(::File)?.delete() }
                                choices.clear(); draft = null; content = ""; urlInput = ""; legacySubmissionId = null
                                draftKey = UUID.randomUUID().toString(); localCreatedAt = System.currentTimeMillis(); error = null
                            }
                            .onFailure { error = it.message ?: "Could not withdraw this suggestion." }
                    } }
                }, modifier = Modifier.testTag("submission.deleteDraft")) { Text("Withdraw suggestion") }
            }
            else -> {
                Text(hadith.referenceDisplay, color = colors.textPrimary)
                Text("Add one to three source links or files. Evidence stays private while checked.", color = colors.textSecondary, fontSize = 12.sp)
                OutlinedTextField(value = content, onValueChange = { content = it }, modifier = Modifier.fillMaxWidth().height(170.dp).testTag("submission.editor"))
                Row {
                    OutlinedTextField(value = urlInput, onValueChange = { urlInput = it }, label = { Text("HTTPS source link") }, modifier = Modifier.weight(1f).testTag("submission.evidence.url"))
                    TextButton(onClick = {
                        val url = EvidenceClientPolicy.httpsURL(urlInput)
                        if (url == null || choices.size >= 3) error = "Enter an HTTPS source link without credentials."
                        else { choices.add(LocalEvidenceChoice(UUID.randomUUID().toString(), "url", url.host ?: url.toString(), url = url.toString())); urlInput = ""; error = null }
                    }, enabled = localLoaded && draft == null && choices.size < 3) { Text("Add link") }
                }
                TextButton(onClick = { picker.launch(arrayOf("image/jpeg", "image/png", "image/webp", "application/pdf")) }, enabled = localLoaded && draft == null && choices.size < 3, modifier = Modifier.testTag("submission.evidence.file")) { Text("Add image or PDF") }
                choices.forEach { choice ->
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Text(choice.label, color = colors.textPrimary, modifier = Modifier.weight(1f))
                        if (draft == null) TextButton(onClick = { choice.filePath?.let { File(it).delete() }; choices.remove(choice) }) { Text("Remove") }
                    }
                }
                draft?.items?.forEach { item ->
                    Row(modifier = Modifier.fillMaxWidth()) {
                        Text("${item.displayName ?: item.url ?: "Evidence"}: ${item.state.replace('_', ' ')}", color = colors.textSecondary, fontSize = 12.sp, modifier = Modifier.weight(1f))
                        if (item.kind == "file" && item.state != "quarantined_unscanned" && choices.firstOrNull { it.id == item.clientItemKey }?.filePath?.let { File(it).isFile } != true) {
                            TextButton(onClick = {
                                replacingItemKey = item.clientItemKey
                                picker.launch(arrayOf("image/jpeg", "image/png", "image/webp", "application/pdf"))
                            }) { Text("Select again") }
                        }
                    }
                }
                if (uploading) LinearProgressIndicator(
                    progress = { progress.toFloat() },
                    modifier = Modifier.fillMaxWidth().semantics { contentDescription = "Evidence upload progress" }
                        .testTag("submission.uploadProgress"),
                )
                error?.let { Text(it, color = colors.textSecondary, modifier = Modifier.testTag("submission.error")) }
                if (uploading) TextButton(onClick = { uploadJob?.cancel() }, modifier = Modifier.testTag("submission.cancelUpload")) { Text("Cancel upload") }
                if (draft != null && !uploading) TextButton(onClick = {
                    draft?.submissionId?.let { id -> scope.launch {
                        runCatching { repository.deleteEvidenceDraft(id) }
                            .onSuccess {
                                localPrefs.edit().remove(localKey).apply()
                                choices.forEach { it.filePath?.let(::File)?.delete() }
                                choices.clear(); draft = null; content = ""; urlInput = ""; legacySubmissionId = null
                                draftKey = UUID.randomUUID().toString(); localCreatedAt = System.currentTimeMillis(); error = null
                            }
                            .onFailure { error = it.message ?: "Could not delete this draft." }
                    } }
                }, modifier = Modifier.testTag("submission.deleteDraft")) { Text("Delete draft") }
                Button(
                    enabled = localLoaded && !uploading && content.isNotBlank() && (draft != null || choices.isNotEmpty()),
                    onClick = {
                        uploadJob = scope.launch {
                            uploading = true
                            error = null
                            try {
                                val retrying = draft != null
                                val current = draft?.let { repository.getOwnEvidenceDraft(it.submissionId) ?: kotlin.error("Draft status is unavailable") } ?: repository.createEvidenceDraft(
                                    hadithInternalId = hadith.internalId,
                                    language = viewModel.state.value.language,
                                    proposedContent = content.trim(),
                                    replacesTranslationId = existingTranslation?.translationId,
                                    legacySubmissionId = legacySubmissionId,
                                    draftKey = draftKey,
                                    items = choices.map { choice ->
                                        if (choice.kind == "url") mapOf("kind" to "url", "clientItemKey" to choice.id, "url" to choice.url)
                                        else mapOf("kind" to "file", "clientItemKey" to choice.id, "declaredMime" to choice.mime, "declaredSize" to choice.size?.toDouble(), "declaredSha256" to choice.sha256, "displayName" to choice.label)
                                    },
                                ).also { created ->
                                    draft = created
                                }
                                draft = current
                                persistRemoteDraft(current, choices.toList())
                                if (current.status in setOf("awaiting_processing", "evidence_ready", "processing_failed", "infected", "under_review", "approved", "held", "rejected", "review_unavailable")) {
                                    choices.forEach { it.filePath?.let(::File)?.delete() }
                                    choices.clear()
                                    persistRemoteDraft(current, emptyList())
                                    return@launch
                                }
                                if (current.status == "expired") return@launch
                                current.items.filter { it.kind == "file" && it.state != "quarantined_unscanned" }.forEach { item ->
                                    val choice = choices.firstOrNull { it.id == item.clientItemKey } ?: kotlin.error("Select this file again to retry.")
                                    val file = choice.filePath?.let(::File) ?: kotlin.error("Select this file again to retry.")
                                    require(file.isFile) { "Select this file again to retry." }
                                    if (retrying) repository.replaceEvidenceSlot(current.submissionId, item.itemId, mapOf("kind" to "file", "clientItemKey" to item.clientItemKey, "declaredMime" to choice.mime, "declaredSize" to file.length().toDouble(), "declaredSha256" to choice.sha256, "displayName" to choice.label))
                                    progress = 0.0
                                    repository.uploadEvidence(current.submissionId, item.itemId, choice.mime ?: item.declaredMime ?: kotlin.error("Missing file type"), file) { progress = it }
                                }
                                repository.finalizeEvidenceDraft(current.submissionId)
                                draft = repository.getOwnEvidenceDraft(current.submissionId) ?: current.copy(status = "awaiting_processing")
                                choices.forEach { it.filePath?.let(::File)?.delete() }
                                choices.clear()
                                persistRemoteDraft(current, emptyList())
                            } catch (cancelled: kotlinx.coroutines.CancellationException) {
                                error = "Upload paused. Retry when you are ready."
                            } catch (failure: Exception) {
                                error = evidenceError(failure)
                            } finally { uploading = false; uploadJob = null }
                        }
                    },
                    modifier = Modifier.fillMaxWidth().testTag("submission.submit"),
                ) {
                    if (uploading) CircularProgressIndicator(modifier = Modifier.padding(end = 8.dp))
                    Text(if (draft == null) "Submit with evidence" else "Retry evidence upload")
                }
                Text(stringResource(R.string.e3_consent), color = colors.textSecondary)
            }
        }
    }
}
