# Native Saved store final read-only review

2026-10-21. Parent remains sole implementer. Reviewed final native Saved raw journal, append/replay, bounded fold, page-chain verification, prepared projection, lifecycle/export and additive schema changes. No repository edits, external calls or delegates.

## Result

The concrete Android projection scan finding is resolved. No remaining concrete replay, count, cross-owner data-loss, mutation-clock, erasure, export or schema-migration defect was found within this component's stated scope. This is approval of the durable prepared-store component, not production Saved activation or end-to-end sync readiness.

Android now defines `saved_projection_collection(collection_key,row_key)`, uses both closed collection-prefix bounds, and rejects foreign continuation cursors. Swift also rejects foreign projection cursors. I executed an isolated SQLite schema/query reproduction using10,000 foreign rows and9 target rows: EXPLAIN selects the compound index and constrained collection+lower+upper search; first8 rows required122 VM steps, last1 required28, and an empty target required18. The former query needed40,030 steps for just1 target. Local evidence confirms bounded scope rather than relying solely on returned LIMIT.

The earlier iOS failure is now explained by real disk ordering: default natural String sorting did not match technical hexadecimal cursor ranges. Explicit `.lexical` descriptors now cover Saved raw ordinal keys, page sequence keys, projection keys and export sections, plus existing outcome migration/export/retention technical keys. I read the actual failing focused log and subsequent four-test success, including hexadecimal ordinal disk ordering and101-header outcome export windows. This repairs the identified cursor-order mismatch; it is not a claim that arbitrary user-facing strings should use lexical sorting.

## Terminal evidence inspected

- `/tmp/hadithly-saved-store-ios-expanded2.log`:105 tests, zero failures, `TEST SUCCEEDED`.
- `/tmp/hadithly-saved-store-android-expanded3.log`:86 tests, zero skipped/failed, `BUILD SUCCESSFUL`.
- `/tmp/hadithly-saved-store-order-red.log`: actual disk order tests failed before lexical descriptors.
- `/tmp/hadithly-saved-store-ios-sort-green.log`: four focused tests, zero failures, `TEST SUCCEEDED`.

I inspected the actual new tests rather than using totals alone:1,005 raw facts/503 projections with reopen and unchanged production base; exact replay without mutation-clock change; changed replay/duplicate source rejection; Android actual SQLite checkpoint abort rollback; Swift logical rollback without claiming injected CoreData save recovery; streamed portable Saved evidence with retained old-owner notes, foreign subject/namespace exclusion and redacted continuation tokens; shared fence invalidation; suspended late reply after durable erase; bounded cleanup/reopen; owner-only reset preserving sibling owner and shared clock; real old SwiftData schema and SQLite v1/v2 disk reopen with prior outcome evidence retained.

## Accurate limits and remaining gates

The implementation now states the real bounded operation budget: up to8 raw facts per local fold,8 target reads,8 writes plus fixed metadata below50; page-chain verification reads at most8 receipts+8 facts plus metadata. Generated server page capacity is currently1 fact. No16-total-operation claim and no future larger-page claim is made.

A small session-guard parity hardening opportunity was sent to the parent: Android's local non-Collecting advance checks `isCurrent` before entering `withContext(IO)` while append also rechecks inside IO. The durable owner/epoch/generation/erasure checks remain in each transaction and reject erased candidates. This observation did not demonstrate cross-owner corruption; parent can mirror the append guard before finalizing.

Production page subscriptions, active generation/pointer migration, private Saved barrier/pruning/manifest settlement integration, legacy whole-partition cache scale and positions remain separate work. Actual recoverable iOS save-failure, physical-device/installed SDK/cross-device and hosted/deployed proof remain open. No A2 deployment, paid-model or private-account action is authorized by these local test results. No cloud/live correctness was inferred.
