# Outcome retention implementation recheck

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only follow-up after dependency and activation fixes

## Result

No remaining concrete implementation defect was found in the reviewed retention slice. The prior cross-platform dependency overmatch is fixed, the activation race is closed on both coordinators, and both expanded native suites now have terminal passing logs.

This is a local native retention pass. It does not close manifest Undo migration, public producer, full-store scale, hosted/device, deployment or full A2 gates.

## Prior P1 rechecked

- `folderRestore` now blocks only the parent deletion whose receipt operation ID equals its `deletionId`, or an exact replay whose operation ID equals the candidate target.
- Local membership/delete commands now block a restore-result journal only when the local alias resolves through `folderMappings` to that receipt's actual destination folder ID. A delete journal uses the exact `restore:<receiptId>` alias.
- The same exact predicates apply to pending, frozen, confirmed, server/historical/rejected recovery and `outcome.original` sources.
- Cross-header tests prove a dependency for A retains A while unrelated delete/restore B remains eligible. The supplied dependency red logs fail on both platforms before this correction.

## Source invariants confirmed

- Only matched, complete, exact-total success with no superseded/missing identities writes `manifestAckLink`. Partial, unavailable and historical outcomes never gain prune proof.
- ACK handling captures the exact link before cursor adoption, validates owner and exact ACK, writes the journal's first `acknowledgedAt` first, then persists the copied cursor state. Replay reuses the timestamp and accepts a valid cursor that closes beyond the requested sequence.
- Old checkpoint and partition JSON decode absent fields conservatively. No new native entity/table, pruned tombstone or admission rule exists.
- Eligibility requires 30 days, exact ACK marker, complete facts, Saved owner/revision and no exact durable dependency. Proofless, recovery-linked and partitionless journals remain retained.
- The partition cursor scans at most 50 headers, advances across retained entries, wraps and resumes after reopen. The journal removes at most 50 members per transaction/save and persists `removed` before the next page.
- A failed member-delete transaction rolls back the whole page. Android's trigger fixture proves the already removed first 50 stay at 50 while the remaining 451 survive the failed next page.
- After irreversible pruning begins, a new late restore is admitted normally. The 501-row fixture reopens after the first page, completes pruning, sends the late restore, and preserves its original through the actual unresolved response.
- Export fencing invalidates a pre-prune export. Direct evidence and portable export fail explicitly while `removed` is present, so no surviving subset appears complete.
- Journal-first ACK with failed Android AtomicFile adoption leaves the old partition and first ACK timestamp. Reopen adopts a later valid cursor once without renewing retention.
- The iOS reconstructed crash seam verifies the persisted journal marker against the old partition state without unsupported Core Data fault injection. It remains a reconstruction, not actual recoverable SwiftData save-failure evidence.
- Partitionless evidence is retained by cleanup, then removed by subject/namespace account erasure. Late cleanup cannot recreate the owner.
- When `activate` meets an existing worker, both coordinators now set `requested = true` before awaiting it. Completion starts the deferred bounded pass, closing the flaky activation-during-finalization race.

## Evidence checked

- `/tmp/hadithly-outcome-retention-ios-dependency-red.log`: exact unrelated-dependency test fails before the fix.
- `/tmp/hadithly-outcome-retention-android-dependency-red.log`: same failure reproduced on connected Android.
- `/tmp/hadithly-outcome-retention-ios-expanded.log`: 85 tests, zero failures, terminal `TEST SUCCEEDED`.
- `/tmp/hadithly-outcome-retention-android-expanded.log`: 68 connected tests, zero failures, terminal `BUILD SUCCESSFUL`.
- `git diff --check` passes.

## Still-open proof and product gates

- Actual recoverable iOS SwiftData partition-save failure after journal ACK marker remains unproved. The reconstructed old-partition seam is useful but does not replace that evidence.
- The 30-day rule uses local wall time. Rollback delays cleanup, while forward clock changes are not tamper-proof elapsed-time evidence or an SLA.
- Whole-partition dependency scans and Saved/export memory use remain open scale work despite bounded journal pages.
- The late-restore fixture proves local queuing and a controlled unresolved result. Actual hosted authority for legacy/restored-device late restores remains unproved until the producer and deployment path run.
- Manifest Undo migration, public producer cutover, retention disclosure, physical/cross-device tests, deployment and full A2 remain open.

The implementation is ready for the parent's verification record and next bounded unit without another code correction from this review.
