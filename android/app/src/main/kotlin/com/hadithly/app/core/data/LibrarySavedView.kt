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
    fun point(current: LibrarySavedViewItem?, change: LibraryLocalChange, outcome: SyncOutcome?, mappings: Map<String, String>): LibrarySavedViewItem? {
        val command = change.operation.command; val target = target(command) ?: throw LibrarySyncFailure.InvalidChange
        if (current != null && current.value.hadithId != target) throw LibrarySyncFailure.OwnerMismatch
        val at = change.operation.at
        var item = current ?: LibrarySavedViewItem(SavedPrivateItem(target, at, at), change.source.reference?.takeIf { it.hadithId == target }?.collectionSlug?.takeIf { it.isNotEmpty() })
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
