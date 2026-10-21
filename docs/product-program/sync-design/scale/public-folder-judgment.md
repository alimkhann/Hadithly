# Public folder transition cross-judge

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Mode: read-only architect/arena cross-judge

## Verdict

Reject both candidates unchanged. Use a smaller B-derived Candidate C:

- Keep `openBinding({})` exactly unchanged and v1.
- Add `openManifestBinding({})` for current native clients. It returns the unchanged `SyncBinding` DTO but stores optional protocol-2 metadata on the binding row.
- Keep one apply/poll/ACK/retire family. Dispatch from stored binding metadata and guard every returned or consumed stream proof against that protocol.
- Move both current native `open` adapters to `openManifestBinding`; no `SyncBinding` wire/schema/codegen/test-initializer churn is needed.

Graft A's explicit no-effect split semantics and backend-first native cutover, plus B's stored binding authority, authoritative legacy deletion-set restore and compact projection rules.

## Scores

| Criterion | A | B | Judgment |
| --- | ---: | ---: | --- |
| Exact old/new client and mixed-frame truth | 2 | 3 | A versions only apply; B stores protocol but still permits replay-first/shared paths to expose unsupported proof unless every path guards output. |
| Public job/Undo idempotence and alias visibility | 3 | 4 | Both use held jobs. A adds unnecessary alias reservation state and incorrectly rejects empty legacy restore; B is closer to existing authoritative transition ownership. |
| Native compact/offline behavior | 4 | 4 | Both preserve exact split migration and causal local projection without a second member array. |
| Bounded work, ownership and source compatibility | 3 | 4 | B keeps authoritative legacy deletion sets. A's empty-command rejection discards valid bounded server authority. |
| Interface depth and executable proof cost | 3 | 3 | A duplicates the apply surface; B changes the common binding DTO and negotiation contract. Candidate C avoids both costs. |

Totals: A 15/25. B 18/25. Candidate C is the selected synthesis rather than shipping B unchanged.

## Mandatory decoder boundary

A restored old v1 binary can share a `clientKey` with stream history created by v2. The boundary therefore cannot depend on which apply endpoint receives the request or on command shape. Before a v1 call consumes or returns an unsupported proof, throw fixed `SYNC_CLIENT_UPGRADE_REQUIRED` and roll back the transaction.

Apply this guard to all paths:

1. `applyBatch`: run exact stream lookup first. A v2 binding may replay old inline committed proof. A v1 binding encountering pending manifest, manifest terminal receipt, or split receipt throws upgrade-required instead of returning it or applying anything.
2. `pollPending`: verify binding protocol before returning the pending/committed/reconcile exchange. V1 never receives v2 proof.
3. `acknowledge`: if exact active proof or the resulting cursor contains unsupported v2 state, throw before the mutation commits. Convex rollback preserves the slot. Wrong ACK must not leak an unsupported cursor either.
4. `retireInvalidFrame`: a v1 call cannot retire or step across a v2 pending/committed slot. Guard the resulting cursor before return so thrown errors roll back retirement consumption.
5. Any shared cursor/readback helper must pass through the same protocol-output guard. One audited `assertProtocolExchange` / `assertProtocolCursor` family is safer than scattered decoder checks.

V2 accepts old inline proof exactly. V1 accepts only its shipped inline outcome set. Unknown protocol metadata fails closed. Capability protocol comes only from the stored binding row, never request fields or client key.

## Candidate C shape

```text
openBinding()          -> existing SyncBinding, stored protocol absent = v1
openManifestBinding()  -> same SyncBinding, stored protocol = 2

applyBatch(capability, frame)
pollPending(capability, pending)
acknowledge(capability, ack)
retireInvalidFrame(capability, clientKey, sequence)
```

`requireLibraryBinding` returns owner plus internal protocol metadata. Public DTOs remain unchanged. Existing test fixtures and installed decoders remain valid. Current iOS and Android transport `open` calls the new endpoint first; an old backend that lacks it is a backend-first rollout blocker, not a silent fallback to v1.

## Frame dispatch and replay

- Validate identity, frame and unchanged `syncBatchDigest`, then resolve existing stream state before classifying fresh work.
- V2 replay of a v1 committed mixed frame returns the exact inline receipt. Never split or reapply it.
- A fresh v2 mixed frame commits one exact `batch_requires_split` receipt per operation, with no business effect and no Saved version advance.
- Native split settlement accepts only an exact direct or polled receipt for the still-matching frozen frame. All IDs/revisions must match and every outcome must be split. It requeues unchanged operations and sources in original order ahead of later writes, persists ACK intent and waits for ACK before freezing new frames.
- Unknown/historical cursor adoption archives original source and never auto-requeues it.
- A fresh v2 isolated folder operation enters the manifest path. V1 retains current inline behavior and its explicit >500 limitation.

## Delete, restore and legacy authority

- Delete preparation and `holdFolderFrame` share one Convex mutation. A pending slot is exact and never ACKable. Prepared held work must be recovered automatically and committed idempotently.
- Restore begin/hold also shares one mutation. Manifest restore uses the authoritative retained deletion manifest, name and members; client `hadithIds` is not authority.
- For a legacy inline deletion mark, its owned `folder_deletion.hadithIds` set is authoritative and already bounded to at most 500. A compact v2 restore with `hadithIds: []` may use that server set. Do not reject it merely because the client list is empty.
- Old nonempty restore commands may use only the same authoritative server set. Extra client IDs cannot create identity; current union behavior may classify extras missing, but the restored set comes from the mark.
- Retain the <=500 legacy transaction/read-scale gate. Do not fabricate clocks, original rows, or deletion time from mark `_creationTime`.

## Alias visibility without a pending-alias table

Reserve the `restore:` key namespace from ordinary client `folder_create` keys. At restore begin, resolve the authoritative destination policy and inspect any preexisting `restore:<deletionId>` alias. Exact same destination is idempotent; a conflicting alias yields terminal superseded before transition reservation or visibility.

Publish the alias with destination visibility and the held terminal receipt in the final transaction. Do not expose it while pending. This removes the need for a separate pending-alias table while preventing a new ordinary create from stealing the server-owned namespace.

## Native compact Undo and projection grafts

- Account Undo stores deletion operation ID, name, original deadline and captured write context. It emits `folder_restore` with an empty list. Guest/local Undo keeps its local identities.
- During projection, tag membership removed by the exact local delete operation. Compact restore may restore only items still tagged by that deletion.
- Later membership assignment, explicit none/same-folder move, last-facet removal, or newer folder operation clears/replaces the tag. Old delete intent cannot resurrect newer placement.
- If the authoritative Saved base advances without the local delete in the fold, project no guessed membership until the real result arrives.
- Accepted restore keeps the existing Saved barrier and binds `restore:<deletionId>` mapping from the actual receipt.

## Required proof

- V1 calls through apply, replay, poll, wrong/exact ACK and retire against every v2 pending/split/manifest state. Every unsupported path throws exactly `SYNC_CLIENT_UPGRADE_REQUIRED` with no state consumption.
- V2 exact replay of old v1 inline committed and pending history; no duplicate effect.
- Fresh mixed v2 no-effect split, lost response, polled split, ACK loss/reopen, operation order/source preservation and unknown-cursor non-requeue.
- 501+ delete preparation, held recovery from prepared, automatic commit, retryable busy, terminal stale/missing/expiry and erasure.
- Manifest restore authoritative members/name, legacy empty compact restore from <=500 server mark, injected client IDs ignored/missing, and >500 legacy gate retained.
- Alias namespace rejection for ordinary creates, preexisting conflict terminal before visibility, idempotent exact alias and atomic final alias/visibility/receipt.
- Both real native stores: compact account Undo, projection causal tags, newer move/removal suppression, guest parity and generated wire decoding.

## Gates retained

Backend-first rollout, old installed-client matrix, legacy transaction scale, full Saved/export bounds, manifest Undo/public producer deployment, physical authenticated cross-device proof and full A2 remain open.
