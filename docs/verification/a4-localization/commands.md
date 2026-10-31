# Re-run the local A4 checks

Run these commands from the repository root. The native commands use controlled
fixtures and synthetic stores. They do not invoke real account or store actions.
Use a new result-bundle path for every iOS run.

## Check copy, resource structure, and the ledger

```sh
for A4_SOURCE in a4-offline-copy a4-runtime-notice-copy a4-runtime-edge-copy a4-final-wrapper-copy a4-authenticity-copy; do
	python3 scripts/generate-ui-polish-copy.py --source docs/$A4_SOURCE.json --check
done
for A4_SOURCE in a4-runtime-binding-copy a4-runtime-edge-reuse a4-final-wrapper-reuse; do
	python3 scripts/generate-ui-polish-copy.py --source docs/$A4_SOURCE.json --android-only --check
done
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p 'test_*copy*.py'
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_catalog_staging.py
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts -p test_localization_audit.py
PYTHONDONTWRITEBYTECODE=1 python3 scripts/localization_audit.py --allow-drafts --ledger --runtime-report docs/verification/a4-localization/runtime-candidates.json
PYTHONDONTWRITEBYTECODE=1 python3 scripts/a4-final-local-audit.py --native --output docs/verification/a4-localization/final-local-audit.json
```

The last command re-reads the recorded raw native artifacts. It fails if those
artifacts are unavailable. The report identifies the passing scopes inside a bundle
that also contains a rejected test. Source-only checks omit `--native` and do not
count as fresh native evidence. `generated_drafts` in the ledger counts catalog
`needs_review` units on iOS and English-identical resource units on Android. It is
not a count of approved translations. Every review status remains pending.

## Run the changed iOS presentations

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
	-destination 'platform=iOS Simulator,id=D47D7363-4705-4767-8617-F47DDB6A3241' \
	-derivedDataPath /tmp/hadithly-la1-ios \
	-clonedSourcePackagesDirPath /Users/alim/Library/Developer/Xcode/DerivedData/Hadithly-betzezfbgwsvcjehkzzgdxiskzhx/SourcePackages \
	-disableAutomaticPackageResolution -parallel-testing-enabled NO \
	-collect-test-diagnostics never \
	-resultBundlePath /tmp/hadithly-a4-new-run.xcresult \
	-only-testing:HadithlyUITests/VisualPolishUITests/testOfflineNoticesUseSelectedLanguage \
	-only-testing:HadithlyUITests/VisualPolishUITests/testOfflineNoticesRemainReadableAtLargeText \
	-only-testing:HadithlyUITests/VisualPolishUITests/testRuntimeNoticesUseSelectedLanguage \
	-only-testing:HadithlyUITests/VisualPolishUITests/testRuntimeNoticesRemainReadableAtLargeText \
	-only-testing:HadithlyUITests/VisualPolishUITests/testEdgeCopyUsesSelectedLanguage \
	-only-testing:HadithlyUITests/VisualPolishUITests/testEdgeCopyRemainsReadableAtLargeText \
	-only-testing:HadithlyUITests/VisualPolishUITests/testFinalWrappersUseSelectedLanguage \
	-only-testing:HadithlyUITests/VisualPolishUITests/testFinalWrappersRemainReadableAtLargeText \
	-only-testing:HadithlyUITests/VisualPolishUITests/testChromeUsesSelectedLanguage \
	-only-testing:HadithlyUITests/VisualPolishUITests/testAuthenticityCopyUsesSelectedLanguage \
	-only-testing:HadithlyUITests/VisualPolishUITests/testAuthenticityCopyRemainsReadableAtLargeText \
	-only-testing:HadithlyUITests/VisualPolishUITests/testChromeRemainsReadableAtLargeText \
	-only-testing:HadithlyTests/OfflineStoreTests \
	-only-testing:HadithlyTests/ReaderR5Tests \
	-only-testing:HadithlyTests/LocaleFallbackTests test
```

The focused boundary/unit run also selects `SettingsS1Tests/testOfflineNoticeBoundaryKeepsArgumentsAndBoundsDiagnostics`,
`SettingsS1Tests/testRuntimeNoticeBoundaryPreservesKnownGuidanceAndBoundsDetails`,
`LocalizationCatalogTests/testFormattedLabelsUseBaseLocaleFallbackAndPreserveSourceArguments`,
and `LocalizationCatalogTests/testCompiledCountCategoriesMatchScopedDraftsInEveryLocale`.

## Run the changed Android presentations

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
	python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
	--class com.hadithly.app.core.theme.NativeFinishingTest#offlineNoticesUseSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#offlineNoticesRemainReadableAtLargeText \
	--class com.hadithly.app.core.theme.NativeFinishingTest#runtimeNoticesUseSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#runtimeNoticesRemainReadableAtLargeText \
	--class com.hadithly.app.core.theme.NativeFinishingTest#runtimeNoticeBoundariesUseKnownCopyAndBoundDiagnostics \
	--class com.hadithly.app.core.theme.NativeFinishingTest#edgeCopyUsesSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#edgeCopyRemainsReadableAtLargeText \
	--class com.hadithly.app.core.theme.NativeFinishingTest#edgeMenusUseSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#edgeMenusRemainReadableAtLargeText \
	--class com.hadithly.app.core.theme.NativeFinishingTest#finalWrappersUseSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#finalWrappersRemainReadableAtLargeText \
	--class com.hadithly.app.core.theme.NativeFinishingTest#chromeUsesSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#chromeRemainsReadableAtLargeText \
	--class com.hadithly.app.core.theme.NativeFinishingTest#authenticityCopyUsesSelectedLanguage \
	--class com.hadithly.app.core.theme.NativeFinishingTest#authenticityCopyRemainsReadableAtLargeText
```

JVM checks select `com.hadithly.app.OfflineStoreTest`, `com.hadithly.app.ReaderR5Test`,
`com.hadithly.app.ReaderR6Round3Test`, and `com.hadithly.app.LocaleFallbackTest` through
`./gradlew testDebugUnitTest --tests ...` with the same JDK. These tests use synthetic data.

Keep the explicit emulator guard. The physical-phone incident remains unresolved.
The copy generators preserve equal-text XML rows and unrelated iOS catalog metadata.
The scoped staging helper stages declared new keys without including incoming catalog
formatting. `verify-a4-preservation.py` accepts the original `/tmp/hadithly-a4-finish-1031`
snapshot and all eight copy sources recorded in `final-preservation.json`.
