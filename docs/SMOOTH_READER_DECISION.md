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

## Post-commit reuse and the remaining preference path

The account store now reuses the exactly committed decoded state only after a
successful durable write. Fresh-row owner/byte checks, the existing 8 MiB bound,
rollback and erasure behavior remain. The real write-followed-by-read benchmark
was red at 177.53 ms for 20 reads and passes at 20.21 ms. All 161 safety tests
pass. Its first matched large-type run remains 9.59 ms/s, so no hitch benefit is
claimed. See [the record](smooth-reader-verification/committed-cache-local.json).

A focused SwiftUI trace succeeded when attaching by process name. It records
253,111 update events, with preference propagation prominent. One high-severity
7.24 ms update names `PreferenceBinder<ReaderScrollStateKey>` among its causes.
Nested update times overlap; the diagnostic does not measure acceptance hitches.
This new evidence supports retesting bounded viewport tracking after quiet-period
persistence. Earlier geometry tests ran with 42 saves per workload, so they did
not isolate the remaining post-repair preference cost. Keep the same renderer,
typography, single landing writer and semantic restoration during that test.

## Combined geometry result and next attribution

The combined bounded-tracking/quiet-save build passed both UI checks but still
measured 8.94 ms/s with 14 hitches. The extra geometry implementation was removed.
The [record](smooth-reader-verification/quiet-bounded-viewport-experiment.json)
preserves the failed experiment. Preference tracing suggested a candidate, but
the controlled test does not support retaining it as a hitch repair.

[Matched frame phases](smooth-reader-verification/remaining-frame-phases.json)
show 1.21–1.55 ms GPU phases for the 15 retained hitches in the post-commit-cache
run. Render CPU phases peak at 3.68 ms. These pipeline intervals overlap and must
not be added. Two associated app updates exceed 15 ms. This keeps app work and
synchronization in scope; it does not establish a GPU limit. See Apple's
[frame-lifetime explanation](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app).

The standard Animation Hitches template, with app-only Time Profiler and Points
of Interest, successfully captured the complete scrolling driver. Unlike the
older custom combination, it finalized without the backtrace schema error.
Correlate its late-frame lifetime and main-thread stacks before further repairs.
The installed app during this diagnostic still contains the rejected bounded
tracking experiment; local ReaderView.swift is restored to the retained renderer.
This diagnostic is not an acceptance run. Restore the retained app before final
owner testing. The below-1-ms/s matrix and full behavior/owner gates remain open.

## Owner checkpoint overrides experimental removal

The owner subsequently reported that the currently installed app feels much
better and requested an exact checkpoint before continuing. Restore the bounded
tracking source to match that installed binary and preserve it in the
[owner checkpoint](SMOOTH_READER_CHECKPOINT.md). The whole tracked iOS source
digest matches the build manifest, including incoming files left uncommitted.
This preserves a known improved experience, while the strict 1 ms/s gate and the
isolated geometry-benefit claim remain unproven. Further work continues from
this rollback point rather than discarding the owner's observed improvement.

## Correlated sync work and shared quiet period

The successful combined capture joins frame lifetimes, update records, main-thread
CPU samples and thread-state intervals by frame identity. Sixteen of its 19 late
frames are dominated by library/storage samples in their preparation windows.
Examples spend approximately 14–23 sampled milliseconds in `LibrarySync.run`,
`GuestDataStore` and `UserLibraryModel.reloadAccount`. Every joined frame-lifetime
end matches the hitch's final presentation time within exported timestamp precision.
The [diagnostic record](smooth-reader-verification/correlated-main-thread-diagnostic.json)
is not a performance acceptance score because CPU tracing changes the workload.

The candidate shares reader motion timing with normal sync and subscription
processing. A single existing ordered account writer waits for 500 ms of quiet
before reconciliation and projection work. Received full snapshots wait for
quiet, are checked again against owner/session/epoch, and are cleared on
unsubscribe. There is no second writer and no background-executor
claim. Initial owner binding remains available for local intent capture.

Accepted late receipts keep the original settlement rule: cancellation does not
drop a reply for the captured owner's still-existing partition. Session checks
and deletion fences still reject unrelated or erased owners. Two real-path tests
were red before this repair and pass after it; the expanded 165-test safety suite
and both UI checks also pass, including deferred-snapshot account changes and
late-receipt cancellation. The first geometry-only quiet candidate measures
2.23 ms/s with three hitches. See
[the matched result](smooth-reader-verification/shared-quiet-experiment.json).

## Native phase closes the geometry quiet gap

Geometry updates can stop while a finger remains down. On iOS 18 and later,
the next candidate keeps a per-viewport activity token through native tracking,
interaction, deceleration and animation. Work resumes 500 ms after all active
viewports end. Geometry remains the iOS 17 fallback. Page/volume changes,
disappearance and backgrounding release the reader's own tokens; explicit final
position saves still flush immediately through the existing writer.

All 168 safety tests and both UI checks pass. The first valid matched large-type
slow run measures **0.67 ms/s**, with one 12.50 ms hitch. Storage, projection and
progress-save intervals have zero overlaps with native active scrolling. Their
respective maximum durations are 11.79, 1.81 and 3.06 ms. The 0.44 ms geometry
callback overlaps the hitch; overlap alone does not attribute that hitch to
geometry. CPU is 12.03 sampled seconds and peak sampled footprint 182.06 MiB.
The first attempt disconnected and was rejected. See
[the exact build and result](smooth-reader-verification/phase-aware-quiet-experiment.json).
One passing run does not close the repeated matrix or owner gate.

Two further real-path tests exposed issues before final installation: 40 full
read snapshots caused 40 durable writes after quiet, and a received remote
position's timestamp was invisible to the next local capture. Both tests were
red, then green. The queue now retains at most one highest-version full snapshot
per stream. Durable mutations and receipts retain their original order.
The reader's ordering clock sees the deferred current Positions snapshot without
hydrating storage or publishing UI changes. Stale versions cannot advance it,
and owner changes clear it. All 171 safety tests and both reader UI checks pass
on these additional changes. See [the local record](smooth-reader-verification/shared-quiet-local.json).
The first [matched physical repetition](smooth-reader-verification/phase-bounded-quiet-experiment.json)
measures 1.34 ms/s with two 12.50 ms hitches, so matrix expansion stops. Storage,
projection and progress persistence again have zero active-scroll overlap.
The associated app updates take 15.09 and 17.13 ms; attribute that remaining
delay before changing another variable. Eight further simulator behavior checks
pass, including Saved return, large text/growth, manual landing/revisits and
focus-position stability. The phone is now occupied; wait for owner availability
before the next diagnostic. The owner's exact checkpoint remains unchanged.

## Offline frame-phase attribution after the shared gate

An additional serial export from the same retained 1.34 ms/s trace joins both
remaining hitches to frame lifetimes, app updates, render/GPU phases and commit
calls. Each lifetime ends at the hitch's final presentation within exported
timestamp precision. No new physical action was needed. The
[frame record](smooth-reader-verification/remaining-phase-quiet-frame-phases.json)
keeps those joins and the exact measured build.

GPU phases take 1.10 and 1.11 ms; render phases take 3.21 and 3.29 ms. The
longest individual app commit calls within the associated app updates take
0.89 and 0.40 ms. Pipeline intervals overlap and must not be added. Both app
updates begin approximately 36.6 ms after native active scrolling starts, on
separate gestures. Storage/projection/persistence have zero overlap with the
entire associated app-update windows. The residual is early in a drag, and
these records do not establish an expensive glyph-layout or GPU bottleneck.

The next ranked explanations and predictions are:

1. Early-scroll UI/gesture work. Simultaneous main-thread samples should show
   reader gesture callbacks, SwiftUI graph processing or layout occupying the
   affected update windows. A repair must remove the attributed work and then
   improve the same matched physical workload.
2. Main-thread waiting or scheduling. The affected update windows would have
   relatively little running CPU and substantial blocked/runnable time. Inspect
   that state before interpreting wall time as expensive text layout.
3. Text creation/layout. CoreText/TextKit or glyph preparation would dominate
   those windows, with the long/large cases reproducing the cost. Only that
   evidence would reopen the conditional renderer comparison.

The owner-checkpoint CPU trace predates the shared gate; do not use its samples
to claim the new candidate's residual cause. Capture the latest installed
candidate after the owner says the phone is free. Keep the failed 1.34 ms/s run,
the strict metric and owner acceptance gate unchanged.

## Resumed diagnostics and early axis-rejection experiment

The owner made the phone available again, open and wired. Preparation confirms
the same passage, Arabic 40/English 22 pt, generation off, Low Power Mode off
and nominal thermal state. The installed measured binary is unchanged.

The first [resumed CPU/frame diagnostic](smooth-reader-verification/resumed-phase-diagnostic.json)
contains 1,969 active app updates including preflight, with median 3.74 ms,
p95 5.55 ms and maximum 12.44 ms. It has no hitch rows. This is a valid
diagnostic that did not reproduce the stalls, not an acceptance replacement for
the retained 1.34 ms/s failure.

The second [waiting-thread diagnostic](smooth-reader-verification/resumed-waiting-diagnostic.json)
catches three late frames in measured native scrolling and one additional frame
outside native active intervals. Scheduler intervals show approximately 12–15 ms
blocked and 3–8 ms running in their preparation windows. Stack examples in the
measured frames contain UIKit gesture/container traversal and SwiftUI graph
resolution, rather than library storage or text layout. They do not identify a
specific blocking call as the complete cause. The extra inactive frame includes
Clerk device-ID/receipt synchronous XPC; it is not an active-scroll result and
no authentication change is proposed.

Instruments warns that the requested 5 ms sampling period differs from its
configured 1 ms period. Sample weights/percentages are therefore omitted from
the portable record; stack identities and separately recorded scheduler
intervals remain diagnostic evidence only. Only the completed recorder's owned
temporary directory was cleared after its saved trace was verified, recovering
3.88 GiB. The saved capture remains available.

The paging recognizer currently begins on vertical input and remains a
simultaneous window recognizer throughout scrolling. The next bounded experiment
rejects clearly vertical input in
[`gestureRecognizerShouldBegin`](https://developer.apple.com/documentation/uikit/uigesturerecognizerdelegate/gesturerecognizershouldbegin%28_%3A%29).
Apple documents that returning false moves that recognizer to failed before it
begins. Existing horizontal/ambiguous input, page-turn mapping and native scroll
ownership remain. This tests whether removing the redundant paging participant
reduces the gesture/graph traversal associated with the remaining frames.

Two real delegate-seam tests were red before the change, with five failed
assertions. The candidate passes all 41 paging/round-3 unit checks and three
gesture UI cases for fast/canceled, vertical and horizontal input. The optimized
development app passed its behavior checks, but the
[matched timing run](smooth-reader-verification/early-axis-experiment.json)
measures 2.68 ms/s with four 12.50 ms hitches. CPU is lower, but that does not
establish a hitch benefit. Reject the experiment: both production and test
changes were restored, and the retained development build was rebuilt and
installed. The owner's exact rollback bundle/tag remain unchanged.

On November 2 the owner accepted the restored installed reader as good enough
and chose page/volume transitions for the next session. Stop the marginal
sub-1-ms investigation under that revised product decision. The original strict
target was not achieved; neither the diagnostic with no hitches nor the owner's
acceptance is a retroactive passing result for that target. Remaining storage,
transition/cache and lifecycle findings are carried into the next-session records.
