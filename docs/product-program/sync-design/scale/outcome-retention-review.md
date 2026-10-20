# Outcome retention implementation review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only architect Phase D review of the initial retention implementation

## Finding

### P1: dependency matching globally retains unrelated journals

Both `LibraryPartitionState.retainsOutcome` implementations overmatch compact commands:

- Any `folderRestore` blocks every restore-phase journal because the predicate is `binding.phase == restore || deletionId == target`.
- Any `membershipPut` with a local folder and any `folderDelete` with a local folder blocks every journal, without checking whether that alias belongs to the journal's operation or restore mapping.

One unrelated queued restore can therefore retain all successful restore journals forever. One durable local-folder command can retain all successful delete and restore journals. This defeats the selected fair cleanup policy even after 30 days and exact ACK proof.

Match exact dependencies instead:

- A restore blocks its parent deletion only when `deletionId == binding.receiptId`; replay of the same operation is already covered by `change.operation.id == target`.
- A local folder reference blocks only when its local alias resolves through the partition's exact folder mapping or retained recovery source to this binding. If the relationship is ambiguous, retain that affected candidate conservatively, not every header in the subject.
- Keep the exhaustive recovery scan, but apply the same exact relation to `server`, `historical`, `rejected` and `outcome.original` entries.

Evidence: `GuestMergePlanner.swift:737-760`, especially line 742 and lines 743-744; `LibrarySync.kt:261-285`, especially lines 266-268.

Add cross-header tests with two independent delete/restore journals: queue a dependency for A, prove A remains, and prove eligible B still prunes. Repeat with unrelated local-folder membership and delete commands.

## Paths that otherwise match the contract

- Only matched, complete, zero-superseded/zero-missing settlement writes `manifestAckLink`. Partial, unavailable and historical states remain unlinked and retained.
- ACK handling validates the exact persisted link and ACK, accepts a validated cursor closing beyond the requested sequence, writes the journal ACK time first, then adopts the cursor in the partition. A partition-save failure leaves the marker idempotent and the ACK retryable.
- `LibraryOutcomeRetention` lives inside existing checkpoint JSON and the fair cursor lives in defaulted partition JSON. No new native model/table or schema migration was added.
- Old checkpoint/partition JSON decodes with absent fields and gains no fabricated ACK proof.
- Eligibility requires exact complete totals, explicit ACK time, 30 days, matching Saved owner/revision, an extant owner partition and no detected compact dependency. Partitionless old-owner headers remain retained.
- Discovery reads at most 50 ordered headers and advances the persisted cursor past blocked entries. Pruning removes at most 50 ordered member rows per journal transaction/save and persists the removed ordinal.
- A failed cursor save after a partial prune is replay-safe because the header's removed ordinal is authoritative. A failed cursor save after final header removal may rescan the old range but cannot recreate the deleted header.
- Every ACK/prune mutation bumps the subject/namespace export clock. Export and direct evidence reads reject a checkpoint once `removed` is non-null, so no surviving subset can appear complete.
- Full erasure and generation checks remain authoritative. Cleanup requires an active owner partition and cannot create one for an orphan.
- The coordinator performs four yielded cleanup steps only from idle, then schedules another bounded pass when work remains.

## Evidence status at review time

- The supplied red logs reproduce permanent retention before this implementation.
- `/tmp/hadithly-outcome-retention-android-first.log` completes successfully for the one-header success case.
- `/tmp/hadithly-outcome-retention-ios-first.log` currently ends in a failed assertion that the acknowledged journal was still readable. No later passing iOS focused log was available at review time. Treat iOS first-green evidence as pending until a fresh terminal log passes; do not infer success from the current source.
- The one-header fixture does not expose the global dependency overmatch described above.

## Broad proof still required

- Exact unrelated-header dependency tests, more than 50 blocked headers before an eligible tail, cursor wrap/reopen and partial-prune resume.
- Journal-marker-first replay when partition cursor adoption fails, duplicate ACK, later cursor slot, owner/generation mismatch and lost response.
- 29/30-day boundaries, clock rollback, old proofless headers, partial/unavailable/historical recovery, and partitionless retention.
- Export before/during/after prune, storage failure for journal page and partition cursor, cancellation, erasure and late stale cleanup.
- A new restore admitted after irreversible prune, sent normally, with its actual server result collected and its original preserved on failure.

Manifest Undo migration, public producer, full partition/Saved/export scale, iOS save-failure proof, hosted/device/deployment and full A2 remain open.
