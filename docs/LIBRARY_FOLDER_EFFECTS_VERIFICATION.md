# A2 logical folder deletion and staged Undo

October 20, 2026. Continues `9eadf68`. Internal logical deletion, staged restoration,
phase-aware membership and bounded materialization are implemented and locally
verified. The public async producer and native outcome collector remain disabled.
This is not an app-level large-folder support or A2 completion claim. No deployment,
private account call, migration or paid provider call was performed.

The implementation contract is
`product-program/sync-design/scale/logical-effects.md`.

## Implemented effects

A prepared deletion checks owner existence, original folder identity, current
membership epoch, metadata time and folder mark again. Its transaction removes
the folder row, stores an owner tombstone, advances Saved revision and publishes
the held frame's bounded terminal receipt. No partial member unlink is exposed.
Raw pointers retain the original set, while the effective membership rule returns
no folder and at least the deletion clock. An older same-value removal leaves the
pointer and Undo authority intact.

Undo reserves one restore operation on the handle in a transaction. Another ID
is superseded without staging. Same-ID/time retry refers to the reserved work;
different time is rejected. Eligibility requires the same Saved row, original
pointer/clock and available hadith. Stages are private until the final flip.
Accepted concurrent moves or last-facet removals clear stages and adjust preparing
restored/superseded/missing counters in their own transaction. Older/tied observations
preserve the stage. Final totals freeze at visibility commit and remain historical
when later user edits change current membership.

An existing same-name destination stays structurally locked through normalization.
A new destination is created only at the final commit, or a newly appeared stable
same-name folder is reused. All legacy/current physical delete and restore paths
respect the lock. Normal membership/facet edits remain possible. Materialization
rewrites at most four member identities per transaction and releases the lock only
after completion. There is one staging lookup and no redirect history.

Unconsumed handles retain facts for 30 days from server deletion commit. Reserving
Undo protects the later of the retained deadline or 30 minutes from progress; pages
renew that reservation. A near-expiry valid restore cannot lose its facts to cleanup.
Successful restore details get 30 days from their own visibility commit. Cleanup
of an unconsumed handle first materializes orphan pointers to explicit deletion
clocks, then removes tombstone/facts. Already-visible restoration must finish
materializing before cleanup. Unavailable old authority cannot create a new folder.
These are source lifecycle rules, not a certified privacy deletion SLA.

Owner erasure fences late workers and cleans their facts. Recovery dispatch now
recognizes restore/expiry work and pending normalization without repeatedly scanning
completed handles. Receipt publication and business visibility share transactions;
an unavailable held proof causes rollback rather than an unreceipted effect.

## Reproduced and repaired issues

The first before/after materialization assertion exposed raw `folderStage` and
physical membership clocks in the legacy Saved snapshot. The boundary now omits
stage data and returns the effective clock, keeping the visible payload identical
before and after normalization. Evidence:
`/tmp/hadithly-logical-folder-initial-red.log`.

The same first run exceeded convex-test's default 100 scheduled-step drain limit
for full large restores. That was a harness limit, not evidence of an infinite
worker. The fixture now drives the actual existing scheduled functions with a
finite bound derived from member count and checks terminal normalized state.
The full 501- and 2,001-member sequences complete.

An actual legacy-endpoint regression then showed ghost canonical members after
older bookmark/favorite/note removal. Older endpoints only changed legacy tables.
Their old and current counterparts now share the canonical stage-aware writers.
Old note updates keep the returned notes ID and original creation time, and old
bookmark addition keeps optional scroll offset. Red/green evidence:
`/tmp/hadithly-logical-folder-legacy-red.log` and
`/tmp/hadithly-logical-folder-legacy-green.log`.

The contract review identified two P1s before implementation: competing Undo
reservation and retention crossing an active restore. Both are addressed in source
and actual tests. The implementation review found no concrete blocker; the final
writer/snapshot and note-compatibility rechecks found no new blocker. Raw reports:
`product-program/sync-design/scale/logical-effects-contract-review.md`,
`logical-effects-review.md`, and `logical-effects-review-final.md`. Reviews preceded
completed final test output and do not certify app cutover or hosted behavior.

## Executed verification

| Boundary | Result | Evidence |
| --- | --- | --- |
| New actual Convex transition/legacy compatibility cases | 14 pass in full suite | `backend/convex/savedFolderTransitions.test.ts` |
| Complete backend suite | 453 tests, 40 files pass | `/tmp/hadithly-logical-folder-final-verified-backend.log` |
| Strict backend typecheck | Pass | `/tmp/hadithly-logical-folder-final-typecheck.log` |
| iOS existing core/store/coordinator and new receipt guard | 56 pass | `/tmp/hadithly-logical-folder-ios.log`, `.xcresult` |
| Android existing core/store/coordinator and new receipt guard | 35 pass | `/tmp/hadithly-logical-folder-android.log` |
| Local API and native wire consistency | Pass | Both generator `--check` commands |
| Existing public 501-member product probe | Red | `/tmp/hadithly-logical-folder-public-support-red.log` |

Cases cover full 501/2,001 sets and bounded receipt size, the 50/100/75 stale-removal
counterexample, newer during-stage removal, older post-flip removal, immutable final
totals, missing members, empty folders, competing restore IDs, same-name replacement,
structural locks, delayed materialization, retention crossing active work, automatic
recovery, expiry clocks, erasure and older facet endpoints. Native tests specifically
prove a bounded manifest receipt cannot clear the frozen original or become ACK-able
before outcome collection exists. They do not prove a successful native Undo journey.

Per effect step, at most four full Saved and hadith identities are read, plus small
facts/metadata. Preparation retains its existing row/byte pagination limits. Local
Convex tests do not enforce hosted document/transaction byte budgets or prove cloud
index building, job delivery or cron execution. Those need approved deployment and
readback. Current-schema local stores are not prior installed-schema proof.

## Remaining cutover

Add bounded outcome pages and durable native collection, including honest unavailable
details after retention. Only then may the native guards accept/ACK these manifest
receipts. The exact historical receipt must not be rewritten when detail expires;
locally available originals remain recoverable.

Owned Saved/folder and export pagination, truthful old mixed-frame handling, legacy
timestamp/list-only Undo authority and installed client/schema migration still need
their final versioned cutover. Current old synchronous entry points retain their
existing 500-member support boundary. The fresh public probe remains red. Real
authenticated cross-device delivery, SDK deletion, physical devices, privacy/retention,
production and all release gates remain open in `PRODUCT_PROGRAM.md`.
