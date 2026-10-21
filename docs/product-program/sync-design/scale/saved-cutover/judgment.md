# Saved production cutover cross-judgment

2026-10-21. Read-only architect/arena judgment of both complete candidates, frame, parent grounding and grounding. Actual source checked: both LibraryProjection reducers, the four LibraryPartitionState consumers and call sites, Android AtomicFile partition/claim paths, iOS partition wrappers, and both current Saved sort/filter callers. No implementation, repository edit, delegation, cloud action or gate approval. The parent is the sole implementer.

Phase record: frame read; both candidates read end to end; code constraints checked; cross-judgment complete; parent selection/graft and verification remain.

## Recommendation

Use **candidate A as the base**, with the indexed-row correction below before implementing the production cutover. Its same-database Android partition migration and atomic private/view/queue publication give a tractable ownership model. Its materialized effective rows use native storage capabilities instead of requiring a custom range/exclusion index engine on both platforms.

This selects a design direction, not an implemented contract or passing gate. A has a substantive query-work gap as written; do not silently treat its bounded continuation as sufficient.

## Scores

Scores are out of five for each supplied criterion. They compare these design artifacts, not source correctness or runtime evidence.

| Criterion | A | B | Reason |
|---|---:|---:|---|
| One private authority for all four consumers | 5 | 4 | Both explicitly replace all four scalar consumers. A publishes private pointer, derived view and queue transition in one row DB. B keeps Android queue cross-file; its ordering can be safe, but it leaves more reconciliation proof and overlay-epoch publication unspecified. |
| Bounded/filter-correct UI and exact targets with pending semantics | 3 | 4 | A has exact display indexes and target lookups, but its base/point-overlay anti-join can exhaust an entire scope under tombstones across small steps. B explicitly recognizes and designs around that problem with range/exclusion indexes; correctness depends on building that substantial custom engine. |
| Session, refresh, erasure, migration and restart safety | 4 | 3 | A has one DB ownership marker and same-transaction cutover; cross-store guest claim migration still needs a precise crash protocol. B captures epochs and uses conservative pointer-first ordering, but does not fully specify activation/overlay epoch atomicity or visibility between row activation and AtomicFile reconciliation. |
| Independent public references and preserved full preview/Copy | 5 | 5 | Both preserve missing private rows, expose unresolved collection coverage, resolve exact-ID metadata separately, and require complete validated text for Copy. Public hydration never satisfies private barriers. |
| Interface depth and practical implementation/verification path | 4 | 2 | Both have a deep Saved facade. A adds familiar materialized rows and one partition migration. B requires an immutable multidimensional tree plus exclusion-aware iterators, incremental heap initialization and substantially larger index verification machinery. B itself advises choosing maintained rows unless measurement proves fanout unacceptable. |
| **Total** | **21/25** | **18/25** | **A is the stronger maintainable base after correction.** |

## Required correction to A: remove its anti-join scan

A section 4 proposes immutable published rows plus a mutable point overlay, anti-joining base candidates, with an empty-but-more continuation after a bounded scan budget. That limits each transaction; it does not prevent reading the full selected base to prove that every row was overridden or removed. With 100,000 base note rows and 100,000 point tombstones, an empty notes query may inspect all of them before exhaustion. The frame explicitly rejects full-directory postfilter exhaustion, so this cannot be the accepted final shape.

Use the materialized-row approach all the way through ordinary point edits:

- Maintain the **published effective derived table** with indexes on actual current facet mask, effective folder, route classification and rank. A point edit updates/removes that one derived target and relevant indexes transactionally with its exact queue change, local view serial and export fence. It does not leave a logical tombstone requiring an anti-join at read time.
- This table is disposable presentation data. The immutable private generation and existing queue/originals remain its sources; it cannot mint private observation.
- Bulk delete/restore, private refresh or accepted alias changes still build a distinct staged effective generation in bounded steps. While building, normal edits update the published table and append the catch-up tail. The builder applies those exact changes to the staged table before atomic publication. Retired generations are physically cleaned in bounded steps.
- A query cursor binds current published view identity and edit serial. Any point edit invalidates the ticket; callers keep the prior visible window until a correct replacement is ready. Exact target reads query the indexed published target. There is no cross-serial page splice.
- If the application requires immutable tickets to continue indefinitely across edits, a separate persistent indexed versioning design is necessary. Do not quietly preserve the anti-join as a compatibility path. The actual UI already reprojects after mutations, so ticket invalidation is a reasonable first contract to verify.

This is a correction within A's materialized derived-row architecture. It does not require B's custom tree or a new private authority. It reduces, rather than moves, query complexity.

## Folder delete and compact Undo

The source reducers prove that delete affects more than folder visibility. Every matching item's membership becomes nil, its sort timestamp is floored at the delete time, and `removedBy` records the deletion operation. Compact restore acts only on that exact tag plus still-saved/unassigned membership. An explicit membership change, removal of the last facet, or later deletion invalidates/replaces the tag. A materialized compiler must preserve this chronology even for offscreen members.

A is honest that O(affected items) total work is required for its exact indexed presentation; bounded work per step does not make the operation instantaneous. Use a durable bulk intent and staged generation, publish complete results only, and allow Undo to be admitted while work is applying. The deadline belongs to the accepted action/Undo token, not to when the rebuild finally displays. Do not block Undo behind a draining builder or let the action appear accepted before its command is durable.

Resolve the mixed state explicitly: prior published rows remain a complete old view with an applying indicator while the bulk intent is durable. Exact target observations must identify which published view they represent; do not return a partly applied member set as current. If immediate target membership during applying is needed, it needs a bounded authoritative per-target rule evaluation contract, rather than an undocumented second projection. The most important Reader bookmark/favorite/note facets remain unaffected by a pure folder delete; folder labels/move menus still need the explicit applying state.

Use indexed membership scans for delete, and an indexed deletion-provenance scan for compact restore. Restoration aliases need one deterministic normalization and tie rule agreed with backend, since Swift currently applies NFC plus lowercase while Android applies Locale.ROOT lowercase and both choose the first dictionary value. The new derived view should not persist nondeterminism. Existing timestamp-only final sorts are also nondeterministic on ties; an explicit stable identity tie is appropriate and must be identical on both platforms.

Graft B's strongest verification counterexample: members whose timestamps straddle delete time, delete → compact restore → one explicit move → last-facet removal → facet recreation → second delete, with the interesting target beyond every initial visible window. Compare the complete exhausted output and exact target states against the old reducer as a test oracle, with its unspecified ties normalized in the oracle.

## Android partition authority migration

Select A's migration into the existing row database. Merely retaining AtomicFile behind a mutex is not equivalent to row atomicity, particularly because an effective view depends on both row activation and the queued operations omitted by that observation. Pointer-first can avoid premature pruning, but still needs a durable read/rebuild protocol before an old overlay epoch can be shown over a newly active base. A avoids that split publication problem.

The migration's marker must make DB ownership irreversible for ordinary account paths: after row commit, reads, enqueue, receipts, settlement, retention, positions caching, export and erasure select the row partition even if old JSON bytes survive. Old file deletion is cleanup; its failure must not cause fallback. Use exact subject/namespace/storage identity validation and checksum/readback of pending, frozen, confirmed, recovery, mappings, positions and receipt intent. Do not introduce an observed-revision mirror.

A still needs one design addition: **guest claim crosses two stores** because guest drafts remain in AtomicFile. Existing claim atomically removes guest originals and creates account queue entries in one file. After account migration this property disappears unless an idempotent transfer identity/recovery phase replaces it. Never delete guest originals first. A durable DB import keyed to a transfer identity followed by file cleanup can work, but startup must suppress a second claim of the same transferred originals and preserve any new guest edits made after the captured transfer. A per-owner migration marker alone does not solve this. The same transfer must appear once in portable export and account deletion recovery. Keep that as a required implementation prerequisite, not a claim that moving a blob solves all storage scale.

The large account queue/positions JSON blob can remain a separately measured scale gate during this unit, but no source page or ordinary Saved point mutation may reserialize the old joined public text cache after cutover. One-time legacy decoding is migration cost, not steady-state proof.

## Route-unknown coverage and public hydration

Both candidates correctly identify the hard schema limitation: private Saved facts have opaque hadith IDs and no collection slug. There is no truthful way to assign a missing old public document to a reader collection. Keep independent route states: known route, unresolved, terminal missing, retryable failure. Missing does not remove private facets or notes and does not block the private active revision.

Global Saved must render private identities without public refs. Collection-filtered Saved may show known matches plus unresolved coverage; it may show true empty only when that selected scope is proven exhausted and no unresolved target could match. A permanently missing unknown route should lead to a stable unavailable-reference state/route-unresolved section, not repeated endless retries. Do not show it as belonging to the current collection. Route resolution updates only derived presentation indexes and their view serial/epoch.

Graft B's explicit separation of a compact public header from `CompleteText`. Full preview and Copy need exact target plus validated complete response, byte-for-byte text preservation, explicit missing/too-large/failure, and no provider-number-only fallback that can drift target. Set a measured serialized bound including JSON escaping; a document-size number alone is insufficient. A public cache has its own byte/recency budget and can be evicted without changing private presence, authority or terminal route classification. Capture owner/session delivery even for public payloads.

## Grafts and rejections

Graft from B:

1. Its precise counterexamples for delete-time rank floors, offscreen exact targets and empty-scope proof.
2. Its explicit immutable query ticket inputs and no cross-ticket page splicing, adapted to A's published materialization identity/serial.
3. Its concrete unresolved-reference footer/terminal missing distinction and exact complete-text payload contract.
4. Its requirement to measure actual row/VM work rather than claim that LIMIT or eight output rows prove bounded access.

Reject from B:

- The custom two-dimensional range tree and exclusion-aware planner. They are technically motivated, but disproportionate until measured bulk applying latency proves ordinary materialized indexing inadequate. The range tree needs O(n log n) secondary data per relevant scope, verified builders, immutable node traversal, exclusion-aware seeks and resumable planning. That is a storage engine project alongside sync.
- Cross-file account authority as the preferred cutover. A safe pointer-first recovery can be designed, but it does not simplify the active-view/queue proof and makes future callers carry more repair constraints.

Reject from A:

- Base/overlay anti-join scan as the final UI query contract; use direct indexed effective point rows as above.
- Any implied immediate bulk application or complete pending/positions scale claim. Explicit applying state and measured latency are requirements.
- Treating the migration marker as sufficient for cross-store guest claims. Transfer crash semantics must be designed and tested.

## Parent implementation order and evidence

1. Implement compact authenticated Saved invalidation plus independent bounded exact-ID header/text backend contracts. Tests must include missing public docs and full text larger than the private fact envelope. No deployment implied.
2. Specify Android partition and guest-transfer migration before changing authority; verify actual old files/DBs and crash points. Add same-transaction iOS adapters. Preserve old legacy content until a recoverable display migration is ready.
3. Add the mandatory store-issued observation parameter throughout all four pure consumers and their internal callers while production mode is still off. Test high old joined revision versus absent/lower row authority. Test positions updates and direct settlement paths, not just the Saved subscription.
4. Implement indexed effective rows, deterministic keys, exact targets/folders and bounded query windows; query-work fixtures must include large unrelated owners, sparse facets, no-folder/exact-folder, all rows removed by point edits, many folders, route-unknown and large equal timestamps. No full-base scan may be necessary merely to prove empty.
5. Implement staged bulk builds/catch-up/publication and export/erase of all retained states. Verify all accepted edits and immediate Undo survive crash/reopen, final server recheck races, session/binding expiry, deletion and owner replacement. The private pointer, observation-used queue pruning and selected complete effective view must publish coherently.
6. Switch all production callers together: both Saved surfaces, paged folders, exact Reader status/note queries, independent public loading, complete preview/Copy and nonfalse empty states. Delete old subscription/whole-array Signed-in Saved path in the same runtime cutover.
7. Drive both native UI flows and inspect runtime artifacts, then review and commit. Retain hosted/backend-first installed-client, real SDK/JWT, cross-device, physical-device, legacy deletion age, pending/positions/server export scale and actual recoverable SwiftData.save failure gates. This design judgment closes none of them.

The next safe concrete work is the prerequisite backend head/header/text contract, while the parent incorporates the indexed-row and guest-transfer corrections into the selected design. Full A2 and the full product program remain open.
