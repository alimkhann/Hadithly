package com.hadithly.app.core.data

private fun SyncHadithSummary.reference() = HadithRef(_id, collectionSlug, collectionName, volumeId, providerHadithId, arabicText, englishText, referenceDisplay)

val LibraryLocalSource.reference: HadithRef? get() = when (this) {
    is LibraryLocalSource.Account -> reference
    is LibraryLocalSource.Bookmark -> value.let { HadithRef(it.hadithId, it.collectionSlug ?: Collections.slugForName(it.collectionName), it.collectionName ?: "Saved hadith", it.volumeId, it.hadithNumber, it.arabicText, it.englishText, it.referenceDisplay ?: "") }
    is LibraryLocalSource.Favorite -> value.let { HadithRef(it.hadithId, it.collectionSlug ?: Collections.slugForName(it.collectionName), it.collectionName ?: "Saved hadith", it.volumeId, it.hadithNumber, it.arabicText, it.englishText, it.referenceDisplay ?: "") }
    is LibraryLocalSource.Note -> value.let { HadithRef(it.hadithId, it.collectionSlug ?: Collections.slugForName(it.collectionName), it.collectionName ?: "Saved hadith", it.volumeId, it.hadithNumber, it.arabicText, it.englishText, it.referenceDisplay ?: "") }
    is LibraryLocalSource.Position -> value.let { HadithRef(it.hadithId, it.collectionSlug, it.collectionName, it.volumeId, it.hadithNumber, it.arabicText, it.englishText, it.referenceDisplay ?: "") }
    is LibraryLocalSource.Folder, is LibraryLocalSource.Membership -> null
}

class LibraryProjection(state: LibraryPartitionState) {
    val items: List<SavedItemEntry>
    val folders: List<SavedFolder>
    val progress: List<ProgressEntry>
    init {
        val byId = state.savedSnapshot?.items.orEmpty().associate { value -> value.hadithId to SavedItemEntry(value.hadithId, value.createdAt, value.updatedAt,
            value.bookmarkCreatedAt, value.favoriteCreatedAt, value.noteContent, value.folderId, value.hadith.reference(), value.noteCreatedAt, value.noteUpdatedAt) }.toMutableMap()
        val byFolder = state.savedSnapshot?.folders.orEmpty().associate { it._id to SavedFolder(it._id, it.name, it.createdAt) }.toMutableMap()
        val byCollection = state.positionsSnapshot?.rows.orEmpty().associate { it.collectionSlug to ProgressEntry(it.collectionSlug, it.hadith.reference(), it.position, it.updatedAt) }.toMutableMap()
        fun folderId(value: SyncFolderReference): String? = when (value) {
            SyncFolderReference.None -> null
            is SyncFolderReference.Server -> value.id
            is SyncFolderReference.Local -> state.folderMappings[value.key] ?: "local:${value.key}"
        }
        fun initial(id: String, change: LibraryLocalChange) = byId[id] ?: SavedItemEntry(id, change.operation.at, change.operation.at, hadith = change.source.reference)
        val changes: List<Pair<LibraryLocalChange, SyncOutcome?>> = state.confirmed.map { it.change to it.outcome } + state.frozen?.changes.orEmpty().map { it to null } + state.pending.map { it to null }
        for ((change, outcome) in changes) {
            val at = change.operation.at
            when (val command = change.operation.command) {
                is SyncCommand.BookmarkAdd -> initial(command.hadithId, change).let { byId[command.hadithId] = it.copy(bookmarkCreatedAt = minOf(it.bookmarkCreatedAt ?: command.createdAt, command.createdAt), updatedAt = maxOf(it.updatedAt, at)) }
                is SyncCommand.BookmarkRemove -> byId[command.hadithId]?.let { byId[command.hadithId] = it.copy(bookmarkCreatedAt = null, updatedAt = maxOf(it.updatedAt, at)) }
                is SyncCommand.FavoriteAdd -> initial(command.hadithId, change).let { byId[command.hadithId] = it.copy(favoriteCreatedAt = minOf(it.favoriteCreatedAt ?: command.createdAt, command.createdAt), updatedAt = maxOf(it.updatedAt, at)) }
                is SyncCommand.FavoriteRemove -> byId[command.hadithId]?.let { byId[command.hadithId] = it.copy(favoriteCreatedAt = null, updatedAt = maxOf(it.updatedAt, at)) }
                is SyncCommand.NotePut -> initial(command.hadithId, change).let { byId[command.hadithId] = it.copy(noteContent = command.content, noteCreatedAt = it.noteCreatedAt ?: command.createdAt, noteUpdatedAt = command.updatedAt, updatedAt = maxOf(it.updatedAt, command.updatedAt)) }
                is SyncCommand.NoteRemove -> byId[command.hadithId]?.let { byId[command.hadithId] = it.copy(noteContent = null, noteCreatedAt = null, noteUpdatedAt = null, updatedAt = maxOf(it.updatedAt, at)) }
                is SyncCommand.MembershipPut -> if (command.mode != "claim_if_unset" || outcome != null) byId[command.hadithId]?.let { byId[command.hadithId] = it.copy(folderId = folderId(command.folder), updatedAt = maxOf(it.updatedAt, at)) }
                is SyncCommand.FolderCreate -> {
                    val id = state.folderMappings[command.key] ?: "local:${command.key}"
                    byFolder.putIfAbsent(id, SavedFolder(id, command.name, at))
                }
                is SyncCommand.FolderDelete -> folderId(command.folder)?.let { id ->
                    byFolder.remove(id)
                    for ((key, item) in byId.toMap()) if (item.folderId == id) byId[key] = item.copy(folderId = null, updatedAt = maxOf(item.updatedAt, at))
                }
                is SyncCommand.FolderRestore -> {
                    val id: String
                    val restored: List<String>
                    if (outcome is SyncOutcome.FolderRestored) { id = outcome.folderId; restored = outcome.restored }
                    else { id = byFolder.values.firstOrNull { it.name.lowercase(java.util.Locale.ROOT) == command.name.lowercase(java.util.Locale.ROOT) }?.id ?: state.folderMappings["restore:${command.deletionId}"] ?: "local:restore:${command.deletionId}"; restored = command.hadithIds }
                    byFolder.putIfAbsent(id, SavedFolder(id, command.name, at))
                    for (key in restored) byId[key]?.let { byId[key] = it.copy(folderId = id, updatedAt = maxOf(it.updatedAt, at)) }
                }
                is SyncCommand.FacetRestore -> {
                    val item = initial(command.hadithId, change)
                    byId[command.hadithId] = when (val value = command.value) {
                        is SyncCommandFacetRestoreValue.Bookmark -> item.copy(bookmarkCreatedAt = item.bookmarkCreatedAt ?: value.createdAt, updatedAt = maxOf(item.updatedAt, at))
                        is SyncCommandFacetRestoreValue.Favorite -> item.copy(favoriteCreatedAt = item.favoriteCreatedAt ?: value.createdAt, updatedAt = maxOf(item.updatedAt, at))
                        is SyncCommandFacetRestoreValue.Note -> item.copy(noteContent = value.content, noteCreatedAt = value.createdAt, noteUpdatedAt = at, updatedAt = maxOf(item.updatedAt, at))
                    }
                }
                is SyncCommand.PositionPut -> byCollection[command.position.anchor.collectionSlug] = ProgressEntry(command.position.anchor.collectionSlug, change.source.reference, command.position, command.position.updatedAt)
                is SyncCommand.LegacyPositionPut -> change.source.reference?.let { source ->
                    val position = if (outcome is SyncOutcome.ResolvedPosition) outcome.position else (change.source as? LibraryLocalSource.Position)?.value?.readingPosition
                    byCollection[source.collectionSlug] = ProgressEntry(source.collectionSlug, source, position, command.updatedAt)
                }
            }
        }
        items = byId.values.filter { it.bookmarkCreatedAt != null || it.favoriteCreatedAt != null || it.noteContent != null }.sortedByDescending { it.sortDate }
        folders = byFolder.values.sortedBy { it.createdAt }
        progress = byCollection.values.sortedByDescending { it.updatedAt }
    }
}
