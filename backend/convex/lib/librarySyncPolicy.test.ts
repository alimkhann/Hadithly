import { syncValidatorContract } from "../../test/librarySyncContract";
import { afterAll, expect, test } from "vitest";
import { syncBatchDigest, syncIntentDigest, syncReceiptSetMatches, syncWriteDecision, validateSyncBatch, type SyncBatch } from "./librarySyncPolicy";
const operation = { id: "note-1", revision: "revision-1", at: 1_000, command: { kind: "note_put", hadithId: "target", content: "private fixture", createdAt: 1_000, updatedAt: 1_000 } } satisfies SyncBatch["operations"][number];
const batch = { id: "batch-1", operations: [operation] } satisfies SyncBatch;
const intentVectors: SyncBatch[] = [batch,
  { id: "unicode", operations: [{ id: "note", revision: "r1", at: 1e-7, command: { kind: "note_put", hadithId: "target", content: "العربية 🙂 é \n \\ / \"", createdAt: 0, updatedAt: 1e20 } }] },
  { id: "folders", operations: [{ id: "delete", revision: "r2", at: 1_000, command: { kind: "folder_delete", folder: { kind: "server", id: "folder-a" } } }] },
];

test("cross-native intent fingerprint ignores property order but distinguishes commands with reused IDs", async () => {
  expect(await syncIntentDigest(batch)).toBe(await syncIntentDigest({ operations: batch.operations, id: batch.id }));
  expect(await syncIntentDigest(batch)).not.toBe(await syncIntentDigest({ ...batch, operations: [{ ...operation, command: { ...operation.command, content: "different" } }] }));
});

test("receipt matching requires every exact operation and revision once", () => {
  expect(syncReceiptSetMatches(batch, [{ id: operation.id, revision: operation.revision, outcome: { kind: "preserved" } }])).toBe(true);
  expect(syncReceiptSetMatches(batch, [])).toBe(false);
  expect(syncReceiptSetMatches(batch, [{ id: operation.id, revision: "newer-revision", outcome: { kind: "preserved" } }])).toBe(false);
  expect(syncReceiptSetMatches({ ...batch, operations: [operation, { ...operation, id: "note-2" }] }, [
    { id: operation.id, revision: operation.revision, outcome: { kind: "preserved" } },
    { id: operation.id, revision: operation.revision, outcome: { kind: "preserved" } },
  ])).toBe(false);
});

test("batch admission bounds work and bytes without silently truncating", () => {
  expect(() => validateSyncBatch(batch, 2_000)).not.toThrow();
  expect(() => validateSyncBatch({ ...batch, operations: [] }, 2_000)).toThrow("INVALID_BATCH");
  expect(() => validateSyncBatch({ ...batch, operations: Array.from({ length: 51 }, (_, index) => ({ ...operation, id: `note-${index}` })) }, 2_000)).toThrow("INVALID_BATCH");
  expect(() => validateSyncBatch({ ...batch, operations: [operation, operation] }, 2_000)).toThrow("INVALID_OPERATION");
  expect(() => validateSyncBatch({ ...batch, operations: [{ ...operation, at: Infinity }] }, 2_000)).toThrow("INVALID_OPERATION");
  expect(() => validateSyncBatch({ ...batch, operations: [{ ...operation, at: 1_000_000 }] }, 2_000)).toThrow("INVALID_OPERATION");
  expect(() => validateSyncBatch({ ...batch, operations: [{ ...operation, command: { ...operation.command, content: "ع".repeat(12_001) } }] }, 2_000)).toThrow("INVALID_NOTE");
});

test("nested data clocks cannot bypass the operation clock bound", () => {
  const future = 1_000_000;
  for (const command of [
    { ...operation.command, createdAt: future },
    { ...operation.command, updatedAt: future },
    { kind: "legacy_position_put", hadithId: "target", updatedAt: future },
    { kind: "facet_restore", hadithId: "target", deletionId: "remove", value: { kind: "note", content: "fixture", createdAt: 1_000, updatedAt: future } },
  ] satisfies SyncBatch["operations"][number]["command"][]) {
    expect(() => validateSyncBatch({ ...batch, operations: [{ ...operation, command }] }, 2_000)).toThrow("SYNC_INVALID");
  }
});

test("one batch cannot multiply the bounded folder membership fanout", () => {
  expect(() => validateSyncBatch({ id: "fanout-batch", operations: [1, 2].map(index => ({ id: `delete-${index}`, revision: "r1", at: 1_000, command: { kind: "folder_delete", folder: { kind: "local", key: `folder-${index}` } } })) }, 2_000)).toThrow("SYNC_INVALID_BATCH");
});

test("semantic equality differs from a different cloud winner or a missing clock", () => {
  expect(syncWriteDecision({ at: 1, cloudAt: 2, same: true })).toBe("preserved");
  expect(syncWriteDecision({ at: 1, cloudAt: 2, same: false })).toBe("newer_cloud");
  expect(syncWriteDecision({ at: 2, cloudAt: 2, same: false })).toBe("tie_cloud");
  expect(syncWriteDecision({ at: 3, cloudAt: 2, same: false })).toBe("apply");
  expect(syncWriteDecision({ at: 1, cloudAt: null, same: false })).toBe("apply");
});

test("batch identity is stable across object property order and changes with intent", async () => {
  const reordered: SyncBatch = { operations: [{ command: { updatedAt: 1_000, createdAt: 1_000, content: "private fixture", hadithId: "target", kind: "note_put" }, at: 1_000, revision: "revision-1", id: "note-1" }], id: "batch-1" };
  expect(await syncBatchDigest(batch)).toBe(await syncBatchDigest(reordered));
  expect(await syncBatchDigest(batch)).not.toBe(await syncBatchDigest({ ...batch, operations: [{ ...operation, command: { ...operation.command, content: "Different intent" } }] }));
});


afterAll(async () => {
  const directory = process.env.HADITHLY_LIBRARY_SYNC_CONTRACT_DIR;
  if (!directory) return;
  const { mkdirSync, writeFileSync } = await import("node:fs");
  const { resolve } = await import("node:path");
  const policy = await import("./librarySyncPolicy");
  const { readingPositionValidator } = await import("./readingPositions");
  mkdirSync(directory, { recursive: true });
  const validators = { SyncFolderReference: syncValidatorContract(policy.syncFolderReference), SyncCommand: syncValidatorContract(policy.syncCommand),
    SyncOperation: syncValidatorContract(policy.syncOperation), SyncBatch: syncValidatorContract(policy.syncBatch), SyncOutcome: syncValidatorContract(policy.syncOutcome),
    SyncReceipt: syncValidatorContract(policy.syncReceipt), SyncBinding: syncValidatorContract(policy.syncBinding), SyncReply: syncValidatorContract(policy.syncReply),
    SyncDeletionAuthorization: syncValidatorContract(policy.syncDeletionAuthorization), SyncDeletionResult: syncValidatorContract(policy.syncDeletionResult),
    SyncRevision: syncValidatorContract(policy.syncRevision), SyncHadithSummary: syncValidatorContract(policy.syncHadithSummary),
    SyncSavedItem: syncValidatorContract(policy.syncSavedItem), SyncFolderRow: syncValidatorContract(policy.syncFolderRow), SyncPositionRow: syncValidatorContract(policy.syncPositionRow),
    SyncSavedSnapshot: syncValidatorContract(policy.syncSavedSnapshot), SyncPositionsSnapshot: syncValidatorContract(policy.syncPositionsSnapshot),
    SyncFrame: syncValidatorContract(policy.syncFrame), SyncCommitted: syncValidatorContract(policy.syncCommitted),
    SyncPending: syncValidatorContract(policy.syncPending), SyncOutstanding: syncValidatorContract(policy.syncOutstanding),
    SyncCursor: syncValidatorContract(policy.syncCursor), SyncAcknowledgement: syncValidatorContract(policy.syncAcknowledgement),
    SyncExchange: syncValidatorContract(policy.syncExchange), SyncAckReply: syncValidatorContract(policy.syncAckReply),
    ReadingPosition: syncValidatorContract(readingPositionValidator) };
  const intentDigests = await Promise.all(intentVectors.map(async value => ({ json: JSON.stringify(value), digest: await syncIntentDigest(value) })));
  writeFileSync(resolve(directory, "contract.json"), JSON.stringify({ ...validators, intentDigests, limits: { operations: policy.SYNC_BATCH_LIMIT, fanoutOperations: policy.SYNC_FANOUT_LIMIT, bytes: policy.SYNC_BATCH_BYTES, noteBytes: policy.SYNC_NOTE_BYTES, folderLength: policy.SYNC_FOLDER_LENGTH } }, null, 2) + "\n");
});
