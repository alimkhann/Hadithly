# Public manifest folder transition boundary

October 21, after `47a7f29`. A2 remains active. Wire validated public sync frames to
existing manifest jobs and migrate both native account Undo callers to compact
commands while preserving actual offline intent. No cloud/private-account/provider
change is authorized. Full bounded Saved/export/legacy/installed/device/deployment
gates remain open until their own proof; local producer wiring is not a broad launch.

Workflow: [x] ground; [x] re-run old public 501 support probe red; [x] two sketches;
[x] cross-judge/selection; [x] parent implementation; [x] actual backend/native proof;
[x] review/document; commit follows the staged review. Consultants write only their own `/tmp` files, read-only.

## Grounded current paths

`librarySync.applyBatch` verifies Clerk+capability, validates frame/size, computes the
unchanged syncBatchDigest and checks current stream. It then synchronously applies
all operations and commits ordinary receipts. Folder delete reads take501 and
returns folder_too_large over500. Folder restore uses owner legacy deletion marks
and a bounded <=500 requested array. Existing installed clients can decode inline
receipts only. Current native new freeze already isolates folder operations, but
old frozen backups can contain one folder plus ordinary writes. IDs alone do not
prove such a backup was never applied. No mutation may guess/rewrite that history.

Internal `prepareFolderManifest` records the original folder/epoch/name and schedules
50-row scan steps. `holdFolderFrame` binds one exact folder operation to its pending
stream proof including content intent digest. Scans currently stop prepared;
`commitPreparedFolderDeletion` must be called separately. It publishes logical
visibility and exact held terminal receipt atomically. Restore reserves the same
owner deletion operation via `beginFolderRestoration`, stages four identities per
transaction, then publishes exact counts and materializes. Recovery currently
handles scanning/restoring/expiring/normalization, not stranded prepared delivery.
Workers check owner/generation. Public adapters do not invoke these domain entries.

`beginFolderRestoration` uses authoritative captured deletion name and member set,
not command.hadithIds. Restore visibility currently does not create the
`librarySyncFolderKeys` alias `restore:<deletionId>` that later local-folder commands
need. That alias must commit with visibility and reject conflicting rebinding.
Current legacy alias helpers are private in `librarySync.ts`; shared ownership is
needed when transition code writes the same alias.

Both production native `send` adapters call librarySync:applyBatch. Account folder
delete captures a full cached hadith ID array for the five-second Undo closure;
Undo sends folder_restore(deletionId,name,hadithIds). Guest local Undo needs its
local identities and stays unchanged. The current account payload rejects >500 IDs.
Projection folds pending/frozen/confirmed changes over owned Saved. It can recover
pre-delete membership from an earlier local delete in the same fold without storing
a second member array; it must not guess after the authoritative base already moved.
A later membership move, same-folder unassignment or last-facet removal must supersede
that local Undo. Already accepted manifest restoration still waits for real Saved.

## Required shape and compatibility

Choose an explicit new-client protocol boundary. Compare A: a versioned public frame
endpoint for current native callers, retaining the old endpoint only for genuinely
installed clients; B: binding-negotiated protocol2 using a defaulted optional binding
field and one apply endpoint. Old capabilities/schema and old inline receipt replay
must be truthful. No current internal caller should remain accidentally on the old
path. Do not infer client support from request content alone.

For new isolated deletes, resolve actual owner folder, prepare and hold in one
mutation; jobs automatically commit when prepared. Replays return exact same pending
or committed proof. Transient structural/owner busy work preserves the frozen request
for retry; terminal missing/stale/expired outcomes are explicit. Pending is never ACK.
For new manifest Undo, begin/reserve and hold in one mutation; use authoritative
membership/name, permit no identity injection, and create destination alias at final
visibility. Missing retained authority is recoverably unavailable and creates no folder.

Old mixed frozen requests need an exact no-effect migration rule. One candidate is a
new-client-only batch_requires_split receipt for every exact operation, committed
before any business effect. The client requeues original commands unchanged only
from that exact direct/polled receipt, persists ACK intent, ACKs it, then sends isolated
frames. Unknown/historical cursor adoption never proves unsent original work and must
not auto-replay it. Preserve operation order, IDs/revisions, sources and later writes.
Never split a request that may already have committed through the v1 stream.

Migrate both account Undo callers to empty hadithIds plus captured deletion ID/name;
no new full-ID array in UI or persisted queue. Existing old inline restore commands
still need an honest compatibility path; do not manufacture a manifest from the
client's list. Existing owner legacy deletion marks can remain bounded compatibility
for this unit only with an explicit remaining transaction/read-scale gate, or propose
a fully specified bounded conversion if justified. Its metadata lacks a trusted
server deletion-commit timestamp; do not call mark._creationTime that timestamp after
replace, reset unknown old retention or invent absent original Saved row identity.

For immediate offline compact Undo, preserve local intent from earlier delete in the
same projection fold. Track each item's last local folder deletion operation rather
than storing another identity list. A later membership write or last-facet removal
clears that local authority; a later folder delete/restore must not resurrect older
membership. When the owned Saved base advances and original local authority is absent,
show no guessed restored membership until the real result arrives. Keep names and
same-name destination behavior consistent; preserve guest/local Undo separately.

Keep all existing receipt ownership, intent fingerprints, journal, Saved barrier,
ACK, retention, deletion and export protections. Do not change syncBatchDigest.
Wire types derive from real Convex validators. New schema/validator source is local;
no convex dev/codegen deployment without action-time approval.

Rubric1-5: exact old/new client and mixed-frame truth; public job/Undo idempotence and
alias visibility; native compact/offline behavior with no overwritten moves; bounded
work/ownership/deletion/source compatibility; interface depth and executable proof.
Read architect runner-prompt/rationale-template and screen design red flags.
