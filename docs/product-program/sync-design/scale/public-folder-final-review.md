# Public folder transition final review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only final source and terminal-evidence audit

## Result

No remaining concrete implementation defect was found in the reviewed public-folder transition slice. The protocol boundary, alias race, bounded producer, split replay and compact native Undo paths now have terminal passing local evidence.

This is a local implementation pass. It does not close deployment, installed-client, hosted account, SDK/device, full Saved/export scale, iOS save-failure or full A2 gates.

## Final source invariants

- `openBinding` remains the unchanged v1 endpoint and DTO. `openManifestBinding` returns the same `SyncBinding` while storing private `manifest_v2` metadata. Current native adapters use the new endpoint with no fallback.
- Apply resolves existing stream state before fresh dispatch. V2 replays old inline proof exactly. V1 cannot receive or consume v2 pending, manifest or split proof through apply, poll, ACK, retire or outcome detail.
- Fresh mixed v2 frames produce exact all-operation split receipts with no business or Saved-version effect. Native settlement requeues only an exact still-frozen frame with matching IDs/revisions and all-split outcomes, preserves source/order/later writes, and ACK-gates isolated sends.
- Unknown or historical cursor adoption never replays local work. Direct and exact polled split paths converge after reopen and lost ACK.
- Isolated delete prepares and holds in one mutation. Scans stay at 50 rows per step, automatically commit prepared held work, and recover a lost prepared schedule idempotently.
- Isolated restore uses retained authoritative membership and captured name. Legacy compact restore uses only the owned <=500 deletion mark; client-claimed IDs grant no membership.
- Restore alias is checked at begin and immediately before final visibility. A late conflict publishes exact terminal superseded proof and starts bounded unwind. Existing destination ownership is released; no new conflicting destination becomes visible and recovery does not loop.
- Fresh ordinary clients cannot claim the `restore:` namespace. Exact existing alias reuse remains idempotent. Alias, destination visibility, Saved revision and held terminal receipt share the final Convex transaction.
- Account Undo stores no member list and submits an empty array; guest Undo remains local. Projection restores only membership causally tagged by the matching local delete and suppresses restoration after newer moves, removal, later deletion or an advanced authoritative base.
- Existing journal, Saved barrier, ACK confirmation, retention, export fence and erasure rules remain intact.

## Evidence checked

- `/tmp/hadithly-public-folder-backend-final.log`: 41 files, 484 tests passed, terminal run complete.
- `/tmp/hadithly-public-folder-typecheck-final.log`: `tsc --noEmit` completed with no diagnostics; no typecheck process remains.
- `/tmp/hadithly-public-folder-ios-verified.log`: 89 tests passed, terminal `TEST SUCCEEDED`. This includes real-store split ACK failure/reopen, exact poll versus historical non-replay, malformed proof rejection, causal projection and 501-item compact Undo reopen.
- `/tmp/hadithly-public-folder-android-verified.log`: 72 connected tests passed, terminal `BUILD SUCCESSFUL`.
- `/tmp/hadithly-public-folder-support-final.log`: explicit current-binding 501 support probe passes. The separate default-v1 safety behavior remains preserved in the full backend suite.
- Focused public and domain runs remain green: 12 public protocol/producer tests and 35 adapted held/transition tests.
- `git diff --check` passes.

## Bounds checked

- Maximum 50-operation mixed split reply is measured below 64 KiB and stores no input batch copy in the committed stream slot.
- 501-member manifest pending and terminal replies are measured below 2 KiB; outcome pages remain at most 50 rows and 64 KiB.
- A valid legacy-shaped restore request with 500 multibyte claimed IDs remains below the 128 KiB input limit. The held stream size is measured below input plus fixed overhead, while the terminal manifest receipt remains compact.
- These tests establish current local source/wire bounds. They do not prove hosted platform behavior or future schema growth.

## Earlier red runs accounted for

- The first full backend failure came from the heavy 501 test exceeding Vitest's 5-second default under parallel load; its leaked in-flight convex-test transaction caused the other 11 immediate failures. The scoped heavy test now has a 30-second timeout, while the bounded drain logic is unchanged. The final full suite passes.
- The first expanded iOS run failed to compile because a new pure projection test lacked `@MainActor`. The annotation is fixed and the full 89-test runtime suite passes.

## Gates retained

- No Convex development or production deployment, migration readback, or generated-SDK rollout was performed here.
- Installed v1 binaries and restored backups still require an actual backend-first compatibility matrix against the deployed endpoint set.
- The bounded legacy <=500 transaction/read path remains a compatibility gate with unknown old deletion age.
- Full Saved snapshot, whole-partition and export memory bounds remain open.
- Hosted identity/account, cross-device, physical iPhone/Android and real SDK delivery remain open.
- Recoverable iOS SwiftData save-failure evidence remains open from the prior unit.
- Public producer rollout, retention disclosure and full A2 remain open.

The implementation is ready for the parent's verification record and commit workflow without another code correction from this audit.
