# Convex cost diagnostic

## Agreed outcome

Owner decisions on October 31, 2026: staying free is important, low cost is
permissible, and the destination is a finished app experience while release
dependencies remain deferred. No numeric spending ceiling has been selected.
Paid changes still require exact action-time approval.

Prioritize one Convex diagnostic from `POST_GOAL_BACKLOG.md` now. This is an
owner-selected sequencing exception, not completion of the original program.
Keep A1/A3/A4 acceptance, A7's study deferral, E Linear, the final audit and all
G01-G41 gates in their existing states. Preserve A2's wrap-up, A5 repairs and
B/C/D local completion. Other backlog items retain their existing order.

The diagnostic ends with a repeatable baseline, separated background and reader
costs, and one recommended optimization with correctness checks. If live evidence
is unavailable, deliver the local evidence and exact missing readback instead.
Neither outcome establishes a live saving or free-plan reader capacity.

## Evidence available before measurement

The owner's October 1-31 UTC screenshots show 463K calls, 1.06 GB database I/O
against a displayed 1 GB allowance, 2.2 GB-hours action compute and 272.21 MB
egress. Detailed panels show slightly different totals, so treat them as separate
captures rather than one atomic snapshot. They are historical monthly usage,
not current rates, reader counts or a one-reader workload.

- `listBucketPage`: 282K development calls but only 4.76 MB database I/O.
- Progress summaries and detailed progress: 312.99 MB and 156.89 MB database I/O.
- Collection, outline and volume queries: 190.24 MB, 148.9 MB and 123.13 MB.
- Development daily push action: about 2.9K calls and 237.01 MB egress.

Source inspection found a 15-minute notification cron and a loop over all 96
delivery buckets. About 2.9K runs times 96 checks is 278K queries, near 282K.
This is a lead for attribution, not a measured saving or a proven root cause of
database I/O. Inspect current deployment behavior before choosing a repair.
The October 12 Q1 repair already reduced Library outline reads; monthly totals
span that change. Current missing-count fallbacks and deployed revision remain
unverified. Do not repeat the old repair from the monthly chart alone.

## Procedure

Use `hadithly-convex-cost` for this unit. Use `diagnosing-bugs` Phase 1 to build
the measurement loop before testing a cause. This cost investigation uses a
repeatable workload and resource measurements as its feedback signal.

1. Inspect the existing dashboard through available authorized read-only access.
   Select Hadithly and distinguish development from production. Record the UTC
   interval, deployment revision if available, capture time and per-function
   resource dimensions. Prefer a recent post-change interval. If access needs
   sign-in or account changes, record that boundary before acting.
2. Pin a workload on each native app: cold process launch, Library, first reading,
   then ten page moves. Record build, simulator/emulator, auth state, collection,
   exact locale, text size, content-cache state and start/end times. Use existing
   cached content with generation disabled. Stop if content needs an unapproved
   provider call. Keep production and physical devices outside this unit.
3. Capture an equal-duration idle interval with the same deployment and app state.
   Span at least one 15-minute cron tick. Separate cron, health monitoring and
   test traffic from the foreground journey. Record overlap and uncertainty;
   aggregate before/after differences alone cannot prove attribution.
4. Report calls, database documents and bytes read/written, action compute,
   egress, storage and provider calls separately. Mark unavailable dimensions.
   Label local counts as local; do not turn them into billed bytes. Retain the
   exact commands, inputs and redacted outputs needed to repeat the workload.
5. Rank measured opportunities by resource cost, reader impact and correctness
   risk. Recommend one change and define the same before/after workload. Check
   identity and authorization, exact locale/provenance, freshness, revocation,
   offline behavior, notification delivery and quotas as relevant to that change.

Consult current official [Convex usage definitions](https://docs.convex.dev/production/state/limits)
and [usage attribution fields](https://docs.convex.dev/production/integrations/log-streams)
for the mechanisms actually measured. Refresh pricing only if estimating costs.

## Boundaries and stop point

This preparatory session changes documentation only. The next unit is diagnosis,
not an optimization rollout. No app/backend behavior, cloud configuration,
deployment, migration, entitlement, paid generation, external message, remote
issue, publication or release action is authorized by this brief.

Keep existing tracking in `docs/agents/issue-tracker.md`. The scope is one unit;
a new spec/ticket hierarchy, tracker setup, architecture ADR and glossary changes
are unnecessary. Use `to-spec` and `to-tickets` only if measured findings justify
multiple implementation units. Once a fix is selected, use a focused failing
check where meaningful, review standards and requirements, verify the real
artifact, and commit the completed unit without pushing.

Stop the diagnostic after recording evidence, limitations and the recommended
next change. A later implementation must retain all open gates and compare the
same workload before and after; builds alone do not establish a cost reduction.

## Preparation verification

The preparation changes only this brief and its checkpoint/continuation links.
No baseline, native run, new dashboard readback or cost reduction has been
performed. Scoped diff/whitespace, local Markdown links and code-fence checks
pass. Original PLAN and PRODUCT_PROGRAM checklist lines are unchanged. SHA-256
readbacks confirm the five incoming iOS catalog/project/scheme files are intact;
the pre-existing index was empty. Those files and `scripts/__pycache__/` belong
to incoming work and remain unstaged. No native build is needed for these docs.
