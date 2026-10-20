# Native outcome settlement boundary

October 21, after `d53bbf0`. A2 remains active. Implement exact terminal settlement
and Saved revision wakeup before enabling the public producer. Retain every journal
for now. Success pruning, bounded full Saved reads/exports, old Undo migration,
physical/cross-device/hosted proof and A2 deployment remain separate open work.
No cloud/private-account/provider action is authorized by this frame.

Workflow: [x] ground; [x] two distinct sketches; [x] cross-judge and selection;
[x] parent implementation; [x] local store/coordinator proof; [x] final source/evidence review with iOS save-failure gate retained.
Consultants are read-only, write only their assigned `/tmp` artifact. Parent codes.
Use architect's runner-prompt and rationale-template. Compare caller usage first.

## Grounded existing flow

Both `LibrarySync` coordinators read `LibraryPartitionState.collectingOutcome` before
poll/ACK/freeze/send. `collectOutcomeStep` persists <=50 rows or a local verification
checkpoint per step. Complete and unavailable currently stop as failed without
settlement or ACK. Exact authority and original matched/historical intent already
survive reopen. Matched originals stay frozen. Historical adoption archives the
old frozen changes before collecting. Projection uses the owned Saved snapshot;
restore never projects its whole requested list, and delete overlay ends once the
snapshot reaches the committed Saved revision.

Partition `settle` and `adopt` validate one manifest, exact operation/revision/phase
and captured fingerprint. Ordinary inline settlement appends recovery and recent
receipts, drops frozen, increments sequence, then persists ACK intent. Store methods
mutate a copied partition and save before coordinator ACK. Android AtomicFile and
SQLite are separate; a durable matching journal must precede JSON settlement.
iOS saves partition JSON in SwiftData. Journal facts are immutable and export now
discovers all headers for the captured subject/namespace, including partitionless
orphans. The journal clock must bump if any new lifecycle metadata is written.

`cacheSavedSnapshot` checks owner/version and persists it. Real facade subscriptions
reload projection but do not currently wake the coordinator. A terminal journal
must wait without polling/failing or busy-looping until an owned snapshot reaches
`committed.revision.saved`; later Saved delivery must trigger progress. Session
checks must surround every await. Late A cannot acknowledge B or recreate erased A.

Server ACK removes the exact committed stream slot; losing reply then retrying is
idempotent. There is currently no native ACK-confirmed journal lifecycle marker.
Do not claim success pruning until that marker and all Undo/offline/recovery
dependencies are integrated. A small ACK settlement milestone may keep all journals
conservatively without claiming retention is solved.

## Required semantics

- Recheck persisted frozen content fingerprint, exact ID/revision/phase and full
  binding at settlement. Same IDs with different commands cannot confirm originals.
- `complete` needs exact verified totals. Partial restore records compact journal
  recovery and preserves locally available original source. Do not accumulate member
  arrays in partition state. Fully successful matched work can settle after Saved.
- `proof_unavailable` cannot authorize settlement or ACK. `detail_unavailable`
  has verified terminal authority and may settle only under an explicit recoverable
  policy retaining original source and collected evidence. Historical origin never
  invents a matched local source. No guessed restore overlay.
- Preserve later queued writes, folder mappings, Undo deadline and current receipt
  semantics. Recovery/export must remain discoverable after ACK and reopen.
- Persist final settlement and ACK intent before network ACK. Duplicate/reopen
  transitions must not duplicate recovery or advance sequence twice. Stale pending,
  journal mismatch, storage failure, cancellation, erasure and account changes stop.
- Do not silently prune journal evidence. If lifecycle/prune metadata is proposed,
  define exact transaction and export clock rules rather than bolting on flags.

Candidate A: partition-owned terminal transition with compact journal recovery,
no new mutable journal lifecycle until a later pruning unit. Candidate B: structurally
distinct journal-owned settlement/ACK lifecycle, with a replay plan across SQLite and
AtomicFile. Both must identify tradeoffs and concrete tests, including real facade
Saved delivery wakeup, no ACK below revision, exact partial/unavailable handling,
ACK failure/reopen and adopted cursors.

Rubric 1-5: exact authority/original preservation; durable crash/replay/ACK safety;
Saved/projection/Undo correctness; bounded state/export/erasure consistency; interface
depth and executable proof scope. Prefer fewer moving parts when correctness ties.
