# Bounded Saved reads: current architecture grounding

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Mode: read-only `how` grounding before design

## Overview

The current Saved read is one identity-scoped, whole-account projection. `librarySync.savedSnapshot` resolves the Clerk user, reads a per-owner Saved revision, then calls `library.readSavedSnapshot`. That helper collects every canonical item, folder, legacy bookmark, legacy favorite and legacy note, merges them by hadith, resolves effective folder membership, joins full hadith summaries, filters missing targets and returns one complete array.

Both native apps treat that response as the authoritative private base. They persist the whole `SyncSavedSnapshot` inside the local sync partition, project pending/frozen/confirmed writes over it, and use its version as the Saved observation barrier for overlay removal and manifest settlement. A paged replacement must preserve that complete-base contract. A page cannot replace the cached base or satisfy an ACK/Saved barrier.

## Current read flow

1. `backend/convex/librarySync.ts:savedSnapshot` authenticates through Clerk-derived identity, reads `librarySyncVersions(saved)`, and returns `{ownerKey, version, folders, items}`.
2. `backend/convex/library.ts:readSavedSnapshot` runs five unbounded owner queries with `.collect()`:
   - canonical `savedItems`
   - `savedFolders`
   - legacy `bookmarks`
   - legacy `favorites`
   - legacy `notes`
3. Canonical items win the initial per-hadith slot. Each item calls `effectiveSavedMembership`, which may read one stage manifest, destination folder, current folder, and deletion mark. Visible folder and membership clock can therefore differ from raw `folderId/folderUpdatedAt`.
4. Legacy rows merge into the same hadith key. Bookmark/favorite timestamps take the earliest value. The newest note by `updatedAt` wins. Overall `createdAt` is the minimum and `updatedAt` the maximum, including effective membership time.
5. Every merged item performs a hadith lookup. The response embeds `_id`, provider, optional canonical ID, provider reference, collection, volume/chapter, Arabic, English and display reference. Missing hadith documents remove the item from the returned array; folders remain.
6. Folders sort oldest first. Items sort newest `updatedAt` first.

This is a union, not a simple page over `savedItems`. Sequential pages must retain source identity and deterministic merge rules until every source is complete.

## Revision ownership and writer map

`librarySyncVersions(userId, "saved")` is the private Saved revision. The important writers are:

- `librarySync.applyBatch` advances Saved once for any committed batch containing a Saved command. It can advance even when an operation resolves superseded/unresolved; the committed receipt revision is still the overlay barrier.
- Legacy bookmark/favorite/note mutations call `recordLegacyLibraryWrite`, which advances Saved and stamps a causal mark before dual-writing canonical and legacy rows.
- `restoreSavedFacet` uses the same legacy-write boundary.
- `createSavedFolder` advances before validation/write. `assignSavedFolder` advances only on an actual membership write.
- Legacy folder delete/restore advance once at entry and also call `recordLegacyLibraryWrite` per affected membership, so one logical operation may jump the revision many times. Consumers must compare revisions, never assume increments correspond one-to-one with commands.
- `guestMerge.mergeGuestData` advances Saved once before merging folders/items/legacy facets, including retries or payloads that later produce no visible change.
- Manifest folder deletion advances Saved when logical deletion becomes visible and the held receipt commits. Manifest restore advances when staged restored membership becomes effective. Later materialization preserves that already-visible projection and does not need another revision.
- `migrations.migrateH3SavedItems` is a concrete missing boundary: it writes canonical facets and timestamps from legacy rows without advancing the owner's Saved revision. A version-fenced paged reader can otherwise assemble changed private data under an unchanged revision. This migration must gain an owner revision strategy or remain excluded/gated during cutover.

Canonical hadith writes are separate. Provider refresh, migration or canonical metadata/text changes do not advance the private Saved revision.

## Native consumers and barriers

iOS `UserLibraryModel` and Android `UserLibraryModel` subscribe to the whole snapshot. After owner/session/epoch checks they durably call `cacheSavedSnapshot`, reload projection, and wake sync.

`GuestDataStore` and `GuestStore` accept only the captured owner. Older versions are ignored; equal versions may replace the cached snapshot. The entire snapshot is stored inside `LibraryPartitionState` JSON/SwiftData partition state.

`LibraryProjection` starts from cached folders/items, then applies confirmed, projected frozen, and pending changes. The snapshot version has three correctness roles:

- confirmed Saved overlays disappear only when the observed version reaches their committed revision;
- the local folder-delete overlay remains while an outcome's required Saved revision is unobserved;
- terminal manifest settlement waits until the owned snapshot reaches `committed.revision.saved`.

Retention eligibility also uses the owned snapshot version. Therefore native assembly must stage pages separately, restart on revision change, and publish/cache only one completed revision. Until completion, the previous full snapshot and its overlays remain authoritative.

## Private revision versus public summary revision

The Saved version fences private facets, folders and effective membership. It does not fence embedded hadith summaries. Hadith text/reference/canonical fields can change while the Saved revision stays constant, and missing hadith rows can appear/disappear independently.

A new contract must state this honestly. It can guarantee an exact private Saved assembly at revision R, but it cannot call embedded public content one atomic corpus snapshot unless it introduces a separate content revision/digest. A smaller design may assemble exact private facts first and resolve bounded summaries separately, accepting public-content eventual consistency. It must not let summary drift satisfy or invalidate private ACK barriers.

## Non-obvious parity requirements

- Preserve dual-read merge, including duplicate legacy rows and earliest bookmark/favorite timestamps.
- Preserve newest-note selection and min-created/max-updated rules.
- Preserve `effectiveSavedMembership`, including one restore stage, destination ownership, deleted-folder mark and effective clock.
- Preserve missing-hadith behavior explicitly. Current UI omits the item; a paged protocol must count it as processed/skipped, not silently lose cursor coverage.
- Preserve exact canonical summary shape on both platforms, including nullable canonical ID, volume/chapter and full Arabic/English text until a separate summary contract changes it.
- Folder rows and item rows are independent. Empty folders must survive even when no item page references them.
- Cross-owner cursor reuse must fail before reading. Cursor state must bind owner and starting revision.

## Unbounded and high-risk edges

- All five source queries collect without limits.
- Legacy per-hadith duplicates are unbounded; merge work cannot assume one legacy row per hadith even where an index exists.
- Effective membership adds several point reads per canonical item.
- Hadith joins run for the entire merged map with `Promise.all`.
- `arabicText`, `englishText`, `referenceDisplay`, note content and several provider strings have no schema byte bound. A single source row can exceed a page response budget. Truncation would change Saved/render/export semantics; the page must return explicit oversized/unavailable failure.
- The number of unique merged hadiths, folders and response bytes is unbounded.
- `users.exportCurrentUserData` independently collects Saved plus many other tables and joins canonical identities. It is a separate full-export scale problem and must not be claimed fixed by Saved paging.

## Design consequences

The first design slice should define a bounded, owner/revision-bound assembly protocol with explicit source cursors, page byte budgets, skipped/missing/oversized outcomes, replay rules and a final completion proof. It should derive wire validators from one backend definition.

Two viable directions remain:

- stateless pages over each source, with deterministic native merge and a final revision recheck;
- a bounded server preparation/session that materializes only compact merged private facts, then pages them.

The stateless shape avoids persistent copies but exposes five-source merge complexity to native code. The prepared shape simplifies native callers but needs bounded creation, invalidation, cleanup and storage limits. Neither may hide a whole `.collect()` behind a paged response, claim public-summary atomicity, or replace the cached native base before final completion.

## Key files

- Backend read and legacy writers: `backend/convex/library.ts`
- Revision and causal marks: `backend/convex/lib/librarySyncVersions.ts`, `librarySyncMarks.ts`
- Effective membership: `backend/convex/lib/savedMembership.ts`
- Sync writer/reader endpoint: `backend/convex/librarySync.ts`
- Guest merge and missing revision boundary: `backend/convex/guestMerge.ts`, `migrations.ts`
- Folder visibility: `backend/convex/lib/savedFolderTransitions.ts`
- Schema/wire: `backend/convex/schema.ts`, `lib/librarySyncPolicy.ts`
- iOS cache/projection: `GuestDataStore.swift`, `GuestMergePlanner.swift`, `UserLibraryModel.swift`
- Android cache/projection: `GuestStore.kt`, `LibrarySync.kt`, `LibraryProjection.kt`, `UserLibraryModel.kt`
