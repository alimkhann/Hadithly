# Lossless outline storage verification

November 1, 2026. This unit reduces the database bytes read by
`collections.getOutline` while preserving its full public response. Evidence
covers the local comparison and development rollout. The owner approved
deployment of ed93a19 and conversion of seven cached outlines on November 1. Production is outside scope.

## Decision

Both native apps use the complete chapter outline for contents and reader jumps.
Returning fewer fields after reading the same document would retain its database
I/O. Splitting chapters into separate rows would require new APIs and loading
behavior on both apps. Lossless compression of the existing row is the smaller
change with a measurable benefit.

The stored row contains lightweight volume metadata and gzip-compressed Convex
JSON for the full volumes. The public query reconstructs the original shape,
including chapter IDs, Unicode, optional fields and special Float64 values.
`fflate` is pinned at 0.8.3. The query validates decoded length, CRC32, SHA-256
and metadata agreement. Chunked decoding bounds expansion work. Complete legacy
documents must fit Convex's document limit so rollback remains possible. When
compression would grow the complete row, storage keeps the legacy format.

Refresh replaces the same row and updates counts in the same mutation. Conversion
preserves `_id`, `_creationTime` and `indexedAt`; cache lifetime and freshness
policy stay intact. Existing count fallback reads volume metadata without
decoding chapters. No native API, provider, generation, quota, identity or rights
policy changes.

Convex supports binary `ArrayBuffer` values and accounts for documents and index
entries read. See the official [value types](https://docs.convex.dev/database/types)
and [limits](https://docs.convex.dev/production/state/limits). Returning the same
full payload means this change does not reduce client response bandwidth.

## Real local measurement

The isolated anonymous Convex 1.45.0 backend used a private snapshot of seven
existing public cached development outlines. No user records or provider calls
were used. Crons were disabled and cloud credentials were excluded. Each format
received one uncached public query followed by one cached query. Completion logs
confirmed those cache states. The verifier compared full response objects before
conversion, after conversion and after rollback, including system fields.

| Collection | Legacy cold DB bytes | Packed cold DB bytes |
| --- | ---: | ---: |
| ibn-majah | 6,432 | 2,524 |
| bukhari | 889,575 | 232,323 |
| muslim | 10,202 | 3,757 |
| tirmidhi | 10,326 | 2,853 |
| sunan-nasai | 8,630 | 3,317 |
| abu-dawood | 7,166 | 2,795 |
| mishkat-al-masabih | 4,339 | 1,936 |
| Total | 936,670 | 249,505 |

The total reduction is 73.36%; Bukhari alone falls 73.88%. Every warm query used
zero database read bytes. Bukhari's cold query execution increased from 34.8 ms
to 82.9 ms. These single local samples establish an I/O tradeoff, not a latency
distribution, live-service saving, invoice estimate or free-plan user capacity.

All seven conversion retries were idempotent and all seven rollback responses
matched exactly. Numeric usage and response digests are in
[outline-storage-local.json](verification/convex-cost/outline-storage-local.json).
Raw chapter data stays outside git. The final write-size guard was added after
this capture; it does not change measured reads and all seven source rows fit.

## Checks and review

All 557 backend tests across 45 files and `npm --prefix backend run typecheck`
pass. Ten storage tests cover payload fidelity, row identity, refresh/counts,
conversion/retry/rollback, metadata-heavy fallback, corruption, forged expansion,
CRC and complete-document limits. An oversized refresh leaves the original row
and counts intact. The real offline artifact builder emits identical immutable
bytes before and after conversion. Existing count-size coverage now measures
the public decoded outline, since JSON stringification does not size binary data.

Independent standards and requirements reviews identified bounded expansion,
CRC validation and whole-document size issues. Failing regression cases reproduced
all three before the fixes; both reviews then reported no remaining defect.
The verifier stopped its owned local process and removed temporary state.
The five incoming iOS catalog/project/scheme files remain unstaged and unchanged.

## Repeatable commands

Run from the repository root. Choose a new private snapshot path. The capture is
read-only, projects only public outline fields, rejects already-packed rows and
creates an exclusive file with mode 0600 outside the repository.

```sh
python3 scripts/capture-convex-outline-snapshot.py --deployment festive-cobra-664 --output /tmp/hadithly-outline-new-baseline.json
node scripts/verify-convex-outline-cost.mjs --snapshot /tmp/hadithly-outline-new-baseline.json --output docs/verification/convex-cost/outline-storage-local.json
npm --prefix backend test -- --maxWorkers=2
npm --prefix backend run typecheck
```

The verifier boots its own anonymous local backend, seeds only the snapshot,
measures both formats, checks retry and rollback, then cleans up. It refuses an
unrelated legacy anonymous deployment and records no raw response or log payload.

## Approved development rollout and rollback

The approved ed93a19 deployment succeeded on development `festive-cobra-664`
at approximately 09:19 UTC, 14:19 Asia/Almaty. Deployed function metadata confirms
`migrations.js:rewriteCollectionOutlineStorage` is internal. The private baseline
captured all seven original public documents and remains outside the repository.
The conversion completed at 09:20:47 UTC. Every full public response, identity and
freshness timestamp matched before and after. All seven retry calls returned
`already_packed`. Stored documents fell from 936,286 to 249,121 bytes, 73.39%.

Live completion logs contain exactly two public queries in each sequential
post-conversion window. The first query was uncached and the repeat was cached.
Cold database read bytes match the local packed results above, totaling 249,505;
all seven repeats used zero database bytes. Bukhari's live cold execution took
178 ms. Local before/after samples are the controlled latency comparison; this
single live sample has different runtime conditions. The rollout's one-time
conversion reads and writes are included separately in `outline-rollout-usage.json`.
There were fourteen mutation completions, seven document writes and no failures.
These are measured resource reductions, not invoice or free-capacity estimates.

Artifacts under `verification/convex-cost/` are `outline-live-baseline.json`,
`outline-deployed-function.json`, `outline-live-conversion.json`,
`outline-live-query-completions.json` and `outline-rollout-usage.json`.
They retain only public-payload digests and allowlisted metadata, not chapters,
user records, tokens or raw logs. The deployment verifier stops on any content
mismatch and keeps partial conversion progress reviewable. Production-target
rejection was verified locally before any CLI call.

The approved one-shot rollout is reproducible with a new private baseline and
new evidence paths. Run the baseline before converting any row; deployment
requires its own action-time approval when repeated:

```sh
node scripts/verify-convex-outline-deployment.mjs --mode baseline --deployment festive-cobra-664 --baseline /tmp/hadithly-private-outline-baseline.json --output /tmp/outline-baseline-metadata.json
# Deploy the approved code from backend with the existing development target verified.
node scripts/verify-convex-outline-deployment.mjs --mode convert --deployment festive-cobra-664 --baseline /tmp/hadithly-private-outline-baseline.json --output /tmp/outline-conversion-metadata.json
```

The internal mutation also accepts `format: "legacy"`. Restore rows using that
format before attempting an older schema deployment. Stop on a mismatch or
failed query; do not continue converting other collections until diagnosed.
No manual notification, paid generation or production action is included.

The owner separately approved ed93a19, the seven-record development conversion
and native verification. No manual notification, paid generation or production
action occurred. All G01-G41, A1/A3/A4 acceptance, A7/G38 deferral, E Linear and
final audit stay open. The original app and release program retains those gates.


## Native development readback

Android's guarded runner passed both `ConvexCostJourneyTest` methods on the
existing task-owned guest emulator-5554. The ten page moves produced the same
eleven page/volume positions as the prior fresh baseline. The second method
opened live contents, displayed volume 1, jumped to Hadith 57 and retained guest
state. Generation was disabled in both methods. This was an existing app
installation, so its aggregate action counts are not a fresh-install cost pair.

On the task-owned iOS 27 simulator 5EF04509-2CE0-4FBA-9341-F407EBDE8045, the
existing ten-page reading method passed in 117.6 seconds. The new live contents
method then passed in 43.3 seconds, displaying volume 1 and reaching Hadith 57.
Its first attempt failed because a direct Go tap occurred while the keyboard
was moving. Reusing the existing `tapSettledGo` test helper fixed the interaction;
no app source or backend change was needed. The initial failure remains recorded
and is not counted as a passing run. The final single-test xcresult summary is
Passed, one passed and zero failed. The original ten-page test already passed
and was not needlessly repeated.

Both iOS methods launch with automatic generation off and English UI. The local
app-store readback confirms 26/16 reading sizes. The simulator retains its prior
task-owned guest data; the harness's old literal "fresh simulator guest" is
corrected to existing guest in the saved evidence. Neither platform test resets
an account or changes physical devices. All five incoming iOS files remain
byte-identical and unstaged.

`outline-android-native.json` and `outline-ios-native.json` record the checks and
source hashes. `outline-android-usage.json`, `outline-ios-reader-usage.json` and
`outline-ios-contents-usage.json` capture their bounded development windows.
No generation function completed in the captured native windows. Direct provider
request counters are unavailable. The contents window includes ambient scheduled
traffic; these captures do not attribute the whole deployment's activity to one
reader or establish a bill reduction.

Repeat the native checks using the guarded Android runner and the task-owned
iOS simulator, with normal simulator signing:

```sh
JAVA_HOME=/Users/alim/Library/Java/JavaVirtualMachines/openjdk-21.0.1/Contents/Home python3 scripts/run-android-ui-tests.py --serial emulator-5554 --class com.hadithly.app.ConvexCostJourneyTest
xcodebuild -project ios/Hadithly.xcodeproj -scheme Phase4Live -destination 'platform=iOS Simulator,id=5EF04509-2CE0-4FBA-9341-F407EBDE8045' -only-testing:HadithlyUITests/ReaderR5UITests/testConvexCostColdLaunchLibraryAndTenPageMoves -only-testing:HadithlyUITests/ReaderR5UITests/testConvexCostContentsJumpWithGenerationOff -parallel-testing-enabled NO test
```
