# Receipt lifecycle decision

Parent comparison: candidate A is the base. Both independent design workers
failed with the account usage limit before producing artifacts. The two checked-in
alternatives are parent-authored; independent cross-judging remains open. Do not
present them as model consensus or a passed review.

| Criterion | A, acknowledged stream | B, per-entity CAS |
| --- | ---: | ---: |
| No replay after compaction | 5 | 5 |
| Crash/ack/backup recovery | 5 | 4 |
| Routine storage/call bounds | 5 | 5 |
| Ownership/devices/erasure | 5 | 5 |
| Undo and exact outcome meaning | 5 | 3 |
| Small interface and proof seams | 4 | 2 |
| Total | 29 | 24 |

A retains the existing newest-clock merge policy and exact in-flight receipts.
B changes every reader/write boundary to causal bases and complicates guest merge
and folder deletion. Graft B's use of last domain operation identity for conditional
undo; detailed operation ledger rows are not undo authority after compaction.

Use two RPCs, apply and acknowledge. Each response can carry the current cursor,
so there is no mandatory inspect call. Apply returns an exact committed receipt
only for the matching open sequence and immutable batch. Otherwise it returns a
reconciliation cursor without effects. Acknowledgement closes only the matching
active sequence/batch/digest, or returns the cursor unchanged. New native batches
cannot freeze while an acknowledgement remains durable.

When a cursor conflicts with a local frozen batch, preserve its available original
changes as historical recovery, clear only that frozen batch and reconcile to
closedThrough+1. If a different active server batch exists, persist its receipt
proof acknowledgement before proceeding. Do not relabel unknown old acceptance as
preserved, rewrap an old sent change under a new sequence, or discard pending
intents that were never frozen. An old backup cannot recover newer original local
content that the backup never contained; no such guarantee is claimed.

A late acknowledgement response may modify only the matching still-pending local
acknowledgement. An erased native partition is never recreated by settlement.
Every cursor and committed receipt must match the captured server owner and local
installation key, with safe finite integer sequences. One current stream cursor
and at most one bounded receipt set replace the lifetime batch/operation ledger.
Per-domain conflict marks and folder aliases remain separate domain-state work.

Implementation and local evidence may proceed. Independent review and the full
A2 real-auth/cross-device/deployment gates remain open.
