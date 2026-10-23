# Durable Saved draft-view component recheck

2026-10-23. Read-only follow-up to `/tmp/hadithly-saved-view-store-review.md`. Inspected the current allocator/resume API split, serial limits, strict Android scalar decoding, iOS indexed peer admission and the actual new disk tests. Parent is sole implementer. No code/docs/cloud/delegation changes by this consultation.

## Findings resolved

All three concrete P2 findings from the prior review are addressed in current source and matching real-store tests. **No remaining concrete correctness finding identified in this reviewed draft component.**

1. **Head/serial ABA:** caller-selected `beginSavedViewRows(identity)` has been removed. `createSavedViewRows(privateScope)` allocates a fresh UUID generation inside the store and checks exact owner/current private epoch. It rejects same-identity preexisting head/child key prefixes with bounded probes. `draftSavedViewStamp(identity)` only resumes an existing validated head and never creates. New tests delete an empty head, require getter failure, allocate a different identity, then create headless private child rows, require old draft access failure and allocate another empty generation without adopting those children. Thus an old serial0 ticket cannot revive after head loss. Orphan private evidence remains retained/exportable until scoped erasure.
2. **Terminal serial:** head reads and export allow terminal9007199254740990; writes reject that terminal before changing any child row/index. The last valid increment remains readable, and further writes cannot return an unusable stamp. Actual-store tests capture a fence, set terminal metadata, read draft/export successfully, reject a write, and require unchanged private rows/fence.
3. **Android metadata coercion:** serial read/export requires Cursor integer type plus Long range. Kind read/export requires actual integer storage and exact0/1 before narrowing. New SQL poison fixtures use fractional serial0.5 and kind4294967297; both draft read and retained export reject instead of coercing them.

The lifecycle correction is an API improvement rather than a repair protocol around corruption: allocation chooses a new identity, resume cannot reset it, and recovery/export does not silently certify orphan rows as a current draft.

## Boundedness and rollback recheck

The iOS three-head peer cap now uses a closed technical key-prefix range rather than unindexed scopeKey filtering. Exact metadata admission uses fetchCount without decoding/loading the account payload. Existing index seeks use primary key ranges with bounded page heads plus exact private row reads; no broad filter-after-limit or tombstone anti-join is introduced.

Logical batch bound remains eight private item/folder inputs, at most sixteen technical index keys per visible item; those are different counts and are named honestly. Index cleanup remains128 small derived rows, private rows/heads8. All child/index/serial/fence changes still save atomically within the existing database boundary.

The Android trigger aborts the head serial update **after** staged child row/index mutations. The test reopens/reads unchanged private state, zero indexes and a valid preexisting export fence, then retries successfully. This is actual SQLite transaction rollback evidence.

The iOS clock-exhaustion test stages child/index changes, then fails the export-clock bump before save; context rollback leaves no private/index rows and the prior fence valid. It proves logical unsaved-context rollback, **not** recovery from ModelContext.save failure. The prior Core Data trigger fatal remains failure evidence and the actual recoverable iOS save-failure gate stays open.

## Privacy and orphan evidence

New tests retain a headless private note, another same-subject old-owner view whose account partition was removed, and a foreign subject's view. Captured-owner retained export includes both correct-scope orphan notes and excludes the foreign note. Draft reads of the missing owner/head fail; export does not recreate or authorize that owner. Full scoped erasure preserves the foreign view and a newer anonymous guest note while deleting matching heads/private rows/indexes. This exercises extra derived private copies instead of treating them as exempt cache data.

The component still exposes raw draft APIs only. It has no certified completeness record, published active view pointer or production row-mode setter. A query over an incomplete draft is not evidence of complete library emptiness. Publication, bulk compiler/catch-up and atomic private/mode/view/queue transition remain next work, as do exact UI windows/public hydration. Raw mask0 writes represent final compiled omission; later optimistic queue integration must still preserve/recompute relevant chronological zero-facet history rather than blindly forgetting old createdAt/folder semantics.

## Pure policy and oracle precision

Prior normalization/alias fixes remain intact and `python3 scripts/generate-saved-view-vectors.py --check` passes against actual backend normalization. Directory/name selection uses the shared UTF-8 folder rank.

The Foundation Date oracle now compares old Date values to Date constructed from the new exact milliseconds at the same conversion boundary. It does not round the new private Double fields or relax deterministic technical-key fixtures. That resolves the previous reference-epoch precision mismatch without making the old reducer mirror the new implementation.

## Limits

No broad A2/release gate is approved. Draft persistence/index seek is only one verifiable component. Three-head retirement orchestration, certified build coverage, production pointer/row-mode/UI cutover, independent public route/text hydration, legacy full-array/cache retirement, pending/positions/server-export throughput, installed/backend-first rollout, real SDK/JWT, cross-device/physical-device and actual recoverable iOS save failure remain open. No deployment or push is authorized here.

## Current-tree test artifacts

Inspected parent-run terminal artifacts directly; reviewer did not relaunch native suites:

- `/tmp/hadithly-saved-view-ios-full.log`: **134 selected tests, zero failures**, TEST SUCCEEDED. Result bundle `/tmp/hadithly-saved-view-ios-full.xcresult`. This current run supersedes the earlier focused Date-oracle failure.
- `/tmp/hadithly-saved-view-android-full.log`: **123 connected tests**, BUILD SUCCESSFUL. The actual current connected XML `TEST-hadithly(AVD)-_app-.xml` reports123 tests, zero failures/errors/skips.
- Shared backend-generated naming/key fixture `--check` passes, and final `git diff --check` is clean.

All three prior P2 findings are resolved on the inspected source/test paths. No remaining concrete finding identified in this draft persistence/index unit. Parent can document/commit the component with production mode still OFF and all limits above retained.
