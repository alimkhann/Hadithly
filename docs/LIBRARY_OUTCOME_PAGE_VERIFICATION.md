# A2 paged folder outcomes

October 20, 2026. Continues `fcd0502`. The local server query reads exact historical
folder outcome facts in bounded pages. The native journal design is selected;
durable native collection and the public async producer remain unimplemented.
This is not app-level large-folder support or A2 completion. No deployment,
private account call, paid provider call or installed migration was performed.

The contract and candidate comparison are in
`product-program/sync-design/scale/outcome-collection.md`.

## Implemented boundary

`librarySync.outcomePage` verifies Clerk identity and a live owner-bound capability.
It requires the current committed stream's exact client, sequence, batch and digest,
plus receipt ID, manifest ID/generation and phase. Pending or acknowledged streams
provide no detail authority. The server derives ownership; callers do not pass it.

Each indexed page returns at most 50 contiguous identity facts and 64 KiB of encoded
response. The page echoes owner and request. A fact contains ordinal, manifest-member
ID, hadith ID and disposition. It contains no note, folder name or provider passage.
Continuation and explicit terminal status follow the receipt total. Missing facts
throw a fixed invariant error. Zero members still require an explicit terminal page.

Delete pages retain the original identity set while Undo changes restore categories
on those facts. Restore pages require the committed restoration and matching frozen
totals/destination. Later ordinary membership changes do not change historical pages.
`proof_unavailable` and `detail_unavailable` remain distinct. Neither can become a
fabricated complete empty result. Native settlement policy for expired detail remains
part of the collector cutover.

The wire generator derives both native page types and limits from actual Convex
validators. The ignored local API bindings were refreshed with the installed SDK's
pure template, without CLI credentials, network or cloud initialization.

## Reproduced defects and corrections

A corrupt stored restored count of 2 and missing count of -1 could cancel to a
plausible total of 1. The actual query returned a completed page. It now rejects
each invalid category before sum arithmetic. Red evidence:
`/tmp/hadithly-outcome-pages-counter-red.log`. The full green suite includes this
case and missing-ordinal rejection.

The first large-page fixture opened a new binding per query/replay and reached the
existing 20-live-binding limit. That was a test-client mistake. The fixture now
reuses its binding until expiry, matching the coordinator. The production binding
limit was preserved. Initial evidence: `/tmp/hadithly-outcome-pages-targeted.log`.

The native page design review exposed another path around the earlier receipt
guard. Unknown committed cursors could be adopted and ACKed without collection,
including a same-ID/different-intent restored copy. Both native test hosts reproduce
this. Cursor validation now rejects either manifest receipt before changing frozen,
waiting, recovery, sequence or ACK state. Tests cover reconcile, retirement,
unmatched pending completion and acknowledgement-response adoption for both kinds.
This preserves source data while the collector is absent; it does not collect pages.
Red evidence: `/tmp/hadithly-outcome-adoption-ios-red.log`,
`/tmp/hadithly-outcome-adoption-red.xcresult`, and
`/tmp/hadithly-outcome-adoption-android-red.log`.

## Executed verification

| Boundary | Result | Evidence |
| --- | --- | --- |
| Actual Convex page/transition fixtures | 0/1/50/51/501 members, replay, foreign owner/capability, wrong receipt proof/phase/generation, pending/ACK, expiry, missing ordinal, malformed counts, mixed frozen categories | `backend/convex/savedFolderTransitions.test.ts` |
| Complete backend suite | 469 tests, 40 files pass | `/tmp/hadithly-outcome-pages-backend.log` |
| Strict backend typecheck | Pass | `/tmp/hadithly-outcome-pages-final-typecheck.log` |
| Native wire and local API source checks | Pass | `generate-library-sync-wire.py --check`, `generate-convex-api-local.mjs --check` |
| iOS core/store/coordinator/guard checks | 57 pass | `/tmp/hadithly-outcome-pages-ios.log`, `.xcresult` |
| Android core/store/coordinator/guard checks | 36 pass | `/tmp/hadithly-outcome-pages-android.log` |

The independent server review found no concrete blocker and did not run tests or
certify native/public readiness. The full report is
`product-program/sync-design/scale/outcome-server-review.md`.
The independent native recheck found no alternate manifest ACK path in the inspected
partition methods. It did not rerun tests or certify the collector. Its full report
is `product-program/sync-design/scale/outcome-native-adoption-review.md`. Pending
reconcile and mixed legacy direct receipts were inspected in source; they were not
additional explicit new fixtures.

## Remaining A2 gates

Implement the selected SwiftData/SQLite row journal with bounded page transactions,
exact ordinal/member uniqueness, restart replay, unavailable-detail recovery and
captured-owner orphan erasure/export. Prove strict compare before SwiftData uniqueness
upsert, Android journal-before-JSON-before-ACK ordering, Saved revision barriers,
Undo-aware pruning and interrupted writes on both native hosts. Keep full growing
identity arrays out of partition JSON. Existing whole-file Saved cache/pending scale
and installed schema/client migration remain open.

The public async producer, legacy timestamp/list-only Undo cutover, bounded Saved
read/export, hosted limits and authenticated device/cross-device proof remain open.
The public 501-member support probe is still red. A2 deployment requires fresh
action-time approval for its concrete schema/function changes. A1 approval does not
cover it. Other content, localization, store and release gates are unchanged.
