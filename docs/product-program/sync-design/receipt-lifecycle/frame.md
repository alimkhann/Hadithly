# A2 receipt lifecycle design frame

October 18. The preceding goal turn made progress: commit a21300c added the local
server/native core, real-store evidence and independent review. This next unit
removes the routine-sync lifetime limit before production integration.

## Phases

- [x] Ground current core and the full A2 contract.
- [x] Compare two structurally distinct complete receipt lifecycle designs.
  Both independent workers failed at the usage limit; parent supplied both.
- [x] Parent synthesis recorded in decision.md.
- [ ] Independent cross-judge, unavailable at the account usage limit.
- [x] Implement the chosen contract on server and both native apps.
- [x] Verify local replay/ack/backup/compaction/account/undo transitions through
  actual Convex functions and native stores; record precise limits in
  `../../../LIBRARY_SYNC_PROTOCOL_VERIFICATION.md`.
- [ ] Integrated transport/process interruption and suspended-commit cancellation.
- [ ] Review, commit verified work and retain actual auth/device gates.

## Shared candidate task

Design the smallest complete lifecycle replacing the provisional 10,000-batch
lifetime cap and indefinite per-operation/batch receipts in a21300c. Write caller
usage first, types/state transitions, module ownership, pseudocode, failure table
and rationale. It must fit the existing immutable frozen batches, exact per-op
receipts, durable account partitions, server-derived JWT owner plus opaque binding,
local session generations and captured write contexts. Do not alter auth UI or
accept a client user identity. Convex remains the only API.

Read librarySync.ts, librarySyncPolicy.ts, librarySyncMarks.ts, schema sync tables,
Swift GuestMergePlanner/GuestDataStore, Android LibrarySync/GuestStore, and the
A2 decision and verification record. No cloud/provider/account calls. Do not edit
implementation or shared candidate files. Each candidate owns its assigned file.

Required cases: arbitrarily many routine positions without hitting a lifetime
limit; bounded per-call database work; retry after lost response; crash before/
after local settlement and server acknowledgement; old backup with frozen batch,
with pending work but no frozen batch, or a locally settled older sequence;
duplicate/concurrent activates and multiple devices; account switch/erasure;
conditional facet/folder undo after detailed receipts are compacted; no replay
resurrecting an add after a later delete. Preserve available original losing private
content, including when reconciling older local state. Do not infer exact acceptance
from a query snapshot or silently discard an unfamiliar batch. State impossible
backup guarantees honestly. No mandatory manual conflict queue.

## Parent/judge rubric, 0-5 each

1. Old requests cannot reapply effects after receipt compaction.
2. Crash/ack/backup recovery preserves available original intent without stalling.
3. Storage and each call's work remain bounded for routine reading positions.
4. Verified ownership and multiple devices stay independent; erasure stays final.
5. Conditional undo and per-operation outcomes retain their actual meaning.
6. Fits a small, implementable native/Convex interface with explicit proof seams.
