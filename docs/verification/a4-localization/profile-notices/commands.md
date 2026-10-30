# Profile notice verification

Run from the repository root. These checks use controlled fixtures. They do not
save a profile or submit an authentication request. Copy approval remains pending.
The result summary is in `../profile-notices.json`.

```sh
python3 scripts/generate-ui-polish-copy.py --source docs/a4-profile-notice-copy.json --check
python3 scripts/stage-new-catalog-copy.py --source docs/a4-profile-notice-copy.json
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*copy*.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_catalog_staging.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_localization_audit.py'
PYTHONDONTWRITEBYTECODE=1 python3 scripts/localization_audit.py --allow-drafts --runtime-report docs/verification/a4-localization/runtime-candidates.json
```

The guarded catalog staging command adds `--stage` only during scoped staging.
It includes exactly five new entries. The earlier auth fallback stays unchanged.

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,id=D47D7363-4705-4767-8617-F47DDB6A3241' \
  -derivedDataPath /tmp/hadithly-la1-ios \
  -clonedSourcePackagesDirPath /Users/alim/Library/Developer/Xcode/DerivedData/Hadithly-betzezfbgwsvcjehkzzgdxiskzhx/SourcePackages \
  -disableAutomaticPackageResolution -parallel-testing-enabled NO \
  -collect-test-diagnostics never \
  -resultBundlePath /tmp/hadithly-profile-session-1031/profile-green-ios.xcresult \
  -only-testing:HadithlyTests/SettingsS1Tests/testProfileUsernameFailuresUseCodesAndBoundUnknownDetails \
  -only-testing:HadithlyUITests/VisualPolishUITests/testProfileNoticesUseSelectedLanguage \
  -only-testing:HadithlyUITests/VisualPolishUITests/testProfileNoticesRemainReadableAtLargeText test

JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
  python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.core.theme.NativeFinishingTest#profileNoticesUseSelectedLanguage \
  --class com.hadithly.app.core.theme.NativeFinishingTest#profileNoticesRemainReadableAtLargeText

(cd android && JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
  ./gradlew testDebugUnitTest --tests com.hadithly.app.SettingsS1Test.profileFailuresUseCodesAndBoundUnknownDetails)
```

Use a fresh result-bundle path for an iOS rerun. Android connected checks must keep
the explicit emulator guard. The physical-phone incident remains unresolved.
Before captures retain expected failed Arabic assertions from the extracted
production renderer before localization. The Android before fixture injects a
synthetic diagnostic directly into that renderer; the original production
assignment from Clerk's `errorMessage` was confirmed by source inspection.
