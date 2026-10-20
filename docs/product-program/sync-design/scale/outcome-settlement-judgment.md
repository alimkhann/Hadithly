# Outcome settlement cross-judge

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Mode: read-only architect/arena cross-judge

## Verdict

Use Candidate A as the base, but remove its pre-settlement journal source attachment. At this no-prune milestone the partition already owns the durable original. Its atomic settlement save can replace `collectingOutcome` and the matching frozen change with a compact `LibraryRecovery.outcome` pointer plus the locally available original. The journal remains immutable evidence and is retained in full.

Graft Candidate B's deterministic settlement identity, lost-wake handling, exact ACK replay table and no-recreation checks. Do not graft its mutable certificate lifecycle or ACK-confirmed journal state.

## Scores

| Criterion | A | B | Judgment |
| --- | ---: | ---: | --- |
| Exact authority and original preservation | 4 | 5 | Both bind exact authority and matched intent. A should preserve the original in partition recovery rather than duplicate it into the journal. |
| Durable crash, replay and ACK safety | 4 | 4 | Corrected A has a simple two-state replay: frozen before partition save, recovery pointer plus ACK after. B handles every seam but creates four cross-store states. |
| Saved, projection and Undo correctness | 5 | 5 | Both wait for the owned Saved revision, avoid guessed restore overlays and preserve the original Undo deadline. |
| Bounded state, export and erasure consistency | 5 | 3 | Corrected A adds no collected arrays or mutable journal lifecycle. B adds certificates, source records, ACK markers, migration and export/erase work. |
| Interface depth and executable proof scope | 5 | 3 | A keeps one partition-owned transition behind the store. B makes the coordinator reconcile two mutable authorities. |

Totals: A 23/25. B 20/25.

## Why journal source attachment is unnecessary now

The current matched path keeps the exact original in `frozen.changes` until settlement. The current historical path already archives its original into partition recovery before collecting. Settlement reads and validates the durable terminal journal first, then writes one copied partition atomically.

For matched work, the next partition can contain:

```text
LibraryRecovery.outcome(
  collectionKey,
  authorityDigest,
  terminalStatus,
  expectedCounts,
  collectedCounts,
  original: LibraryLocalChange?
)
```

That same partition save clears only the exact `collectingOutcome` and matching frozen batch, advances sequence once, preserves later pending writes and mappings, and writes exact ACK intent. The three crash positions are safe:

- Before the partition save, frozen plus collecting state remains and settlement retries.
- During a failed AtomicFile/SwiftData save, the old partition remains authoritative.
- After the save, the compact pointer and original are durable with ACK intent; a lost ACK only retries that exact ACK.

The retained journal already supplies bounded evidence pages by `collectionKey`. Adding original source to its header does not improve any of these states. It instead makes the journal mutable, bumps the export clock, requires installed schema/export/erasure changes, and creates a new failure between source attachment and partition save. Those costs belong only if a later pruning design makes journal-owned source necessary.

The optional original is bounded by existing admission. A restore can still carry up to 500 requested IDs, so this does not close the old restore-size or whole-partition scale gates. It adds no collected member arrays.

## Base shape and minimal grafts

1. Add one deterministic recovery identity from `collectionKey + authorityDigest + terminal checkpoint digest`. Replaying the same settlement must find the existing recovery entry and ACK intent rather than append or advance again.
2. Re-read the persisted journal summary inside the store transition. A caller checkpoint is only a hint. Require exact binding, generation, receipt ID/revision/phase, expected totals and terminal classification.
3. For matched origin, require the current frozen batch fingerprint, full operation equality and exact command kind. Same IDs with different commands must not confirm or discard the original.
4. `complete` requires verified exact totals. A restore with superseded or missing identities records recovery despite complete collection. `proof_unavailable` never settles. `detail_unavailable` may settle only under the explicit policy with a compact pointer, collected-prefix counts and matched original.
5. Historical origin never invents an original. Keep the already archived historical recovery and add only the deterministic outcome pointer when useful.
6. Require an owned Saved snapshot at or above `committed.revision.saved`. Waiting is an idle state, not failure or polling. Persisted Saved delivery must wake only the same active owner/session/generation.
7. Preserve later pending writes, restore folder mapping conflict checks, delete Undo authority and the original deadline. Do not create a manifest membership overlay.
8. Persist partition settlement and ACK intent before network ACK. On reopen, the existing ACK branch retries. A stale callback cannot recreate an erased partition or acknowledge another owner.
9. Keep all journal rows. No ACK-confirmed marker, source attachment, pruning flag or retention claim enters this milestone.

## Required proof

- Complete delete/restore, partial restore, `detail_unavailable`, and blocked `proof_unavailable`, with exact totals and no member arrays in partition JSON.
- Same IDs with a different command, missing/mutated frozen source, historical adoption, owner switch and erasure.
- Saved revisions below, equal to and above the barrier through the real facade callback. Prove no busy loop, no lost wake and no stale-owner wake.
- Failure before/during partition save, reopen after save before ACK, lost ACK reply, duplicate settlement and late mismatched ACK. Sequence, recovery and mappings change once.
- Later queued writes and delete Undo remain intact; restore never projects requested membership.
- Recovery/export resolves the pointer to retained journal pages after ACK and reopen. Full journal export remains bounded.

## Gates retained

Success pruning, ACK-confirmed lifecycle, retention policy, old Undo migration, 500-ID restore source size, whole-partition and full Saved/export bounds, public producer cutover, physical/cross-device proof, deployment and the full A2 gate remain open.
