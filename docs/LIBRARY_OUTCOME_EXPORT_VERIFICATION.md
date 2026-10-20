# A2 retained outcome export verification

October 20, 2026. Continues `eec9ba4`. Settings export now includes the retained
native outcome journal on both platforms. This advances one A2 component. It does
not enable manifest settlement, ACK, pruning, the public folder producer, hosted
sync, or app-level large-folder support. No cloud deployment, private account call,
paid generation, production migration or push was performed.

## Behavior and ownership

`LibrarySync.preparePortableExport` combines the existing server export and current
portable partition with `localOutcomeEvidence`. It preserves existing fields and
exact user note strings through structural JSON encoding. Provider passage and
capability fields are removed by key, without filtering words from user text.

Journal discovery covers every retained header for the captured Clerk subject and
deployment namespace, including older owner keys and headers without a partition.
Foreign subjects and deployments are excluded after authority cross-checks. Each
entry carries exact receipt authority, expected and collected category totals,
verification state, unavailable reason and at most 50 facts per read. A collected
prefix is never labelled complete merely because its local pages end.

One subject-plus-namespace clock covers all those owner keys. Header creation,
page/checkpoint writes, verification, scope setup, inventory backfill and erasure
advance it in the same native save or transaction. Every bounded read and final
private promotion checks its captured epoch/revision. An insertion before the
inventory cursor invalidates the entire staged export. No writer lease delays sync
or deletion. Empty reads do not recreate a clock for a deleted account.

SwiftData adds a unique scoped inventory and two-pass bounded backfill. Android
upgrades SQLite v1 to v2 additively with a subject/namespace/header index and clock
backfill. Existing member data is not rebuilt. Both actual old-store fixtures retain
owned facts and prove indexed inventory lookup. These runs use the installed iOS
27 simulator and Android 16 emulator, not a complete minimum-OS migration matrix.

Complete files are staged in registered private UUID directories. Cancellation,
mutation, account switch, erasure and detected missing facts discard the partial
file. Startup removes abandoned registered artifacts and managed orphan directories.
Settings removes iOS prepared files on disappearance or session change. Android
rechecks the captured fence and account throughout its bounded destination copy.

Android's CreateDocument returns a new document rather than overwriting an existing
one. This allows best-effort deletion of that new URI on failed export. See the
[Android storage documentation](https://developer.android.com/training/data-storage/shared/documents-files).
The cleanup tries DocumentsContract first and ContentResolver deletion second in a
non-cancellable finalizer. A debug-only, permission-protected DocumentsProvider
exercises real local URIs. Its registration is absent from the freshly processed
release manifest. This does not prove rollback for arbitrary external providers.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Actual iOS store/coordinator, presentation and Settings suites | 74 pass, zero failures | `/tmp/hadithly-outcome-export-ios-final.log`, `/tmp/hadithly-outcome-export-final.xcresult` |
| Actual Android store/coordinator instrumentation | 56 pass | `/tmp/hadithly-outcome-export-android-final.log` |
| Release manifest processing and provider exclusion | Pass | `/tmp/hadithly-outcome-export-release-manifest.log`, freshly generated `merged_manifest/release/processReleaseMainManifest/AndroidManifest.xml` |
| Generated native wire and local Convex API references | Pass | `python3 scripts/generate-library-sync-wire.py --check`, `node scripts/generate-convex-api-local.mjs --check` |
| Diff whitespace | Pass | `git diff --check` |

The original red tests called the previous portable export and demonstrated missing
retained member 50 on both hosts. Logs are `/tmp/hadithly-outcome-export-ios-red.log`
and `/tmp/hadithly-outcome-export-android-red.log`. The final tests parse the real
prepared JSON files and inspect exact facts, counts, ownership and user text.

Fixtures cover complete and partial/unavailable evidence, owned older-key orphans,
foreign exclusion, inserted-before-cursor and verification mutations, erasure,
startup cleanup, account switch and cancellation during preparation. Removing a
persisted fact after successful journal verification makes actual preparation fail
and leaves no staged artifact. Android additionally writes partial bytes to a real
local document URI, injects mutation, I/O failure, cancellation and account switch,
then verifies destination rollback and private-file cleanup. Another fixture rejects
a journal mutation after sealing and before destination copy. It also tests a
successful byte-for-byte copy in the original journal export fixture.

An initial SwiftData test accidentally reopened an upgraded store with a stale test
schema and removed the new clock table. The test contexts now share the canonical
current schema. The dedicated pre-upgrade fixture still creates the real older
schema before the app first opens it. This harness repair is separate from product
migration evidence. Existing SQLite teardown warnings do not prove power-loss
behavior.

Read-only architecture review found five defects before correction. The retained
Android copy fence, new-document rollback, iOS disappearance cleanup, missing-scope
clock coverage and old-store/index proof are now repaired. The final review found
no remaining actionable defect in this export slice. Reports are
`product-program/sync-design/scale/outcome-export-review.md` and
`product-program/sync-design/scale/outcome-export-final-review.md`. Its observed
73/55 run preceded the final 74/56 corruption and preparation-race expansion.

## Gates retained

- The current coordinator still stops at a complete/unavailable journal with no
  settlement, ACK or later send. Exact intent, Saved revision barriers, recovery,
  Undo-aware pruning and the public producer remain required before cutover.
- Existing server export JSON and current native partition/cache/pending blobs
  still accumulate in memory. Bounded journal streaming does not close full-export
  or whole-library scale. Legacy owner-partition export scope remains separate.
- Physical Settings/share/save/cancel journeys, iOS 17 and older Android installed
  upgrades, interrupted inventory backfill and power-loss recovery remain open.
- Arbitrary SAF providers can refuse rollback. Receiving apps can retain bytes
  after successful handoff. No external atomicity or revocation claim is made.
- Native SDK auth/deletion propagation, actual cross-device delivery, hosted limits,
  A2 deployment approval and every broader content/localization/store/release gate
  remain open. The full product program remains active.
