# Consistently smooth iPhone reader

Status: Baseline complete; measured interruption repairs committed, strict final acceptance open. The owner approved this continuation on November 1,
2026. The earlier bounded repair remains verified only against its recorded
5 ms/s mean target in `SCROLLING_VERIFICATION.md`.

## Contract and ordered goals

Preserve typography, floating controls, safe-area text, gestures, source actions,
accessibility and semantic reading positions. Work iPhone-first, with Android
behavioral parity. Do not start page-transition caching or priority-4 translation
work. Keep A2 row mode off and all original product acceptance gates open.

1. Establish matched optimized-development physical baselines and attribute
   remaining hitches. Record passage, text digest, settings and device conditions.
2. Remove only the interruptions supported by those measurements. Preserve
   durable final saves, scope fencing, ordering, rollback and lifecycle behavior.
3. If text creation/layout still fails, compare bounded SwiftUI with reusable
   UIKit/TextKit 2 rendering. Keep SwiftUI if both pass. Replace only the text
   surface if UIKit alone passes the performance and behavioral requirements.

The warm scrolling target is strictly below **1 ms/s in every retained run**,
three 30-second repetitions for each slow/flick workload and content condition.
This is a project quality target, not an Apple threshold. Report individual
hitches and investigate recurring stalls. Owner confirmation on the optimized
installed app is required. Average-only results, zero unsupported SDK fields,
simulator timing and builds cannot close that gate.

## Primary-source research and architectural constraints

- [Apple responsiveness guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
  recommends keeping non-UI work off the main actor and profiling actual hitches.
- [SwiftUI Instruments](https://developer.apple.com/videos/play/wwdc2025/306/)
  traces update causes and observable dependencies. Inspect many short updates
  as well as individual long updates.
- [Scroll geometry](https://developer.apple.com/documentation/swiftui/view/onscrollgeometrychange(for:of:action:))
  changes frequently; avoid broad app updates from every geometry callback.
- [TextKit 2](https://developer.apple.com/videos/play/wwdc2021/10061/) provides
  viewport-based layout. A fully measured text view inside another scrolling
  container can defeat that advantage.
- [Collection reuse/prefetching](https://developer.apple.com/videos/play/wwdc2021/10252/)
  bounds creation and prepares content ahead of display. Very large individual
  cells still need investigation.
- [TextKit compatibility](https://developer.apple.com/videos/play/wwdc2022/10090/)
  explains why accessing `layoutManager` can force TextKit 1 fallback.
- [ProMotion](https://developer.apple.com/documentation/quartzcore/optimizing-iphone-and-ipad-apps-to-support-promotion-displays)
  adapts frame pacing. Hardware maximum refresh is not observed display FPS.

The phone reference is Sajda 6.7.1, build 5325. Live inspection confirms text
scrolling beneath fixed page/juz pills, tap-to-hide floating controls and page-end
navigation within the reading surface. Page 263 remained selected. This establishes
observable interaction and appearance, not measured FPS or a proprietary renderer.
No Sajda setting, account or audio action was changed.

## Reproduction and instrumentation

The previous installed-app result `[6.285142, 0, 0]` ms/s fails the new
`--each-scroll-hitch-below 1` check. Its 2.095 mean cannot conceal the failing
run. Executable checks cover this distinction, the strict boundary, empty
scrolling, non-finite values, zero frame counts and incomplete trace windows.

`scripts/build-reader-profile.py` builds locally for generic iOS using Debug's
development configuration with Swift `-O`, whole-module compilation, C `-Os`
and dSYMs. It retains DEBUG conditions and development entitlements. It verifies
the explicit development URL, app identity and diagnostics environment and does
not install or regenerate Xcode files. Existing Release uses Production.xcconfig.

`HADITHLY_READER_PROFILE=1` enables fixed-name signposts for geometry handling,
scroll persistence and native interacting/decelerating phases, plus a DEBUG-only
metadata snapshot. Metadata contains
public passage identity, a text digest, display preferences and initial
power/thermal conditions. It excludes account identifiers and text contents.

`prepare-reader-profile-run.py` selects the destination-only physical test and
removes the generated injected `libRPAC` profiler, PERFC environment variables
and performance/main-thread checkers. Code coverage and verbose performance
diagnostics are disabled; automatic attachments are discarded. Incoming scheme
files remain unchanged. These are measurement controls, not a claimed cause of
the owner's original lag.

The physical test activates the installed reader without launch/reset arguments.
`HADITHLY_SCROLL_SECONDS=30` requires a metadata snapshot and actual content
movement before measuring. In trace mode it drives one run per capture, verifies movement
in each and emits measured-run boundaries without invoking XCTest metrics.
`run-reader-device-scroll.py --trace` collects Hitches, Core Animation activity,
commits, server work, frame lifetimes, display presentations, Points of Interest
and Activity Monitor. It uses deferred recording and waits for Instruments'
capture-ready notification before driving gestures. It rejects a disconnect or incomplete run and
exports native data for `summarize-reader-scroll-trace.py`.

The summary intersects app-attributed hitch intervals with native active-scroll
intervals, merges overlaps and checks every run against 1 ms/s. The capture must
contain app frame-update events, display presentation events and app CPU/footprint samples. Presentation
counts belong to the shared display and do not establish app FPS. CPU deltas
and peak footprint describe the observed resource-sampling windows.

Raw results remain local under `/tmp/hadithly-smooth-reader-20261101`.
No whole-app FPS claim follows from unsupported zero frame counts.

The optimized development app and updated test runner were built and installed;
the installation URL and bundle identity were read back. Subsequent launch
timed out while the phone displayed its lock screen. After the owner unlocked
it, the SDK metric service disconnected during the long run. Only one sample
and zero frame counts remained, so the capture was rejected. The native and SDK
scroll-duration fields both described about 1.33 seconds despite the 33-second
loop; they do not establish whole-loop coverage.

The first gesture-only Instruments attempt was also rejected. The test host
reported Low Power Mode and the trace ended after its network connection dropped.
The owner connected USB, disabled Low Power Mode and unlocked the phone. The
validated optimized app and runner were installed again, with matching app
installation readback and binary digest. The clean wired capture stayed
connected, verified 333 points of content movement and completed its first
30-second repetition. The second repetition changed from nominal to fair
thermal state, so the test rejected the set. It is diagnostic evidence only.
The unfinished device-wide trace was terminated after excessive data growth and
removed to recover local space; logs and rejection metadata remain. A five-second
wired PID-attachment probe then completed and finalized at 55 MB. The final
baseline capture uses the lighter instruments above without CPU stack sampling,
and retains all-process signposts so the test driver's measured boundaries are
present. A capture-ready notification avoids the earlier truncated first
interval. Driver identity uses its fixed subsystem because Instruments may name
the newly started runner `Process (pid)`. Finalization is limited to two minutes.

Rolling-window captures produced display presentations but no app frame updates.
Their apparent zero-hitch results are rejected. Removing the rolling window
restored app frame-update and hitch records. Three matched optimized ordinary slow runs establish a repeatable failure:
26.35, 24.33 and 27.59 ms/s, with 35, 37 and 45 active hitch events and individual
hitches up to 25 ms. Measured windows are 30.35, 30.15 and 34.15 seconds, with
18.66, 18.67 and 21.30 seconds of active scrolling. Low Power Mode is off and
thermal state remains fair throughout each retained run. The portable record is
[smooth-reader-verification/ordinary-slow-baseline.json](smooth-reader-verification/ordinary-slow-baseline.json).
The full initial matrix is now complete; see the controlled-baseline section below.

All 35 active hitches in the first run map by display/swap identity to app-update
work. Fourteen associated app-update intervals overlap progress persistence;
all overlap geometry callbacks. The matched updates have median duration 14.53 ms
and maximum 20.49 ms. Temporal overlap is correlation, not causal attribution.
The first run includes 28 persistence operations up to 13.51 ms. The geometry
callback's inclusive maximum is 9.57 ms. The first controlled repair is selected in
[SMOOTH_READER_DECISION.md](SMOOTH_READER_DECISION.md). Its non-observed live
geometry holder is prepared locally but has not been built or installed yet. Raw device traces stay outside git.

The preparation passes 160 iOS safety cases, two iOS simulator checks for
full-bleed controls and semantic reanchoring, eight Android emulator parity cases
and twelve focused Python checks. The final diagnostic additions also build for
optimized development iOS. These checks do not close the physical frame gate.

## Complete initial baseline and repair direction

[smooth-reader-verification/baseline-matrix.json](smooth-reader-verification/baseline-matrix.json)
contains all 18 valid runs, individual hitch durations, active-scroll coverage,
CPU and sampled footprint. All six conditions fail the strict target.

| Condition | Slow runs, ms/s | Fast runs, ms/s |
| --- | --- | --- |
| Ordinary English 18 pt | 26.35, 24.33, 27.59 | 16.59, 12.61, 20.10 |
| Single Hadith 7, bilingual 18 pt | 10.37, 11.35, 10.34 | 15.54, 18.53, 15.27 |
| Original page, Arabic 40 / English 22 pt | 52.94, 36.83, 32.89 | 28.92, 32.61, 28.10 |

The long condition is one 22,032-byte narration. The large-type condition uses
multiple hadiths so one oversized row does not hide multi-row update costs.
Every retained gesture now requires both a native scrolling interval and app
frame/presentation evidence. Historical ordinary captures were revalidated
against the actual gesture counts in their driver logs.

The initial ordinary cohort was stable fair thermal state; later cohorts are
stable nominal. The nominal ordinary repeat from a known header entry is complete. Its slow runs
are 14.92, 19.01 and 20.99 ms/s; fast runs are 24.93, 12.12 and 27.44. The
[controlled matrix](smooth-reader-verification/controlled-baseline-matrix.json)
contains all 18 nominal-temperature comparison runs. An incomplete final fast
trace was rejected and repeated. Do not merge thermal conditions into one
before/after improvement claim.

A separate 20-second app-only CPU trace completed. The reproducible
`summarize-reader-cpu-profile.py` report attributes leaf CPU predominantly to
SwiftUI/AttributeGraph, with library synchronization/storage also present.
CoreText is a small sampled share in this ordinary workload. A combined
stack/hitch diagnostic failed on an Instruments backtrace type mismatch; the
simpler Time Profiler capture succeeded. A focused SwiftUI template did not
resolve the running PID, so no view-specific cause graph is claimed.

The architecture decision retains SwiftUI for a small geometry-state experiment.
It preserves capture/restoration math and the single native scroll writer.
Persistence remains on the main actor in this candidate. Full physical acceptance
and a causal result are still open.

## Quiet-period persistence repair

Two geometry experiments failed to improve large type and were removed. Their
records are `anchor-cache-experiment.json` and `bounded-viewport-experiment.json`.
The retained interruption repair defers durable progress writes until 500 ms
without viewport motion, while keeping the latest semantic location and its
capture-time ordering. Explicit final saves, stop, backgrounding and pending
account fences remain in force. Storage still runs on the existing main actor
once quiet; no background executor is claimed.

All 161 safety tests and two full-bleed/reanchor UI checks pass. The new real-path
regression was red before repair and now verifies no accepted durable positions
during continuous motion, exact final sub-threshold offset and capture timestamp.
The first matched large-type slow run measures 8.04 ms/s and 11 hitches, versus
the baseline's 32.89–52.94 range. Geometry peaks at 0.42 ms; progress saves fall
from 42 to 14. See [the portable record](smooth-reader-verification/quiet-persistence-experiment.json).
The strict target still fails. A separate CPU diagnostic will attribute remaining
work; the full final matrix and owner confirmation remain open.

## Shared quiet scheduling and current proof

Combined frame/CPU attribution identifies library/storage work in 16 of 19
late-frame preparation windows. Commit `a6c3035` defers normal reconciliation,
read-snapshot hydration and projection until the reader is quiet. Native scroll
phase keeps that gate closed while a finger is held, during interaction and
deceleration. Geometry remains the iOS 17 fallback. The latest full snapshot per
stream replaces older queued reads. Durable mutations and accepted receipts
retain ordering, account/deletion fences, rollback and late-settlement behavior.
The next local position timestamp can see an already received deferred position.
Explicit final/background saves still flush through the existing ordered store.

The geometry-only gate measures 2.23 ms/s. The first native-phase candidate
measures 0.67 ms/s. The bounded-read/ordering candidate measures **1.34 ms/s**
with two 12.50 ms hitches, so the strict target still fails and matrix expansion
stops. Storage, projection and persistence have zero active-scroll overlap in
both native-phase runs. They also do not overlap either associated 15.09 or
17.13 ms app-update interval in the latest run. Attribution of that remaining
UI delay is next; a renderer replacement is not yet justified.
See [the exact result](smooth-reader-verification/phase-bounded-quiet-experiment.json)
and [implementation decision](SMOOTH_READER_DECISION.md).

All 171 safety tests, two full-bleed/reanchor UI checks and 13 capture checks pass.
Eight further [simulator behavior cases](smooth-reader-verification/phase-bounded-behavior.json)
pass, including large RTL/long-locale source clearance and growth, guest Saved
return, text resizing, manual header/revisit landing, vertical no-page-turn,
language/accessibility structure and focus-position stability. These do not
replace physical VoiceOver or owner confirmation. The existing eight unchanged
Android parity cases retain their recorded scope; no Android product code changed.

The owner-requested exact rollback remains commit `2ad8243`, local tag
`reader-smooth-owner-20261102` and the signed bundle/source archive documented in
[SMOOTH_READER_CHECKPOINT.md](SMOOTH_READER_CHECKPOINT.md).

The iPhone became occupied in another app after the valid wired capture and now
reports local-network transport. Phone inspection was detached. Two subsequent
diagnostic attachment attempts produced no usable capture. Wait for the owner's
availability response before further physical actions; local checks are complete.

## Remaining proof

- Attribute the remaining 15–17 ms app updates before changing another variable.
- Complete the matched final three-run matrix and inspect individual stalls.
- Verify remaining live Continue/Saved restoration and physical VoiceOver,
  then obtain fresh owner confirmation on the optimized installed build.
- Preserve incoming iOS project/scheme/catalog and Python cache bytes, all
  original program gates, A2 row mode off and deferred page-cache/priority-4 work.
  Commit completed logical units without pushing.
