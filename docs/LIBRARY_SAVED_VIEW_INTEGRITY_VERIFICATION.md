# A2 Saved draft integrity and bounded discard

October 24, 2026, after `1257916`. Both native stores now persist and resume an
integrity audit for a compiled Saved draft and reclaim abandoned drafts in bounded
transactions. This is a local component checkpoint. It does not publish a user
library, establish latest server/queue coverage, connect production UI or enable
row mode. A2 remains active.

## Behavior and boundary

A compiled snapshot produces a deterministic manifest containing private item,
folder and technical-index counts plus a SHA256 chain over sorted technical row
keys and semantic private-row fingerprints. It includes no provider passages or
original note text. The one-time manifest computation takes the already captured
snapshot; it is not a claim of bounded whole-library source capture or queue scale.
Duplicate targets and zero-facet source rows reject.

The persisted audit binds that manifest to the exact view serial. Each transaction
checks at most eight private rows and their expected exact indexes, or enumerates
at most 128 small index entries. Row fingerprints, ownership, exact target keys,
index targets and deterministic digest must agree. Checking all expected indexes
and then the total unique index count detects missing, extra and misdirected
entries. Exhausted source rows must match all expected private counts and digest
before the index phase can finish. A missing draft cannot pass as an empty one.
A genuinely empty compiled snapshot can pass both phases.

Every ordinary draft write clears the audit in its existing row/index/serial/clock
transaction. An older serial cannot resume or read a previous integrity result.
Repeated begin with the same manifest resumes existing progress. A changed manifest
at the same serial rejects. Verified reads and repeated verified steps make no
writes and do not invalidate an export fence. Every changed audit checkpoint does.

Discard marks the draft as retiring before deleting anything, in the same
transaction. Normal queries, writes and audits reject a retiring head, so an
interrupted deletion cannot look like an empty library. Each step removes at most
128 technical index entries or eight private rows; the head is removed last.
Reopening resumes cleanup, another draft stays usable, and completion releases a
slot from the three-head limit. Repeating a finished discard is a no-op. These are
**draft-only** operations. The future publisher must protect its active view and
select retirement explicitly.

Android schema 8 adds audit data and the retiring flag to actual version-7 heads.
The test reconstructs that predecessor on disk after writing 2,001 items and
seventy folders; reopening preserves all rows and indexes and initializes the new
state. Earlier migration fixtures still pass. SwiftData adds an optional audit
payload and a default-false retiring flag. The genuine captured older Saved model
still migrates in the regression suite. This does not prove migration from every
intermediate SwiftData binary, physical device or OS.

All private originals in still-retained draft rows continue through the existing
scoped export/erase paths. Audit hashes/cursors and retirement flags add no original
private content. Scope/epoch/deletion admission is checked for every step. Full
publication/catch-up and exporter scale remain separate gates.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| iOS planner/presentation/Settings suite | 137 pass, zero failures | `/tmp/hadithly-view-audit-ios-full.log`, corresponding `.xcresult` |
| Android connected planner/facade suite | 126 pass, zero failures/skips | `/tmp/hadithly-view-audit-android-full.log`, connected JUnit XML |
| Android local units | 212 pass, zero failures/skips | Same command, 34 unit JUnit XML files |
| Final iOS rollback/empty/portable-vector follow-up | 2 pass, zero failures | `/tmp/hadithly-view-audit-ios-final-followup.log` |
| Final Android rollback/empty/portable-vector follow-up | 2 pass, zero failures/skips | `/tmp/hadithly-view-audit-android-final-followup.log` |
| Generated native wire and portable fixtures | Pass | Both generation helpers with `--check` |

The 2,001-item audit resumes after repeated store reopen, verifies all seventy
folders and every expected index, and rejects an old proof after an accepted
write. Six corruption cases reject missing private rows, missing indexes, an extra
index, wrong index targets, changed valid private payloads and a nonempty manifest
applied to an empty draft. Neither successful integrity verification nor discard
changes the private active pointer or production row mode.

Android injects real SQLite statement aborts for audit checkpoint updates and for
index deletion after the retiring mark. State and export clocks roll back together.
iOS injects logical clock exhaustion before save, checks unchanged audit progress,
retirement admission and fence, then retries after recovery. This is not evidence
of recoverable SwiftData save failure. That gate remains open.

The portable fixture helper independently encodes a private item/folder manifest
with fractional timestamps, Greek text and exact route/folder membership. Both
native implementations compare against its digest. Broader practical refresh
latency is not inferred from these composed test durations or per-step limits.

## Next integration and retained gates

Bind a persisted build to its immutable private generation and accepted queue cut,
resume source compilation, catch up accepted changes and perform final transport
completion validation. Publish private pointer, effective view, row mode and queue
effects atomically. Only then switch both Saved locations, Reader exact state,
paged folder controls and independent reference/full-text hydration, retiring the
old joined-array display path safely. A caller-supplied compiled manifest is an
integrity expectation, never a complete private observation or publication permit.

Account pending/positions and server-export scale, installed/backend-first/real
SDK/JWT/cross-device/physical-device verification, recoverable iOS save failure,
A2 development deployment and A1 content dependencies remain open. No cloud
change, paid call, production change or push occurred. Incoming generated Xcode
and localization-catalog changes remain separate.
