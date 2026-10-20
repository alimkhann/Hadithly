# Candidate B: journal-owned ACK ledger and fair cleanup queue

## Usage first

```text
terminal settlement(owner, exact collection):
  journal.prepareAckCandidate(exactAuthority, successClassification)
  partition.persistSettlementAndAck(exactManifestLink) // no raw member arrays

ACK reply(owner, requestedAck, reply):
  store.confirmManifestAckAndAdopt(owner, requestedAck, reply)

coordinator on activation / successful ACK / durable Saved delivery / foreground:
  store.cleanupOutcomeStep(capturedOwner, maxHeaders=20, maxMembers=50)
```

One high-level store method hides journal/partition replay. Neither Settings nor views own timers/cursors. Cleanup is opportunistic bounded work, independent of ordinary sync success; retained rows never block sends. Use a persisted queue cursor and nextDue time, not a scan starting at first header on every run.

## Grounding

Current complete/detail-unavailable settlement waits for owned Saved revision and stores recovery references for partial/historical/unavailable results. Successful matched originals leave frozen state and create ordinary ACK. Both stores then adopt ACK cursor and forget requested ACK; there is no ACK-confirmed journal state. Journal rows/checkpoints are exported under subject+namespace mutation clock and include old-owner orphans. Android journal SQLite and partition AtomicFile are separate; iOS journal ModelContext save and partition JSON save are separate. Existing facade cacheSavedSnapshot validates owner/version and is the correct trigger after durable save. No current code supports safe success retention simply by examining a later snapshot or current cursor.

## Types and module ownership

```text
AckCandidate = {collectionKey, exactOwner, namespace, subject, journalGeneration,
  clientKey, sequence, batchId, digest, receiptOperationId, receiptRevision,
  manifestGeneration, phase, requiredSavedRevision, classification}
PartitionManifestAckLink = {collectionKey, candidateDigest, exactAck}
RetentionRow = {candidate: AckCandidate,
  ackProof?: {exactAck, validatedCursorDigest, closedThrough, confirmedAt},
  state: retained | pruning | pruned,
  nextCheckAt, lastCheckedOrder, deletionCursor?}
ScopeSweep = {scopeKey, headerAfterKey, backfillDone, nextFairOrder}
```

Journal stores one RetentionRow per collection, separate from immutable checkpoint/facts; no growing per-operation log or source attachments. Candidate only includes bounded receipt metadata. Existing partition recovery owns available original note/source. Journal methods live in existing journal/store rather than a new generic queue framework. Native wire is unchanged except local Codable/Serializable ACK link. Store owns dependency checks against real current partition; journal owns queue transitions and deletion. All journal lifecycle writes bump the existing subject+namespace export clock atomically.

## Exact ACK capture and two-store order

During settlement, validate full manifest authority and prepare RetentionRow before saving partition's exact ACK+link. Classification is immutable: eligible-success only for matched origin, complete verified facts and zero restore superseded/missing. Partial, unavailable, historical or any recovery-classified collection remains ineligible. PREPARE is not an ACK marker and cannot trigger pruning.

When ACK response arrives, under existing native serialization:

1. Read still-existing captured partition. Require its persisted acknowledgement equals requested, manifest link/candidate digest matches, owner/subject/namespace match and generation is current. Reuse actual ACK cursor validation and require reply.clientKey==requested.clientKey and reply.cursor.closedThrough>=requested.sequence. Later new pending/committed slot is permitted only if the actual cursor validator accepts it; do not require closedThrough==sequence.
2. Journal transaction records exact validated proof and confirmedAt once, with clock bump. This happens BEFORE partition adopts cursor/clears ACK. Earliest successful local confirmation time is retained across duplicate replies; no arbitrary network-send time or server clock substitute.
3. Save copied partition through existing settleAcknowledgement, clearing only matching ACK+link and adopting the reply cursor. If save fails, persisted ACK survives and retry is safe. If response is lost, no marker exists; resend exact ACK normally.

On reopen, existing matching pending ACK can replay a saved proof's exact cursor through the same validator. If marker exists but partition moved forward, no cursor rollback is attempted. If partition/link absent or incompatible, marker alone may never recreate state or settle a newer ACK. Erasure/generation mismatch rejects every stage. iOS save rollback and Android cancellation during AtomicFile commit require actual tests; neither transaction spans network await.

Old ACKs lacking a manifest link are adopted as today but cannot create RetentionRow ACK proof from ID coincidence. Old journals without explicit proof stay retained indefinitely until erasure or a separately proven migration. Schema backfill indexes them as ineligible, never sets a fabricated confirmedAt. No account/partition is recreated to backfill orphan headers.

## Eligibility and dependency claim

At least 30*24h AFTER local confirmedAt, eligibility requires complete verified journal, eligible-success classification, exact ACK proof, savedSnapshot owner/version>=requiredSavedRevision, no recovery reference and no live Undo/deletion dependency. Clock reversal postpones work. Persist a conservative wall-clock lower bound; test injected clock. A forward device-clock jump cannot prove real elapsed time without a trusted clock; prefer monotonic elapsed evidence within process plus conservative wall-clock across restarts, and retain on uncertain rollback. Do not claim tamper-proof 30-day elapsed retention from a user-adjustable clock.

Under the SAME GuestDataStore mutex/MainActor serialization used by enqueue and settlement, gather references from pending and frozen commands, waiting/collecting authority, recovery variants (including server/historical/rejected originals), recent Undo receipts and manifest authorities. Resolve deletion operation IDs to collection keys through indexed journal authority. Any ambiguous/unknown original format blocks affected pruning conservatively. Dependency extractor is one pure exhaustive variant switch shared by eligibility and enqueue tests. No member scans or partition member arrays.

This still examines already-loaded existing partition arrays; partition read/decode itself remains whole-file and is explicitly an existing size gate. A hard bound on arbitrary partition history would require a separate indexed dependency migration, outside this candidate. Per-step journal discovery/deletion is bounded regardless of member count.

Claim transaction changes retained→pruning only after dependency recheck while serialization is held. Once irreversible claim is saved, enqueue of a very late new offline restore referencing that deletion does not cancel partial prune or pretend facts can be recovered. It preserves original command/source in recovery with `local_details_aged_out`; if remote restore is still accepted by server, its new receipt is collected independently. Current already-pending/frozen restore must block claim even when UI five-second Undo elapsed. Five-second UI deadline is never the retention dependency policy.

## Fair queue and bounded deletion

Index eligible candidates by scope/state/nextCheckAt/fairOrder/key. Each step takes <=20 due headers, evaluates each once, then advances lastCheckedOrder to monotonically increasing scope order and sets a future recheck. Retained first-page candidates cannot starve later ones. Recheck due time plus rotating fair order prevents repeatedly selecting blocked entries. Advance persistent ScopeSweep cursor during index/backfill over <=50 headers so orphan/legacy inventory also progresses fairly. Reject malformed nonfinite order; epoch rollover can rebuild queue metadata in bounded pages, never reset safety classification.

For one claimed pruning collection, delete <=50 member rows per journal transaction using deterministic ordinal/index continuation (or first remaining rows). Header remains marked pruning. After last fact, atomically replace with compact `pruned` evidence marker retaining authority/ACK time/totals/reason; no full identity list. Delete cursors are resumable and idempotent; crash can only leave zero or more rows under a pruning header. Storage failure rolls back that transaction and pauses worker, never resets native store or deletes recovery.

Bounded scheduled/foreground worker resumes already-pruning rows before or interleaved with discovery. Limit transactions per activation and yield; fair queue keys ensure automatic progress without a required manual queue. Native background execution is best effort; completion is guaranteed on subsequent active runs, not when OS permanently prevents execution.

## Export integrity and erasure

Every claim/page-delete/final-pruned/ACK/backfill mutation increments existing export clock in the same journal save/SQLite transaction. An export that began before pruning fails its final clock check and deletes staged artifact. A new export sees pruning/pruned status and exact original totals but must NEVER serialize surviving subset as complete detail. Policy: export a compact explicit aged-success-details-removed marker, no residual facts, for pruning/pruned collections; source remains otherwise unchanged. Export that requires full retained facts instead fails explicitly while pruning. Choose one deterministic policy; recommend marker with original immutable totals and explicit details unavailable due local aged cleanup.

Retained partial/unavailable/historical/recovery collections export every available collected prefix as now. Complete-success pruning removes identity detail only after its policy claim; it cannot evict original private recovery/source. RetentionRow and queue metadata are private fields structurally filtered of capabilities, no logs. Orphan discovery/export still uses captured subject+namespace, not only active owner/partition.

Account erasure advances current scope generation/clock before deleting fact/header/retention/queue rows in bounded indexed batches. Include old-owner orphans and orphan RetentionRows without headers. Late ACK markers cannot create a missing header/scope; claim and ACK APIs require existing matching generation and nondeleting account. Delete queue scheduling handles through same scope fence. Erasure can clean all rows without a current partition and cannot emit another subject/deployment's evidence.

## Alternatives and cost

Minimal checkpoint metadata (candidate A) can store confirmedAt and pruning cursor in existing header and is likely the simpler correct base. This candidate buys independent indexed due/fair queue, explicit orphan ACK proof and clearer separation of immutable outcome checkpoints from retention policy. It costs one new ledger entity/table, partition ACK link, backfill and extra export-clock writes. Do not introduce prepared/applied/confirmed source-certificate machinery: one bounded candidate/proof row plus state is sufficient. Moving all partition data into journal DB would simplify transactions but broadens storage migration and is rejected here.

Recommend A when equivalent fairness and erasure are achievable with header indexes. Graft this candidate's exact ACK-before-cursor order, dependency extractor and explicit pruning export representation. Journal-owned queue is justified only if native indexed scheduling demonstrably reduces repeated header scans enough to offset schema/replay cost.

## Proof and first implementation step

Write pure exact-ACK and exhaustive dependency tests before persistence changes. Real-store tests: response closes beyond sequence with next slot; changed/missing link; lost ACK reply; failure after marker before partition save; duplicate response/reopen without renewed retention date; obsolete response cannot mark new ACK. Inject 29/30 days and clock rollback; partial/unavailable/historical/legacy proofless remain retained. Populate many blocked earliest headers then eligible tail and assert progress with <=20-header/50-member bounds. Pending/frozen expired-UI Undo and every recovery variant block claim; late restore after first deleted page preserves original but cannot reverse prune. Export before/during/after claim/page/finalization must fail or report explicit removed detail, never complete subset. Erase between marker/partition save, partitionless orphan rows, schema backfill interruption and canceled AtomicFile commit. Preserve public producer, manifest Undo migration, full Saved/export scale, iOS failure and actual hosted/device/A2 gates.

## Synthesis decision

Candidate B only. Read-only design consultation; parent implements and verifies selected shape.
