# Reader entry prefetch cost verification

November 1, 2026. Development deployment `festive-cobra-664`; production is outside
this unit. Notification deployment/readback is already complete in
[CONVEX_COST_VERIFICATION.md](CONVEX_COST_VERIFICATION.md).

## Measured cause and repair

Android warmed all seven collection outlines when Today, Library or Saved
appeared, even for a guest with no reading progress. The iOS entry path already
warms only its most recent continue-reading target. Library progress counts come
from the compact summary stream and do not need those outlines.

Android now uses the same policy: no reading target means no entry prefetch;
otherwise warm that target's outline and, when present, its volume's first page.
The unused collection-list parameter and seven-outline bound are removed from
all three callers. Selected-reader loading, adjacent-volume prefetch, content,
exact-locale translation/provenance, revocation, quotas and offline reads use
their existing paths. No backend, schema, cloud config or entitlement changed.

The focused test `entry planning does no work without reading progress` failed
before the repair with an AssertionError. All 30 ReaderR6Round3Test cases pass
afterward, including latest-progress selection, volumeless targets, adjacent
volume bounds and offline failure tolerance.

## Controlled Android comparison

The same instrumentation method ran against the four production files from
`51ee40d`, then the candidate. Only those four files switched temporarily;
the candidate was restored in a finally block. The task-owned emulator had no
Hadithly package before each install, so both runs began with fresh guest data,
no reading progress and no offline packs. Earlier exploratory runs are not used
as the controlled comparison.

Both cold process launches opened Library, selected Bukhari and moved ten pages
through the native accessibility action. The test verifies the rendered page and
volume after every move. Both runs produced identical eleven positions from
Page 1 / Volume 1 to Page 7 / Volume 2. English, 26-point Arabic, 16-point
translation and automatic generation off were pinned. The emulator was
`hadithly`, Android 16, explicitly selected as `emulator-5554` through the guarded
runner. Source hashes and UTC bounds are in the journey JSON files.

| Measured function | Baseline completions | Candidate completions |
| --- | ---: | ---: |
| actions/hadithData:getCollectionOutline | 9 | 1 |
| collections:getOutline | 32 | 24 |
| actions/hadithData:getReaderPage | 21 | 21 |
| hadiths:listByVolume | 21 | 21 |

Eight outline actions and their eight queries disappeared from this reading
journey. Reader page work and rendered destinations stayed the same. This is
live development evidence from local native builds, not a released app saving.

The shared server's query cache was not flushed. The baseline recorded six
uncached outline reads totalling 47,095 bytes; the candidate's outline reads were
all cached. Both volume-query sets were entirely cached. These differing cache
states prevent an isolated database-byte or billed-saving claim. Action network
egress and execution seconds are recorded separately in the usage artifacts;
they are not cellular download bytes or per-journey GB-hours.

## Idle control

Both controlled test apps were confirmed stopped at 08:27:18 UTC and remained
stopped through 08:28:39 UTC. No test interaction occurred in that interval.
`idle-observation.json` retains the wider window. Equal-duration windows, centred
on the observed 08:27:29 scheduled tick, match each controlled Android journey.
Both contain one push-page query, one heartbeat mutation and one daily push
action, with no reader calls. Background calls are reported separately, not
subtracted from deployment totals to invent reader attribution. Other users or
existing simulators were not controlled; their overlap cannot be ruled out by
an account-wide aggregate.

## iOS parity and limits

The iOS product prefetch policy is unchanged. The same cold-process Library /
Bukhari / ten-page workload passed on the isolated iPhone 18 Pro / iOS 27
simulator. The app was uninstalled only on that task-owned simulator before the
final run, removing reading progress left by failed test attempts. English,
26-point Arabic and 16-point translation were read back from its local settings.
Automatic generation was disabled through the launch configuration. The guest
had no prior account on this simulator.

The fresh run completed at 08:41:23 UTC, with one outline action and fifteen
reader-page actions. Its outline queries were cached; three volume-query misses
read 372,707 bytes and translation defaults read 22,282 bytes. Platform prefetch
lifecycles and shared cache state differ, so these are separate baselines, not a
cross-platform efficiency ranking. The iOS test duration includes XCTest waits
and is not a page-transition latency benchmark. Its timestamps have one-second
resolution. The matching 112-second stopped-app control, from 08:42:14 to 08:44:06 UTC,
contains one scheduled notification action and one token-page query, with no
reader calls. `ios-idle-control.json` records the stopped-app checks. These
controls use the same recorded duration; the one-second iOS timestamp resolution
remains a boundary uncertainty.

An initial unsigned build failed Clerk keychain setup with missing entitlement
status -34018. Normal simulator signing resolved startup. Test-only offscreen
controls and animation races were then corrected: the test uses window swipes
and waits for progress controls to disappear before revealing them. Those failed
attempts are excluded from passing evidence. The final fresh XCTest run passed.

Per-window document reads/writes and estimated action memory GB-hours are
recorded in each usage artifact. Action memory GB-hours sum memoryUsedMb times
execution seconds, divided by 1024 and 3600, following Convex's documented memory
accounting. They are usage estimates, not invoice totals. The whole Android
windows read six versus one documents, with different shared-cache hits; iOS read
149 documents. All three windows recorded zero document writes. Storage change,
separate CPU billing and explicit provider request counters are unavailable. No paid generation or manual notification was
invoked. Shared cache state, authentication cohorts and real reading frequency
are insufficient to estimate free-plan users. All original app/release gates
remain open.

## Review and remaining work

The scoped source review found all three Android entry callers migrated and no
remaining seven-outline constant or caller. Identity, generation and cached
content retrieval are unchanged. Focused tests cover empty and existing resume targets. The real native
before/after pair covers fresh guests; iOS is a no-change product parity check. The five incoming iOS catalog/project/scheme files remain
byte-identical and unstaged. Nothing was pushed or deployed by this unit.

## Reproduction and evidence

From the repository root, use the guarded native method with JDK 21:

```sh
python3 scripts/run-android-ui-tests.py --serial emulator-5554 --class com.hadithly.app.ConvexCostJourneyTest#coldLaunchLibraryAndTenPageMoves
python3 scripts/capture-convex-cost-baseline.py --deployment festive-cobra-664 --log-history 2000 --log-sample-seconds 5 --since <journey-start-UTC> --until <journey-end-UTC> --output <new-evidence-path>
```

Keep the task-owned guest emulator fresh, preserve other devices and worktrees,
and verify the native test's guest assertion. Compare the `51ee40d` production
prefetch files with the candidate using the same test. Never reset a user's
signed-in device. The UTC-window capture rejects malformed bounds, filters
completions to the requested interval, retains only allowlisted numeric metadata
and marks missing dimensions null. A synthetic canary verifies outside-window
exclusion, unknown-field/payload redaction and missing-value handling.

Authoritative artifacts under `verification/convex-cost/`:

- `android-controlled-journey-before.json` and `android-controlled-journey-after.json`
- `android-controlled-usage-before.json` and `android-controlled-usage-after.json`
- `android-controlled-idle-before.json` and `android-controlled-idle-after.json`
- `idle-observation.json`
- `ios-reader-journey.json`, `ios-reader-usage.json`, `ios-reader-idle.json` and `ios-idle-control.json`

For iOS, select a separate fresh simulator and keep normal simulator signing:

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme Phase4Live -destination 'platform=iOS Simulator,id=<isolated-simulator-id>' -only-testing:HadithlyUITests/ReaderR5UITests/testConvexCostColdLaunchLibraryAndTenPageMoves -parallel-testing-enabled NO test
```

Do not disable signing: Clerk's real guest path needs simulator keychain
entitlements. Check the built app's deployment host before running it.

Resource interpretation follows the current official
[Convex limits](https://docs.convex.dev/production/state/limits) and
[execution log documentation](https://docs.convex.dev/production/integrations/log-streams).
The CLI exposes recent events without installing a paid log-stream integration.

The remaining largest reader I/O candidate is the chapter-rich Bukhari outline
read on a cache miss. Splitting its metadata requires a separately measured
backend design, schema/backfill decision and any needed action-time approval.
This unit does not silently introduce that migration or promise unlimited free use.
