# Outcome settlement final review

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Scope: read-only final source and evidence recheck

## Result

No remaining concrete implementation defect was found in the reviewed settlement slice. The expanded policy, ownership, reopen, export, erasure and Android write-fault evidence matches the partition-owned contract.

The iOS partition save-failure seam remains explicitly unproved. The removed SQLite trigger was not a valid failure injection for SwiftData because it caused Core Data's fatal optimistic-lock path rather than a recoverable save error. This is an evidence gap, not proof of a source defect.

## Source and policy recheck

- Complete delete and restore require exact terminal totals. Restore with superseded or missing identities records compact recovery. `detail_unavailable` records the collected prefix plus matched original; `proof_unavailable` makes no partition mutation and creates no ACK.
- Collecting and verifying checkpoints remain nonterminal. Incomplete complete-counts fail closed.
- Matched settlement rechecks the full frozen operation, receipt ID/revision/phase and intent digest. Missing or changed frozen source and restore-alias conflicts fail before mutation.
- Historical settlement never invents an original. It preserves the earlier historical recovery and adds a journal pointer with `original: nil`.
- The owned Saved barrier accepts only finite integral versions for the same owner. Below-barrier state stays untouched; facade persistence wakes the captured coordinator without polling.
- The atomic partition transition preserves later pending work, mapping consistency and original delete deadline, advances sequence once, and persists exact ACK intent. Duplicate settlement returns the same state.
- Android reads the journal generation under the store mutex and commits the copied partition through AtomicFile while still serialized. The new permission-failure fixture prevents the parent-directory write, reopens the unchanged frozen/collecting state, then retries once.
- iOS reads exact scope/header generation and checkpoint on `MainActor`, then saves one copied SwiftData partition. Foreign namespace and erased owner paths cannot settle or recreate partition/journal state.
- Reopen and export retain the unavailable journal prefix honestly. Export still distinguishes `detailComplete: false` and preserves the matched original through partition recovery without adding collected arrays.

## Evidence checked

- `/tmp/hadithly-outcome-settlement-ios-verified.log`: 78 tests, zero failures. This includes the pure terminal matrix, actual unavailable reopen/export, foreign scope, erased-owner non-recreation, coordinator wait/wake, retryable ACK and retained journal coverage.
- `/tmp/hadithly-outcome-settlement-android-verified.log`: 61 connected emulator tests, zero failures.
- `/tmp/hadithly-outcome-settlement-android-write-fault.log`: focused real parent-directory permission failure passes and proves unchanged reopen plus one successful retry.
- `git diff --check` passes.

## Remaining evidence and product gates

- iOS SwiftData save failure after journal read but before partition commit is unproved. A future supported injection should fail `ModelContext.save()` without corrupting the persistent store or triggering Core Data fatal handling, then prove frozen/collecting state survives reopen.
- The local tests do not prove OS termination at each instruction boundary. Android AtomicFile failure/reopen evidence is strong, while actual process-kill tests remain open.
- ACK-confirmed journal lifecycle, dependency-aware pruning, retention, old manifest Undo migration and public producer cutover remain separate work.
- The 500-ID original restore and whole-partition/Saved/export memory bounds remain open scale gates.
- Hosted account, cross-device, physical-device, deployment and full A2 gates remain open. These local native passes do not close them.

The settlement implementation is ready for the parent's verification record and next bounded unit. It should be described as a local native settlement pass with the iOS save-failure limitation retained.
