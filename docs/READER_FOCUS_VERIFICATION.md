# Reader focus, Settings, and orientation verification

November 4 and 5, 2026. Debug builds on the existing iPhone 18 Pro simulator
(iOS 27.0) and `emulator-5554` (Android 16). Both used English UI and local
reader fixtures. The iOS manual focus check used Paper, with Arabic at 26 and
translation at 16. Android used the Dark rotation fixture.

## Focus and Settings

- iOS `testProductionFocusRetainsThinProgressAndTextPosition` checks manual
  hide and reveal, the 4-point progress bar, and the Arabic text position.
  `testReaderChromeIdleAndSettingsDetent` checks the 8-second idle timeout,
  the Reduce Motion branch, and Settings push and pop at the compact and
  manually expanded heights. Before the fix, the idle assertion timed out
  after ten seconds. The iOS Reduce Motion check uses a fixture override.
  The iPhone replay shows intermediate fade frames over about 0.18 seconds.
- Android `ContentsNavigationTest.idleFocusAndSettingsKeepReaderPosition`
  checks manual and idle focus, timer reset, suspension while Settings is
  open, stable hadith bounds, both Settings heights, and a vertical swipe.
  The Android Settings sheet now starts at the partial detent.
- iOS `testLoadedReaderScrollsBehindFloatingControls` and
  `testPreparedEdgesBothDirectionsAndAbsoluteBoundaries` exercise scroll
  and cross-volume paging. The final iOS build also passed
  `testHorizontalDragTurnsPage`. Android paging tests cover horizontal motion
  and the zero-animation-scale path. The normal Android run used animator
  scale 1. The Reduce Motion run used scale 0. The emulator settings were
  restored afterward.

## Orientation

- iOS uses the reader's scene to observe actual interface rotation and
  changes the supported orientation mask for that scene. The normal app
  mask is portrait. The rotation test uses a scrolled, multi-hadith fixture
  and checks the corner timeout, landscape lock, menu unlock, retained
  hadith, and return to portrait when closing from landscape.
  [Apple scene geometry](https://developer.apple.com/documentation/uikit/uiwindowscene/effectivegeometry)
- Android `ReaderOrientationTest.readerRotationLockAndExitRetainHadith`
  checks portrait entry, landscape, the corner lock and its timeout,
  rotation attempts while locked, menu unlock, exit while locked, and
  normal app rotation. The reader stayed on hadith 58 and saved that
  anchor on exit.

Reader text uses copy actions. Text selection in a reader editor inherits
the sheet pause. Actual assistive-technology interaction, physical devices,
and iPad windowing remain open.
The localized orientation labels are drafts pending native-language review.
