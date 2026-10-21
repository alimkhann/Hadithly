# Native Saved final hardening recheck

2026-10-21. Read-only scope: final bounded hardening deltas after `store-final-review.md`; no repo edits, cloud calls or delegates.

## Result

Session-guard parity is repaired: Android local advance and network append both recheck the captured session inside IO, then again before returning. Durable lease/incarnation checks remain in the transaction. Missing-parent admission now refuses retained child evidence rather than creating a fresh candidate over orphan rows. Owner-only deletion requires the extant header's erase marker. Swift Saved existence/admission/erase windows now use hashed indexed technical-key ranges, and deletion-intent checks use the unique existing scope key.

One small bounded-query gap remains in the inspected source: `ios/Hadithly/Core/GuestData/GuestDataStore.swift` `beginSavedErase(subject:namespace:ownerKey:)` still fetches `GuestSavedAssembly` with `subject && namespace && ownerKey` and `fetchLimit=2`. The model only indexes the unique `key`; these filter fields have no explicit index. This can scan unrelated retained headers even though returned rows are bounded. Compute the exact assembly key `hash([namespace,subject]) + ":" + hash([ownerKey,subject])`, use existing indexed `savedAssembly(key,in:)`, validate its owner fields, and set erasing. This does not affect the already-indexed full-scope erase loop or undermine the terminal correctness checks. It is the same bounded-IO requirement as the fixed Android projection finding.

## Fresh terminal evidence inspected

- `/tmp/hadithly-saved-store-ios-verified.log`:107 tests with zero failures, `TEST SUCCEEDED`; includes actual disk migration/query-plan test, missing raw fact rejection, historical token cycle, unavailable nonactivation and fresh incarnation/session checks.
- `/tmp/hadithly-saved-store-android-verified.log`:88 tests completed, zero skipped/failed, `BUILD SUCCESSFUL`; includes v1/v2-upgraded on-disk query-plan assertion requiring `saved_projection_collection` and `SEARCH`.

Inspected the actual query-plan assertions: Swift opens the migrated native store read-only through SQLite and asserts indexed range SEARCH for raw fact, page sequence and projection technical keys; Android checks the production compound index after each old schema upgrade. These are local disk proofs, not hosted native-SDK or physical-device proofs.

No new replay, cross-owner result, count, clock, export or erase correctness defect was found. Preserve separate gates for production activation/subscription/read/barrier integration, legacy full-cache scale, physical/installed SDK/cross-device paths and recoverable iOS save failure. No cloud action is authorized by local evidence.
