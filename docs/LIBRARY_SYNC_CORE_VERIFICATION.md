# Library sync core, local verification

October 18, 2026. Baseline A2 engineering checkpoint at `a21300c`. The complete A2
gate remains open. The receipt lifetime, table and API details below describe that
baseline; `LIBRARY_SYNC_PROTOCOL_VERIFICATION.md` records their subsequent replacement.
The production sign-in callers still use `guestMerge:mergeGuestData` followed by
`clearAll`. Signed-in writes and subscriptions have not migrated to this core.
This document must not be read as proof that the reported sign-in race is fixed
in the running product.

## Reproduction and chosen ownership

Both real native stores reproduced the existing cleanup race: a note edit and
newer reading position made after the sent snapshot were removed by unconditional
cleanup. The Android positive control confirmed both existed before cleanup.
These were local store diagnostics, not authenticated sign-in tests. Original
evidence is in `/tmp/hadithly-guest-merge-race-red-ios.xcresult`, its `.log`,
`/tmp/hadithly-guest-merge-race-red-android.log` and
`/tmp/hadithly-guest-merge-race-control-android.log`.

The source traces, two structural alternatives, independent comparison and chosen
ownership are in `product-program/sync-design/`. One native coordinator owns
durable account partitions, immutable in-flight batches and exact receipts. A
claim moves the guest records and their original private values into an account
partition in the same storage commit. New guest writes enter the next claim.
Only the exact operation ID and revision may settle a submitted change. Conflicts,
missing targets and transformed positions retain their original local values for
owner-scoped recovery. A partial folder restore records restored, superseded and
missing memberships separately.

The server obtains the owner from the verified JWT. A short-lived opaque binding
must match that owner before any operation. The client compares the returned
verified subject with its captured session before claiming guest data. A local
write context captures owner, session and generation before asynchronous work;
a stale context is rejected after account change. Enqueue requires an existing
partition and cannot recreate an erased one. Late receipts can settle only their
captured owner's still-existing partition.

The installed Swift Clerk/Convex integration fetches and refreshes tokens from the
current Clerk session. Its authenticated value is the raw token, not an account
identity. This is source evidence for an explicit binding guard, not proof that an
actual queued request was attributed to another account. No real auth tokens or
private reader data were collected for these tests.

## Implemented local components

- `librarySync:openBinding` and `librarySync:applyBatch` validate JWT ownership,
  batch bounds and operation clocks. Identical retries return recorded receipts;
  reused IDs with changed intent fail. A retry of an old add cannot reapply it
  after a later remove. Existing write handlers stamp conflict clocks, and
  bookmark/favorite target lookups now use owner-plus-hadith indexes.
- Shared folder-name policy retains the existing 64 Unicode code-point, NFC,
  whitespace and control-character rules. Native wire values and limits derive
  from the actual Convex validators through
  `scripts/generate-library-sync-wire.py`, rather than a second handwritten API.
- SwiftData claims and Android atomic-file claims retain all six guest record
  types and their original metadata. A frozen batch survives reopening the real
  store. Bookkeeping saves do not trigger another guest-change drain.
- Android damaged JSON now raises a fixed storage failure. Guest Saved read/write
  boundaries preserve cancellation and enter the existing load-error state. The
  sign-in snapshot boundary returns before merge/cleanup on a storage-read failure.
  No damaged file is replaced with an empty store.
- Account erasure covers the six new server tables in the local fixture; export
  includes batch receipts and excludes binding capabilities. Large-account server
  erasure and native pending/recovery export are still pending.

## Executed verification

| Boundary | Result | Evidence |
| --- | --- | --- |
| Backend strict typecheck | Pass | `/tmp/hadithly-sync-core-final-typecheck.log` |
| Complete backend suite | 378 tests, 34 files, all pass | `/tmp/hadithly-sync-core-final-backend.log` |
| Native wire generation consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| iOS GuestMergePlannerTests | 19 pass, including 6 new core cases | `/tmp/hadithly-sync-context-ios.xcresult`, `.log` |
| Android GuestMergeRaceTest | 8 pass on emulator | `/tmp/hadithly-sync-store-final-android.log` |

Backend fixtures execute the actual Convex mutations and queries locally. They
prove wrong-owner rejection without effects, expiry/erasure, stable lost-response
retry, changed-batch rejection, mixed independent receipts, newer cloud notes and
placements, actual-target legacy position resolution, undo after a newer note,
stale folder deletion and partial folder restore. Policy tests include byte/work
bounds, exact receipt sets and nested clocks that cannot bypass the future limit.

Both native suites run the coordinator with a controlled transport and their real
stores. They prove new guest edits during a send are delivered in the next batch,
reopening preserves the exact frozen batch, wrong-owner/incomplete receipts cannot
clear it, losing notes and partial folder restores retain original intent,
verified-subject mismatch leaves guest data unclaimed, and captured writes cannot
follow account switches or recreate erased partitions. Android also proves older
JSON migration and corrupt-file retention through the existing Saved read/write
error boundary. These controlled transports do not prove Clerk or network delivery.

Re-run the backend suite from `backend/` with `npm run typecheck` and `npm test`.
Run the wire generator from the root. On the configured native toolchains:

```sh
xcodebuild -project ios/Hadithly.xcodeproj -scheme LA2Verification \
  -destination 'platform=iOS Simulator,name=Hadithly LA2 iPhone18Pro' \
  -parallel-testing-enabled NO \
  -only-testing:HadithlyTests/GuestMergePlannerTests test

android/gradlew -p android :app:connectedDebugAndroidTest \
  -Pandroid.testInstrumentationRunnerArguments.class=com.hadithly.app.GuestMergeRaceTest
```

The executed iOS run used simulator UUID
`D47D7363-4705-4767-8617-F47DDB6A3241`, derived data
`/tmp/hadithly-la1-ios` and the existing resolved package checkout. Android used
JDK 21. No Xcode project regeneration was performed for this unit.

## Review and remaining gates

Requested independent reviewer: gpt-6-sol. The initial review identified two P1s:
stale folder deletion and overstated folder restore acceptance. Both were repaired
and tested. The source-review addenda found no new blocker within this bounded
core. The complete report is `product-program/sync-design/core-review.md`.

Before this can replace production paths:

- Implement safe receipt compaction and reconciliation after older backup restore.
  The current 10,000-batch lifetime cap is provisional and unsuitable for routine
  reading-position writes. Per-installation sequence fields alone prove nothing.
- Migrate both real sign-in callers, remove unconditional cleanup from completion,
  and route every signed-in facet, folder, undo and position write through durable
  delivery. Add owner-tagged Saved/position responses and subscription epoch checks.
- Complete invalid legacy draft admission/recovery, large-folder continuation,
  vanished-anchor resolution, native pending/recovery export and erasure, and
  bounded large-account server deletion. Current folder batches stop at 500
  memberships and explicitly report an unresolved larger folder.
- Prove transport interruption/restart and permanent failures through integrated
  callers, plus cancellation at Android's suspended storage commit. The post-claim
  session check does not replace that cancellation test. Broaden actual storage
  failure and installed-schema migration evidence on both platforms.
- Obtain action-time approval for A2 development deployment and private test-account
  writes after concrete local integration is reviewable, then prove iOS-to-Android
  and Android-to-iOS delivery, sign-out and account changes with real auth.

No new A2 cloud deployment, account creation, private cloud write, paid generation,
permission change or production action was performed. The prior approval covered
A1 first-reading development only. A1's eleven missing locales, maintenance and
ordinary-reader quality issue remain open, alongside the rest of the full program.
