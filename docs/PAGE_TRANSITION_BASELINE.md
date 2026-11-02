# Page and volume transition baseline

November 2, 2026. This is discovery evidence, not a completed repair. Production
source stayed at `cffd6dc`; the installed optimized development app was activated
without reinstallation or data reset. A separate gesture-test runner was built
outside the checkout and installed after the owner's phone-use authorization.
The owner approved iOS's UI Automation prompt directly on the phone.

## Capture and workload

The physical iPhone 16 Pro runs iOS 27.0.1. QuickTime captured its native screen
at 1206 × 2622. The same standalone XCTest runner sent this sequence to both
installed apps, with screenshots after two seconds of rest between cases:

1. Rightward drag at 120 points per second.
2. Leftward drag at 1400 points per second.
3. Rightward drag at 1400 points per second.
4. Leftward drag at 120 points per second.
5. Upward vertical drag.
6. Rightward drag at 1400 points per second.
7. Leftward drag at 1400 points per second.

Horizontal drags cover normalized x 0.18–0.82 at y 0.5. Direction has different
meaning in the two apps. Sajda advances rightward; Hadithly's English Automatic
setting advances leftward. This comparison matches physical input and inspects
logical outcomes, rather than treating page-number direction as a defect.

Sajda starts at Quran page 261, Ibrahim 14:43, Russian translation, dark theme.
Page 262 starts Al-Hijr and Juz 14. Hadithly starts at Bukhari page 26, volume
97, hadith 7184, English translation, Arabic 40 pt and translation 22 pt,
system dark theme. Automatic translation was visibly off before the workload.
This is not an equal-content performance benchmark.

| Capture | Decoded frames | Observed average | Median interval | Maximum interval |
| --- | ---: | ---: | ---: | ---: |
| Sajda controlled | 2,781 | 56.46 fps | 16.667 ms | 66.684 ms |
| Hadithly controlled | 2,775 | 53.32 fps | 16.667 ms | 83.350 ms |

These are recording cadences, not app frame rates, display refresh rates, or
gesture latency. Native source presentation timestamps select original frames;
no interpolation or upsampling is used. Missing capture intervals limit claims
about small movements between frames. The earlier Device Hub mouse-drag probe
contains canceled turns and is retained as exploratory evidence, not the matched
controlled workload. The first XCTest configuration failed before execution;
the next attempt reached an iOS approval timeout. Both approved sequences pass.

## Observed differences

| Case | Sajda | Hadithly |
| --- | --- | --- |
| Slow committed turn | Rendered outgoing and incoming pages move side by side. Page and Juz pills keep the outgoing identity during sampled motion and update after landing. | First previous-page turn exposes a skeleton beside the outgoing page, then a full loading page. |
| Warm revisit | Rendered neighbor remains available in sampled frames. | Rendered neighbor is available during the sampled warm transition; no sampled loader. |
| Scroll A, turn to B, return to A | Restores the scrolled Ibrahim 14:45–47 position. | Preview initially shows the earlier scrolled position, then resets to the header after horizontal landing. |

The Hadithly reposition is directly visible in `hadithly-controlled.mov` at
44.265–44.432 seconds, followed by header content by 44.624 seconds. The sampled
first-turn loader is full screen by 21.612 seconds and still visible at 22.654;
7181 is visible at 22.970. Those samples bound observations, not exact loading
duration. No claim is made about unseen intervening frames.

Sajda's immediate neighbor restoration is confirmed. Its behavior after moving
farther away, closing the reader or restarting is not established. The sampled
Sajda turns cross a Juz boundary, not proof of Hadithly cross-volume behavior.

The page pill opens a bottom sheet with Juz and Page wheels, Apply and Close.
The sheet was closed without applying a different selection. Other pill actions
and screenshot-sharing behavior remain later work.

## Source explanation and boundaries

Hadithly's iOS `ReaderView.pageStrip` retains a rendered neighbor view. At commit,
`ReaderModel.pageIndex.didSet` requests header landing; the active native writer
then applies that request. This matches the observed old-position preview followed
by a new header position. The new owner decision replaces header landing for
recently visited pages, while preserving one landing owner and explicit semantic
restoration for Continue and Saved.

iOS `ReaderModel.warmAdjacentVolumes` and Android `ReaderPrefetch.warmAdjacentVolumes`
discard returned payloads. They warm server data rather than retain reusable
client content. Ordinary forward-loaded pages already remain in the page array.
The backward target following the resumed entry was not loaded in this workload.

Both native `OfflineStore.offlinePage` paths can reconstruct Arabic and embedded
provider English from an active base dump. Their legacy page identities must not
be substituted for live pages by ordinal alone. Both `translation` lookups return
nil/null because version 1 packs lack entry rights and revocation identity.
`backend/convex/offlineDumps.ts` suppresses pack manifests. This session did not
verify an installed collection, exercise disconnected reading, or enable packs.

## Local evidence

Raw media, screenshots, test results, logs and the standalone driver remain at
`/Users/alim/Developer/Artifacts/Hadithly/page-transitions-20261102`. They are local
artifacts, not uploaded or committed. Relevant files are:

- `sajda-controlled.mov` and `hadithly-controlled.mov`.
- `sajda-controlled-analysis/manifest.json` and `hadithly-controlled-analysis/manifest.json`.
- Their timestamp-labeled contact sheets and selected full-resolution frames.
- `hadithly-first-loading-detail/burst-1-contact.png`.
- `gesture-probe/sajda-sequence-approved.xcresult` and `gesture-probe/hadithly-sequence.xcresult`.
- `gesture-probe/Tests/GestureProbe.swift`, `gesture-probe/prepare.py` and `gesture-probe/project.yml`.
- `analyze_sajda.py` in the artifact root.

The portable metadata is in
[verification/page-transitions/baseline.json](verification/page-transitions/baseline.json).
It contains source hashes and timestamps without device/account identifiers.

Reversed continuous drags, rapid repeated input, both Hadithly volume edges,
RTL, verified offline data, translation growth, accessibility and Android runtime
remain required cases in the [plan](PAGE_TRANSITION_PLAN.md). The present captures
do not pass that full matrix or any original release/acceptance gate.

The planning closeout verifies both native-video hashes against the portable
record, frame-count/timestamp metadata against the analysis manifests, document
links, and byte preservation of incoming iOS files and Python caches. Independent
source/requirements review caught the older manual-header backlog rule; its
current bullet now reflects the owner's recent-page decision. No product test
suite was rerun for these documentation-only changes.
