# Reader settings UI verification

Date: 2026-10-15. Scope: the owner's five reader-settings screenshots.

## Result

Both reader settings entry points share native controls and the same section
order. Reading & type now follows the grouped settings layout. The reader sheet
starts at 480 points on iOS, expands for detail pages, and uses the large detent
for accessibility text sizes. Native back navigation and Done remain available.
Android keeps its header visible while each detail page starts at the top.

The controls preserve Arabic and translation visibility, all-hidden rejection,
four Arabic faces, live previews, the Arabic size ladder, translation sizes,
languages and reader themes. Reading direction and Saved removal confirmation
remain in Reading & type. Android translation sizing is now wired to its existing
preference setter. Choosing a reader theme enables the existing separate-reader
appearance preference so the selection takes effect while app appearance is linked.
App appearance can still disable the separate-reader preference.

The backend, preference schema and reader restoration logic are unchanged.

## Checks

- iOS simulator build passed. `ReaderPreferencesTests` and `ReaderR4Tests` passed
  20 tests. Both `ReaderSettingsUITests` passed through the actual Settings root
  and reader sheet. The rendering pass captured English, Arabic and Urdu in
  System, Light, Paper and Dark, plus scrolling at the largest iOS accessibility
  text category.
- Android debug build and all 202 debug unit tests passed. Three focused emulator
  tests passed, covering both shared entry points and the existing settings-sheet
  contract. The global control test uses 200% font scaling on the RTL emulator.
- Interaction checks change font and both sizes, select a language and Paper,
  return through native navigation, and verify the updated summaries. Visibility
  controls reject hiding the last layer. The Android tests check switch and radio
  selection semantics, plus visible header and back controls.
- Screenshots are local verification artifacts, outside git. The iOS result bundle
  is `/tmp/hadithly-reader-settings-final.xcresult`. Android screenshots are copied
  into the emulator's Pictures directory by the focused test.

## Repeat

From the repository root, with a booted iOS simulator:

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,id=<simulator UUID>' \
  -parallel-testing-enabled NO \
  -only-testing:HadithlyUITests/ReaderSettingsUITests \
  -only-testing:HadithlyTests/ReaderPreferencesTests \
  -only-testing:HadithlyTests/ReaderR4Tests test
```

This host reused the existing SourcePackages checkout through
`-clonedSourcePackagesDirPath` after a fresh checkout failed before compilation.
The test fixture is Debug-only and requires the existing automation guard.

With the `hadithly` Android emulator booted and JDK 21 selected:

```sh
cd android
./gradlew assembleDebug testDebugUnitTest
./gradlew connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.hadithly.app.features.settings.ReaderPreferenceContentTest,com.hadithly.app.features.reader.ReaderR6Round3Test#settingsSheetRenamedWithNoQuranModes
```

## Limits and remaining gates

This verifies local native controls and preferences. It does not close physical
VoiceOver/TalkBack, device, signed-in sync or release gates. The locale screenshots
check rendering and theme contrast; translation completeness and full RTL QA remain
in L1. The broader older
Android reader suite is not a clean gate here: its Saved/search English-string
assertions failed on the Arabic emulator. The focused settings tests above are
rerun independently.

All prior gates remain in [OPEN_GATES.md](OPEN_GATES.md). Stop before L1.


## Language flags and Paper preview follow-up

The owner spotted that the displayed Paper selection still had a dark background.
The screenshot fixture supplied the app palette instead of the reader palette.
It now supplies the effective reader theme, palette, color scheme and presentation
background, matching the existing `ReaderView.readerSheet` wrapper. The production
reader wrapper already supplied these values. The global Settings tab retains its
own app appearance when a separate reader appearance is selected.

`testSelectingPaperChangesRenderedSheetBackground` reproduced the old screenshot:
the sampled background red channel was 13/255 with Paper selected. The regression
now checks a warm, light rendered background rather than only the checkmark.
Android's reader control tests also check the rendered Paper pixels.

Language choices now show the existing iOS flag mapping in both reader settings
entry points. Android uses the same mapping in reader, App language and Hadith
translation choices. Names and locale identifiers remain unchanged; the added
flags are decorative to screen readers.

Follow-up evidence: `/tmp/hadithly-paper-red.xcresult` records the failing color
check; `/tmp/hadithly-flags-paper-green.xcresult` records the corrected preview and
both entry-point journeys. Android debug build, 202 unit tests and three focused
emulator tests pass, including 200% text scaling and native radio semantics.
The prior device, localization, signed-in sync and release gates remain open.
