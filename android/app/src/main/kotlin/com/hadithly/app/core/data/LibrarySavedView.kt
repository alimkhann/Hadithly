package com.hadithly.app.core.data

import kotlinx.serialization.Serializable
import java.text.Normalizer
import java.util.Locale

@Serializable
data class LibrarySavedViewItem(val value: SavedPrivateItem, val collectionSlug: String? = null, val removedBy: String? = null) {
    val mask: Int get() = (if (value.bookmarkCreatedAt != null) 1 else 0) or (if (value.favoriteCreatedAt != null) 2 else 0) or (if (value.noteContent != null) 4 else 0)
    fun validate() {
        LibrarySavedPolicy.validate(value)
        if (collectionSlug != null && (collectionSlug.isEmpty() || collectionSlug.toByteArray().size > 128) || removedBy != null && (removedBy.isEmpty() || removedBy.toByteArray().size > 128)) throw LibrarySyncFailure.InvalidReceipt
    }
}
@Serializable
enum class LibrarySavedViewFacet { All, Bookmarks, Favorites, Notes }
@Serializable
sealed interface LibrarySavedViewFolderSelection {
    @Serializable data object All : LibrarySavedViewFolderSelection
    @Serializable data object Unfiled : LibrarySavedViewFolderSelection
    @Serializable data class Folder(val id: String) : LibrarySavedViewFolderSelection
}
@Serializable
data class LibrarySavedViewSelection(val facet: LibrarySavedViewFacet = LibrarySavedViewFacet.All, val folder: LibrarySavedViewFolderSelection = LibrarySavedViewFolderSelection.All, val collection: String? = null) {
    fun validate() {
        val folderID = (folder as? LibrarySavedViewFolderSelection.Folder)?.id
        for (value in listOfNotNull(collection, folderID)) if (value.isEmpty() || value.toByteArray().size > 128) throw LibrarySyncFailure.InvalidChange
    }
}
@Serializable
data class LibrarySavedViewIdentity(val owner: LibrarySyncOwner, val epoch: String, val generation: String) {
    @kotlinx.serialization.Transient val scope: String = LibrarySavedLease(owner, epoch, generation).key
    @kotlinx.serialization.Transient val key: String = LibrarySavedLease(owner, epoch, generation).collection + ":view"
    fun itemKey(id: String) = key + ":i:" + LibraryOutcomeBinding.hash(listOf(id))
    fun folderKey(id: String) = key + ":f:" + LibraryOutcomeBinding.hash(listOf(id))
    fun queryPrefix(selection: LibrarySavedViewSelection, unresolved: Boolean = false): String {
        val folder = when (val value = selection.folder) { LibrarySavedViewFolderSelection.All -> listOf("all"); LibrarySavedViewFolderSelection.Unfiled -> listOf("unfiled"); is LibrarySavedViewFolderSelection.Folder -> listOf("folder", value.id) }
        return key + ":q:" + LibraryOutcomeBinding.hash(listOf(selection.facet.name) + folder + when { unresolved -> listOf("unresolved"); selection.collection != null -> listOf("collection", selection.collection); else -> listOf("all") }) + ":"
    }
    val folderPrefix get() = key + ":d:"
    fun namePrefix(name: String) = key + ":n:" + LibraryOutcomeBinding.hash(listOf(LibrarySavedViewPolicy.nameKey(name))) + ":"
}
@Serializable
data class LibrarySavedViewStamp(val identity: LibrarySavedViewIdentity, val serial: Long)
data class LibrarySavedViewTicket internal constructor(internal val stamp: LibrarySavedViewStamp, internal val selection: LibrarySavedViewSelection, internal val after: String)
data class LibrarySavedViewPage(val stamp: LibrarySavedViewStamp, val items: List<LibrarySavedViewItem>, val next: LibrarySavedViewTicket?, val unresolvedCoverage: Boolean)

object LibrarySavedViewPolicy {
    private val nameTrim = setOf('\u0009','\u000A','\u000B','\u000C','\u000D','\u0020','\u00A0','\u1680','\u2000','\u2001','\u2002','\u2003','\u2004','\u2005','\u2006','\u2007','\u2008','\u2009','\u200A','\u2028','\u2029','\u202F','\u205F','\u3000','\uFEFF')
    fun nameKey(name: String): String = Normalizer.normalize(name.trim { it in nameTrim }, Normalizer.Form.NFC).lowercase(Locale.ROOT)
    private fun bytesKey(value: String) = value.toByteArray(Charsets.UTF_8).joinToString("") { "%02x".format(it) }
    private fun timeKey(value: Double, descending: Boolean): String {
        if (!value.isFinite() || value < 0) throw LibrarySyncFailure.InvalidReceipt
        val bits = (if (value == 0.0) 0.0 else value).toRawBits()
        return (if (descending) bits.inv() else bits).toULong().toString(16).padStart(16, '0')
    }
    fun rank(item: SavedPrivateItem) = timeKey(item.updatedAt, true) + ":" + bytesKey(item.hadithId)
    fun folderRank(folder: SyncFolderRow) = timeKey(folder.createdAt, false) + ":" + bytesKey(folder._id)
    fun indexKeys(identity: LibrarySavedViewIdentity, item: LibrarySavedViewItem): Set<String> {
        item.validate(); if (item.mask == 0) return emptySet()
        val facets = listOf(LibrarySavedViewFacet.All) + listOfNotNull(if (item.mask and 1 != 0) LibrarySavedViewFacet.Bookmarks else null, if (item.mask and 2 != 0) LibrarySavedViewFacet.Favorites else null, if (item.mask and 4 != 0) LibrarySavedViewFacet.Notes else null)
        val folders = listOf(LibrarySavedViewFolderSelection.All, item.value.folderId?.let { LibrarySavedViewFolderSelection.Folder(it) } ?: LibrarySavedViewFolderSelection.Unfiled)
        return facets.flatMap { facet -> folders.flatMap { folder ->
            val global = LibrarySavedViewSelection(facet, folder)
            listOf(identity.queryPrefix(global) + rank(item.value), if (item.collectionSlug == null) identity.queryPrefix(global, true) + rank(item.value) else identity.queryPrefix(global.copy(collection = item.collectionSlug)) + rank(item.value))
        } }.toSet()
    }
    fun matches(item: LibrarySavedViewItem, selection: LibrarySavedViewSelection): Boolean {
        item.validate()
        val facet = when (selection.facet) { LibrarySavedViewFacet.All -> item.mask != 0; LibrarySavedViewFacet.Bookmarks -> item.mask and 1 != 0; LibrarySavedViewFacet.Favorites -> item.mask and 2 != 0; LibrarySavedViewFacet.Notes -> item.mask and 4 != 0 }
        val folder = when (val value = selection.folder) { LibrarySavedViewFolderSelection.All -> true; LibrarySavedViewFolderSelection.Unfiled -> item.value.folderId == null; is LibrarySavedViewFolderSelection.Folder -> item.value.folderId == value.id }
        return facet && folder && (selection.collection == null || item.collectionSlug == selection.collection)
    }
    fun target(command: SyncCommand): String? = when (command) {
        is SyncCommand.BookmarkAdd -> command.hadithId; is SyncCommand.BookmarkRemove -> command.hadithId
        is SyncCommand.FavoriteAdd -> command.hadithId; is SyncCommand.FavoriteRemove -> command.hadithId
        is SyncCommand.NotePut -> command.hadithId; is SyncCommand.NoteRemove -> command.hadithId
        is SyncCommand.MembershipPut -> command.hadithId; is SyncCommand.FacetRestore -> command.hadithId
        is SyncCommand.FolderCreate, is SyncCommand.FolderDelete, is SyncCommand.FolderRestore, is SyncCommand.PositionPut, is SyncCommand.LegacyPositionPut -> null
    }
    fun point(current: LibrarySavedViewItem?, change: LibraryLocalChange, outcome: SyncOutcome?, mappings: Map<String, String>, route: String? = change.source.reference?.takeIf { it.hadithId == target(change.operation.command) }?.collectionSlug?.takeIf { it.isNotEmpty() }): LibrarySavedViewItem? {
        val command = change.operation.command; val target = target(command) ?: throw LibrarySyncFailure.InvalidChange
        if (current != null && current.value.hadithId != target) throw LibrarySyncFailure.OwnerMismatch
        val at = change.operation.at
        var item = current ?: LibrarySavedViewItem(SavedPrivateItem(target, at, at), route)
        val value = item.value
        fun folder(reference: SyncFolderReference): String? = when (reference) { SyncFolderReference.None -> null; is SyncFolderReference.Server -> reference.id; is SyncFolderReference.Local -> mappings[reference.key] ?: "local:${reference.key}" }
        item = when (command) {
            is SyncCommand.BookmarkAdd -> item.copy(value = value.copy(bookmarkCreatedAt = minOf(value.bookmarkCreatedAt ?: command.createdAt, command.createdAt), updatedAt = maxOf(value.updatedAt, at)))
            is SyncCommand.FavoriteAdd -> item.copy(value = value.copy(favoriteCreatedAt = minOf(value.favoriteCreatedAt ?: command.createdAt, command.createdAt), updatedAt = maxOf(value.updatedAt, at)))
            is SyncCommand.NotePut -> item.copy(value = value.copy(noteContent = command.content, noteCreatedAt = value.noteCreatedAt ?: command.createdAt, noteUpdatedAt = command.updatedAt, updatedAt = maxOf(value.updatedAt, command.updatedAt)))
            is SyncCommand.BookmarkRemove -> if (current == null) return null else item.copy(value = value.copy(bookmarkCreatedAt = null, updatedAt = maxOf(value.updatedAt, at)))
            is SyncCommand.FavoriteRemove -> if (current == null) return null else item.copy(value = value.copy(favoriteCreatedAt = null, updatedAt = maxOf(value.updatedAt, at)))
            is SyncCommand.NoteRemove -> if (current == null) return null else item.copy(value = value.copy(noteContent = null, noteCreatedAt = null, noteUpdatedAt = null, updatedAt = maxOf(value.updatedAt, at)))
            is SyncCommand.MembershipPut -> if (current == null || command.mode == "claim_if_unset" && outcome == null) return current else item.copy(value = value.copy(folderId = folder(command.folder), folderUpdatedAt = maxOf(value.folderUpdatedAt ?: 0.0, at), updatedAt = maxOf(value.updatedAt, at)), removedBy = null)
            is SyncCommand.FacetRestore -> when (val facet = command.value) {
                is SyncCommandFacetRestoreValue.Bookmark -> item.copy(value = value.copy(bookmarkCreatedAt = value.bookmarkCreatedAt ?: facet.createdAt, updatedAt = maxOf(value.updatedAt, at)))
                is SyncCommandFacetRestoreValue.Favorite -> item.copy(value = value.copy(favoriteCreatedAt = value.favoriteCreatedAt ?: facet.createdAt, updatedAt = maxOf(value.updatedAt, at)))
                is SyncCommandFacetRestoreValue.Note -> item.copy(value = value.copy(noteContent = facet.content, noteCreatedAt = facet.createdAt, noteUpdatedAt = at, updatedAt = maxOf(value.updatedAt, at)))
            }
            else -> throw LibrarySyncFailure.InvalidChange
        }
        if (item.mask == 0) item = item.copy(removedBy = null)
        item.validate(); return item
    }
    fun deleted(item: LibrarySavedViewItem, operation: String, at: Double) = item.copy(value = item.value.copy(folderId = null, folderUpdatedAt = maxOf(item.value.folderUpdatedAt ?: 0.0, at), updatedAt = maxOf(item.value.updatedAt, at)), removedBy = operation)
    fun restored(item: LibrarySavedViewItem, folder: String, at: Double) = item.copy(value = item.value.copy(folderId = folder, folderUpdatedAt = maxOf(item.value.folderUpdatedAt ?: 0.0, at), updatedAt = maxOf(item.value.updatedAt, at)), removedBy = null)
}

@Serializable
data class LibrarySavedViewSnapshot(val items: List<LibrarySavedViewItem>, val folders: List<SyncFolderRow>)
fun LibrarySavedViewPolicy.captureLegacy(state: LibraryPartitionState, owner: LibrarySyncOwner, observed: LibrarySavedObservation): LibrarySavedViewSnapshot {
    if (state.savedSnapshot?.ownerKey?.let { it != owner.key } == true) throw LibrarySyncFailure.OwnerMismatch
    val items = linkedMapOf<String, LibrarySavedViewItem>(); val folders = linkedMapOf<String, SyncFolderRow>()
    for (row in state.savedSnapshot?.items.orEmpty()) {
        val item = LibrarySavedViewItem(SavedPrivateItem(row.hadithId, row.createdAt, row.updatedAt, row.bookmarkCreatedAt, row.favoriteCreatedAt, row.noteContent, row.noteCreatedAt, row.noteUpdatedAt, row.folderId), row.hadith.takeIf { it._id == row.hadithId }?.collectionSlug?.takeIf { it.isNotEmpty() })
        item.validate(); if (items.put(row.hadithId, item) != null) throw LibrarySyncFailure.StoreUnavailable
    }
    for (row in state.savedSnapshot?.folders.orEmpty()) {
        LibrarySavedPolicy.validate(SavedFact.Folder(row._id, 0.0, row))
        if (folders.put(row._id, row) != null) throw LibrarySyncFailure.StoreUnavailable
    }
    fun folder(reference: SyncFolderReference): String? = when (reference) { SyncFolderReference.None -> null; is SyncFolderReference.Server -> reference.id; is SyncFolderReference.Local -> state.folderMappings[reference.key] ?: "local:${reference.key}" }
    val changes = state.confirmed.map { it.change to it.outcome } + state.projectedFrozenChanges(owner, observed).map { it to null } + state.pending.map { it to null }
    for ((change, outcome) in changes) {
        val at = change.operation.at
        val pointTarget = target(change.operation.command)
        if (pointTarget != null) { point(items[pointTarget], change, outcome, state.folderMappings)?.let { items[pointTarget] = it }; continue }
        when (val command = change.operation.command) {
            is SyncCommand.FolderCreate -> {
                val id = state.folderMappings[command.key] ?: "local:${command.key}"
                folders.putIfAbsent(id, SyncFolderRow(id, command.name, at))
            }
            is SyncCommand.FolderDelete -> folder(command.folder)?.let { id ->
                folders.remove(id)
                for ((target, item) in items.toMap()) if (item.value.folderId == id) items[target] = deleted(item, change.operation.id, at)
            }
            is SyncCommand.FolderRestore -> {
                val result = outcome as? SyncOutcome.FolderRestored
                val id = result?.folderId ?: folders.values.filter { nameKey(it.name) == nameKey(command.name) }.minByOrNull(::folderRank)?._id ?: state.folderMappings["restore:${command.deletionId}"] ?: "local:restore:${command.deletionId}"
                folders.putIfAbsent(id, SyncFolderRow(id, command.name, at))
                if (outcome == null && command.hadithIds.isEmpty()) {
                    for ((target, item) in items.toMap()) if (item.removedBy == command.deletionId && item.value.folderId == null && item.mask != 0) items[target] = restored(item, id, at)
                } else for (target in result?.restored ?: command.hadithIds) items[target]?.let { items[target] = restored(it, id, at) }
            }
            is SyncCommand.PositionPut, is SyncCommand.LegacyPositionPut -> Unit
            else -> throw LibrarySyncFailure.InvalidChange
        }
    }
    val result = LibrarySavedViewSnapshot(items.values.filter { it.mask != 0 }.sortedBy { rank(it.value) }, folders.values.sortedBy(::folderRank))
    result.items.forEach { it.validate() }; result.folders.forEach { LibrarySavedPolicy.validate(SavedFact.Folder(it._id, 0.0, it)) }; return result
}

class LibrarySavedViewChanged : Exception()
data class LibrarySavedViewFolderTicket internal constructor(internal val stamp: LibrarySavedViewStamp, internal val name: String?, internal val after: String)
data class LibrarySavedViewFolderPage(val stamp: LibrarySavedViewStamp, val folders: List<SyncFolderRow>, val next: LibrarySavedViewFolderTicket?)


/** Integrity of one compiled snapshot, never proof of current server/queue coverage. */
@Serializable
data class LibrarySavedViewManifest(val items: Long, val folders: Long, val indexes: Long, val digest: String, val bindings: Long? = null) {
    fun validate() {
        if (listOf(items, folders, indexes).any { it !in 0..9_007_199_254_740_990L } || !digest.matches(Regex("[0-9a-f]{64}")) || (bindings ?: 0) !in 0..indexes || indexes > items * 16 + folders * 2 + (bindings ?: 0)) throw LibrarySyncFailure.InvalidReceipt
    }
    companion object {
        val initialDigest: String get() = LibraryOutcomeBinding.hash(listOf("saved-view-manifest-v1"))
        fun make(identity: LibrarySavedViewIdentity, source: LibrarySavedViewSnapshot): LibrarySavedViewManifest {
            val json = kotlinx.serialization.json.Json { encodeDefaults = true; explicitNulls = false }
            val rows = mutableMapOf<String, String>(); var indexes = 0L
            for (item in source.items) {
                item.validate(); if (item.mask == 0) throw LibrarySyncFailure.InvalidChange
                val key = identity.itemKey(item.value.hadithId)
                if (rows.put(key, librarySemanticDigest(json.encodeToJsonElement(LibrarySavedViewItem.serializer(), item), "saved-view-row-v1:")) != null) throw LibrarySyncFailure.InvalidChange
                indexes += LibrarySavedViewPolicy.indexKeys(identity, item).size
            }
            for (folder in source.folders) {
                LibrarySavedPolicy.validate(SavedFact.Folder(folder._id, 0.0, folder))
                if (rows.put(identity.folderKey(folder._id), librarySemanticDigest(json.encodeToJsonElement(SyncFolderRow.serializer(), folder), "saved-view-row-v1:")) != null) throw LibrarySyncFailure.InvalidChange
                indexes += 2
            }
            var digest = initialDigest
            for ((key, fingerprint) in rows.toSortedMap()) digest = LibraryOutcomeBinding.hash(listOf(digest, key, fingerprint))
            return LibrarySavedViewManifest(source.items.size.toLong(), source.folders.size.toLong(), indexes, digest).also { it.validate() }
        }
    }
}
@Serializable
enum class LibrarySavedViewAuditPhase { Rows, Indexes, Verified }
@Serializable
data class LibrarySavedViewAudit(val serial: Long, val manifest: LibrarySavedViewManifest,
    val phase: LibrarySavedViewAuditPhase = LibrarySavedViewAuditPhase.Rows, val after: String? = null,
    val items: Long = 0, val folders: Long = 0, val indexes: Long = 0, val digest: String = LibrarySavedViewManifest.initialDigest) {
    fun validate(stamp: LibrarySavedViewStamp) {
        manifest.validate()
        if (serial != stamp.serial || items !in 0..manifest.items || folders !in 0..manifest.folders || indexes !in 0..manifest.indexes || !digest.matches(Regex("[0-9a-f]{64}"))) throw LibrarySyncFailure.InvalidReceipt
        if (after != null && (after.toByteArray().size > 1024 || !after.startsWith(stamp.identity.key + ":"))) throw LibrarySyncFailure.InvalidReceipt
        if (phase != LibrarySavedViewAuditPhase.Rows && (items != manifest.items || folders != manifest.folders || digest != manifest.digest)) throw LibrarySyncFailure.InvalidReceipt
        if (phase == LibrarySavedViewAuditPhase.Verified && (indexes != manifest.indexes || after != null)) throw LibrarySyncFailure.InvalidReceipt
    }
}


@Serializable
data class LibrarySavedReplayEntry(val operation: SyncOperation, val outcome: SyncOutcome? = null, val route: String? = null)
class LibrarySavedReplayCut internal constructor(val entries: List<LibrarySavedReplayEntry>, val mappings: Map<String, String>, val routes: Map<String, String>) {
    val mappingDigest = librarySemanticDigest(kotlinx.serialization.json.Json.encodeToJsonElement(kotlinx.serialization.builtins.MapSerializer(kotlinx.serialization.serializer<String>(), kotlinx.serialization.serializer<String>()), mappings), "saved-build-mappings-v1:")
    val routeDigest = librarySemanticDigest(kotlinx.serialization.json.Json.encodeToJsonElement(kotlinx.serialization.builtins.MapSerializer(kotlinx.serialization.serializer<String>(), kotlinx.serialization.serializer<String>()), routes), "saved-build-routes-v1:")
    val prefixes: List<String> = buildList {
        add(LibraryOutcomeBinding.hash(listOf("saved-build-cut-v1", mappingDigest, routeDigest)))
        val json = kotlinx.serialization.json.Json { encodeDefaults = true; explicitNulls = false }
        for (entry in entries) add(LibraryOutcomeBinding.hash(listOf(last(), librarySemanticDigest(json.encodeToJsonElement(LibrarySavedReplayEntry.serializer(), entry), "saved-build-entry-v1:"))))
    }
    companion object {
        fun capture(state: LibraryPartitionState, source: LibrarySavedGenerationRecord): LibrarySavedReplayCut {
            source.validate(source.lease, true); val version = source.checkpoint.position?.version ?: throw LibrarySyncFailure.InvalidReceipt
            if (state.savedSnapshot?.ownerKey?.let { it != source.lease.owner.key } == true) throw LibrarySyncFailure.OwnerMismatch
            val values = state.confirmed.filter { !it.change.operation.command.isPositionChange && it.version > version }.map { it.change to it.outcome } +
                state.frozen?.changes.orEmpty().filter { !it.operation.command.isPositionChange && (state.collectingOutcome == null || it.operation.command is SyncCommand.FolderDelete && version < state.collectingOutcome!!.committed.revision.saved) }.map { it to null } +
                state.pending.filter { !it.operation.command.isPositionChange }.map { it to null }
            val entries = values.map { (change, outcome) ->
                if (!LibrarySyncAdmission.accepts(change.operation.command, change.operation.at)) throw LibrarySyncFailure.InvalidChange
                val target = LibrarySavedViewPolicy.target(change.operation.command)
                LibrarySavedReplayEntry(change.operation, outcome, change.source.reference?.takeIf { it.hadithId == target }?.collectionSlug?.takeIf { it.isNotEmpty() })
            }
            if (entries.map { it.operation.id }.toSet().size != entries.size) throw LibrarySyncFailure.InvalidReceipt
            val routes = state.savedSnapshot?.items.orEmpty().mapNotNull { row -> row.hadith.takeIf { it._id == row.hadithId && it.collectionSlug.isNotEmpty() }?.let { row.hadithId to it.collectionSlug } }.toMap()
            return LibrarySavedReplayCut(entries, state.folderMappings.toMap(), routes)
        }
    }
    fun item(base: SavedPrivateItem?, target: String, bindings: Map<Int, String>): LibrarySavedViewItem? {
        var value = base?.let { LibrarySavedViewItem(it, routes[target]) }
        for ((index, entry) in entries.withIndex()) {
            val command = entry.operation.command; val at = entry.operation.at
            if (LibrarySavedViewPolicy.target(command) == target) {
                val change = LibraryLocalChange(entry.operation, LibraryLocalSource.Account(null))
                value = LibrarySavedViewPolicy.point(value, change, entry.outcome, mappings, entry.route)
            } else when (command) {
                is SyncCommand.FolderDelete -> {
                    val folder = bindings[index] ?: throw LibrarySyncFailure.InvalidReceipt
                    value?.let { if (folder.isNotEmpty() && it.value.folderId == folder) value = LibrarySavedViewPolicy.deleted(it, entry.operation.id, at) }
                }
                is SyncCommand.FolderRestore -> {
                    val folder = bindings[index] ?: throw LibrarySyncFailure.InvalidReceipt
                    val result = entry.outcome as? SyncOutcome.FolderRestored
                    value?.let { item ->
                        val matches = if (result != null) target in result.restored else if (command.hadithIds.isEmpty()) item.removedBy == command.deletionId && item.value.folderId == null && item.mask != 0 else target in command.hadithIds
                        if (matches) value = LibrarySavedViewPolicy.restored(item, folder, at)
                    }
                }
                else -> Unit
            }
        }
        return value
    }
}
@Serializable
enum class LibrarySavedBuildPhase { Folders, FolderCommands, Items, PointTargets, Manifest, Audit, Prepared }
@Serializable
data class LibrarySavedBuildRecord(val source: LibrarySavedGenerationRecord, val accountRevision: Long, val commandCount: Int, val cutDigest: String,
    val phase: LibrarySavedBuildPhase = LibrarySavedBuildPhase.Folders, val after: String? = null, val commandNext: Int = 0,
    val seen: LibrarySavedCounts = LibrarySavedCounts(), val expected: LibrarySavedCounts = LibrarySavedCounts(),
    val bindings: Long = 0, val manifest: LibrarySavedViewManifest? = null) {
    fun validate(identity: LibrarySavedViewIdentity) {
        source.validate(source.lease, true)
        if (source.lease.owner != identity.owner || source.lease.epoch != identity.epoch || accountRevision !in 0..9_007_199_254_740_990L || commandCount < 0 || commandNext !in 0..commandCount || cutDigest.length != 64 || seen.items !in 0..source.checkpoint.counts.items || seen.folders !in 0..source.checkpoint.counts.folders || expected.items !in 0..9_007_199_254_740_990L || expected.folders !in 0..9_007_199_254_740_990L || bindings !in 0..commandCount.toLong()) throw LibrarySyncFailure.InvalidReceipt
        manifest?.validate()
    }
}
class LibrarySavedBuildSession internal constructor(val identity: LibrarySavedViewIdentity, val revision: Long, val cut: LibrarySavedReplayCut, internal val bindings: MutableMap<Int, String>)
class LibrarySavedBuildChanged : Exception()

@Serializable
internal data class LibrarySavedBuildBinding(val folder: String, val digest: String) {
    fun validate(identity: LibrarySavedViewIdentity, index: Int, cut: LibrarySavedReplayCut) {
        if (folder.toByteArray().size > 128 || digest != LibraryOutcomeBinding.hash(listOf(identity.key, index.toString(), cut.prefixes[index + 1], folder))) throw LibrarySyncFailure.InvalidReceipt
    }
    companion object {
        fun make(identity: LibrarySavedViewIdentity, index: Int, cut: LibrarySavedReplayCut, folder: String) = LibrarySavedBuildBinding(folder, LibraryOutcomeBinding.hash(listOf(identity.key, index.toString(), cut.prefixes[index + 1], folder)))
    }
}


@Serializable
internal data class LibrarySavedPublication(val identity: LibrarySavedViewIdentity, val source: LibrarySavedLease, val version: Double, val digest: String, val commandCount: Int, val cutDigest: String) {
    fun validate(owner: LibrarySyncOwner, epoch: String) {
        source.validate(); LibrarySavedLease(identity.owner, identity.epoch, identity.generation).validate(); LibrarySavedPolicy.integer(version)
        if (identity.owner != owner || source.owner != owner || identity.epoch != epoch || source.epoch != epoch || !digest.matches(Regex("[0-9a-f]{64}")) || commandCount < 0 || !cutDigest.matches(Regex("[0-9a-f]{64}"))) throw LibrarySyncFailure.OwnerMismatch
    }
}
sealed interface LibrarySavedPublicationResult {
    data class Published(val stamp: LibrarySavedViewStamp) : LibrarySavedPublicationResult
    data object Restart : LibrarySavedPublicationResult
    data class Unavailable(val reason: SavedFactsReplyUnavailableReason) : LibrarySavedPublicationResult
}
data class LibrarySavedViewTarget(val stamp: LibrarySavedViewStamp, val item: LibrarySavedViewItem?)
data class LibrarySavedViewFolderTarget(val stamp: LibrarySavedViewStamp, val folder: SyncFolderRow?)
