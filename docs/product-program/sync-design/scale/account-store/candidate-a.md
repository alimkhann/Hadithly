# Candidate A: owned account rows with a recoverable guest-file claim

2026-10-22. Read-only architect candidate. No implementation or gate claim. Grounded in `GuestStore.kt` guest CRUD and lines316–548 account/deletion wrappers; `LibraryOutcomeJournal.kt` real v4 schema and synchronous transaction; `LibrarySync.kt` mutable partition reducer; actual `GuestMergeRaceTest.kt` legacy-file, corruption, ACK-failure, partitionless-evidence, clone/late-reply, deletion and upgrade fixtures; accepted Saved cutover decision. Phase A complete, Phase B sketch below; synthesis/implementation remain with parent.

## Problem

Android currently makes guest claim atomic by replacing one JSON file containing guests and every account partition/deletion intent. Per-owner account rows must move into the existing Saved/outcome DB so queue, receipt, activation and erasing fences can commit together. Keeping guest AtomicFile preserves its simple guest representation, but creates a two-store claim. Per-instance mutexes do not serialize cloned stores; comparing captured draft values cannot distinguish deletion followed by an identical re-add. The design therefore makes guest-file ownership and transfer recovery explicit, without exposing that protocol to native product callers.

## Usage (caller's view)

Existing product call sites retain their domain API:

```kotlin
// UserLibraryModel: reads only guest lists, never all accounts.
val guest = guestData.snapshots() // GuestSnapshot, six guest lists only
renderGuestItems(guest.bookmarks, guest.favorites, guest.notes)

// LibrarySync bootstrap: no caller coordinates transfer/import/cleanup.
store.claimGuestForSync(owner)
val frame = store.freezeSyncFrame(owner)

// Receipt coordinator: account state and journal ACK marker share one DB commit.
store.settleSyncAcknowledgement(reply, requested, owner, now)

// Deletion coordinator remains resumable and scope-bound.
store.beginDeletion(subject, namespace)
// ... existing remote deletion with separately authorized identity ...
store.markDeletionBackendComplete(subject, namespace)
```

Account reads/mutations never return `GuestStoreFile`; they select exactly one keyed row. Guest snapshots no longer include `syncPartitions` or `deletions`; the old DTO survives only as a legacy decoder. Account export is an intentional indexed enumeration of one subject+namespace, not a compatibility implementation of snapshots.

## Shape

### Data structures and storage

Add schema v5 in **the same** `library_outcomes.db`:

- `account_import(id=1, phase, legacy_hash, counts, cursor, guest_epoch, guest_revision, schema_version)`. `phase` is staging or ready; ready is irreversible and never removed by account erasure/reset. Old `guest_store.json` is never an authority after ready, even if it remains/restores. First import alone decodes it.
- `account_partitions(owner_storage_key PRIMARY KEY, subject, namespace, owner_key, revision, state_json)`, indexed `(subject, namespace, owner_storage_key)`. Exact source state JSON retains pending/frozen/recovery/recent/client/sequence/ACK/waiting/collecting/link/retention cursor/confirmed/mappings/Saved snapshot/positions. Keep whole state-per-owner blob as an explicit pending/cache scale limit. No global file-shaped row.
- `account_deletions(scope_key PRIMARY KEY, subject, namespace, phase)`, scope hash over `(namespace, subject)` and exact stored field validation.
- `guest_transfers(source_epoch, source_revision PRIMARY KEY pair, fingerprint, owner_storage_key, subject, namespace, clear_revision, phase)`. Only one pending cleanup can exist globally. `phase=imported` means the account append and receipt committed together; `phase=cleaned` is a compact, permanent duplicate-suppression record. Receipt has no duplicate private note payload. Receipt rows are scoped/indexed for export/erasure; a content-free source revision tombstone remains after account erasure to prevent reclaims.
- `guest_v3.json`: new guest-only AtomicFile envelope `{epoch, revision, sixLists}`. Every guest mutation changes revision. Epoch is minted once during the one-way import and checked against the irreversible account-import authority row. This new path prevents stale legacy `guest_store.json` from being confused with current guest state.
- `guest_store.lock`: stable lock file, never atomically replaced or deleted. Canonical-path process mutex plus exclusive FileChannel lock serializes guest file access across cloned helpers/processes. All lock-taking work is synchronous inside a single `withContext(IO)`; no suspension while a file or SQLite transaction is held. FileChannel alone throws overlapping-lock errors for concurrent same-process channels, so the canonical-path mutex is necessary as an admission adapter, not the authority.

Legacy `LibrarySyncPartition` contains only opaque `ownerKey` and subject, not explicit namespace. The production namespace comes from `BuildConfig.CONVEX_URL`; fixtures use plain names. Establish/validate the namespace contract forbidding `|`, then split the **first** delimiter, preserving any remainder in owner key. Persist and validate explicit fields on import. An invalid/ambiguous old row is retained and reports `StoreUnavailable`; it is never guessed into another scope or silently discarded. This contract needs a source assertion/test before implementation, rather than assuming arbitrary concatenations are safe.

```kotlin
internal data class GuestSnapshot(/* six existing typed lists, exact values */)
internal data class GuestEnvelope(
    val epoch: String,
    val revision: String,
    val guest: GuestSnapshot,
)
internal data class AccountRow(
    val owner: LibrarySyncOwner,
    val revision: Long,
    val state: LibraryPartitionState,
)
internal sealed interface ImportState {
    data class Staging(val sourceHash: String, val next: ImportPosition) : ImportState
    data class Ready(val guestEpoch: String) : ImportState
}
internal data class PendingGuestCleanup(
    val sourceEpoch: String,
    val sourceRevision: String,
    val sourceFingerprint: String,
    val clearRevision: String,
)
```

### Functions and module map

Keep guest file ownership in `GuestStore.kt`; put all account/transfer state and transaction-local journal operations in `LibraryOutcomeJournal.kt`. Existing reducers remain in `LibrarySync.kt`. No new call-chain layer.

```kotlin
// GuestStore.kt, external boundary; all product methods remain suspending.
suspend fun snapshots(): GuestSnapshot
suspend fun claimGuestForSync(owner: LibrarySyncOwner)
suspend fun syncPartition(owner: LibrarySyncOwner): LibraryPartitionState?
suspend fun enqueueSyncChange(change: LibraryLocalChange, owner: LibrarySyncOwner)
suspend fun beginDeletion(subject: String, namespace: String)

// Private synchronous guest shell; one IO dispatcher entry wraps the whole operation.
private fun <T> withGuestAuthority(block: (GuestEnvelope) -> T): T
// TODO acquire stable cross-instance/process lock, finish/import readiness,
// reconcile pending cleanup, validate epoch, then invoke synchronous block.
private fun persistGuest(envelope: GuestEnvelope)
private fun finishPendingTransferLocked()

// Journal owns exact owner/scope checks, ready-state check, DB locking and save.
fun readAccount(owner: LibrarySyncOwner): LibraryPartitionState?
private fun <T> mutateAccount(
    owner: LibrarySyncOwner,
    operation: (SQLiteDatabase, AccountRow) -> T,
): T // operation is non-suspend, fresh decoded state, no cached mutable partition
fun importGuest(owner: LibrarySyncOwner, captured: GuestEnvelope): PendingGuestCleanup
// TODO one transaction: reject deletion, validate ready epoch; exact receipt lookup;
// append captured originals once and write account+transfer receipt+clock together.
fun pendingGuestCleanup(): PendingGuestCleanup?
fun finishGuestCleanup(expected: PendingGuestCleanup)
fun beginAccountDeletion(subject: String, namespace: String)
// TODO intent+same-DB shared clock erasing fence in one transaction.
```

`mutateAccount` is private, not a general public transaction escape hatch. Add transaction-local overloads for journal ACK, settlement checkpoint and pruning so no nested `withContext`/suspending lambda occurs while SQLite thread-local state is held. Externally retain meaningful existing methods; avoid dozens of forwarding-only wrappers. Account state decode occurs after DB transaction begins, so cloned instances cannot overwrite a newer revision loaded beforehand. Semantic equality suppresses needless writes/clock bumps. A fresh state object per operation prevents mutation leaking after rollback.

Per boundary-discipline, only file/import/owner/JSON boundaries validate. Reducer operations consume existing typed domain objects. Per model-the-domain, readiness and transfer states represent actual durable authority. Per make-operations-idempotent, source revision—not draft-value equality—names a transfer. Per minimize-reader-load, file shell owns one protocol and DB module owns one transaction boundary.

### One-way legacy import

1. Every guest/account API calls a cheap DB ready check. If staging/uninitialized, take the guest lock and recheck. No mutation, deletion network preparation or partial account export is admitted until ready.
2. Read and checksum the actual legacy AtomicFile once per migration attempt, preserving corruption as an error and leaving source bytes untouched. Validate duplicate/colliding owners, explicit scopes and deletion intents before authority changes. Decoding the old whole file is unavoidable one-time work, not a steady-state path.
3. Stage account/deletion rows in transactions of at most eight records, with durable cursor/hash/counts. Staged rows are invisible to ordinary operations. Resume against the exact checksum; if the source changed, fail safely and retain both sources instead of combining versions. A resumed attempt may re-decode the whole old file; no claim of bounded legacy decode.
4. Atomically write new `guest_v3.json` with predetermined epoch+revision and exact six guest lists. Failure leaves old source and staging intact. Replaying the same write is harmless; newer guest edits cannot exist because readiness has not been granted.
5. Revalidate file epoch/revision/digest and staged counts/digests. Commit `ready` in DB. Now new APIs use exact account rows and the new guest-only envelope. Cleanup old `guest_store.json` and `.bak` is best effort after ready, under the stable lock. Never use old-file absence as authority and never remove ready on deletion.

Existing journal v1–v4 upgrades become additive-to-v5: run the preexisting export/Saved upgrades for the applicable old version, then create account tables/import state. Preserve export migration, existing Saved active/retiring generations, clocks, scopes, artifacts and all outcome rows. A fresh v5 install begins with import state pending until absence of the old file is proved and an empty guest envelope is durably installed.

### Ongoing guest claim crash protocol

`claimGuestForSync` acquires guest authority and reconciles pending cleanup first. While holding the guest lock, capture envelope revision R. One DB transaction appends its exact originals to the target account (or creates it), records `(epoch,R)` as imported, assigns predetermined clear revision C, and bumps the target export clock. Command admission/invalid recovery is unchanged from current loops; invalid/private source drafts remain exact. If R was already imported, no append occurs.

Then atomically replace guest envelope R with empty six lists at C. Finally mark receipt cleaned in DB. Return success only after cleanup is durable. Crash boundaries converge:

| Last durable state | Restart action before any guest read/write |
| --- | --- |
| No DB receipt; R file intact | Retry import once |
| Account+imported receipt; file still R | Validate exact fingerprint, write predetermined empty C; never append again |
| File C; receipt still imported | Validate C and empty payload; mark cleaned |
| Receipt cleaned; later file revisions | Leave new guest edits intact |

No reader sees captured originals as both guest and account after imported receipt, because guest reads execute reconciliation before returning. No writer can create a newer edit while cleanup is pending, so there is no equality-based cleanup that erases a remove/re-add. For cloned instances, DB locking serializes account appends; stable file locking serializes captures. Two owners racing to claim see one source revision; the second sees the cleared/new envelope and cannot duplicate the first owner's originals. Account edits can run concurrently with file cleanup because they use DB transactions and cleanup does not rewrite the account row.

If file contents have changed unexpectedly at the same source revision or an imported receipt sees neither R nor predetermined C, stop with retained error state; do not clear an unknown newer file. This is a data-integrity failure, not an ordinary race once all writers use the shell. Hash and epoch validation are not permission tokens.

### Deletion and export

Account deletion writes scope intent and erasing fence in **one DB commit**. A pending imported guest transfer may still need file cleanup: its originals belong to the account after DB import, so deletion must remove account data and still consume R before any guest access; it must not restore the data as guest. Complete cleanup under guest lock before dropping private transfer owner fields. Retain only content-free `(epoch, sourceRevision, clearRevision, hash)` suppression tombstones after account cleanup. Do not clear unrelated guests or sibling owners. No private transfer payload is retained outside source/account rows; no old file reimport follows clearing deletion intent.

Partition changes now bump the existing shared export clock in the same transaction, including enqueue/freeze/settlement/cache changes. Export intentionally pages exact `(subject,namespace,owner_storage_key)` rows and needed transfer metadata; it excludes foreign scopes. An export before import ready fails explicitly rather than omitting staged/private data. Existing retained Saved/outcome stages remain included. Account portable state still has a whole-per-owner payload ceiling/scale gate; this migration does not normalize pending/positions or solve full-text cache scale.

If deleting the old legacy file fails after ready, it still contains multiple owners. Its contents are already imported; treating the duplicate as an ignored cache is not sufficient for local erasure. Deletion must either finish legacy cleanup before reporting local cleanup complete or retain a durable cleanup gate/error. Restored ignored legacy files must likewise be removed before reporting a later deletion complete. Never decode them on ordinary account paths. This is an unavoidable extra filesystem obligation of this candidate.

### Interface depth and red-flag screen

Product callers perform one claim or one mutation and know nothing about staging, file revision, SQLite handles, cleanup order or locks. Guest snapshots expose exactly guest data. Account state remains a domain reducer object. No whole `GuestStoreFile` compatibility facade, generic public transaction hook, transport type, or list of account blobs leaks into guest callers. The cost is a substantial internal file protocol and a persistent lock/receipt subsystem. This is deep rather than shallow, but its hidden implementation is meaningfully larger than a same-DB guest row.

## Synthesis decision

Not filled by this runner. Parent/judge must compare the structurally different same-DB guest-row alternative. If Candidate A wins, retaining the file is a deliberate storage tradeoff, not assumed compatibility.

## Tradeoffs accepted

- We accept global serialization of guest operations and transfer reconciliation in exchange for preserving a simple AtomicFile guest representation; account point operations remain independent of this lock after ready.
- We accept permanent compact source-revision tombstones in exchange for duplicate/reclaim suppression across crashes and account deletion.
- We accept a one-time whole legacy decode and bounded row writes in exchange for preserving exact old private data without pretending the old JSON format is pageable.
- We accept per-owner whole-state JSON in exchange for a focused migration; pending queues, position caches and joined Saved caches remain explicitly unscaled until the planned cutover/normalization.
- We accept two filesystem cleanup obligations and a fail-closed guest state when cleanup cannot finish in exchange for keeping guest data out of the account DB.

## Alternatives considered

1. Put guest lists in the same existing DB as one guest row, and claim with an account append+guest clear in one transaction. It hides more invariants behind the same public surface and removes ongoing cross-store transfer complexity; this candidate loses that simplicity to preserve AtomicFile guests. This is a strong competing whole-shape alternative, not merely an implementation variation.
2. Capture guest draft values, append them to account DB, and conditionally remove equal values from the existing file. Rejected: identical remove/re-add edits are indistinguishable, cloned instances race, and callers effectively inherit cleanup/order hazards.
3. Store the entire old `GuestStoreFile` as one DB row. Rejected: transaction atomicity improves but every account operation still decodes and rewrites all owners/guests; information boundaries and steady-state work remain wrong.

## Open questions and risks

- Does preserving the current guest file justify a custom stable-lock and transfer-receipt subsystem when no product requirement mandates it? The same-DB guest alternative should be preferred unless actual migration evidence shows a countervailing risk.
- Can the namespace delimiter contract be proved for every previously admitted deployment namespace? If not, import needs an opaque legacy-row quarantine/binding path rather than guessing a namespace.
- What is the largest real legacy file, and how long does one-time decode/staging plus guest-lock admission take on minimum-spec hardware? Do not label eight-row writes a bounded total migration.
- How should a surviving legacy-file cleanup error appear through existing Saved failure state while preserving access to already imported data? Reporting deletion complete is unavailable until private duplicate bytes are removed.
- Does OS process death during FileChannel lock release behave as expected on target Android filesystems? Use real subprocess/instrumentation proof rather than equating JVM unit serialization with cross-process evidence.

## Next implementation step

Build v5 additive account-row import plus exact-owner DB read/mutate and actual old-file disk fixtures first; only then replace guest claim with the revisioned transfer shell and fault-injection matrix.

## Concrete verification path

Extend actual `GuestMergeRaceTest.kt`, not implementation-mirroring mocks:

1. For authentic v1/v2/v3/v4 databases, preserve all applicable existing journal/Saved/clock/artifact values while importing a legacy file with two subjects, two namespaces, exact multiline/RTL private text, invalid-source recovery, frozen batch, current ACK, mappings and both caches. Verify each exact owner state after reopen and user-level guest snapshot equality.
2. Kill/fail after each bounded staging write, before/after guest-envelope replacement, before/after ready commit and during old-file deletion. Reopen two instances and converge; stale restored legacy file cannot reimport a deleted account or guests. Corruption before readiness retains original bytes and blocks cloud deletion preparation exactly as existing tests require.
3. Fault claim before DB commit, after commit, during AtomicFile write/finish and before receipt clean. Reopen and claim with same/different owner; count each original source once. Verify identical-value remove/re-add after finished cleanup remains guest data, and guest reads while pending never return transferred originals.
4. Race cloned guest writers, cloned claimers, account enqueue, deletion and late remote reply. Show no lost guest update, no duplicated claim, no new account authorization after erase fence, and unrelated subject/namespace byte-for-byte state unchanged. Use synchronous same-thread transaction assertions.
5. Replace current directory-permission ACK-save failure fixture with actual SQLite trigger abort; ACK journal marker and account row must both roll back (old test's separately durable marker behavior intentionally changes to atomicity). Keep later-cursor, stale-proof and export-fence assertions.
6. Move partitionless-evidence corruption fixture to a direct actual account-row removal, preserving outcome/Saved orphan rows and existing retention/export/erase expectations. Keep separate legacy file fixtures; do not weaken test assertions by silently seeding the wrong authority.
7. Capture owner export fence, mutate queue/cache/receipt from clone, and prove rejection; export selected-owner and old-owner partitionless data without foreign scopes. Erase during pending transfer, fail legacy-file cleanup, resume; no cleanup success or identity phase advance until private duplicates gone.
8. Prove query plans for exact owner and scoped enumeration over many foreign account rows; instrument legacy decoder and assert zero calls after ready for ordinary account reads, Saved guards, enqueues, retention, guest mutations and deletion-phase checks. Snapshot return type must lack account lists at compile time.
9. iOS is an explicit no-change storage parity check: existing SwiftData guest/partition/deletion rows already share one container; run selected suites and inspect that future transaction adapters use one fresh context. Do not invent a new Swift import solely for Android parity.

Prepared-only Saved runtime cutover remains OFF. Native physical/device, actual SDK/auth, cross-device, deployment-first, large-cache/queue/export and iOS save-failure gates remain open. No cloud/deployment/push requested by this design.
