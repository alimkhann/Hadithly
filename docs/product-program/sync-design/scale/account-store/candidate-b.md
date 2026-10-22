# Candidate B: one local database for guests and account state

Read-only design, October 22 at `9e2eab9`. No implementation, deployment, permission change, new production-read mode, or gate closure. Parent remains the sole implementer. This refines the migration detail of the accepted Saved design without changing the full PRODUCT_PROGRAM objective.

## Problem

Android's `guest_store.json` contains the six guest lists, every account partition and deletion intent. Current guest claim is safe only because queue append and guest removal share one AtomicFile replacement. Moving only account partitions into SQLite would replace that with a permanent two-store transfer protocol. Move the guest record as well. A one-way import is then the only cross-store boundary; all normal claims, queue changes, outcome/Saved metadata and deletion fences can use the existing `library_outcomes.db` transaction. Preserve the exact imported state, including old caches, and keep later cache retirement separate.

## Usage, caller first

The app keeps its existing asynchronous `GuestDataStore` facade. It has no public transaction callback and exposes neither migration tokens nor SQLite handles. Each call enters IO before its synchronous database work. A first call may prepare the one-way import; normal calls thereafter touch only the relevant row.

```kotlin
// Signed-out UserLibraryModel. Does not decode any account partition.
val guest: GuestSnapshot = store.snapshots()
store.saveNote(target, exactPrivateText, /* existing reference fields */)
```

```kotlin
// Existing sync activation, unchanged caller intent.
store.claimGuestForSync(verifiedOwner)
val frame = store.freezeSyncFrame(verifiedOwner)
// claim transaction appends exact originals to one account row and clears the
// same captured guest row. A later guest edit is a different committed revision.
```

```kotlin
// Existing sync receipt caller. Journal ACK metadata and queue cursor update
// now either commit together or both remain unchanged.
store.settleSyncAcknowledgement(reply, requested, owner, now)
```

```kotlin
// Existing deletion flow. Network remains outside database transactions.
store.beginDeletion(subject, namespace) // intent + row erase fence atomic
val result = backend.erase(preparedAuthorization)
store.markDeletionBackendComplete(subject, namespace)
// resumable local cleanup must finish before IDENTITY_PENDING is durable.
```

The old `GuestStoreFile` becomes an importer-only serialization type. `snapshots()` returns a guest-only value containing the same six guest fields. No empty `syncPartitions` compatibility property is needed in production. Tests that compare `GuestStoreFile()` should compare the new guest snapshot instead.

## Shape

### Data structures

Add schema version 5 to the same helper. Existing v1-v4 tables and data remain in place.

```text
local_store_import
  id = 1 PRIMARY KEY
  state = capturing | importing | verifying | ready
  import_id, immutable_source_digest, source_length
  cursor_phase, next_source_ordinal, rolling_import_digest
  expected_counts, checked_counts, verification_cursor
  cleanup_pending

local_guest
  id = 1 PRIMARY KEY
  revision >= 0
  payload = GuestSnapshot JSON
  payload_digest

local_account_partitions
  owner_storage_key PRIMARY KEY
  subject NOT NULL
  namespace NOT NULL
  owner_key NOT NULL
  revision >= 0
  state = exact LibraryPartitionState JSON
  state_digest
  INDEX(subject, namespace, owner_storage_key)

local_deletions
  scope_key PRIMARY KEY                 // framed hash(namespace, subject)
  subject, namespace
  phase = server_pending | identity_pending
  deletion_id                          // durable local erase incarnation
  local_cleanup = pending | done
  INDEX(subject, namespace)

local_import_receipts
  import_id, source_kind, ordinal PRIMARY KEY
  identity, source_fingerprint
```

`local_import_receipts` are temporary migration verification records, not a second queue or source authority. Their cleanup is bounded after readiness. Each staged data row is inaccessible until `local_store_import.state == ready`. Publication flips one marker; it does not copy every staged account row into another table.

The guest row is intentionally one guest-only blob, not a normalized guest collection. Account state remains one blob per owner. This removes all-owner work and makes the required atomic boundary real; it does not solve a very large individual guest or pending queue. Name that limit in verification rather than calling the store fully normalized.

`owner_storage_key` retains the exact existing key to preserve collision/mismatch behavior. The separately indexed subject/namespace/key are validated against the captured `LibrarySyncOwner` on every owned entry. Never change a row's subject during an upsert. For legacy rows, parse the storage-key convention at the import boundary, reject malformed/ambiguous keys, and preserve the source for recovery. Do not derive scope with arbitrary `startsWith(namespace)` after migration.

### Internal functions and module map

Illustrative signatures, not implementation scaffolding.

```kotlin
// GuestDataStore.kt, facade and existing user-facing domain calls.
suspend fun snapshots(): GuestSnapshot
suspend fun claimGuestForSync(owner: LibrarySyncOwner)
suspend fun syncPartition(owner: LibrarySyncOwner): LibraryPartitionState?
suspend fun beginDeletion(subject: String, namespace: String)

// LibraryOutcomeJournal.kt, same SQLiteOpenHelper and same transaction helper.
fun guestSnapshot(): GuestSnapshot
fun updateGuest(change: GuestChange): GuestMutationResult
fun claimGuest(owner: LibrarySyncOwner): ClaimResult
fun account(owner: LibrarySyncOwner): LibraryPartitionState?
fun enqueue(change: LibraryLocalChange, owner: LibrarySyncOwner)
fun settleAcknowledgement(reply, requested, owner, now)
fun settleCollectedOutcome(expected, owner, now): LibraryOutcomeSettlement
fun beginAccountDeletion(scope: SubjectDeployment): DeletionHandle
fun eraseAccountStep(handle: DeletionHandle): EraseProgress
fun finishLocalDeletion(handle: DeletionHandle)

// LocalAccountStorage.kt, importer records / guest-only DTO / pure claim policy.
sealed interface ImportProgress { data object Ready; data class More(...); ... }
fun importStep(capturedSource: LegacySource): ImportProgress
fun verifyImportStep(): ImportProgress
fun claimGuestSources(guest: GuestSnapshot, state: LibraryPartitionState): Claimed
```

Keep SQLite transaction ownership in `LibraryOutcomeJournal`, rather than introducing a second helper opening the same path. Domain policy such as exact guest-source conversion may live in `LocalAccountStorage.kt`; transaction callbacks are synchronous and internal. The dominant trace is facade -> one helper method -> pure policy. No pass-through account repository is necessary, per laziness-protocol.

The existing helper's `transaction(block: (SQLiteDatabase) -> T)` is already synchronous. Enter `withContext(Dispatchers.IO)` before calling it. No `suspend` transform, `withContext`, network request, `yield`, callback awaiting an app actor, or suspending file operation may run inside it. Extract shared private helpers that accept the current database for combined ACK/partition or erase/partition operations. Do not nest public methods that open independent transactions and then call the result atomic.

### One-way import, with explicit publication

1. Every new facade method first checks the singleton DB readiness row. A ready marker wins over any old `guest_store.json`, `.bak`, `.new` or import snapshot. It is never cleared by guest claim, owner reset, account deletion or normal cleanup.
2. If unready, acquire a migration file lock for the app's fixed local import path. Cloned instances cannot capture or mutate the old file concurrently. All new-version guest/account mutations wait for readiness; none writes the legacy file. Ordinary DB journal operations can remain available internally, but production owner-admitting operations must not bypass import readiness.
3. Capture the AtomicFile's recoverable committed contents into a fixed private immutable import snapshot using an atomic file replacement and fsync. Bind it by exact byte length and SHA-256 to the DB import record. A missing legacy source means a valid empty guest/partition/deletion source. Corruption means StoreUnavailable, with exact source bytes preserved, not an empty store.
4. The order is durable snapshot first, DB import record second. A crash before metadata can leave an orphan snapshot; recovery under the file lock validates or recaptures it before any publication. A crash after metadata must resume that exact digest. It never silently selects a newly appeared legacy file. If the live legacy contents changed under an unsupported old writer, preserve both copies and fail publication instead of dropping either set of edits.
5. Decode the captured legacy source once per migration attempt. The old format is one JSON object, so one whole-source read/decode is a stated migration cost. It is not a steady-state adapter. Crash/reopen may repeat that decode. A large-source parser limit must fail explicitly and retain the bytes; no silent empty/default fallback.
6. Stage guest payload, deletion rows and account rows in bounded row-count steps. Each step records source ordinal/fingerprint and its cursor in the same transaction as inserted rows. Resume exact receipts idempotently. Conflicting same-key records fail without overwriting either source. Exact duplicated legacy records may coalesce only if equality is proved and both source ordinals are accounted for in receipts; otherwise reject for recovery.
7. Run a bounded readback verification pass over staged records and receipts. Verify owner fields, exact domain payloads, count/digest and no extra/omitted staged rows. Persist verification progress. A single account/guest blob can be large; the bounded claim is the number of independently staged rows, not a fabricated byte bound on old payloads.
8. In one final DB transaction, recheck the exact verified import identity/checkpoint and publish ready. Install erase fences for imported deletion intents in that same transaction. Do not reinterpret imported `identity_pending` as an invitation to reopen a deleted account. Existing Saved/outcome clocks and active/retiring pointers are preserved; imported account snapshots grant no new private Saved authority.
9. After ready, cleanup of redundant legacy source files and migration receipts is resumable. Every new instance ignores those files even if deletion failed, the file was restored from an old copy, or a test creates it again. Cleanup never writes DB account or guest state. The durable readiness marker is irreversible for this database incarnation.

An unsupported rollback that restores the entire database to a pre-ready backup is outside the local exactly-once guarantee. Do not claim that a small readiness row can prevent whole-database history rollback. Installed-version rollback/backup restoration needs its separate compatibility evidence.

### Atomic claim and cloned instances

`claimGuest(owner)` begins a SQLite write transaction, checks readiness, deletion and owner fields, reads the singleton guest row plus only the selected account row, runs the existing source conversion in the existing order, appends to the account state, writes the account state and increments its revision, then replaces the guest payload with empty lists and increments guest revision. Commit once.

Keep exact originals in `LibraryLocalSource`, including invalid drafts sent to recovery, private note text, timestamps, semantic reading positions, unversioned membership claim behavior, and current client/sequence/ACK state. A duplicate claim after commit sees an empty guest row and cannot append the same originals again. Rollback leaves both rows unchanged. New guest edits commit after the claim under SQLite locking and remain unclaimed until the next explicit claim. Different simultaneous owners race for one guest row; one commits the claim, the other sees the remaining guest state. That is the existing single-owner claim contract, not duplicate distribution to both accounts.

Do not use an earlier in-memory `GuestSnapshot` as the deletion predicate. Read the current guest row inside the claim transaction. Guest mutation similarly reads its current row inside its own transaction, so a stale facade cannot overwrite newer edits. The per-instance Kotlin mutex can remain for UI single-flight work, but correctness across two helper instances comes from SQLite locking and row checks. No transform runs outside a transaction and later overwrites a newer revision. If an explicit outside-transform ever becomes necessary, require a revision CAS and retry pure policy against a fresh row.

### Owned state, ACK and future observation

All account methods use indexed exact-key lookup. `syncPartition` loads one owner, checks exact subject/namespace/key and deletion scope, then returns a decoded copy. It does not decode the guest row or another owner. Guest mutation does not load account state. Neither path constructs `GuestStoreFile`.

Receipt settlement, ACK confirmation and terminal-outcome policy read the selected queue state and relevant journal rows within one current DB transaction, then write queue plus journal metadata together. This fixes the present ACK path that calls `outcomeJournal.acknowledge` and subsequently persists AtomicFile. Future Saved observation and effective-view publication can use the same transaction without inventing a cross-file atomicity claim. Production Saved read mode remains unchanged during this migration unit.

Every account mutation that changes export-visible data bumps the existing subject/deployment export clock in the same transaction. Retention and owner-admission lookups use `local_deletions` by exact scope. The old `prepareExportStep(blockedScopes: Set<String>)` must stop constructing an all-deletions set from the file; its bounded journal scan can check each encountered scope against the indexed deletion table. Update empty-clock/removal predicates so an extant account row prevents a scope from being declared empty or its clock being removed.

### Deletion and retained legacy privacy

`beginDeletion` inserts or preserves the exact intent and sets the Saved/outcome/export erasing fence in one transaction. A late clone then cannot append, settle, activate or reopen the owner. `server_pending` is preserved across network failure. Scope capture and actual auth checks stay outside/around network as today.

After backend completion, erase bounded Saved/outcome/effective rows and matching account rows by `(subject, namespace)`, retaining the deletion intent and erase fence. Account deletion does not erase the guest row or another subject/deployment. Fixed-path exported artifacts remain separate file effects with resumable metadata.

The ready marker prevents stale legacy bytes from resurrecting state, but those bytes remain private retained data until removed. Therefore local deletion cannot reach `identity_pending` while any old legacy base/backup/new/import snapshot still contains the account. Once ready, all source data already exists in database rows, so those source files are globally redundant: delete the entire fixed set, preserving unrelated owners in DB. If cleanup fails, retain pending local cleanup and report retry; do not claim erasure completed. A retry of backend erase is already idempotent while the existing public phase remains server_pending. A distinct internal local-cleanup flag records the precise remaining work without adding a new public account-flow behavior.

Any owner-reset test helper erases only its captured account rows and journal generations; it never clears DB readiness or imports the old file. Clearing a completed deletion intent must not remove a clock while any scope data/artifact remains, and must not automatically bootstrap an account. Existing verified identity/bootstrap rules remain in charge.

### Export

Export admission first requires ready, exact owner and no deletion fence. Before ready, fail/retry with no partial artifact; never export the raw all-owner import snapshot to one account. After ready, export current account state and retained matching Saved/outcome stages under the shared clock as today. The importer/source files are redundant migration retention, not a consumer data export section. If retained because cleanup failed, record that cleanup state for local erasure without copying unrelated private content into an export.

Bumping the clock for account changes now makes cloned-instance note/pending/receipt mutations invalidate the same fence as Saved/outcome changes. Capture the local account value after the fence and validate again at seal. A clone's account mutation must reject the stale artifact even if no journal page changed. Account export still loads that one account blob and server export scale remains open. Guest export, if invoked, uses the guest revision and a separate guest fence; do not attach anonymous guest state to an authenticated owner's export merely because it shares the database.

### Additive v1-v4 upgrades and iOS parity

Upgrade `library_outcomes.db` to version 5 additively. Fold the current upgrade conditions into sequential migrations: v1 export additions, v2 Saved tables, v3 active/retiring additions, then v4-to-v5 local-state tables. Fresh creation calls the same table builders. `onUpgrade` only creates schema/initial import metadata; it never reads a potentially huge JSON file while the helper holds its upgrade transaction. Import runs afterward through the readiness driver.

Actual old v1-v4 files must preserve every scope/header/member, existing export clock epoch/revision/erasing flag, artifact, prepared/active/retiring Saved record and migration cursor. No destructive rebuild, downgrade, database rename or second backend is involved.

iOS already stores guest models, `GuestLibraryPartition`, deletion intent and Saved/outcome rows in one SwiftData container. This unit needs no new iOS schema. Run existing claim/reopen/new-edit/owner/deletion/export parity tests and explicitly document no-change parity. Later combined observation/view adapters must use one fresh ModelContext and one save, not separate contexts advertised as atomic.

## Interface depth

The public facade still offers guest edits, one-owner queue operations, deletion and export. It hides import snapshots, readiness, SQL locking and ownership validation. A caller cannot accidentally import again or claim half a guest row. This is simpler than asking every caller to handle a cross-store transfer ID, suppression set, cleanup phase and newer guest edits. The deeper helper earns its size because it owns the real invariant: one local transaction for guest ownership and account/journal changes.

## Tradeoffs accepted

- We accept one-time whole legacy JSON decode and possibly large single-owner/guest blobs in exchange for a small additive migration and exact source preservation. Those byte/latency limits remain measured gates.
- We accept moving guest persistence to SQLite in exchange for deleting the permanent cross-store claim protocol.
- We accept waiting for full migration verification before any new guest/account writes in exchange for one unambiguous authority and no partially imported user view.
- We accept explicit local-erasure retry when redundant source-file cleanup fails in exchange for honest private data retention semantics.
- We accept old test-fixture updates in exchange for testing the actual new authority rather than allowing hot code to keep reading stale files.

## Alternatives considered

1. Account rows in DB, guest remains AtomicFile. This keeps guest storage superficially small but requires a durable permanent transfer protocol, suppression of captured originals, new-edit preservation, export union and deletion of in-flight transfer data. It exposes more lifetime states and crash seams than this one-time import.
2. One `GuestStoreFile` row in SQLite. Rejected. It changes the storage engine but retains all-owner decode/rewrite and a shallow compatibility interface; it fails the stated owner-work requirement.
3. Per-owner rows plus a compatibility `readWholeStore()` assembling all rows. Rejected for production. Exact owner methods would still hide an all-owner scan, and a note edit would remain coupled to unrelated private state.
4. Normalize every guest facet and queue operation now. A possible later scale design, but unnecessarily expands this migration. Preserve exact queue semantics in one owned blob first, then measure and address that explicit separate scale gate.

## Synthesis decision

For the parent and judge. I recommend B as the migration base. It eliminates the ongoing two-store ownership problem rather than implementing a permanent recovery protocol around it. Retain Candidate A's crash probes and source-preservation concerns if they expose a missing import case, but do not retain cross-store claim state after DB readiness.

## Open questions and risks

- Can the existing guest/account largest-fixture bytes be decoded and committed within acceptable memory/latency, and which explicit failure should retain an oversized old source for recovery?
- Do any valid historical storage keys contain the delimiter in a way that makes namespace parsing ambiguous, requiring a retained unclassified import row rather than a guessed scope?
- Can exact source-file cleanup failures be injected independently from database write failures so deletion's retained-byte guarantee is actually proved?
- Will existing optional widget tests use the guest-only snapshot correctly, without smuggling account lists back into the production API?

These are bounded implementation/review checks for the parent, not a reason to request cloud permission or stop before local work.

## Concrete units and tests

1. Add v5 tables and guest-only types, plus a real-file migration driver. Test fresh/no-file, old guest-only JSON, full mixed-owner source, defaults, exact note Unicode/whitespace and every queue field. Assert corrupt/truncated source remains byte-for-byte unchanged and no cloud/deletion call occurs. Test malformed/duplicate conflicting owner records fail without publication.
2. Add import checkpoints/readiness. Kill or throw before/after snapshot write, import metadata, each staged row/cursor, verification page and ready commit. Reopen using a genuinely new helper instance each time. Assert unpublished rows never leak, replay never duplicates, exact source hash/counts survive and a stale/restored old file is ignored after ready. Inject marker transaction abort; verify no authority flip.
3. Move guest CRUD and claim to DB. Race two cloned instances on the same note, distinct notes, claims into the same owner and claims into different owners. Assert no lost late edits and exactly one queue copy of each original. Throw after account update but before guest clear; assert full rollback and exact retry. Test invalid originals are retained in recovery once, not silently discarded.
4. Move every one-owner partition method, ACK/terminal settlement and deletion scope read. Seed thousands of unrelated owner blobs, including intentionally undecodable foreign payloads. An operation for owner A and a guest mutation must succeed without decoding foreign payloads. Trace SQL or use query-plan/VM evidence to prove exact indexed rows, not compatibility all-owner assembly. Keep actual corrupt-target tests failing visibly.
5. Make ACK queue+journal changes atomic and account mutations export-clock-visible. Abort the second write with a real SQLite trigger and reopen; both sides must remain unchanged. Mutate pending/notes from a clone after export fence; seal must fail even if Saved/outcome rows are unchanged. Preserve existing private text/token redaction export assertions.
6. Begin deletion atomically with journal fences. Resume from backend response loss, local cleanup interruption, failed source unlink and identity failure. Every clone must reject late account/Saved/outcome writes while deleting. Unrelated guest data and sibling subject/deployment survive exactly. Deleted account plus restored legacy JSON must never be imported again. Verify `identity_pending` is impossible while matching source bytes remain.
7. Upgrade actual installed v1, v2, v3 and v4 DB files, both with and without legacy JSON. Read back existing journal/Saved/clock/artifact fields and exact data. Reopen the v5 result repeatedly; schema creation/import never resets active pointers, generation epochs or deletion flags.
8. Replace tests that directly mutate `guest_store.json` after readiness with direct, narrowly scoped DB fixture seeding/corruption. Keep old-file fixtures specifically for migration and corruption-before-readiness. Replace AtomicFile failure in steady-state receipt tests with actual SQLite abort, retaining the original rollback/retry assertions.
9. Run Android's complete `GuestMergeRaceTest`, guest/widget relevant tests and the existing iOS selected parity suites. Inspect real disk results and independent review before committing. Preserve pending/positions/server-export throughput, recoverable iOS save failure, installed/client/cloud/device and full A2 gates. Runtime Saved cutover remains off.

## Next implementation step

Implement v5 schema, the irreversible verified-import marker and guest-only snapshot API, then prove crash/reopen and stale-file suppression on actual SQLite before moving any normal mutation.
