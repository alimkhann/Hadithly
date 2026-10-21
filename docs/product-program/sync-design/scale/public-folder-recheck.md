# Public folder transition implementation recheck

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only follow-up after P1/P2 corrections

## Result

No remaining concrete product-source defect was found in the two corrected areas. The late alias conflict now becomes an exact terminal held receipt with bounded unwind, and `outcomePage` now requires a stored manifest-v2 binding.

The implementation cannot yet be called regression-green. Android's expanded native suite passes, but the expanded iOS suite fails to compile and the full backend run reports all 12 new public-folder tests failed. Focused backend suites pass when run alone. These are current verification blockers even though the reviewed correction logic is coherent.

## P1 alias race rechecked

- V1 inline restore now checks for any owned manifest with the same deletion operation and throws `SYNC_CLIENT_UPGRADE_REQUIRED` before it can bind the alias.
- Restore begin still rejects a preexisting alias that conflicts with the authoritative destination policy.
- Final restore rereads `restore:<deletionId>` before creating a new destination. Exact same destination is idempotent.
- A late conflict calls `startFolderExpiry` with exact `superseded(changed_since_delete)`. That function publishes the held restore receipt before moving the header to bounded expiring cleanup.
- Existing destination transition ownership is released through `releaseFolderId`; a new conflicting destination is never created. The worker returns `failed` rather than throwing into a recovery loop.
- Focused public tests cover late injected conflicts for both new and existing destinations, stable terminal replay and unwind.

## P2 protocol boundary rechecked

- `outcomePage` reads the stored binding protocol and throws fixed `SYNC_CLIENT_UPGRADE_REQUIRED` for inline-v1 before reading manifest details.
- Apply resolves stream history before fresh dispatch and guards v1 direct accepted/pending/reconcile exchanges.
- Poll guards pending, committed and reconcile output.
- ACK and retire guard the current cursor before mutation, so a restored v1 caller cannot consume a v2 slot. Convex rollback protects state on thrown errors.
- V2 can replay old inline proof exactly. Protocol comes only from the verified binding row; endpoint name, frame contents and `clientKey` do not infer support.
- Focused public tests cover v1 pending, deleted-manifest, restored-manifest and split exposure/consumption, including wrong ACK/retire paths and rollback.

## Other source invariants confirmed

- `openBinding` and `SyncBinding` remain unchanged; `openManifestBinding` stores optional `manifest_v2` privately. Both native open adapters migrated with no silent fallback.
- Fresh mixed v2 frames commit all-split proof with no operation or Saved-version effect. Native settlement requires exact frozen batch, IDs, revisions, source order and all-split outcomes before requeue and ACK.
- Direct/polled split replay is deterministic; unknown historical cursor adoption does not requeue original work.
- Isolated delete prepare/hold is one mutation. Prepared held scans auto-commit, and bounded recovery includes prepared headers whose schedule was lost.
- Isolated restore uses authoritative manifest membership/name. Legacy compact empty restore uses the owned <=500 deletion mark rather than client IDs.
- Final alias bind, destination visibility, Saved version and held receipt occur in one transaction. Ordinary fresh `folder_create` cannot use the server-owned `restore:` namespace.
- Account Undo is compact; guest Undo remains local. Projection restores only exact locally deleted membership and clears causal authority on later membership or last-facet removal.

## Evidence checked

- `/tmp/hadithly-public-folder-public-first.log`: 12 focused public tests pass.
- `/tmp/hadithly-public-folder-domain-adapted.log`: 35 adapted held/transition tests pass.
- `/tmp/hadithly-compact-undo-ios-first.log`: focused 501-item native test passes.
- `/tmp/hadithly-compact-undo-android-first.log`: connected counterpart passes.
- `/tmp/hadithly-public-folder-android-expanded.log`: 72 connected tests pass, terminal `BUILD SUCCESSFUL`.
- `/tmp/hadithly-public-folder-ios-expanded.log`: terminal `TEST FAILED`; new projection assertions call `@MainActor` `LibraryProjection` from a nonisolated test context. This is a test-code compile defect, so no expanded iOS runtime evidence exists yet.
- `/tmp/hadithly-public-folder-expanded-backend.log`: terminal red. It reports `librarySyncPublicFolders.test.ts` 12/12 failed while the same 12 pass focused. The log contains no individual stack traces, so concurrency, shared fake timers or another suite interaction is not established. Rerun with full diagnostics and fix the actual interference before claiming backend regression pass.
- `git diff --check` passes.

## Remaining proof and gates

- Fix actor isolation in the iOS test methods and obtain a terminal expanded pass.
- Diagnose the full-suite backend failure with actionable output; focused passes cannot substitute for all-suite compatibility.
- Add or confirm explicit response/source byte measurements for maximum mixed split proof, 501 delete pending/terminal proof, compact restore terminal proof and outcome pages. Input batch bounds alone do not prove every stored/returned exchange stays under intended limits.
- Verify real generated Convex bindings after approved codegen/development rollout; local TypeScript validators are not deployed evidence.
- Backend-first rollout, installed-v1 matrix, legacy transaction scale, full Saved/export bounds, physical authenticated cross-device proof and full A2 remain open.

The correction itself is ready for continued verification, but the current terminal logs do not support a final green handoff.
