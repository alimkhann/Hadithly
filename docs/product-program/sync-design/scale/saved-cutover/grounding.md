# Production Saved cutover grounding

2026-10-21. Read-only how/architect grounding of current native production paths and accepted active-generation store. No design/cutover proposal in this record. No repo/code edits, delegation, cloud calls or account actions.

## Current production observation path

### iOS

- `ios/Hadithly/Core/Saved/UserLibraryModel.swift:88`: `LibraryReadTransport` currently has exactly two publishers: `saved -> SyncSavedSnapshot` and `positions -> SyncPositionsSnapshot`.
- Its Convex convenience initializer at144 subscribes to `librarySync:savedSnapshot` and `librarySync:positionsSnapshot`. No production publisher drives accepted Saved fact paging or activation.
- `refresh` captures current Clerk session, `sync.owner` whose subject matches it, and a UI epoch; changed owner/session calls `unsubscribe`, clearing arrays/undo and cancelling subscriptions/retries. `matches` also compares current sync owner.
- `subscribeAll` at451 receives on main, checks captured owner/session/epoch and payload ownerKey, calls `GuestDataStore.cacheSavedSnapshot`, then `reloadAccount`, then `sync.wake`. Positions separately cache/reload but do not explicitly wake here.
- `reloadAccount` at177 decodes the whole partition and constructs `LibraryProjection(state)`. It replaces complete `savedItems`, `folders`, `progress` arrays and derives complete bookmarks/favorites/notes arrays. Readiness currently means `state.savedSnapshot != nil || projected items nonempty`; an empty fully observed snapshot is Ready, while no snapshot/no local item is Loading.

### Android

- `android/app/src/main/kotlin/com/hadithly/app/core/data/UserLibraryModel.kt:73`: `LibraryReadTransport.savedSnapshot/positionsSnapshot` are Flow methods.
- `.../ConvexRepository.kt:61` subscribes to the same two backend functions, with IO flow context. Repository also implements manifest sync transport and opens `librarySync:openManifestBinding`; that does not itself cause Saved page collection.
- `UserLibraryModel.refresh/reloadAccount` at143/160 captures owner/session/epoch and rechecks after the suspending partition read. `subscribeAll` at320 checks matches before caching and again around reload/wake.
- `reloadAccount` still constructs `LibraryProjection(state)` and replaces complete StateFlow lists. Readiness uses the same cached snapshot-or-local-items condition.

## Serialized partition/cache ownership

- Swift `GuestDataStore.partitionRow/syncPartition/saveSyncPartition` at313/322/328 (`ios/Hadithly/Core/GuestData/GuestDataStore.swift`) resolve a unique owner storage key, verify subject and decode/encode the complete `LibraryPartitionState` JSON blob. The SwiftData `GuestLibraryPartition` model in `.../GuestDataModels.swift:307` contains ownerKey, subject and `stateData`; it is not a row-normalized Saved store.
- Swift `cacheSavedSnapshot` at540 validates owner and finite nonnegative integer version, refuses an older version, sets whole snapshot, calls `pruneConfirmed`, then rewrites the partition. `cachePositionsSnapshot` also calls `pruneConfirmed`, so a positions update currently observes Saved through whatever savedSnapshot remains in that partition.
- Android `GuestStore.kt:166-199` stores `GuestStoreFile` in `AtomicFile(guest_store.json)`. `readLocked` reads/decodes the entire file; `writeLocked` applies a transform and `persistLocked` encodes/writes the entire file. This contains guest data plus every account sync partition. The mutex serializes that file's local access, not an atomic commit shared with the outcome/Saved SQLite database.
- Android `cacheSavedSnapshot` at462 validates owner/subject/version, stores the joined snapshot and prunes in one AtomicFile replacement. Any enqueue, receipt settlement, ACK or other partition write can reserialize the full existing joined Saved cache and its public passage summaries. Removing the network subscription alone leaves that full-cache dependency.
- Local sync source records carry references for optimistic/account/guest actions. Guest partition claim moves guest facts into the durable queue and removes original guest storage in one platform-local commit. Position snapshots/overlays remain in this same partition independently of Saved.

## Four authoritative observed-version consumers

Both platforms implement these in `ios/Hadithly/Core/GuestData/GuestMergePlanner.swift` (`LibraryPartitionState`) and `android/.../core/data/LibrarySync.kt` (`LibraryPartitionState`). All four currently use `savedSnapshot.version`; none consults the accepted new row-store active pointer.

1. **`pruneConfirmed`** (Swift612, Android206): removes accepted local overlays once the relevant observed version is >= receipt version. Position commands use positionsSnapshot.version; every other command uses savedSnapshot.version. Called by both cache methods and by direct committed receipt settlement (`settle`/`settleExchange`, Swift887 / Android391), not only the Saved observer. Therefore a cache-only observer migration would leave internal acceptance/pruning behavior on the old source.
2. **`projectedFrozenChanges`** (Swift604, Android201): normally overlays all frozen changes. Once collecting manifest outcome, keeps only a frozen folder-delete overlay while observed Saved version is below the manifest's committed Saved revision. This preserves deletion presentation until the authoritative folder deletion is observed; other manifest frozen originals are not guessed into projection.
3. **`settleCollectedOutcome`** (Swift682, Android212): validates exact frozen/historical frame authority and terminal outcome proof, then requires an owned Saved snapshot with finite integer version >= committed revision before producing durable recovery, folder alias mapping, recent Undo evidence, manifest ACK linkage, clearing frozen/collecting and advancing sequence+ACK intent. Complete proof or `detailUnavailable` can settle; `proofUnavailable` cannot. GuestStore wrappers read the row-journal outcome checkpoint and rewrite partition state only if changed. The sync run loop (Swift around1200, Android around742) returns WaitingForSaved on this barrier and relies on a later wake.
4. **`canPruneOutcome`** (Swift772, Android293): requires exact complete success counts, no superseded/missing, retained ACK age >=30 local days, matching owner/version >= committed Saved revision, plus no references in pending/frozen/confirmed/recovery/recent/waiting/manifest ACK link. Retention driver in GuestStore (Swift around469; Android around416) consults the partition dependency state, then removes bounded journal rows. Replacing only settlement authority would leave retention using old cache proof.

The owner-scoped snapshot version is private observation authority today. Public summary availability is currently bundled into its payload, but neither proof completeness nor note ownership intrinsically depends on those public passages.

## Projection and overlay behavior

- Swift `LibraryProjection` is at the end of `Core/Saved/UserLibraryModel.swift` (~625); Android has separate `core/data/LibraryProjection.kt`.
- Base items/folders come from whole joined snapshot. Public `SyncHadithSummary` is converted to HadithRef (collection route, numbers, Arabic/English passages/reference). Position rows use their own joined summary.
- Overlay order is `confirmed`, then `projectedFrozenChanges`, then `pending`. Overlay reducers preserve independent facets, earliest add times and note fields, local-to-server folder mappings, and positions.
- Folder delete iterates all currently materialized items to clear membership and tags a transient `removedBy[hadithId]=deleteOperationID`; compact pending restore reassigns only still-saved/unassigned rows with that exact deletion tag. Membership put (including explicit none), removal of final facet and later deletes invalidate/replace the tag. This causality currently assumes the fold sees the relevant item base and preceding delete in that one projection pass.
- Final complete item list filters absent facets and sorts aggregate updatedAt descending; folder list sorts createdAt ascending. The accepted store's active projection pages instead traverse hashed row keys, retaining `firstOrdinal` and private timestamps as fields. They are not already UI sort/filter pages.
- Both UI facades create bookmark/favorite/note SavedEntry arrays from that one projected list. Account SavedEntry.rowId is set to hadithId, but older guest entries have their own IDs/references: do not assume SavedEntry.rowId is globally a hadith identity.

## Reader exact-target dependence on hydrated lists

- Swift `UserLibraryModel.isBookmarked/isFavorite` at237/241 searches `bookmarks/favorites` for `$0.hadith?.hadithId == target`. ReaderModel `isBookmarked/isFavorite` at1125/1132 delegates (except explicit DEBUG test seeds). `savedItem(for:)` at1139 searches `savedItems.hadithId`; `noteContent(for:)` at1165 instead searches `library.notes` by hydrated HadithRef identity. ReaderView uses these for markers, menu labels, note editor initial value and Undo timestamps (`.../ReaderView.swift` around1658,1704,1827,1899).
- Android `UserLibraryModel.isBookmarked/isFavorite` at225/228 also searches hydrated `SavedEntry.hadith?.hadithId`; `noteContentFor` at311 does likewise. ReaderViewModel delegates at942-950. ReaderScreen collects complete bookmark/favorite/note/Saved/folder lists and uses exact target entries for note/Undo/action UI (around211,385,2240).
- Consequently a private fact with no public summary/ref currently appears not bookmarked/favorited/with no note to Reader's helper calls even when its private facet exists. A prefix-only UI list would also make an offscreen target appear absent. This is a current dependency, not evidence that the private item can be deleted.

## UI and hydration surprises

- `ios/.../Features/Saved/SavedView.swift` filters/sorts the complete in-memory list again; it explicitly omits `item.hadith == nil` rows. Reader Saved sheet in `Features/Reader/ReaderSheets.swift` repeats whole-list facet/folder filtering and uses same shared row.
- Swift `Features/Saved/SavedItemRow.swift` (~117) renders only inside `if let ref = item.hadith`. Row mutations/removal enum currently carry HadithRef, and open/share/copy route/passage behavior assumes that ref. Its expanded preview uses ref text already present.
- Android `features/saved/SavedItemRow.kt:56` immediately returns for `item.hadith == null`; SavedScreen and Reader Saved sheet can therefore have a nonempty private list with no visible row. Android expanded preview can separately call `ConvexRepository.loadSavedPreview(ref)` when text is incomplete, but requires an existing HadithRef first; it is not an ID-only missing-summary resolver.
- Android SavedScreen around83/100 and ReaderScreen Saved sheet around3547 collect full lists, filter+sort in memory, and render LazyColumn. Native list virtualization limits rendered rows, not underlying list/materialized projection size. Folder controls and move menus likewise accept a whole folders array.
- Empty/error checks compare underlying full `savedItems` versus filtered rows, so public-summary omission, filtered emptiness, initial loading, fully observed empty and failed refresh are currently intertwined.
- `assignFolder` uses the current savedItems array to find an optional source ref; commands still address hadithId. Local mutations otherwise capture LibraryWriteContext/session/actionScope and preserve undo deadlines independent of public preview loading.

## Accepted active-generation APIs and boundaries

- Swift `GuestDataStore` extension exposes `beginSavedAssembly`, `collectSavedStep`, `activateSavedGeneration`, `activeSavedGeneration`, `activeSavedPage`, `replaceSavedCandidate`, `cleanupSavedGenerationStep`; Android GuestStore delegates corresponding calls to `LibraryOutcomeJournal`.
- Active handle contains store-created lease plus private version. Lease binds owner key/subject/namespace, stable owner-scope epoch and generation. Each active page read resolves current scope, checks erase fence and current active-handle equality, then reads <=8 private projection rows by scoped indexed technical keys.
- Candidate raw facts/pages are exact and immutable. Prepared is not active; activation performs final exact server completion recheck and checkpoint CAS, changes pointer+old retirement+export clock in one row DB transaction. Active older generation remains readable while new candidate is collecting/stopped. Stale handles stop after pointer changes. Cleanup targets only explicit distinct retiring generation in bounded steps.
- Projection rows are `LibrarySavedProjection.item(SavedPrivateItem,firstOrdinal)` or folder, without `SyncHadithSummary`; no production exact-target lookup or facet/folder/sort paging API is currently exposed. Existing keyed projection lookup is private reducer support.
- Export already streams current/active/retiring metadata and retained private rows under shared mutation fence; owner erasure hides all generations and bounds physical cleanup. These APIs have local disk proof but no production observer or receipt-barrier authority wiring yet.

## Ownership invariants observed

Clerk subject/session and transport namespace are captured independently of server owner key; `LibrarySyncOwner.storageKey` binds namespace+owner. Network callbacks reject stale session/UI epoch/owner; private store records recheck subject/namespace/owner/incarnation and erase state. Partition queue/receipt intent currently lives separately from the row database on Android. Account deletion invalidates coordinator before suspension, persists deletion intent, fences row store, and cleans both storage domains. Public hydration has no permission to change private ownership, private observed revision or delete absent targets.

This grounding is source inspection, not a design selection or new verification result. Production cutover, full cache/throughput, hosted/installed-SDK/cross-device/physical matrices and recoverable iOS save-failure remain open.
