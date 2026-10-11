package com.hadithly.app

import com.hadithly.app.core.offline.OfflineAuthenticity
import com.hadithly.app.core.offline.OfflineBaseDump
import com.hadithly.app.core.offline.OfflineDownloadRecord
import com.hadithly.app.core.offline.OfflineDownloadState
import com.hadithly.app.core.offline.OfflineDownloadTransport
import com.hadithly.app.core.offline.OfflineDumps
import com.hadithly.app.core.offline.OfflineDumpHadith
import com.hadithly.app.core.offline.OfflineEnqueueResult
import com.hadithly.app.core.offline.OfflineLicenseRecord
import com.hadithly.app.core.offline.OfflineLicenseTerms
import com.hadithly.app.core.offline.OfflineCollectionStatus
import com.hadithly.app.core.offline.OfflineManifest
import com.hadithly.app.core.offline.OfflineManifestsResponse
import com.hadithly.app.core.offline.OfflineModels
import com.hadithly.app.core.offline.OfflinePackEntry
import com.hadithly.app.core.offline.OfflineStore
import com.hadithly.app.core.offline.OfflineTranslationPack
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.file.Files

/**
 * O2 gate: fault-injection tests proving interruption or corruption never
 * replaces usable data. Every test drives the real OfflineStore against a
 * temporary directory with a fake transport and fake manifests. Mirrors the
 * iOS `OfflineStoreTests`.
 */
class OfflineStoreTest {

    private val tempDirs = mutableListOf<File>()

    @After
    fun tearDown() {
        tempDirs.forEach { it.deleteRecursively() }
        tempDirs.clear()
    }

    private val license = OfflineLicenseRecord(
        sourceKey = "sunnah_now",
        sourceName = "Sunnah.now",
        sourceUrl = "https://sunnah.now",
        terms = OfflineLicenseTerms(
            kind = "verified",
            licenseName = "Sunnah.now early-access data grant",
            licenseUrl = "https://github.com/sunnah-now/database",
            permitsDisplay = true,
            permitsRedistribution = false,
            permitsOfflineDistribution = true,
            verifiedAt = 1700000000000.0,
        ),
    )

    private fun hadith(id: String, tag: String) = OfflineDumpHadith(
        canonicalId = "sunnah_now:bukhari:$id",
        provider = "sunnah_now",
        collectionSlug = "bukhari",
        providerHadithId = id,
        volumeId = "2",
        arabicText = "نص $id · $tag",
        referenceDisplay = "Sahih al-Bukhari · Hadith $id",
        collectionName = "Sahih al-Bukhari",
        authenticity = OfflineAuthenticity(
            kind = "collection_scope",
            normalizedGrade = "sahih",
            claimScope = "collection",
            sourceLabel = "Documented Sahih collection",
            sourceName = "Sunnah.now",
            sourceUrl = "https://sunnah.now",
            verificationMethod = "manual_collection_mapping",
        ),
    )

    private val json = Json { ignoreUnknownKeys = true }

    private fun baseBytes(
        versionHex: String,
        ids: List<String>,
        generatedAt: Double = 1700000000000.0,
        slug: String = "bukhari",
    ): ByteArray {
        val name = if (slug == "bukhari") "Sahih al-Bukhari" else slug
        val dump = OfflineBaseDump(
            format = OfflineDumps.BASE_FORMAT,
            schemaVersion = 1.0,
            collectionSlug = slug,
            collectionName = name,
            contentVersion = "od1:$versionHex",
            generatedAt = generatedAt,
            license = license,
            hadiths = ids.map {
                hadith(it, versionHex.take(4)).copy(
                    canonicalId = "sunnah_now:$slug:$it",
                    collectionSlug = slug,
                    collectionName = name,
                    referenceDisplay = "$name · Hadith $it",
                )
            },
        )
        return json.encodeToString(OfflineBaseDump.serializer(), dump).toByteArray(Charsets.UTF_8)
    }

    private fun manifest(
        versionHex: String,
        bytes: ByteArray,
        generatedAt: Double = 1700000000000.0,
        minAppVersion: String = "0.1.0",
        slug: String = "bukhari",
    ) = OfflineManifest(
        format = OfflineDumps.MANIFEST_FORMAT,
        schemaVersion = 1.0,
        kind = "base",
        collectionSlug = slug,
        contentVersion = "od1:$versionHex",
        byteSize = bytes.size.toDouble(),
        sha256 = OfflineDumps.sha256Hex(bytes),
        minAppVersion = minAppVersion,
        generatedAt = generatedAt,
        license = license,
        compatiblePacks = emptyList(),
        downloadUrl = "https://example.invalid/$slug.json",
    )

    private class FakeTransport : OfflineDownloadTransport {
        var handler: (String) -> ByteArray = { ByteArray(0) }
        var gate: CompletableDeferred<Unit>? = null
        var cancelled = false
        override suspend fun downloadToFile(
            url: String,
            tmpFile: File,
            offset: Long,
            progress: (Double) -> Unit,
        ) {
            gate?.await()
            val bytes = handler(url)
            if (offset > 0) {
                java.io.FileOutputStream(tmpFile, true).use { it.write(bytes) }
            } else {
                tmpFile.writeBytes(bytes)
            }
            progress(1.0)
        }

        override fun cancel() {
            cancelled = true
        }
    }

    private class FakeManifests(var bases: List<OfflineManifest>, var packs: List<OfflineManifest> = emptyList())

    private fun makeStore(
        transport: FakeTransport = FakeTransport(),
        server: FakeManifests,
        anchors: Set<String> = emptySet(),
        scope: kotlinx.coroutines.CoroutineScope,
    ): Pair<OfflineStore, File> {
        val root = Files.createTempDirectory("offline-test").toFile()
        tempDirs.add(root)
        val store = OfflineStore(
            root = root,
            transport = transport,
            appVersion = "0.1.0",
            manifestProvider = { OfflineManifestsResponse(server.bases, server.packs) },
            ioScope = scope,
        )
        store.setAnchorProvider("bukhari") { anchors }
        store.noteManifests(server.bases, server.packs)
        return store to root
    }

    private fun hex(char: Char) = char.toString().repeat(64)

    private suspend fun waitUntil(timeoutMs: Long = 10_000, condition: () -> Boolean) {
        withTimeout(timeoutMs) {
            while (!condition()) delay(25)
        }
    }

    // MARK: - Happy path

    @Test
    fun downloadVerifiesAndActivates() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1", "2"))
        val server = FakeManifests(listOf(manifest(hex('a'), bytes)))
        val transport = FakeTransport()
        transport.handler = { bytes }
        val (store, _) = makeStore(transport, server, scope = this)

        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)
        assertNotNull(store.loadActiveDump("bukhari"))
        val status = store.status("bukhari", null)
        assertTrue(status is OfflineCollectionStatus.Active)
        assertEquals("od1:${hex('a')}", (status as OfflineCollectionStatus.Active).version)
        assertEquals(OfflineEnqueueResult.AlreadyActive, store.enqueue("bukhari", "base", null))
    }

    // MARK: - Corruption never replaces usable data

    @Test
    fun corruptUpdateKeepsPreviousVersionActive() = runBlocking {
        val v1 = baseBytes(hex('a'), listOf("1", "2"))
        val server = FakeManifests(listOf(manifest(hex('a'), v1)))
        val transport = FakeTransport()
        transport.handler = { v1 }
        val (store, _) = makeStore(
            transport, server,
            anchors = setOf("sunnah_now:bukhari:1", "sunnah_now:bukhari:2"),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        )
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)

        // v2 arrives with one flipped byte: same size, wrong hash.
        val cleanV2 = baseBytes(hex('b'), listOf("1", "2"), generatedAt = 1700000100000.0)
        val corruptV2 = cleanV2.copyOf().also { it[it.size - 20] = (it[it.size - 20].toInt() xor 0xFF).toByte() }
        transport.handler = { corruptV2 }
        val m2 = manifest(hex('b'), cleanV2, generatedAt = 1700000100000.0)
        server.bases = listOf(m2)
        store.noteManifests(listOf(m2))
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").download?.state == OfflineDownloadState.FAILED.wire }
        val status = store.status("bukhari", null)
        assertTrue(status is OfflineCollectionStatus.Failed)
        assertTrue((status as OfflineCollectionStatus.Failed).reason.contains("checksum"))
        // Previous version is still active and still reads.
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)
        assertEquals(2, store.loadActiveDump("bukhari")?.hadiths?.size)
    }

    @Test
    fun replacementMissingSavedAnchorsIsRefused() = runBlocking {
        val v1 = baseBytes(hex('a'), listOf("1", "2"))
        val server = FakeManifests(listOf(manifest(hex('a'), v1)))
        val transport = FakeTransport()
        transport.handler = { v1 }
        val (store, _) = makeStore(
            transport, server,
            anchors = setOf("sunnah_now:bukhari:1", "sunnah_now:bukhari:2"),
            scope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        )
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }

        // v2 is valid but drops hadith 2, which the user saved.
        val v2 = baseBytes(hex('c'), listOf("1", "3"), generatedAt = 1700000100000.0)
        transport.handler = { v2 }
        val m2 = manifest(hex('c'), v2, generatedAt = 1700000100000.0)
        server.bases = listOf(m2)
        store.noteManifests(listOf(m2))
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").download?.state == OfflineDownloadState.FAILED.wire }
        assertTrue(store.status("bukhari", null) is OfflineCollectionStatus.Failed)
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)
        assertEquals(2, store.loadActiveDump("bukhari")?.hadiths?.size)
    }

    @Test
    fun incompatiblePackIsRefused() = runBlocking {
        val v1 = baseBytes(hex('a'), listOf("1"))
        val server = FakeManifests(listOf(manifest(hex('a'), v1)))
        val transport = FakeTransport()
        transport.handler = { v1 }
        val (store, _) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }

        val pack = OfflineTranslationPack(
            format = OfflineDumps.PACK_FORMAT,
            schemaVersion = 1.0,
            collectionSlug = "bukhari",
            language = "ur",
            baseContentVersion = "od1:${hex('b')}", // targets a base we do not have
            contentVersion = "od1:${hex('d')}",
            generatedAt = 1700000100000.0,
            license = license,
            entries = listOf(
                OfflinePackEntry("sunnah_now:bukhari:1", "ur", "ترجمہ", "official", "Sunnah.now"),
            ),
        )
        val packBytes = json.encodeToString(OfflineTranslationPack.serializer(), pack)
            .toByteArray(Charsets.UTF_8)
        val packManifest = OfflineManifest(
            format = OfflineDumps.MANIFEST_FORMAT,
            schemaVersion = 1.0,
            kind = "pack",
            collectionSlug = "bukhari",
            locale = "ur",
            contentVersion = "od1:${hex('d')}",
            baseContentVersion = "od1:${hex('b')}",
            byteSize = packBytes.size.toDouble(),
            sha256 = OfflineDumps.sha256Hex(packBytes),
            minAppVersion = "0.1.0",
            generatedAt = 1700000100000.0,
            license = license,
            compatiblePacks = emptyList(),
            downloadUrl = "https://example.invalid/pack.json",
        )
        transport.handler = { packBytes }
        server.packs = listOf(packManifest)
        store.noteManifests(server.bases, listOf(packManifest))
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "pack", "ur"))
        waitUntil { store.recordFor("bukhari").download?.state == OfflineDownloadState.FAILED.wire }
        assertTrue(store.status("bukhari", "ur") is OfflineCollectionStatus.Failed)
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)
        assertNull(store.recordFor("bukhari").activePacks["ur"])
    }

    @Test
    fun installedVersionOnePackCannotBypassRevocationIdentity() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1"))
        val base = manifest(hex('a'), bytes)
        val transport = FakeTransport().apply { handler = { bytes } }
        val server = FakeManifests(listOf(base))
        val (store, _) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }
        val pack = OfflineTranslationPack(OfflineDumps.PACK_FORMAT, 1.0, "bukhari", "ur", "od1:${hex('a')}", "od1:${hex('d')}", 1700000100000.0, license,
            listOf(OfflinePackEntry("sunnah_now:bukhari:1", "ur", "Unvalidated legacy community text", "community", "Community")))
        val packBytes = json.encodeToString(OfflineTranslationPack.serializer(), pack).toByteArray()
        val packManifest = OfflineManifest(OfflineDumps.MANIFEST_FORMAT, 1.0, "pack", "bukhari", "ur", "od1:${hex('d')}", "od1:${hex('a')}", packBytes.size.toDouble(), OfflineDumps.sha256Hex(packBytes), "0.1.0", 1700000100000.0, license, emptyList(), "https://example.invalid/pack.json")
        transport.handler = { packBytes }
        store.noteManifests(listOf(base), listOf(packManifest))
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "pack", "ur"))
        waitUntil { store.recordFor("bukhari").activePacks["ur"] != null }
        assertNotNull(store.loadActivePack("bukhari", "ur"))
        assertNull(store.translation("sunnah_now:bukhari:1", "bukhari", "ur"))
        val reader = store.offlineHadith("sunnah_now:bukhari:1", "bukhari", "ur")
        assertNotNull(reader); assertTrue(reader!!.arabicText.isNotEmpty())
        assertFalse(reader.englishText == "Unvalidated legacy community text")
    }

    @Test
    fun twoCollectionsDownloadConcurrently() = runBlocking {
        // Regression: one shared run job meant starting a second collection
        // cancelled the first, so only one could download.
        val bytesBukhari = baseBytes(hex('a'), listOf("1"))
        val bytesMuslim = baseBytes(hex('a'), listOf("1"), slug = "muslim")
        val server = FakeManifests(
            listOf(
                manifest(hex('a'), bytesBukhari),
                manifest(hex('a'), bytesMuslim, slug = "muslim"),
            ),
        )
        val transport = FakeTransport()
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        transport.handler = { url -> if (url.contains("muslim")) bytesMuslim else bytesBukhari }
        val (store, _) = makeStore(transport, server, scope = this)

        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("muslim", "base", null))
        waitUntil { store.recordFor("bukhari").download?.state == OfflineDownloadState.DOWNLOADING.wire }
        waitUntil { store.recordFor("muslim").download?.state == OfflineDownloadState.DOWNLOADING.wire }

        gate.complete(Unit)
        waitUntil { store.recordFor("bukhari").activeBase != null }
        waitUntil { store.recordFor("muslim").activeBase != null }
        assertEquals(1, store.loadActiveDump("bukhari")?.hadiths?.size)
        assertEquals(1, store.loadActiveDump("muslim")?.hadiths?.size)
    }

    @Test
    fun offlinePagesCarryLegacyWireValues() = runBlocking {
        // Regression (device crash in saveProgress): offline pages claimed
        // the dump's od1: version and an "offline-…" page key, which the R1
        // ReadingPosition require() rejects. Offline chunking is
        // approximate, so pages carry "legacy" and restoration resolves by
        // semantic anchor. Building the position exactly like saveProgress
        // does must not throw.
        val bytes = baseBytes(hex('a'), listOf("1", "2"))
        val server = FakeManifests(listOf(manifest(hex('a'), bytes)))
        val transport = FakeTransport()
        transport.handler = { bytes }
        val (store, _) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }

        val page = store.offlinePage("bukhari", "2", 0, null)
        assertNotNull(page)
        assertEquals("legacy", page!!.contentVersion)
        assertEquals("legacy", page.pageKey)
        // Same construction as ReaderViewModel.saveProgress.
        val anchor = page.items.first()
        com.hadithly.app.core.data.ReadingPosition(
            anchor = com.hadithly.app.core.data.ReadingPositionAnchor(
                provider = anchor.provider,
                collectionSlug = anchor.collectionSlug,
                providerHadithId = anchor.providerHadithId,
            ),
            contentVersion = page.contentVersion,
            volumeId = anchor.volumeId ?: "2",
            chapterId = anchor.chapterId,
            pageKey = page.pageKey,
            displayPageIndex = 1.0,
            rawPageOffset = 0.0,
            normalizedOffset = 0.0,
            layoutSignature = "legacy",
            updatedAt = 1700000000000.0,
        )
        Unit
    }

    // MARK: - Interruption and process death

    @Test
    fun pauseThenRetryCompletesWithoutClobbering() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1"))
        val server = FakeManifests(listOf(manifest(hex('a'), bytes)))
        val transport = FakeTransport()
        val gate = CompletableDeferred<Unit>()
        transport.gate = gate
        transport.handler = { bytes }
        val (store, _) = makeStore(transport, server, scope = this)

        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").download?.state == OfflineDownloadState.DOWNLOADING.wire }
        assertEquals(
            OfflineDownloadState.DOWNLOADING.wire,
            store.recordFor("bukhari").download?.state,
        )
        // Pause cancels the suspended run; an immediate retry must win over
        // the stale run's resume (the iOS-found generation-guard regression).
        store.pause("bukhari")
        assertEquals(
            OfflineDownloadState.PAUSED.wire,
            store.recordFor("bukhari").download?.state,
        )
        assertNull(store.recordFor("bukhari").activeBase)
        store.retry("bukhari")
        gate.complete(Unit)
        waitUntil { store.recordFor("bukhari").activeBase != null }
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)
        assertEquals(1, store.loadActiveDump("bukhari")?.hadiths?.size)
    }

    @Test
    fun freshStoreOverSameRootKeepsActiveVersion() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1"))
        val server = FakeManifests(listOf(manifest(hex('a'), bytes)))
        val transport = FakeTransport()
        transport.handler = { bytes }
        val (store, root) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }
        assertEquals("od1:${hex('a')}", store.recordFor("bukhari").activeBase)

        // Simulate process death: a fresh store over the same root.
        val store2 = OfflineStore(
            root = root,
            transport = FakeTransport(),
            appVersion = "0.1.0",
            manifestProvider = { OfflineManifestsResponse(server.bases) },
            ioScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        )
        assertEquals("od1:${hex('a')}", store2.recordFor("bukhari").activeBase)
        assertEquals(1, store2.loadActiveDump("bukhari")?.hadiths?.size)
    }

    // MARK: - Refusals

    @Test
    fun providerRollbackIsBlocked() = runBlocking {
        val v1 = baseBytes(hex('a'), listOf("1"), generatedAt = 1700000100000.0)
        val server = FakeManifests(listOf(manifest(hex('a'), v1, generatedAt = 1700000100000.0)))
        val transport = FakeTransport()
        transport.handler = { v1 }
        val (store, _) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }

        val older = baseBytes(hex('d'), listOf("1"), generatedAt = 1700000000000.0)
        val mOld = manifest(hex('d'), older, generatedAt = 1700000000000.0)
        server.bases = listOf(mOld)
        store.noteManifests(listOf(mOld))
        val result = store.enqueue("bukhari", "base", null)
        assertTrue(result is OfflineEnqueueResult.Blocked)
        assertTrue((result as OfflineEnqueueResult.Blocked).reason.contains("older"))
        assertNull(store.recordFor("bukhari").download)
    }

    @Test
    fun appUpdateRequiredBlocksDownload() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1"))
        val server = FakeManifests(
            listOf(manifest(hex('a'), bytes, minAppVersion = "99.0.0")),
        )
        val (store, _) = makeStore(transport = FakeTransport(), server = server, scope = this)
        val result = store.enqueue("bukhari", "base", null)
        assertTrue(result is OfflineEnqueueResult.Blocked)
        assertTrue((result as OfflineEnqueueResult.Blocked).reason.contains("Update Hadithly"))
        val status = store.status("bukhari", null)
        assertTrue(status is OfflineCollectionStatus.AppUpdateRequired)
        assertEquals("99.0.0", (status as OfflineCollectionStatus.AppUpdateRequired).minVersion)
    }

    @Test
    fun deleteRemovesFilesOnly() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1"))
        val server = FakeManifests(listOf(manifest(hex('a'), bytes)))
        val transport = FakeTransport()
        transport.handler = { bytes }
        val (store, root) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }

        store.delete("bukhari")
        assertNull(store.recordFor("bukhari").activeBase)
        assertFalse(File(root, "bukhari").exists())
        assertTrue(store.status("bukhari", null) is OfflineCollectionStatus.NotInstalled)
    }

    // MARK: - Pure domain

    @Test
    fun chunkingMirrorsServerPaging() {
        val rows = (1..11).map { "x".repeat(100) }
        val pages = OfflineModels.chunkHadiths(
            rows,
            arabicText = { it },
            englishText = { null },
            narrator = { null },
            narratorAr = { null },
        )
        assertEquals(2, pages.size)
        assertEquals(10, pages[0].size)
        assertEquals(1, pages[1].size)

        val long = listOf("y".repeat(5100), "z".repeat(200))
        assertEquals(
            2,
            OfflineModels.chunkHadiths(
                long,
                arabicText = { it },
                englishText = { null },
                narrator = { null },
                narratorAr = { null },
            ).size,
        )
    }

    @Test
    fun dottedIdOrder() {
        assertTrue(OfflineModels.compareProviderHadithIds("2", "10") < 0)
        assertTrue(OfflineModels.compareProviderHadithIds("4.5", "10") < 0)
        assertTrue(OfflineModels.compareProviderHadithIds("10", "4.5") > 0)
    }

    @Test
    fun corruptRegistryRebuildsFromDisk() = runBlocking {
        val bytes = baseBytes(hex('a'), listOf("1", "2"))
        val server = FakeManifests(listOf(manifest(hex('a'), bytes)))
        val transport = FakeTransport()
        transport.handler = { bytes }
        val (store, root) = makeStore(transport, server, scope = this)
        assertEquals(OfflineEnqueueResult.Started, store.enqueue("bukhari", "base", null))
        waitUntil { store.recordFor("bukhari").activeBase != null }

        File(root, "registry.json").writeText("corrupt")
        val rebuilt = OfflineStore(
            root = root,
            transport = FakeTransport(),
            appVersion = "0.1.0",
            manifestProvider = { OfflineManifestsResponse(server.bases) },
            ioScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
        )
        assertEquals("od1:${hex('a')}", rebuilt.recordFor("bukhari").activeBase)
    }
}
