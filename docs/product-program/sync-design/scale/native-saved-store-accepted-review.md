# Native Saved prepared-store accepted review

2026-10-21. Final read-only recheck of the same durable prepared-store component. Parent is sole implementer. No repository edits, external/cloud/account calls or delegation.

The last identified bounded-query gap is resolved. Swift `beginSavedErase(ownerKey:)` computes the exact hashed assembly key, calls the existing unique-key lookup and validates subject/namespace/owner before marking erasing. Android now likewise uses its primary-key `scope_key` lookup/update and validates the returned ownership fields in one transaction. Missing headers remain no-op at this marking step; retained-child admission protection and explicit bounded orphan cleanup remain unchanged. Namespace mutation clocks still bump, preserving export invalidation.

This closes the concrete findings recorded in `store-review.md`, `store-final-review.md` and `final-hardening-review.md`: Android projection scans, technical-key ordering, inside-IO session-guard parity and Swift erase-admission lookup scope are addressed. No remaining concrete defect was found in the final inspected delta or previously reviewed prepared-store component.

Fresh terminal logs inspected directly:

- `/tmp/hadithly-saved-store-ios-accepted.log`:107 tests, zero failures, `TEST SUCCEEDED`.
- `/tmp/hadithly-saved-store-android-accepted.log`:88 tests completed, zero skipped/failed, `BUILD SUCCESSFUL`.

Accepted scope remains durable raw page/continuation storage, exact replay/identity checks, bounded fold and page-chain/projection verification, prepared-generation reads, additive disk migration, shared export fencing/streaming and bounded local erasure. The prior reports record actual tests and query-plan evidence supporting that scope.

Production page subscription/activation/read and active Saved version/barrier migration, manifest settlement/pruning integration, legacy full-cache/export scale, real hosted/installed-SDK/cross-device/physical-device matrices, and recoverable iOS save-failure evidence remain open. These results neither deploy A2 nor establish production/release readiness. The full product program remains active.
