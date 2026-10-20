# Outcome export final implementation review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only architect Phase D recheck after the first implementation review

## Result

No remaining actionable implementation defect was found in the reviewed outcome-journal export slice. All five prior findings are repaired in current source, and the focused native evidence covers the important failure paths.

This result does not close settlement, ACK, pruning, full-export scale, deployment, external-provider, physical-device or release gates.

## Prior findings rechecked

1. **Android retained fence during SAF copy: fixed.** `LibraryPreparedExport` now retains `LibraryOutcomeExportFence`. `copyPreparedExport` checks session capability, the exact epoch/revision fence and artifact ownership before every bounded write and after flush. A post-seal or mid-copy journal mutation now fails the copy.
2. **Android failed-document rollback: fixed within app control.** Settings tracks completion and runs `SettingsExport.removeFailedDocument` in a non-cancellable finalizer for failure, cancellation and session change. It also removes a created URI when the captured context is absent. The helper tries `DocumentsContract.deleteDocument` and then `ContentResolver.delete`.
3. **iOS disappearance cleanup: fixed.** Settings cancels the task and discards any prepared artifact in `onDisappear`; account/session changes use the same cleanup path.
4. **iOS scope-only mutation clock hole: fixed.** `collectOutcomeStep` records whether it inserted a missing scope and bumps the same subject-plus-namespace clock before the shared save. Header/inventory creation and scope repair therefore invalidate an active export.
5. **Installed migration and index proof: fixed for local native stores.** The iOS test creates the exact pre-export SwiftData schema, reopens it with the new schema, exports old-owner orphans and verifies SQLite query-plan index use. Android creates a real v1 SQLite journal, upgrades to v2, verifies the `headers_export` query plan and reads the migrated rows.

## Current invariants confirmed from source

- One mutation clock covers a Clerk subject plus deployment namespace across every owner key. Old-owner and partitionless headers are included only when their persisted authority matches the captured subject and namespace.
- Header creation, page persistence, checkpoint verification, scope repair, inventory backfill and erase changes bump the clock in the same native transaction/save as their journal change.
- iOS discovers headers through a unique scoped inventory key with two-pass bounded backfill. Android discovers them through `(subject, namespace, collection_key)` with 50-row pages.
- Full erasure marks the clock erasing before cleanup, deletes private artifacts, and leaves the durable deletion intent to prevent clock or journal resurrection after the clock row is removed.
- Private files remain registered until explicit discard. Preparation failures and cancellation remove partial files; startup sweeps abandoned registry rows and managed directories.
- Exported rows remain bounded to 50 per read. Status, expected and collected counts, verification counts, unavailable reason and collected-prefix boundary remain distinct.
- Server and partition fields are preserved structurally, exact user text survives JSON encoding, and denied capability/provider-passage fields are removed structurally.

## Evidence checked

- `/tmp/hadithly-outcome-export-ios-index.log`: 73 tests, zero failures. The run includes real old-schema SwiftData reopen, owned orphan export, foreign exclusion, index query-plan proof, mutation/verification/erase fencing, cancellation cleanup and parsed file checks.
- `/tmp/hadithly-outcome-export-android-races.log`: 55 connected Android tests passed. Instrumentation uses actual debug `DocumentsProvider` URIs and injects mid-copy mutation, I/O failure, cancellation and account switch. Partial destinations are observed, rolled back and confirmed absent. The suite also verifies real v1-to-v2 migration and `headers_export` query-plan selection.
- `git diff --check` passes.

## Gates that remain open

- Arbitrary production SAF providers and receiving iOS apps may refuse deletion or retain bytes after accepting them. The code now attempts rollback and reports failure honestly; debug `DocumentsProvider` success cannot prove every external provider.
- No physical-device Settings journey or user-visible share/save/cancel matrix was reviewed here. Emulator/simulator and native-store evidence do not close that gate.
- Existing server export and local partition payloads are still assembled in memory. Journal streaming does not close the full-export memory/scale gate.
- Final journal settlement, ACK intent, success pruning and exact retention policy remain outside this slice. The current terminal journal correctly stops before ACK.
- Development deployment, cross-device/account deletion propagation and release gates remain open.

The implementation is ready for the parent's broader verification and documentation pass without another code correction from this review.
