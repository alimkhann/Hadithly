# Candidate A: indexed effective Saved view, with atomic local publication

Read-only design, 2026-10-21. Not implementation or end-to-end evidence. Parent remains sole implementer. Grounding: frame.md, parent-grounding.md, grounding.md; actual LibraryProjection, LibraryPartitionState four consumers, both store activation/read methods, generated SavedPrivateItem, Convex savedSnapshot and Android loadSavedPreview were inspected. Architect runner/rationale and red flags applied. Phase A grounded; Phase B candidate supplied; synthesis, implementation and proof remain parent work.

## Problem

The accepted immutable raw/private-generation store solves collection and activation, but production still reads a complete joined JSON snapshot. Its public text currently supplies private Reader status and collection classification, and its scalar version is implicitly read by four unrelated pure-state consumers. Replacing the subscription alone leaves those authorities and whole-array UI untouched. We need one row-store private observation authority, an independently queryable effective view, exact target reads, and public reference hydration that cannot affect private completeness. Android's per-owner queue currently lives in AtomicFile, so an atomic queue/view transition requires moving that existing owner partition into the same SQLite database; writing a second observed version into AtomicFile is rejected.

## Usage (caller's view)

UI sees one Saved facade, not fact pages, capabilities, projection checkpoints or publication roots. Domain pseudocode follows; platform syntax is illustrative.

```swift
// Global Saved; selection changes create a different keyed window.
let window = library.saved.window(.init(facet: .notes, folder: selectedFolder,
                                       collection: .all, order: .updatedDescending))
for await state in window.states {
    render(state.rows, coverage: state.coverage, activity: state.activity)
}
await window.loadMore() // bounded keyset page, stable view stamp

// Reader status never searches the Saved window or hydrated references.
for await status in library.saved.target(currentHadith.id).states {
    bookmarkButton.isOn = status.bookmark != nil
    noteEditor.initialText = status.note?.content
}
let edit = try await library.saved.apply(.removeFolder(folderID))
showUndo(edit.undo) // durable original/deletion identity, no copied member array

// A missing public passage keeps the private row and its destructive actions.
row.render(private: item, reference: item.referenceState)
let complete = try await library.saved.reference(item.target).completeText()
copy(complete.arabic + complete.english) // never copy a truncated preview
```

Store/sync caller has one read/write transaction boundary rather than a version scalar to maintain:

```swift
try store.withLibrary(owner) { tx in
    let observation = try tx.savedObservation() // minted from current row header
    state.pruneConfirmed(observed: observation)
    let progress = try state.settleCollectedOutcome(expected, binding: binding,
        checkpoint: checkpoint, observed: observation, now: now)
    try tx.persist(state) // same DB; schedules/rebases effective-view work
}
```

Positions remain their own revision domain; a positions cache write obtains the same Saved observation through this transaction and cannot revive the old joined Saved authority.

## Shape

### Public domain types

```swift
struct SavedTarget: Hashable { let hadithID: String }
struct SavedSelection: Hashable {
    enum Facet { case all, bookmarks, favorites, notes }
    enum Folder { case all, unfiled, id(String) }
    enum Collection { case all, slug(String) }
    enum Order { case updatedDescending, createdDescending /* actual UI supported orders */ }
    let facet: Facet; let folder: Folder; let collection: Collection; let order: Order
}
struct SavedViewStamp: Hashable { /* opaque, store-created */ }
struct SavedWindowState {
    let rows: [SavedRow]                 // fixed page/window budget, not whole library
    let coverage: SavedCoverage         // exhausted / more / unresolved routing / unavailable
    let activity: SavedActivity         // ready / refreshing / locallyApplying / failedKeepingPrior
    let stamp: SavedViewStamp
}
struct SavedTargetState {
    let target: SavedTarget
    let bookmark: SavedFacetTime?; let favorite: SavedFacetTime?; let note: SavedNote?
    let folder: SavedFolderIdentity?; let coverage: SavedTargetCoverage
    // missing target is distinct from private base not yet established
}
struct SavedRow {
    let target: SavedTarget; let privateValue: SavedTargetState
    let referenceState: SavedReferenceState
}
// Reference state: resolving / available(route, label, preview) / missing / failed(retry).
// A route and complete passage are distinct validated domain types.
protocol SavedLibrary {
    func window(_ selection: SavedSelection) -> SavedWindow
    func target(_ id: SavedTarget) -> SavedTargetWatch
    func folders(_ query: SavedFolderQuery) -> SavedFolderWindow
    func apply(_ edit: SavedEdit) async throws -> SavedEditReceipt
    func undo(_ token: SavedUndoToken) async throws -> SavedEditReceipt
    func reference(_ id: SavedTarget) -> SavedReference
}
```

UI never receives LibrarySyncOwner, raw continuation, DB keys, active generation or wire summaries. Window cursors bind opaque selection + view stamp + last `(sortValue, targetID)` key. Resetting a window after publication is explicit and preserves its visible anchor where possible. No cursor silently continues across generations. Reader target watchers cache only currently watched/visible targets, never all IDs. Folder menus page/search their own index; selecting a known folder uses exact ID even when its menu page is absent.

### Authoritative storage and transaction ownership

1. Keep existing Saved raw facts, receipts, projections and private active/retiring metadata. Their immutable generation remains the complete private base. Add an owner mode in that **same scope header**: legacy presentation or row-backed. It is not a second active pointer. After cutover, only the header's complete active private record can mint Saved observation.
2. Move Android account `LibraryPartitionState` from AtomicFile into one owned SQLite partition row. iOS already has such a row in the same SwiftData container; use the same fresh ModelContext for partition and Saved metadata transaction. Queue blob normalization is a subsequent pending-throughput unit, not secretly solved here. Remove full joined Saved cache from the normal partition payload after safe migration.
3. Add derived-view storage in that DB: one published effective-view handle, build checkpoint, immutable sorted view rows, and a small mutable point-edit overlay over the published view. The effective view is disposable derived data, not private observation authority. Exact item/folder indexes cover owner/view/identity; display indexes cover owner/view, facet, effective folder, routing classification, selected sort value, target-ID tie. Composite facet bitmask has seven nonempty masks; a query fans into at most four matching mask ranges and merges fixed streams. No JSON predicate or full scan then filter. Folder rows have `(createdAt, folderID)` and normalized-name exact index for restore aliases.
4. A normal point edit transaction appends durable exact command/source, updates its effective overlay row/tombstone and indexes, increments published local view serial and shared export fence. The base stream anti-joins that exact overlay key; point overlay stream is independently indexed. At most these two streams per facet mask. A window query reads next keys from these fixed streams with bounded work and exact keyset merge. Tombstoned/overridden base candidates are skipped using **bounded scan budget**; when budget is consumed, return continuation with zero visible rows and `more`, never exhausted. This is honest bounded work even for many tombstones. Background compaction prevents indefinite accumulation.
5. Operations affecting many items (folder delete/restore, accepted folder aliases, private-base refresh) build a new complete derived view in resumable small steps. Source access is indexed and each step has a persisted budget and checkpoint. Publication changes one derived handle in the same transaction as the chosen private pointer/queue transition. Old published view stays readable until then; no partial rewritten member set is exposed. New point edits are applied to current overlay and recorded in a bounded catch-up tail while build runs. Final publication retires the prior overlay generation and installs a new empty overlay by pointer; physical removal of old overlay rows is bounded background work, never an unbounded DELETE hidden inside publication. The builder catches up; if tail exceeds a fixed budget, it switches to draining mode and queues new edit requests at the owner-actor entry until it publishes, then resumes them. Such requests are not acknowledged as durable until admitted to the DB; all receipt/queue producers use that same owner boundary. This is bounded local backpressure, not a second untracked durable intent ledger. This prevents an endless rebuild under continuous edits. A crash resumes durable work; acknowledged point edits remain durable and visible after startup reconciliation.

**Important cost and UX limit:** existing folder delete changes each member's effective folder, updatedAt and removedBy provenance. It therefore requires O(affected rows) total work for exact indexed presentation. Bounded steps do not make it O(1). During bulk local application, display an explicit quiet applying state and preserve prior complete rows; the folder action can show its pending intent immediately, but do not falsely publish a half-deleted item list. Undo remains available immediately and is durably queued, so build can publish the resulting delete+restore state without waiting for server acceptance. This is local optimistic application, but its latency at large N must be measured. If the product requires instantaneous full sorted-list change for arbitrary-size folder delete, reject this shape rather than hiding the cost; a persistent copy-on-write ordered tree or a considerably more complex logical-bucket query engine is then necessary.

### Overlay compiler, causality and freshness

Extract the existing per-item command fold into a pure effective-item reducer. Feed it confirmed, projected frozen and pending in the existing exact order; preserve earliest facet times, notes and `claim_if_unset` semantics. A derived row carries membership provenance including `removedByDeletionOperation`, cleared by explicit membership put (including none), removal of final facet, or a later deletion. A delete compiler scans the exact folder-membership index, not a UI page; compact restore reads the exact deletion-provenance index. Explicit restored IDs use exact target lookup. Restore aliases use a deterministic normalized-name/ID order shared by both platforms; existing Swift normalization versus Android lowercasing must be reconciled with backend contract rather than copied inconsistently. Pending originals and Undo remain the existing durable receipt-linked commands, not snapshots of UI rows.

For private refresh, compile a staging view against the candidate private generation and an immutable queue cut. Do not expose candidate-derived observation before both final source recheck and derived publication transaction succeed. Point-edit catch-up rebases against the new base, not against the previous effective row, so commands already represented by the candidate are pruned using the candidate observation and are not double-replayed. Final publication CAS checks owner/epoch, candidate checkpoint, exact queue serial and view-build completion. If the server source changed, discard/stage-retire the candidate and preserve old published base+view. Atomic observation and view publication are an intentional extension to current `activateSavedGeneration`, not a separate later setter.

### All four barrier consumers

Replace implicit savedSnapshot access with a mandatory typed observation parameter throughout the pure call graph:

- `projectedFrozenChanges(observed:)`: keep collecting folder-delete overlay until the owned complete observed private version reaches committed Saved revision.
- `pruneConfirmed(observed:)`: Saved commands use this observation; positions use positionsSnapshot revision. All direct receipt settlement and both cache callers supply it through owned row transaction.
- `settleCollectedOutcome(... observed:)`: validate owned completed active base and existing exact outcome proof before durable settlement/ACK linkage.
- `canPruneOutcome(... observed:)`: same authority plus current references and existing 30-day policy.

Use `SavedObservation.unavailable` or store-minted `complete(ownerScope, epoch, privateGeneration, revision)`. No arbitrary Double or durable copied observation in `LibraryPartitionState`. During legacy migration, the store-selected mode can derive a legacy observation from the old owned snapshot; after row-backed mode flips, that branch is impossible. Remove/decode-only `savedSnapshot` references from production pure policy. A compact head event is never an observation, and neither public route nor text cache participates in these predicates. Tests must cover all four, not merely one facade cache method.

### Public references and collection scope

Actual SavedPrivateItem has **no collectionSlug**. Convex document IDs do not encode a valid route. Thus collection filtering cannot be complete solely from private facts. Add a bounded independent route-metadata resolver accepting a fixed list of IDs, returning each as available metadata or missing. Persist metadata by exact hadith ID in its own row table and maintain the derived collection classification index. On private collection completion, every target is either known routed, unresolved, or known missing-with-unknown-route; metadata failure cannot delete its private row or delay private revision observation. Queue metadata work independently in bounded ID batches. Existing locally captured route is usable if validated against target identity and tagged with provenance.

Global Saved renders unresolved/missing rows with private note/facet controls and a quiet reference unavailable/loading state. Reader Saved shows known matching rows plus explicit unresolved-scope coverage if some target may match; zero known rows is **not** an exhausted empty result until scope classification is complete. A permanently missing reference with unknown route leaves an honest unavailable-reference indication, not an infinite spinner or a claim the collection has no Saved items. Adding durable collection routing to future private target identities is a separate schema improvement; it cannot be retroactively inferred for old missing documents.

Passage hydration is a second API: exact target + validated route resolves one stored full Arabic/English document only through Convex. Parent verified current Convex limits (1 MiB document, 16 MiB return), so a generous fixed single-document wire bound can preserve all stored text without introducing chunk machinery. Account for JSON encoding expansion when choosing that bound; validate the actual serialized response, and distinguish missing from unavailable. Never silently truncate Copy or expanded preview. CompleteText is constructed only after the full response validates. Preview can show a small text fragment while full text loads, but Copy waits for CompleteText. If future storage moves passages beyond the single-document contract, redesign hydration explicitly rather than truncate. Do not retain Android's provider-number-only fallback as identity authority: validate returned canonical target/provider identity before opening/copying. Public data cache is bounded, per-row, independently evictable, never a whole savedSnapshot rewrite. Capture owner/session epoch for delivery even though payload is public; stale responses cannot mutate a new user's selected row/watch.

### Transport and recovery

New compact authenticated Saved-head query returns owned revision plus protocol availability, no joined rows. It is only a refresh trigger. A private collector opens a fresh manifest binding through the existing bound sync transport; captures actual Clerk session, subject, namespace, owner, binding identity, owner epoch and cancellation generation. Each source page and final completion recheck uses that actual binding. Binding expiration/revocation ends the old source session; open a fresh binding and new root, never attach old continuation to new capability. Stop/unavailable is recorded and retry follows a bounded/backoff state machine; changed revision coalesces a new collection instead of spawning concurrent collectors. Logout/erase changes epoch before awaits and fences all delivery. Offline uses old complete private base + published local view.

### Cache migration

First migrate each Android owned partition into row DB, copying exact bytes/decoded state under an idempotent checksum and source owner validation. Commit DB ownership marker before deleting old AtomicFile copy; every account read/write/export/erase thereafter selects DB by marker. A crash after DB commit cannot choose old file as authority. Guest data stays in its existing store; claims cross the existing durable ownership transition and must be retested. iOS adds projection schema/indexes without rewriting source artifacts.

Compile old joined cache into an explicitly legacy display base once, incrementally by bounded work after the one-time legacy JSON decode. It may preserve cached complete text for offline use. Do not label its version as a fresh private page observation. Keep old payload until row-backed view, private activation, all consumer code paths and migration readback are ready. Final row transaction flips row-backed mode, private active handle, effective view and queue pruning together. Only then remove joined cached payload in a recoverable cleanup step; never fallback to it because public hydration failed. Export/erase include all retained legacy, build, base, delta, public metadata/private note rows as appropriate; public cache is not private completeness evidence.

### Module map and depth

- `UserLibraryModel`/`SavedLibrary`: windows, exact target watches, user edit/Undo receipts; hides subscription lifecycle and bounded window management.
- Existing `GuestDataStore` / `GuestStore + LibraryOutcomeJournal`: one owner transaction + observation authority + durable derived projection/compiler and indexes. Keep storage representation private; no chain of new pass-through repositories.
- `LibrarySavedPolicy` / extracted effective reducer: pure command/causality and query-key policy shared by generated fixtures, no DB/network types.
- Existing `LibraryReadTransport`/`ConvexRepository`: compact head, bound fact collection, independent route/text hydration; parse wire to domain at boundary.
- Saved global/reader UI + shared row: selection, row state, exact identity, loading/missing handling, paged folder menus; no local library filters or private-version comparisons.

Per interface-depth and boundary-discipline, the complicated mechanisms sit behind a small Saved surface; UI owns visual selection and intent only. Owner transaction is internal, not another public UI API. Per foundational-thinking and type-system-discipline, unavailable/private complete/public text complete are distinct values. Per make-operations-idempotent, every migration/build/refresh/cleanup step CASes durable owner+work identity. Per minimize-reader-load, retain existing native store and transport boundaries rather than introduce temporal load/validate/project/save wrappers.

## Synthesis decision

For the parent/judge to fill. This is candidate A only; no claim of selected design or implemented cutover.

## Tradeoffs accepted

- We accept additional indexed derived rows and rebuild work in exchange for exact bounded UI reads without retaining the private library in arrays.
- We accept one owned account-partition migration in exchange for real Android queue/view atomicity rather than two-file synchronization folklore.
- We accept bounded scan continuation pages that can be empty-with-more in exchange for hard work bounds under tombstones; UI keeps requesting within a scheduling budget and distinguishes progress from true exhaustion.
- We accept bulk local applying latency and one-time legacy decode in exchange for a practical native row DB implementation. Neither is represented as solved throughput; measure before accepting UX.
- We accept explicit unresolved collection coverage because legacy private IDs lack routes; public absence cannot manufacture a false empty state.

## Alternatives considered

- **Read a bounded private page then replay all local operations in UI:** exposes queue ordering, folder causality, filtering and pagination to every caller; wrong for off-window deletes/restores and exact Reader status. It hides storage only, not Saved semantics.
- **Normalize mutable effective table and run one unbounded SQL UPDATE for folder delete, then pointer swap:** simple interface but hides unbounded transaction latency; lacks portable bounded SwiftData equivalent. Rejected for scale proof, although useful as a small-fixture oracle.
- **Persistent ordered tree with copy-on-write roots:** gives precise bounded reads and tiny atomic root publication even for staged bulk changes, but requires a custom transactional storage/index engine on both native platforms. Deep interface, high correctness/maintenance cost. Prefer it only if measured bulk-view delay makes this candidate unacceptable.
- **Keep Android queue in AtomicFile and mirror a Saved observed version:** makes partial commits and stale observations normal; caller must understand repair ordering. Rejected because four barriers need actual row authority, not copied proof.

## Open questions and risks

- Can measured large-folder local applying latency meet the quiet native UX requirement, or should this candidate be rejected in favor of a persistent logical/index engine before production cutover?
- Can the current SDK transport distinguish binding expiration cleanly enough for deterministic fresh-root recovery, or does the new compact protocol need an explicit expiration reason?
- Which current UI sort options are actually supported on both platforms, and do normalized folder-name aliases already have one backend ordering contract?

These are implementation investigations, not requests to pause for user approval; answer with source/runtime evidence.

## Next implementation step

Build and test the prerequisite compact revision and independent bounded route/text hydration contracts, then the Android owned-partition row migration, before enabling any production Saved page mode.

## Ordered implementation and proof

1. Backend compact head and public ID metadata/full-text contracts: verified JWT ownership, fixed batch/byte limits, missing and oversized distinction, no private mutation/counter coupling; fixtures cover absent public docs. Typecheck and local Convex tests only; no deployment approval implied.
2. Android DB partition migration and iOS same-context transactional adapters: real old files/databases, crashes at both ownership boundaries, stale clones, account claims, exports and deletion. Assert no account mutation rewrites old joined cache after migration.
3. Mandatory observation type through every pure consumer and wrapper, with row mode still disabled: named tests for all four consumers, receipts and positions updates, stale/foreign/erasing headers, no old snapshot fallback.
4. Derived indexes/compiler/windows/target reads and projection oracle: random bounded operation histories plus >1,000-row and sparse-filter fixtures compare every exhausted query to existing full reducer, including note restore, folder delete+move+Undo, duplicate names, fixed ties and target outside first page. Query-plan/VM work evidence with large foreign owner and tombstone populations. Work counters enforce budgets and prove zero-row continuation progresses.
5. Refresh publication under concurrent edits: old view remains complete; point edits during build; catch-up draining; crash/reopen each work stage; stale capability/epoch/session; changed revision; arbitrary private missing public IDs. All four consumers advance only on final row transaction.
6. UI switch together: global and reader Saved windows, exact target watches, folder menus, missing rows, nonfalse empty states, full expanded preview and Copy, route-stable open. Both native builds and driven UI recordings/screenshots; existing row behavior preserved.
7. Delete old snapshot production subscription/projection path and safely clean cache after migration proof. Retention/export/erase include all new stages. Commit local implementation and evidence; remain honest about pending queue/positions/server export, installed/backend-first deployment, real SDK/auth, cross-device, physical device and SwiftData.save failure gates. Full PRODUCT_PROGRAM stays active.
