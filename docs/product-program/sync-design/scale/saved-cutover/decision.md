# Selected production Saved cutover contract

2026-10-22, after19ace8e. Parent read both full candidates, grounding and independent judgment. Select A21/25 over B18/25, with judge/parent corrections below. This is a design decision, not completed implementation or a passed A2/runtime/deployment gate. Parent remains sole implementer.

## Accepted shape

Keep the existing immutable private active generation as the sole source of complete private observation. Its raw facts/pages/verified projections and durable epoch are already locally proved. Add an indexed effective presentation table, not another observation cache. Migrate all four consumers through a mandatory store-minted observation, including internal receipt settlement and positions-cache paths. Head version is invalidation only; public metadata/full text never satisfy a private observation barrier.

The published effective presentation rows may be mutable. Ordinary point edits update the exact indexed row and queue/source record, bumping the view serial in the same row transaction. Every list cursor captures view identity+serial+selection+rank and rejects a changed serial; callers keep their old visible window until replacement. No base/overlay anti-join or accumulating tombstones are accepted. This deletes the proposed read-scan layer instead of hiding it behind small continuation steps.

Bulk folder delete/Undo, accepted aliases and private-base refresh build a separate effective generation in persisted bounded steps. The builder starts from immutable private base+queue cut, maintains exact membership-removal provenance, catches up accepted edits, and atomically publishes a complete result. Old published rows remain usable with a quiet applying state. Undo is admitted immediately against its accepted-action deadline, never blocked behind a rebuild. Backpressure applies only to not-yet-admitted edits and never claims undurable success. O(affected rows) total work and observed large-folder latency remain explicit acceptance criteria.

Use actual display indexes for facet mask, effective folder, route classification and deterministic rank. Exact Reader target reads do not search a list window or public HadithRef. Folder chips/pickers/actions also page indexed rows; no silent first-page folder limit. Empty means selected scope proved exhausted. Missing public routes remain visible/actionable globally; a reader collection scope reports unresolved coverage until it can establish classification, without claiming those unknown rows belong to that collection.

Android account queue/receipt/positions state must migrate into the existing row DB before the coherent private/view/queue runtime cutover. iOS uses the same fresh context for these rows. Retain existing whole pending blob only as an honest separate scale limit; do not mirror observed Saved version into that blob. Source-page persistence never reserializes the old joined text cache.

## Grafts and rejected alternatives

From B, retain exact offscreen-target and folder-time-floor counterexamples, serial-bound tickets, explicit unresolved-route coverage and complete text distinct from a compact reference. Retain actual query-plan/VM-work evidence as a gate, not output LIMIT alone. Reject its custom multidimensional/exclusion tree unless measured materialized bulk latency justifies a separate storage-engine project.

From A, retain same-DB partition ownership, staged bulk publication, private observation type and a deep native Saved facade. Reject A's immutable-base-plus-point-overlay anti-join because an empty query could exhaust every overridden row. No invariant requires immutable presentation rows when tickets invalidate on serial changes. Do not claim instantaneous bulk application or normalized pending/positions scale.

## Guest/account transaction prerequisite

The initial sketch required a cross-file guest transfer before moving account rows
out of AtomicFile. The subsequent [account-store design](../account-store/decision.md)
compared keeping that split with migrating guest state into the same SQLite database.
The latter eliminates the permanent transfer protocol. Android's one-way staged
v5 import and atomic guest/account claim now pass real disk/rollback/clone/export/
deletion evidence. iOS already shares one SwiftData container and has no-change
parity proof. This does not yet implement the future observation/effective-view
adapters or enable the production read cutover.

## Common read boundary implemented first

Compact authenticated Saved-head invalidation, independent exact-ID route/reference metadata, and on-demand full cached text are necessary for either viable design. Metadata omits passages. Full text remains exact, with an explicit serialized-wire ceiling accounting for JSON escaping. Missing/unavailable public data never remove private rows or alter private versions. Captured native contexts validate actual owner/session/binding/expiry around suspension and delivery. Rights scope remains the existing authenticated Saved surface; no new web/offline/production permission is inferred.

## Ordered work and evidence

1. [x] Backend head/reference/fulltext, generated native DTOs and captured native transport guards; 524 backend, 120 iOS and 102 Android checks. See `../../../../LIBRARY_SAVED_READ_BOUNDARY_VERIFICATION.md`. No production observer switch.
2. [ ] Android shared guest/account transaction prerequisite is locally implemented and verified, with 114 Android and 120 iOS no-change parity passes. See `../../../../LIBRARY_LOCAL_STORE_VERIFICATION.md`. Matching future observation/effective-view transactional adapters remain open; production row mode is still disabled.
3. [ ] Mandatory single observation through all four pure consumers and every wrapper/internal call; high old joined version must not authorize absent/lower row observation. Production row mode stays disabled until complete read/UI readiness.
4. [ ] Effective indexes/compiler, exact target/folder reads and filtered keyset windows. Compare exhausted output to the existing reducer oracle on2,001 rows, offscreen Undo, sparse facets, many folders, equal times and unknown routes. No full scan merely to establish empty.
5. [ ] Bulk build/catch-up/publication, final completion check, binding refresh and private export/erase of all retained stages. Prove every accepted intent and Undo through reopen and races.
6. [ ] Switch both native Saved locations, Reader exact bookmark/favorite/note status, paged folder controls and independent reference/fulltext UI together; delete old production whole snapshot/array path and safely retire old caches. Drive UI, accessibility and capture results on both platforms.
7. [ ] Practical throughput/large-library latency, whole-partition pending/positions and server export scale; retain installed/backend-first/actual SDK/auth/cross-device/physical/iOS save-failure gates and A1 dependencies. No A2 deployment is authorized. Full PRODUCT_PROGRAM remains active.
