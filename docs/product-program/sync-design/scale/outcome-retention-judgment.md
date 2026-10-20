# Outcome retention cross-judge

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Mode: read-only architect/arena cross-judge

## Verdict

Use Candidate A as the base after two required corrections: remove positive-local-authority admission for late restores, and keep the fair sweep cursor in the active partition JSON rather than adding a journal queue or new native model/table. Graft Candidate B's post-claim late-restore behavior, exhaustive dependency extractor, exact ACK replay cases and explicit pruning export state.

Do not add a separate retention ledger, permanent pruned tombstones or a schema rewrite. Reuse the existing header checkpoint JSON for ACK/prune state, the existing subject/namespace inventory for discovery, and a defaulted partition field for sweep progress.

## Scores

| Criterion | A | B | Judgment |
| --- | ---: | ---: | --- |
| Exact ACK and crash safety | 5 | 5 | Both use journal-first exact ACK proof followed by cursor adoption and preserve retryability. |
| Offline Undo and recovery preservation | 2 | 5 | A's positive-authority admission would reject valid restored/legacy late commands from missing local evidence. B correctly preserves and sends a new late restore after irreversible claim. |
| Bounded fair cleanup and interruption | 4 | 4 | Both bound discovery and deletion. A can stay smaller with a partition sweep cursor; B adds a due/fair queue and ledger. |
| Export, erasure and migration integrity | 4 | 4 | Both clock lifecycle mutations and avoid exporting a surviving subset as complete. A needs no schema rewrite when metadata stays in existing JSON. |
| Interface depth and native verification cost | 5 | 2 | Corrected A needs an ACK link, header metadata and two store calls. B adds a retention entity, indexes, queue backfill and more replay states. |

Totals: A 20/25. B 20/25. The tie goes to corrected A because it has fewer persistent authorities and migration paths.

## Required correction: late restore after cleanup claim

Absence of a local journal does not prove that server Undo authority expired. A restored device, legacy client or valid delayed command can lack the local parent evidence while the server still accepts it. Local admission must not invent an `expired-evidence` result from that absence.

Before irreversible claim, already queued/frozen/waiting/collecting restore dependencies block pruning. Claim eligibility runs under the same MainActor/mutex serialization as enqueue and sees those durable dependencies.

After the aged-success header is claimed for pruning, a newly admitted restore may still enter the ordinary queue and go to Convex. It cannot reverse local pruning or promise local member reconstruction. Preserve its exact original command/source until the server result settles. If accepted, collect the new result independently. If rejected, unavailable or unresolved, preserve the original in normal recovery. No fabricated unavailable authority is created locally.

The pruning worker does not need a permanent tombstone to enforce this. Existing queued commands and server receipts own the new attempt. Missing old local detail remains an honest limitation.

## Smaller selected shape

1. Add a defaulted optional `manifestAckLink` to `LibraryPartitionState` when terminal settlement writes exact ACK intent. It contains the journal key, exact ACK, required Saved revision and `successCandidate | retain` classification.
2. On ACK reply, validate the still-persisted exact link and ACK, owner/subject/namespace, journal generation, and the full cursor. Require `closedThrough >= requested.sequence`; accept a valid later pending/committed slot through the existing cursor validator.
3. Write the idempotent ACK proof and first local `ackedAt` into the existing header checkpoint JSON first. Bump the export clock in that journal transaction. Then adopt the reply cursor and clear the exact link/ACK in one partition save. A failed journal write leaves ACK retryable; a failed partition save reuses the same marker and reply safely.
4. Retain old headers with no explicit link/proof, plus every partial, unavailable, historical or recovery-dependent result. Only matched complete success with exact totals and no recovery pointer can become a candidate.
5. Add a defaulted `outcomeRetentionSweep` field to the active partition JSON: subject/namespace scope, `afterHeaderKey`, and optional claimed key if needed. No new SwiftData entity or SQLite table is required.
6. One cleanup invocation reads at most 50 ordered inventory headers after the persisted cursor. It evaluates each compact header/partition dependency once and advances past retained entries, wrapping after the end. A retained prefix cannot starve an eligible tail.
7. If a header is already pruning, perform one member-delete transaction of at most 50 before or alongside one discovery page. Persist member progress in the header checkpoint JSON. Crash/reopen resumes from journal state; duplicate pages are idempotent.
8. Eligibility requires exact ACK proof, verified complete totals, matched success classification, owned Saved revision, at least 30 conservative days after first local ACK, no manifest link, and no current dependency in pending, frozen, waiting/collecting, recovery variants or recent receipts.
9. Do not prune partitionless headers. Missing partition or Saved proof means retain. This intentionally leaves old-owner orphans until account erasure or a later separately proven policy.
10. Export during `pruning` fails explicitly and discards staging. After final deletion the header and inventory entry disappear; do not serialize a partial surviving prefix as complete. An export started earlier fails through the clock.
11. Final member deletion, header/inventory deletion and every ACK/prune metadata change bump the existing subject/namespace clock. Account erasure remains authoritative and can delete partitionless rows without recreating an account.

## Crash and replay requirements

- ACK marker saved, partition adoption fails: resend/replay the exact ACK response, reuse the original `ackedAt`, and adopt once.
- Partition adopts, callback repeats: marker/link identity prevents renewed retention time or cursor rollback.
- Reply closes beyond the requested sequence: mark only the exact linked manifest, then let existing cursor adoption preserve the validated next slot.
- Claim saved, partition sweep cursor save fails: rescan finds the already-pruning header and resumes; no second claim or shortened retention.
- Member batch fails: transaction deletes nothing and keeps the same progress. Other headers and recovery source remain untouched.
- Erasure or owner switch at any stage: generation/deletion checks reject late ACK/cleanup without recreating header, clock or partition.

## Required proof

- Exact linked ACK, lost reply, duplicate/reopen, later cursor slot, wrong link/owner/generation and partition-save failure after journal marker.
- 29-day retention, conservative 30-day eligibility, clock rollback/uncertainty and no reset of first `ackedAt`.
- Every pending/frozen/recovery/recent dependency blocks claim, including expired UI Undo that remains durably queued.
- A new restore after first prune batch is admitted, retains its original, reaches the server independently and records actual success/failure without inventing old details.
- More than 50 blocked early headers followed by an eligible header; persisted cursor advances, wraps and resumes after interruption.
- At most one 50-header discovery page and one 50-member delete batch per step; no member-wide scan.
- Export before/during/after claim and member deletion, storage failure, account erasure, foreign scope and partitionless retain behavior.
- Old partition/header JSON decodes with absent ACK/prune/sweep fields and stays retained. No installed schema migration should be necessary.

## Gates retained

Manifest Undo migration, authoritative late-restore hosted behavior, ACK/prune deployment, iOS save-failure evidence, full partition/Saved/export scale, public producer, physical/cross-device tests, retention disclosure and full A2 remain open.
