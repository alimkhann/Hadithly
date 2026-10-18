import { v, type Infer } from "convex/values";
import { FOLDER_NAME_LIMIT, normalizedFolderName } from "./savedFolderPolicy";
import { readingPositionValidator, parseReadingPosition } from "./readingPositions";
import { textDigest } from "./evidenceReviewPolicy";

export const SYNC_BATCH_LIMIT = 50;
export const SYNC_BATCH_BYTES = 128 * 1024;
export const SYNC_NOTE_BYTES = 24_000;
export const SYNC_FOLDER_LENGTH = FOLDER_NAME_LIMIT;
export const SYNC_BINDING_LIFETIME = 15 * 60_000;
export const SYNC_BINDING_LIMIT = 20;
export const SYNC_RECEIPT_LIMIT = 10_000;

export const syncFolderReference = v.union(
  v.object({ kind: v.literal("server"), id: v.string() }),
  v.object({ kind: v.literal("local"), key: v.string() }),
  v.object({ kind: v.literal("none") }),
);
const target = { hadithId: v.string() };
export const syncCommand = v.union(
  v.object({ kind: v.literal("bookmark_add"), ...target, createdAt: v.number() }),
  v.object({ kind: v.literal("bookmark_remove"), ...target }),
  v.object({ kind: v.literal("favorite_add"), ...target, createdAt: v.number() }),
  v.object({ kind: v.literal("favorite_remove"), ...target }),
  v.object({ kind: v.literal("note_put"), ...target, content: v.string(), createdAt: v.number(), updatedAt: v.number() }),
  v.object({ kind: v.literal("note_remove"), ...target }),
  v.object({ kind: v.literal("folder_create"), key: v.string(), name: v.string(), purpose: v.union(v.literal("guest_claim"), v.literal("create")) }),
  v.object({ kind: v.literal("folder_delete"), folder: syncFolderReference }),
  v.object({ kind: v.literal("membership_put"), ...target, folder: syncFolderReference }),
  v.object({ kind: v.literal("position_put"), position: readingPositionValidator }),
  v.object({ kind: v.literal("legacy_position_put"), hadithId: v.string(), updatedAt: v.number() }),
  v.object({ kind: v.literal("facet_restore"), ...target, deletionId: v.string(), value: v.union(
    v.object({ kind: v.literal("bookmark"), createdAt: v.number() }),
    v.object({ kind: v.literal("favorite"), createdAt: v.number() }),
    v.object({ kind: v.literal("note"), content: v.string(), createdAt: v.number(), updatedAt: v.number() }),
  ) }),
  v.object({ kind: v.literal("folder_restore"), deletionId: v.string(), name: v.string(), hadithIds: v.array(v.string()) }),
);
export const syncOperation = v.object({ id: v.string(), revision: v.string(), at: v.number(), command: syncCommand });
export const syncBatch = v.object({ id: v.string(), operations: v.array(syncOperation) });
export type SyncCommand = Infer<typeof syncCommand>;
export type SyncOperation = Infer<typeof syncOperation>;
export type SyncBatch = Infer<typeof syncBatch>;
export type SyncFolderReference = Infer<typeof syncFolderReference>;

export const syncOutcome = v.union(
  v.object({ kind: v.literal("preserved") }),
  v.object({ kind: v.literal("folder"), folderId: v.id("savedFolders") }),
  v.object({ kind: v.literal("folder_deleted"), hadithIds: v.array(v.id("hadiths")), deletedAt: v.number() }),
  v.object({ kind: v.literal("folder_restored"), folderId: v.id("savedFolders"), restored: v.array(v.string()), superseded: v.array(v.string()), missing: v.array(v.string()) }),
  v.object({ kind: v.literal("resolved_position"), position: readingPositionValidator }),
  v.object({ kind: v.literal("superseded"), reason: v.union(v.literal("newer_cloud"), v.literal("tie_cloud"), v.literal("changed_since_delete")) }),
  v.object({ kind: v.literal("unresolved"), reason: v.union(v.literal("missing_target"), v.literal("missing_folder"), v.literal("missing_saved_item"), v.literal("folder_name_taken"), v.literal("position_unavailable"), v.literal("folder_too_large")) }),
);
export const syncReceipt = v.object({ id: v.string(), revision: v.string(), outcome: syncOutcome });
export type SyncOutcome = Infer<typeof syncOutcome>;
export type SyncReceipt = Infer<typeof syncReceipt>;
export const syncBinding = v.object({ ownerKey: v.string(), subject: v.string(), capability: v.string(), validUntil: v.number() });
export const syncReply = v.object({ ownerKey: v.string(), batchId: v.string(), receipts: v.array(syncReceipt) });
export type SyncBinding = Infer<typeof syncBinding>;
export type SyncReply = Infer<typeof syncReply>;

function identifier(value: string): boolean { return /^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(value); }
function timestamp(value: number): boolean { return Number.isFinite(value) && value >= 0; }
function folderName(value: string): boolean {
  try { normalizedFolderName(value); return true; }
  catch { return false; }
}

function reference(value: SyncFolderReference): boolean {
  return value.kind === "none" || (value.kind === "local" ? identifier(value.key) : value.id.length > 0 && value.id.length <= 128);
}

/** Convex validates the wire shape; this boundary validates size and domain values. */
export function validateSyncBatch(batch: SyncBatch, now: number): void {
  const validTime = (value: number) => timestamp(value) && value <= now + 5 * 60_000;
  if (!identifier(batch.id) || batch.operations.length === 0 || batch.operations.length > SYNC_BATCH_LIMIT ||
    new TextEncoder().encode(JSON.stringify(batch)).byteLength > SYNC_BATCH_BYTES) throw new Error("SYNC_INVALID_BATCH");
  const ids = new Set<string>();
  for (const operation of batch.operations) {
    if (!identifier(operation.id) || !identifier(operation.revision) || ids.has(operation.id) || !validTime(operation.at)) throw new Error("SYNC_INVALID_OPERATION");
    ids.add(operation.id);
    const command = operation.command;
    if ("hadithId" in command && (!command.hadithId || command.hadithId.length > 128)) throw new Error("SYNC_INVALID_TARGET");
    if ("createdAt" in command && !validTime(command.createdAt)) throw new Error("SYNC_INVALID_OPERATION");
    switch (command.kind) {
      case "note_put":
        if (!validTime(command.updatedAt) || command.content.length === 0 || new TextEncoder().encode(command.content).byteLength > SYNC_NOTE_BYTES) throw new Error("SYNC_INVALID_NOTE");
        break;
      case "folder_create":
        if (!identifier(command.key) || !folderName(command.name)) throw new Error("SYNC_INVALID_FOLDER");
        break;
      case "folder_delete":
      case "membership_put":
        if (!reference(command.folder) || command.kind === "folder_delete" && command.folder.kind === "none") throw new Error("SYNC_INVALID_FOLDER");
        break;
      case "position_put":
        parseReadingPosition(command.position);
        if (!validTime(command.position.updatedAt)) throw new Error("SYNC_INVALID_OPERATION");
        break;
      case "legacy_position_put": if (!validTime(command.updatedAt)) throw new Error("SYNC_INVALID_OPERATION"); break;
      case "facet_restore":
        if (!identifier(command.deletionId) || !validTime(command.value.createdAt) || command.value.kind === "note" && (!validTime(command.value.updatedAt) || !command.value.content || new TextEncoder().encode(command.value.content).byteLength > SYNC_NOTE_BYTES)) throw new Error("SYNC_INVALID_RESTORE");
        break;
      case "folder_restore":
        if (!identifier(command.deletionId) || !folderName(command.name) || command.hadithIds.length > 500 || new Set(command.hadithIds).size !== command.hadithIds.length || command.hadithIds.some(id => !id || id.length > 128)) throw new Error("SYNC_INVALID_RESTORE");
        break;
      case "bookmark_add": case "bookmark_remove": case "favorite_add": case "favorite_remove": case "note_remove": break;
      default: { const exhaustive: never = command; return exhaustive; }
    }
  }
}

export async function syncBatchDigest(batch: SyncBatch): Promise<string> {
  // Explicit field order keeps request-object property order out of identity.
  return textDigest(JSON.stringify([batch.id, batch.operations.map(op => [op.id, op.revision, op.at, canonicalSyncValue(op.command)])]));
}
function canonicalSyncValue(value: unknown): unknown {
  if (Array.isArray(value)) return value.map(canonicalSyncValue);
  if (value !== null && typeof value === "object") {
    return Object.fromEntries(Object.entries(value).sort(([a], [b]) => a.localeCompare(b)).map(([key, child]) => [key, canonicalSyncValue(child)]));
  }
  return value;
}

export function syncReceiptSetMatches(batch: SyncBatch, receipts: readonly SyncReceipt[]): boolean {
  if (receipts.length !== batch.operations.length) return false;
  const expected = new Map(batch.operations.map(op => [op.id, op.revision]));
  for (const receipt of receipts) {
    if (expected.get(receipt.id) !== receipt.revision) return false;
    expected.delete(receipt.id);
  }
  return expected.size === 0;
}

/** Equality preserves an add/value even if a newer clock already carries it. */
export function syncWriteDecision(input: { at: number; cloudAt: number | null; same: boolean }): "preserved" | "apply" | "newer_cloud" | "tie_cloud" {
  if (input.same) return "preserved";
  if (input.cloudAt === null || input.at > input.cloudAt) return "apply";
  return input.at === input.cloudAt ? "tie_cloud" : "newer_cloud";
}
