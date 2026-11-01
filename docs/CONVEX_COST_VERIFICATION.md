# Convex notification cost repair

November 1, 2026, Asia/Almaty. The owner expanded the diagnostic into reducing
Convex usage with sound system design. Local implementation is authorized;
cloud deployment, migrations and paid changes retain action-time approval.
The finished app experience remains the destination while release dependencies
and the A7 study remain deferred.

## Finding and design

The notification action enumerated all 96 wall-clock buckets every 15-minute
tick, even with no tokens. A new failing test exercised `runDuePushes` against
the real schema through `convex-test`: expected one query, received 96. This is
background traffic, independent of reader activity.

Replace that fixed fan-out with `listPushDeliveryPage`, one bounded cursor page
over the existing `by_enabled_bucket` index. Retain enabled status, canonical
bucket eligibility and ordering. The action follows the cursor and applies the
same per-token due-window, IANA timezone, retry, duplicate-date, content and
provider rules. Sent/retry bookkeeping does not move the indexed fields. Empty
filtered pages continue using the original cursor and `isDone`.

The obsolete `listBucketPage` endpoint, its caller and the 96-bucket enumeration
are removed together. No schema/index migration, second backend, native payload
change, new provider, weaker quota or delayed notification schedule is introduced.
This deliberately retains one scan of eligible tokens per tick. A due-UTC index
would require a separate scheduling/DST/backfill design; it is not justified by
the measured small-population call overhead.

## Live evidence before deployment

Read-only Convex CLI access succeeded after native Chrome access timed out twice.
No sign-in, credential or configuration change was needed. Captures are in
`verification/convex-cost/development-before.json` and `development-current.json`.
Both report `seedStatus: complete`. The latter snapshot at October 31 19:43 UTC
reports 459,965 development calls and 1.061385 GB database I/O for the UTC month;
the current UTC day reports 14,319 calls and 0.009377 GB database I/O. These are
deployment aggregates, not a team allowance or an isolated reader's cost.

The execution sample covers October 31 18:12:30-19:43:25 UTC, 893 completion
events. It includes 592 `library:listBucketPage` completions and seven daily push
action completions. Boundary overlap means these are not seven complete cron
trees. No reader-content or progress query occurred in that sample. The daily
push actions account for 586,779 sampled network egress bytes; this does not
prove how many bytes the repair saves.

A read-only inline query confirmed seven `collectionCounts` documents, one for
each configured collection. The historical monthly progress-query totals span
the October 12 count-materialization repair. No current missing-count migration
is justified by those totals. The 72-hour insights readback showed two OCC
retries in `savePushToken`, not a reader I/O-limit finding.

## Same-workload local comparison

`scripts/verify-convex-push-cost.mjs` runs the baseline `d872913` and candidate
against a real isolated anonymous Convex backend with the current schema.
Synthetic data, disabled crons, record-only senders and blocked generation keep
this independent of accounts, real tokens and provider services. Its result is
`verification/convex-cost/push-local-before-after.json`.

| Workload | Before token queries | After token queries | Preserved result |
| --- | ---: | ---: | --- |
| Empty tick | 96 | 1 | No sends or failures |
| 205 non-due tokens in two buckets | 96 | 2 | All 205 skipped outside their window |
| 200 stale tokens, then one due device | 97 | 2 | 200 deletions, one send |
| 201 permanently invalid devices | 97 | 2 | 201 failures and deletions |
| 501 due devices | 35 | 3 | Exactly 500 attempts |
| A page of invalid legacy buckets, then a due device | 96 | 2 | Invalid rows excluded, one send |

The empty-tick token-query reduction is 98.96%. At 96 ticks/day, an always-running
empty/single-page dispatcher would avoid 9,120 internal query calls/day. This is
a workload calculation, not a measured invoice saving or a capacity promise.
Returned token-row counts remain identical; database-byte reduction is unproven.
The final run also compares complete delivery result objects and ordered
device-token/body digests, not just send counts, across every before/after case.

Reproduce from the repository root:

```sh
node scripts/verify-convex-push-cost.mjs --baseline-ref d872913 --output docs/verification/convex-cost/push-local-before-after.json
python3 scripts/capture-convex-cost-baseline.py --deployment festive-cobra-664 --log-history 2000 --log-sample-seconds 20 --output docs/verification/convex-cost/development-current.json
```

The second command is read-only but refreshes the saved evidence; retain earlier
captures when comparing windows. It allowlists aggregate numbers and function
names, excludes payloads/log messages/identities, and marks missing usage null.

## Checks and limits

- All 546 backend tests in 44 files and `npm run typecheck` pass from `backend/`.
- All six before/after scenarios pass on real local Convex, including deletion
  of the last row underlying a page cursor. No provider request or push is sent.
- Two-axis review found no production correctness defect. The standards review
  found a script stderr disclosure path, now replaced with generic failures.
  Subprocess deadlines and owned-process-group cleanup were added.
- A failing-command canary confirms raw subprocess output is withheld. A capture
  canary confirms unknown fields, log text and payloads are excluded, and missing
  usage is unavailable rather than zero.
- An interruption probe sent SIGTERM while the real local backend was listening.
  The verifier exited 143, removed its temporary state and left no owned process
  group. Shared cleanup and SIGINT/SIGTERM handlers cover interrupted checks.
- `convex-test` cannot continue after its cursor document is deleted, unlike the
  real local backend. That unsuitable added test was replaced with the real
  runtime scenarios above. It is not counted as passing evidence.
- Earlier harness attempts failed from a mixed V8/Node fixture and concurrent
  local dev owners. Separate runtime fixtures and sequential server ownership
  fix those harness problems. One test invocation mistakenly used the repo root;
  it failed before running and was rerun from `backend/`.

No native code or public backend contract changed. Source parity is preserved;
no fresh native/device journey or live notification-delivery proof is claimed.
The paired native reading workload and controlled equal-duration idle interval
from `CONVEX_COST_DIAGNOSTIC.md` remain pending. The ambient sample is not a
substitute for those measurements.

## Remaining goal and action boundary

The owner approved fe8742c for development festive-cobra-664 and passive readback.
The push succeeded on October 31 at 19:58 UTC. The first push attempt stopped
before deployment because strict CLI typecheck expected convex/tsconfig.json;
this repo uses backend/tsconfig.json. Running npm run typecheck explicitly, then
pushing with CLI typecheck disabled, passed. No new config or SDK upgrade was
needed. Deployed function metadata confirms the new endpoint and removal of the
old one; see verification/convex-cost/deployed-function-readback.json. Production
is outside this unit. No manual live notification or paid generation was invoked.

The passive observer completed successfully. Both scheduled calls were recognized
as scheduler-originated and correlated with their child queries. The artifact is
`verification/convex-cost/deployed-scheduled-runs.json`.

| Completion UTC on October 31 | New token-page queries | Old bucket calls | Action seconds | Action egress bytes | Token DB read bytes |
| --- | ---: | ---: | ---: | ---: | ---: |
| 20:12:29 | 1 | 0 | 0.804 | 2,976 | 2,005 |
| 20:27:28 | 1 | 0 | 0.347 | 2,890 | 2,005 |

Both executions succeeded. This closes the development notification-dispatch
readback. The old 96-query empty/single-page fan-out is absent. It does not prove
reader I/O savings or an invoice reduction; returned token bytes remain present.

## Native baseline checkpoint

The first Android reader attempt ran 2h 36m and failed before reading because a
Library text selector matched two UI nodes. No valid baseline resulted. The test
now selects the stable `tabs.library` tag. Its rerun had a ten-minute host limit
and finished in 46 seconds, timing out at line 42 while waiting for
`reader.nextPage` after entering the reader. Both Android jobs have finished.
The iOS reader method is drafted but unrun. Both platforms remain unfinished
verification work. The long unchecked run was a workflow failure, not evidence
that more optimization was needed. Poll live handles and record outcomes before
starting or expanding another unit.

Next investigate reader I/O with the pinned native journey: whole-volume reads
remain a source-based candidate, not a measured current defect. Keep A1/A3/A4,
all G01-G41, A7/G38, E Linear and final original-program acceptance open. Preserve
A2's wrap-up, A5 fixes, B/C/D local completion and unrelated incoming work.

## Independent review

### Standards

The initial review found one credential-disclosure failure path in the verifier
and subprocess cleanup concerns. All raw CLI failure output is now withheld;
commands have deadlines, and owned process groups are shut down and checked
before local state removal. The final standards rereview passes with no
unresolved concrete concern.

### Spec

The requirements review found no concrete production behavior defect. Its paging,
permanent-deletion, attempt-cap and invalid-only-page evidence gaps are covered
by the extended real-backend scenarios and result/delivery-digest comparisons.
The broader native, controlled-idle and deployed savings requirements remain
open. The final requirements rereview reports no concrete spec defect.
