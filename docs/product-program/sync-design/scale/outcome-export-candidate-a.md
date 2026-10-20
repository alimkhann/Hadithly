# Candidate A: revision-fenced private export stream

## Problem

Settings currently materializes server export and native `portableState` as JSON in memory, then writes one file (`ios/.../SettingsDestinations.swift:1141-1173`; `android/.../SettingsScreen.kt:1043-1063`). The new SwiftData/SQLite outcome journal has owner-scoped headers and bounded member reads, including evidence that can outlive a partition or owner key. A subject+deployment export must discover all such headers without silently missing an insertion before its cursor, stream facts without a growing array, and never publish a file assembled across journal mutations or an account switch. Existing server/partition memory scale remains a separate gate.

## Usage (caller's view)

Settings captures the existing `LibraryWriteContext` after confirmation/reauth. It asks the coordinator for one private export; the coordinator gathers the existing server and partition fields and delegates the entire journal stream, staging and final fence to `OutcomeExport`. The UI receives a publishable local file or a fixed failure. Views never see header cursors or member pages.

```text
// Settings, after reauth and existing server export:
let captured = librarySync.captureWriteContext()
let server = await repository.exportUserData(librarySync.capability(captured))
let file = try await outcomeExport.prepare(captured, server,
    local: librarySync.portableState(captured), stillCurrent: { librarySync.capability(captured) })
share(file) // iOS share URL / Android FileProvider URI; no partial file handed to UI

// sign-out/account switch: revoke the staged or shared private artifact
outcomeExport.cancelPublication(captured)
// account deletion: markDeletionBackendComplete erases every partition and journal orphan
outcomeExport.beginErase(captured.subject, namespace)
```

## Shape

Public surface: `prepare(context, server, local, stillCurrent) async throws -> PublishedExport`, `cancelPublication(context)`, `beginErase(subject, namespace)`, and internal `writeJournal(subject, namespace, sink, token)`; `PublishedExport` owns cleanup/revocation. The coordinator derives subject and namespace from the captured session/transport, not UI input. `prepare` structurally writes all current server fields and sanitized `localLibrary` fields, then adds `localOutcomeEvidence` as a streamed JSON array of headers: exact owner/proof/manifest identity, expected category totals, current checkpoint/status, collected-prefix count, and bounded rows. It labels `endOfCollectedPrefix` separately from `complete`. It preserves user note text byte-for-byte through JSON encoding and removes provider passages/capabilities structurally; a forbidden-key scan is a final defense, not a text rewrite. No JWT/capability is written to the journal or file.

One `SubjectExportFence` per `(subject, namespace)` contains `epoch`, 64-bit `revision`, `state=active|erasing`, and migration version. Create it before any exportable header. **Every** journal mutation increments revision in the same SwiftData save/SQLite transaction: scope/header creation, page-row and checkpoint persistence, verification status, future final settlement or success pruning, orphan repair, and erasure start/batches. A transaction that only reads does not increment. If a mutation fails, neither data nor revision commits. Erasure first atomically switches the fence to `erasing` and increments revision, then may delete rows in bounded batches; export fails even if its header has already been read. Remove the fence only after all scope/header/member rows are gone; a captured token then fails because its fence is absent. A later new account cannot reuse that token. Do not store export leases that could delay erasure.

The private `ExportToken` is `(subject, namespace, epoch, revision, captured session generation)`. `begin` rejects `erasing` or incomplete migration. `readHeaders(token, afterKey, <=50)` uses a subject+namespace+collection-key ordered index, including older owner keys and headers whose partition is missing. `readRows(token, header, start, <=50)` verifies persisted authority/checkpoint and exact ordinal continuity; it returns at most one bounded row page. Both check the same fence before and after their read transaction. A new or removed header anywhere in order changes revision, so final validation catches an insert before the cursor. `finish` checks the same token plus session/capability, then promotes the complete private `.partial` file atomically while sharing the store's writer serialization. The file remains private until that promotion; on cancellation, error, switch or mutation, close and delete it. Startup sweeps abandoned private `.partial` files. No partial artifact is publishable.

SwiftData: add a unique lexicographically sortable `GuestOutcomeInventory` key built from length-prefixed subject and namespace followed by collection key, plus `GuestOutcomeExportFence`. Insert/delete inventory rows with headers in the same save. Existing `GuestOutcomeHeader.key` is a hash, so using it alone cannot discover a subject by an indexed prefix. Backfill old headers in bounded key pages before enabling export; migration and each batch increment the fence revision, and export refuses until migration marker is complete. The `GuestDataStore` MainActor serializes final token validation with private-file promotion; a fresh `ModelContext` reads each bounded page. Android SQLite v1→v2 adds `subject_fences`, `CREATE INDEX headers_export ON headers(subject,namespace,collection_key)` and any missing migration marker in a real transaction; no table rebuild or journal wipe. SQLite transactions bump the fence with every journal mutation. `GuestStore` mutex serializes final validation and handoff of a private FileProvider-backed artifact; it does not keep the mutex across network or long file writes. Use the existing captured deletion intent to reject publication. The current Android SAF `CreateDocument` path writes directly to a user-visible URI, so it must be replaced or made a separate post-validation copy that deletes the destination on any later fence failure. The FileProvider share path has the smaller reliable publication boundary; revoke/delete the private file on sign-out/deletion.

Invariant-bearing types: `ExportToken` is opaque; `JournalHeaderPage` carries a next key and never a guessed total; `JournalRowsPage` carries `nextOrdinal` plus `endOfCollectedPrefix`; `PublishedExport` cannot be built from a partially written file. The store alone parses persisted authority and enforces subject/namespace. This keeps pagination, mutation fencing, redaction and cleanup behind one deep interface (boundary-discipline, idempotent state transitions). `prepare` checks `stillCurrent` after every async boundary and immediately before promotion. Retrying with a new token restarts a new private file rather than splicing prefixes from different revisions.

## Synthesis decision

Candidate A is the revision-fenced stream base for comparison; graft another candidate only if it can guarantee the same cross-page inventory stability and immediate erasure without a larger caller contract.

## Tradeoffs accepted

- We accept a restart if any journal mutation occurs during export in exchange for a simple, provable single-inventory snapshot without copying all rows.
- We accept SwiftData index backfill and SQLite v1→v2 migration in exchange for bounded orphan discovery across old owner keys.
- We accept private staging and a changed Android share flow in exchange for keeping incomplete or stale output out of a user-visible destination.

## Alternatives considered

A native read snapshot/lease can hold a consistent SQLite read transaction, but a long export pins WAL pages and a SwiftData cross-context snapshot is not established by the current store. A writer lease would block page collection and erasure. Both expose lifetime and cancellation rules to Settings, whereas the revision fence hides retries behind one call. A single JSON array from `portableState` avoids a new index but grows with every member and misses partitionless orphans.

## Open questions and risks

Can Android product UX accept FileProvider sharing in place of `CreateDocument`, or must the export use a private staged file plus a carefully cleaned SAF copy? Can the SwiftData installed-schema migration add inventory/fence models and backfill all existing headers without data loss? When will the separate server/partition streaming gate replace their current in-memory JSON assembly? None is resolved by this journal design.

## Next implementation step

Build real-store tests that insert a header before the discovery cursor, mutate a verification checkpoint, prune, switch accounts and erase during streaming; each must abort and remove the private file, then implement the fence and indexes behind that seam.
