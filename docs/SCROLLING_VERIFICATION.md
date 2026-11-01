# Reader scrolling and floating controls

Status: active; first repair improves physical scrolling but residual microjitters remain. November 1, 2026.

The owner started this goal after priority-2 verification. Scope is loaded-page
vertical scrolling and the owner-reported blank-header regression. Page turns,
cache changes, development Free/Pro controls and translation reliability remain
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
an FPS claim. Physical before/after timing and owner acceptance remain required.

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

## Current verification and remaining work

All local repair checks pass: 33 distinct iOS unit tests, five iOS UI cases
including the four-locale large-text iteration, and eight Android instrumentation
tests. Real semantic re-anchoring returns to the same scrolled fraction; source
clearance, glyph/capsule sizing, focus stability, guest Saved return, translation
text growth and vertical/no-page-turn behavior pass. The first production-view
geometry checks fail before the full-bleed repair on both apps.

The Android repeat records 132 frames, median 32.11 ms, p95 80.89 ms and 20 frames
at/over deadline. Hardware acceleration is enabled; emulator refresh is 60 Hz.
Manual setup and host/emulator variation preclude attributing these differences
to a performance repair. Both runs fetch exactly one page and report no dropped
frame callbacks. No Android 60 FPS or release acceptance is claimed.

Portable aggregate results and synthetic captures are in `scrolling-verification/`.
The iPhone repair bundle build, installation and installed-app readback pass.
Temporary page-body counters and abandoned simulator CPU/trace driver tests were
removed. Incoming five iOS files and the existing Python cache match the initial
hashes; backend files remain unchanged.

Checkpoint the verified first repair, then continue the same goal for residual
microjitters with agent-driven physical scrolling. Do not begin page caching or
priority 4. Preserve every original-program gate and deferral in PLAN.md.
