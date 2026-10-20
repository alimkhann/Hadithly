# Candidate B: journal-owned settlement certificate and ACK reconciliation

## Usage first

```text
LibrarySync drain(capturedSession):
  if partition.collectingOutcome:
    progress = store.advanceOutcomeSettlement(capturedOwner, expectedCollection)
    switch progress:
      collectPage: fetch bounded page and persist through existing journal
      waitSaved: return idle (no timer, no failure)
      blockedProof: return recoverable failure (never ACK)
      readyAck: continue existing ACK branch
  if partition.acknowledgement:
    reply = transport.acknowledge(binding, exactAcknowledgement)
    store.confirmOutcomeAcknowledgement(owner, exactAcknowledgement, reply)

Saved facade callback(snapshot, capturedOwner, subscriptionEpoch):
  require current owner/session/epoch
  store.cacheSavedSnapshot(snapshot, capturedOwner)
  sync.savedSnapshotPersisted(capturedOwner) // wake after successful durable save
```

Coordinator owns one coalesced wake signal and drain worker per active captured context. Views do not coordinate journal/partition state. A wake received while draining sets a dirty bit; the drain consumes it before idle, preventing lost wake between barrier check and suspension. On activation/reopen run the same transition once, even without a new subscription event.

## Grounding and problem

Current `LibraryPartitionState.settle/adopt` persists collectingOutcome with exact committed authority and matched fingerprint or historical origin. Swift `settleReceipts` and Android equivalent reject manifest receipts. Both coordinators inspect collectingOutcome before poll/ACK/freeze and terminal journal currently fails. Store `cacheSavedSnapshot` persists owned versions, but iOS UserLibraryModel Saved callback and Android callback only reload projection; neither wakes the drain. Android journal SQLite and AtomicFile partition are distinct persistence boundaries. iOS journal uses separate SwiftData ModelContext saves from partition JSON. There is no honest atomic cross-store settlement today.

## Shape

```text
SettlementCertificate = {
  collectionKey, authorityDigest, receiptIdentity, capturedOwnerIdentity,
  origin: matched(frozenIntentFingerprint) | historical,
  decision: completeSuccess | completePartial | recoverableDetailUnavailable,
  requiredSavedRevision, originalDigest?, originalSource?, terminalCheckpointDigest,
  state: prepared | partitionApplied | ackConfirmed
}
PartitionSettlementLink = {collectionKey, certificateDigest, sequence}
OutcomeProgress = collectPage | waitSaved(requiredVersion) | blockedProof | readyAck
```

One certificate per exact collection key, stored beside immutable journal facts. Certificate state is monotonic. No member identity arrays or growing lifecycle history. OriginalSource is at most the existing one frozen folder operation's local source (bounded command/source admission); if legacy source itself is oversized, preserve via a separate bounded original-source record stream, never silently truncate. Certificate stores the original actual bytes or references to durable original rows, not only a digest that cannot recover a note. Historical origin never synthesizes matched source.

`LibraryOutcomeJournal` owns authority validation, certificate preparation/ACK marker and recovery evidence. `GuestDataStore` owns copying that certificate's deterministic projection into partition state. `LibrarySync` drives one high-level advance/confirm API. Journal is the durable record of why a manifest may settle; partition is its replayable working projection. This deliberately adds cross-store reconciliation complexity for future retention/lifecycle authority (per model-the-domain); it is larger than the no-prune partition-owned alternative.

## Exact terminal decision

Reconstruct LibraryOutcomeBinding from persisted collectingOutcome and compare owner/subject/namespace, installation key, sequence, batch ID/digest, receipt operation ID/revision, manifest generation and phase. Recheck journal header authority byte-for-byte/canonical digest and terminal checkpoint proof. Matched origin requires the still-frozen command fingerprint and exact submitted ID/revision/phase to match. Same IDs/different command fail into historical recovery, never confirm original acceptance. Do not infer equality from cached snapshot contents.

- Complete: verified count and immutable category totals exactly match bound receipt. Complete restore with superseded/missing>0 is partial, despite collection completeness; preserve original source and compact journal recovery reference.
- proof_unavailable: cannot create a settlement certificate or ACK intent. Remains blocked, retains frozen/local source and collected prefix; retry only on relevant authority/service change or explicit retry, not busy loop.
- detail_unavailable: only the explicit validated terminal server authority permits recoverable settlement. Certificate records unavailable reason, expected totals, collected prefix and source. Never classifies the prefix as complete. If actual producer cannot prove terminal authority separately from missing proof, stop rather than apply this policy.
- Historical: preserve existing adopted historical archive and journal evidence, do not invent a local accepted command. Cursor adoption must still pass owner/installation/sequence checks.

For every settleable case require persisted owner-matching Saved snapshot.version >= committed.revision.saved. Older snapshot returns waitSaved. A higher snapshot is sufficient for barrier, never evidence that an original command was accepted. Snapshot owner/version validation remains existing cacheSavedSnapshot policy. No polling/failure while waiting; wake only after successful persistence or activation.

## Ordered cross-store commits

1. Under store serialization, read exact partition/frozen state and journal authority; validate barrier and terminal policy. Journal transaction saves PREPARED certificate, including every needed original/recovery reference. Bump subject+namespace export mutation clock in the SAME SQLite transaction / SwiftData journal save. No ACK yet.
2. Existing copied-partition transaction rechecks exact collection/fingerprint and Saved barrier, applies certificate once, inserts compact recovery/evidence link where needed, preserves pending newer writes, clears only matching frozen/collecting state, advances nextSequence once and persists exact ACK intent plus PartitionSettlementLink. Atomically save AtomicFile JSON or SwiftData partition. If validation changed after step 1, park certificate as historical, do not force it onto a different frame.
3. Journal transaction marks PARTITION_APPLIED using certificate digest and persisted link. This is a replay checkpoint, not a precondition that can undo successful partition save. Bump export clock. Only then coordinator may send exact ACK. ACK send still requires current binding/captured context; no stale A request may acknowledge B.
4. On valid ACK response, first save ACK_CONFIRMED certificate with response cursor proof and bump export clock, then apply existing partition ACK settlement iff its pending ACK and link still match. If partition save fails/restarts, confirmed certificate can finish that same pending transition. It never creates an erased partition or settles a newer ACK.

Every journal transaction rechecks captured journal generation/deletion fence. Partition mutation checks account exists and is not deleting; cancellation/error before a durable save leaves prior state. No lock/SQL transaction is held across network awaits. Existing actor/mutex owns local serialization. Android suspend/cancellation between journal prepare and AtomicFile finish is an explicit test seam.

## Crash/replay table

| Durable state on reopen | Action |
| --- | --- |
| Terminal journal; no certificate | Revalidate authority/original/barrier, prepare normally. |
| PREPARED; exact collection still frozen | Revalidate and replay deterministic partition apply. |
| PREPARED; matching partition link/ACK already saved | Mark applied, do not append recovery/increment sequence again. |
| PARTITION_APPLIED; ACK lost or failed | Existing exact ACK retries; journal remains retained. |
| ACK_CONFIRMED; matching partition ACK remains | Replay only that ACK settlement. |
| Certificate but partition missing/erased | Retain orphan evidence unless deletion fence erases it; never recreate partition or send ACK on its behalf. |
| Certificate and incompatible/newer local frame | Historical orphan, preserve original source; no guessed settlement. |

Recovery and recent entries use collectionKey+certificateDigest as deterministic identity; partition apply checks the link before appending. Sequence increments once, even after repeated prepare/reopen. Cursor adoption referencing an unknown server slot retains original historical intent and cannot reuse another certificate by sequence alone.

## Projection, mappings and Undo

Manifest restore never becomes a guessed full-member optimistic overlay. After the Saved barrier, authoritative snapshot already owns actual memberships. Settlement can remove the delete overlay and clear only exact confirmed transition; no new manifest confirmed array is needed. Preserve later pending commands and their overlay order.

For validated restored manifest use receipt destination folderId to persist `restore:<deletionId>` mapping, with existing owner-scoped mapping conflict checks. Same-name merge points to actual destination. Historical receipt may update a needed server alias only if its canonical receipt binding proves that mapping; never change an unrelated pending local folder reference.

Matched delete retains compact recent manifest receipt/handle only while ORIGINAL operation.at + current Undo duration remains future. Reopen/settlement does not restart deadline. Locally available undo original and certificate remain durably discoverable even after ACK; if Undo still uses old member-array contract, retain that gate rather than claim working offline manifest Undo. No pruning introduced here. Partial/unavailable source is recovery/export evidence regardless of Undo expiry.

## Export, clock and erasure

Add certificates to bounded journal evidence discovery/streaming under captured subject+namespace, including partitionless headers and older owner-key orphans. Export all terminal policy classifications, original available source and ACK state structurally; no capabilities/provider text fields. Every preparation/state marker mutation bumps existing subject+namespace export clock atomically, so export cannot mix pre/post-settlement states. Replaying an already-identical state causes no mutation/clock bump.

Erasure removes certificate/original rows alongside header/member evidence in bounded batches and advances generation/clock before cleanup. Subject+namespace discovery works when partition is absent. Late ACK/certificate callbacks cannot recreate erased header/scope/partition. Schema migration must default existing headers to no certificate and preserve facts; migrate no old terminal journal directly to accepted status. Retain all journals, including complete success; ACK_CONFIRMED here is evidence only, not pruning authorization. Full cache/export scale remains open.

## Alternatives and tradeoffs

- Partition-owned no-prune transition: validates terminal journal then commits compact recovery/ACK once; no new mutable journal lifecycle. This is likely the smaller correct base for the exact current milestone because success pruning is explicitly deferred.
- Journal-owned lifecycle (this candidate): retains authoritative original/settlement evidence outside the partition and supports future lifecycle/export diagnosis; costs two-store replay state, installed schema migration and extra mutation-clock transitions.
- Move whole native outbox/partition into SQLite/SwiftData rows now: can reduce cross-store settlement to one transaction, but broadens scope into existing cache/storage migration; rejected for this unit.

This candidate's overhead is justified only if parent needs journal-owned ACK confirmation now. It does not make pruning safe by itself: retention, offline Undo, original-source dependencies and authoritative snapshot observation still require the later dedicated unit. Prefer candidate A when correctness ties; graft this candidate's deterministic settlement identity, post-persist Saved wakeup and explicit no-recreation checks.

## Proof and next implementation step

Start with pure terminal-decision/partition-apply functions and journal certificate migration, then real-store coordinator fixtures. Test exact complete totals, partial category recovery, detail_unavailable versus proof_unavailable, same-ID command fork, historical cursor, missing originals, newer pending writes, mapped destination and original Undo deadline. Inject failure/reopen at all four commits plus ACK lost response and mismatched late ACK. Drive actual UserLibraryModel Saved callback to persist revision below/equal/above barrier; assert no ACK below, eventual wake exactly once after, no polling/spin, stale owner emissions cannot progress. Verify exported orphan certificate/original content, atomic export clock increments, erasure during each stage and Android canceled AtomicFile commit. Keep public producer, old Undo migration, pruning, full Saved/export bounds and authenticated/device/deployment A2 gates open.

## Synthesis decision

Candidate B only; parent compares against no-prune candidate A. No implementation or completion claim.
