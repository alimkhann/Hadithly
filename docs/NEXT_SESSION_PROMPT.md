# Continue the active reader scrolling goal

Priority-2 verification was committed as `85adf64`. The owner then started loaded
reader scrolling diagnosis, approved a physical trace and requested installing
the latest build first. The first repair Debug build is installed and has paired physical evidence. The owner's
low-frame-rate report and blank-header complaint are the current scope.

```text
Continue Hadithly from docs/PLAN.md and docs/SCROLLING_VERIFICATION.md. The active
goal is loaded-page scrolling and restoring full-bleed text behind floating
progress controls. Do not begin page-transition/cache or priority-4 work.

The physical Time Profiler baseline exposes synchronous progress/account-library
work. The real local account-facade regression originally produced 31 immediate
writes for 31 captures. The iOS repair batches scroll saves within 500 ms while
keeping immediate final/navigation saves and fencing delayed writes by account
scope. Both native readers move top clearance into scroll content so text can
pass behind controls, while explicit targets retain measured clearance. Preserve
the single landing owner and reading-area coordinate mapping.

Read the verification record for exact passing suites and rejected attempts.
The initial simulator CPU loop had no account library and does not prove this
repair. Android's normal-runtime frame test provides independent Debug emulator
timings, not release/physical 60 FPS proof. Temporary page-body counters and the
abandoned simulator performance-driver tests were removed.

The repair is installed and verified on the named iPhone. Both 30-second
Animation Hitches runs are complete on the owner-confirmed same passage/settings.
Hitches fall 227→102 and their time ratio 8.012%→5.400%, missing the proposed
50% reduction target. The owner confirms smoother motion and restored appearance,
but reports microjitters and explicitly requests agent-driven scrolling and a
root-cause repair. The same goal remains active. Next build a guarded physical UI
test that activates the already-loaded reader, injects only vertical gestures,
and requires an explicit test-host opt-in. Use existing device artifacts or
install only the test runner; do not reset data, sign in or generate text.
The same physical profiling and latest-build installation approvals persist.
Inspect the remaining sync/partition-decoding work against reader updates and
render stalls using repeated gestures; do not infer causality from unmatched
manual CPU totals. Keep exact settings metadata unknown where not captured.

Preserve incoming iOS catalog/project/scheme bytes and scripts/__pycache__, the
completed Convex continuation, A2 wrapped with row mode off, A5, B/C/D and all
G01-G41, A1/A3/A4 acceptance, A7/G38 deferred with retired dates, E actual Linear
and the original final audit. No study recruitment/contact/observation/collection.
No backend/API/cost implementation changed. Cloud/account/credential, paid-model,
deployment, migration and publication still need exact action-time approval.
Commit verified scoped work without pushing. Keep GPT-only and no Relay.
```
