# A2 coordinator outcome collection

October 20, 2026. Continues `605d08b`. Both real native coordinators now drive the
durable journal from registered outcome-page transports. They stage exact manifest
receipts without acknowledging or sending later changes. Final settlement, full
export and pruning remain unimplemented. This does not enable the public async
producer, prove app-level large-folder support, or finish A2. No deployment,
private account call, paid generation, production migration or push was performed.

## Implemented flow

A new optional `collectingOutcome` partition field stores the bounded terminal
receipt and its local origin. Older partitions decode with no collection. A direct
accepted receipt must match the frozen single operation's batch, ID/revision and
command kind. Its origin records the exact intent fingerprint and retains the
frozen source. It cannot advance the sequence or create ACK intent.

Reconcile, retirement and acknowledgement cursors validate manifest shape/counts
before mutation. A matching observed pending proof plus frozen fingerprint retains
the original as matched. Other restored-copy receipts archive any original as
historical recovery before collection; matching IDs alone cannot confirm a different
command. Polled terminal responses use the same split. Freeze and further adoption
are blocked while collection is active. The owner-bound store checks remain in place.

The receipt parser is shared by staging and journal binding. Invalid negative
categories, mixed manifest receipt sets and mismatched direct operations fail before
an original is released. The previous blanket receipt rejection is replaced by this
durable no-ACK phase, not by ordinary successful settlement.

Both coordinators check collection before pending poll, ACK, freeze or send. Each
iteration drives one fetch/verification step through the existing journal and checks
captured session generation across awaits. Swift and Kotlin production adapters call
`librarySync:outcomePage` with the current binding and generated request shape. They
make no direct content-provider calls and pass no user identity argument.

At a complete or unavailable journal, the current coordinator stops with its existing
failed state, retaining the phase and all original data. It does not repeatedly
fetch the completed result or send the queued next operation. This is an intentional
cutover guard while final settlement/export are missing, not a finished user flow.
The public backend producer still cannot issue these receipts through ordinary
`applyBatch`; this code has not been deployed.

Projection keeps a matched delete's optimistic overlay only below the committed
Saved revision. During collected restoration it uses the owned Saved snapshot and
newer local changes, never the command's entire guessed member list. A partial
authoritative restore therefore cannot display every originally requested member
as restored. The frozen source remains available for later exact settlement.

## Executed proof

| Boundary | Result | Evidence |
| --- | --- | --- |
| iOS core/store/coordinator, presentation and Settings | 68 pass | `/tmp/hadithly-outcome-coordinator-ios-verified.log`, `.xcresult` |
| Android actual store/coordinator instrumentation | 48 pass | `/tmp/hadithly-outcome-coordinator-android-verified.log` |
| Generated native wire source | Pass | `python3 scripts/generate-library-sync-wire.py --check` |

The new actual coordinator fixture receives a 501-member committed result, persists
two pages, injects a network failure at ordinal 100, deactivates and reopens the real
store. A fresh coordinator resumes at 100, collects and verifies the remaining rows,
and preserves the exact partition, frozen source and later queued change. Both hosts
observe one send, zero ACK calls and a complete journal. This is controlled transport
evidence, not a hosted/private-account proof.

The revised native guard fixtures assert durable collection and no ACK through
reconcile, retirement, forked pending completion and next-slot ACK responses for both
manifest kinds. The direct fixture retains its exact matched fingerprint and survives
JSON roundtrip. A malformed negative-count cursor leaves the entire prior state
unchanged. A real projection fixture shows no guessed restore before the owned base
arrives and only the one successful member afterward. An initial iOS fixture needed
MainActor isolation to call the actual projection; the final run includes that fix.

The read-only implementation review found no concrete blocker in this collection
phase. It did not execute tests or review final settlement/export/pruning. Full report:
`product-program/sync-design/scale/outcome-coordinator-review.md`.

## Next required cutover

Recheck the persisted matched intent before releasing the frozen source. Durably
record exact partial/unavailable recovery and discover/export every retained journal,
including orphan evidence. Apply the authoritative Saved revision barrier, then
persist settlement/ACK intent before acknowledging. Define unavailable-detail
settlement explicitly; unavailable proof cannot authorize ACK. Add Undo-aware success
pruning without deleting recovery evidence. Test all direct and adopted routes through
those actual final steps on both apps.

The public producer, bounded Saved read/export, old timestamp/list-only Undo and
installed stream/client/schema migration, native whole-file cache/pending scale,
physical/authenticated cross-device delivery, hosted limits and fresh deployment
approval remain open. All other content, localization, store and release gates stay
open. The full product program remains active.
