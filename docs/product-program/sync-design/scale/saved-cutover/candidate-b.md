# Candidate B: immutable indexed base, query-time overlay

Design exploration only. No implementation, deployment, completed gate, or production-read claim. Parent owns implementation. This candidate was derived from the current source at `19ace8e`, the frame, parent grounding and `grounding.md`.

## Problem

Production Saved still loads the complete joined snapshot into the account partition, replays the complete queue against it, and hands complete arrays to both Saved screens and Reader target checks. The accepted row store already has complete private generations and atomic activation. The missing design is how to consume that authority without rebuilding a second complete mutable display projection. A read-time merge is attractive because an immutable base plus the small set of local edits should normally be enough. It is substantially harder than merging two sorted arrays: deleting a folder changes every member's `updatedAt`, compact Undo applies to a causally defined member set, and private facts contain no collection slug.

My recommendation is conditional. The shape below is correct with a multidimensional immutable query index, but a simple SQLite/SwiftData filtered-page merge is not a viable substitute. If the parent chooses maintained materialized display rows, borrow the authority, display-state, hydration and exact-target interfaces below and reject the custom query index.

## Usage, written before the types

Global Saved and reader Saved own a bounded visible window, not a library array. The library owns filters, continuation integrity, overlay replay and public loading. A renderer receives private rows even when their public references cannot load.

```swift
// SavedView. ReaderSavedSheet differs only in collection scope.
let feed = library.saved(.init(facet: .notes, folder: selectedFolder,
                              collection: .all, order: .recent))
for await state in feed.states {
    render(state.rows, footer: state.footer)
    // rows are private identities plus explicit reference state.
    // Empty UI is allowed only for state.footer == .exhausted and rows.isEmpty.
}
await feed.loadNext()                 // cancels/restarts if its query ticket changed
await feed.refresh()                  // compact invalidation and private collection
```

```kotlin
// ReaderViewModel, independent of any Saved feed or loaded public passage.
library.observeTarget(HadithIdentity(hadithId)).collect { state ->
    bookmarkSelected.value = state.private?.bookmarkCreatedAt != null
    noteDraftSource.value = state.private?.noteContent
}
// Removal and note save use private ID and captured write scope.
library.removeBookmark(target, capturedScope)
```

```swift
// Full row preview / Copy. A compact header never pretends to be full text.
switch try await library.text(for: target, purpose: .copy) {
case .complete(let passage): clipboard.write(passage.arabicAndEnglish)
case .unavailable(let reason): presentRetryOrUnavailable(reason)
}
```

Sync does not request a display feed. Store methods obtain private authority internally while holding the local owner mutation critical section.

```kotlin
// Coordinator sees the same API; store now derives all Saved barriers from rows.
when (store.settleCollectedOutcome(expected, owner, now())) {
    AWAITING_SAVED -> savedRefresh.wake(owner)
    SETTLED -> continueSync()
    // Existing explicit collection/unavailable branches retained.
}
```

## Shape

### Public types and module map

Illustrative native-neutral type sketch, not new wire types or implementation.

```text
SavedLibrary
  saved(SavedQuery) -> SavedFeed
  folders(FolderQuery) -> FolderFeed
  observeTarget(HadithIdentity) -> stream<TargetState>
  text(HadithIdentity, TextPurpose) -> CompleteText | TextUnavailable

SavedQuery
  facet: all | bookmark | favorite | note
  folder: any | none | exact(FolderIdentity)
  collection: all | exact(CollectionSlug)
  order: recent                         // updatedAt DESC, hadithId lexical ASC

SavedFeed
  states: stream<SavedWindow>
  loadNext()
  refresh()

SavedWindow
  rows: bounded retained visible rows<SavedRow>
  footer: loading | more | exhausted | routeUnresolved(count) | retryable(error)
  freshness: current | refreshing | offlinePriorComplete | legacyFallback

SavedRow
  target: HadithIdentity
  private: SavedPrivateItem
  folder: private exact folder label or explicit unavailable
  reference: loading | ready(PublicHeader) | missing | retryable | tooLarge

TargetState
  private: SavedPrivateItem?             // exact private state, no hydration gate
  folder: FolderState
  reference: ReferenceState
  freshness: TargetFreshness

CompleteText
  target: HadithIdentity
  contentRevision: PublicRevision
  arabic: String
  english: String?
  completeness: Complete                 // no truncated String masquerading as full

// Internal, sealed by row store. Callers cannot construct from server invalidation.
OwnedSavedObservation
  owner + subject + namespace + scopeEpoch + activeGeneration + privateVersion

// A query ticket captures both immutable inputs.
SavedQueryTicket
  activeHandle + overlayEpoch + routeIndexEpoch + query + lastOutputRank
```

`UserLibraryModel` becomes the platform facade and feed owner. Existing `GuestDataStore` / `GuestStore` own row reads and owner serialization. Existing `LibrarySavedPolicy` owns pure per-target replay and bulk-effect compilation. Existing transport/repository implementations own the compact invalidation and public endpoints. Avoid a chain of thin per-purpose repositories. Hide transport binding, technical row keys, planning heaps and continuation blobs behind the facade, per boundary-discipline and minimize-reader-load.

### Immutable base index

Keep accepted raw facts, receipts, private projections, active pointer and export semantics. Add immutable query indexes to each candidate generation before it can satisfy the production-read contract. An older generation without the index is a legacy-format generation and cannot produce paged production tickets.

Each private item contributes:

- Exact target lookup by `(generation, hadithId)`.
- Facet mask from its three independent optional facets. There are seven nonempty masks.
- Base folder identity, with explicit no-folder bucket.
- Base rank `(updatedAt DESC, hadithId ASC)`.
- Route classification `known(collectionSlug)` or `unknown`. Route state is public display metadata, never private version proof.

Folder query indexes use `(createdAt ASC, folderId ASC)` and `(normalizedName, createdAt, folderId)` for deterministic collision resolution. The current native use of dictionary `first` for an equal normalized folder name is not deterministic enough to become a persisted query contract. Resolve it with the server's normalization and deterministic identity policy.

For All and exact-folder queries, base indexes include exact facet-mask and rank. Collection variants need a separately complete route-classification index. Do not query all folders or all collections then filter in application code.

The load-bearing addition is an immutable two-dimensional rank index for each relevant scope/mask. A range tree, built in bounded persisted steps, supports:

1. Enumerate by base rank.
2. Enumerate IDs in lexical order restricted to `base.updatedAt <= T`.
3. Enumerate base ranks with `base.updatedAt > T`.
4. Exact counts and empty-range proof for those rectangles.

The second operation is necessary for logical folder delete and restore: all members at or below the operation time acquire the same new timestamp and must reorder by target ID. A composite B-tree `(folder, updatedAt, hadithId)` cannot provide ID order across a timestamp range without reading and sorting the range. A B-tree `(folder, hadithId, updatedAt)` can scan arbitrarily many rows failing the timestamp condition. The range index is substantive infrastructure, not a TODO for later.

A concrete disk representation is a balanced immutable tree over ID ranges, with each node storing a timestamp-sorted secondary range index and child IDs. Canonical segment decomposition of the ID interval plus timestamp range counts lets the iterator find the next eligible ID without scanning rejected leaves. Build progress, node counts, digest and completeness are verified before publishing the query-index-ready flag. Every node read is budgeted. Index storage is roughly `O(n log n)` per indexed scope, materially more than ordinary display indexes.

### Compact overlay data

Do not modify immutable base items when the queue changes. Publish immutable overlay epochs containing:

- Explicit target edits, reduced once per touched hadith ID from its exact base row and chronological target operations. Persist their final projected values and sort keys only for these touched targets.
- A target exclusion set keyed by base target ID, and scope/rank exclusion entries needed by the base iterators. It contains explicit targets, never all folder members.
- Folder event programs indexed by original folder identity and operation order.
- Exact folder creates/deletes/restores, normalized-name decisions and local/server aliases.
- Dependencies on frozen/confirmed status and the row-derived Saved observation used to omit already observed overlays.

These rows are a derived compact edit set, not another authoritative private snapshot. The durable queue and outcomes remain source records for recovery and export. Queue epochs are immutable for a read ticket. Building a new epoch may take bounded steps when pending work is large; a feed keeps its last complete epoch until replacement is ready and marks refresh in progress. Full pending-queue persistence scale remains a separate gate, not solved by this sketch.

Ordinary target edits use the same reducer for an offscreen Reader target and a Saved feed. Per-target evaluation loads its base, explicit events and relevant folder program. It does not scan a Saved window. A local creation without a base row is still an explicit overlay target.

### Logical folder delete and compact Undo

Compile bulk events into a disjoint stream plan by original base folder. Explicitly touched targets are excluded from bulk streams and replay their own complete chronology.

For untouched base items, a folder delete does not remove facets. It hides the folder, changes membership to none, records `removedBy = deletionOperationId`, and floors the item sort time at the operation time. Compact restore applies only to the same deletion tag, still-saved/unassigned membership, and its resolved destination alias. A later explicit membership put, removal of the final facet, or another delete clears/replaces the tag exactly as the existing reducer does.

Untouched items within an original base folder have the same bulk event sequence. Compile that sequence to final effective folder, removal tag and timestamp floor. A delete/restore chain therefore yields a stream transformation rather than one write per member. The transformed timestamp function is `max(base.updatedAt, floor)`. Its output is a merge of an unchanged high-timestamp stream and an ID-ordered floor-timestamp stream obtained from the two-dimensional index. Empty folders and restored folder metadata use the exact folder directory indexes.

Folder aliases must be settled before planning. Local folder creation, restores into an existing same-name folder, and operation order are inputs to the compiler. Accepted explicit restored-member lists are target edits; compact manifests use the retained causal bulk program until the private observed revision permits removing it. Never infer restored membership from currently visible rows or current unassigned rows alone.

### Page query and exact termination

A ticket freezes active generation, overlay epoch and route epoch. Query planning selects relevant base streams from exact facet-mask, collection and effective-folder indexes. It adds the sorted explicit-target stream. Bulk streams have disjoint origin folders; the ordinary unaffected stream excludes changed origin folders by indexed range partitioning, not a broad `NOT IN` filter over a full directory.

The planner loads heads and merges by `(effective updatedAt DESC, hadithId ASC)`. Explicit targets suppress their base instances before output. Persisted planning continuation allows at most eight source/node/overlay records per step, with the existing conservative aggregate-work budget enforced in addition. A public page may require several steps. It returns loading, not an empty complete result, while it lacks enough stream heads to establish the next exact output rank.

Do not use `LIMIT 8` after an arbitrary anti-join as a work bound. Excluding many edited targets can make that query inspect the whole base. The exclusion index must provide key-range gaps or exact subtree counts so the base iterator can seek across excluded runs. This is a second nontrivial part of the custom index. An overlay epoch with many changed folder rules also requires resumable head initialization; it must not allocate one unbounded heap or load every folder name into memory.

Emit at most the requested page and retain only a bounded view window. When a window drops old rows, reverse navigation reloads through a ticket checkpoint. End-of-list is an exact iterator proof. A filtered first page with no match is never sufficient to declare empty.

A new queue edit, active pointer or route epoch invalidates the ticket. Reopen the view near the previous stable target/rank and replace it atomically when a correct new window is available. Never splice pages from different tickets. Reader exact-target state gets its own targeted update immediately and does not wait for a list-window rebuild.

### Collection routing and missing public references

The actual `SavedPrivateItem` and legacy bookmark/favorite/note facts contain only opaque `hadithId`, not collection slug. The current schema `savedItems` also has no saved route. Therefore the query index cannot derive collection membership from existing private fields.

Use a bounded public metadata resolver by exact hadith IDs, independent of private collection/activation. It returns ID-checked route/header metadata, explicit missing, or an explicit bounded-payload failure. Persist route classification as a public display index with its own epoch. It can fill during candidate collection and after activation. A compact header must not include full passage text. Existing locally captured route references can seed this index after identity validation.

Global Saved always displays a private row. Its missing-header form still shows facets, note, private folder and removal/move actions. Reader collection-filtered Saved can prove known matching rows, but cannot truthfully prove total emptiness while some private routes remain unknown. Show an explicit unresolved-reference footer, with bounded retry and a terminal unavailable state for IDs the server reports missing. Missing routes remain in an unresolved section reachable from Saved; never claim they belong to the current collection. This is a necessary user-visible state, not a reason to block private revision activation. If product requires an exact total collection count even for permanently missing targets, preserving route identity in private records becomes a separate backend schema/backfill requirement.

### Independent public text and complete Copy

Use Convex-only public header and text APIs by exact target. Prefer a single exact-ID full-text response with a generous fixed serialized-wire bound measured against the actual Convex document limit. The parent verified the documented one-MiB document and sixteen-MiB return boundaries; no need to introduce chunk infrastructure merely because the Saved source-fact envelope is smaller. Return full Arabic/English plus exact target and content revision, or explicit missing/unavailable/too-large. Validate that a returned ready payload is complete before Copy; never use a compact preview excerpt as copied content. Expanded rows render loading and then complete text, preserving the current full preview function. Measure native decode and rendering memory with the largest permitted fixture. If that measurement requires chunks later, add revision-pinned continuity and total/hash checks rather than truncating content.

Bound the on-disk public text cache separately by bytes and recency. A cache eviction does not change private facets, Saved observed version, missing state, or selected target. Offline full text exists only when previously cached. Public failure disables only actions requiring public route/text; private note edits, removals, Undo and folder movement remain usable. Share and open require a resolved route from that exact target, not a nearby loaded row.

### One private authority for all four consumers

Make the store issue `OwnedSavedObservation?` from the current active row pointer and erase fence. The pure partition methods take this sealed domain input; they never read joined cache version. No scalar observed-version field is written to AtomicFile.

1. `pruneConfirmed(observation, positionsObservation)` uses row observation for non-position commands and the existing positions version for positions. Migrate every settlement/cache/internal call, not only subscriptions.
2. `projectedFrozenChanges(observation)` preserves the frozen folder-delete overlay while row authority is absent or below the committed Saved version.
3. `settleCollectedOutcome(..., observation)` accepts exact outcome proof but waits until owned row observation reaches committed Saved version. Missing public routes/text have no effect on this barrier.
4. `canPruneOutcome(..., observation)` uses the same owned row source alongside existing exact counts, ACK age and dependency checks.

Legacy fallback is a display mode only after a client opts into row authority. Joined legacy version is never an alternate fallback for these four methods. Before first row activation the barriers wait and overlays remain. Old joined snapshot content can remain visible as a clearly old fallback view while the first complete private generation is built.

Android cannot atomically commit the row pointer and partition JSON. Keep activation and queue mutation under the same captured-owner store critical section, with no suspension between row-authority read and partition rewrite. The safe order is row activation, then pruning/settlement. A crash between them leaves redundant overlays/receipt intent that replay can reconcile; never prune first. Owner/session/erase checks apply at the final side effect. iOS should use its row transaction for row changes and the same critical-section discipline for pure queue policy. No claim of cross-file atomicity.

### Compact invalidation, binding and restart

Add a compact `savedHead` subscription which authenticates JWT identity and returns owner/version only. It is an invalidation trigger, never an `OwnedSavedObservation`. Observe compact positions independently as the existing contract requires. Keep capture checks for actual Clerk session, subject, deployment namespace, owner, UI epoch and local scope epoch.

A single-flight refresh driver obtains the actual manifest binding from the existing sync coordinator. Never manufacture a page capability or trust only a cached owner key. The request binds source root/cursors to capability, binding ID and owner. Binding expiry/reopen abandons the candidate's network continuation and starts a new candidate root under a newly opened binding while leaving prior active data readable. Session changes or erase cancel the driver and invalidate every view and text response. Owner namespace/incarnation mismatch is a hard stop.

After terminal source collection, existing bounded fold/check/verify runs, then query-index construction and verification, then exact server completion recheck and existing atomic activation. A changed server version restarts from a fresh candidate. Repeated invalidation is coalesced to the newest observed head; do not repeatedly replace a candidate when the head equals its collected revision. Retries use bounded backoff and visible retry state, never an endless busy loop.

### Cache migration and removal

Introduce an explicit decoder version for row-authority clients. Decode old whole snapshots once as migration input without claiming complete row authority. Keep them until the first row generation and query index are active, then clear the joined snapshot in a single durable partition migration. A failed clear leaves old bytes but never alternate authority. No source page serializes this cache again.

Because current queue and positions still share the partition JSON, avoid rewriting it during private collection. Removing only the network whole-snapshot subscription does not solve this. The decoder's migration write must drop the large joined Saved payload before ordinary ongoing partition writes continue on row mode. Startup parsing of an old huge partition and positions/pending scale remain explicit gates.

Delete the old production `savedSnapshot` subscription and whole Saved projection/array interfaces in the same runtime cutover. Preserve guest-local behavior through a guest feed implementation, not signed-in fallback to the old authority. Shared rows accept paged folder selection and exact folder labels instead of a complete folder array. Folder chips can be a bounded horizontal feed plus a paged picker; do not silently limit which folders can be selected.

## Interface depth

The facade hides exact query planning, ownership, overlay replay, public loading and continuation invalidation. Callers choose a query, request more rows, observe one target or request complete text. They do not join private/public records, inspect queue commands or carry server capabilities. This is a deeper module than a collection of public `loadBasePage`, `loadPending`, `resolveRoute` and `merge` helpers.

The internal index complexity is severe. Its public simplicity does not make the implementation cheap. The custom two-dimensional and exclusion-aware iterators are the cost of preserving sort-correct query-time bulk transformations without materializing affected members.

## Tradeoffs accepted

- We accept a larger immutable index and longer candidate preparation in exchange for avoiding writes to every member when a local folder is deleted or restored.
- We accept bounded incremental planning before a new filter window becomes ready in exchange for exact filtering and sorting.
- We accept explicit unresolved public-reference states in exchange for retaining private records and keeping activation independent of public availability.
- We accept keeping the prior visible window during overlay preparation in exchange for avoiding inconsistent pages. Exact Reader target state still updates independently.
- We accept that old partition parsing, large pending queues, positions and server export are not solved by the Saved query index.

## Alternatives considered

1. Base B-tree pages plus a small in-memory edit map. Rejected. It hides little from callers once folder delete reorders unseen members, filtering requires exhaustion, and offscreen Reader targets need a second path. Its easy implementation preserves the wrong behavior.
2. SQL view with left joins to edits and `ORDER BY max(base.updatedAt, folder.floor) LIMIT 8`. Rejected. Output is bounded, work is not. Dynamic computed sort and exclusion can scan/sort the whole relevant library. SwiftData also has no equivalent expressive indexed-join API.
3. Chunked scan until eight filtered results. Rejected as the final shape. It limits each transaction but can still scan every saved target to answer one empty folder/collection query, explicitly forbidden by the frame.
4. Maintained materialized display projection with indexed effective rank/facet/folder/collection. Practical competing whole shape. It hides bulk rebuild/overlay reconciliation behind the same facade and uses familiar B-tree indexes. Its tradeoff is bounded background fanout when local bulk rules change. I would prefer it over introducing the custom index unless measurement shows bulk fanout is the dominant product failure.

## Synthesis decision

For the parent/judge. Candidate B is a real distinct design, but I do not recommend implementing its custom range/exclusion tree for this app now. The simple query-time merge direction fails the actual sort and bounded-work requirements. The honest viable version above costs more domain-specific indexing machinery than maintaining effective display rows. Keep its common facade and single-observation contracts if another shape wins.

## Open questions and risks

- Can a custom immutable multidimensional index earn its disk/verification cost when bounded display-row fanout gives simpler proof on both platforms?
- Will route-unresolved rows remain an acceptable explicit state for permanently missing targets, or must a future private route migration preserve exact collection classification after public deletion?
- How will preexisting huge partition migration and real SwiftData save failures be exercised without confusing successful row collection with recoverable queue persistence?
- Does measured source collection at one fact per network page meet practical first-sync throughput, or must the existing page bound be revisited with exact payload and replay tests before any rollout?

These are implementation/product audit questions, not requests to stop for human permission. The parent can select the bounded materialized alternative now.

## Complete verification path

Start with counterexamples, not happy-path pages.

1. On both real native stores create 2,001 targets, more folders than a menu page, interleaved masks, identical timestamps, multiple collections and missing public IDs. Compare every query's complete concatenated output to the existing whole pure reducer used only as a test oracle. Verify deterministic tie order and no duplicate/missing identities.
2. Delete a 2,001-member folder whose times straddle the deletion time; assert the `max(baseTime, operationTime)` order exactly, then compact Undo, move one target, remove its final facet, recreate one facet and delete again. Offscreen Reader exact state must equal the oracle at every step.
3. Query a note-only folder with its sole match beyond several base pages; query a true empty folder; query a collection with only unresolved routes. Only proven exhaustion gets an empty-state label.
4. Count actual row/node reads and SQL VM work with large unrelated owners, excluded targets and timestamp predicates. Output size or passing correctness tests alone does not prove bounded indexed access. A failed complexity bound rejects this candidate rather than adding scan exceptions.
5. Feed all four authority consumers old high joined versions plus absent/new lower row authority. None may prune, settle or retain based on joined data. Activate the required row revision and verify each barrier advances. Positions keep their independent version.
6. Crash/reopen after raw writes, fold, query-index steps, final recheck, pointer commit and before partition pruning. Deletion during every suspended network/hydration stage must prevent resurrection; another owner remains untouched.
7. Expire/reopen capability mid-source and after terminal preparation; a new binding never consumes old cursor/completion proof. Preserve the prior active generation until new exact activation. Simulate repeated identical and newer head triggers to prove single-flight convergence.
8. Migrate actual old disk schemas and old whole-cache partition files. Compare exact notes/facet dates/folders/pending/recovery/positions and portable export. Clear joined cache only after row readiness, then inspect disk and subsequent queue writes to prove it is not reintroduced.
9. Hydration missing/error/oversized and public revision changes never change private barrier or facet state. Full preview and Copy preserve a passage larger than the private source-fact envelope byte-for-byte, with no truncation and no target drift. Exercise the full-text envelope boundary and explicit over-limit response separately. Missing rows remain actionable privately.
10. Actual native UI tests cover both Saved locations, selected filters/folders, paged folder actions, expanded text, Copy, empty/error/offline states, exact Reader bookmark/favorite/note actions beyond page one, RTL and accessible labels.
11. Preserve separate backend-first installed-client compatibility, real Clerk SDK/JWT, cross-device, physical-device, external document/provider, paid grounding, legacy-delete-age, pending/positions/server-export scale and recoverable iOS save-failure gates. Local fake transports and disk fixtures do not close them.

## Next implementation step

Implement the compact authenticated Saved-head invalidation and bounded exact-ID public-header/text contracts with actual Convex tests before enabling row-authority production reads, then choose the display indexing shape from measured native counterexamples.
