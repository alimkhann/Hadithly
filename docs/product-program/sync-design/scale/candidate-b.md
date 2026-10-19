# Candidate B: membership cohorts with logical visibility and bounded cohort reparenting

## Usage first

```text
library.deleteFolder(folderID)       // enqueue folder_delete; no member-ID capture
library.undoFolderDelete(deletionID) // enqueue folder_restore; no member-ID list
subscription.apply(page)             // effective folderID already resolved by server
```

Native LibrarySync retains its frozen frames, sequence acknowledgement and captured owner/session fences. Folder receipts contain a deletion/restore handle and canonical destination ID; they never enumerate members. A transition that needs metadata normalization returns a durable transition handle, not false completion. The coordinator automatically watches/drives that handle; its final exact operation outcome settles through the existing receipt lifecycle. Library callers remain unaware of cohorts and continuation.

## Problem and actual source constraints

`librarySync.applyOperation` folder_delete currently reads take(501), rejects >500, stamps each membership and stores complete member arrays in both outcome and folder-deletion mark. folder_restore unions that server list with command.hadithIds and returns restored/superseded/missing arrays. `library.deleteSavedFolder` independently collects every member; legacy restore trusts a supplied list and deletedAt. Saved snapshot joins raw folderId. Swift `UserLibraryModel.deleteFolder/undoFolderDeletion`, its overlay, Android `LibraryProjection`, both wire validators and generated commands depend on those member arrays. Merely paging the existing mutation does not bound its receipt.

Logical visibility avoids touching members on ordinary deletion, but arbitrary same-name merge and repeated deletion/undo cannot be implemented by a one-field deleted flag alone. Redirect chains become unbounded; union sets make subsequent deletion touch arbitrarily many roots. This design makes that cost explicit and normalizes cohort metadata automatically, never member rows.

## Shape and ownership

```ts
type Folder = {id: FolderId; owner: UserId; name: string; active: boolean;
  phase: "stable" | "normalizing"; generation: number; visibilityAt: number};
type Cohort = {id: CohortId; owner: UserId; head: FolderId;
  maxMemberAt: number | null; count: number};
type Membership = {owner: UserId; hadithId: HadithId; cohort: CohortId;
  at: number; operationId: string}; // one current row per owner+hadith
// Membership references cohort directly, never parent cohort or restore history.
type FolderTransition = {id: string; owner: UserId; source: FolderId;
  destination: FolderId | null; kind: "delete" | "restore_merge";
  deletionId: string; phase: "normalizing" | "committed" | "superseded";
  cursor: string | null; clock: number};
type FolderReceipt = {kind: "folder_deleted"; deletionId: string; folderId: string}
  | {kind: "folder_restored"; transitionId: string; folderId: string}
  | {kind: "folder_pending"; transitionId: string};
```

Indexes: membership by_owner_hadith, by_cohort_at (descending maximum), by_cohort_hadith (bounded export); cohort by_head, by_head_maxAt; folder by_owner_normalized_active_name; transition by_owner_operation and due cursor. `savedItems` retains facets, not an independent authoritative folderId. Existing marks remain conflict clocks; membership operations update one membership plus cohort aggregate. Removing/moving the maximum member recomputes maximum with a single indexed first query, then updates cohort.maxMemberAt. Folder delete reads highest cohort maximum using by_head_maxAt, avoiding member scans and preserving current “any current membership newer than delete rejects whole deletion” rule.

`lib/folderMembership.ts` owns logical folder resolution and cohort transitions. `librarySync` owns operation/receipt admission; legacy library/guestMerge call the same domain methods. Native models consume existing effective server folder IDs. Internal cohort IDs never enter user-facing IDs or UI APIs (per boundary-discipline and minimize-reader-load).

## Ordinary delete and undo

A stable folder owns one or more cohorts. Each membership resolves with at most two point reads: membership.cohort → cohort.head → folder. An inactive folder yields no effective folder. Delete checks folder metadata and current cohort maximum against operation.at, then atomically sets active=false, records deletionId/clock on folder, and creates an immutable deletion handle referencing that folder generation. No member writes, no arrays. Effective membership clocks include the folder.visibilityAt so an older queued move cannot defeat a newer logical deletion. Raw inactive membership remains as recovery evidence.

Undo without same-name conflict atomically activates that folder only if its latest deletionId still matches and no later transition supersedes it. It advances visibility clock to restore time. Membership moved/cleared meanwhile no longer references its old cohort and is automatically excluded. A removed Saved item loses its membership row; restoration never recreates its facets. Folder native ID remains stable for this restoration. New current memberships use a fresh writable cohort where necessary to distinguish later intent from deletion generations.

## Same-name merge and repeated history

If a new active folder with the normalized name exists, preserve that destination's stable ID. The source must not simply redirect to destination forever. Instead create a restore_merge transition and automatically reparent source cohorts to destination in pages of, e.g., 100 cohort rows. Members remain untouched. A temporary single-hop source→destination folder alias allows consistent read projection while normalization runs. No alias may target another alias: transitions lock their source and destination metadata from a second structural transition until normalization ends. Queued deletes/restores of either folder wait durably and then apply against current clocks. Ordinary member moves/removals remain available and update the cohort aggregates transactionally.

All affected memberships become effectively restored at the merge transition's logical commit (set source alias). Reparent pages preserve that semantic visibility and carry restore clock in cohort metadata. Effective membership at=max(member.at, cohort.visibilityAt, head.visibilityAt); an intervening move/removal overwrites its current membership row and is never restored. Destination max-cohort aggregate includes incoming source maximum before publishing alias; until normalization ends structural operations are queued, so delete admission cannot miss an unflattened newer member. After last cohort reparent, alias is retired and source is a retained tombstone. Next delete operates on stable destination with direct cohorts. Each read remains bounded by one folder alias hop, independent of history.

Deletion handle restoration is once-only logical transition authority. Replaying its exact frozen operation returns exact receipt; a new restore command for the same handle resolves its recorded destination and never activates cohorts detached by a later destination deletion. Store handle state with final transition, not by walking successive restores. Later destination delete gets a new handle and hides every directly owned cohort together. Undo of that delete activates destination; old source handle is not an alternate resurrection path. Tombstone metadata is O(real folder transitions); routine membership/position writes do not append histories or arrays.

This requires automatic resumable **cohort metadata normalization**, not resumable member mutation. An arbitrary number of cohorts may require many pages before a subsequent structural operation commits. There is no honest O(1) arbitrary merge/deletion/history solution here without changing semantics or accepting unbounded redirects/sets. This bounded deferred cost is the principal tradeoff and may lose to candidate A for simplicity.

## Concurrency and receipt semantics

Server transition state is owner-derived and operation-ID keyed. Mutation commits alias/handle/job atomically; retry cannot start another transition. Worker pages use cursor+phase CAS, are idempotent, and reschedule themselves transactionally. A worker has no client capability/user argument: internal handler receives a transition ID and loads the retained server owner. Account deletion invalidates/deletes jobs; workers verify owner row and transition still exist before effects. Different accounts never share cohorts. Distinct device commands serialize through current folder phase/clock, not local locks.

Do not put a mutable pending outcome in a compacted committed receipt. Either existing stream stays outstanding until final transition outcome and uses a bounded progress RPC, or extend operation outcome to acknowledge durable acceptance distinctly from completed folder effect. Recommend keep stream outstanding with server transition reference, allow receipt polling to return pending until terminal result, then issue exact final receipt and permit normal ack. This delays unrelated commands in that stream, while another device remains independent; coalescing fresh reading positions remains local. Lost response/restart resumes handle; native UI may project optimistic deletion but must not claim restored server membership complete before terminal receipt.

## Reads, migration and compatibility

All read boundaries resolve logical membership, including saved snapshot, folder filters, export and private sync response. At arbitrary account size a monolithic snapshot is already unbounded: migrate to bounded item pages plus bounded folder metadata pages. Each item page resolves <=pageSize cohorts/heads and returns effective folderId and membership clock; caller cannot join against an incomplete alias map. Native merge-by-stable-ID projection preserves scrolling/navigation; folder ID changes only when restoration merges into an existing destination, as current behavior already permits.

Migration is required, not optional: resumable schema migration creates one initial cohort per existing folder and imports raw memberships in bounded pages. During migration use versioned dual-read/dual-write with per-row migrated markers; every write updates the new authoritative representation transactionally. Keep old raw folderId as deprecated projection only until all readers/writers move. Already installed legacy clients access the same updated function names, which must resolve logical membership server-side; legacy delete routes to the new transition boundary. Legacy restore cannot preserve its old synchronous full-array result for arbitrarily large folders. Version that contract or return a fixed upgrade-required error retaining undo data; do not silently send capped arrays. A release/device compatibility gate is unavoidable.

Guest folders remain local small cohort-equivalent state or use existing store lists; guest merge writes canonical cohort membership through shared methods. Both native folder restore commands stop capturing hadithIds; original locally available deleted-member metadata stays in owner recovery/export until explicit erasure. Private export pages cohorts/heads/transitions and resolves effective membership; account erasure deletes them in bounded indexed jobs and prevents continuation resurrection. No content/identifiers enter operational logs.

## Alternatives and accepted risks

- Pure folder deleted flag: smallest interface but fails same-name merge and repeated undo after newer deletion.
- Persistent redirects/union-find with path compression: cheap writes initially, but first read after arbitrary history has an unbounded walk; path compression does not prove bounded Convex work.
- Member mutation jobs: simpler compatibility and exact per-member outcome accounting; accepts O(member count) writes, whereas this design pays O(cohort count) on merges and O(1) ordinary deletion.
- We accept a deeper schema/read migration and short automatic structural serialization in exchange for instant logical delete at arbitrary member count and no per-member deletion stamps.
- We cannot retain full per-member restored/superseded/missing arrays in bounded receipts. Provide paginated audit enumeration by handle if needed; terminal receipt describes the logical set operation, not counts guessed from local observation.

## Proof and next implementation step

First build a pure cohort visibility/transition model with 501, 50,000 and repeated-name merge/delete/undo histories. Assert resolution depth<=one alias, no member writes on delete, bounded per-page DB work, and no stale handle resurrects later deletions. Then actual Convex fixtures cover maximum-member removal/move aggregation, concurrent moves during normalization, same-name existing destination, second delete waiting behind merge, lost final receipt and account erasure between pages. Native real-store coordinator tests must cover handle persistence/offline undo, no member arrays, exact terminal receipt settlement and paginated projection on both apps. Migration fixtures include old raw schema, partially migrated rows, legacy APIs and rollback without target/facet loss. Builds/local fixtures remain separate from actual authenticated cross-device proof.

## Synthesis decision

Candidate B only. Its benefit is strongest when folders have very many members but few merges/cohorts; its unavoidable metadata normalization and compatibility migration should be weighed explicitly against the member-job candidate.
