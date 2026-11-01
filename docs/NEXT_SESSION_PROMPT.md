# Reader scrolling verified; stop before page transitions

Priority-2 passed as `85adf64`. The first scrolling repair is `ea04f6e`; the
subsequent decoded-partition repair completes the bounded scrolling goal. See
`SCROLLING_VERIFICATION.md` and `scrolling-verification/results.json`.

```text
Continue Hadithly from docs/PLAN.md. Loaded-page scrolling and the blank-header
regression are verified in their recorded scope. iOS batches progress saves and
reuses decoded account data only after validating freshly read owner/data bytes.
The one-entry Foundation cache admits at most 8 MiB encoded data and clears on
library scope changes. No schema, API or A2 row-mode change occurred.

Both native readers again draw text behind floating controls and into safe areas,
with measured explicit-target clearance, stable focus and the single landing
owner preserved. All 160 focused iOS safety cases pass. The first repair's five
iOS UI and eight Android native cases retain their recorded proof.

The final Debug build is installed on the named iPhone. An opted-in destination-
only XCTest drives actual loaded-reader gestures without app reinstall/reset.
Its matched slow scrolling hitch ratio falls from 10.47 to 2.10 ms/s; a separate
750-point/s flick check averages 4.72 ms/s. Both meet the 5 ms/s target. The slow
CPU non-regression budget passes. Zero SDK frame-count/app-wide fields are not
used as proof; Android emulator timings do not close physical Android or release
performance acceptance. Do not restart completed scrolling work without a fresh
reproduction. Preserve the raw-trace privacy boundary and incoming files.

Stop here. The proposed next goal is page-transition/loading/cache measurement,
with the same public-content identity, locale/type settings and generation-off
scope pinned before changes. Start it only as its own goal after the owner says
to continue. Preserve semantic Continue/Saved restoration and manual header
landing; page caching must not reintroduce a competing scroll owner. Free/Pro
development controls and translation reliability remain later priority-4 goals.

Preserve completed Convex reductions, A2 wrapped with row mode off, A5, B/C/D,
G01-G41, A1/A3/A4 acceptance, A7/G38 deferred with retired dates, E actual Linear
and the original final audit. No study recruitment/contact/observation/collection.
Keep incoming iOS project/scheme/catalog bytes and scripts/__pycache__ intact.
Commit scoped work without pushing. Cloud/account/credential, paid-model,
deployment, migration and publication still need exact action-time approval.
Existing physical installation/profiling/scrolling authorization persists for its
named scope; coordinate readiness if the owner is interacting with the phone.
Keep GPT-only and no Relay.
```
