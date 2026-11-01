# Reproduce the reader checks

From the repository root. Select only the named simulator/emulator. Physical
runs require the current session's explicit device scope; fixture reset arguments
are never permitted on the owner's installed app.

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,id=D47D7363-4705-4767-8617-F47DDB6A3241' \
  -parallel-testing-enabled NO \
  -only-testing:HadithlyTests/GuestMergePlannerTests/testReaderScrollCoalescesAccountWritesAndFlushesExactFinalPosition \
  -only-testing:HadithlyTests/GuestMergePlannerTests/testReaderScrollFlushesDuringContinuousReadingAndStop \
  -only-testing:HadithlyTests/GuestMergePlannerTests/testPendingReaderScrollCannotFollowAnAccountSwitch \
  -only-testing:HadithlyTests/GuestMergePlannerTests/testGuestScrollFlushesWhenReaderStops \
  -only-testing:HadithlyTests/ReaderR4Tests \
  -only-testing:HadithlyTests/ReaderPagingTests \
  -only-testing:HadithlyTests/ReadingPositionTests \
  -only-testing:HadithlyUITests/ReaderR6AUITests/testLoadedReaderScrollsBehindFloatingControls \
  -only-testing:HadithlyUITests/ReaderR6AUITests/testLoadedReaderSemanticReanchorPreservesScrolledPosition \
  -only-testing:HadithlyUITests/ReaderR5UITests/testGoAtLargeTextInRTLAndLongLocales \
  -only-testing:HadithlyUITests/ReaderR5UITests/testTranslationSizeChangesActualReaderText \
  -only-testing:HadithlyUITests/ReaderPagingUITests/testVerticalScrollOnLongPageDoesNotTurnPage test

JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home \
python3 scripts/run-android-ui-tests.py --serial emulator-5554 \
  --class com.hadithly.app.features.reader.ContentsNavigationTest \
  --class com.hadithly.app.features.reader.ReaderScrollingPerformanceTest

python3 scripts/check-reader-scroll-metrics.py \
  --android-json docs/scrolling-verification/android-frames-after.json
```

Physical aggregates are extracted locally from xctrace XML exports:

```sh
python3 scripts/summarize-reader-time-profile.py EXPORTED_TIME_PROFILE.xml
python3 scripts/summarize-reader-hitches.py EXPORTED_HITCHES.xml --duration-seconds TRACE_DURATION
```

The duration comes from the actual trace TOC. Hitch summaries select the app
process and merge overlapping intervals. Their ratios are not display FPS.
Raw traces and exports remain outside git. See SCROLLING_VERIFICATION.md for
accepted/rejected loops, build identity and the owner-reported residual defect.

The second repair's repeatable checks use the physical metrics files:

```sh
# Expected failure: the pre-reuse build exceeds the scrolling hitch budget.
python3 scripts/check-reader-scroll-metrics.py \
  --ios-json docs/scrolling-verification/iphone-automated-before.json \
  --max-scroll-hitch-ms-per-second 5 --max-cpu-seconds 6.35

# Expected passes: matched slow-drag repeat and a separate faster-flick check.
python3 scripts/check-reader-scroll-metrics.py \
  --ios-json docs/scrolling-verification/iphone-automated-after.json \
  --max-scroll-hitch-ms-per-second 5 --max-cpu-seconds 6.35
python3 scripts/check-reader-scroll-metrics.py \
  --ios-json docs/scrolling-verification/iphone-automated-fast.json \
  --max-scroll-hitch-ms-per-second 5
```

Run `GuestMergePlannerTests` plus `ReadingPositionTests` and `ReaderR4Tests` for
the complete 160-case storage/ownership/layout check. The new standalone tests
are `testRepeatedUnchangedAccountPartitionReadsStayWithinScrollBudget` and
`testWarmPartitionReadChecksFreshBytesOwnerAndDeletion`.

For a fresh physical run, first build the `Phase4Live` scheme for the explicitly
approved iPhone with `build-for-testing`, using existing signing and no portal
updates. Install only its `HadithlyUITests-Runner.app` for repeated measurements.
Prepare a local copy of the generated xctestrun target with these settings from
the installed `xcodebuild.xctestrun` manual:

- `UseDestinationArtifacts = true`.
- `TestHostBundleIdentifier = com.hadithly.app.uitests.xctrunner`.
- `TestBundleDestinationRelativePath = PlugIns/HadithlyUITests.xctest`.
- `UITargetAppBundleIdentifier = com.hadithly.app`.
- Remove `TestHostPath`, `TestBundlePath`, `UITargetAppPath`, `DependentProductPaths`.
- Empty `UITargetAppCommandLineArguments` and `UITargetAppEnvironmentVariables`.
- Set the test-host `HADITHLY_PHYSICAL_SCROLL` environment value to `1`.
- Set `OnlyTestIdentifiers` to `ReaderR6AUITests/testPhysicalLoadedReaderScrollingPerformance`.
- For the faster case set test-host `HADITHLY_SCROLL_GESTURE = fast`; otherwise leave it unset.

Keep the app on the loaded persisted passage with generation off. Then:

```sh
python3 scripts/run-reader-device-scroll.py --device "$HADITHLY_PROFILE_DEVICE" \
  --xctestrun "$HADITHLY_SCROLL_TEST_CONFIG" --output "$HADITHLY_SCROLL_OUTPUT" \
  --allow-physical-scroll
```

The runner validates the destination-only configuration before touching the
phone, selects one named device and records three measurements after warm-up.
No test launches a fixture or resets the app. The physical XCTest skips unless
its explicit test-host opt-in exists. When an updated app must be reopened,
`devicectl device process launch --payload-url com.hadithly.app://continue`
uses the existing persisted Continue Reading route; do not reconstruct identity
from guessed page numbers. Keep generated configuration, logs and recordings
local. Do not apply the slow-drag absolute CPU budget to the longer fast-flick
workload without a matched fast baseline.
