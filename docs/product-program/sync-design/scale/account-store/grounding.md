# A2 account-store migration grounding

2026-10-22. Read-only how/architect source and test trace against `frame.md`. No design selection, repository/code edits, delegation, cloud or account actions. Parent remains sole implementer; full A2/product program scope unchanged.

## What current callers actually use

`android/app/src/main/kotlin/com/hadithly/app/core/data/GuestStore.kt:125` defines GuestStoreFile as six guest lists plus all syncPartitions and deletion intents. `readLocked` (~177) decodes the entire AtomicFile; absent base and backup means initial empty, damaged JSON means StoreUnavailable without replacement. `writeLocked` (~183) accepts a suspending transform under one GuestDataStore instance's mutex, then `persistLocked` hops to IO and rewrites the whole file. Reopened instances have independent mutexes.

Production `UserLibraryModel.loadGuestData` (`.../UserLibraryModel.kt:370`) uses snapshots only for bookmarks, favorites, notes, progress, folders and memberships. It does not need every account row or deletion list. Its guest projection preserves exact note contents/timestamps, old cached route/text fields and folder links. Guest operations/read helpers use those same guest lists. Optional `features/widgets/ContinueWidgetRuntimeTest.kt:30-31` compares snapshots with GuestStoreFile() only as an empty-fixture guard; lines71/88 remove its own exact guest progress fixture. That compatibility check does not justify reconstructing all account blobs for steady-state guest reads.

Account callers need one owner's LibraryPartitionState via syncPartition(owner), not a GuestStoreFile. It contains exact pending/frozen commands and original source payloads, clientKey/nextSequence, waiting/collecting outcome, ACK intent/link, recent Undo receipts, recovery, confirmed overlays, folder mappings, retention cursor, positions snapshot and legacy joined Saved snapshot. Each account method locates the ownerKey row then checks subject; enqueue requires an existing row and must not recreate one erased behind a captured write context. Ownership and deletion checks cannot be replaced by a caller-supplied user ID.

`syncPartition` (~316), freeze (~345), enqueue (~356), settleExchange/Pending/Retirement (~368-398), cacheSaved/Positions (~462-484), and ordinary guest mutations currently load/write all guest and unrelated account data. That is the specific hot-path coupling to remove. A per-owner state blob still has queue/cache size costs; it is not row-normalized merely because other owners are no longer loaded.

## Claim is a durability boundary, not a network merge

`claimGuestForSync` (~322-343) checks deletion and exact owner subject, opens/creates that owner's state, appends every guest original in deterministic source order (folders, bookmarks, favorites, notes, memberships, positions), then clears all six guest lists in the same AtomicFile replacement. Repeated claim when no new guests exist appends nothing; guest edits made after that commit remain guest data for a later claim.

Invalid folder/note/identity admission does not silently drop the original: `LibraryPartitionState.append` records invalid source in recovery when no valid command can be formed. Membership with unknown timestamp uses claim_if_unset; progress retains exact semantic ReadingPosition when available and otherwise legacy position intent. Frozen command identities/batch digest/receipt sequence survive reopen and are not regenerated on retry.

Do not substitute `GuestMergePlanner.makePayload` (bottom of GuestStore.kt) for migration or claim. That older pure payload helper filters invalid IDs and deduplicates/filters drafts, whereas current durable claim must retain invalid originals as recoverable evidence. Filtering at import would lose private data already accepted locally.

The two candidate seams have different obligations without choosing between them here:

- If guest AtomicFile remains, DB account import and guest cleanup no longer share a commit. A durable transfer identity and exact source evidence are needed so an imported guest claim is not resent under new operation IDs after crash, and cleanup/suppression cannot erase a later edit with the same hadith ID. Target-only cleanup is insufficient; source content/timestamps/identity matter. The preexisting all-file atomicity cannot be claimed across SQLite+AtomicFile.
- If guests move into the same DB, steady-state guest remove/account append can share a synchronous transaction. The one-way legacy-file import still has a cross-file crash boundary and must establish irreversible DB authority before stale legacy cleanup/restore can matter. New guest edits must enter the DB only after readiness, and must never be merged from a stale AtomicFile over a committed DB deletion/claim.

## Every journal wrapper and cross-store dependency

Current LibraryOutcomeJournal v4 owns synchronous `transaction(block:(SQLiteDatabase)->T)` (`.../LibraryOutcomeJournal.kt:291`) using begin/setSuccessful/end on one thread. Its operations do not suspend. GuestStore wraps most calls in withContext(IO); the existing suspend transform cannot be placed around a thread-local SQL transaction that survives IO hops.

Account/journal coordination currently has these distinct shapes:

- settleSyncAcknowledgement (~400): validate owned reply/cursor, compute next partition state, mark journal ACK with acknowledgedAt first, then AtomicFile partition replacement. A failed file write leaves journal ACK evidence; retry must preserve its original age and settle once.
- pruneOutcomeSuccessStep (~416): reads all deletion scopes, prepares export inventory, reads bounded journal retention entries, loads corresponding owner partition dependencies, prunes a journal chunk, then saves sweep cursor to file. Missing owner partition retains evidence. Interrupted prune persists its own row checkpoint.
- settleCollectedOutcome (~450): reads durable journal terminal checkpoint, computes exact queue/recovery/ACK transition from that owner's state, then writes state. It cannot declare settlement before that durable account transition succeeds.
- collectOutcomeStep (~615): checks captured session and account/deletion, captures journal generation/open checkpoint, awaits network outside lock, then rechecks current scope/account and commits one page. outcomeEvidencePage (~639) is a direct IO journal call.
- Saved begin/checkpoint/raw/prepared/active page, replace, cleanup and activation wrappers (~552-613) use journal transactions with durable epoch/generation/erase checks; network collection/final activation awaits occur outside SQL transaction. Those calls currently do not all load the whole-file account authority; do not assume migration gating only readLocked/writeLocked reaches every entry point.
- prepareOutcomeExport (~677) clears abandoned artifacts, reads deletion scopes, incrementally prepares journal inventory, then captures owner fence. validate/entries/page/register/seal validate current account via AtomicFile before the corresponding journal call. savedExportRecords uses the journal fence directly. Artifact directory create/remove/atomic rename is filesystem work with separate resumable metadata.

A shared DB migration therefore must gate every authority-bearing entry point while import is incomplete, including direct journal/Saved reads and cleanup—not merely replace the obvious account CRUD methods. Existing helper methods start their own synchronous transactions; future combined operations need a same-thread/same-database composition seam, without a suspend transform or a whole-GuestStoreFile-shaped account compatibility read.

## Migration/readiness and cloned-instance hard constraints

Legacy import may require a one-time full JSON decode. That exception does not justify full decoding on every staged row or normal call. Preserve source until validation/import readiness is durable; staged rows are not partial account/guest authority. A single durable readiness/authority decision must make every later reopened helper ignore a restored legacy base or backup, otherwise cleared guest drafts/deleted accounts can resurrect. Cleanup failure must not revoke DB authority. Malformed legacy JSON must remain intact and visible as failure; do not fall back to empty.

The authoritative row key/subject must be validated before importing any account. Duplicate owner keys, conflicting subjects or duplicate deletion scope records cannot be resolved with silent last-wins data loss. An absent legacy file and a corrupt existing file are distinct. Existing old JSON defaults for missing folders/partitions/deletions remain compatibility requirements.

Cloned instances share the actual SQLite locking/CAS boundary; their separate Kotlin mutexes are insufficient. Imported exact frozen/client/receipt/recovery state must remain identical across interrupted import/reopen. No migration step may run a normal guest/account write against an uncoordinated legacy file while other rows are being imported.

## Deletion and export lifecycle

Deletion intent is scoped by subject+namespace, not global subject alone. beginDeletion (~489) persists SERVER_PENDING before installing shared Saved erasure fence; account caller invalidates sync before suspension. Backend completion (~499) performs bounded Saved cleanup, artifact/outcome erasure, removes only matching account partitions and advances IDENTITY_PENDING. Identity deletion failure resumes without server bootstrap/generation. Unrelated guest data, sibling users and same-subject other deployments survive. clearDeletion is last, after identity success.

An import/readiness decision must not resurrect old deletion phases or deleted owners from the stale file on the next process start. Preserve existing active Saved/outcome clocks and orphan evidence when adding account tables. Do not add cascade deletion from account rows to Saved/outcome evidence: old-owner partitionless evidence is intentionally exportable, and cleanup is explicitly bounded rather than implicit whole-tree cascade.

Current portable export (`LibrarySync.kt:portableState/preparePortableExport`) snapshots only captured owner's partition, strips provider passages, then streams retained outcome/Saved rows for that subject/namespace under journal mutation fence. Guest rows are not automatically owned by the signed-in account. Unifying storage does not authorize exporting all unclaimed guest notes as account data. Existing shared journal clocks cover Saved/outcome changes; not every partition/guest mutation currently advances that fence. Full export/partition consistency and scale remain distinct work unless explicitly migrated here.

Artifact directory cleanup cannot be made atomic with SQL by pretending filesystem deletion is a transactional DB statement. Retain durable metadata/retry rules. Readiness and deletion must cover imported/staged private values as well as live rows, even when an old owner lacks a live account partition.

## Concrete regression fixtures to retain or migrate

All Android references below are `android/app/src/androidTest/kotlin/com/hadithly/app/GuestMergeRaceTest.kt`:

- `frozenClaimSurvivesReopenWithoutClearingOtherOwnerOrNewEdits` (~2089): exact frozen batch after reopen; later guest note survives account settlement; wrong owner rejected.
- `verifiedSubjectMismatchLeavesGuestDataUnclaimed` (~2126) and `capturedWritesCannotFollowAccountSwitchOrRecreateErasedPartition` (~2144): failed binding does not claim; old captured context cannot affect sibling owner or recreate erased row.
- `corruptStoreIsRetainedAndReportedThroughExistingSavedErrorState` (~2172): damaged original file survives reads/writes and UI reports failed. `legacyFileWithoutPartitionsMigratesAndKeepsExactPrivateText` (~2198) preserves old minimal JSON note through exact durable frame/reopen.
- `outcomeSettlementWriteFailureKeepsFrozenAndRetryAdvancesOnce` (~1450) uses filesystem permission failure, asserts partition unchanged, reopens and settles once. Another ACK write-failure fixture (~1221) proves journal-first timestamp is not renewed on retry. After DB authority, inject a real failing SQL transaction at the equivalent state commit; retain the rollback/retry assertions rather than expecting guest_store.json permission changes to govern the new store.
- Direct file fixtures around461 (old-owner partition removal),1013/1084/1200/1242 and1929/1959 seed/corrupt retained account state. Update their authority-targeted fixture setup when live authority moves, preserving missing-partition/export/ownership and exact-frame assertions. Keep genuine pre-import/old-file cases as legacy tests.
- `deletionSurvivesResponseLossRestartAndIdentityFailureWithoutBootstrappingOrErasingOtherScopes` (~1735) and `deletionRejectsWrongPreparationAndFinishesOnlyCapturedLocalErasureAfterSwitch` (~1780): preserve server-vs-identity phases, scope, no bootstrap, and local completion after account switch.
- Existing SQLite v1/v2 upgrade, v3->v4 Saved activation, suspended erasure/reopen, partitionless export, actual SQLite abort and bounded-query-plan tests cover journal retention. New additive schema may not rebuild those tables or discard their data.

## iOS matching no-change parity

`ios/Hadithly/Core/GuestData/GuestDataStore.swift:claimGuestForSync` (~337) already fetches guest SwiftData models, appends exact sources to one owner JSON partition, deletes claimed guest models and saves in one context with rollback. `GuestLibraryPartition.stateData` is still one owner blob. It shares the ModelContainer with Saved/outcome models, though existing helper calls use separate fresh contexts/commits; sharing the file alone is not proof a future activation+partition update is atomic.

beginDeletion (~568) saves intent+shared erase clock together; backend-complete cleanup preserves scopes and identity phase; exports already stream journal/Saved evidence plus captured partition. Relevant `ios/HadithlyTests/GuestMergePlannerTests.swift` tests include frozen claim (~2104), account erasure/orphans (~1006), deletion response-loss/identity failure (~1723), switched deletion (~1784), private portable export (~1825), Save logical rollback (~464), old-schema migration (~548), and suspended erase (~511). Preserve these as no-change parity now; later same-context authority adapters are separate cutover work. Recoverable injected iOS save failure remains unproved.

This record grounds candidate comparison only. It does not select guest-vs-account migration architecture, normalize the whole queue, change production Saved consumers, close deployment/SDK/device/cross-device gates, or complete A2.
