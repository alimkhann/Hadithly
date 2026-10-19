# Library sync receipt lifecycle, local verification

October 18, 2026. Continuation of the A2 core in `a21300c`. Full A2 integration,
deployment and real account/device delivery remain open. The receipt protocol
received an independent source review on October 19; see below.

## Change and reason

The first local core retained every batch/operation receipt and stopped at 10,000
batches over an account's lifetime. A focused test against the actual mutation
reproduced `SYNC_RECEIPT_LIMIT`; evidence is
`/tmp/hadithly-sync-lifetime-red.log`. This limit would eventually stop routine
reading-position sync. It is removed.

Each verified account now has a separate stream for each native installation key.
The server stores a closed-through sequence and at most one current bounded receipt
set. Applying a new sequence commits its effects and exact receipts atomically.
The native store settles those receipts, retains conflicts and durably records
acknowledgement in the same local commit. Only then does it acknowledge the server.
Acknowledgement advances the cursor and removes the detailed receipt set. Repeating
either request is safe; a closed sequence never reapplies an old add after a later
remove. A new native batch cannot freeze while an acknowledgement is pending.

A restored backup can propose an old closed sequence, a different batch at the
occupied sequence, or a sequence beyond the server cursor. Reconciliation performs
no private write. The native store preserves the available original frozen intent
as historical recovery, keeps never-frozen pending edits and adopts the actual
cursor. If another batch occupies the sequence, its committed receipt proof is
durably acknowledged before continuing. Unknown old acceptance is never called
preserved and an old sent intent is never automatically rewrapped under a new
sequence. A backup cannot restore newer original local content it never contained.

Binding, captured owner/session/generation and exact operation/revision checks stay
in place. Nested cursor receipt owners and installation keys are checked before
local settlement. A late acknowledgement can settle only its matching still-pending
acknowledgement. An erased local partition is not recreated by either response.

Conditional undo now uses the current domain mark's exact deletion ID and command
kind, independent of detailed receipts. Newer cloud notes and folder moves remain
protected. A folder undo older than the deletion changes nothing. Partial folder
restores keep explicit restored/superseded/missing outcomes.

The old batch, operation and lifetime-count tables and native batch-only settlement
APIs are removed. Four server tables remain for bindings, streams, domain marks and
folder aliases. Account erasure covers these in the local fixture; export includes
the active stream receipt proof but no binding capability. Existing large-account
erasure/export work remains open.

## Bounds

Each batch admits at most 50 operations and 128 KiB. Native freeze and server
admission allow at most one folder delete/restore per batch, retaining a second
such intent for the next batch. That prevents multiplying the existing 500-member
folder boundary across 50 operations in one transaction. Repeated position writes
reuse the stream and collection mark; receipt storage does not grow per reading.
Stream rows scale with installations, and domain marks/aliases scale with domain
identities. This is not proof of cleanup or unlimited account cardinality.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Backend strict typecheck | Pass | `/tmp/hadithly-sync-stream-final-typecheck.log` |
| Complete backend suite | 383 tests, 34 files pass | `/tmp/hadithly-sync-stream-final-backend.log` |
| Generated native wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| iOS GuestMergePlannerTests | 23 pass | `/tmp/hadithly-sync-stream-final-ios.xcresult`, `.log` |
| Android GuestMergeRaceTest | 12 pass | `/tmp/hadithly-sync-stream-final-android.log` |

The backend tests execute actual local Convex functions, including a fixture that
starts at closedThrough=10,000 and then runs 100 apply/ack cycles for positions.
It ends with one stream row, no active receipts, one progress row and one domain
mark. This is 100 executed cycles after a seeded cursor, not 10,100 executed cycles.
Other cases prove exact retry before ack, repeated ack after compaction, no old add
replay after removal, occupied/gap reconciliation without effects, wrong-JWT apply
and ack rejection, and conditional facet/folder undo after detailed receipts are
gone. Unsafe nested clocks and multiplied folder fanout are rejected.

Both native suites use the real stores with controlled transports. New cases prove
acknowledgement survives reopening, freezing waits for it, a stale ack cannot clear
a newer frozen batch, a closed-backup original remains recoverable while a fresh
pending intent remains queued, an occupied stream's receipt proof is retained,
a nested wrong owner is rejected, and a second folder fanout remains pending.
Earlier race, mismatched owner/receipt, partial restore, corrupt Android storage
and captured-context checks still pass. Reopening a store is local persistence
evidence, not an actual process-kill, Clerk, network or two-device test.

Re-run commands and toolchain paths are in `LIBRARY_SYNC_CORE_VERIFICATION.md`.
No Xcode project regeneration was performed; incoming generated project/catalog
changes are excluded from this unit.

## Review and remaining work

The initial design workers failed at the account usage limit, so the parent
recorded two alternatives and a decision. A fresh independent gpt-6-sol source
review later completed against committed `0609bf2` and found no concrete blocking
defect in its receipt lifecycle. The exact report is
`product-program/sync-design/receipt-lifecycle/implementation-review.md`. That
review excludes the later uncommitted production integration.

The production sign-in and signed-in write callers are now migrated in the next
checkpoint. See `LIBRARY_SYNC_INTEGRATION_VERIFICATION.md` for actual-facade proof
and remaining boundaries. Local recovery export, account-deletion restart/retry,
large-folder continuation, vanished anchors, suspended storage-commit cancellation,
installed-schema migration and broader transport/process interruption proof remain
open. No A2 cloud deployment, private account write, paid generation, permission or
production change was performed or newly approved.
