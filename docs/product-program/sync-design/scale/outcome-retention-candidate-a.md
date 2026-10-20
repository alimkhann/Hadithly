# Candidate A: exact ACK link, then conservative journal pruning

## Problem

Terminal settlement now persists a compact recovery entry when needed, advances the partition and saves ACK intent, but `settleSyncAcknowledgement` forgets the ACK after adopting the server cursor (`GuestMergePlanner.swift:855-862`; `LibrarySync.kt:381-391`). Journal rows and export inventory therefore remain forever. SwiftData partition JSON and Android AtomicFile are separate from the row journal, so an ACK marker and cursor adoption need an explicit replay order. Success cleanup must not discard a deletion needed by queued offline Undo, recovery or export, and must not repeatedly examine only the first retained headers.

## Usage (caller's view)

```text
// store.settleTerminalOutcome, inside the existing atomic partition save:
partition.manifestAck = ManifestAckLink(bindingKey, exactAck, savedRevision, origin=.matched)
partition.acknowledgement = exactAck

// LibrarySync ACK branch, one server request as today:
let reply = await transport.acknowledge(capability, ack)
try store.confirmAcknowledgement(reply, requested: ack, owner: owner)
// store verifies exact link/reply, marks journal ACK, then adopts cursor

// app startup / after journal or partition change, outside network path:
try store.pruneOutcomeSuccessStep(now: now, maxHeaders: 50, maxMembers: 50)
// one bounded progress step; repeat by fair scheduler, stop on storage error
```

## Shape

Add optional `ManifestAckLink` to `LibraryPartitionState`: exact `LibraryOutcomeBinding.key`, captured owner/subject/namespace, clientKey/sequence/batchId/digest, savedRevision and `pruneClass=successCandidate|retain`. Write it with `acknowledgement` in the **same** partition commit as terminal settlement. This is a single outstanding link, not a growing list. Old partitions without it are conservative: their journals have no pruning proof. A historical, unavailable or partial result uses `retain`; only matched `complete` with all receipt categories successful and no compact recovery entry is a success candidate. Retain journals with any recovery pointer, including locally available original text/source. `manifestAck` is consumed only by an exact server ACK response; ordinary ACKs have no link.

`confirmAcknowledgement(owner, requested, reply)` validates the active partition still holds that exact ACK and link, the owner-bound reply client key, and `reply.cursor.closedThrough >= requested.sequence`; its committed next slot may be different and must be validated by existing cursor logic. It reopens the exact journal binding and asserts verified `complete` with the same erasure generation and receipt totals. Then, under the native store's single writer serialization, write `ackedAt` and `pruneClass` into the journal checkpoint **first**, bumping the subject+namespace export clock in that same SwiftData save/SQLite transaction. If already marked with the same exact proof, keep the first `ackedAt`; a conflicting proof fails. Only after that commit does the store adopt the reply cursor and clear `manifestAck`/ACK intent in one partition save. If journal write fails, partition ACK remains retryable; if partition save fails, exact server ACK can be retried and the idempotent journal marker is reused. An unlinked or malformed response never marks a journal. The marker alone never permits pruning while the partition still has that outstanding ACK link.

Checkpoint metadata is `retention: none | acked(exactAck, ackedAt, pruneClass) | pruning(nextOrdinal, exactAck, ackedAt)`. This is deliberately smaller than a separate certificate ledger. Every metadata transition increments the existing journal export clock atomically. `none` includes all installed pre-feature data, so it is retained. `pruning` is irreversible; the header stays in inventory until the last member batch is deleted. Export started before it fails its revision fence; export started during `pruning` fails explicitly rather than presenting the remaining prefix as complete. After the final bounded batch, delete header and inventory entry in one journal transaction and bump the clock. The account-erasure fence still wins over cleanup, and an erased/missing owner scope cannot be recreated by a late worker.

Eligibility is a pure `canPrune(header, partition, now)` evaluated under the same iOS MainActor/Android `GuestStore` mutex used by enqueue, settlement and account erasure. Require exact `acked(successCandidate)`, verified complete counts, `now >= ackedAt + 30 days`, an owned Saved snapshot with version at least `savedRevision`, an extant matching partition, no outstanding manifest ACK link, and **no** reference to the deletion operation ID or journal binding in pending, frozen, waiting/collecting, recovery (server/historical/rejected/outcome), or recent Undo receipts. For a restore result, also preserve it if recovery or a queued local alias still refers to its restore operation. Read only compact partition commands/metadata, never the manifest member set. A blocked header stays intact; no rows are removed. Claim by changing checkpoint to `pruning(ordinal=0)` in one journal transaction only after eligibility passes. Later pages delete at most 50 member rows and advance ordinal in the same transaction; duplicate/restarted workers resume from persisted ordinal. At that point newly admitted restore commands referencing the pruned parent deletion must fail local admission with an explicit expired-evidence reason. Admission uses positive local authority (retained eligible deletion handle/recent receipt or already-queued predecessor), so absence after final header deletion cannot masquerade as recoverable Undo. An offline restore queued **before** claim blocks eligibility. Do not promise reconstruction of already deleted facts after a new late restore.

Fairness: a persisted global scan cursor walks the indexed `(subject,namespace,collectionKey)` header inventory in batches of at most 50, then wraps. It advances past blocked headers; a separate active-pruning cursor resumes one claimed header in 50-row steps, yielding to the header scan after each step. Thus permanently retained first-page entries cannot starve later eligible headers. Cursor, `pruning` progress, index removal and clock updates share journal transactions. A missing partition means retain, not infer safety. The scheduler may run at startup and after relevant writes, but one invocation has a fixed work budget and never loops over all members. Errors stop without altering unrelated data.

Module map: `LibraryPartitionState` owns the bounded link and pure dependency scan; `GuestDataStore`/`GuestStore` expose `confirmAcknowledgement` and `pruneOutcomeSuccessStep`; `GuestOutcomeHeader`/SQLite `headers.checkpoint` own ACK/prune metadata; `LibrarySync` keeps its existing ACK request and calls the new store method; export rejects `pruning`. No view or transport sees a cleanup cursor. The interface hides two-store replay and fairness behind two store calls (idempotence, boundary discipline).

## Synthesis decision

Candidate A is the minimal partition-owned base. Prefer it if the alternate journal-owned ledger adds another sequence authority without closing a concrete replay gap.

## Tradeoffs accepted

- We accept retaining all old, historical, partial, unavailable and recovery-dependent journals in exchange for never deleting unproved user evidence.
- We accept a small ACK link in the whole-file partition and a journal-first marker in exchange for replayable two-store ACK confirmation without a third ledger.
- We accept a durable irreversible-prune admission boundary in exchange for bounded success cleanup; a new late Undo cannot claim facts already deleted.

## Alternatives considered

A journal-owned ACK/cleanup queue could make the journal the sole retention scheduler, but it must reconcile partition ACK, queued Undo and owner state after every crash; that exports more lifecycle state to callers. A time-only 30-day TTL is smaller in code but can delete offline Undo dependencies and expose a half-pruned export. The exact link and one checkpoint state give the deeper interface.

## Open questions and risks

Can old Undo callers be migrated to positive local deletion authority before any deletion journal is pruned? Is the current partition scan still bounded enough once installed whole-file data grows? Can iOS SwiftData and Android SQLite migration add nullable retention fields without losing old rows? These remain explicit cutover gates, as do hosted/device proof and public producer.

## Next implementation step

Write crash/reopen tests for journal-marker-first versus failed partition save, exact ACK with a later cursor slot, queued offline Undo blocking claim, a late post-claim Undo rejection, a retained first-page header followed by an eligible one, and export during interrupted 50-row pruning.
