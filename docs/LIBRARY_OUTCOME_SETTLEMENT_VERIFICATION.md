# A2 native outcome settlement verification

October 21, 2026. Continues `d53bbf0`. Both native coordinators now settle exact
terminal manifest outcomes after the owned Saved revision arrives, persist recovery
and ACK intent, and retry ACK after reopen. This advances the settlement component;
it does not finish A2 or enable the public async producer. No deployment, private
account call, paid generation, production migration or push was performed.

## Implemented boundary

The store re-reads the persisted collection, exact journal authority and erasure
generation. Its pure partition transition reconstructs manifest proof, validates
client/sequence and terminal category totals, and rehashes matched frozen content.
Operation ID, revision, batch operations and delete/restore kind must match. Matching
IDs with changed commands, a missing frozen original, conflicting restore aliases
and foreign owned snapshots leave the partition unchanged.

Complete journals require exact verified totals. Partial restore and explicit
`detail_unavailable` retain the locally available original command/source with compact
journal authority and checkpoint in `LibraryRecovery.outcome`. No collected member
array is copied into partition JSON. `proof_unavailable` cannot settle or ACK.
Historical adoption keeps its earlier historical archive and adds an outcome pointer
with no invented original. All journal facts remain discoverable for private export.

A finite integral Saved snapshot from the same owner must reach the committed Saved
revision. Until then, the coordinator reports `waitingForSaved` without polling or
failure. Successful owned Saved subscription delivery persists the snapshot and wakes
the existing coalesced worker. Its owner/session/epoch checks protect the signal;
activation/reopen also rechecks an already persisted barrier. Restoration uses the
authoritative snapshot rather than the originally requested member list.

One atomic partition write stores recovery/original, restore mapping, next sequence
and exact ACK intent while clearing only the matched frozen/collecting state. Later
pending changes survive. Delete receipts retain the original operation's five-second
Undo deadline; late settlement does not restart it. The already durable journal
precedes this write and network ACK follows it. A duplicate transition with that
same persisted ACK returns without appending recovery or advancing twice.

SwiftData reads the journal through a fresh context and saves the copied partition
on MainActor. Android holds the store mutex across a pure SQLite checkpoint read
and the AtomicFile partition commit. Its extracted private `persistLocked` retains
the existing write/finish/fail behavior for all callers. This unit adds no mutable
journal lifecycle metadata or export-clock mutation. Account deletion still removes
partition and evidence together. Any future partition-only cleanup must preserve
recoverable originals first. The independent reset helper remains test-only.

## Design and review

Two complete designs were read end to end. Corrected partition-owned candidate A
wins 23/25 against journal certificate candidate B at 20/25, matching the independent
judge. Keep original recovery in the same atomic partition write as ACK intent.
Reject a mutable journal certificate/source attachment for this milestone; it adds
cross-store states without strengthening that atomic write. Graft B's replay,
lost-wake and no-recreation checks. Sources and selection are under
`product-program/sync-design/scale/outcome-settlement*.md`.

The first source review found no concrete defect in the partial-restore path. Wider
verification followed it; the final review is recorded beside the design. Neither
review nor this record claims every storage/crash/installed-client scenario is proved.

## Executed evidence

| Boundary | Result | Evidence |
| --- | --- | --- |
| iOS actual stores/coordinators, presentation and Settings | 78 pass, zero failures | `/tmp/hadithly-outcome-settlement-ios-verified.log`, `/tmp/hadithly-outcome-settlement-verified.xcresult` |
| Android actual store/coordinator instrumentation | 61 pass, zero failures/skips | `/tmp/hadithly-outcome-settlement-android-verified.log` |
| Native wire and local API reference generators | Pass | `python3 scripts/generate-library-sync-wire.py --check`, `node scripts/generate-convex-api-local.mjs --check` |
| Diff whitespace | Pass | `git diff --check` |

The initial red fixture reproduced the missing terminal transition and Saved wake
on each platform. After a sufficient Saved snapshot, the original remained frozen
and no ACK occurred. Evidence: `/tmp/hadithly-outcome-settlement-ios-red.log` and
`/tmp/hadithly-outcome-settlement-android-red.log`. Focused first-green logs use the
same names ending `-first.log`.

The actual facade fixture starts with durable partial-restore evidence, delivers a
below-barrier snapshot and observes zero ACKs, then delivers the exact barrier.
Recovery retains the original folder text, mapping and later pending note. An injected
ACK failure leaves durable ACK intent. Real-store reopen retries it, preserves the
single recovery record and retained rows, and only then sends the later change.
This is controlled transport evidence, not a hosted lost-response/cross-device proof.

Real-store unavailable fixtures collect 50 of 51 facts, persist unavailable detail
or unavailable proof, reopen, apply the policy and parse actual exported files after
coordinator activation. Detail-unavailable permits recoverable ACK; proof-unavailable
preserves the unchanged collection and frozen original with zero ACKs. Both exports
retain the original text and partial facts with `detailComplete=false`.

The pure policy matrix covers full delete/restore, partial restore, both unavailable
reasons, historical adoption, below/above Saved revisions, unfinished collecting and
verification, incomplete terminal counts, changed matched command, missing source,
foreign snapshot, alias collision, expired/unexpired Undo deadlines and duplicate
settlement. Real-store foreign-deployment and account-erasure tests reject stale
settlement without recreating partition or evidence. The existing 501-member
interruption/reopen fixture now reaches complete detail and waits for Saved with one
send, zero ACKs and all later work preserved.

Android's initial write-failure setup did not actually prevent AtomicFile writing.
The corrected fixture removes parent-directory write permission, observes a real
IOException, restores permissions and reopens the old unchanged frozen partition.
A successful retry and duplicate advance once, retaining journal evidence. Focused
proof is `/tmp/hadithly-outcome-settlement-android-write-fault.log`; the final complete
61-test run includes it.

The artificial iOS SQLite abort trigger caused Core Data's fatal optimistic-lock
handling instead of a catchable save failure. That unsupported fault injection was
removed. The failed attempt remains in `/tmp/hadithly-outcome-settlement-ios-cases.log`
and `.xcresult` at `/tmp/hadithly-outcome-settlement-cases.xcresult`. Final 78-test
evidence excludes it. Actual iOS save-failure/power-loss recovery is still UNPROVED;
a passing guard/reopen test is not a substitute for that requirement.

## Remaining cutover and broader gates

- No success pruning, ACK-confirmed journal marker or retention completion is claimed.
  Every journal remains retained. Undo/offline/recovery dependencies must be integrated
  before pruning. Old list-only manifest Undo and installed-client migration remain open.
- Native whole-partition/cache/pending growth, the original restore's 500-ID limit,
  full Saved/export bounds, public producer/read cutover and app-level 501-member
  product support remain open.
- Actual iOS save failures, power loss, cancellation exactly around the durable write,
  complete physical/SDK auth/deletion and hosted lost-ACK/cross-device matrices remain
  open. Existing owner/session checks and local tests do not close these by inference.
- Full external export-provider rollback, older-OS upgrades, development deployment
  approval, hosted limits, content, localization, stores and release gates remain open.
  The full product program is active. Continue the remaining A2 cutover, then the
  owner's ordered research and native/web/Linear work.
