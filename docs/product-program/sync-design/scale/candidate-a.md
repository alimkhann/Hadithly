# Candidate A: resumable manifest job with an atomic visibility flip

## Problem

`librarySync.ts:72-118` currently reads up to 501 members, clears each membership, stamps each mark, and returns complete member arrays in one `applyBatch`. It returns `folder_too_large` above 500. The legacy folder delete/restore paths in `library.ts:786-835` also collect or write an unbounded set. Paging the current loop would expose a partially deleted folder and break exact Undo. A bounded design needs an authoritative record of the actual membership set at deletion, a single logical visibility switch, and per-member conflict checks during restore. `librarySync` still derives owner from the JWT and keeps its per-installation apply/ACK cursor.

## Usage (caller's view)

```swift
// iOS UserLibraryModel: same one-tap calls; LibrarySync owns job lifecycle.
library.deleteFolder(folder)        // optimistic local projection hides it
library.undoDeleteFolder()          // queues exact deletion operation ID, even offline
// A2 status can report pending/recoverable work; no member arrays in the view.
```

```kotlin
// Android facade uses the same domain API and owner capture.
library.deleteFolder(folder, message)
// Undo closure calls library.restoreFolder(deletionId) from the captured account scope.
```

```ts
// Existing single-operation sync frame remains the carrier; the result is a bounded job handle.
{ kind: "folder_delete", folder: { kind: "server", id } }    // apply -> started(jobId)
{ kind: "folder_restore", deletionId }                     // apply -> started(jobId)
// LibrarySync privately observes/polls `folderJobStatus(jobId)` and finishes the receipt state.
```

## Shape

```ts
type FolderJob = {
  userId: Id<"users">; operationId: string; folderId: Id<"savedFolders">;
  kind: "delete" | "restore"; phase: "scanning" | "committing" | "visible" | "done" | "superseded";
  requestedAt: number; originalName: string; membershipEpoch: number;
  cursor?: string; generation: number; leaseUntil?: number;
  deletedFolderId?: Id<"savedFolders">; restoredFolderId?: Id<"savedFolders">;
  scanned: number; restored: number; changed: number; missing: number;
};
type MemberFact = { userId: Id<"users">; jobId: Id<"folderJobs">;
  hadithId: Id<"hadiths">; memberVersion: number; disposition?: "restored" | "superseded" | "missing" };
type FolderJobReceipt =
  | { kind: "folder_job_started"; jobId: Id<"folderJobs"> }
  | { kind: "folder_job_done"; jobId: Id<"folderJobs">; restored: number; superseded: number; missing: number };
beginFolderJob(ctx, owner, op): Promise<FolderJobReceipt>;   // no user-ID argument from mobile
advanceFolderJob(ctx, jobId, limit: 50): Promise<void>;      // internal, lease-safe, repeatable
folderJobStatus(ctx, jobId): Promise<FolderJobReceipt>;      // JWT-owner checked, bounded
```

`folderJobs` is indexed by owner+operation ID and phase+lease. `folderJobMembers` is indexed by job+hadith and job+cursor. Every member-placement writer, including legacy mutations and guest merge, increments `savedFolders.membershipEpoch` in the same transaction. Read-only queries continue to return owner-tagged snapshots. A schema migration adds the epoch and ensures every old writer participates *before* jobs are enabled; otherwise the final flip is unsound.

Delete preparation pages `savedItems.by_folder` in fixed-size chunks and stores one `MemberFact` per actual member, including its membership version. It reads only `<= requestedAt` members; a newer member makes the stale delete `superseded`, matching current behavior. The job records the folder's starting membership epoch. A concurrent older/equal placement changes that epoch: the scanner discards that generation's facts in bounded cleanup and restarts. A later placement (timestamp `> requestedAt`) stops the job as `superseded`. No membership is changed during scanning. Each step and cleanup has a bounded document count and resumes by cursor/lease after crashes. A constantly changing folder may postpone completion; the job must surface a bounded conflict after repeated invalidated scans instead of pretending to have finished.

The final delete transaction compares the recorded epoch and folder updated time again. If equal, it atomically removes the active folder row and sets the job to `visible`; all `savedItems.folderId` values still point to the now-absent original ID. Saved queries and widgets project that orphan pointer as no folder. New writes targeting the deleted folder reject; moves away from the orphan pointer work and increase the item's membership version. Because the fact table was complete before the flip, the server knows exactly which IDs deletion affected without returning an unbounded list. A same-name folder may be created immediately; restore reuses it by the existing normalized-name rule and records an alias from old folder ID to restored/new ID.

Undo carries only `deletionId`, and may be queued before the delete job becomes visible. The server stores a dependent restore job and starts it only after the delete finishes; if deletion was superseded, Undo resolves without a destructive write. Restore iterates `MemberFact`s in bounded pages. It marks a fact restorable only if the current item still points to the deleted folder ID with the captured membership version. An item moved or removed meanwhile is `superseded` or `missing`. To keep restore atomic to readers, each chunk records disposition, not a visible membership patch. A final constant-size transaction sets the restore job `visible` and the old-ID alias. Reads resolve old-ID members through the fact/disposition index to the restored folder; later writer or delete paths must resolve the same alias and compare the member version. Background materialization may rewrite physical IDs in chunks, but projection must be identical before, during and after that rewrite. Alias chains must be flattened or explicitly capped; never run an unbounded ancestry walk.

The old `folder_deleted` / `folder_restored` arrays become a bounded `jobId` plus counts. The native frozen frame settles only a **started** receipt, durably stores the job handle beside the captured owner and deletion ID, then acknowledges/compacts the batch. A separate job-status subscription drives final projection/recovery; it can survive restart and lost messages. `folderRestore` can be enqueued immediately after the delete frame ACK because it references the deletion ID, not a received list. A later account switch cannot display or drive another owner's job. Export includes pending jobs and recoverable member facts through bounded pages; deletion purges jobs/facts/aliases through resumable owner-scoped cleanup. No text, member list or account ID enters client logs.

## Synthesis decision

Candidate A only; arena synthesis pending.

## Tradeoffs accepted

- We accept per-member fact storage and read-time alias resolution in exchange for exact arbitrary-size Undo and atomic visual state.
- We accept a visible pending state and delayed final receipt in exchange for bounded Convex mutations; an Undo before completion is a dependent job.
- We accept writer migration and a new epoch invariant because scanning a mutable folder without one cannot produce an exact atomic deletion set.

## Alternatives considered

- Page the existing clear-and-stamp loop: implementation looks smaller, but it exposes half-deleted folders and cannot return an exact bounded receipt; the caller must coordinate pages and rollback.
- Cap folders at 500 and reject further membership: hides the problem by changing product behavior and leaves existing large folders unresolved.
- One transaction that writes a compressed member manifest: still has unbounded read/write bytes and cannot meet Convex limits at arbitrary count.

## Open questions and fatal risks

- Can all legacy write paths and offline/backfill paths be migrated to bump `membershipEpoch` before jobs are enabled? **If not, this shape is unsafe**: a concurrent member can evade the final comparison.
- Can the owned Saved query, reader, widget, folder-count and export paths all resolve orphan/alias membership consistently? **If not, atomic visibility is false** even if the job is correct.
- Can Convex retain and page per-member facts for the required retention window and later delete them without exceeding storage/cost policy? Actual limits and worst-case tests are required.
- What is the conflict policy for a folder changed continuously during scan? Conservative supersession after bounded retries is safe but requires a visible recoverable result, not an infinite job.

## Next implementation step

Write a red Convex model test with 501+ members, an interleaved newer move, a same-name recreation and offline Undo; assert no partial reader snapshot, exact member dispositions, bounded per-step reads/writes and stable apply/ACK replay before adding job tables.
