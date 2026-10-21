# Candidate A: explicit v2 frame endpoint

## Problem

The current public `librarySync.applyBatch` synchronously applies every operation, and folder delete returns `folder_too_large` after a 501-row read (`librarySync.ts:75-96,243-265`). Existing installed clients understand only inline receipts. The bounded manifest scanner, held stream proof and logical delete/restore jobs exist but are not connected to a public producer (`savedFolderManifests.ts`, `librarySyncFrames.ts`, `savedFolderTransitions.ts`). Current native clients already freeze folder operations alone, but installed v1 backups can contain mixed frames. A new endpoint must preserve exact old stream history before changing production routing.

## Usage (caller's view)

```text
// New iOS/Android LibrarySyncTransport.send; all current native sends use v2.
transport.send(capability, frozenFrame) -> SyncExchange  // librarySync:applyBatchV2
// accepted ordinary receipt / pending manifest / exact split receipt, all on one stream

// Account Saved UI, unlike guest local Undo:
let deletion = enqueue(folderDelete(serverOrLocalFolder))
undo.capture(deletion.operation.id, folder.name, deletion.operation.at) // no member array
undo.tap { enqueue(folderRestore(deletionId: id, name: name, hadithIds: [])) }

// Existing installed binary stays on librarySync:applyBatch and decodes inline receipts.
```

## Shape

`applyBatchV2(capability, frame: SyncFrame): SyncExchange` is the explicit new-client boundary; keep `applyBatch` as the unchanged v1 route for installed clients. Both derive user from Clerk JWT and owner-bound capability, validate the same frame/size/clock rules, compute the **unchanged** `syncBatchDigest`, and call `existingFrameExchange` before choosing a new effect. A v2 request at an already committed v1 slot gets that exact inline receipt; a closed sequence reconciles, never replays. `pollPending`, ACK, cursor, retirement and page proof remain shared. Transport generation derives from the actual Convex validator; no version inference from operation contents or capability shape.

For a fresh v2 frame, classify `ordinary | isolatedDelete | isolatedRestore | mixedFolder`. `mixedFolder` means any folder operation with any other operation (including a second folder); commit a no-effect accepted reply with one new `batch_requires_split` outcome per exact operation ID/revision, one Saved revision observation but no Saved data/version mutation, and a normal ACK slot. Native `LibraryPartitionState` accepts this sentinel **only** for an exact frozen batch whose operations and `intentDigest` still match the submitted frame and all receipts are split. It atomically prepends those unchanged `LibraryLocalChange`s to `pending` ahead of later writes, clears frozen, advances one sequence and persists ACK intent. No command executes before split; ACK gates the requeued frames. A polled exact receipt can do the same only when retained frozen intent matches. A historical/unknown cursor archives old local source and never auto-requeues. A previously committed v1 mixed frame must return its old receipt, not a split claim; the pre-classification stream check is the crucial ordering. New sentinel is v2-only, so installed v1 decoders never see it.

For isolated delete, resolve the owner folder reference through a shared alias resolver, then call `prepareFolderManifest` and `holdFolderFrame` **in one mutation**. The pending slot captures client/sequence/batch/digest/intentDigest, manifest ID/generation and exact single operation. Its worker scans at most 50 rows per step; when it reaches `prepared`, schedule `commitPreparedFolderDeletion` immediately. Add `prepared` to the stale-worker recovery index; a lost schedule is retried by generation and state, and duplicate commits converge. Commit rechecks owner, epoch, folder metadata/mark, logically removes visibility, advances Saved revision and publishes the held exact receipt atomically. A replay returns the same pending/committed proof. `folder_busy`/`owner_busy`/structural lock is a fixed retryable error with no applied business effect and the client keeps its frozen frame; missing/stale/expired is a committed unresolved/superseded single receipt, not an endless busy retry. Pending is never ACKed.

For isolated restore, call `beginFolderRestoration(owner, {id,at,deletionId})`, then `holdFolderFrame` for its `restoring` result in one mutation. The authoritative manifest supplies name and original members; v2 ignores `command.hadithIds` for that handle. Four-member workers stage and finalize, and the final transaction must publish one exact receipt with counts **and** bind the owner alias `restore:<deletionId>` to the visible destination. Missing/expired deletion authority returns `folder_restore_unavailable` with no folder creation. Reserve that alias key at restore begin against another use, with a manifest-bound pending state that ordinary folder resolution treats as unavailable; at final visibility flip set its folder ID, reject conflicting rebinding and leave no half-visible alias. Legacy alias helpers move behind one owner-scoped module used by ordinary create/restore and transition workers. Same-name destination reuse remains the existing transition rule.

V2 compatibility is deliberately narrow. If no manifest exists, a nonempty old `folder_restore.hadithIds` may use the current **bounded** legacy deletion mark path and return its inline outcome; an empty compact command cannot conjure identities from a legacy mark and returns recoverable unavailable. The installed v1 endpoint remains its existing <=500 path, including its `folder_too_large` outcome. This unit does not convert old marks to manifests: they lack a trusted deletion-commit clock and original Saved row identities. Any account Undo token from a prior v1 inline deletion retains its old bounded array until used/expired; newly created v2 tokens contain only deletion ID/name. Do not use mark `_creationTime` as a substitute timestamp or silently reset retention.

Native projection needs one transient per-item causal tag, derived during its existing fold rather than stored as a second array. When a local delete removes an item from its folder, set `removedBy[hadithId]=deleteOperationId`; when a later membership put (including same-folder unassignment), last-facet removal, or newer folder operation touches it, clear/replace that tag. A compact **uncommitted** restore reassigns only still-tagged, still-saved items for its `deletionId` to the same-name destination or `local:restore:<id>` placeholder. If the owned base advanced and has no original local delete authority, project no restored identities. Once accepted, `collectingOutcome` suppresses the guessed restore until the authoritative Saved revision arrives, as the current partition already does. `folderMappings["restore:"+deletionId]` is set from the exact visible receipt and server alias, enabling later queued local-folder references without overwriting moves. Guest folder deletion/Undo keeps its local identity list and is unchanged.

The public adapter is one narrow function in `librarySync.ts` plus a shared owner alias module; manifest workers stay in the domain modules. Native transport changes only its send endpoint and split-settlement rule; UI account Undo changes token shape; projection owns the transient tag. No second mobile API/control plane is introduced. This keeps the public interface small while hiding job/replay/compatibility rules (boundary discipline, idempotence).

## Synthesis decision

Candidate A is the explicit-endpoint base for comparison. Prefer it if binding-negotiated protocol2 cannot reduce code without risking old decoder exposure or ambiguous installed backups.

## Tradeoffs accepted

- We accept two public apply endpoints during installed-v1 compatibility in exchange for a provable decoder boundary.
- We accept a one-time no-effect split ACK for old mixed frames in exchange for preserving operation IDs, sources and ordering without pretending they were unsent.
- We accept a bounded legacy restore path and an open transaction/read-scale gate in exchange for not fabricating server deletion history.

## Alternatives considered

Binding-negotiated protocol2 uses one endpoint and an optional version flag, but old capability/binding schema plus stale client state must be upgraded together; a missing or misread flag can expose manifest/split receipts to an installed v1 decoder. Rewriting mixed frames client-side before checking the server stream is unsafe because the original may already be committed. The explicit endpoint hides less migration ambiguity behind a slightly larger API surface.

## Open questions and risks

Can the installed native schema decode a new split outcome only after the app switches to v2? How should a v2 client surface a legacy `folder_too_large` outcome if an old v1 frame was already committed? Are current full Saved snapshot/export reads and old Undo UI tokens migrated before enabling public >500 behavior? These are verification gates, along with hosted byte limits, real device/account journeys and approved development deployment.

## Next implementation step

Write red backend tests for fresh 501 delete/Undo, prepared-worker recovery, final alias visibility, v1 exact replay and fresh v2 mixed no-effect split; then wire the v2 adapter and both native transport/Undo/projection paths against them.
