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
