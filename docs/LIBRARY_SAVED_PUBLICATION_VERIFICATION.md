# A2 atomic Saved publication and published reads

October 24, 2026, after `b6fd523`. Both native stores can now publish a prepared
Saved build together with its actual private generation, presentation identity,
row mode, covered-confirmation pruning and retirement references. Published
exact-target, folder and indexed page reads use that coherent pair. The installed
runtime/UI does not invoke these new publication APIs yet. Production stays on the
existing display path; only explicit component tests enable row mode. A2 remains
active.

## Publication boundary

The publisher rechecks the build's actual private source, account revision, replay
cut, view serial and verified integrity manifest. Fresh publication also requires
the exact current prepared candidate/checkpoint and a final matching completion
reply. Owner, source root, version, input/completion cursor, exhausted ordinal/count
and empty final facts must all agree. Cancellation and the supplied current-session
check run around the awaited fetch and Android delivery boundaries. An accepted
edit during confirmation invalidates the captured cut; it must catch up before
publication. This is local callback/transaction proof, not real SDK/binding-expiry
or cross-device transport proof.

Android commits through the existing account-row SQLite transaction; iOS uses the
existing fresh account ModelContext and one save. Private pointer, published view,
mode, old private/view retirement references, source-covered confirmation pruning,
account revision and export clock cannot commit separately. Existing pending,
frozen, recovery and unrelated account data remain governed by their existing
policies. Queue pruning obtains its observation from the newly selected actual
private record in that same transaction, never from the old joined cache.

The published record binds view identity to private lease/version/digest. Its
represented command count and cut digest describe presentation input only; they
are not another private observation. A repeated publication of the same identity
returns the current published stamp without fetching again or renewing the export
fence, even though successful publication has cleared the mutable build record.

Offline local publication requires an already coherent publication in row mode and
the exact immutable active source. It cannot bootstrap a first private observation
without the final completion check. A newer candidate may keep collecting while
local presentation is rebuilt from the active generation. Private-generation and
view-retirement occupancy are checked separately. A new private generation cannot
replace another retained private generation before its retirement slot is free.
A new view cannot overwrite an occupied view-retirement slot.

A restart/unavailable final reply preserves the existing private/view pair and all
accepted queue originals. An unpublished candidate records its stopped state. If
the checked source is already active, that immutable checkpoint is not rewritten
into an invalid stopped state. The runtime must still implement renewal, retry and
backpressure using its actual captured transport binding.

## Reads and retirement

Each published read selects the current owner/deletion/private epoch, validates the
published record against the actual active private source, and queries that view
in one transaction/context. Exact target results distinguish unavailable
publication from a complete known-absent target. Item/folder pages retain fixed
budgets and serial-bound tickets. Replacing the publication rejects an old ticket;
it does not silently continue into another view. Unresolved public routing remains
explicit and cannot turn a selected collection into a false exhausted empty state.

Generic draft write/discard calls cannot mutate or erase the published identity.
Private-only activation cannot bypass a real published pair. The old whole-array
projection factory also rejects a real published library. These guards do not
silently fall back to the retained joined cache. Existing forced row-mode-only
observation fixtures still test their independent private authority boundary.

Publication marks the previous view retiring and saves its exact stamp. Cleanup
uses the existing bounded deletion helper: at most 128 small indexes or eight
private values per step, then its head. The current view stays readable throughout;
the retirement pointer clears only when cleanup finishes. Private generation
cleanup remains separate. Retained old/current rows continue through existing
scoped export/erase streams; the new pointer/cut metadata adds no original note
text or provider passages. The old joined cache is retained until its safe runtime
migration/cleanup, not deleted during this component cutover.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Full iOS planner/presentation/Settings suite | 143 pass, zero failures | `/tmp/hadithly-pub-ios-full.log`, corresponding `.xcresult` |
| Full Android connected planner/facade suite | 134 pass, zero failures/skips | `/tmp/hadithly-pub-android-full.log`, actual JUnit XML |
| Android local units | 212 pass, zero failures/skips | Same command, 34 unit JUnit XML files |
| Preserved Android full-run XML | Pass totals verified | `/tmp/hadithly-pub-android-full-junit/` |
| Focused publication fixtures | 3 passes per platform, zero failures | `/tmp/hadithly-pub-ios-focused-fixed.log`, `/tmp/hadithly-pub-android-focused-fixed.log` |
| Native wire and portable view generation | Pass | Existing helpers with `--check` |
| Independent source review | No actionable finding identified | [Review](product-program/sync-design/scale/saved-cutover/publication-store-review.md) |

The first-publication fixture uses 67 private items and seventy folders, accepts a
folder delete and a new local note, then verifies exact published status, paging,
normalized folder lookup, unresolved collection coverage and known absence. The
covered confirmation is pruned while both pending edits remain. Reopen reads the
same publication; idempotent replay performs no fetch/write. Raw discard/write,
private-only activation and the old projection factory cannot bypass its guards.
A second private generation publishes coherently, invalidates old page tickets and
retires the old view in bounded steps. A subsequent local Undo publishes offline
from the active source while a newer candidate remains collecting.

Invalid completion owner/version/root/input/completion/count/ordinal cases preserve
both absence of publication and the original fence. A stale current-session callback
cannot publish. An accepted edit during the fetch rejects the old cut, then a
recaptured/caught-up build publishes. Restart and unavailable results retain the
old readable pair and exact accepted originals.

Android injects an actual account-payload SQL update abort after both pointers,
mode, retirement and in-memory pruning have been staged. Everything rolls back,
including old readability, the verified draft, queue data and export fence. iOS
exhausts the logical export clock on the outer account update after publication
metadata has been staged and proves the same pre-save rollback. This does not
prove recovery from a failing ModelContext.save; that gate stays open.

After a successful retry, export contains both old and current retained note
values. Scoped account erasure removes its retained private/view generations while
another subject's published view and newer unclaimed guest original survive.

Android schema 10 adds nullable publication/retiring-view fields. The exact v9
assembly shape is reconstructed on disk with a prepared draft, private source,
accepted queue note and fence; reopen preserves them, has no publication by default,
then publishes the retained build. Earlier version fixtures now remove columns
that did not exist in their declared schema before upgrade. The genuine captured
older SwiftData Saved model still migrates with the new nullable fields in the
full suite. Every installed binary/OS/backup combination is not proved.

## Remaining delivery

Wire ordinary point intent admission and every receipt/cache/claim producer to
published-view updates or bounded scheduled rebuilds. Add the runtime single-flight
collector/compiler/publisher with real binding renewal, cancellation, retry,
retirement and edit backpressure. Then switch both Saved locations, Reader exact
state and paged folder controls together, including independent reference/full-text
hydration and safe old joined-array/cache retirement. Drive the real native UI and
accessibility journeys and show rendered results.

A published view can still describe an earlier represented cut while new queue
changes await that future orchestration. The runtime must expose/apply that state
coherently and must not label its cut digest a private revision. No installed caller
is switched to this intermediate state by this unit.

Pending/positions and server/local export scale, practical large-folder/replay
latency, actual SDK/JWT/backend-first/installed/cross-device/physical verification,
recoverable iOS save failure, A2 development deployment and A1 content dependencies
remain open. Full PRODUCT_PROGRAM remains active. No cloud change, paid call,
production configuration change or push occurred. Incoming generated Xcode/catalog
changes remain separate.
