import type { Doc, Id } from "../_generated/dataModel";
import type { LibrarySyncProtocol } from "./librarySyncIdentity";
import type { MutationCtx } from "../_generated/server";
import { libraryVersion } from "./librarySyncVersions";
import { syncBatchDigest, syncIntentDigest, syncReceiptSetMatches, type SyncCursor, type SyncExchange, type SyncFrame, type SyncOutcome } from "./librarySyncPolicy";

export function assertSyncProtocolCursor(protocol: LibrarySyncProtocol, cursor: SyncCursor): void {
  if (protocol === "manifest_v2" || !cursor.outstanding) return;
  const slot = cursor.outstanding;
  if (slot.kind === "pending" || slot.committed.reply.receipts.some(receipt => receipt.outcome.kind === "folder_deleted_manifest" || receipt.outcome.kind === "folder_restored_manifest" || receipt.outcome.kind === "batch_requires_split")) throw new Error("SYNC_CLIENT_UPGRADE_REQUIRED");
}
export function protocolExchange(protocol: LibrarySyncProtocol, exchange: SyncExchange): SyncExchange {
  if (protocol === "inline_v1") {
    if (exchange.kind === "pending" || exchange.kind === "accepted" && exchange.committed.reply.receipts.some(receipt => receipt.outcome.kind === "folder_deleted_manifest" || receipt.outcome.kind === "folder_restored_manifest" || receipt.outcome.kind === "batch_requires_split")) throw new Error("SYNC_CLIENT_UPGRADE_REQUIRED");
    if (exchange.kind === "reconcile") assertSyncProtocolCursor(protocol, exchange.cursor);
  }
  return exchange;
}

export function librarySyncCursor(stream: Doc<"librarySyncStreams"> | null): SyncCursor {
  const slot = stream?.slot;
  return { closedThrough: stream?.closedThrough ?? 0, ...(slot ? { outstanding: slot.kind === "pending" ? { kind: "pending", pending: slot.pending } : slot } : {}) };
}

export function existingFrameExchange(ownerKey: string, frame: SyncFrame, digest: string, stream: Doc<"librarySyncStreams"> | null): SyncExchange | null {
  const cursor = librarySyncCursor(stream), slot = stream?.slot;
  const proof = slot?.kind === "pending" ? { sequence: slot.pending.sequence, batchId: slot.pending.batchId, digest: slot.pending.digest }
    : slot ? { sequence: slot.committed.sequence, batchId: slot.committed.reply.batchId, digest: slot.committed.digest } : null;
  if (frame.sequence !== cursor.closedThrough + 1 || proof && (proof.sequence !== frame.sequence || proof.batchId !== frame.batch.id || proof.digest !== digest)) {
    return { kind: "reconcile", ownerKey, clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id, cursor };
  }
  if (!slot) return null;
  if (slot.kind === "pending") return { kind: "pending", ownerKey, pending: slot.pending };
  if (!syncReceiptSetMatches(frame.batch, slot.committed.reply.receipts)) throw new Error("SYNC_INVALID_RECEIPT");
  return { kind: "accepted", committed: slot.committed };
}

/** Called only after the public adapter validates owner, frame and current stream. */
export async function holdFolderFrame(ctx: MutationCtx, userId: Id<"users">, frame: SyncFrame,
  work: { id: Id<"savedFolderManifests">; generation: string }): Promise<SyncExchange> {
  if (!await ctx.db.get(userId)) throw new Error("SYNC_ACCOUNT_MISSING");
  const operation = frame.batch.operations[0];
  if (frame.batch.operations.length !== 1 || operation.command.kind !== "folder_delete" && operation.command.kind !== "folder_restore") throw new Error("SYNC_FOLDER_FRAME_NOT_ISOLATED");
  const digest = await syncBatchDigest(frame.batch);
  const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", userId).eq("clientKey", frame.clientKey)).unique();
  const existing = existingFrameExchange(userId, frame, digest, stream);
  if (existing) return existing;
  const header = await ctx.db.get(work.id);
  if (header?.userId !== userId || header.generation !== work.generation || header.expiresAt <= Date.now()) throw new Error("SYNC_WORK_MISMATCH");
  if (operation.command.kind === "folder_delete") {
    const reference = operation.command.folder;
    const alias = reference.kind === "local" ? await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", reference.key)).unique() : null;
    const target = reference.kind === "server" ? reference.id : alias?.folderId;
    if (header.operationId !== operation.id || header.requestedAt !== operation.at || header.folderId !== target || header.state.kind !== "scanning" && header.state.kind !== "prepared") throw new Error("SYNC_WORK_MISMATCH");
    if (header.heldBy) throw new Error("SYNC_WORK_ALREADY_BOUND");
    const folder = await ctx.db.get(header.folderId);
    if (folder?.userId !== userId || (folder.membershipEpoch ?? 0) !== header.captured.epoch || folder.updatedAt !== header.captured.updatedAt) throw new Error("SYNC_WORK_CHANGED");
  } else {
    if (header.operationId !== operation.command.deletionId || header.state.kind !== "restoring" || header.state.operationId !== operation.id || header.state.at !== operation.at) throw new Error("SYNC_WORK_MISMATCH");
    if (header.restoreHeldBy) throw new Error("SYNC_WORK_ALREADY_BOUND");
  }
  const pending = { clientKey: frame.clientKey, sequence: frame.sequence, batchId: frame.batch.id, digest, intentDigest: await syncIntentDigest(frame.batch),
    manifestId: header._id, generation: header.generation, retryAfterMs: 1_000 };
  const slot = { kind: "pending", pending, batch: frame.batch } satisfies NonNullable<Doc<"librarySyncStreams">["slot"]>;
  const streamId = stream?._id ?? await ctx.db.insert("librarySyncStreams", { userId, clientKey: frame.clientKey, closedThrough: 0, slot });
  if (stream) await ctx.db.patch(streamId, { slot });
  const binding = { streamId, sequence: frame.sequence, digest };
  await ctx.db.patch(header._id, operation.command.kind === "folder_delete" ? { heldBy: binding } : { restoreHeldBy: binding });
  return { kind: "pending", ownerKey: userId, pending };
}

/** Failure proof commits before temporary work can be purged; no library effect is claimed. */
export async function failHeldFolderFrame(ctx: MutationCtx, header: Doc<"savedFolderManifests">,
  reason: "changed" | "missing_folder" | "expired"): Promise<void> {
  const outcome: SyncOutcome = reason === "changed" ? { kind: "superseded", reason: "changed_since_delete" }
    : { kind: "unresolved", reason: reason === "expired" ? "preparation_expired" : "missing_folder" };
  await publishHeldFolderOutcome(ctx, header, outcome, "delete");
}

export async function publishHeldFolderOutcome(ctx: MutationCtx, header: Doc<"savedFolderManifests">, outcome: SyncOutcome, phase: "delete" | "restore"): Promise<boolean> {
  const held = phase === "delete" ? header.heldBy : header.restoreHeldBy;
  if (!held || !await ctx.db.get(header.userId)) return false;
  const stream = await ctx.db.get(held.streamId), slot = stream?.slot;
  if (stream?.userId !== header.userId || slot?.kind !== "pending" || slot.pending.sequence !== held.sequence || slot.pending.digest !== held.digest
    || slot.pending.manifestId !== header._id || slot.pending.generation !== header.generation) return false;
  const committed = { clientKey: stream.clientKey, sequence: held.sequence, digest: held.digest,
    revision: { saved: await libraryVersion(ctx, header.userId, "saved"), position: await libraryVersion(ctx, header.userId, "position") },
    reply: { ownerKey: header.userId, batchId: slot.batch.id, receipts: slot.batch.operations.map(op => ({ id: op.id, revision: op.revision, outcome })) } };
  await ctx.db.patch(stream._id, { slot: { kind: "committed", committed } });
  return true;
}
