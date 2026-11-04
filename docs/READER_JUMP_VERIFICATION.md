# Reader volume/page jump sheet verification

Session of November 4, 2026. Either revealed progress pill opens a sheet with
alarm-style Volume and Page
wheels and a Liquid Glass Go button that lands at the top of the chosen page.
The Page wheel repeats within the selected volume in both directions. Changing
the Volume wheel selects Page 1. Owner decisions are recorded in
[POST_GOAL_BACKLOG.md](POST_GOAL_BACKLOG.md). Sajda evidence is in
[PAGE_TRANSITION_BASELINE.md](PAGE_TRANSITION_BASELINE.md).

## Committed behavior

- iOS `ReaderJumpSheet` (ReaderSheets.swift), Android `ReaderJumpSheet` and
  `ReaderJumpWheel` (ReaderJumpSheet.kt). Both use existing localized keys for
  Close, Retry, Go, and the wheel headers.
- Both reader models use `knownPageCountForJump` (cache-only counts),
  `pageCountForJump` (on-demand resolution for one volume), `jumpToPage`
  routing through the existing `TurnTarget` pending machinery. Go on the open
  page keeps the current position. The pill and wheel use the same page number.
- Jump commits remove the landing page from recent positions and land at the
  top of the page (Android commits an explicit `ReaderVerticalLanding.Header`
  request; iOS uses its header landing path).
- The reader's window swipe is disabled while the iOS sheet is open.
  Android system Back closes the sheet before the reader.

## Verification run

The first polish round reserved space for loading and retry, and switched the
Go label to the palette's `onInteractive` color. It also added a compact close
button, a shared selection band, and a drag handle at a single sheet height.
The owner then chose to keep Page wrapping inside the selected volume.
The final layout uses one native two-component iOS picker, a 400-point detent,
and a compact close control with a 44-point hit area. Android uses a single
selection band with position-based scaling as rows approach its center.
The iOS rows use one font size throughout. The native wheel's perspective
changes continuously during scrolling. Selecting a row does not reload its
column or change its font size.

### Volume-local wheel checks

- Android `ReaderJumpTest` on `emulator-5554`: six passed. They cover opening and
  closing from the real progress pill, starting at the current page, wrapping
  Page in both directions, resetting Page on a Volume change, landing on the
  exact destination, and keeping position on same-page Go.
- Android `:app:testDebugUnitTest` passed after the wheel update.
- On the retained iPhone 18 Pro simulator, `Phase4Live` ran
  `ReaderR5UITests.testJumpPageWheelWrapsWithinSelectedVolume`. It opened the
  production sheet from the Page pill, dragged the Page wheel slowly with a
  1.5-second hold, then selected Volume 3 and verified Go landed on Page 1.
  The final run passed. The recorded drag frames show rows moving through
  the native center band without a release-time font change.

Captures and the final iOS result bundle are stored locally at
`/Users/alim/Developer/Artifacts/Hadithly/reader-jump-20261104`.

### Initial navigation and localization checks

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

## Open gates

- Physical-device review and the full VoiceOver and TalkBack reading journeys
  remain open.
- `ios/Hadithly/Localizable.xcstrings` in the working tree carries a large
  mixed diff (Xcode key respace plus older unrelated additions) that predates
  this session; it was excluded from every commit and needs an owner decision
  before it is committed or reverted.

## Device review script

1. Open any collection and tap the page to reveal the pills.
2. Tap either pill. The same sheet opens at the current
   location.
3. Flick the Page wheel past the last page, then backward past Page 1. Both
   wraps stay in the same volume.
4. Spin the Volume wheel to an uncached volume. Page returns to 1 and the Go
   button stays in place while the count resolves.
5. Tap Go. The reader lands at the top of the chosen page. Go on the open page
   dismisses the sheet and keeps the current position.
