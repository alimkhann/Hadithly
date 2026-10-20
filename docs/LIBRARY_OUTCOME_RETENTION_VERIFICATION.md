# A2 native outcome retention verification

October 21, 2026. Continues `28bfbad`. Exact confirmed ACK metadata and bounded
success-journal cleanup now run on both native apps. This advances one A2 integration
component. It does not enable the public producer or finish manifest Undo, full-library
scale, hosted/cross-device testing, deployment or full A2. No cloud/private-account
call, paid generation, production migration or push was performed.

## Implemented lifecycle

A matched complete result with zero missing/superseded identities saves one bounded
`manifestAckLink` with its exact ACK intent in the partition. Partial, unavailable
and historical results remain unlinked and retain their recovery evidence. Old
partition/header JSON decodes absent optional fields conservatively; no ACK proof is
inferred from old data. No native model/table or SQLite schema version changed.

The owned ACK response must match the persisted ACK and link. Existing cursor
validation runs on a copied partition before any journal effect. A valid response
closing at or beyond the requested sequence writes the journal's first local ACK
time before cursor adoption. A valid later pending/committed slot is handled by the
existing cursor rules. Replay reuses the original timestamp. A failed journal write
leaves ACK retryable; a failed partition save leaves the marker plus the old ACK/link.
No network send or Saved snapshot alone grants retention proof.

Eligibility requires complete verified totals, explicit ACK metadata, at least 30
local days after that first ACK, an extant matching owner partition/Saved revision,
and no exact durable dependency. Pending, frozen and confirmed commands, collecting/
waiting/ACK state, recent Undo receipts and every relevant recovery variant protect
their own journal or parent deletion. Local aliases match the actual restored folder
mapping. Unrelated folder commands do not retain every journal. Proofless, partial,
unavailable, historical, recovery-dependent and partitionless journals remain held.

A persisted partition cursor scans at most 50 ordered header summaries per step,
advances past retained entries and wraps at the end. It does not advance past a
half-pruned candidate. An eligible claim and deletion of at most 50 ordered facts
share one native transaction/save. Checkpoint metadata records the removed ordinal.
Reopen resumes there. Final deletion removes header/inventory and an unused owner
scope. Every ACK/prune mutation bumps the subject-plus-namespace export clock in
the same transaction. Native idle workers perform four yielded steps per pass and
schedule bounded continuation when needed. This is foreground/opportunistic work,
not a promise that an OS will run the app while it remains closed.

Exports begun earlier fail the clock fence. Direct evidence and portable export
fail explicitly during pruning; a surviving subset cannot appear complete. Cleanup
errors stop and preserve the last committed page. Erasure/generation checks reject
late cleanup and cannot recreate an erased account. Owner/deployment scopes stay
separate. Current active partition/clock metadata remains until ordinary erasure;
this component removes eligible outcome detail, not all private account storage.

An offline restore already queued before claim protects its parent evidence even
when the five-second UI Undo deadline expired. A NEW restore after irreversible aged
cleanup may still queue and reach Convex. Its original survives normal failure/
recovery, and a real successful receipt would be collected independently. Missing
local detail never fabricates expired server authority. No permanent prune tombstone
or positive-local-authority admission rule was introduced.

## Design and corrections

Both complete sketches were read end to end. Parent agrees with the independent
20/25 tie and chooses corrected A for lower persistence/migration cost. Keep the ACK
link and sweep cursor in partition JSON and lifecycle metadata in existing checkpoint
JSON. Reject a separate ledger/queue, source attachments and a schema rewrite. Graft
B's exact replay, dependency and late-restore rules. Design artifacts are
`product-program/sync-design/scale/outcome-retention*.md`.

Initial source review found a cross-platform P1: unrelated restore/local-folder
commands retained every result journal. The new cross-header regression failed on
both hosts, then exact deletion-ID and destination-alias matching repaired it. Raw
red logs end `-dependency-red.log`; reports are `outcome-retention-review.md` and
`outcome-retention-review-final.md` beside the contract. Final recheck found no
remaining concrete implementation defect, with the wider gates retained.

An iOS activation test also exposed a finishing-worker window. Both `activate`
implementations awaited an existing worker without setting the coalesced dirty bit.
They now set `requested=true`, so completion runs the deferred activation. Tests
wait for actual bounded cleanup, then verify evidence absence and empty inventory.
Initial first/cases logs retain the failed observations; they are not final passes.

## Executed evidence

| Boundary | Result | Evidence |
| --- | --- | --- |
| Actual iOS store/coordinator, presentation and Settings suites | 85 pass, zero failures | `/tmp/hadithly-outcome-retention-ios-verified.log`, `/tmp/hadithly-outcome-retention-verified.xcresult` |
| Actual Android store/coordinator instrumentation | 68 pass, zero failures/skips | `/tmp/hadithly-outcome-retention-android-verified.log` |
| Earlier complete expanded suites | 85 iOS / 68 Android pass | `/tmp/hadithly-outcome-retention-ios-expanded.log`, `-android-expanded.log` |
| Native wire/local API generators | Pass | `python3 scripts/generate-library-sync-wire.py --check`, `node scripts/generate-convex-api-local.mjs --check` |
| Diff whitespace | Pass | `git diff --check` |

The first red fixture uses the real coordinator, ACKs one full result, advances an
injected clock beyond retention and proves the journal remains indefinitely under
the old implementation. Evidence is `/tmp/hadithly-outcome-retention-ios-red.log`
and `-android-red.log`. The final fixture proves actual automatic cleanup and empty
owned inventory; it does not use a source-text check as a substitute.

The 501-row fixture checks the exact retention boundary, claims/deletes 50 identities,
invalidates an earlier export fence and rejects an actual portable export while
pruning. It reopens, admits a new restore, finishes the remaining pages and inspects
zero member/header/inventory/unused-scope rows. Its controlled transport receives the
late restore and returns a real typed unresolved result; the exact original remains
in recovery. Android additionally aborts the next DELETE transaction with a SQLite
trigger and observes 451 rows plus `removed=50` before resuming.

The fairness fixture creates 51 proofless headers sorting before a successful
candidate, persists the first scan cursor, reopens and prunes the eligible tail.
Every proofless header remains. Pure policy tests cover the 30-day boundary, rollback,
unknown ACK data and each pending/frozen/recent/collection/recovery dependency.
Cross-header tests separate parent A from unrelated B and actual destination aliases.

Android's ACK fixture prevents the AtomicFile parent-directory write after the
journal marker commits. It reopens the unchanged ACK/link partition with the marker
still present, retries a valid later cursor and verifies the first timestamp does
not renew. Invalid/stale ACKs cannot mark or renew it. iOS reconstructs that exact
journal-first/old-partition durable seam with real store writes, then proves replay.
This reconstruction is not an actual SwiftData save-failure or process-kill test.
Partitionless confirmed evidence survives cleanup, then scoped account erasure
removes it. Late cleanup cannot recreate partition or journal rows.

## Gates retained

- Manifest Undo/public producer/read cutover, original restore's 500-ID admission,
  old mixed frames/installed clients and app-level 501-member support remain open.
- Existing whole-file partition/cache/dependency arrays and full Saved/export memory
  bounds remain open despite bounded journal discovery/deletion.
- Old/unproved, partial, unavailable, historical and recovery-dependent evidence is
  retained until a separately proven resolution/erasure policy. This is not a full
  retention/disclosure or account-deletion SLA certification.
- Local wall time is user-adjustable. Rollback delays pruning; a forward jump does
  not prove trusted elapsed time. No tamper-proof 30-day claim is made.
- Actual recoverable iOS save failures, power loss, termination at every commit seam,
  physical/older-OS matrices, hosted late-restore authority and real cross-device
  delivery remain open. Controlled native transport tests are not deployed proof.
- A2 development approval, hosted limits, content/localization, store and release
  gates remain open. The complete product program remains active.
