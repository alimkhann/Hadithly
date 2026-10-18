# A2 implementation decision

October 18. Candidate B is the base, with A's exact per-operation receipt rules.
Requested independent judge: gpt-6-sol. A scores 20/30; B scores 24/30. Parent
agrees with the judge's six criterion scores. The larger interface depth is
justified by the complete A2 requirement: signed-in Saved/position writes must
also survive failures, and cannot stay on a separate fire-and-forget path.

## Ownership and caller shape

One native LibrarySync owner accepts session activation/deactivation and library
intents. It owns an account-partitioned durable queue and fenced read projection.
Claiming a guest generation and opening the next generation is a single local
transaction. Frozen batches are immutable. New writes never mutate the submitted
batch. Both current sign-in callers migrate together; clearAll is removed from
the completion path and no longer authorizes data disposal.

The server derives the owner from the verified JWT. An opaque server-issued
binding is checked against that owner before private operations; its response
includes the verified principal so the client can compare the captured Clerk
account before claiming/sending data. No user ID is accepted in request args.
Installed Swift integration source establishes mutable current-session token
fetch/refresh; actual queued-request reassignment remains unproven. The binding
is an explicit guard against that uncertainty, not a claim that it happened.
Both private query payloads carry their server-derived owner, checked with a
local subscription epoch before rendering. Sign-out invalidates rendering first.

## Receipts and recovery

Graft A's exact submitted operation/revision checks. One receipt cannot acknowledge
multiple independent facets. Distinguish semantic preservation, a different cloud
winner, rejected/missing data, and transformed position. Settle only that frozen
operation. Automatically select the existing domain winner while retaining losing
private content for owner-scoped recovery/export; no required manual conflict queue.
Missing dependencies park rather than spin. Folder references are resolved within
the same owner and carry explicit dependency/mapping facts.

A committed batch and its digest/receipts are atomic. Retrying that exact batch
returns its recorded facts, without reapplying an old add after a later remove.
The baseline a21300c used a provisional 10,000-batch lifetime cap. The subsequent
receipt-lifecycle implementation replaces it with monotonic per-installation
acknowledgement and one current receipt set. See `receipt-lifecycle/decision.md`
and `../../LIBRARY_SYNC_PROTOCOL_VERIFICATION.md`; its independent review is open. No time-only expiry makes an old batch
new. Delete/export must cover bindings, ledger, pending and recovery. Never log
capabilities, identifiers, notes or positions in evidence/analytics.

## Phases and proof

1. Implement bounded typed operations, semantic decisions, binding/receipt storage,
   current-model application and deletion/export coverage; run actual Convex tests.
2. Implement real SwiftData/Android durable claims and production coordinator.
   Convert the red diagnostics to run through that coordinator and its real stores.
3. Migrate every Saved/folder/undo/position entry point on both apps, not only guest
   sign-in. Fence the two private subscription projections and remove old ownership.
4. Prove failures, lost responses, deletes/undo, newer edits, equal/newer cloud
   values, invalid targets, account switches, restart and storage failure locally.
5. After concrete tested implementation and explicit development action-time
   approval, verify iOS-to-Android and Android-to-iOS authenticated delivery.

Do not deploy an incomplete new contract or claim A2 from local tests. No new
backend deployment, account creation or private cloud write is currently approved
for A2. The previous development approval was first-reading-specific.

Reject a clearIfUnchanged patch: it still cannot explain skipped/mixed facets or
provide eventual signed-in delivery. Reject inferring acknowledgements from a
subscription snapshot: that hides causality and confuses cloud winners with exact
preservation. Do not start a general sync framework or alter auth UI/config.

The native and server trace reports are historical source snapshots. Use function
names and current source for line locations; some original server line references
predate the final 324-line layout. The copied reports are not new runtime proof.
