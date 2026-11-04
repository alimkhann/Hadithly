# Reader volume/page jump sheet verification

Session of November 4, 2026. Feature request: the revealed progress pills
become buttons; either pill opens one sheet with alarm-style Volume and Page
wheels, a cross-updating preview, and a Liquid Glass Go button that lands at
the top of the chosen page. Owner decisions recorded in
[POST_GOAL_BACKLOG.md](POST_GOAL_BACKLOG.md); Sajda evidence in
[PAGE_TRANSITION_BASELINE.md](PAGE_TRANSITION_BASELINE.md).

## Committed behavior

- iOS `ReaderJumpSheet` (ReaderSheets.swift), Android `ReaderJumpSheet` and
  `ReaderJumpWheel` (ReaderJumpSheet.kt). Both localize every string
  ("Close", "Retry", "Go", the wheel headers use the existing keys; no new
  untranslated copy enters either catalog).
- Reader model, both platforms: `knownPageCountForJump` (cache-only counts),
  `pageCountForJump` (on-demand resolution for one volume), `jumpToPage`
  routing through the existing `TurnTarget` pending machinery. Same-page
  destinations are ignored; volume-relative page numbering means pill labels
  and wheel rows agree without renumbering books.
- Jump commits remove the landing page from recent positions and land at the
  top of the page (Android commits an explicit `ReaderVerticalLanding.Header`
  request; iOS uses its header landing path).
- Windows swipe is disabled while the sheet is open (iOS);
  Android system Back closes the sheet before the reader.

## Verification run

Follow-up polish round (same session, owner screenshots): loader and retry
got a reserved fixed slot so the Go button never shifts; Go text uses the
paired `onInteractive` token (fixes white-on-white in the dark palette); the
close control shrank with tighter top spacing; a single unified grey
selection pill now sits behind both wheels (Sajda style); a grey drag handle
was added and the sheet is one fixed-height detent so it no longer expands
upward; and the Page wheel became a true looping wheel — an edge step past
the volume's last page advances the Volume wheel to that volume's first page
(and back on the way up), implemented as a virtual infinite row space on
Android and a `UIPickerView`-backed loop on iOS with the marker rows removed.

- Android `:app:compileDebugKotlin`, `:app:testDebugUnitTest`: clean.
- Android `ReaderJumpTest` on emulator-5554 (instrumented, 3 cases):
  1. `jumpToVolumePageLandsAndClearsPendingTurn` — Go inside the volume lands
     page 2 and clears the pending turn.
  2. `jumpAcrossVolumesFetchesCountAndLandsFirstPage` — Go into the next
     volume resolves its count on demand and lands page 1 with the volume
     header landing.
  3. `jumpToCurrentPageKeepsPositionWithoutTurn` — Go on the open page keeps
     position with no turn at all.
  Result: 3 passed, 0 failed, re-run after the polish round. The first two
  runs surfaced a fixture bug in the
  test itself (`cv:`-prefixed content versions and non-`pg1:` page keys are
  rejected by `ReadingPosition` schema validation, so the landed page could not record progress); the app model was
  unchanged by that fix.
- iOS `xcodebuild build` for the Hadithly scheme on the reused iPhone 18 Pro
  simulator: succeeded.
- iOS `HadithlyTests` on the same reused simulator: 442 executed, 9 skipped,
  0 failures (includes the corner-title tests added with this session's
  localization commit).

## Wait: recorded open gates

- The on-screen wheel interaction (flick, cross-volume snap, Liquid Glass Go,
  VoiceOver/TalkBack labels) is not yet machine-asserted. iOS simulator and
  Android emulator manual passes with the recorded script below; then a
  physical-device check per the existing reader motion gates.
- UI test additions for the sheet are tracked in backlog if the manual passes
  surface states worth pinning.
- `ios/Hadithly/Localizable.xcstrings` in the working tree carries a large
  mixed diff (Xcode key respace plus older unrelated additions) that predates
  this session; it was excluded from every commit and needs an owner decision
  before it is committed or reverted.

## Manual script for the pending device/simulator passes

1. Open any collection, scroll to reveal the pills.
2. Tap the Page pill or the Volume pill — the same sheet opens at the current
   location.
3. Flick the Page wheel past the volume's last page: the Volume wheel advances
   and Page shows 1; flick back from Page 1: previous volume's last page. The
   wheel keeps cycling — it never stops at an edge.
4. Spin the Volume wheel to a heavy volume: counts auto-advance to its first
   page.
5. Tap Go: reader lands at the top of the chosen page; Go on the currently
   open page just dismisses.
