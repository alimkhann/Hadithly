# A2 Android local-state migration and transaction proof

October 22, 2026, after `9e2eab9`. Android guest drafts, account queue/receipt/position state and deletion intents now share the existing Saved/outcome SQLite database. This removes a real cloned-store lost-write defect and makes future coherent Saved publication possible. Production Saved subscriptions and all four private observation consumers still use the legacy joined snapshot. A2 remains active.

The selected shape, alternatives and corrections are in [the account-store decision](product-program/sync-design/scale/account-store/decision.md). iOS already has a shared SwiftData container and receives a no-change parity check here.

## Reproduced defect and implementation

Two independently opened Android stores previously read and replaced the whole AtomicFile under separate per-instance mutexes. Both new clone probes accepted sixteen distinct operations but retained only one guest note or account command. The SQLite implementation retains all sixteen of each through the same public APIs and reopen.

Version 5 adds a guest-only row, exact-owner account rows, scoped deletion intents and staged import metadata to the existing journal database. It preserves installed v1-v4 journal/Saved tables. There is no all-owner hot-path compatibility snapshot. Current-row account/guest mutation, claim, ACK journal/account changes and the export clock share synchronous SQL transactions. All ordinary transactions require durable Ready. Network remains outside transactions.

Import captures exact original bytes plus canonical normalized data and hashes. It stages and verifies at most eight source records per transaction, then scans staged rows through indexed bounded pages. Source ordinal receipts account for duplicate-equal records. Conflicting owners, malformed keys, unknown source fields and corrupt UTF-8/data fail visibly with source preserved. Omitted random defaults are captured once. Final publication rechecks the legacy source, clears both source BLOBs and makes the database permanently authoritative. Stale files are ignored and cleaned after Ready.

Deletion stages an intent and erasing clock atomically, erases scoped account rows in bounded batches, removes retained Saved/outcome/artifact state and strictly cleans redundant legacy files before identity_pending. Unlink failure retains retry state. Live authority is checked again inside journal producer/active/export transactions, while historical old-owner evidence remains available to scoped export without its account row.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Original concurrent public-API probes | Red: sixteen accepted guest/account edits each retain one | `/tmp/hadithly-account-store-clones-red.log` |
| Same two clone probes after migration | Pass: all sixteen retained each | `/tmp/hadithly-account-store-clones-green.log` |
| Android existing store/facade suite with corrected fixtures | 104 pass | `/tmp/hadithly-account-store-android-second.log` |
| Android final store/facade suite | 114 pass, zero failures | `/tmp/hadithly-account-store-android-final.log`, connected JUnit XML |
| Android local unit suite | 212 pass, zero skipped/failed, 34 files | `/tmp/hadithly-account-store-android-unit.log`, unit JUnit XML |
| Installed Continue widget runtime fixture | One skipped; not verification | Same final run; empty/signed-out/installed-widget prerequisites required |
| iOS planner/presentation/Settings parity | 120 pass, zero failures | `/tmp/hadithly-account-store-ios-parity.log`, `/tmp/hadithly-account-store-ios-parity.xcresult` |

The final JUnit XML records 115 total tests, 114 passes, one skip. Gradle's progress counter prints a different terminal total; the actual per-case XML is authoritative.

New actual-disk cases exercise:

- Interrupted/reopened import across staging, verification and scan with nineteen owners and private Unicode. Missing client UUID defaults stay identical across every helper reopen. SQL abort at stage checkpoint rolls back all row/receipt changes. SQL abort at Ready preserves both source BLOBs and rejects guest/private authority until retry. Final Ready clears the retained bytes.
- Unknown/conflicting/ambiguous source rejection without an empty-store fallback; duplicate-equal account and deletion records with all five ordinal receipts; changed old source refusing final publication while exact captured originals remain retained.
- SQL abort between account claim write and guest clear preserving both sides, followed by exact-once retry. Duplicate-target note originals remain distinct; an invalid note becomes exact recovery. A restored file after claim cannot resurrect drafts. Racing two owners claims the single original once, and a later guest note remains unclaimed.
- Exact reopened account payload over 2.3 MB using BLOB windows. Guest and selected-owner edits succeed with a corrupt foreign payload that remains untouched. An actual query plan uses `local_accounts_scope`; guest-only edits leave an authenticated export fence valid while account-only edits invalidate it.
- Deletion intent/clock rollback and strict legacy unlink failure/retry, preserving unrelated guest and sibling account data. Late direct journal calls reject a missing account; retained artifact validation rejects a deletion intent inside its own transaction.
- Actual prior-v4 schema reconstruction preserving active and retiring Saved identities, frozen account frame, shared export fence and artifact metadata after production migration. Existing actual v1/v2/v3 fixtures still pass, including prepared rows and historical partitionless outcome/Saved evidence export/erasure.

Old test fixtures now corrupt/remove the actual account row or abort real SQLite account writes. They no longer modify an ignored post-migration JSON file or use AtomicFile directory permissions as a proxy. The ACK failure contract is deliberately stronger: journal ACK metadata and the account cursor both roll back; successful retry sets its timestamp once and a stale ACK cannot renew it. Wrong-owner settlement preserves its existing OwnerMismatch error precedence.

## Review and remaining gates

The independent implementation review found an artifact validation precheck/transaction race. The validator now checks current owner/deletion admission inside its own transaction, with an actual retained-artifact regression. The [final independent recheck](product-program/sync-design/scale/account-store/accepted-review.md) found no remaining concrete correctness finding in this local unit. It inspected the completed native artifacts; it did not independently relaunch them.

This is local persistence proof, not real installed app upgrade/rollback or hosted delivery proof. The large-payload test does not establish acceptable memory/latency at arbitrary size. Whole selected account/guest blobs, pending/positions and server export scale remain open. So do private observation/effective-view/production UI cutover, backend-first rollout, actual Clerk/Convex SDK and cross-device/physical-device matrices, recoverable iOS save failure and A2 deployment. Backend was unchanged and its prior 524-pass baseline was not rerun. No cloud, paid generation, production change or push occurred. A1 content and the full PRODUCT_PROGRAM remain open.
