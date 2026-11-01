# Priority-2 font size and Settings direction verification

November 1, 2026. The owner selected this goal before performance work. Both
reported defects retain their A5 repairs. Fresh checks reproduce neither defect,
so this session changes no product code or tests.

## Requirements and fresh results

| Requirement | Actual evidence | Result |
| --- | --- | --- |
| Translation size changes rendered reading text | Existing iOS `ReaderR5UITests.testTranslationSizeChangesActualReaderText` and Android `ReaderR6AQuietTest.translationSizeChangesActualReaderText` change the production HadithBlock preference from 14 to 22. Both assert increased text height and unchanged opaque body text. Reviewed iOS captures show the actual glyph growth. | Pass on both apps |
| Both settings entry points expose working size controls | iOS `ReaderSettingsUITests.testBothEntryPointsKeepSettingsAndNativeNavigation` covers reader and global settings. Android's two `ReaderPreferenceContentTest` cases cover those entry points, with global controls at fontScale 2. Both platforms select 18 and retain the selected translation locale through Back. These use controlled settings hosts. | Pass on both apps |
| Font geometry does not corrupt stored reading identity | Both projection checks change with translation size. Existing semantic-anchor checks retain the original position, preserve its semantic anchor and normalized offset, and reject its stale raw pixel offset. | Pass on both apps |
| Arabic to English returns to correctly oriented Settings | Existing root guest language tests exercise English, Arabic, Back, English, Back, and Settings. iOS compares returned row pixels with an English baseline in normal and flipped orientations. Reviewed captures show readable English and correct leading/trailing controls on both apps. | Pass on both apps |
| Direction survives reopening | iOS terminates and relaunches the process and repeats the row-image check. Android's instrumentation recreates MainActivity and retains English direction and the separate translation locale. A separate manual guest journey repeats Arabic-to-English, force-stops and relaunches the Android process, and verifies English Settings again. | Pass within these scopes |
| Preserve incoming work and existing gates | SHA-256 comparison against the pre-run snapshot covers native/backend/script sources, incoming files, cache files, and retained gate records. Only explicitly updated program documentation is exempted. Incoming index entries remain unchanged. | Recorded in results.json |
| Commit evidence and stop before performance | Scoped documentation/evidence commit, no push. No scrolling trace, paging optimization, entitlement override, or generation-reliability work is included. | Session boundary |

There are 19 passing automated cases: three iOS UI cases, two iOS unit cases,
four Android UI cases, and ten Android unit cases. All three invocations finish
successfully, with no failed or skipped cases. The Android position class contains
nine cases; its additional projection check contributes one. The full test names,
durations, source hashes, artifact hashes, and preservation result are retained in
[results.json](priority2-verification/results.json).

## Targets and artifacts

The iOS target is the existing isolated `Hadithly LA2 iPhone 18 Pro`, iOS 27.0,
`D47D7363-4705-4767-8617-F47DDB6A3241`. Android is the `hadithly` Android 16 AVD,
explicitly selected as `emulator-5554` through the guarded runner. Builds use the
current worktree at base commit `10c1083`, including the preserved incoming iOS
catalog/project/scheme bytes. No Xcode project regeneration was needed.

Raw evidence is in `/tmp/hadithly-priority2-20261101/`: `ios.xcresult`, exported
attachments and manifest, `ios-summary.json`, `ios-tests.json`, Android JUnit XML,
three invocation logs, the separate Android cold-process hierarchy/captures and
result, and `before.json`. Selected reviewed captures are copied
unchanged into [priority2-verification](priority2-verification/).

The Android cold-process check installs the current Debug APK after Gradle's
instrumentation teardown removes its installation, then completes onboarding as
a guest and repeats the actual language picker journey. An initial launch after
teardown found no installed activity. A startup hierarchy read returned null,
and an early helper could reuse an older dump; those observations are rejected.
The accepted helper removes its own old dump, requires a successful fresh dump,
then reads the hierarchy. The final Settings screenshot is inspected directly.
These observation failures are separate from the 19 passing automated cases.

The prior causal evidence remains in [A5_READER_CONTROLS.md](A5_READER_CONTROLS.md)
and [A5_REQUIREMENT_AUDIT.md](A5_REQUIREMENT_AUDIT.md). This is a fresh verification
of those repairs, not a second implementation or a new A5 completion claim.

## Repeat the automated checks

Run from the repository root, with an explicitly selected guest simulator and
the guarded Android emulator. Use a new result bundle path for each run. Native
device suites were run sequentially; the separate Android JVM checks do not
operate a native device.

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.features.reader.ReaderR6AQuietTest#translationSizeChangesActualReaderText \
  --class com.hadithly.app.features.settings.ReaderPreferenceContentTest#readerControlsPreserveSelectionsSizesAndLastVisibleLayer \
  --class com.hadithly.app.features.settings.ReaderPreferenceContentTest#globalControlsPreserveSelectionsSizesAndLastVisibleLayer \
  --class com.hadithly.app.features.settings.LanguageSwitchTest#liveLocaleSwitchUpdatesLabelsAndDirectionWithoutChangingTranslation

xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,id=D47D7363-4705-4767-8617-F47DDB6A3241' \
  -derivedDataPath /tmp/hadithly-la1-ios \
  -clonedSourcePackagesDirPath /Users/alim/Library/Developer/Xcode/DerivedData/Hadithly-betzezfbgwsvcjehkzzgdxiskzhx/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -resultBundlePath /tmp/hadithly-priority2-new-run.xcresult \
  -only-testing:HadithlyTests/ReaderR4Tests/testTranslationSizeInvalidatesLayoutProjection \
  -only-testing:HadithlyTests/ReadingPositionTests/testOldGeometryAndTranslationSizeUseSemanticAnchorWithoutRewritingPosition \
  -only-testing:HadithlyUITests/ReaderR5UITests/testTranslationSizeChangesActualReaderText \
  -only-testing:HadithlyUITests/ReaderSettingsUITests/testBothEntryPointsKeepSettingsAndNativeNavigation \
  -only-testing:HadithlyUITests/LanguageSwitchUITests/testLiveLanguageSwitchKeepsEnglishLTRAndArabicLabels test

cd android
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
./gradlew testDebugUnitTest \
  --tests com.hadithly.app.ReaderR4Test.translationSizeInvalidatesLayoutProjection \
  --tests com.hadithly.app.ReadingPositionTest
```

## Scope and retained gates

Text-growth checks exercise the real native renderer with synthetic English
content, not a provider generation. Control-host tests and semantic-anchor unit
checks are distinct evidence; they do not establish a live authenticated reader
session or every language/type combination. Root Settings tests run as guests.
Ordinary startup may read existing public development content.

No real account operation, paid-model request, cloud configuration, deployment,
migration, publication, external message, or push was invoked. Physical-device,
authenticated, native-speaker, full accessibility, content/provider, store and
release acceptance remain open. Preserve all G01-G41, A1/A3/A4 acceptance,
A7/G38's deferral and retired dates, E actual Linear, and the final program audit.
A2 remains wrapped with row mode off; A5 and B/C/D retain their local completion.
The verified Convex continuation is unchanged.

Stop after the scoped commit. The next proposed goal is priority-3 scrolling
measurement on each app, with physical iPhone action separately gated. It has
not started. Page-transition optimization and priority-4 free/pro testing and
translation reliability remain subsequent goals.
