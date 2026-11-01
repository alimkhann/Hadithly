# Smooth reader implementation decision

November 2, 2026. Keep the current SwiftUI renderer. Two geometry experiments
did not improve the measured stalls and were removed. The current experiment
defers progress persistence until viewport motion is quiet. UIKit/TextKit 2
remains conditional on a measured text-layout limit; the full performance gate remains open.

## Evidence

The [baseline matrix](smooth-reader-verification/baseline-matrix.json) contains
18 valid optimized-development physical runs. All fail the strict 1 ms/s target.
Each run contains at least 30 seconds of workload, app frame updates, display
presentations, CPU/footprint samples and a native scroll interval for every
reported gesture. The record includes individual hitch durations. Live mirroring,
runtime checkers and CPU stack sampling are excluded from acceptance captures.

| Condition | Slow runs, ms/s | Fast runs, ms/s |
| --- | --- | --- |
| Ordinary English, 18 pt | 26.35, 24.33, 27.59 | 16.59, 12.61, 20.10 |
| Single long Hadith 7, bilingual 18 pt | 10.37, 11.35, 10.34 | 15.54, 18.53, 15.27 |
| Multi-hadith page, Arabic 40 pt / English 22 pt | 52.94, 36.83, 32.89 | 28.92, 32.61, 28.10 |

The original ordinary cohort is stable fair thermal state; the later cohorts
are stable nominal. The [controlled matrix](smooth-reader-verification/controlled-baseline-matrix.json)
repeats ordinary at nominal temperature and a known header entry. Its slow runs
are 14.92, 19.01 and 20.99 ms/s; fast runs are 24.93, 12.12 and 27.44. Keep the initial cohort as
historical evidence and do not mix the thermal conditions in improvement claims.

All 35 retained hitches in the first ordinary slow run map to app-update work by
frame display/swap identity. Fourteen of those update intervals overlap progress
persistence. The matched app updates have median duration 14.53 ms and maximum
20.49 ms. Persistence reaches 19.04 ms in the first large-type run. Temporal
intersection alone does not prove which operation caused a missed deadline.

The separate [20-second CPU diagnostic](smooth-reader-verification/ordinary-cpu-diagnostic.json)
covers 3,351 ms of sampled main-thread CPU within seven complete native scrolling
intervals. AttributeGraph and SwiftUICore account for 36.41% of leaf samples.
Library synchronization appears in 16.50% of sampled stacks; GuestDataStore in
14.83%. These inclusive groups overlap. CoreText appears in 0.03%. This ordinary
workload does not establish the cold-layout cost of every possible long passage.

A focused SwiftUI diagnostic could not resolve the already running app PID, so
it yielded no view-specific cause graph. The first repair must therefore be
verified by an actual before/after experiment, rather than treating the source
inspection as proof of causation.

## First controlled repair

`ReaderPageView` stores its latest anchor dictionary in `@State`. Its geometry
callback changes this dictionary on every offset update even though the text
content has not changed. The dictionary is needed by landing callbacks, not by
the text's visual rendering.

Use one page-owned `ReaderLiveAnchorFrames` reference with an ordinary dictionary
field. Retain its identity in `@State`, while updating its non-observed value.
Keep the existing capture algorithm, normalized offsets, current-page checks,
model-owned landing command and single `ScrollViewReader` writer.

Prediction: the same gestures and progress writes produce less SwiftUI update
work and fewer hitches. First compare the largest failing case under matched
conditions, then repeat the full matrix. A lower average cannot close the gate.
If the result does not improve, reject this explanation and inspect geometry
propagation and synchronization before extending the change.

This candidate does not move persistence off the main actor. If storage still
interrupts scrolling, the next repair must preserve one ordered account writer,
account fences, rollback, final-position flushing and background/exit behavior.
Wrapping existing synchronous work in `Task {}` is not a background executor.
Do not introduce a second context that can overwrite another writer's account
snapshot.

Do not add redundant equality guards to the Saved arrays. They already conform
to `Equatable`; a local probe with the active compiler reports zero observation
notifications for an identical array assignment and one for a changed value.
Rebuilding projections can still consume CPU and remains a separate measured
candidate. The probe does not prove all library updates are cheap.

## Reference behavior

Sajda 6.7.1, build 5325, was inspected on the connected iPhone. A drag moved the
Russian Quran text from the 15:24 range toward 15:31 while the page/juz pills
remained fixed on page 263. Tapping toggled the floating controls and status bar.
The page-end navigation remained in the reading surface. The page number did
not change. This is an interaction/appearance observation, not measured FPS or
evidence of Sajda's private renderer. Its settings, account and audio were not
changed.

Preserve Hadithly's full-bleed text, floating controls, font choices, RTL,
accessibility and gestures. Apple's
[render-loop guidance](https://developer.apple.com/documentation/xcode/improving-app-responsiveness)
and [SwiftUI performance guidance](https://developer.apple.com/videos/play/wwdc2025/306/)
support optimizing the attributed update path first.

## Stop and acceptance

The candidate is prepared locally and has not yet been installed. Require
matched physical runs, full functional regression checks and owner confirmation
on the optimized development build before closing the smooth-reader goal.
Retain SwiftUI if it passes. Compare bounded SwiftUI and reusable UIKit/TextKit 2
only if attributed text creation/layout still prevents acceptance. Preserve all
original program gates, incoming files, A2 row mode off, and the deferred page
cache and priority-4 work.

## First experiment result and bounded tracking

The non-observed dictionary alone measured 35.61 ms/s on the nominal, wired
large-type workload, within the baseline's 32.89–52.94 range. It is insufficient;
no improvement is claimed. Both full-bleed and semantic-reanchor UI tests passed.
The [experiment record](smooth-reader-verification/anchor-cache-experiment.json)
retains the measured result and exact candidate build.

The next experiment stores item frames in a stable content coordinate space and
projects them using one viewport offset. On iOS 18 and later, the offset comes
from Apple's `onScrollGeometryChange`; iOS 17 retains a single content-origin
geometry preference. The same model landing command and ScrollViewReader remain
the only scroll writer. The prediction is fewer page-wide geometry updates and
less app-update work without changing semantic restoration. The candidate passed both UI checks but measured 35.13 ms/s, again within
baseline variation. The [result](smooth-reader-verification/bounded-viewport-experiment.json)
is retained and both geometry experiments were removed. Neither warrants extra
renderer complexity.

## Quiet-period persistence experiment

Both large-type experiments still performed 42 progress saves per run, taking
up to 15 ms each. The next candidate keeps the latest viewport anchor/offset
cheaply and waits for 500 ms without geometry motion before saving. One pending
task follows the latest quiet deadline. It does not encode a new durable position
for each capture. Explicit final saves, stop and background behavior still flush
the latest semantic location, and the pending scope must pass the existing
account fence. Writes remain serialized through the existing main-actor store;
this is deferral to a quiet period, not background execution.

A regression using the real reader/library/store path fails before the change:
continuous motion generated six partition-change notifications before quiet.
The corrected counter deduplicates sync acknowledgments by position timestamp.
All 161 safety tests and two UI checks pass on the final ordered implementation.
The [first matched run](smooth-reader-verification/quiet-persistence-experiment.json)
measures 8.04 ms/s with 11 hitches, down from the 32.89–52.94 baseline range.
Geometry callback maximum falls to 0.42 ms. Saves fall from 42 to 14, with a
5.13 ms maximum. Sampled CPU is 12.21 seconds versus baseline 12.52–12.60;
peak sampled footprint is 165.75 MiB versus 177.61–178.49. These are observed
windows, not whole-app resource guarantees. Retain this interruption repair,
but do not claim the target passes or expand the full matrix while this case
still fails. Remaining hitches do not overlap the save intervals or their joined
app updates. A separate CPU diagnostic is running to attribute the remaining work.
