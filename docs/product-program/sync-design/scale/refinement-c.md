# Parent refinement C: orphan membership plus a staged restore slot

Alternative graft to compare with A's unbounded-per-history member facts. No code.

Delete: add index savedItems.by_folder_membershipAt. In one transaction read folder
and the highest current member folderUpdatedAt, reject if either is newer than op.
Delete folder row and retain a small deletion handle (old folderID/name/at). Leave
raw item.folderId pointers intact. Every read projects a pointer to absent folder
as none. Explicit moves/removals overwrite that raw pointer and clock as usual.
Thus current orphan pointers themselves are the authoritative still-eligible set;
no per-member deletion stamp or copied manifest is needed. Current concurrent
insert/move conflicts on the indexed range/row must preserve the existing stale
whole-delete rule. Old rows lacking folderUpdatedAt default0. Audit all writers.

Restore: resolve deletion handle and create/reuse same-name destination. Start a
bounded job. Page raw savedItems.by_folder(oldID), check current raw pointer and
clock <= deletionAt, and set a per-item staging slot {jobID,destinationID,restoreAt};
do not expose it yet. Moves/removals clear that slot. While job is preparing, a
writer clearing a staged slot transactionally decrements job.stagedCount. At final
commit, flip job visibility; that is the exact linearization point for the count.
Reads resolve unchanged staged slot -> job done -> destination. Later writes clear
the slot and win normally. Background pages materialize destinationID and clear
slot, preserving visible projection. No redirect chains and no per-deletion copied
member-fact table; storage O(current items + active jobs + small deletion handles).

Structural delete/restore involving destination waits durably until its current
materialization ends; ordinary membership/facet operations stay available. Source
has one active restore job too. This prevents another restore staging over the
same item or a destination delete missing unmaterialized staged members. Reads
need only one point job lookup per item. Paginated Saved/export required regardless.

Receipts: new native freeze isolates one folder operation per frame. A stream with
folder work returns explicit pending progress, keeps frozen unacknowledged until
terminal exact result. Worker can finish without client polling/online state.
Pending stream/job cannot be retired as if no effects exist; retirement must wait
for its terminal proof or have a separate cancellation proof. Old mixed frames
need truthful bounded incompatibility or a specified resumable prefix contract,
not blind replay. Legacy synchronous member-array APIs cannot be arbitrary-size.

Questions to falsify: can indexed max query safely replace full newer-member scan
under Convex transaction conflict rules? Can per-item current raw pointers define
all still-eligible membership without keeping missing/superseded identities? Can
counter maintenance make the final summary exact with concurrent moves/removes?
Does bounded materialization remove every alias/history walk? How do late old undo
handles avoid restoring members after a later delete/recreate/merge? What deletion
handle and worker retention bounds are honest for offline Undo? These are not solved
by naming the fields. Reject this if simpler appearance hides a correctness gap.
