# Public folder transition implementation review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only architect Phase D review of the initial Candidate C implementation

## Findings

### P1: a legacy restore can strand a v2 restore after begin

`beginFolderRestoration` checks a preexisting `restore:<deletionId>` alias against the destination known at begin. Ordinary fresh `folder_create` can no longer claim the reserved prefix. However, the legacy v1 inline `folder_restore` path can still bind that same alias after v2 begin and before the v2 worker publishes visibility.

If the legacy restore chooses a different same-name/client-name destination, `advanceFolderRestoration` reaches `bindLibraryFolderKey`, throws `SYNC_FOLDER_KEY_REUSED`, and rolls back that final transaction. Recovery reschedules the same restoring job, which encounters the same conflict again. No terminal held receipt is published, so the exact v2 frame can remain pending until expiry instead of receiving deterministic superseded/unavailable proof.

Handle the conflict as a domain terminal before visibility:

- Recheck the alias in the final restoration transaction.
- Exact same destination remains idempotent.
- A conflicting destination must publish the held exact `superseded(changed_since_delete)` result and unwind/expire transition ownership without creating or exposing the new destination.
- Add an interleaving test: begin v2 restore, run a v1 legacy restore that binds the alias elsewhere, then advance v2. Assert one terminal v2 receipt, no half-visible destination, stable replay, and no recovery loop.

Evidence: `savedFolderTransitions.ts:70-76`, `savedFolderTransitions.ts:113-116`, `librarySyncFolders.ts:10-15`, and the legacy `applyOperation(folder_restore)` alias write in `librarySync.ts`.

### P2: outcome detail endpoint does not enforce the binding protocol

`outcomePage` calls `boundOwner` but discards its protocol. A v1 capability for the same account can request exact v2 manifest detail if it knows the proof. This does not crash an installed v1 decoder because old binaries do not call the endpoint, but it weakens the selected capability protocol boundary and contradicts the rule that v2 manifest proof stays behind stored binding metadata.

Require `manifest_v2` for `outcomePage` and throw `SYNC_CLIENT_UPGRADE_REQUIRED` for v1 before reading detail. Add a v1/v2 capability test against the same committed proof.

Evidence: `librarySync.ts:308-315`.

## Paths that currently hold

- `openBinding` keeps the old arguments and `SyncBinding` result. `openManifestBinding` returns the same DTO while the private binding row records `manifest_v2`. Native open adapters use only the new endpoint and do not silently fall back.
- Apply resolves existing stream proof before fresh dispatch. `protocolExchange` blocks v1 pending, manifest and split exchanges. V2 replays old inline committed proof unchanged.
- Poll guards direct pending, committed and reconcile results. ACK and retirement validate the current cursor before mutation, so a v1 restored client cannot consume a v2 slot. Thrown Convex mutations roll back.
- Fresh mixed v2 frames commit all-split receipts with `changesSaved=false`; no operation executes and Saved version does not advance.
- Native split settlement requires an exact still-frozen mixed frame, unique operation IDs, exactly one folder operation, matching receipt IDs/revisions, and all-split outcomes. It requeues unchanged sources ahead of later pending work and persists ACK intent. Unknown cursor adoption does not requeue.
- Delete prepare and hold occur in one public mutation. Scan scheduling starts after transaction commit. Prepared held work is scheduled immediately and the bounded recovery pass includes stranded prepared headers.
- Restore begin and hold share one mutation. Manifest restore uses retained authoritative members/name. Legacy fallback uses the owned server deletion mark and remains bounded to 500; an empty compact client list does not remove that authority.
- Account Undo emits an empty identity list while guest Undo retains local identities. The native projection restores only items tagged by the matching local delete and clears tags on later membership changes or loss of the final Saved facet.
- No second backend or user-supplied identity was introduced. Existing digest, owner, journal, Saved barrier, ACK, retention and erasure paths remain in use.

## Evidence status

- `/tmp/hadithly-compact-undo-ios-first.log`: focused 501-item compact account Undo test passes.
- `/tmp/hadithly-compact-undo-android-first.log`: connected Android counterpart passes.
- `/tmp/hadithly-public-folder-initial-backend.log`: not green. It ends with 22 failures and 447 passes. Many failures are expected fixture mismatches because transition tests still open v1 bindings or expect work to remain pending despite automatic commit. This log cannot support a backend implementation pass.
- The current focused native tests do not cover split coordinator replay, newer membership suppression, or guest parity yet.

## Required next proof

1. Full v1 decoder matrix across apply replay, poll, wrong/exact ACK and retire for v2 pending/split/manifest slots, asserting fixed upgrade-required and unchanged stream state.
2. V2 replay of old inline proof and fresh mixed no-effect split, including lost response, polled receipt, ACK loss/reopen, exact source/order preservation, and unknown cursor non-requeue.
3. 501+ delete through the public adapter, prepared auto-commit, prepared recovery, busy rollback, expiry/stale/missing terminal proof, owner deletion and exact replay.
4. V2 restore authoritative set/name, legacy compact empty restore, injected client IDs, the alias race above, same-destination idempotence, and atomic visibility/alias/receipt.
5. Both native actual stores: compact account token survives offline/reopen, later none/same-folder move and last-facet removal suppress old restore, authoritative base without local delete guesses nothing, guest path unchanged.
6. Generated validators/code compile and complete backend suite passes after fixtures intentionally select v1 or v2.

Backend deployment, old installed-client matrix, legacy scale, full Saved/export bounds, physical authenticated cross-device proof and full A2 remain open.
