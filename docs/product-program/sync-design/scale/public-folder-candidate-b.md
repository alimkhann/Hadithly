# Candidate B: capability-negotiated protocol 2, one frame endpoint

## Usage first

```text
current native transport.open:
  binding = librarySync.openBinding({protocol: 2})
  verify binding.protocol==2 and captured subject/session before claiming/sending
transport.send(frame): librarySync.applyBatch({capability: binding.capability, frame})

account delete: submit folder_delete(folderReference)
account Undo: submit folder_restore(deletionId, capturedName, hadithIds=[])
// Guest Undo retains existing local identities; account UI captures no member array.
```

The endpoint hides protocol dispatch and manifest preparation. Callers cannot request asynchronous behavior through command shape. Both native transports request protocol2; all current source callers migrate together. The unchanged syncBatchDigest remains immutable frame identity.

## Grounding

Current `librarySync.openBinding` has no args, stores owner/digest/expiry and returns owner/subject/capability. `applyBatch` validates binding/frame then calls existingFrameExchange before business operations; inline folder delete reads take501 and rejects larger membership. Existing `holdFolderFrame` validates one exact folder operation and binds header/stream proof, while `commitPreparedFolderDeletion` publishes visibility and held terminal receipt atomically. Scans stop prepared without automatic commit. `beginFolderRestoration` reserves server deletion membership/name, stages bounded work and publishes after visibility flip. Alias restore:<deletionId> is currently maintained only in private librarySync helper. Native account Undo captures full local member IDs; projection's existing array fallback can overwrite newer intent. These are the boundaries to change, not receipt authority/ACK/retention policy.

## Shape and dispatch

```ts
type BindingProtocol = 1 | 2;
// openBinding args: {protocol?: literal(2)}; omitted means 1.
// Stored binding adds protocol?: literal(2), legacy absent means 1.
// Response protocol?: literal(2), old callers retain prior response shape.
type SyncOutcome += {kind: "batch_requires_split"};
// Current syncFrame/digest unchanged. Existing pending/accepted/reconcile unchanged.
```

`boundOwner` returns validated owner plus stored protocol to apply dispatch, not a client-supplied protocol flag. Reject unknown protocol values. Do not upgrade an existing capability in place. New client refuses send if protocol2 request returns absent/unsupported response; it does not silently fall back to inline support. Old backend rejecting the new optional arg is an explicit backend-first rollout gate. Binding renewal preserves requested protocol; old stored/schema bindings remain v1.

`librarySync.ts` owns negotiation and frame adapter. `librarySyncFrames.ts` owns held proof and existing stream decision. `savedFolderTransitions.ts` owns bounded jobs/visibility/recovery; extract alias helper into a small shared owner-validated module used by both legacy and manifest visibility. One adapter, not a second domain implementation.

Public adapter order:
1. Verify JWT+capability protocol; validate unchanged frame/size; compute digest.
2. Run existingFrameExchange before protocol routing. Existing v1 pending/committed history returns exact original proof, even when replayed with a v2 capability. No folder preparation or split migration touches an existing slot.
3. Protocol1: preserve shipped inline behavior and old validators. Never emit new outcome kinds to capabilities without protocol2.
4. Protocol2 new frame containing folder operation mixed with other operations: commit exact no-effect split receipts for ALL operations, no library version advance, no manifest/job/business effect. This is a real committed stream receipt, not an error or retry hint.
5. Protocol2 isolated folder delete/restore: enter manifest adapter below. Other frames retain current ordinary behavior.

## Mixed frozen migration

Native split transition accepts only direct accepted proof for the exact frozen frame or exact poll proof with matched persisted fingerprint. Validate every ID/revision and require every outcome=batch_requires_split; mixed ordinary/split outcomes are invalid. Persist replacement pending commands in original order with ORIGINAL IDs/revisions/timestamps/source and clear only that frozen frame, with exact ACK intent in the same local save. Later queued writes follow the replacement commands. Freeze blocks until ACK completes, then existing isolation produces singleton folder frames without modifying command bytes.

Unknown/historical cursor adoption archives as today; it does not requeue originals because a split-like server cursor alone proves no local command match. Existing v1 committed mixed frame returns its original inline receipt: never split/reapply it. Lost split response/reopen retries exact stream slot and replays the deterministic local transition once. New batch IDs/sequences, unchanged operation identities are valid because server idempotence is stream/frame proof, not an indefinite per-operation ledger; confirm actual current source retains that invariant before implementation.

## Atomic manifest admission and automatic completion

Delete adapter resolves actual owner folder/reference, prepares manifest and holds exact frame in ONE Convex mutation transaction. If preparation/hold fails, no orphan manifest or half-bound stream commits. Structural owner busy is transient fixed error/retry with frozen frame retained. Missing/stale/expired are explicit terminal outcomes. Manifest workers retain 50-row scan bounds and owner/generation checks.

When scan reaches prepared, schedule commitPreparedFolderDeletion automatically. Extend recovery's bounded indexed selection to prepared HELD headers; rerun commit idempotently so a crash/missing scheduler delivery cannot strand pending stream. Commit rechecks folder epoch/metadata/owner/header expiry and exact held stream proof; visibility+Saved revision+terminal committed receipt remain one transaction. An already committed pending replay returns exact outcome. Changed/expired work publishes explicit failure before purge; pending itself is never ACK.

Restore adapter resolves authoritative owner deletion handle, reserves beginFolderRestoration and holds frame atomically. Ignore command.name/member list for authority. Missing/expired retained authority creates no destination folder and returns recoverably unavailable. Stage and final materialization use existing bounded jobs. At final visibility, insert/check restore:<deletionId> alias in same transaction as destination visibility and held receipt. Exact alias reuse is idempotent; conflicting alias destination aborts visibility, not overwrite. Same-name destination comes from domain name policy, never local guessed IDs. Workers/recovery cannot recreate erased owner data.

## Compact account Undo and offline projection

Account Undo state becomes {deletionId, name, originalDeadline, capturedWriteContext}; account SavedFolderDeletion presentation must not carry hadithIds. Change both account call sites and remove full-ID capture; keep guest SavedFolderDeletion local behavior separate. New account commands retain hadithIds=[] only for wire compatibility. Old nonempty commands are old state, not a license to trust injected membership.

Projection fold keeps ephemeral per-item `lastLocalFolderDeletion` metadata while processing its existing loaded items, not another persistent list. When applying delete D, mark each currently assigned local item with D and clear visible membership. Applying restore(D) can restore only those marked D, choosing consistent normalized-name destination/server alias or local placeholder. Later membership_put, INCLUDING explicit none/same-folder assignment, clears local deletion authority; last-facet removal clears it too. Subsequent delete/restore updates token so old D cannot revive later history. Preserve fold order of pending/frozen/confirmed; no second array or command member payload.

When authoritative Saved base advances and the earlier delete is no longer in fold, no authority exists: compact Undo renders no guessed restored members until actual Saved response. Existing manifest settlement waits for committed Saved revision and does not invent full restore overlay. Original five-second UI deadline does not restart on retry/reopen; already queued offline Undo remains pending durably even after UI expiry. Retention dependency extractor must continue recognizing empty-array folder_restore through deletionId so queued Undo prevents deletion evidence pruning.

## Old deletion authority and installed compatibility

Protocol2 can encounter legacy inline deletion marks from an old installed app/backup. A compact empty list cannot reconstruct absent canonical Saved row identity or trusted server deletion time. For this unit retain existing bounded legacy restore adapter only when an exact owner legacy folder-deletion mark proves authoritative stored member set<=500; use that server set, not client list, and retain explicit legacy transaction-scale/unknown-age gate. If mark lacks sufficient authority or exceeds bounds, return explicit recoverable unavailable with original command retained. Do not pretend the mark._creationTime after replace is deletion commit time, reset a retention clock, or manufacture a fresh manifest from claimed IDs.

Protocol1 capabilities continue exact old inline receipts/admission and have the documented >500 limitation. Old validators/schema defaults remain decodable. New wire outcome/generated native source evolves locally; backend schema adds optional binding field. Local schema/codegen source changes do not authorize convex dev/codegen deployment. Backend-first rollout plus old installed app replay proof are separate gates. One endpoint simplifies endpoint inventory but creates negotiation state; it cannot erase legacy support honestly.

## Ownership, storage and proof

No new user-ID arguments, no secrets outside binding, no paid/provider calls. Keep exact pending intent digest, stream sequence, Saved barrier, native journal terminal collection, ACK confirmation, 30-day retention, erasure/export fences. Batch_requires_split is explicitly no-business-effect migration, not recovery that may be silently discarded. Historical sources remain available without automatic re-execution.

Backend real Convex red/green: public protocol2 501+ delete reaches prepared then automatically committed; default/old capability never receives manifest/split; renewed protocol2 rejects fallback; existing v1 mixed committed replay exact unchanged; new mixed returns all-split with zero business writes/version changes; lost poll/response stable; prepare/hold rollback; prepared recovery after interrupted scheduler; stale epoch/busy/expiry; restore authoritative set/name and alias atomically published; wrong owner/erasure cannot publish.

Both native actual-store/coordinator tests: direct/polled split persists once, order/IDs/source/later writes survive restart and ACK loss; unknown cursor never requeues; singleton restored old backup; account Undo emits empty list at 501+ with no UI member capture; local projection clear/restore D, newer none/same-folder move, removal, later delete/restore suppress D; authoritative base without D yields no guessed members. Verify real generated wire, current send adapters and guest unchanged parity. Full Saved/export bounds, old installed/Undo migration, deployment and physical authenticated cross-device gates remain open.

## Tradeoffs, alternatives and synthesis

Accept optional capability protocol metadata and explicit backend-first negotiation in exchange for one apply endpoint and centralized replay-first routing. Versioned endpoint is simpler to inspect and avoids capability/schema branching but duplicates API surface; it may win when rollout clarity matters more than endpoint count. Inferring support from empty member lists is rejected: old/new frozen content is not capability proof. Rewriting mixed batches client-side before exact no-effect receipt is rejected because v1 may already have committed them.

Recommend protocol-negotiated base only if binding tests prove old schema default and renewal reliably. Graft versioned candidate's centralized shared adapter rather than duplicating domain logic. Candidate only; parent selects implementation.
