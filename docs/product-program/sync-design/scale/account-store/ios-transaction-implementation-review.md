# iOS account transactions and export retry review

2026-10-23. Read-only review of the current GuestDataStore.swift transaction diff, GuestMergePlanner.swift export retry, matching Android LibrarySync.kt retry diff and iOS regression additions. Parent is sole implementer. No code/docs changes, cloud, schema or delegation. This file is a consultation artifact outside the checkout.

## Result

The fresh-context account prerequisite is structurally sound for synchronous MainActor writers in this process. No new concrete account/journal atomicity defect found in the reviewed diff. **The current full suites are failing because one old export mutation assertion conflicts with the newly intended retry behavior.** Do not report final acceptance until that contract is verified and both runs pass.

Actual observed failures:

- `/tmp/hadithly-ios-account-transactions-third.log`: testOutcomeExportMutationCancellationSwitchAndErasureDiscardPartialFiles fails at current source828, `Changed/canceled export was published`, and830, leftovers nonempty.
- `/tmp/hadithly-ios-account-transactions-android-parity.log`: outcomeExportMutationCancellationSwitchAndErasureDiscardPartialFiles fails with the same assertion.

These failures are expected specifically for the one-shot mutation subcase under the new retry contract: a failed attempt is discarded, the next attempt captures fresh authority, and a valid new artifact may be returned. The old test rejects any success and never discards that newly successful artifact, hence its leftover assertion also fails. This is a test contract mismatch, not evidence that an invalid old fence was accepted. The cancel/switch/erase subcases must still reject and clean up.

## Transaction boundary checks

- partitionRow, syncPartition and deletion admission now take the selected context. Public account reads create a fresh context; account mutations use one fresh context with autosave disabled.
- withAccount admits exact current partition and no deletion, decodes a fresh value, invokes a nonasync callback, writes only a changed domain state, bumps the shared export clock, saves once and rolls back escaping mutation errors. State equality is semantic, avoiding JSON-key-order-only fence changes.
- ACK retention helper mutates header and clock in the supplied account context without saving independently. Queue cursor/link/sequence and ACK metadata commit together. Retention member/header/scope/inventory plus account sweep cursor similarly share the final account save. Terminal settlement reads checkpoint and current account state in that context.
- Claim fetches guest rows in a fresh context and appends exact originals/deletes those same rows with account payload and clock in one save. The new cached guest claim/late-original regression directly checks the identity-map concern. Creation is confined to claim; ordinary account operations require an existing row.
- Deletion lookups are fresh/scope-selected. Account removal runs bounded scoped batches before journal cleanup, and account presence prevents premature shared-clock deletion. identityPending and clear validate scope emptiness. Clear intent remains the last local phase operation.
- Export capture initializes a present clock for an existing legacy account without one. Empty-fence validation includes account presence, so an account-only clone mutation now invalidates the same scope fence. Guest-only edits remain outside an authenticated owner's clock.

No new schema is necessary for this boundary. MainActor plus nonasync operations serializes reopened writers in this process; no evidence here proves arbitrary concurrent Core Data processes, backup restoration or external database writers.

## Regression evidence must be described precisely

The red public export-fence test failed before this implementation: `/tmp/hadithly-ios-account-transactions-red.log` reports `testAccountOnlyMutationInvalidatesExportFenceAndGuestMutationDoesNot`, XCTAssertThrowsError did not throw. That reproduces the missing account-clock behavior.

The cloned account command test was a passing control on the old implementation. **Do not claim an iOS lost-update defect was reproduced.** Its value is preserving the accepted-command contract across the fresh-context refactor.

The clock-exhaustion ACK test performs a logical mid-operation failure: journal ACK bump succeeds in memory, account bump then throws before save, rollback preserves both account and retention state and the earlier fence. It meaningfully proves one-context rollback of pending changes, but it is not an injected ModelContext.save failure.

The second run's real SQLite trigger against Core Data resulted in `fatal: Unable to recover from optimistic locking failure`, recorded in `/tmp/hadithly-ios-account-transactions-second.log`. Removing a framework-fatal default test is reasonable. Retain the failed experiment and **actual recoverable iOS save-failure gate remains OPEN**. Do not describe this as recovered or passing simply because the default suite no longer contains that probe.

## Export retry scope

Both native preparePortableExport wrappers retry only StoreUnavailable, at most three complete attempts. Each attempt obtains a new local fence and reads current local state; neither disables writes or weakens fence validation. Session/owner/capability checks are repeated on the new attempt. Cancellation is not caught as StoreUnavailable and remains terminal. iOS checks capability again before yielding; Android's next MainActor attempt performs that same admission immediately after yield.

Per-attempt cleanup remains inside the attempt's existing defer/finally before a retry is admitted. iOS closes its file then best-effort discards the attempt artifact. Android closes streams in NonCancellable and discards a failed artifact. A filesystem cleanup failure remains an operational limitation; do not claim every failure guarantees no retained bytes merely because cleanup was attempted. Existing durable artifact cleanup/erasure remains responsible for such residue.

Catching all StoreUnavailable also retries deterministic corruption/store failure twice. That is bounded and preserves failure, not a silent success. A narrower explicit invalidated-fence error could avoid redundant work later, but no new error hierarchy is required merely to pass this unit. Continuous mutation may still exhaust all three attempts; the function must return failure with no successful artifact from an invalid authority.

The provided server export value is reused across attempts. This retry only establishes coherent local evidence for the captured local scope; it does not create a transaction spanning a pre-fetched server export snapshot. Full server/export consistency/scale remains a separate gate, unchanged here.

## Required test adjustment and focused retry proof

Split the old mixed-mode test so it expresses each resulting behavior:

1. One transient mutation: let the first partial attempt be invalidated, then permit a fresh successful retry. Assert returned JSON contains the inserted current local evidence/private account edit, not just that a file exists. Assert superseded artifact metadata/directories/partial files are gone; explicitly discard the successful returned artifact before checking an empty export directory.
2. Cancellation, account/session switch and account deletion: keep rejection and cleanup assertions. A new attempt must not admit the old captured write scope.
3. Repeated invalidation: deterministically invalidate each of the three attempts, count attempts, and assert bounded final failure plus cleanup. Do not rely solely on incidental asynchronous sync churn to exercise the limit.
4. Already stable scope: export succeeds once, preserving full private originals, scoped old-owner orphan evidence, denied-key redaction and complete row counts. Existing corruption/half-pruned journal tests remain terminal after bounded retries.

A successful full rerun after changing only the one-shot expected result would establish compatibility but would not by itself prove the max-three contract. Use the targeted repeated-invalidation case or a comparably strong real-artifact check.

## Remaining limits

No broad A2 gate is approved. The four private Saved consumers and production UI are still awaiting their coordinated row-authority cutover. Pending/positions/server export throughput, practical repeated-export cost under large libraries, real SDK/JWT, installed/backend-first rollout, cross-device/physical-device and actual recoverable iOS save failure remain open. Preserve the preexisting generated Xcode/catalog changes independently. Parent should finish the retry proof, inspect terminal native results, then document/commit the local unit.
