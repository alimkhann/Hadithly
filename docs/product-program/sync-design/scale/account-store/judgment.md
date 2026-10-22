# Android local-state migration cross-judgment

2026-10-22 at source `9e2eab9`. Read-only architect/arena judgment. Read both candidates completely, frame and grounding; checked actual GuestStore account/guest/claim/ACK/deletion and direct Saved/outcome/export wrappers, LibraryOutcomeJournal transaction ownership, and existing v4 boundary. No source/repository edits, delegation, cloud action or gate approval. Parent remains sole implementer. Tests underway in the parent are not claimed as evidence here.

## Recommendation and rubric

Select **candidate B: guest singleton plus per-owner account and scoped deletion rows in the existing SQLite database**. No user requirement keeps guests in AtomicFile. Moving them removes the permanent claim transfer protocol rather than maintaining it forever. One-way legacy import still requires careful crash recovery, but that complexity ends at irreversible readiness.

| Criterion, five points each | A | B | Rationale |
|---|---:|---:|---|
| No loss, duplication or resurrection across crash boundaries | 4 | 4 | Both explicitly preserve exact originals and stale-file suppression. B has fewer steady-state boundaries. Its final readiness/fence staging and import-lock details need the corrections below. |
| One actual DB ownership/transaction and cloned-instance correctness | 3 | 5 | A requires DB plus revisioned AtomicFile plus permanent receipt/locking protocol. B's normal claim and queue/journal updates are actual single-DB transactions, using current rows rather than stale facade snapshots. |
| Per-owner steady-state work and honest bounded import/readiness | 4 | 4 | Both remove all-owner blobs from normal reads and admit one-time whole legacy decoding. Neither normalizes a huge individual guest/account blob. B's stated all-deletion-fences final publication must be bounded before implementation. |
| Deletion, export, privacy, installed schema and iOS parity | 4 | 4 | Both preserve journal rows and scope-specific cleanup and retain open physical/installed gates. B explicitly includes source-file residue, account export-clock bumps and no-change SwiftData parity; wrapper gating and orphan evidence require systematic proof. |
| Simple deep interface and practical implementation/test path | 2 | 5 | Same public facade, far fewer durable states in B. A hides a substantial stable-lock/revision-envelope/permanent transfer-receipt subsystem solely to retain an unrequired storage split. |
| **Total** | **17/25** | **22/25** | **B is the stronger base after the required corrections.** |

These are design-artifact scores. They do not certify correctness or close any implementation/runtime gate.

## Required corrections before implementation

### Keep readiness publication bounded

B's import step 8 says to install erase fences for imported deletion intents in the final readiness transaction. If a legacy file has thousands of deletion scopes, this makes the final transaction unbounded even though account rows were staged eight at a time.

Stage and verify required deletion fences in bounded transactions before final ready publication, or encode an equivalent indexed staged-deletion guard consumed by every authority path. If staging actual existing shared clocks/erase fences, never clear or replace an existing erasing epoch as a side effect of import. The final transaction must check a complete verified checkpoint/digest and flip one readiness marker; it must not enumerate all imported scopes. All new facade authority paths remain blocked while readiness is incomplete, so staged changes cannot become partial account/guest authority. Verification must account for preexisting journal data, not fabricate a new clock incarnation that makes existing evidence disappear.

The zero-source/fresh-DB path also needs explicit ready publication. An absent old file is a legitimate empty import; an unreadable/corrupt base or recoverable AtomicFile backup is not absence.

### Make import capture serialize cloned helpers correctly

Graft A's canonical-path same-process serialization in addition to the stable file lock for import capture. A FileChannel lock alone may throw OverlappingFileLockException when separate instances in the same JVM overlap; it is not automatically a waiting mutex. Keep the lock file path stable; do not lock a file that AtomicFile replacement changes.

This is an import-only mechanism in B. After ready, ordinary guest/account/claim operations rely on SQLite transactions, not a new permanent file lock. Enter IO before synchronous locking/capture/DB work. Never retain a thread-local SQL transaction across `withContext`, `yield`, network work or another suspension. If import runs over multiple facade calls, durable DB checkpoint/CAS and immutable source identity must make concurrent resume steps idempotent; do not require holding a file lock across coroutine suspension.

Snapshot-before-metadata is the correct capture order. Crash after snapshot but before metadata requires a defined orphan-snapshot recovery check under the lock. After metadata commits, all restarts resume the exact captured digest; they must not recapture a newer file over staged state. A detected unsupported old writer must retain both source versions and fail publication. Do not claim protection against rollback of the entire database history or a separately running old binary that ignores the new protocol.

## Same-thread transaction ownership

Actual `LibraryOutcomeJournal.transaction` owns `beginTransaction/setTransactionSuccessful/endTransaction` synchronously. Actual GuestStore `writeLocked` currently accepts a suspending transform and ACK settlement calls `withContext(IO)` inside it before the later AtomicFile write. That shape cannot be reused as a generic transaction lambda after migration.

The safe seam is facade enters IO, then a meaningful helper operation loads its selected current rows, invokes pure policy and writes them on the same thread/connection before return. Introduce internal database-parameter helpers for ACK metadata, export clock, deletion fence and account-row mutation. Do not compose public helpers that each open their own independent transaction and call that atomic. Decode a fresh mutable LibraryPartitionState only after transaction start; a failed transaction must not leave a cached instance mutated for retry.

For cloned instances, two guest changes read the current guest row within their respective write transactions. Claim reads current guest plus selected account rows and clears/appends in that same transaction. A facade-local mutex may control UI activity but is not the data invariant. Returned account objects are detached snapshots; callers cannot persist them later without current-row transaction policy or explicit revision CAS.

Future Saved private activation/effective view publication can then share this DB boundary; this migration itself must leave production Saved read mode unchanged.

## Readiness must cover the actual wrappers

Changing only `readLocked/writeLocked` misses existing direct journal calls. Parent should maintain an explicit entry-point matrix covering:

- Guest snapshots and every guest mutation; account read, claim, freeze/enqueue and all settlement variants; deletion read/start/finish/clear/reset.
- Outcome capture/open, post-network persist, terminal settlement and retention.
- Saved checkpoint/raw/prepared/active reads, candidate replacement, fold/persist/activation and cleanup.
- Export inventory preparation, fence capture/validation, Saved/outcome streamed rows, artifact registration/seal/share validation and cleanup where it admits private authority.

Every authority-bearing production path needs durable readiness inside the selected DB operation, not solely a cached facade boolean. Import driver/internal upgrade helpers may operate before ready by an explicit internal seam. Network remains outside transactions, and post-await writes recheck captured session/owner plus DB deletion/incarnation.

Do not turn an account-existence check into a cascade data-loss rule. Existing old-owner **partitionless** Saved/outcome evidence must remain retained and exportable to the correct subject/deployment after ready. A current account operation cannot recreate an erased owner, but historical evidence reads/retention/export should not require inventing a live partition for its old owner. Keep scope validation and new-authority admission separate.

## Legacy retained bytes, deletion and export

B correctly recognizes that ignored bytes are still retained private data. A ready marker prevents resurrection; it does not erase old guest_store.json, backup/new variants or immutable import snapshot. Once ready, those files are globally redundant because all source owners and guests exist in DB. Deleting the fixed redundant set can preserve unrelated users in DB without rewriting multi-owner JSON. Verify unlink/remaining-file state before local deletion reaches identity_pending. Failed cleanup retains a durable retry state; ready remains irreversible.

The import snapshot/receipts are not an authenticated owner's export payload. Before ready, refuse partial exports. After ready, export the captured owner's partition plus all retained matching journal/Saved stages, including old partitionless evidence, under the shared clock. Guest data remains anonymous/unclaimed and is not automatically included. No export path may copy the raw multi-owner source snapshot into one account artifact.

B's account mutation clock extension is valuable: a clone changing pending/confirmed/recovery/positions/receipts must invalidate a captured export even when Saved/outcome pages did not change. Extend empty-clock removal predicates to account rows and retained artifacts so cleanup cannot destroy the fence early. Do not reset existing clocks during v5 import. Actual filesystem artifact effects remain independently resumable, outside any claim of SQL atomicity.

Import preserves exact deletion phase and scope. Identity_pending is not permission to recreate a missing account. Clearing an intent must not clear DB readiness, revive old file authority or reset a live erase generation. Account deletion excludes the guest singleton and sibling scopes.

## Grafts and rejections

Graft from A into B:

1. Stable canonical-path in-process admission plus file lock for import capture, with the same-process overlapping-lock counterexample.
2. Exact legacy namespace/storage-key validation and preservation on malformed or ambiguous historical keys. Check the actually admitted namespace convention; never silently split arbitrary strings into another privacy scope.
3. Crash probes for identical-value remove/re-add, two owners racing to claim and late edits. In B these prove current-row SQLite ownership without introducing source-revision transfer receipts.
4. Keep fixture assertions about exact frozen/client/sequence/ACK/invalid-source recovery, source corruption and private note bytes. Move steady-state corruption/failure injection to the real DB authority rather than weakening the old assertions.

Reject from A:

- A permanent guest_v3 AtomicFile, stable locking on every guest operation, imported/cleaned transfer phases and permanent suppression tombstones. These solve a boundary B eliminates and expand deletion/export states without a product requirement.
- A whole GuestStoreFile-shaped compatibility read that reconstructs all account rows. Both candidates reject this; do not reintroduce it merely to minimize test edits.

Reject shortcuts in either candidate:

- One giant DB row containing the old all-owner file.
- Decode/modify outside a transaction followed by unconditional replace from a stale clone.
- Run legacy JSON decoding in SQLiteOpenHelper.onUpgrade.
- Drop/rebuild journal/Saved tables on upgrade or cascade old partitionless evidence when an account row disappears.
- Claim bounded bytes/normalized queue scalability merely because account rows are separately keyed.

## Concrete verification priorities

1. Keep the parent's currently red clone tests as regression evidence, then run them against current-row DB operations. Add two helper instances racing distinct guest edits, same target updates, same/different owner claims and deletion; verify exact original counts and no late-edit loss.
2. Real v1, v2, v3 and v4 DB upgrade fixtures preserve existing Saved prepared/active/retiring records, outcome headers/members, clocks/erase flags, artifacts and export migration cursor. Add old guest-only and full mixed-owner JSON. Exact field/readback equality is stronger than merely opening v5.
3. Fault before/after snapshot, metadata, each bounded staging/receipt/checkpoint transaction, verification, deletion fence stage and final ready commit. Reopen a fresh helper each time; incomplete rows never authorize use. Restore stale legacy files after successful claim and account deletion; they must never reimport.
4. Real SQLite trigger abort between account update and guest clear, and between journal ACK metadata and account cursor, must roll back both sides. Reopen and retry advances once; don't rely on legacy file permission failure after authority moved.
5. Seed many unrelated account blobs including invalid foreign JSON; exact owner and guest operations must not decode them. Use actual query plans/work instrumentation. A corrupt selected owner still fails visibly. Separate tests cover malformed/conflicting legacy import rows without partial publication.
6. During migration, direct Saved/outcome/export/cleanup wrappers must not bypass readiness. After ready, account partition removal must leave old journal evidence retained/exportable and must not bootstrap a replacement account.
7. A cloned account-only mutation after export fence invalidates seal. Exact selected subject/deployment export excludes foreign and unclaimed guest data. Deletion unlink failure prevents identity_pending; retry clears retained source bytes without touching sibling DB state.
8. Run the full Android GuestMergeRaceTest and relevant guest/widget checks, then selected iOS claim/reopen/new-edit/ownership/deletion/export suites as explicit no-change storage parity. iOS already has one SwiftData container; no invented migration or broad platform rewrite is needed.

Full pending/positions/server export throughput, large blob latency, actual iOS save-failure recovery, installed-client/backend-first rollout, real SDK/JWT, cross-device, physical-device and full A2/product gates remain open. This judgment approves no gate or deployment. Parent can implement the local B schema/import/atomic ownership unit after recording these corrections.
