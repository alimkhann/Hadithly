# Native outcome settlement contract

October 21, 2026. Read both candidates fully and adopt A with the source-placement
correction. Parent agrees with the independent judge: A 23/25, B 20/25. Two initial
consultant calls hit usage limits; retries produced both complete artifacts. No
implementation delegation or external/cloud/private-account action is involved.

The existing partition owns final sequence and ACK state. The deep store operation
re-reads exact persisted collection authority and immutable verified journal summary,
then computes a copied partition. Matched origin requires a fresh frozen fingerprint,
full operation equality and exact operation ID/revision/phase. Historical origin
retains its separately archived original and never invents a match. Conflicting
restore aliases fail before mutation. Later pending work remains untouched.

Complete collection requires exact totals. A partial restore retains its original
plus a compact authority/checkpoint reference in partition recovery. Detail-unavailable
may settle as explicit recovery with its collected prefix and matched original.
Proof-unavailable never authorizes ACK. All journal rows remain exportable and no
collected member array enters partition JSON. Locally available originals remain
bounded by current command admission; the existing 500-ID original restore and
whole-partition scale gates remain open.

A persisted owned Saved snapshot must reach the committed Saved revision before
settlement. Below it, return a waiting state without polling or a failure notice.
Successful owned Saved delivery wakes the existing coalesced coordinator worker.
The subscription's owner/session/epoch guard and coordinator generation check protect
that signal. Activation/reopen also re-evaluates the durable barrier.

One atomic SwiftData/AtomicFile partition write removes only the exact frozen and
collecting state, preserves recovery/source and mappings, advances sequence once,
and persists exact ACK intent. The already-durable journal precedes this write;
network ACK follows it. Before-save failure keeps frozen source. After-save failure
or lost ACK retries the persisted ACK. Duplicate transitions are identified by exact
committed proof and cannot advance twice. Original delete Undo deadline is not
restarted. Projection never guesses the restored identity set.

Graft B's exact replay cases, lost-wake analysis and no-recreation checks. Reject
journal source attachment, settlement certificates and four-stage mutable lifecycle
for this milestone. They add cross-store commits without strengthening the current
atomic original-plus-ACK write. Partition deletion without joint journal erasure
must remain prohibited for recoverable originals or migrate them first. Current
production removal is account erasure; the independent reset helper is test-only.

Keep all journals. ACK confirmation metadata, dependency-aware pruning and retention
are the next separate integration requirement, alongside manifest Undo/public
producer/read/export cutover and actual hosted/device proof. No broad readiness or
full A2 completion claim follows from this boundary.
