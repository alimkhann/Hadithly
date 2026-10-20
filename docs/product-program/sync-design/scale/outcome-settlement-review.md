# Outcome settlement implementation review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only architect Phase D review of the first settlement implementation

## Result

No concrete implementation defect was found in the reviewed matched partial-restore path. The current source follows the corrected partition-owned design: it reads the retained journal without mutating it, computes settlement on a copied partition, and persists recovery, mapping, sequence and ACK intent in one partition write.

The first green proves one important path on each platform. It does not yet prove the other terminal policies, cancellation/crash seams, historical ownership, delete Undo, or stale-session behavior listed below. Those remain required verification, not confirmed defects.

## Source review

- Both pure `settleCollectedOutcome` functions reconstruct `LibraryManifestProof`, require exact committed/binding/client identity, compare the persisted `collectingOutcome`, and revalidate matched frozen content through full operation equality plus intent digest. Same IDs with a different command cannot settle through this branch.
- `complete` requires exact verified totals. `proof_unavailable` returns a blocked result with no mutation. `detail_unavailable` remains recoverable and never changes its checkpoint to complete.
- Settlement waits for a finite, integral, owner-matching Saved snapshot at or above `committed.revision.saved`. No requested membership list becomes a projection overlay.
- Partial restore recovery retains the full locally available original plus journal authority/checkpoint, without copying collected member rows into partition JSON. Historical origin carries no invented original.
- Restore mapping conflicts fail before mutation. Later pending writes remain in `pending`. Delete recent receipt uses the original operation timestamp, so settlement does not restart the Undo deadline.
- Idempotence is explicit: the exact persisted ACK plus advanced sequence returns `settled` without appending recovery or advancing again. A different recovery record for the same journal key fails closed.
- iOS re-reads scope, header, generation and checkpoint before copying and saving the partition on `MainActor`. Android holds the store mutex while `settlementCheckpoint` validates current SQLite scope/header generation and while `persistLocked` commits the copied AtomicFile payload.
- Android's `persistLocked` keeps AtomicFile `startWrite`, write and `finishWrite` under the same store mutex. A failed write retains the old partition. A durable write followed by cancellation leaves exact ACK intent for activation/reopen.
- The coordinators check session/generation around network awaits and before settlement/ACK. Saved callbacks persist first, recheck captured owner/session/epoch, reload, then call the coalesced `wake`. A wake arriving while the worker exits sets `requested` and runs after completion, closing the red lost-wake failure.
- Account erasure and owner switch cannot interleave with the local settlement commit on either platform. Later network ACK still goes through the captured coordinator generation and exact persisted ACK comparison.

## Evidence checked

- The supplied red logs reproduce the original lost Saved wake: both platforms remained in collecting/frozen state after the barrier snapshot.
- `/tmp/hadithly-outcome-settlement-ios-first.log` now passes the focused test in 0.258 seconds.
- `/tmp/hadithly-outcome-settlement-android-first.log` now passes the connected emulator test.
- Both green fixtures prove below-barrier waiting, facade-delivered barrier wake, partial restore recovery with original text, mapping, preservation of later pending work, retryable failed ACK, reopen, successful ACK and retained journal rows.

## Required wider proof before handoff

1. Pure policy matrices on both platforms: exact complete delete, exact complete restore, complete restore with superseded/missing, partial `detail_unavailable`, blocked `proof_unavailable`, collecting and verifying checkpoints, malformed totals and owner mismatch.
2. Matched authority attacks: same operation ID/revision with changed command, changed batch digest, wrong phase/manifest/generation, mutated or missing frozen source, stale expected collection and conflicting restore alias. Assert zero partition mutation.
3. Historical adoption: no frozen source is invented, its earlier historical recovery survives, the compact outcome pointer is deterministic, and a foreign owner/namespace cannot resolve the journal.
4. Saved wake races: snapshot below/equal/above the barrier, duplicate delivery, delivery while the worker is exiting, stale owner emission after switch, subscription failure and activation/reopen with an already sufficient cached snapshot. Assert no polling loop.
5. Crash/cancellation seams: before journal read, after journal read but before partition save, injected SwiftData/AtomicFile save failure, cancellation after durable save but before return, app death before ACK, lost ACK response and duplicate ACK callback. Recovery, sequence and mapping must change once.
6. Delete policy: original Undo deadline expired and unexpired, duplicate settlement, later pending work, and reopen. Retain the existing old manifest-Undo migration gate rather than claiming full Undo support.
7. Erasure and reset: deletion intent before settlement, erasure after partition save before ACK, late ACK after account switch, and prohibited partition-only deletion while recoverable journal pointers exist.
8. Serialization/backward compatibility: reopen old partition JSON with no outcome recovery case, export the new recovery pointer and original structurally, and prove no collected arrays or capability/provider fields enter it.

## Gates retained

The one-test first green is not a full settlement gate. ACK-confirmed journal lifecycle, pruning, retention, old Undo migration, 500-ID original restore scale, whole-partition/Saved/export bounds, public producer cutover, hosted/cross-device/physical proof, deployment and full A2 remain open.
