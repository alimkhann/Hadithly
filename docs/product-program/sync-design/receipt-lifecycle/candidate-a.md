# Candidate A: one acknowledged stream per account installation

Parent-authored fallback candidate. Both requested GPT design workers failed at
the account usage limit before producing an artifact. This is not an independent
agent result.

## Caller first

The native partition freezes one immutable batch with its persisted installation
key and next sequence. Sending does not mutate it. The server atomically applies
that sequence and keeps its exact digest/receipts. The native store atomically
settles the receipt, retains conflicts and persists an acknowledgement. Only then
does it acknowledge the server. Acknowledgement clears detailed receipts and
advances a permanent content-free stream high-water mark. New batches start only
after acknowledgement/reconciliation has completed.

## Shapes and state

Server stream key is verified owner plus installation UUID, never a client owner.
State: closedThrough, optional active {sequence, batchID, digest, receipts}.
Exactly one active batch per stream. All counters are safe integer numbers.

Native state: pending, optional frozen {sequence,batch,originalChanges}, recovery,
optional ack {sequence,batchID,digest}, nextSequence and installation key. A local
settlement commit removes only that frozen intent and writes ack in one commit.

RPC shapes:
- apply(capability, installation, sequence, immutableBatch) returns accepted exact
  receipt, closed sequence, occupied-by-another-batch, or gap/server-behind.
- acknowledge(capability, installation, sequence, batchID, digest) returns closed
  high-water mark, including on a repeated acknowledgement.
- inspect(capability, installation) returns closedThrough and the active receipt
  proof, if any. It is account-bound and contains no raw note contents.

The protocol can fold inspect into apply responses and acknowledgement conflicts
so ordinary callers need only apply and acknowledge. Do not infer receipt facts
from the current Saved query.

## Failure transitions

- Crash before apply: same frozen batch is sent.
- Apply committed, response lost: same sequence and digest returns same receipts.
- Native settle failed: frozen batch remains, no acknowledgement is sent.
- Settle committed, crash before/during ack: persisted ack is retried idempotently.
- Ack committed, response lost: closedThrough confirms it without retaining receipts.
- Old request at/below closedThrough: return closed; never apply again.
- Old backup with frozen data at a closed sequence: archive available original
  changes as historical, then advance; do not pretend to know exact prior outcomes.
- Old backup proposes a different batch at the active sequence: return active proof;
  archive the unfamiliar local frozen changes as historical, durably ack the active
  receipt proof, then advance. Its current cloud effects already committed. This
  does not recreate original local content absent from the restored backup.
- Native ack refers to old/unknown state: reply with current stream cursor; reconcile
  explicitly rather than retry forever or advance the server to an invented number.
- Server-behind gap: no effects. Archive available ambiguous local frozen intent;
  reconcile to server next sequence. User edits pending but not previously frozen
  may then use the next actual sequence. Do not silently reapply a possibly sent
  frozen batch under a new sequence.
- Multiple devices have independent keys. Same-key forks serialize through the
  active sequence and retain the losing local original intents for recovery.
- Account deletion removes stream and invalidates the binding. Late enqueue cannot
  recreate a native partition. A new server user has a different owner key.

## Undo without operation receipts

Store the last operation kind with each existing domain conflict mark. A facet
undo requires its exact deletion ID and matching remove kind in the current mark.
Folder restore requires a matching folder deletion mark and per-member deletion
marks. Its partial result remains explicit. These domain marks survive receipt
compaction and change on later writes. Do not consult compacted per-operation rows.

## Bounds and rationale

One constant-size cursor plus at most one bounded receipt set per installation.
No lifetime batch count. Each batch remains <=50 operations/128KiB, each folder
operation has the existing explicit500-member boundary. Per-domain conflict marks
and folder aliases still scale with domain identities, not routine position writes.
Large-domain cleanup remains its own implementation gate.

Retain no lifetime operation ledger: immutable batch sequence owns retry identity.
Within an open sequence, changed intent cannot reuse the sequence. After closing,
old sequences are permanently fenced. Last domain deletion marks own undo authority.

Rejected TTL-only receipts: after expiry an old add could become new. Rejected
saving all commands on server: duplicating private note contents is unnecessary.
Rejected advancing an unrecognized old batch silently: exact outcome is unknown.
