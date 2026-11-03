# Stable pending page turns

November 3, 2026. Unit 3 follows Unit 1 `8c544b7` and Unit 2 `fe0a74f`.
Unit 4 motion/layout and the full native matrix remain active.

## Result

Both apps keep committed volume, page content, page index and reading position
while an unavailable destination resolves. Pending intent has its own job and
identity, separate from ordinary forward prefetch. Success publishes destination
payload, actual returned ordinal and landing together. Failure retains the
outgoing text with retry/cancel; cancellation, supersession, explicit navigation,
account changes and reader exit fence late navigation. A new horizontal gesture
cancels the pending intent. iOS also checks the original identity/navigation
revision before a loaded strip animation can commit.

The quiet accessible cue is a single native rendering decision. It can be changed
to a destination loader without changing the fetching or landing model. Loaded
same-volume tracking keeps the existing native writer. Missing iOS strip slots
hold the outgoing page instead of animating a full skeleton. Android intercepts
the missing destination before its pager exposes a placeholder. Its pager starts
a new volume at the destination index, rather than rendering the new volume at
the previous volume's index until a later effect runs.

This closes the stable-pending behavior, not the surrounding motion program.
Cached cross-volume turns currently replace content when ready. Preparing the
actual cached destination for finger tracking remains Unit 4. No claim of complete
Sajda motion parity, zero flashes or universal smoothness follows from this unit.

## Source identity and lifecycle

Live requests use the actual returned page ordinal, including a source whose page
count shrinks. Incompatible trailing slots are removed. A live ordinal is never
substituted into an unrelated offline chunk. An already verified offline current
page can turn within its legacy namespace; an offline volume edge resolves first
and last entirely within that dump. Offline commits avoid mixing live slots or
starting live lookahead. Semantic entry fallback remains available.

A new native regression exposed an older background-prefetch path that could
append an ordinal offline chunk after a live fetch failed. Both clients now guard
that boundary. Initial offline opening and exact semantic targets remain intact.
Both pending commits invalidate older foreground page work. Android closed
models also release their last captured hadith references after saving progress.

Pending account changes now cancel an uncommitted volume turn. The former Unit 2
edge-replay test was updated for that contract. Ordinary explicit page-load replay
still has separate account-change regressions on both platforms. Public cache
bounds, one landing writer, the existing nearest-forward policy and all private
translation/allowance/generation boundaries remain in place.

## Native checks

Android's 25 cases cover pending success/failure/retry, cancellation, supersession,
explicit Contents priority, both volume edges, actual returned ordinals, ordinary
account replay, pending account cancellation, content reuse and the six retained
recent-position cases. Rendered fixtures use the real ReaderScreen and a gated
request. They prove readable outgoing text, a visible pending cue, successful
release and no late navigation after cancel. A real checksummed local base dump
proves provider 1 to 11 and back without live page fetches. Failed live prefetch
and pending turns cannot substitute that dump's ordinal. The fixtures use fake
transport, not a provider call or downloaded production artifact.

On iOS, focused model/store tests cover the matching intent and cache boundaries,
actual ordinals, account replay and verified offline namespace. Rendered checks
retain partial-header/reflow and recreated-page A-to-B-to-A behavior. A gated
ReaderView fixture proves waiting with readable text, release, and reversal with
no delayed landing. Initial shorthand swipes sometimes produced a canceled native
gesture before any turn intent; the final fixture waits for landing readiness and
uses explicit coordinates/velocity. This does not waive fast/short/diagonal input
from Unit 4's matrix. All final result counts and exact run scopes are in
[verification/page-transitions/unit3.json](verification/page-transitions/unit3.json).

Independent Terra review found the Android destination-at-old-pager-index race
and an iOS pending completion during a new gesture. Both were repaired. Root
review also repaired commit timing at a displaced strip, live/offline namespace
mixing, old prefetch completion and source-clamped ordinals.

## Physical recording and remaining motion evidence

The same iPhone sequence opens Bukhari 7 at volume 1's last page, then performs
slow next, fast previous, fast next and slow previous. Native screenshots confirm
7 to 8 to 7 to 8 to 7 across both volume boundaries. The pre-repair recording
shows full skeletons even on immediate warm volume returns. The repaired sampled
landing windows keep text visible and show the expected destination identity.

Original-frame analysis uses source presentation timestamps without interpolation.
A heuristic body classifier only locates frames for inspection; it is not FPS or
proof of no flash. The inspected repaired landing windows are 22.7-23.1,
25.6-25.95, 28.5-28.9 and 33.8-34.2 seconds. Two unusual body frames at
31.659-31.677 seconds remain a Unit 4 investigation, alongside the owner's report
of tiny jerks and previous-page frames. Earlier activity in that recording is
outside the controlled landing windows. Do not infer turn latency from unsynced
recording/device clocks. A separate fresh canonical-7184 process entry repeats the
original backward-loader path: slow previous to 7181, then fast return to 7184.
Outgoing text stays until 7181 is ready; the return uses the retained native strip.
QuickTime Maximum was selected, but the file remains H.264, not lossless. A single
unusual body frame at 17.156 seconds also remains an inspection item; changing the
capture option alone did not establish its cause.

The physical recording build predates only the final ordinary live-prefetch
fallback guard and DEBUG readiness label. Its exact binary hash and raw video
hashes are retained in the portable record. The accepted Unit 1 signed/source
archive and the earlier smooth-reader checkpoint remain unchanged. Raw artifacts
are in /Users/alim/Developer/Artifacts/Hadithly/paging-implementation-20261102.

## Preserved scope

No backend/schema/deployment/migration, provider/generation expansion, paid model,
publication or push occurred. Incoming project/scheme/catalog/Python bytes remain
unchanged. Accepted vertical scrolling, Convex reductions and every original
G01-G41, A1/A3/A4, A7/G38, E, native-language, physical/accessibility and release
gate keep their recorded scopes. Offline translation packs, opening latency,
sharing, functional pills and simulator cleanup remain separate work.
