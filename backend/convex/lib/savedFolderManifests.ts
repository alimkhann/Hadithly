import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { savedFolderScanGuard, assertSavedFolderStable } from "./savedMembership";
import { failHeldFolderFrame } from "./librarySyncFrames";
import { expireFolderTransition } from "./savedFolderTransitions";
import { librarySyncMark } from "./librarySyncMarks";

export const FOLDER_MANIFEST_PAGE = 50;
export const FOLDER_MANIFEST_READ_BYTES = 2 * 1024 * 1024;
export const FOLDER_MANIFEST_LEASE_MS = 30 * 60_000;
const ACTIVE_PREPARATIONS = 4;
type Header = Doc<"savedFolderManifests">;
type Reason = Extract<Header["state"], { kind: "abandoned" }>["reason"];
export type FolderManifestPreparation = { kind: "manifest"; id: Header["_id"]; generation: string }
  | { kind: "conflict"; reason: Reason | "missing_owner" | "newer_cloud" | "folder_busy" | "owner_busy" };
export type FolderManifestStep = { kind: "ignored" } | { kind: "scanning" | "prepared"; count: number; read: number }
  | { kind: "abandoned"; reason: Reason };

/** Internal domain entry. The later frame adapter supplies its verified owner and validated operation. */
export async function prepareFolderManifest(ctx: MutationCtx, userId: Id<"users">,
  operation: { id: string; at: number; folderId: Id<"savedFolders"> }): Promise<FolderManifestPreparation> {
  if (!await ctx.db.get(userId)) return { kind: "conflict", reason: "missing_owner" };
  const existing = await ctx.db.query("savedFolderManifests").withIndex("by_user_operation", q => q.eq("userId", userId).eq("operationId", operation.id)).unique();
  if (existing) {
    if (existing.folderId !== operation.folderId || existing.requestedAt !== operation.at) throw new Error("FOLDER_MANIFEST_OPERATION_CONFLICT");
    if (existing.state.kind === "abandoned" || existing.state.kind === "purging") return { kind: "conflict", reason: existing.state.reason };
    if (existing.state.kind !== "scanning" && existing.state.kind !== "prepared") return { kind: "conflict", reason: "changed" };
    const current = await ctx.db.get(existing.folderId);
    const reason = existing.expiresAt <= Date.now() ? "expired"
      : current?.userId !== userId ? "missing_folder"
        : (current.membershipEpoch ?? 0) !== existing.captured.epoch || current.updatedAt !== existing.captured.updatedAt ? "changed" : null;
    if (reason) {
      await abandon(ctx, existing, reason);
      return { kind: "conflict", reason };
    }
    return { kind: "manifest", id: existing._id, generation: existing.generation };
  }
  const folder = await ctx.db.get(operation.folderId);
  if (folder?.userId !== userId) return { kind: "conflict", reason: "missing_folder" };
  await assertSavedFolderStable(ctx, folder);
  const guard = await savedFolderScanGuard(ctx, folder);
  if (folder.updatedAt > operation.at || (guard.latestAt ?? 0) > operation.at) return { kind: "conflict", reason: "newer_cloud" };
  for (const phase of ["scanning", "prepared"] as const) {
    if (await ctx.db.query("savedFolderManifests").withIndex("by_user_folder_state", q => q.eq("userId", userId).eq("folderId", folder._id).eq("state.kind", phase)).first()) return { kind: "conflict", reason: "folder_busy" };
  }
  let active = 0;
  for (const phase of ["scanning", "prepared"] as const) active += (await ctx.db.query("savedFolderManifests").withIndex("by_user_state", q => q.eq("userId", userId).eq("state.kind", phase)).take(ACTIVE_PREPARATIONS)).length;
  if (active >= ACTIVE_PREPARATIONS) return { kind: "conflict", reason: "owner_busy" };
  const now = Date.now(), generation = crypto.randomUUID();
  const id = await ctx.db.insert("savedFolderManifests", { userId, folderId: folder._id, operationId: operation.id, requestedAt: operation.at,
    generation, createdAt: now, updatedAt: now, expiresAt: now + FOLDER_MANIFEST_LEASE_MS,
    captured: { epoch: guard.epoch, updatedAt: folder.updatedAt, name: folder.name, createdAt: folder.createdAt },
    state: { kind: "scanning", cursor: null, count: 0, step: 0 } });
  await ctx.scheduler.runAfter(0, internal.librarySync.advanceFolderManifest, { id, generation, step: 0 });
  return { kind: "manifest", id, generation };
}

async function abandon(ctx: MutationCtx, header: Header, reason: Reason): Promise<FolderManifestStep> {
  await failHeldFolderFrame(ctx, header, reason);
  await ctx.db.patch(header._id, { state: { kind: "abandoned", reason, count: header.state.count }, updatedAt: Date.now() });
  await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation });
  return { kind: "abandoned", reason };
}

/** One transaction/page. Expected step is a compare-and-swap fence for duplicate workers. */
export async function advanceFolderManifest(ctx: MutationCtx, request: { id: Header["_id"]; generation: string; step: number }): Promise<FolderManifestStep> {
  const header = await ctx.db.get(request.id);
  if (!header || header.generation !== request.generation || header.state.kind !== "scanning" || header.state.step !== request.step) return { kind: "ignored" };
  if (!await ctx.db.get(header.userId)) {
    await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation });
    return { kind: "ignored" };
  }
  const now = Date.now();
  if (header.expiresAt <= now) return abandon(ctx, header, "expired");
  const folder = await ctx.db.get(header.folderId);
  if (folder?.userId !== header.userId) return abandon(ctx, header, "missing_folder");
  if ((folder.membershipEpoch ?? 0) !== header.captured.epoch || folder.updatedAt !== header.captured.updatedAt) return abandon(ctx, header, "changed");
  const page = await ctx.db.query("savedItems").withIndex("by_user_folder_updated", q => q.eq("userId", header.userId).eq("folderId", folder._id))
    .paginate({ cursor: header.state.cursor, numItems: FOLDER_MANIFEST_PAGE, maximumRowsRead: FOLDER_MANIFEST_PAGE, maximumBytesRead: FOLDER_MANIFEST_READ_BYTES });
  if (!page.isDone && page.continueCursor === header.state.cursor) throw new Error("FOLDER_MANIFEST_NO_PROGRESS");
  let count = header.state.count;
  for (const member of page.page) await ctx.db.insert("savedFolderManifestMembers", { userId: header.userId, manifestId: header._id,
    ordinal: count++, itemId: member._id, hadithId: member.hadithId, ...(member.folderUpdatedAt === undefined ? {} : { membershipAt: member.folderUpdatedAt }) });
  const state: Header["state"] = page.isDone ? { kind: "prepared", count } : { kind: "scanning", count, cursor: page.continueCursor, step: request.step + 1 };
  await ctx.db.patch(header._id, { state, updatedAt: now, expiresAt: now + FOLDER_MANIFEST_LEASE_MS });
  if (state.kind === "scanning") await ctx.scheduler.runAfter(0, internal.librarySync.advanceFolderManifest, { id: header._id, generation: header.generation, step: state.step });
  return { kind: state.kind, count, read: page.page.length };
}

/** Facts have no authority without a still-existing, prepared owner header. */
export async function readPreparedFolderManifest(ctx: QueryCtx | MutationCtx, userId: Id<"users">,
  request: { id: Header["_id"]; generation: string; cursor: string | null }) {
  const header = await ctx.db.get(request.id);
  if (!await ctx.db.get(userId) || header?.userId !== userId || header.generation !== request.generation || header.state.kind !== "prepared" || header.expiresAt <= Date.now()) throw new Error("FOLDER_MANIFEST_UNAVAILABLE");
  const folder = await ctx.db.get(header.folderId);
  if (folder?.userId !== userId || (folder.membershipEpoch ?? 0) !== header.captured.epoch || folder.updatedAt !== header.captured.updatedAt) throw new Error("FOLDER_MANIFEST_UNAVAILABLE");
  return ctx.db.query("savedFolderManifestMembers").withIndex("by_user_manifest_ordinal", q => q.eq("userId", userId).eq("manifestId", header._id))
    .paginate({ cursor: request.cursor, numItems: FOLDER_MANIFEST_PAGE, maximumRowsRead: FOLDER_MANIFEST_PAGE, maximumBytesRead: 64 * 1024 });
}

/** Safe after owner erasure too. A live preparation's facts cannot be removed. */
export async function purgeFolderManifestMembers(ctx: MutationCtx, request: { id: Header["_id"]; generation: string }): Promise<{ deleted: number }> {
  const header = await ctx.db.get(request.id);
  if (header && header.generation !== request.generation) return { deleted: 0 };
  const ownerExists = header ? await ctx.db.get(header.userId) !== null : false;
  const expired = header ? header.expiresAt <= Date.now() : true;
  if (header && ownerExists && (header.state.kind === "deleted" || header.state.kind === "restoring" || header.state.kind === "restored" || header.state.kind === "expiring")) {
    await expireFolderTransition(ctx, header);
    return { deleted: 0 };
  }
  if (header && ownerExists && !expired && header.state.kind !== "abandoned" && header.state.kind !== "purging") return { deleted: 0 };
  const eraseHeader = expired || !ownerExists || header?.state.kind === "purging";
  if (header && eraseHeader) await failHeldFolderFrame(ctx, header, header.state.kind === "abandoned" || header.state.kind === "purging" ? header.state.reason : "expired");
  if (header && eraseHeader && header.state.kind !== "purging") await ctx.db.patch(header._id, {
    state: { kind: "purging", reason: header.state.kind === "abandoned" ? header.state.reason : "expired", count: header.state.count },
    expiresAt: Date.now() + FOLDER_MANIFEST_LEASE_MS,
  });
  const rows = await ctx.db.query("savedFolderManifestMembers").withIndex("by_manifest", q => q.eq("manifestId", request.id)).take(FOLDER_MANIFEST_PAGE);
  for (const row of rows) await ctx.db.delete(row._id);
  if (rows.length === FOLDER_MANIFEST_PAGE) await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, request);
  else if (header && eraseHeader) {
    const deletion = await librarySyncMark(ctx, header.userId, `folder:${header.folderId}`);
    if (deletion?.detail.kind === "folder_manifest" && deletion.detail.manifestId === header._id) await ctx.db.delete(deletion._id);
    await ctx.db.delete(header._id);
  }
  return { deleted: rows.length };
}
