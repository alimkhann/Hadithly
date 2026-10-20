# Candidate A: partition-owned terminal settlement

## Problem

A complete manifest journal is durable, but the native partition still retains `collectingOutcome`, a matched frozen batch or historical recovery, and no ACK intent. The journal and Android AtomicFile cannot commit together. Settlement must bind the exact receipt to the still-current owner and original command, wait for an authoritative Saved revision, preserve partial or unavailable evidence without copying member rows into JSON, then make ACK retryable. Current coordinators deliberately stop at terminal collection (`GuestMergePlanner.swift:1039-1055`; `LibrarySync.kt:616-633`); Saved subscriptions cache snapshots but do not wake them (`UserLibraryModel.swift:453-461`; `UserLibraryModel.kt:321-331`).

## Usage (caller's view)

```text
// LibrarySync run loop, ahead of poll/ACK/freeze/send:
let state = store.syncPartition(owner)
if let collection = state.collectingOutcome {
    let checkpoint = await store.collectOutcomeStep(collection.committed, owner, ...)
    switch store.settleTerminalOutcome(owner, collection, checkpoint, now) {
      case .collecting: continue                // one bounded page/verification step
      case .awaitingSaved(let revision): return // no timer or page polling
      case .proofUnavailable: failClosed()      // no ACK
      case .settled: onPartitionChange(owner); continue // next loop sends persisted ACK
    }
}

// Owned Saved subscription, after a successful cache write:
try store.cacheSavedSnapshot(snapshot, owner)
reloadAccount(owner)
sync.savedRevisionArrived(owner, session, epoch, snapshot.version) // wakes only same active session/owner

// Settings recovery/export reads partition pointer plus bounded journal pages.
// The view never receives a guessed restored member set.
```

## Shape

`LibraryTerminalDecision = collecting | awaitingSaved(requiredRevision) | proofUnavailable | settled`. One deep store call `settleTerminalOutcome(owner, expectedPending, checkpoint, now)` owns all validation and partition mutation. `expectedPending` must equal the persisted `collectingOutcome`, including exact `SyncCommitted` and origin. The store reconstructs `LibraryOutcomeBinding` from verified receipt and captured owner, then reads the persisted journal header under its erasure generation; a caller-supplied checkpoint is only a hint. `complete` means locally verified counts exactly equal receipt totals; `unavailable(detail_unavailable)` is a different terminal case that may settle only under a recoverable policy. `unavailable(proof_unavailable)` and collecting/verifying cannot settle. Validate client key, sequence, batch ID, digest, reply owner, receipt ID/revision/phase, manifest/generation, Saved revision and journal authority. A matched origin additionally rehashes the current frozen batch and compares stored `intentDigest`, exact operation ID/revision, command kind and full `frozen.changes.map(operation)==batch.operations`; a same-ID different command becomes historical, never confirmed. A historical origin must have no matched frozen source and never synthesizes one.

The partition is the owner of sequence/ACK transition. On `complete` plus `savedSnapshot.ownerKey==owner.key` and `savedSnapshot.version>=committed.revision.saved`, build a new partition value once: clear `collectingOutcome` and matched frozen, advance exactly one sequence, set `acknowledgement` to the committed client/sequence/batch/digest, retain later pending writes, and preserve ordinary confirmed overlays independently. Do not create a confirmed folder-restore overlay; the authoritative snapshot already supplies membership. For matched restore, map `"restore:"+deletionId` to receipt `folderId` before releasing frozen so later queued local-folder references resolve. Preserve any existing mapping without replacing a conflicting value silently. For matched delete, add the same short-lived `recent` receipt/Undo deadline used by inline settlement, calculated from operation time; retain its journal original identity set. History/recovery is a **compact journal reference** (`binding key`, exact proof, kind, terminal status, expected/collected counts, and `sourceAvailable`), never member arrays. Add it for any partial restore, any explicit detail-unavailable result, or a historical origin; a fully successful matched result may omit a recovery notice, but the journal remains exportable. The referenced journal retains locally available original source/command when needed: attach it idempotently to the header before changing JSON, guarded by exact intent digest and erasure generation. This header mutation increments the journal export clock. No new ACK/prune marker is added.

For `detail_unavailable`, first preserve the verified proof, collected prefix and original source (if matched) in the journal; then use the same owned Saved revision barrier and write a recoverable `detailUnavailable` pointer before ACK. Never label the prefix complete or infer identities. If source attachment/journal verification fails, JSON is untouched. Android order is **journal source transaction → AtomicFile partition save → server ACK**. A crash after journal source but before JSON simply retries idempotently; a crash after JSON but before ACK resumes ACK without replaying recovery or incrementing sequence. iOS may save both under SwiftData, but the same order/replay rule works with its separate contexts. Keep all journal headers/rows after ACK, including fully successful ones: pruning is another unit and no retention claim follows from this transition.

The store should build the next partition as a copy and save it atomically, as current `settleSyncExchange` does (`GuestDataStore.swift:395-405`; `GuestStore.kt:365-377`). It never calls the server. The coordinator checks generation/session before collection, after each await, before settlement and before ACK. `savedRevisionArrived` is a small coordinator signal: require active owner/session/epoch, confirm the cached owned version at the store, and call existing `wake()` only when a terminal collection is waiting for that revision. The run loop returns without timer while below the barrier; Saved delivery or reactivation restarts it. If subscription fails, keep the state and surface failure; do not spin or ACK. Projection keeps the bounded restore suppressed and ends matched delete overlay at the Saved barrier (`LibraryProjection.kt:26-30`; `UserLibraryModel.swift:646-650`).

Module map: pure `terminalDecision(partition, journalSummary, owner, now)` beside `LibraryPartitionState`; `GuestDataStore`/`GuestStore` perform journal-source then partition commit; `LibrarySync` owns wake/ACK sequencing; both `UserLibraryModel` subscription callbacks emit the owned Saved-revision signal. Journal/export can resolve compact recovery pointers by indexed pages. This hides all page, origin and crash rules behind one store operation (boundary-discipline, idempotent operations).

## Synthesis decision

Candidate A is the partition-owned base for comparison. Prefer it if the alternate journal-owned state machine cannot remove a real replay hazard without growing the caller surface.

## Tradeoffs accepted

- We accept retaining every journal after ACK in exchange for a small safe settlement unit without premature pruning metadata.
- We accept a bounded source attachment before Android's JSON save in exchange for preserving original Undo/recovery evidence across a two-store crash.
- We accept waiting for the owned Saved revision, even after terminal collection, in exchange for never projecting a guessed partial restoration.

## Alternatives considered

A journal-owned ACK lifecycle would make SQLite the source of sequence truth on Android, but then every existing partition path, replay, export and iOS equivalent must reconcile two mutable authorities. Its interface exposes cross-store state to the coordinator. Applying every collected identity to partition JSON would avoid a Saved barrier but rewrites an unbounded array and can override newer server changes. The current authoritative Saved snapshot plus compact pointer is deeper and smaller.

## Open questions and risks

Does the existing short Undo window still need a `recent` receipt when the async delete finishes after its operation timestamp has expired? Can all old Undo callers consume the journal-backed deletion authority before public cutover? Can the existing whole-file Saved snapshot and server export be bounded independently? These are gates, not settled by this design.

## Next implementation step

Write red real-store/coordinator tests for matched/historical partial restore, detail-unavailable source retention, sub-revision wait and Saved callback wake, ACK lost/reopen, and same-ID different-command fork; then add the one store transition and callback signal.
