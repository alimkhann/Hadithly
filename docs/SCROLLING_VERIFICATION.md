# Reader scrolling and floating controls

Status: bounded scrolling goal verified on the installed iPhone build; original acceptance gates remain open. November 1, 2026.

The owner started this goal after priority-2 verification. Scope is loaded-page
vertical scrolling and the owner-reported blank-header regression. Page turns,
page-cache changes, development Free/Pro controls and translation reliability remain
later goals. The approved physical work includes installing the latest build and
profiling the explicitly selected iPhone without reset, sign-in or model calls.

## Baseline and causal test

The current worktree Debug build was installed on the owner's iPhone 16 Pro,
iOS 27.0.1, bundle `com.hadithly.app`, version 0.1.0 (1), using existing local
signing. Installation and bundle identity were read back. The initial deployment
host assertion used an obsolete unregional hostname and failed; the subsequent
readback confirms the correct regional development host. No configuration was
changed. Future dependent validation and installation must run separately.

The owner manually scrolled the same already-loaded passage without page turns
or AI generation during the approved 30-second Time Profiler trace. The trace
spans 31.178 seconds. They describe continuous motion resembling 5–10 FPS,
without severe jumping. That is a subjective estimate. Time Profiler does not
measure display FPS. The passage identity, locale and text sizes were not
captured; the original physical trace alone cannot establish an exact matched
frame-rate improvement.

The main thread contains 13,070 statistical CPU samples, including one without a
backtrace. Inclusive app stacks include 1,680 samples in stable-scroll capture,
1,648 in ReaderModel.saveProgress, 1,634 in UserLibraryModel.saveProgress,
1,643 in the account-partition accessor, and 1,687 in the sync worker. These overlap and must
not be summed. The portable summary is produced by
`scripts/summarize-reader-time-profile.py` from an xctrace time-profile XML export.

The real ReaderModel → UserLibraryModel → LibrarySync → GuestDataStore local
account path, using fake transport and an isolated store, reproduces 31
synchronous account writes for 31 scroll captures. The regression fails before
the fix at both the burst limit (31 > 1) and final-save limit (32 > 2). The target
is at least 90% fewer synchronous writes in that burst, exact final semantic and
raw position, no delayed overwrite after explicit save, bounded idle flush, and
no write into a different account. This is a causal work reduction target, not
an FPS claim. Physical before/after timing remains required; the subsequent owner request
selects agent-driven scrolling for the remaining diagnosis.

## Paired physical frame capture

After local verification, the owner confirmed readiness on the same loaded
passage and settings while the phone still had the pre-repair build. The same
Animation Hitches template is used for both 30-second recordings; it includes
Time Profiler sampling. The baseline spans 31.104395 seconds and records 227
app-attributed hitch intervals, 2,492.087 ms in total, or 8.012% of the trace.
Intervals are merged to avoid double-counting. The longest hitch is 50.009 ms.
These are hitch measurements, not an average FPS calculation.

Before reading the updated-build trace, the physical comparison target is at
least a 50% reduction in the hitch interval ratio, with no worse maximum hitch,
plus owner confirmation of improved motion. Manual gestures are not identical
input replays, so paired trace improvement alone will not be described as a
precise causal percentage. The local real-account write test establishes the
work reduction independently.

The verified repair Debug bundle was built using existing local signing,
installed without a reset, and its new installation URL and bundle identity
were matched to the installed-app readback. The owner reopened the same passage
and settings and confirmed Ready for the updated-build recording. The exact
collection, page and text sizes are not independently captured; matching relies
on that owner confirmation. Both recordings exclude page turns and generation.

The updated trace spans 31.177796 seconds: 102 hitches, 1,683.619 ms of hitch
intervals, a 5.400% ratio and a 41.674 ms maximum. The ratio falls by 32.6%, which
misses the proposed 50% target. The owner confirms smoother scrolling and restored
appearance, but still sees microjitters/microlags and requests agent-driven
scrolling and a root-cause repair. The goal remains active.

Matched Time Profiler stacks show UserLibraryModel.saveProgress samples falling
from 1,064 to 405. LibrarySync.run remains expensive, increasing from 1,648 to
2,086 inclusive samples in these manual runs. Total sampled main-thread time
does not improve, so the first repair does not justify claiming the remaining
performance defect is fixed. The next step is a guarded on-device scrolling
loop and correlating remaining hitches with sync/decoding, reader graph updates
and render work. The existing physical installation/profiling authorization and
the owner's explicit request to drive scrolling apply; no data reset, sign-in,
generation or backend change is part of that loop.

## Floating controls

History identifies `48f0794` as the reserved-viewport change. A5 prevented source
and controls overlapping at large Dynamic Type, but moved the entire scroll
viewport below the pills. The new red iOS check observes viewport Y=124 and pill
Y=70. Android independently reproduces the same structural regression. The
owner wants text to flow behind the floating controls and into the safe areas.

The repair moves measured clearance into native scroll content margins/padding.
See [Apple contentMargins](https://developer.apple.com/documentation/swiftui/view/contentmargins(_:_:for:)-lgl5)
and [Android content padding](https://developer.android.com/develop/ui/compose/lists#content-padding).
The full-screen viewport can draw behind the controls; initial headers and
explicit semantic targets retain clearance. iOS anchor capture, visibility,
scroll fraction and restoration continue to use the unobscured reading area.
The single landing owner remains in control. Clearance remains stable when
chrome is hidden or revealed. Existing large-type source/glyph bounds and
one-point focus stability checks must pass with the new viewport expectation.

## Measurement limitations and rejected attempts

- Early iOS fixture timing has no account library attached. It measures app CPU
  around 7.14 seconds for three swipes, but misses the physical hot path. Its
  proposed CPU budget is retired. Simulator XCTest did not emit frame or hitch
  metrics, so no zero-hitch or FPS claim is supported.
- Page-body diagnostics observe four page evaluations over three swipes, which
  contradicts a broad per-frame page reconstruction explanation in that fixture.
- The first five Android attempts used the Compose test clock with external
  gestures. The first gestures hit the reading hint; later gestures moved the
  content but produced insufficient hardware frame reports. These are rejected
  timing runs, not app-performance verdicts.
- The replacement Android test uses ActivityScenario and the normal runtime
  frame clock. The baseline records 101 frames, median 58.54 ms, p95 111.44 ms,
  47 at or over their reported deadline, no dropped reports and exactly one page
  request. This is a Debug emulator workload with long synthetic Arabic text,
  not physical Android or a release-performance acceptance result.
- The first account test used invalid content/page version fixtures and correctly
  failed admission before exercising writes. Valid cv1:/pg1: fixtures expose the
  actual write storm. An initial full-bleed selector used the wrong accessibility
  element type; the corrected query fails on the intended viewport geometry.

Raw logs, xcresults, traces and screenshots remain local under
`/tmp/hadithly-scroll-20261101`. Raw traces include local/device metadata and are
excluded from git. Portable selected results will be added after verification.

## Second repair: reuse unchanged decoded account data

The repeated main-thread partition reads in the physical stacks are reproduced
through the actual durable GuestDataStore. Fifty warmed reads of a partition
with 1,000 fixture note intents take 565.53 ms before the change. The executable
100 ms budget fails. With bounded decoded-data reuse the same loop takes
64.68 ms in the complete safety suite. Every read still creates a fresh database
context, validates the row/account and compares the full durable bytes before
reuse; this is not a stale revision-only or process-only cache.

The Foundation cache holds one account entry, admits at most 8 MiB of encoded
data, allows memory-pressure eviction and is cleared when the library scope is
unsubscribed. Value state is copied before mutation. A changed payload is decoded
again; malformed bytes still fail; a missing/deleted row returns nil. The warm
corruption test changes bytes without updating the row revision and proves the
read cannot return the old value. Cross-instance write, rollback, account and
erasure cases are included in the 160 passing tests. No schema, wire format,
backend behavior, migration or A2 row-mode change is involved.

Agent-driven scrolling now works on the physical phone through an explicitly
opted-in XCTest. It activates the installed loaded reader and injects only
vertical drags at 250 points/second. Destination-only xctestrun settings prevent
app reinstallation during repeated measurements. The first functional 50-second
driver passes, but separate xctrace attachment cannot resolve the app process
in these automated sessions. Two rejected attachment attempts and a one-second
lookup probe are retained locally; they produce no accepted frame result.

The replacement uses XCTest's own CPU, clock and scroll-signpost metrics. Three
measured iterations each contain six matching drags after a warm-up. Before the
second repair, scroll hitch ratios are 12.565, 12.570 and 6.284 ms/s, averaging
10.473 ms/s. CPU times average 5.774 seconds. The explicit acceptance budgets are
mean scroll hitch ratio at most 5 ms/s and mean CPU at most 6.35 seconds. The
replayable checker fails the baseline on the hitch budget. The device reports
zero frame-count and app-wide hitch fields alongside positive scroll-duration,
scroll-hitch and frame-rate signpost metrics; zero fields are excluded from proof.
No full-app FPS or universal zero-hitch claim follows from this run. See
[Apple's scroll metric](https://developer.apple.com/documentation/xctest/xctossignpostmetric/scrollinganddecelerationmetric)
and [hitch interpretation](https://developer.apple.com/documentation/xcode/understanding-hitches-in-your-app).

After local safety checks the second build is installed and matched to its
installed-app record. The existing `com.hadithly.app://continue` route reopens the
latest persisted position without a reset, fresh-install arguments or a human
navigation step. The same installed test runner measures the updated build.

The second repair's slow-drag repeat passes: scroll hitch ratios are 6.285, 0
and 0 ms/s, averaging 2.095 ms/s against the 5 ms/s budget. CPU averages 5.891
seconds against the 6.35-second non-regression budget. The measured scroll hitch
ratio is approximately 80% lower than the three-sample baseline. This comparison
uses the same test runner, installed-account reader, gesture coordinates and
velocity; it does not compare a manual full-trace ratio with a signpost ratio.
The faster-flick check at 750 points/second also passes the preset 5 ms/s hitch
budget: 10.599, 3.558 and 0 ms/s, averaging 4.719 ms/s. Its clock average is
16.688 seconds, compared with 12.152 seconds for slow drags. A first checker
invocation incorrectly reused the slow-run 6.35-second absolute CPU cap and
rejected the fast run's 6.379 seconds. That cap compares different workloads;
no fast CPU-regression claim is made. The fast acceptance check uses the preset
scroll hitch budget only, retaining the raw CPU values. No budget was raised.
These results describe the measured gestures, not a guarantee of zero hitches
across all reading content or release conditions.

## Final verification and scope

The second repair passes all 160 selected iOS account/storage, reading-position
and layout tests. This includes the first repair's four persistence cases and
the two new durable-read cases. The first repair also passed five distinct iOS
UI cases, including ar/ur/ru/bn large-type iterations, and eight Android native
instrumentation cases. Real semantic re-anchoring, source clearance, caption
bounds, focus stability, guest Saved return, translation growth and vertical
no-page-turn behavior retain their recorded evidence. Android is a no-change
parity check for the subsequent iOS-only decoded-state optimization.

The Android repeat records 132 frames, median 32.11 ms, p95 80.89 ms and 20 frames
at/over deadline. Hardware acceleration is enabled; emulator refresh is 60 Hz.
Setup and host/emulator variation preclude attributing those differences to a
performance repair. Both runs fetch exactly one page and report no dropped frame
callbacks. Physical Android and release-performance acceptance remain open.

The final iPhone repair bundle is installed and matched to its installed-app
record. The agent reopens the persisted passage and runs the same slow-drag
measurements, then a faster-flick acceptance check, without manual scrolling,
app resets, sign-in, generation controls or backend changes. Slow and fast scroll
hitch means pass the 5 ms/s target, and the matched slow CPU result passes its
non-regression budget. The owner had confirmed restored appearance after the
first repair; the second repair changes storage reuse only. That completes this
bounded goal. Page-transition/cache and priority-4 work remain separate goals.

Portable aggregates and synthetic captures are in `scrolling-verification/`.
Temporary page-body counters and abandoned simulator CPU drivers were removed.
Raw traces, recordings, owner app data, device identifiers, generated test-run
configuration and signing artifacts remain outside git. Incoming five iOS files
and the existing Python cache retain their initial bytes. Backend/API/provider,
quota, content and Convex-cost implementations did not change.

Retain every original-program gate and deferral in PLAN.md, including full
physical-device, language, accessibility, store and release acceptance. The
measurements here do not close those broader gates. Stop before page-transition
and cache work; do not start priority 4 automatically.
