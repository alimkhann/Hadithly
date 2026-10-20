# Outcome export contract

October 20, A2 after `eec9ba4`. Parent read both candidates end to end and agrees
with the independent judgment: A wins 22/25, B 19/25. Use one subject+namespace
journal mutation clock, bounded owned inventory and private streamed artifacts.
Graft B's pure export reads, startup artifact cleanup and explicit external
publication limits. Reject a writer lease because it pauses collection and adds
expiry/restart state without improving the final sharing boundary. Full A2,
settlement/ACK and release gates remain open.

`LibrarySync.preparePortableExport` owns captured-session checks, current portable
partition data, stable journal discovery and writing/sealing a private file.
Settings supplies the existing server export and receives a complete artifact.
It never enumerates journal pages or accumulates their members. All existing
server fields and exact note strings survive structural JSON encoding. Provider
passages and capabilities are removed by structural field names only.

Each active subject+deployment has a clock with a UUID epoch and monotonic revision.
Header creation, fact/checkpoint persistence, verification, inventory backfill and
future settlement/pruning bump that clock in the same database save as their
effects. Every bounded export read and final private-file promotion checks the
captured epoch/revision plus current session/deletion intent. Insertions before a
header cursor and removed old headers therefore invalidate the whole staged file.
Export retries start a new file. There is no persistent lease to block erasure.

Inventory includes older owner-key headers and partitionless orphans for the same
captured subject+namespace. It excludes every other subject/deployment. SwiftData
uses a unique scoped inventory key and a bounded global header backfill before
first export; new header writes insert their inventory atomically. Android adds
an owned ordered index and clock table through a non-destructive SQLite v1-to-v2
migration. Both platforms keep per-call member arrays at 50 or fewer.

The file carries exact authority, expected/collected/verified category totals,
status and unavailable reason. Reaching the end of a collected prefix does not
mean the manifest is complete. Missing or changed required facts fail export.
The existing server JSON and partition-blob memory scale remain a separate gate.

Account erasure invalidates the clock before bounded cleanup and removes clock,
inventory and owner metadata when cleanup finishes. A removed or freshly recreated
epoch cannot validate an old export. The existing durable deletion intent prevents
late export or journal setup from recreating metadata. Startup cleanup removes
abandoned private artifacts; cancel/failure removes the current staged file.

iOS promotes the complete private file atomically before showing its share URL.
Android preserves native Save-to-document behavior by staging privately before a
separate destination copy. Check captured context while copying and never report
success after cancellation/account change. Arbitrary SAF providers and receiving
apps cannot promise atomic external rollback or revoke bytes already accepted;
private staging and honest failures do not close that external-provider gate.

Required actual proof: missing-journal export red/green on both native hosts,
all original fields/notes, owned older-key orphans, foreign exclusions, full and
partial/unavailable facts, insert-before-cursor/verification/erase/cancel/switch
invalidation, private-stage cleanup, stored row corruption, old database migration
and real file parsing. Do not remove the final ACK guard until export and exact
settlement are implemented and verified.
