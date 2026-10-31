# Repeat the bounded A5 checks

Run from the repository root. These commands use controlled synthetic pages and
explicit local targets. They do not establish live/authenticated/physical evidence.

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,id=D47D7363-4705-4767-8617-F47DDB6A3241' \
  -derivedDataPath /tmp/hadithly-la1-ios \
  -clonedSourcePackagesDirPath /Users/alim/Library/Developer/Xcode/DerivedData/Hadithly-betzezfbgwsvcjehkzzgdxiskzhx/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -collect-test-diagnostics never -resultBundlePath /tmp/hadithly-a5-new.xcresult \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoOwnsTargetWhilePrefetchIsInFlight \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoAtLargeTextInRTLAndLongLocales \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoThenCloseReturnsWithoutRetargeting \
  -only-testing:HadithlyUITests/ReaderR5UITests/testContentsGuidanceAndValidationLocalizeAtRuntime \
  -only-testing:HadithlyUITests/ReaderR6AUITests/testP1VerticalLandingMatrix \
  -only-testing:HadithlyUITests/ReaderR6AUITests/testSavedStateMiniMarkers \
  -only-testing:HadithlyUITests/ReaderR6Round3UITests/testSavedShortcutTabsRowsAndEdit \
  -only-testing:HadithlyTests/ReaderPagingTests \
  -only-testing:HadithlyTests/ReaderR5Tests \
  -only-testing:HadithlyTests/ReaderR4Tests \
  -only-testing:HadithlyTests/ReaderR6Round3Tests test

JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.features.reader.ContentsNavigationTest \
  --class com.hadithly.app.features.reader.ReaderR5SheetTest \
  --class com.hadithly.app.features.reader.ReaderR6AQuietTest \
  --class com.hadithly.app.features.reader.ReaderR6Round3Test \
  --class com.hadithly.app.core.theme.NativeFinishingTest#contentsGuidanceAndValidationLocalizeAtRuntime

# Run in android/:
# JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home ./gradlew testDebugUnitTest --tests com.hadithly.app.ReaderPagingTest --tests com.hadithly.app.ReaderR5Test --tests com.hadithly.app.ReaderR4Test --tests com.hadithly.app.ReaderR6Round3Test

PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_localization_audit.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/localization_audit.py --allow-drafts \
  --runtime-report /tmp/hadithly-a5-runtime-candidates.json
PYTHONDONTWRITEBYTECODE=1 python3 scripts/verify-a5-contents.py \
  --ios /tmp/hadithly-a5-new.xcresult \
  --android 'android/app/build/outputs/androidTest-results/connected/debug/TEST-hadithly(AVD) - 16-_app-.xml' \
  --output /tmp/hadithly-a5-new-preservation.json
```

Use fresh result-bundle paths. Android runs install/remove only on the explicitly
verified emulator; never replace the guarded runner with an unscoped connected run.
Read the raw native result scopes, including every failure and skip, before declaring
acceptance. The readback script records supplied results without disguising failures
as passes. Its baseline check also rejects unrelated tracked edits and staged incoming
project/catalog changes. New unrelated work requires its own explicit preservation
baseline instead of weakening this snapshot.

For the original iOS race, use a disposable checkout containing this unit's test
harness. Replace only ReaderModel.swift with its `6fdd302` version, then apply
`original-ios-loader-test-seam.patch`. Run the English Go test above. The patch adds
only synthetic page transport and navigation tracing; the old loading guard and
state-clearing path remain original. The test must fail because Contents dismisses
but no target fetch starts. Restore the repaired model before further checks.
The session performed this red readback and restored its candidate automatically.

Android's original controlled run failed with `requests=[page0, page1]`, expected
57, actual null. The current five-locale test additionally holds the target itself
open while releasing the old response, then checks the loading state, visible
header, unchanged body/source fields, single request and close callback.

Android captures are copied by the test to `/data/local/tmp/a5-go-LOCALE.png`, so
uninstall at the end of instrumentation cannot remove them. Pull only from the
selected emulator. Export iOS attachments with `xcrun xcresulttool export attachments`.
The keyboard can resize the iOS sheet; the test waits for a stable, hittable Go frame
before tapping. An existence-only check is insufficient for this presentation.
