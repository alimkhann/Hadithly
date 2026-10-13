package com.hadithly.app.core.offline

import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.CollectionOutlineResult
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderPageResult
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

@Serializable
data class OfflineManifestsResponse(
    val bases: List<OfflineManifest> = emptyList(),
    val packs: List<OfflineManifest> = emptyList(),
)

/**
 * O2 download manager. Owns the on-disk layout, the device-local registry,
 * and the verify → stage → migrate-check → activate pipeline:
 *
 *     <root>/<slug>/base/<od1-hex>/dump.json (+ manifest.json)
 *     <root>/<slug>/pack-<locale>/<od1-hex>/pack.json (+ manifest.json)
 *     <root>/registry.json
 *
 * The reader only ever touches the registry's `activeBase` pointer. Every
 * mutation is idempotent: re-running boot, refresh, download, activation, or
 * deletion converges to the same end state, and a crash at any point leaves
 * the previous version usable. Mirrors the iOS `OfflineStore`.
 */
class OfflineStore(
    private val root: File,
    private val transport: OfflineDownloadTransport = HttpOfflineTransport(),
    private val appVersion: String = "0.1.0",
    private val manifestProvider: (suspend (String?) -> OfflineManifestsResponse)? = null,
    private val ioScope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Main),
) {
    var analytics: com.hadithly.app.core.analytics.UsageStatistics? = null
    private val json = Json { ignoreUnknownKeys = true }

    private val _revision = MutableStateFlow(0L)
    /** Bumped on every registry/progress change so Compose recomposes. */
    val revision: StateFlow<Long> = _revision

    private val _progress = MutableStateFlow(emptyMap<String, Double>())
    val progress: StateFlow<Map<String, Double>> = _progress

    private var registry: OfflineRegistry = OfflineRegistry()
    private var bases: Map<String, OfflineManifest> = emptyMap()
    private var packs: Map<String, OfflineManifest> = emptyMap()
    /**
     * One live run per collection: starting a second collection must never
     * cancel the first. A single shared job meant only one collection could
     * download at a time.
     */
    private var runJobs: MutableMap<String, Job> = mutableMapOf()
    private var runGenerations: MutableMap<String, Int> = mutableMapOf()
    private var dumpCache: MutableMap<String, OfflineBaseDump> = mutableMapOf()
    private var packCache: MutableMap<String, OfflineTranslationPack> = mutableMapOf()
    private val anchorProviders: MutableMap<String, () -> Set<String>> = mutableMapOf()
    var lastError: String? = null
        private set

    init {
        root.mkdirs()
        loadRegistry()
        reconcile()
    }

    private fun changed() {
        _revision.value += 1
    }

    // MARK: - Registry persistence (atomic)

    private fun registryFile(): File = File(root, "registry.json")

    private fun loadRegistry() {
        val file = registryFile()
        val decoded = runCatching {
            json.decodeFromString<OfflineRegistry>(file.readText())
        }.getOrNull()
        if (decoded != null && decoded.version == OfflineRegistry.CURRENT_VERSION) {
            registry = decoded
            return
        }
        if (file.exists()) {
            file.renameTo(File(root, "registry.corrupt-${System.currentTimeMillis()}"))
        }
        registry = OfflineRegistry()
        rebuildRegistryByScanning()
    }

    private fun saveRegistry() {
        val tmp = File(root, "registry.json.tmp")
        runCatching {
            tmp.writeText(json.encodeToString(OfflineRegistry.serializer(), registry))
            val target = registryFile()
            target.delete()
            tmp.renameTo(target)
        }.onFailure { tmp.delete() }
    }

    private fun updateRecord(slug: String, update: (OfflineCollectionRecord) -> OfflineCollectionRecord) {
        val current = registry.collections[slug] ?: OfflineCollectionRecord()
        registry = registry.copy(collections = registry.collections + (slug to update(current)))
        saveRegistry()
        changed()
    }

    fun recordFor(slug: String): OfflineCollectionRecord =
        registry.collections[slug] ?: OfflineCollectionRecord()

    fun isWifiOnly(): Boolean = registry.wifiOnly

    fun setWifiOnly(value: Boolean) {
        registry = registry.copy(wifiOnly = value)
        saveRegistry()
        changed()
    }

    fun lastManifestCheck(): Double? = registry.lastManifestCheck

    /** Test and preview support: swaps cached manifests without network. */
    fun noteManifests(bases: List<OfflineManifest>, packs: List<OfflineManifest> = emptyList()) {
        this.bases = bases.associateBy { it.collectionSlug }
        this.packs = packs.associateBy { OfflineModels.packKey(it.collectionSlug, it.locale ?: "") }
        changed()
    }

    private fun rebuildRegistryByScanning() {
        val slugs = root.listFiles()?.filter { it.isDirectory } ?: return
        for (slugDir in slugs) {
            val slug = slugDir.name
            if (!slug.matches(Regex("^[a-z][a-z0-9-]{1,31}$"))) continue
            val baseRoot = File(slugDir, "base")
            val versions = baseRoot.listFiles()?.filter { it.isDirectory } ?: continue
            var newest: Pair<String, Double>? = null
            for (versionDir in versions) {
                val dumpFile = File(versionDir, "dump.json")
                if (!dumpFile.isFile) continue
                val dump = runCatching {
                    json.decodeFromString<OfflineBaseDump>(dumpFile.readText())
                }.getOrNull() ?: continue
                runCatching { OfflineDumps.validateBaseDump(dump) }.onFailure { continue }
                if (newest == null || dump.generatedAt > newest.second) {
                    newest = dump.contentVersion to dump.generatedAt
                }
            }
            val found = newest ?: continue
            updateRecord(slug) {
                it.copy(activeBase = found.first, activeBaseGeneratedAt = found.second)
            }
        }
    }

    // MARK: - Boot reconciliation (idempotent)

    /**
     * Convergent startup: orphan `.tmp` files without a download record are
     * removed; interrupted downloads become paused; staged entries without
     * their manifest pairing are dropped. The active pointer is never
     * touched here.
     */
    fun reconcile() {
        val slugs = root.listFiles()?.filter { it.isDirectory } ?: return
        var touched = false
        for (slugDir in slugs) {
            val slug = slugDir.name
            if (!slug.matches(Regex("^[a-z][a-z0-9-]{1,31}$"))) continue
            val record = recordFor(slug)
            val download = record.download
            if (download != null) {
                when (OfflineDownloadState.fromWire(download.state)) {
                    OfflineDownloadState.QUEUED,
                    OfflineDownloadState.DOWNLOADING,
                    OfflineDownloadState.VERIFYING,
                    -> {
                        updateRecord(slug) {
                            it.copy(download = download.copy(state = OfflineDownloadState.PAUSED.wire, reason = null))
                        }
                        touched = true
                    }
                    OfflineDownloadState.PAUSED, OfflineDownloadState.FAILED -> Unit
                }
            } else {
                slugDir.walkTopDown().filter { it.isFile && it.extension == "tmp" }.forEach { it.delete() }
            }
            if (record.stagedBase != null &&
                stagedManifest(slug, "base", record.stagedBase, null) == null
            ) {
                updateRecord(slug) { it.copy(stagedBase = null) }
                touched = true
            }
            val badPacks = record.stagedPacks.filter { (locale, version) ->
                stagedManifest(slug, "pack", version, locale) == null
            }.keys
            if (badPacks.isNotEmpty()) {
                updateRecord(slug) { it.copy(stagedPacks = it.stagedPacks - badPacks) }
                touched = true
            }
        }
        if (touched) changed()
    }

    // MARK: - Manifests

    /**
     * Manifest fetches share the reader's bounded-wait discipline: a hung
     * subscription must surface "could not reach the server", never a
     * permanently queued download.
     */
    private val manifestTimeoutMs = 15_000L

    suspend fun refresh(translationLocale: String?) {
        val provider = manifestProvider ?: return
        try {
            val response = withTimeout(manifestTimeoutMs) { provider(translationLocale) }
            bases = response.bases.associateBy { it.collectionSlug }
            packs = response.packs.associateBy {
                OfflineModels.packKey(it.collectionSlug, it.locale ?: translationLocale ?: "")
            }
            registry = registry.copy(lastManifestCheck = System.currentTimeMillis().toDouble())
            saveRegistry()
            lastError = null
            changed()
        } catch (error: Exception) {
            com.hadithly.app.core.diagnostics.CrashReporting.failure(com.hadithly.app.core.diagnostics.DiagnosticFailure.OfflineManifest)
            lastError = "Could not check for updates (${error.message?.take(120)}). Your downloads keep working offline."
            changed()
        }
    }

    fun baseManifest(slug: String): OfflineManifest? = bases[slug]

    fun packManifest(slug: String, locale: String): OfflineManifest? =
        packs[OfflineModels.packKey(slug, locale)]

    // MARK: - Status derivation

    fun status(slug: String, translationLocale: String?): OfflineCollectionStatus {
        val record = recordFor(slug)
        record.download?.let { download ->
            val fraction = _progress.value[OfflineModels.progressKey(slug, download.kind, download.locale)] ?: 0.0
            return when (OfflineDownloadState.fromWire(download.state)) {
                OfflineDownloadState.QUEUED -> OfflineCollectionStatus.Queued(fraction)
                OfflineDownloadState.DOWNLOADING -> OfflineCollectionStatus.Downloading(fraction)
                OfflineDownloadState.PAUSED -> OfflineCollectionStatus.Paused(fraction)
                OfflineDownloadState.VERIFYING -> OfflineCollectionStatus.Verifying
                OfflineDownloadState.FAILED ->
                    OfflineCollectionStatus.Failed(download.reason ?: "Download failed.")
            }
        }
        bases[slug]?.let { manifest ->
            if (!OfflineModels.appVersionSatisfiesMinimum(appVersion, manifest.minAppVersion)) {
                return OfflineCollectionStatus.AppUpdateRequired(manifest.minAppVersion)
            }
        }
        val active = record.activeBase ?: return OfflineCollectionStatus.NotInstalled
        val manifest = bases[slug] ?: return OfflineCollectionStatus.Active(active, false, false)
        val updateAvailable = manifest.contentVersion != active
        var stalePack = false
        if (translationLocale != null) {
            val pack = packManifest(slug, translationLocale)
            val activePack = record.activePacks[translationLocale]
            stalePack = if (pack != null) {
                pack.contentVersion != activePack || pack.baseContentVersion != active
            } else {
                false
            }
            if (pack != null && activePack == null) stalePack = true
        }
        return OfflineCollectionStatus.Active(active, updateAvailable, stalePack)
    }

    // MARK: - Storage accounting

    fun offlineBytes(): Long =
        root.walkTopDown().filter { it.isFile && it.extension != "tmp" && it.name != "registry.json" }
            .sumOf { it.length() }

    fun freeBytes(): Long = root.usableSpace

    /**
     * Refuses a download the device cannot hold: the manifest bytes twice
     * (partial `.tmp` plus verified final) plus an 8 MB headroom.
     */
    fun storageError(manifest: OfflineManifest): String? {
        val need = manifest.byteSize.toLong() * 2 + 8 * 1024 * 1024
        val free = freeBytes()
        if (free < need) {
            return "Not enough storage: need ${OfflineModels.formatBytes(need)}, ${OfflineModels.formatBytes(free)} free."
        }
        return null
    }

    // MARK: - Download lifecycle

    fun enqueue(slug: String, kind: String, locale: String?): OfflineEnqueueResult {
        val record = recordFor(slug)
        if (record.download != null) return OfflineEnqueueResult.Started
        val manifest = if (kind == "pack") {
            if (locale == null) return OfflineEnqueueResult.Blocked("Pick a translation language first.")
            packManifest(slug, locale)
        } else {
            bases[slug]
        }
        if (kind == "pack") {
            if (record.activePacks[locale] == manifest?.contentVersion && manifest != null) {
                return OfflineEnqueueResult.AlreadyActive
            }
        } else if (record.activeBase == manifest?.contentVersion && manifest != null) {
            return OfflineEnqueueResult.AlreadyActive
        }
        if (manifest == null) {
            return OfflineEnqueueResult.Blocked("No offline file is published for this collection yet.")
        }
        if (!OfflineModels.appVersionSatisfiesMinimum(appVersion, manifest.minAppVersion)) {
            return OfflineEnqueueResult.Blocked("Update Hadithly to download this collection.")
        }
        if (kind == "base" && manifest.contentVersion != record.activeBase &&
            record.activeBase != null && record.activeBaseGeneratedAt != null &&
            manifest.generatedAt < record.activeBaseGeneratedAt!!
        ) {
            return OfflineEnqueueResult.Blocked(
                "The server offers an older file than your installed copy. Your copy stays active.",
            )
        }
        storageError(manifest)?.let { return OfflineEnqueueResult.Blocked(it) }
        updateRecord(slug) {
            it.copy(
                download = OfflineDownloadRecord(
                    kind = kind,
                    contentVersion = manifest.contentVersion,
                    locale = locale,
                    state = OfflineDownloadState.QUEUED.wire,
                    updatedAt = System.currentTimeMillis().toDouble(),
                ),
            )
        }
        startRun(slug)
        analytics?.record(com.hadithly.app.core.analytics.AnalyticsMetric.offlineActivationResultStarted)
        return OfflineEnqueueResult.Started
    }

    fun pause(slug: String) {
        if (recordFor(slug).download == null) return
        invalidateRun(slug)
        updateRecord(slug) { record ->
            val state = OfflineDownloadState.fromWire(record.download?.state ?: "")
            if (state == OfflineDownloadState.DOWNLOADING || state == OfflineDownloadState.QUEUED) {
                record.copy(download = record.download?.copy(state = OfflineDownloadState.PAUSED.wire))
            } else {
                record
            }
        }
    }

    fun cancel(slug: String) {
        invalidateRun(slug)
        val record = recordFor(slug)
        record.download?.let { download ->
            analytics?.record(com.hadithly.app.core.analytics.AnalyticsMetric.offlineActivationResultCancelled)
            _progress.value = _progress.value - OfflineModels.progressKey(slug, download.kind, download.locale)
        }
        tmpFile(slug, record)?.delete()
        updateRecord(slug) { it.copy(download = null) }
    }

    fun retry(slug: String) {
        val download = recordFor(slug).download ?: return
        updateRecord(slug) {
            it.copy(
                download = download.copy(
                    state = OfflineDownloadState.QUEUED.wire,
                    reason = null,
                    updatedAt = System.currentTimeMillis().toDouble(),
                ),
            )
        }
        startRun(slug)
    }

    /**
     * Deletes downloaded files only. Saved items, folders, notes, reading
     * positions, and preferences live in other stores and are untouched.
     */
    fun delete(slug: String) {
        invalidateRun(slug)
        File(root, slug).deleteRecursively()
        registry = registry.copy(collections = registry.collections - slug)
        dumpCache.keys.filter { it == slug }.forEach { dumpCache.remove(it) }
        packCache.keys.filter { it.startsWith("$slug#") }.forEach { packCache.remove(it) }
        saveRegistry()
        changed()
    }

    /**
     * Queues a base update and remembers the translation locale so the
     * runner chains the matching pack update once the base is staged.
     */
    fun update(slug: String, translationLocale: String?) {
        if (recordFor(slug).download != null) return
        enqueue(slug, "base", translationLocale)
    }

    // MARK: - Download runner (idempotent)

    private fun invalidateRun(slug: String) {
        runGenerations[slug] = (runGenerations[slug] ?: 0) + 1
        runJobs.remove(slug)?.cancel()
    }

    private fun isCurrentRun(slug: String, generation: Int): Boolean =
        (runGenerations[slug] ?: 0) == generation

    private fun startRun(slug: String) {
        invalidateRun(slug)
        val generation = runGenerations[slug] ?: 0
        runJobs[slug] = ioScope.launch {
            try {
                runLoop(slug, generation)
            } finally {
                // Only the current run clears its own handle; a newer run's
                // job for the same slug must survive.
                if (isCurrentRun(slug, generation)) runJobs.remove(slug)
            }
        }
    }

    private suspend fun runLoop(slug: String, generation: Int) {
        val provider = manifestProvider ?: return
        while (true) {
            val download = recordFor(slug).download
                ?.takeIf { OfflineDownloadState.fromWire(it.state) == OfflineDownloadState.QUEUED }
                ?: return
            if (!isCurrentRun(slug, generation)) return
            // Fresh signed URL: the cached manifest URL may have expired.
            // Bounded: a hung subscription fails the run instead of
            // queueing forever.
            try {
                val response = withTimeout(manifestTimeoutMs) { provider(download.locale) }
                if (download.kind == "base") {
                    bases = bases + response.bases.associateBy { it.collectionSlug }
                } else {
                    packs = packs + response.packs.associateBy {
                        OfflineModels.packKey(it.collectionSlug, it.locale ?: "")
                    }
                }
            } catch (_: Exception) {
                if (isCurrentRun(slug, generation)) {
                    updateRecord(slug) {
                        it.copy(
                            download = it.download?.copy(
                                state = OfflineDownloadState.FAILED.wire,
                                reason = "Could not reach the server. Try again when you are online.",
                            ),
                        )
                    }
                }
                return
            }
            val manifest = currentManifest(slug, recordFor(slug).download ?: return)
            if (manifest == null) {
                if (isCurrentRun(slug, generation)) {
                    updateRecord(slug) {
                        it.copy(
                            download = it.download?.copy(
                                state = OfflineDownloadState.FAILED.wire,
                                reason = "No offline file is published for this collection yet.",
                            ),
                        )
                    }
                }
                return
            }
            if (manifest.contentVersion != download.contentVersion) {
                // Server moved on mid-queue: adopt the newest manifest
                // instead of downloading a stale file.
                updateRecord(slug) {
                    it.copy(download = it.download?.copy(contentVersion = manifest.contentVersion))
                }
                continue
            }
            downloadBytes(slug, download, manifest, generation)
            if (download.kind == "base") {
                val locale = download.locale ?: packLocaleHint(slug)
                if (locale != null) {
                    chainPackIfNeeded(slug, locale)
                    if (recordFor(slug).download != null) continue
                }
            }
        }
    }

    private fun packLocaleHint(slug: String): String? =
        packs.keys.firstOrNull { it.startsWith("$slug#") }?.removePrefix("$slug#")

    private fun chainPackIfNeeded(slug: String, locale: String) {
        val record = recordFor(slug)
        val pack = packManifest(slug, locale) ?: return
        if (record.download != null) return
        if (record.activePacks[locale] == pack.contentVersion) return
        if (pack.baseContentVersion != (record.stagedBase ?: record.activeBase)) return
        updateRecord(slug) {
            it.copy(
                download = OfflineDownloadRecord(
                    kind = "pack",
                    contentVersion = pack.contentVersion,
                    locale = locale,
                    state = OfflineDownloadState.QUEUED.wire,
                    updatedAt = System.currentTimeMillis().toDouble(),
                ),
            )
        }
    }

    private fun currentManifest(slug: String, download: OfflineDownloadRecord): OfflineManifest? =
        if (download.kind == "pack" && download.locale != null) {
            packManifest(slug, download.locale)
        } else {
            bases[slug]
        }

    private fun versionDir(slug: String, kind: String, version: String, locale: String?): File {
        val leaf = if (kind == "pack") "pack-${locale ?: "unknown"}" else "base"
        return File(File(File(root, slug), leaf), OfflineModels.directoryName(version))
    }

    private fun tmpFile(slug: String, record: OfflineCollectionRecord): File? {
        val download = record.download ?: return null
        return File(
            versionDir(slug, download.kind, download.contentVersion, download.locale),
            "download.tmp",
        )
    }

    private suspend fun downloadBytes(
        slug: String,
        download: OfflineDownloadRecord,
        manifest: OfflineManifest,
        generation: Int,
    ) {
        if (!isCurrentRun(slug, generation)) return
        updateRecord(slug) {
            it.copy(download = it.download?.copy(state = OfflineDownloadState.DOWNLOADING.wire))
        }
        val key = OfflineModels.progressKey(slug, download.kind, download.locale)
        val dir = versionDir(slug, download.kind, download.contentVersion, download.locale)
        val tmp: File
        val offset: Long
        withContext(Dispatchers.IO) {
            dir.mkdirs()
            tmp = File(dir, "download.tmp")
            offset = if (tmp.isFile) tmp.length() else 0L
        }
        if (manifest.downloadUrl.isNullOrBlank()) {
            if (isCurrentRun(slug, generation)) {
                updateRecord(slug) {
                    it.copy(
                        download = it.download?.copy(
                            state = OfflineDownloadState.FAILED.wire,
                            reason = "The download link is invalid. Try again.",
                        ),
                    )
                }
            }
            return
        }
        try {
            transport.downloadToFile(manifest.downloadUrl, tmp, offset) { fraction ->
                _progress.value = _progress.value + (key to fraction)
            }
            _progress.value = _progress.value + (key to 1.0)
            if (!isCurrentRun(slug, generation)) return
            updateRecord(slug) {
                it.copy(download = it.download?.copy(state = OfflineDownloadState.VERIFYING.wire))
            }
            verifyAndStage(slug, download, manifest, tmp)
        } catch (_: CancellationException) {
            if (isCurrentRun(slug, generation)) {
                updateRecord(slug) {
                    it.copy(download = it.download?.copy(state = OfflineDownloadState.PAUSED.wire))
                }
            }
        } catch (_: Exception) {
            if (isCurrentRun(slug, generation)) {
                analytics?.record(com.hadithly.app.core.analytics.AnalyticsMetric.offlineActivationResultFailed)
                updateRecord(slug) {
                    it.copy(
                        download = it.download?.copy(
                            state = OfflineDownloadState.FAILED.wire,
                            reason = "The download was interrupted. Your installed copy still works.",
                        ),
                    )
                }
            }
        }
    }

    // MARK: - Verify, stage, activate, rollback

    private fun stagedManifestFile(slug: String, kind: String, version: String, locale: String?): File =
        File(versionDir(slug, kind, version, locale), "manifest.json")

    private fun stagedManifest(slug: String, kind: String, version: String, locale: String?): OfflineManifest? {
        val file = stagedManifestFile(slug, kind, version, locale)
        if (!file.isFile) return null
        return runCatching { json.decodeFromString<OfflineManifest>(file.readText()) }.getOrNull()
    }

    private suspend fun verifyAndStage(
        slug: String,
        download: OfflineDownloadRecord,
        manifest: OfflineManifest,
        tmp: File,
    ) {
        val record = recordFor(slug)
        val expectedBase = if (download.kind == "pack") {
            record.stagedBase ?: record.activeBase
        } else {
            null
        }
        val failure = withContext(Dispatchers.IO) {
            if (!tmp.isFile) return@withContext "The download was interrupted. Your installed copy still works."
            val bytes = tmp.readBytes()
            try {
                OfflineDumps.assertValidForBytes(manifest, bytes, expectedBase)
            } catch (error: OfflineDumpException) {
                return@withContext when (error.code) {
                    "checksum_mismatch" ->
                        "The file failed its checksum. Your installed copy still works."
                    "unsupported_schema" ->
                        "This file needs a newer Hadithly. Update the app and try again."
                    "incompatible_pack" ->
                        "This translation does not match the installed Arabic file."
                    "missing_license", "unlicensed_source" ->
                        "This file's license could not be verified."
                    else -> "This file failed validation. Your installed copy still works."
                }
            } catch (_: Exception) {
                return@withContext "This file failed validation. Your installed copy still works."
            }
            val dir = versionDir(slug, download.kind, download.contentVersion, download.locale)
            val stageFailure: String? = try {
                var problem: String? = null
                if (download.kind == "base") {
                    val dump = json.decodeFromString<OfflineBaseDump>(bytes.decodeToString())
                    OfflineDumps.validateBaseDump(dump)
                    if (pendingAnchors(slug).isNotEmpty()) {
                        val ids = dump.hadiths.map { it.canonicalId }.toSet()
                        val missing = pendingAnchors(slug).filter { it !in ids }
                        if (missing.isNotEmpty()) {
                            dir.deleteRecursively()
                            problem = "__missing_anchors__:${missing.size}"
                        }
                    }
                } else {
                    val pack = json.decodeFromString<OfflineTranslationPack>(bytes.decodeToString())
                    OfflineDumps.validatePack(pack)
                    val baseVersion = record.stagedBase ?: record.activeBase
                    if (pack.baseContentVersion != baseVersion) {
                        problem = "__incompatible_pack__"
                    }
                }
                if (problem == null) {
                    val finalName = if (download.kind == "base") "dump.json" else "pack.json"
                    File(dir, finalName).delete()
                    if (!tmp.renameTo(File(dir, finalName))) {
                        tmp.copyTo(File(dir, finalName), overwrite = true)
                        tmp.delete()
                    }
                    stagedManifestFile(slug, download.kind, download.contentVersion, download.locale)
                        .writeText(json.encodeToString(OfflineManifest.serializer(), manifest))
                }
                problem
            } catch (_: Exception) {
                "This file failed validation. Your installed copy still works."
            }
            return@withContext stageFailure
        }
        when {
            failure == null -> {
                updateRecord(slug) { current ->
                    if (download.kind == "base") {
                        current.copy(stagedBase = download.contentVersion, download = null)
                    } else if (download.locale != null) {
                        current.copy(
                            stagedPacks = current.stagedPacks + (download.locale to download.contentVersion),
                            download = null,
                        )
                    } else {
                        current
                    }
                }
                activateStaged(slug)
            }
            failure.startsWith("__missing_anchors__:") -> {
                val count = failure.removePrefix("__missing_anchors__:").toIntOrNull() ?: 0
                updateRecord(slug) {
                    it.copy(
                        stagedBase = null,
                        download = it.download?.copy(
                            state = OfflineDownloadState.FAILED.wire,
                            reason = "The new file is missing $count of your saved hadiths. Your copy stays active.",
                        ),
                    )
                }
            }
            failure == "__incompatible_pack__" -> {
                updateRecord(slug) {
                    it.copy(
                        download = it.download?.copy(
                            state = OfflineDownloadState.FAILED.wire,
                            reason = "This translation does not match the installed Arabic file.",
                        ),
                    )
                }
                tmp.delete()
            }
            else -> {
                updateRecord(slug) {
                    it.copy(
                        download = it.download?.copy(
                            state = OfflineDownloadState.FAILED.wire,
                            reason = failure,
                        ),
                    )
                }
                tmp.delete()
            }
        }
    }

    fun setAnchorProvider(slug: String, provider: () -> Set<String>) {
        anchorProviders[slug] = provider
    }

    private fun pendingAnchors(slug: String): Set<String> =
        anchorProviders[slug]?.invoke() ?: emptySet()

    /**
     * Flips the active pointer to the staged version. The previous version
     * stays on disk for rollback; older generations are pruned.
     */
    fun activateStaged(slug: String) {
        val record = recordFor(slug)
        val hadStaged = record.stagedBase != null || record.stagedPacks.isNotEmpty()
        val previousBase = record.activeBase
        var next = record
        val staged = record.stagedBase
        if (staged != null) {
            val generatedAt = bases[slug]?.takeIf { it.contentVersion == staged }?.generatedAt
                ?: stagedManifest(slug, "base", staged, null)?.generatedAt
            next = next.copy(activeBase = staged, activeBaseGeneratedAt = generatedAt, stagedBase = null)
            dumpCache.remove(slug)
        }
        if (record.stagedPacks.isNotEmpty()) {
            next = next.copy(
                activePacks = next.activePacks + record.stagedPacks,
                stagedPacks = emptyMap(),
            )
            record.stagedPacks.keys.forEach { packCache.remove("$slug#$it") }
        }
        registry = registry.copy(collections = registry.collections + (slug to next))
        saveRegistry()
        val keep = buildSet {
            next.activeBase?.let { add(it) }
            if (previousBase != null && previousBase != next.activeBase) add(previousBase)
        }
        prune(slug, keep)
        if (hadStaged) {
            analytics?.record(if (previousBase == null) com.hadithly.app.core.analytics.AnalyticsMetric.offlineActivationResultActivated else com.hadithly.app.core.analytics.AnalyticsMetric.offlineActivationResultUpdated)
            analytics?.flush()
        }
        changed()
    }

    /**
     * Rollback is a pointer flip back to the retained previous version.
     * Used when post-activation reads prove the new bytes unreadable.
     */
    fun rollback(slug: String, version: String): Boolean {
        val dumpFile = File(versionDir(slug, "base", version, null), "dump.json")
        if (!dumpFile.isFile) return false
        updateRecord(slug) { it.copy(activeBase = version, stagedBase = null) }
        dumpCache.remove(slug)
        return true
    }

    private fun prune(slug: String, keep: Set<String>) {
        val baseRoot = File(File(root, slug), "base")
        val keepDirs = keep.map(OfflineModels::directoryName).toSet()
        baseRoot.listFiles()?.filter { it.isDirectory && it.name !in keepDirs }
            ?.forEach { it.deleteRecursively() }
    }

    // MARK: - Reader fallback (offline-tolerant, read-first)

    fun loadActiveDump(slug: String): OfflineBaseDump? {
        dumpCache[slug]?.let { return it }
        val version = recordFor(slug).activeBase ?: return null
        val file = File(versionDir(slug, "base", version, null), "dump.json")
        if (!file.isFile) return null
        val dump = runCatching { json.decodeFromString<OfflineBaseDump>(file.readText()) }.getOrNull()
            ?: return null
        dumpCache[slug] = dump
        return dump
    }

    fun loadActivePack(slug: String, locale: String): OfflineTranslationPack? {
        val key = "$slug#$locale"
        packCache[key]?.let { return it }
        val version = recordFor(slug).activePacks[locale] ?: return null
        val file = File(versionDir(slug, "pack", version, locale), "pack.json")
        if (!file.isFile) return null
        val pack = runCatching {
            json.decodeFromString<OfflineTranslationPack>(file.readText())
        }.getOrNull() ?: return null
        packCache[key] = pack
        return pack
    }

    fun translation(canonicalId: String, slug: String, locale: String): String? =
        // Version 1 packs have no per-entry rights or revocation identity.
        null

    fun offlineHadith(canonicalId: String, slug: String, locale: String?): ReaderHadith? {
        val dump = loadActiveDump(slug) ?: return null
        val row = dump.hadiths.firstOrNull { it.canonicalId == canonicalId } ?: return null
        return readerHadith(row, locale?.let { translation(canonicalId, slug, it) })
    }

    private fun readerHadith(row: OfflineDumpHadith, packContent: String?): ReaderHadith =
        ReaderHadith(
            _id = row.canonicalId,
            provider = row.provider,
            canonicalId = row.canonicalId,
            providerHadithId = row.providerHadithId,
            collectionSlug = row.collectionSlug,
            volumeId = row.volumeId,
            chapterId = row.chapterId,
            arabicText = row.arabicText,
            englishText = packContent ?: row.englishText,
            narrator = row.narrator,
            narratorAr = row.narratorAr,
            referenceDisplay = row.referenceDisplay,
            collectionName = row.collectionName,
            chapterName = row.chapterName,
            authenticity = AuthenticityClaim(
                kind = row.authenticity.kind,
                normalizedGrade = row.authenticity.normalizedGrade,
                claimScope = row.authenticity.claimScope,
                sourceLabel = row.authenticity.sourceLabel,
                sourceName = row.authenticity.sourceName,
                sourceUrl = row.authenticity.sourceUrl,
                verificationMethod = row.authenticity.verificationMethod,
            ),
        )

    /**
     * Offline page with the same content-sized chunking as the server, over
     * dotted-id-ordered volume hadiths. R1 positions restore by semantic
     * anchor, so approximate page numbers never strand the reader.
     */
    fun offlinePage(slug: String, volumeId: String?, page: Int, locale: String?): ReaderPageResult? {
        val dump = loadActiveDump(slug) ?: return null
        val rows = dump.hadiths
            .filter { volumeId == null || it.volumeId == volumeId }
            .sortedWith { left, right ->
                OfflineModels.compareProviderHadithIds(left.providerHadithId, right.providerHadithId)
            }
        if (rows.isEmpty()) return null
        val chunks = OfflineModels.chunkHadiths(
            rows,
            arabicText = { it.arabicText },
            englishText = { it.englishText },
            narrator = { it.narrator },
            narratorAr = { it.narratorAr },
        )
        val index = page.coerceIn(0, chunks.size - 1)
        val items = chunks[index].map { row ->
            readerHadith(row, locale?.let { translation(row.canonicalId, slug, it) })
        }
        // contentVersion/pageKey stay "legacy": offline chunking is
        // approximate (not the server's cv1 versions), and restoration
        // resolves semantically through the exact canonical anchor.
        // Claiming the dump's od1: version here crashes position saves
        // against the R1 wire contract on device.
        return ReaderPageResult(
            items = items,
            page = (index + 1).toDouble(),
            pageSize = items.size.toDouble(),
            totalPages = chunks.size.toDouble(),
            hasMore = index + 1 < chunks.size,
            contentVersion = "legacy",
            paginationVersion = 1.0,
            pageKey = "legacy",
        )
    }

    /**
     * Outline synthesized from the dump's own volume ids and counts. Titles
     * fall back to the volume id: Hadithly never invents chapter names, and
     * offline volume titles are no exception.
     */
    fun offlineOutline(slug: String): CollectionOutlineResult? {
        val dump = loadActiveDump(slug) ?: return null
        val counts = linkedMapOf<String, Int>()
        for (row in dump.hadiths) {
            val volume = row.volumeId ?: "1"
            counts[volume] = (counts[volume] ?: 0) + 1
        }
        return CollectionOutlineResult(
            volumes = counts.map { (volume, count) ->
                OutlineVolume(
                    volumeId = volume,
                    title = volume,
                    firstChapterTitle = null,
                    hadithCount = count.toDouble(),
                    chapters = emptyList(),
                )
            },
        )
    }

    fun isCollectionActive(slug: String): Boolean = recordFor(slug).activeBase != null
}
