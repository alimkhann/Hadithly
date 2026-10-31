# Repeating the A5 checks

Run from the repository root. Native targets are explicit; none of these commands
performs a real account action. Use fresh result paths for Xcode. All fixtures
require Debug builds. The root language test checks guest navigation, not live
content quality or authenticated behavior. Startup may make ordinary feed loads with normal selection caching;
its results do not establish provider or cloud acceptance.

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.features.reader.ContentsNavigationTest \
  --class com.hadithly.app.features.reader.ReaderProgressObservationTest
```

Retained native reading and locale scopes:

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.features.reader.ReaderR5SheetTest \
  --class com.hadithly.app.features.reader.ReaderR6AQuietTest \
  --class com.hadithly.app.features.reader.ReaderR6Round3Test \
  --class com.hadithly.app.features.settings.LanguageSwitchTest
```

Saved/folder/state ownership scopes use isolated local stores and fake session
responses. “Switch” and “sign-out” in these case names do not invoke Clerk:

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.GuestMergeRaceTest#actualLibraryFacadePersistsOfflineIntentsAndRestoresProjectionAfterReopen \
  --class com.hadithly.app.GuestMergeRaceTest#actualLibraryFacadeKeepsAcceptedNoteUntilOwnedQueryRevisionCatchesUp \
  --class com.hadithly.app.GuestMergeRaceTest#actualLibraryFacadeRejectsLateAccountReadsAndUndoAfterSwitchAndSignOut \
  --class com.hadithly.app.GuestMergeRaceTest#actualFacadeRejectsOversizedNoteAndExplicitRemoveNeverAddsAnAbsentBookmark \
  --class com.hadithly.app.features.saved.SavedItemRowTest \
  --class com.hadithly.app.features.saved.SavedFilterBarTest \
  --class com.hadithly.app.features.settings.ReaderPreferenceContentTest
```

For iOS use these common arguments, followed by the selected test identifiers in
`results.json`. Do not select an entire suite containing `Live` account/service
tests. The existing `GuestMergePlannerTests` methods mirror the four isolated
Android facade methods above, with `test` prepended and the first letter uppercase.

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,id=D47D7363-4705-4767-8617-F47DDB6A3241' \
  -derivedDataPath /tmp/hadithly-la1-ios \
  -clonedSourcePackagesDirPath /Users/alim/Library/Developer/Xcode/DerivedData/Hadithly-betzezfbgwsvcjehkzzgdxiskzhx/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -resultBundlePath /tmp/hadithly-a5-repeat.xcresult \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoOwnsTargetWhilePrefetchIsInFlight \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoAtLargeTextInRTLAndLongLocales \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoThenCloseReturnsWithoutRetargeting \
  -only-testing:HadithlyUITests/ReaderR5UITests/testProgressControlsPreserveFifteenLocaleBindings \
  -only-testing:HadithlyUITests/ReaderR5UITests/testTranslationSizeChangesActualReaderText \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGuestSavingNoteUndoAndSavedReaderReturn \
  test
```

Unit and resource checks do not need an Android device:

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
android/gradlew -p android testDebugUnitTest \
  --tests 'com.hadithly.app.Reader*' \
  --tests com.hadithly.app.ReadingPositionTest \
  --tests com.hadithly.app.SavedUndoControllerTest
python3 scripts/localization_audit.py --allow-drafts
python3 -m unittest discover -s scripts -p test_localization_audit.py
```

`--allow-drafts` verifies structure; it does not approve copy. All incoming
resource/project bytes must still match `baseline.json` and remain unstaged.
Read native bundles/XML through the preservation tool, supplying each intended
artifact explicitly:

```sh
python3 scripts/verify-a5-program.py \
  --ios /tmp/hadithly-a5-repeat.xcresult \
  --android /tmp/hadithly-a5-repeat.xml \
  --output /tmp/hadithly-a5-readback.json
```

The tool records failures as well as passes. `results.json` classifies accepted,
rejected and superseded scopes; a mixed bundle is not a passing bundle. Inspect
the actual per-case outcomes and expected nonzero case count before accepting.
