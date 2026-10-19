# Candidate A: native row journal with a compact partition checkpoint

## Problem

A terminal folder receipt is bounded while its historical members can number in the thousands. Today iOS stores `LibraryPartitionState` as JSON in one SwiftData `GuestLibraryPartition` row, Android rewrites one AtomicFile JSON store, and both settlement methods throw on manifest outcomes (`GuestMergePlanner.swift:525-546`, `LibrarySync.kt:222-247`). Expanding either partition with identities would reintroduce unbounded writes. The journal must be owner- and receipt-bound, survive a crash between its database and the Android JSON checkpoint, and delay ACK until complete evidence or an explicit unavailable result is durable.

## Usage (caller's view)

`LibrarySync.run` continues to own the session and transport. On an accepted isolated folder frame it calls `outcomes.collect(owner, frozen, committed, fetchPage)`; this returns `ready(checkpoint)` only after journal verification. The coordinator then calls `store.settleManifest(checkpoint, owner)` and only afterward enters its existing ACK branch. A retry after a lost page/checkpoint response calls `collect` again with the same proof; a duplicate becomes a no-op or fails closed if contents differ. `UserLibraryModel` still asks `LibraryProjection` for Saved rows; it never pages. Export calls `outcomes.exportRetained(subject, namespace, owner)` alongside the portable partition; account deletion calls `outcomes.erase(subject, namespace)` even if the partition row vanished.

```text
// iOS LibrarySync.run / Android LibrarySync.run, after accepted or polled terminal proof
let result = try await outcomes.collect(owner: owner, source: frozen?, proof: committed, fetch: transport.outcomePage)
try store.settleManifest(result.checkpoint, owner: owner)  // compact JSON only
// next loop may ACK; never ACK a merely fetched or partly persisted page

// Saved subscription boundary
store.cacheSavedSnapshot(snapshot, owner) // version monotonic; prune only overlays covered by revision
projection = LibraryProjection(partition)  // no journal scan, no speculative member subset

// export / deletion boundary
export = (portablePartition, outcomes.exportRetained(subject, namespace, owner))
outcomes.erase(subject, namespace) // keyed by captured subject + namespace, scans orphan rows too
```

## Shape

`OutcomeJournal` is one deep interface shared conceptually across Swift/Kotlin: `collect(owner, source?, committed, fetchPage) -> VerifiedCheckpoint`, `proof(checkpoint) -> Ready|Incomplete|Unavailable`, `exportRetained(subject, namespace, owner) -> bounded stream`, `pruneAfterAckAndSavedRevision(owner, sequence, observedVersion)`, `erase(subject, namespace)`. The coordinator sees domain `VerifiedCheckpoint`, not wire pages. `fetchPage` takes an opaque server-bound request and returns a parsed bounded page; parsing/validation lives in the journal boundary. `VerifiedCheckpoint` is constructible only after durable terminal state; no raw `SyncOutcome` or arbitrary cursor can trigger ACK.

Persistence: one `OutcomeHeader` per `(namespace, subject, ownerKey, clientKey, sequence, batchId, digest, receiptId, receiptRevision)` with manifest ID/generation, receipt kind, expected count/category totals, saved revision, collection state (`collecting|complete|unavailable`), contiguous next ordinal and terminal proof. One `OutcomeMember` per `(headerId, ordinal)` stores hadith ID and immutable disposition; a second uniqueness check on `(headerId, category, hadithId)` rejects repeated identities. For deletion the category is `original`; for restore it is `restored|superseded|missing`. Each server response is bounded to 50 small rows and 64 KiB, carries exact receipt identity, requested ordinal, next ordinal, end flag and category totals. Validate proof binding, strictly increasing contiguous ordinals, exact count arithmetic, category disjointness, UTF-8/ID bounds and terminal totals before insertion. A repeated page must match every persisted row and endpoint; a different page at an occupied ordinal is a conflict, never replacement. `unavailable` is a distinct durable terminal header with zero *collected* detail and retained local source, not a fabricated complete set. A same-ID different-command fork cannot attach because the proof and local `intentDigest` must match; otherwise keep its source in historical recovery and use only server proof for ACK.

Swift: add `GuestOutcomeHeader`/`GuestOutcomeMember` SwiftData models to `GuestDataStore` schema. Persist each page's rows plus header continuation in one `ModelContext.save`; terminal header and compact partition settlement can be one SwiftData transaction, but the protocol must tolerate separate saves. Android: add a private SQLite journal (`SQLiteOpenHelper` or Room) in `core/data`; each page insert plus header advance is one SQLite transaction. AtomicFile JSON cannot join that transaction, so order **journal complete first, JSON checkpoint second, ACK third**. Reopen reconciles the JSON checkpoint from an exactly matching complete SQLite header, or resumes SQLite from its ordinal. If JSON says ready but SQLite is absent/conflicting, fail closed and retain the frozen frame; never infer readiness from JSON alone. Do not append page rows, full recovery lists or result members to the AtomicFile. The compact checkpoint holds header key, terminal status, proof digest, saved revision, aggregate totals and ACK state.

The journal is the sole source for detailed recovery/export. Successful details may be pruned only after server ACK *and* an authoritative Saved snapshot whose revision is at least the receipt's Saved revision. Partial/unavailable evidence and locally available original source stay retained/exportable; no retention timer silently discards them. For bounded restore the projection never applies `command.hadithIds` as a guessed full result: until the authoritative revision arrives, it shows the prior base plus unaffected local changes and a pending/confirmed operation state; at or above that revision the base wins and the overlay is removed. The same revision fence prevents an old confirmed delete overlay from masking a newer Saved base. Current `pruneConfirmed` already uses Saved versions (`GuestMergePlanner.swift:423`, `LibrarySync.kt:194`); extend its domain rule rather than asking views to inspect pages. Session generation and owner checks must occur before fetch, after await and before every write/ACK; storage itself checks captured subject/namespace/owner and account-deletion phase.

Module map: `OutcomeJournal.swift` + SwiftData models beside `GuestDataStore`; `OutcomeJournal.kt` + SQLite helper beside `GuestStore`; wire decoder in `GuestDataModels.swift`/`LibrarySyncWire.kt`; `LibrarySync` orchestrates and `LibraryProjection` consumes only compact revision state. Backend page query is a dependency, not invented here.

## Synthesis decision

Candidate A is the native row-journal base for comparison. Graft only if another candidate shows a smaller crash-consistent surface with equal per-row uniqueness and orphan erasure.

## Tradeoffs accepted

- We accept two local persistence mechanisms on Android in exchange for bounded SQLite page commits; a strict rows-first/checkpoint-second recovery protocol pays for the missing cross-store transaction.
- We accept a SwiftData schema migration and extra local rows in exchange for avoiding a growing partition blob.
- We accept temporary absence of optimistic large-restore membership in exchange for a Saved-revision-backed projection with no guessed partial result.

## Alternatives considered

A separate atomic file per page plus JSON manifest avoids SQLite, but directory sync, rename durability, duplicate-page detection, orphan discovery and erasure become caller-visible filesystem protocol. A single expanded JSON partition keeps one transaction but every page rewrites all prior identities and violates the scale constraint. Neither hides more complexity behind the same small coordinator interface.

## Open questions and risks

Can the server page boundary return stable ordinal/category rows plus an explicit unavailable terminal under the same receipt proof after detail expiry? Can installed SwiftData schema migration add the two models without sacrificing existing local guest data? How will export stream rows within its existing size and privacy limits rather than building one unbounded object? These are cutover gates, as are old installed cache scale, public producer/read-export cutover, hosted limits and native device proof.

## Next implementation step

Write real-store crash/reopen tests around one exact receipt with duplicate/conflicting pages and an Android SQLite-complete/AtomicFile-stale boundary, then implement the journal behind those tests.
