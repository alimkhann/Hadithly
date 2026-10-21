# Native private Saved assembly: factual grounding

Read-only tracing of current store, wire, partition, projection, journal and subscription code. No implementation or repository changes. This report grounds the two designs; it does not judge them before both are finished.

## Current caller flow and barriers

Both production `UserLibraryModel` implementations subscribe to the old complete `librarySync:savedSnapshot`, capture owner/session/epoch, reject mismatched replies and durably cache before reloading projection and waking sync. iOS checks `matches` on MainActor; Android checks before the suspending cache call and again before reload/wake. Neither currently consumes private fact pages.

`cacheSavedSnapshot` checks remote ownerKey against `owner.key`, requires the local partition and matching subject, validates a finite nonnegative integral version, ignores older versions and accepts equal versions. It assigns the entire joined snapshot, calls `pruneConfirmed`, then rewrites the partition. This remains the old complete joined meaning; private-only rows cannot be passed to it under the same DTO.

Both `LibraryPartitionState` implementations derive four consequential behaviors from `savedSnapshot.version`:

- confirmed Saved overlay pruning (`pruneConfirmed`);
- retaining a frozen folder-delete projection until its committed Saved revision is seen;
- terminal manifest settlement after a complete/unavailable detail journal, including ACK intent and removal of frozen source;
- retention eligibility after the committed Saved revision is observed.

UI projection also starts from the complete snapshot's joined items/folders; iOS `LibraryProjection` is in `UserLibraryModel.swift`, Android uses `LibraryProjection.kt`. Changing only a store pointer does not migrate any of these readers. A first store-core unit can be useful with production untouched, but it cannot claim active product cutover or barrier migration.

## Partition ownership and durable writes

`LibrarySyncOwner` has key, subject and namespace; storageKey is namespace + `|` + key. A matching account key alone is insufficient: storage owner key, exact subject and namespace/session scope must all remain bound.

On iOS `GuestDataStore` is MainActor. `GuestLibraryPartition` has unique ownerKey, subject and JSON stateData. `partitionRow` fetches by ownerKey and rejects subject mismatch. `saveSyncPartition` encodes the complete `LibraryPartitionState` and saves the long-lived context with explicit rollback on failure. Guest claim/removal and partition insertion share a SwiftData save; normal account snapshot persistence is still whole-partition JSON.

Android `GuestStore` stores the complete guest/partition data in AtomicFile JSON under a store mutex. Existing SQLite outcome rows live in a different file. Holding the mutex serializes one GuestStore instance's calls but does not create an AtomicFile-plus-SQLite atomic transaction, nor a process-wide lock across separately opened store instances. A new private generation's active pointer/revision should live with its rows in the row database; do not make the AtomicFile partition a second activation authority.

The outcome collector demonstrates the reusable async shape: check current session, assert partition/account active, capture generation and durable checkpoint, await a bounded network page, check current session, reassert owner/deletion and generation at durable commit, then check again before presenting. iOS uses a fresh context when persisting; Android enters the store mutex and a journal transaction on IO. This pattern prevents old replies from recreating erased evidence.

## Existing row persistence primitives

### iOS

`GuestDataStore.schema` explicitly lists all @Model types. Existing account partition, deletion intent, scope/header/member, clock, inventory/migration and export artifact models live in `GuestDataModels.swift`; helpers live in `GuestDataStore.swift`. Adding models in those existing files avoids project.pbxproj/xcodegen changes.

Outcome scope owns a random generation. Header binds owner/subject/namespace plus exact serialized authority/checkpoint. Member rows have unique ordinal/member/hadith keys and encoded bounded row payload. Fresh `outcomeContext()` instances avoid a stale long-lived identity map hiding a conflicting save from a reopened store. Every page saves rows and checkpoint together; failure rolls back both. Reads and verification use bounded fetches (50); progress persists between steps. No explicit VersionedSchema/SchemaMigrationPlan is installed in the inspected store constructor; additive model migration still needs an actual old-store reopen fixture rather than an assumption.

### Android

Actual `LibraryOutcomeJournal` is **SQLiteOpenHelper version 2**, file `library_outcomes.db`, not version 3. OnCreate creates scopes, headers and members plus export schema. Existing onUpgrade accepts only exact oldVersion=1/newVersion=2, creating export tables with migration not ready; all other paths throw StoreUnavailable. A version-3 Saved addition must support both installed v1→v3 and v2→v3, preserve all old facts and clocks, and never destructively rebuild.

The transaction helper wraps beginTransaction/setTransactionSuccessful/endTransaction. Existing tables index owner/scope/key and member ordinal; row reads and erasure have LIMIT 50. Outcome members cannot simply hold Saved facts: their UNIQUE(collection,hadith) constraint forbids duplicate legacy source facts for one hadith, and their authority/count semantics are manifest-specific. New Saved-specific tables or models need their own domain keys/checkpoints even when sharing the same database and primitives.

## Erasure and stale replies

Both stores persist a deletion intent before backend erasure, refuse account writes while it exists, erase local row evidence/artifacts before clearing account partitions and advance intent to identityPending afterward. A restart can resume the intent; cleanup is not an all-files atomic transaction.

Outcome erasure first bumps/marks a subject+namespace clock, rotates relevant scope generations, then deletes members/headers/scopes in bounded pages. Full subject+namespace erasure includes prior owner keys; test reset can target one ownerKey. A collector captured before erasure cannot recreate its old generation because commit requires existing matching scope/header and an active partition.

New Saved headers, stage rows, projected rows and active pointers must join full erasure and reset. Blocking only in-memory collectors is insufficient across reopen. New async APIs must require a preexisting captured owned scope/generation and reject deleted/superseded generation at commit. Cleanup must not recreate it opportunistically from a late reply.

## Export clocks and cross-feature accounting

Existing mutation clocks are **outcome-specific**: `GuestOutcomeClock` on iOS, `export_clocks` on Android. They bind subject+namespace to epoch, integer revision and erasing flag. Outcome mutations bump that clock. Export captures it after a bounded inventory backfill and validates it around entry/page/artifact operations. Export includes outcome headers from older owner-key partitions for the same subject+namespace, not just the current server owner key.

The iOS inventory migration scans/checks headers in batches of 50 with a persisted migration marker; Android v1→v2 similarly scans/checks header inventory before allowing export. This is precedent for resumable migration, not evidence that new Saved rows are already exported.

**Important integration trap:** current erasure drops the clock after no outcome headers/scopes remain (Android also checks artifacts). Adding Saved rows to that database without extending the remaining-data checks can remove a fence while private Saved data remains. Either extend one shared private-data clock/accounting deliberately, or give Saved a separate equally durable epoch/revision/fence. Do not label the existing outcome fence a whole-account fence. New Saved mutation/export/erasure paths must invalidate their corresponding fences, and artifact cleanup must include their private contents before consumer cutover.

## Hard constraints for the first verifiable store unit

1. Consume generated validators rather than hand-maintaining parallel DTOs. Parent has added actual SavedFact/Reply validators to generator roots; generation/compilation still needs verification when consumed.
2. Validate owner, binding/session, root assembly, exact expected input/start/ordinal and safe numeric values. Empty advancing pages are real transport progress even when fact count does not increase. Replayed same position must match exact durable fact/result; changed same-ordinal content or source-ID reuse must fail.
3. Preserve source encounter order and duplicate semantics, missing public targets and empty folders. Raw canonical effective membership is already computed server-side; no public hydration may erase private facts or become a private completion barrier.
4. Rows, bounded fold result and checkpoint must commit together. Atomic activation pointer and complete private version must share the same row-database transaction. A failed store write cannot publish active revision or prune overlays.
5. No whole-library dictionary/array or complete partition encoding per page. Reads/writes/verification/cleanup max 50 rows per step, with explicit payload limits. Retained raw and projected generations need bounded lifecycle/storage policy.
6. Final server completion traversal is provisional until contiguous durable local verification plus a final current-revision recheck. Restart/unavailable preserves the prior active private generation; it never installs a partial one.
7. Real reopened persistent stores on both platforms must prove duplicate replay, crash boundaries, schema upgrade, account switch/erase racing a reply, rejected store failure and stale generation. Tests must inspect rows/checkpoints/active revision, not only a helper's return value.
8. First store-core completion must explicitly leave old production subscriptions, old joined caches and all their current barriers unchanged. Later cutover must migrate the four barrier consumers and UI data access together; it must not transfer a complete version into an old DTO that lacks unresolved private rows.

Whole-partition pending/cache scaling, full account export, consumer hydration, throughput, SDK subscriptions/auth, installed-client/cross-device and physical persistence failure evidence remain separate open work.
