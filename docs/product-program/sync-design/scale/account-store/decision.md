# Android local-state transaction decision

October 22, 2026, after `9e2eab9`. Read both caller-first candidates and the independent judgment. Select B, 22/25, over A, 17/25. Parent is the sole implementer. This completes an Android storage prerequisite; it does not switch production Saved observations or complete A2.

## Selected ownership

Guest singleton, per-owner account state and scoped deletion intents now share `library_outcomes.db` version 5 with Saved/outcome evidence. Ordinary guest operations never reconstruct account arrays. Account operations select one exact owner key, validate subject/deployment and update a freshly decoded state inside a synchronous SQLite transaction on IO. Guest claim reads the current guest and account rows, appends every original source including invalid drafts to recovery, and clears the guest row in that same transaction. No suspending callback runs inside SQL transactions.

ACK metadata/account cursor, terminal settlement and retention cursor changes use transaction-local journal helpers. Account mutations bump the existing export clock. Authority-bearing Saved/outcome producers, active reads and export validation check the live account and deletion intent within their own transaction. Historical partitionless evidence remains retained and exportable to its subject/deployment; its former account row is not required or recreated.

This replaces the earlier cutover sketch's required cross-file guest transfer. No user requirement kept guest AtomicFile storage. Keeping it would require permanent transfer receipts, locking, suppression and cleanup states which this shared database removes.

## One-way import

The additive schema does not decode files in `onUpgrade`. Before Ready, every normal journal/local-state transaction rejects authority. Import captures original AtomicFile committed bytes and a normalized canonical source BLOB in the SQLite write transaction. Normalization materializes omitted defaults once, particularly random client UUIDs. Both exact original bytes/hash and canonical source hash are retained until publication.

Staging, ordinal receipt verification and indexed table enumeration operate in steps of at most eight source records or rows. Deletion fences are staged and verified before final publication. Duplicate identical records are fully accounted by source ordinal and coalesce to one domain row; conflicting or ambiguous owners fail with source preserved. The final transaction rechecks source presence/hash, publishes Ready and clears retained source BLOBs. Ready is irreversible for all updated callers. Restored legacy files can never become authority again.

The independent judge originally requested a FileChannel lock for immutable-file capture. The implemented BLOB capture uses the same actual SQLite writer lock for all updated clones/processes, and updated writers never mutate the legacy file. The implementation reviewer accepted this simplification. It removes another lock rather than composing unrelated file/database locks. An unsupported old binary that ignores Ready or rollback of the entire database history remains outside this guarantee.

After Ready, ordinary access retries bounded receipt cleanup and redundant fixed legacy-file cleanup. Account deletion strictly removes legacy base/backup/new files and all source receipts before identity_pending. An unlink failure preserves the durable deletion retry. Guest/sibling database rows remain. Identity-pending reads and deletion-intent clearing verify the scope has no retained account/Saved/outcome/artifact metadata.

## Bounds and evidence limits

Owned payloads use 32 KiB BLOB substr reads to avoid Android CursorWindow row limits. Whole guest/account blobs still allocate, decode, encode and write as a unit. Legacy capture/decode and final source hash are one-time whole-source byte work. Eight-row transactions are not a bounded-byte/latency claim. Queue/positions normalization, practical throughput and full export scale remain open.

iOS already uses one SwiftData container, so this unit adds no second migration. Its 120 selected parity checks pass; future private observation/effective-view adapters must use the same fresh context. Recoverable SwiftData save-failure proof remains open. See [verification](../../../../LIBRARY_LOCAL_STORE_VERIFICATION.md) and [initial implementation review](implementation-review.md). No cloud or deployment occurred.
