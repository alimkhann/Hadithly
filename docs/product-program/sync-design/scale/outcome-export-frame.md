# Outcome export boundary

A2 continuation after `eec9ba4`. Grounding is the current real native journal,
`LibrarySync.portableState`, Settings export callers, account erasure, and
`outcome-collection.md`. This is a read-only architecture consultation frame;
consultants write their own `/tmp/hadithly-outcome-export/` file only. Parent
implements. No cloud, private account, provider, production or release action.

Current Settings export reads the server JSON and native partition into memory.
Retained journal facts must be streamed in bounded pages rather than added to
partition JSON or an accumulated result array. Existing server/partition scale
remains a separate open gate. Neither final manifest settlement nor pruning is
enabled yet. Native collection is wired and stops with no ACK at terminal journal.

The current captured Clerk subject and deployment namespace authorize local journal
export, including older owner-key orphan headers for that same subject/namespace.
Other subjects/deployments must never enter it. Discover in bounded key pages,
stream all collected facts with honest expected totals/status, and distinguish the
end of a collected prefix from complete receipt detail. Preserve every server/local
export field and exact user note text; remove provider passages/capability fields
structurally. Do not persist or expose JWTs/capabilities in journal data.

Compare snapshot/revision fencing with a viable native snapshot/lease alternative.
New or removed headers can sort before the discovery cursor, so comparing only one
header checkpoint is insufficient. An export must either see one stable local
inventory or fail explicitly. Erasure must proceed and invalidate export. It must
not leave private owner metadata, stale leases or partial publishable artifacts.

Suggested shape A: a subject+namespace mutation clock, bumped atomically with every
journal mutation. Capture generation/revision, check across bounded discovery/row
reads and before artifact publication. Stage a complete private file first; abort
and remove it on mutation/account switch/cancel. SQLite/SwiftData migration and
clock erasure must be tested. Shape B must be structurally distinct, such as a
native stable read snapshot or short-lived lease, with a smaller reliable caller
surface if it wins. Do not copy all identities into the partition or heap.

Rubric1-5: exact captured ownership/orphan coverage; snapshot correctness under
insert-before-cursor, verification, pruning and erasure; bounded reads/writes and
streamed artifact; crash/cancel/migration/cleanup safety; deep store/coordinator
interface and actual real-store proof. Caller-first sketch, tradeoffs and concrete
failure cases. No implementation or completion claims.

Workflow: [x] ground/frame; [x] two candidates; [x] review/selection; [x] parent
implementation; [x] local native export/erasure/old-store migration proof; [ ] final
settlement integration and ACK proof. Full A2 and product gates remain open.
