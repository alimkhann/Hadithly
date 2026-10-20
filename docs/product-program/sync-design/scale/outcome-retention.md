# Native outcome retention contract

October 21, 2026. Parent read both sketches fully and agrees with the independent
judge's 20/25 tie: choose corrected A for fewer persistent authorities. Keep a
single defaulted manifest ACK binding and fair sweep cursor in partition JSON,
plus optional ACK/prune metadata in existing journal checkpoint JSON. No new model,
table, certificate ledger, permanent pruned tombstone or member array is needed.

Only exact matched complete success produces the bounded ACK binding alongside
ACK intent. Partial, unavailable and historical outcomes retain all evidence.
Before applying an ACK response, compute and validate the copied partition cursor.
For its exact persisted link, require owned reply/ACK identity and closedThrough
at least the requested sequence. Save the journal's first local ACK time before
adopting the copied cursor/clearing the link. A failed partition save leaves a
retryable ACK and reuses the original timestamp; no send/snapshot guesses ACK.

A candidate needs complete exact totals, explicit ACK proof, at least 30 local
calendar days after that ACK, an extant owned Saved revision and no current Undo,
queued/frozen command, collecting/waiting/ACK or recovery dependency. Unknown old
proof and partitionless journals remain retained. Clock rollback postpones cleanup;
user-adjustable wall time is not tamper-proof elapsed-time or a certified SLA.

Claim under the same native writer serialization as enqueue and settlement. Mark
irreversible pruning and remove at most 50 verified ordered identities in one
transaction/save, updating its durable removed ordinal and export clock together.
Further steps resume from that ordinal. Final deletion also removes header and
inventory atomically. A fair persisted inventory cursor advances past retained
headers, does not skip a half-pruned candidate, wraps at end and cannot starve an
eligible tail behind 50 retained headers. Each step reads <=50 header summaries
and deletes <=50 members. A small yielded idle-coordinator budget resumes it.

Export started earlier fails its mutation fence; export during pruning fails
explicitly. No surviving subset is exported as complete. Old optional fields decode
as absent and grant no ACK proof. Erasure/generation checks reject late callbacks
without recreating an owner, scope or header. Storage errors pause cleanup.

Reject A's positive-local-authority admission rule. A restore already durable before
claim protects its parent evidence even after the five-second UI deadline. A NEW
restore after irreversible aged pruning may enter the ordinary queue and reach
Convex; preserve its original and collect the actual server result independently.
Do not fabricate expiration from absent local facts or reverse partial deletion.
No permanent tombstone or new admission policy is introduced.

Graft B's replay cases, exhaustive dependency extraction and explicit export state.
Reject its separate ledger/queue/schema migration. Current whole-partition dependency
scans and cache/export size remain open scale work. Manifest Undo/public producer,
old installed streams, iOS save-failure, clock trust, hosted/device and full A2 gates
remain open. This component is not a complete product cutover.
