# A2 private-source Saved draft builder

October 24, 2026, after `1fb1d86`. Both native stores now compile an actual prepared
private generation and a captured Saved edit sequence into a resumable indexed
draft. Appended delete/Undo and point edits can catch up before preparation. This
implements source compilation and local catch-up. It does not publish private/view
pointers, enable production row mode or switch either native UI. A2 remains active.

## Source and transaction ownership

`beginSavedViewBuild` selects the exact current prepared candidate or the actual
immutable active private generation and captures
account state once in its owner transaction/context. It selects only confirmed
Saved changes newer than that private version, the eligible frozen edits and pending
Saved changes. A local build can use that active generation while a newer candidate
is still collecting. Retired, foreign and incomplete candidate leases reject. An
old joined-cache revision cannot choose this boundary. Position
changes keep their separate domain. The captured replay retains only operation,
outcome and exact-target route metadata, without copying the provider passages or
whole account payload into build rows.

A persisted record binds private lease/checkpoint, account revision, edit count and
prefix digest. Android uses its existing account-row revision. SwiftData now adds a
default-zero account revision advanced with changed account state in the same save,
including guest claims. Negative or exhausted revisions reject before writing. Source-page and draft/index/checkpoint writes advance the
export clock without changing that account revision. Each build step rechecks both
bindings through metadata reads, without decoding the joined account payload.

One transaction handles draft row/index/serial writes and the matching build
cursor/count change. Shared private helpers operate in that transaction/context;
normal raw draft writes clear the build record and audit instead of leaving a
reusable preparedness claim. Failed transactions do not advance the in-memory
folder decisions. Cached folder-decision counts must match the current persisted
count, so a second older session rejects and recaptures. Android serializes advance
calls sharing one session; Swift runs on MainActor. This is not proof of the future
runtime worker scheduler or arbitrary multiprocess access. Prepared reads require the exact verified audit at the current
view serial and matching manifest.

## Compilation and catch-up

The compiler first traverses bounded private projection pages to build the folder
directory. It then resolves folder commands chronologically through exact IDs and
indexed normalized-name lookup. Checksummed technical entries retain each command's
folder decision, bound to view identity, ordinal and edit-prefix digest. No private
item overlay or production tombstone query is introduced.

A second bounded traversal compiles each private item through the captured edit
sequence, including folder delete/compact Undo, explicit membership overrides and
facet removal/restoration. It also processes exact point targets from the queue so
new Saved items absent from the private source are included. Zero-facet intermediate
values exist only during replay; the final row writer removes them. This preserves
original creation time and removal provenance when the last facet is removed and
then restored.

Each source traversal must exhaust its key range and match both private source
counts. Persisted expected visible-row counts advance with writes/deletions. A
bounded manifest pass checks those counts, then the existing serial-bound integrity
audit checks payloads, exact indexes and total unique index count, including declared
technical folder bindings. Only then is the draft marked prepared. That state means
prepared for this captured source; it is not permission to publish.

Reopening recaptures account state once and verifies the old edit digest is still
an exact prefix. Neutral changes, such as moving identical pending edits into a
frozen frame, update the account binding without changing their meaning. Appended
edits extend the cut and resume folder decisions, then recompile private/queued
items before a fresh manifest/audit. Existing published data is untouched. A changed
existing outcome, alias map or captured route set requires a fresh draft rather
than silently reusing incompatible work. Accepted originals remain in the account
queue; bounded discard can reclaim the abandoned draft.

The account queue and its in-memory replay sequence remain an explicit scale limit.
A target replay walks that captured sequence; folder decisions are reloaded once on
capture. Bounded private pages do not prove bounded CPU work independent of queue
length. Appended bulk work can traverse the private source again. Practical bulk
latency, catch-up scheduling/backpressure and pending/positions normalization remain
open. The composed 2,001-item test duration includes source ingestion, compilation,
reopen and audit and is not a measured user-facing refresh latency.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| iOS planner/presentation/Settings suite | 140 pass, zero failures | `/tmp/hadithly-view-build-ios-full.log`, corresponding `.xcresult` |
| Android connected planner/facade suite | 129 pass, zero failures/skips | `/tmp/hadithly-view-build-android-full.log` |
| Android local units | 212 pass, zero failures/skips | Same command, 34 unit JUnit files |
| Preserved Android full-run JUnit evidence | 129 connected and 212 unit passes | `/tmp/hadithly-view-build-android-full-junit/` |
| Final source/binding/rollback follow-up | 3 pass per platform, zero failures | `/tmp/hadithly-view-build-ios-final.log`, `/tmp/hadithly-view-build-android-final.log` |
| Final stale-cache/count guards | 5 iOS and 4 Android passes, zero failures | `/tmp/hadithly-view-build-ios-guards-final.log`, `/tmp/hadithly-view-build-android-guards-final.log` |
| Active-source/neutral-cut/rollback/vector follow-up | 4 passes per platform, zero failures | `/tmp/hadithly-view-build-ios-active-source-final.log`, `/tmp/hadithly-view-build-android-active-source-final.log` |
| Immediate Android v8 migration | Pass, included in final Android four | Prior head shape reconstructed on disk; draft original, account, private scope and export fence preserved |
| Independent source/guard review | No actionable finding identified | [Review](product-program/sync-design/scale/saved-cutover/build-store-review.md) |
| Native generated wire and portable view vectors | Pass | Existing generation helpers with `--check` |

The new 2,001-item/seventy-folder case starts with an actual prepared private
source. A delete and offscreen membership move are already accepted when the build
starts. Compact Undo, a new note and last-facet removal/restoration arrive after item
compilation begins. The old session rejects; a fresh capture extends the edit cut.
Repeated reopen reconstructs exact folder decisions. The final 2,002 rows equal the
independent legacy compiler result, target 1999 retains its explicit folder, original
creation time survives and every queued edit remains durable. No active private
pointer or row-mode flag changes.

A separate case gives the old joined cache revision 999 while the actual private
source is version 9. Version-9 confirmed data is already covered, version-10 data
remains projected, and a legacy-only item is never imported as private source.
Moving pending to frozen resumes; changing aliases rejects that cut and preserves
the accepted frame and prior draft rows.

Android aborts the real build-checkpoint SQL update after staged child/index/serial
writes. The final follow-up also aborts after staging a folder decision and verifies
that persisted state, cached decisions and export clock roll back together. iOS uses
logical clock exhaustion before save for the corresponding rollback checks. An
isolated poisoned joined payload with unchanged revision proves a bounded build step
does not decode that payload; the test restores it immediately. The same rollback fixture now starts from an
active source while a newer candidate is collecting, rejects an older second
session after binding progress, and resumes after recapture. A negative Swift
account revision rejects an enqueue without changing the original payload.
Actual recoverable
SwiftData save failure remains unproven and open.

Android schema 9 adds a nullable build checkpoint to version-8 heads. The exact
preceding head shape is reconstructed with a retained note and reopened through
that migration; identity, serial, note, account and export fence survive. Older schema
paths create the current shape or apply the matching additive columns. Existing
migration suites pass. SwiftData adds optional build metadata and the account
revision; the genuine captured prior Saved model still migrates in the suite.
Every intermediate installed binary/OS migration is not proved. Build metadata has
a separate 512 KiB ceiling to accommodate the admitted private checkpoint/cursor
bounds rather than rejecting valid 12 KiB cursor fields at an identity-only limit. Manifest
binding counts must fit within the total index count before arithmetic, preventing
malformed metadata from overflowing the native integer range.

## Remaining delivery

Revalidate the final completion through the actual captured transport binding.
Atomically publish private generation, effective view, row mode and queue effects,
with bounded old-generation retirement. Wire the owner facade and every Saved,
Reader and folder consumer to those published reads plus independent reference/full
text hydration, then remove the old whole joined-array authority/cache safely.
Drive the real native journeys and measure throughput before accepting the UI gate.

Queue/account/server export scale, binding refresh and SDK/JWT/backend-first/installed/
cross-device/physical verification, recoverable iOS save failure, A2 development
deployment and A1 content dependencies stay open. This unit changes no cloud service,
production setting, paid usage or remote Git state. Incoming Xcode/catalog changes
remain separate. The full PRODUCT_PROGRAM goal remains active.
