# Native outcome retention boundary

October 21, after `28bfbad`. A2 remains active. Complete ACK confirmation and bounded
success-journal pruning, preserving pending Undo and recovery. Public producer,
manifest Undo migration, full Saved/export bounds, hosted/device tests and iOS
save-failure evidence remain open. No cloud/private-account/paid action authorized.

Workflow: [x] ground; [x] two sketches; [x] independent cross-judge and synthesis;
[x] parent implementation; [x] local native proof; [x] independent recheck; [x] verification/documentation prepared for commit.
Consultants are read-only and write only their own assigned `/tmp` files.

## Existing runtime

Both native stores settle complete or explicitly detail-unavailable journals only
after the owned Saved revision. Partial/historical/unavailable cases retain a compact
`LibraryRecovery.outcome(authority,checkpoint,original?)` in the partition. Successful
matched outcomes drop frozen source and create ordinary exact ACK intent. ACK calls
currently apply the reply cursor and forget the ACK. No journal ACK confirmation
exists, so every journal is retained indefinitely. This includes old-owner orphans.

Journal facts are SwiftData rows/iOS or private SQLite/Android, immutable after
verification except account erasure. Checkpoint JSON holds counts/status. The subject+
namespace export clock covers header/fact/checkpoint writes and erase; reads have no
side effects. Export reads up to 50 headers/facts, checks the clock throughout and
stages privately. Missing detail cannot become a partial published export. Pruning
must invalidate active export and expose no half-deleted journal as complete.

Partition persistence is SwiftData JSON or Android AtomicFile, separate from journal
transactions. Android serializes both through one store mutex; iOS MainActor serializes
local writes. Existing account erasure removes orphan rows and metadata in bounded
batches. Native `collectOutcomeStep` and export use captured owner and erasure generation.
An active missing/new generation rejects stale callbacks. The test-only reset is not
an authorized production partition cleanup path.

ACK response cursor may close beyond the requested sequence because retired slots
are consumed. Mark only an exact persisted manifest ACK whose validated reply proves
`closedThrough >= requested.sequence`. Do not infer ACK from a later snapshot, a
network send, matching IDs, or an unknown restored-copy cursor. Losing a reply or a
local save must preserve retryability. Old data without explicit ACK proof must remain
retained conservatively. A new pending/committed cursor can follow the old ACK.

## Required semantics

- Capture a bounded exact manifest reference alongside ACK intent during settlement,
  then record confirmed ACK only after an owned exact response. Journal marker write
  and partition cursor adoption need an explicit replay order across both stores.
- Keep partial, unavailable, historical and recovery-dependent journals. Success
  candidates need complete verified facts, exact ACK confirmation, observed Saved
  revision and a conservative minimum retention window. Compare 30 days after local
  ACK, matching the server's existing 30-day detail policy without shortening it.
- Pending/frozen offline restores reference deletion operation ID. Recovery can also
  refer through original restore commands, prior server/historical/rejected changes,
  outcome authority and recent Undo receipts. Keep the parent deletion evidence while
  any of these dependencies remains. Do not require a whole member array in partition.
- Claim prune eligibility under the same native serialization as enqueue/settlement.
  State explicitly what a very late newly admitted offline restore means after an
  irreversible aged prune has started; do not promise recovery of already deleted
  facts. Existing five-second UI Undo does not authorize pruning queued offline Undo.
- Discovery and deletion are bounded, resumable after interruption and account-scoped.
  At most 50 member rows per transaction. Retained first-page entries cannot starve
  eligible headers later in the inventory. No silent scan of all journal members.
- Export and pruning share exact mutation-clock rules. Stage invalidation, partial
  deletion, index/backfill, orphan discovery and erasure must remain coherent. Never
  recreate a deleted account or export another subject/deployment.
- Storage failure pauses cleanup. Do not evict original note/source recovery or reset
  the whole native store. Existing whole-file partition/cache size remains a gate.
- Avoid a full four-stage certificate state machine if a smaller ACK marker and
  deterministic cleanup cursor provide the same guarantee. Do not reintroduce the
  rejected journal source attachment merely for future flexibility.

Candidate A: minimal partition manifest-ACK link plus journal checkpoint retention
metadata and bounded resumable prune. Candidate B: structurally distinct journal-owned
ACK/cleanup ledger or native queue with precise two-store replay. Both must trace
caller usage first, signatures/types, actual affected paths, and falsifiable cases.
Use architect runner-prompt/rationale-template and screen design red flags.

Rubric 1-5: exact ACK/crash safety; offline Undo/recovery preservation; bounded fair
cleanup and interruption; export/erasure/migration integrity; interface depth and real
native verification cost. Prefer the simpler correct interface when scores tie.
