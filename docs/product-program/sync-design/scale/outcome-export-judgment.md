# Outcome export cross-judge

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Mode: read-only architect/arena cross-judge

## Verdict

Use Candidate A as the base. Its subject-plus-namespace mutation clock gives one stable inventory across bounded reads without pausing journal collection. Graft Candidate B's pure export read split, staging registry and honest external-publication limits. Do not graft the revocable writer lease as the main consistency mechanism.

This design closes no settlement, ACK, pruning, installed-migration, full-export scale or product gate. The current server and partition values still materialize in memory, and neither platform currently exports journal evidence.

## Scores

| Criterion | A | B | Judgment |
| --- | ---: | ---: | --- |
| Exact captured ownership and orphan coverage | 4 | 4 | Both key control by subject plus namespace and include old-owner orphans. A needs an explicit indexed iOS inventory and backfill before it can prove discovery. |
| Snapshot correctness across insertion, verification, pruning and erasure | 5 | 3 | A detects every committed mutation without blocking writers. B works only if every current and future mutator obeys a lease guard and introduces expiry/recovery behavior into writes. |
| Bounded reads/writes and streamed artifact | 4 | 4 | Both page headers and rows. Neither fixes the existing in-memory server/partition export, which remains an open gate. |
| Crash, cancel, migration and cleanup safety | 4 | 4 | Both stage privately and sweep abandoned files. A needs durable erase/tombstone handling after fence deletion; B has more stale-lease states. |
| Deep store/coordinator interface and real-store proof plan | 5 | 4 | A gives Settings one prepare/cancel/erase boundary and names installed SwiftData and SQLite migration tests. B's interface is clean but its lease affects every journal writer. |

Totals: A 22/25. B 19/25.

## Source-grounded findings

- iOS currently stores `GuestOutcomeScope`, `GuestOutcomeHeader` and `GuestOutcomeMember` in SwiftData. Headers carry subject, namespace and old owner key, so export must discover by subject plus namespace rather than through the current partition.
- iOS outcome collection uses fresh `ModelContext` instances, while `GuestDataStore` is `@MainActor`. A revision bump must commit in the same context/save as each journal mutation. MainActor serialization alone does not make two separate saves atomic.
- The current iOS schema has no export fence or subject inventory model. Header keys are binding hashes, not an ordered subject prefix. A bounded `GuestOutcomeInventory` with a unique length-prefixed subject/namespace/collection key is required on iOS 17, where this design cannot assume newer SwiftData compound-index facilities.
- Android is SQLite schema version 1. `onUpgrade` currently throws. The design needs a tested v1 to v2 migration for the subject clock and `headers(subject, namespace, collection_key)` discovery index. Wiping or rebuilding the journal is not acceptable.
- Verification mutates `checkpointData` on both platforms. Export must use a pure read path; it cannot call the existing verifying collector while streaming.
- Current iOS Settings builds server and local values in memory and writes a temporary file before `ShareLink`. Android builds one `JsonObject` in memory and writes directly to a `CreateDocument` URI. Journal streaming alone does not make the whole export bounded.
- Existing erasure already scans subject plus namespace and covers old-owner rows in bounded batches. The clock must integrate with that path rather than introduce current-owner-only state.

## Required corrections to Candidate A

1. Use exactly one clock per `(captured Clerk subject, deployment namespace)`. Do not key revisions by current owner, partition, scope generation or collection. Every header, member, checkpoint, verification, prune, repair and erase mutation for any old owner key must bump that clock in the same transaction.
2. Treat a missing clock as invalid after migration begins. Never lazily create a clock during export or from a late writer. Creation belongs to the centralized journal mutation boundary and must respect the existing deletion intent.
3. Add an indexed iOS inventory model. Backfill existing headers in bounded primary-key pages, writing inventory rows and bumping the subject clock in the same save. Mark migration complete only after a second bounded reconciliation proves no source headers were skipped. Export refuses while migration is incomplete.
4. Preserve ownership from persisted header fields and decoded binding, and require both to match the captured subject/namespace. Include old-owner orphans even when their partition or scope row is gone. Reject foreign subject/namespace rows rather than silently skipping malformed matches.
5. On Android, migrate the installed v1 database in one schema transaction, then backfill/validate controls as bounded post-migration work before enabling export. Test reopen from an actual v1 file, interruption, duplicate rows and corrupt owner fields.
6. Erasure first marks the subject clock `erasing` and bumps it atomically. Keep the durable deletion/tombstone authority until every outcome row, inventory row, private staging record and file is gone. Removing the clock must not let a late callback recreate journal state.
7. Check the token before and after every bounded page and immediately before sealing. A revision mismatch restarts from a new private file; never append a new revision to the old file.
8. `PublishedExport` should mean a sealed app-private artifact, not externally published bytes. The type must own cleanup and expose no path before the final clock/session/deletion check.

## Minimal grafts from Candidate B

- Split verification from export reads. Serialize the persisted checkpoint and honest `collecting`, `verifying`, `complete` or `unavailable` state without mutating it.
- Keep a private staging registry keyed by opaque artifact ID plus subject/namespace. Startup, cancellation, account switch and erasure remove registry entries and files in bounded work. Filenames contain no raw subject.
- State the platform publication limit in the contract and verification record. Android SAF and iOS share handoff cannot guarantee rollback or revocation after another provider/app accepts bytes.
- Test the actual destination path. Private staging proves that no partial artifact is offered before handoff. Strict deletion-race invalidation during an external copy remains open unless the chosen destination supports atomic commit and deletion or the product accepts the irreversible handoff boundary.

## Acceptance tests that must precede any completion claim

- Insert and delete a header that sorts before the discovery cursor; export must abort and remove staging.
- Mutate a checkpoint, finish verification, prune rows and repair an orphan between every page boundary; each must change the same subject clock.
- Export two owner keys for the same subject/namespace, including a partitionless header; exclude another subject and another namespace.
- Start erasure before discovery, during row streaming, after sealing and during destination handoff. Prove the exact boundary the app controls and retain the external-publication limitation where it does not.
- Reopen actual pre-change SwiftData and SQLite stores, run bounded inventory backfill, interrupt/retry it, and prove no journal loss or duplicate inventory.
- Inject disk-full, save failure, cancellation and process death. No partial file may be shareable, and abandoned private artifacts must be swept.
- Parse the final JSON. Preserve every existing server/local field and exact user note text, structurally exclude capability/provider-passage fields, export bounded journal pages, and distinguish collected-prefix end from complete receipt detail.
- Measure page limits and heap behavior with large journals. Keep existing server/partition accumulation recorded as a separate red gate.

Attention: ownership clock centralization, iOS 17 inventory/backfill, installed SQLite migration, durable erase tombstone, and external publication semantics are mandatory before implementation can be called safe.
