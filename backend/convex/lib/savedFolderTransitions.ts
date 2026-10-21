import { bindLibraryFolderKey } from "./librarySyncFolders";
import { internal } from "../_generated/api";
import type { Doc, Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { librarySyncMark, stampLibrarySyncMark } from "./librarySyncMarks";
import { advanceLibraryVersion } from "./librarySyncVersions";
import { failHeldFolderFrame, publishHeldFolderOutcome } from "./librarySyncFrames";
import { assertSavedFolderStable, touchSavedFolderMemberships } from "./savedMembership";
import { FOLDER_EFFECT_PAGE, FOLDER_HANDLE_RETENTION_MS, FOLDER_WORK_LEASE_MS, normalizedFolderName } from "./savedFolderPolicy";
import type { SyncOutcome } from "./librarySyncPolicy";

type Header = Doc<"savedFolderManifests">;
type Restored = Extract<Header["state"], { kind: "restored" }>;
type Work = { id: Header["_id"]; generation: string };
export type FolderEffectStep = { kind: "ignored" | "staged" | "restored" | "materialized" | "expired" | "failed"; read: number };
export type RestoreStart = { kind: "restoring"; id: Header["_id"]; generation: string; operationId: string }
  | { kind: "outcome"; outcome: SyncOutcome };
const unavailable = (): SyncOutcome => ({ kind: "unresolved", reason: "folder_restore_unavailable" });

function deletionOutcome(header: Header): SyncOutcome {
  return { kind: "folder_deleted_manifest", manifestId: header._id, generation: header.generation, count: header.state.count, deletedAt: header.requestedAt };
}
function restorationOutcome(header: Header, state: Restored): SyncOutcome {
  return { kind: "folder_restored_manifest", manifestId: header._id, generation: header.generation, folderId: state.destinationId,
    restored: state.restored, superseded: state.superseded, missing: state.missing };
}

/** The visibility change and its held-frame receipt share this transaction. */
export async function commitPreparedFolderDeletion(ctx: MutationCtx, userId: Id<"users">, work: Work): Promise<SyncOutcome> {
  const header = await ctx.db.get(work.id);
  if (!await ctx.db.get(userId) || header?.userId !== userId || header.generation !== work.generation) return unavailable();
  if (header.state.kind === "deleted" || header.state.kind === "restoring" || header.state.kind === "restored" || header.state.kind === "expiring") return deletionOutcome(header);
  if (header.state.kind !== "prepared") return unavailable();
  const folder = await ctx.db.get(header.folderId);
  const folderVersion = await librarySyncMark(ctx, userId, `folder:${header.folderId}`);
  const reason = header.expiresAt <= Date.now() ? "expired" : folder?.userId !== userId ? "missing_folder"
    : (folder.membershipEpoch ?? 0) !== header.captured.epoch || folder.updatedAt !== header.captured.updatedAt || (folderVersion?.at ?? 0) > header.requestedAt ? "changed" : null;
  if (reason) {
    await failHeldFolderFrame(ctx, header, reason);
    await ctx.db.patch(header._id, { state: { kind: "abandoned", count: header.state.count, reason } });
    await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, work);
    return reason === "changed" ? { kind: "superseded", reason: "changed_since_delete" }
      : { kind: "unresolved", reason: reason === "expired" ? "preparation_expired" : "missing_folder" };
  }
  if (!folder) throw new Error("SAVED_FOLDER_COMMIT_INVARIANT");
  await assertSavedFolderStable(ctx, folder);
  await ctx.db.delete(folder._id);
  await stampLibrarySyncMark(ctx, userId, `folder:${folder._id}`, { id: header.operationId, at: header.requestedAt, command: { kind: "folder_delete" } }, header.requestedAt, { kind: "folder_manifest", manifestId: header._id });
  await ctx.db.patch(header._id, { state: { kind: "deleted", count: header.state.count }, updatedAt: Date.now(), expiresAt: Date.now() + FOLDER_HANDLE_RETENTION_MS });
  await advanceLibraryVersion(ctx, userId, "saved");
  const outcome = deletionOutcome(header);
  if (header.heldBy && !await publishHeldFolderOutcome(ctx, header, outcome, "delete")) throw new Error("SYNC_HELD_FRAME_UNAVAILABLE");
  return outcome;
}

/** CAS reserves one operation. No destination is created merely by starting Undo. */
export async function beginFolderRestoration(ctx: MutationCtx, userId: Id<"users">,
  operation: { id: string; at: number; deletionId: string }): Promise<RestoreStart> {
  if (!await ctx.db.get(userId)) return { kind: "outcome", outcome: unavailable() };
  const header = await ctx.db.query("savedFolderManifests").withIndex("by_user_operation", q => q.eq("userId", userId).eq("operationId", operation.deletionId)).unique();
  if (!header) return { kind: "outcome", outcome: unavailable() };
  if (header.state.kind === "restored") return { kind: "outcome", outcome: header.state.operationId === operation.id && header.state.at === operation.at ? restorationOutcome(header, header.state) : { kind: "superseded", reason: "changed_since_delete" } };
  if (header.state.kind === "restoring") {
    if (header.state.operationId !== operation.id) return { kind: "outcome", outcome: { kind: "superseded", reason: "changed_since_delete" } };
    if (header.state.at !== operation.at) throw new Error("FOLDER_RESTORE_OPERATION_CONFLICT");
    if (header.expiresAt <= Date.now()) return { kind: "outcome", outcome: unavailable() };
    return { kind: "restoring", id: header._id, generation: header.generation, operationId: operation.id };
  }
  if (header.state.kind !== "deleted" || header.expiresAt <= Date.now()) return { kind: "outcome", outcome: unavailable() };
  if (operation.at < header.requestedAt) return { kind: "outcome", outcome: { kind: "superseded", reason: "newer_cloud" } };
  const name = normalizedFolderName(header.captured.name);
  const existing = await ctx.db.query("savedFolders").withIndex("by_user_normalized_name", q => q.eq("userId", userId).eq("normalizedName", name.normalizedName)).unique();
  const alias = await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", `restore:${header.operationId}`)).unique();
  if (alias && alias.folderId !== existing?._id) return { kind: "outcome", outcome: { kind: "superseded", reason: "changed_since_delete" } };
  if (existing) { await assertSavedFolderStable(ctx, existing); await ctx.db.patch(existing._id, { transition: header._id }); }
  await ctx.db.patch(header._id, { state: { kind: "restoring", count: header.state.count, operationId: operation.id, at: operation.at, cursor: null, step: 0,
    destination: existing ? { kind: "existing", id: existing._id } : { kind: "new" }, restored: 0, superseded: 0, missing: 0 },
    updatedAt: Date.now(), expiresAt: Math.max(header.expiresAt, Date.now() + FOLDER_WORK_LEASE_MS) });
  await ctx.scheduler.runAfter(0, internal.librarySync.advanceFolderRestoration, { id: header._id, generation: header.generation, operationId: operation.id, step: 0 });
  return { kind: "restoring", id: header._id, generation: header.generation, operationId: operation.id };
}

export async function advanceFolderRestoration(ctx: MutationCtx, work: Work & { operationId: string; step: number }): Promise<FolderEffectStep> {
  const header = await ctx.db.get(work.id);
  if (!header || header.generation !== work.generation || header.state.kind !== "restoring" || header.state.operationId !== work.operationId || header.state.step !== work.step) return { kind: "ignored", read: 0 };
  if (!await ctx.db.get(header.userId)) { await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation }); return { kind: "ignored", read: 0 }; }
  if (header.expiresAt <= Date.now()) { await expireFolderTransition(ctx, header); return { kind: "expired", read: 0 }; }
  const state = header.state;
  const page = await ctx.db.query("savedFolderManifestMembers").withIndex("by_user_manifest_ordinal", q => q.eq("userId", header.userId).eq("manifestId", header._id))
    .paginate({ cursor: state.cursor, numItems: FOLDER_EFFECT_PAGE, maximumRowsRead: FOLDER_EFFECT_PAGE, maximumBytesRead: 64 * 1024 });
  const counts = { restored: state.restored, superseded: state.superseded, missing: state.missing };
  for (const member of page.page) {
    const item = await ctx.db.get(member.itemId);
    let disposition: "restored" | "superseded" | "missing";
    if (!item || item.userId !== header.userId || item.bookmarkCreatedAt === undefined && item.favoriteCreatedAt === undefined && item.noteContent === undefined || !await ctx.db.get(member.hadithId)) disposition = "missing";
    else if (item.folderId !== header.folderId || item.folderUpdatedAt !== member.membershipAt || item.folderStage !== undefined) disposition = "superseded";
    else {
      disposition = "restored";
      await ctx.db.patch(item._id, { folderStage: { manifestId: header._id, memberId: member._id, generation: header.generation, restoreId: state.operationId } });
    }
    counts[disposition]++;
    await ctx.db.patch(member._id, { disposition });
  }
  if (!page.isDone) {
    await ctx.db.patch(header._id, { state: { ...state, ...counts, cursor: page.continueCursor, step: work.step + 1 }, updatedAt: Date.now(), expiresAt: Math.max(header.expiresAt, Date.now() + FOLDER_WORK_LEASE_MS) });
    await ctx.scheduler.runAfter(0, internal.librarySync.advanceFolderRestoration, { ...work, step: work.step + 1 });
    return { kind: "staged", read: page.page.length };
  }
  const name = normalizedFolderName(header.captured.name);
  const destination = state.destination.kind === "existing" ? await ctx.db.get(state.destination.id)
    : await ctx.db.query("savedFolders").withIndex("by_user_normalized_name", q => q.eq("userId", header.userId).eq("normalizedName", name.normalizedName)).unique();
  if (state.destination.kind === "existing" && (destination?.userId !== header.userId || destination.transition !== header._id || destination.normalizedName !== name.normalizedName)) throw new Error("SAVED_FOLDER_DESTINATION_INVARIANT");
  if (destination && destination.transition !== header._id) await assertSavedFolderStable(ctx, destination);
  const alias = await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", header.userId).eq("key", `restore:${header.operationId}`)).unique();
  if (alias && alias.folderId !== destination?._id) {
    await startFolderExpiry(ctx, header, { kind: "superseded", reason: "changed_since_delete" });
    return { kind: "failed", read: page.page.length };
  }
  const destinationId = destination?._id ?? await ctx.db.insert("savedFolders", { userId: header.userId, ...name, createdAt: Date.now(), updatedAt: state.at, transition: header._id });
  if (destination) await ctx.db.patch(destinationId, { transition: header._id });
  await bindLibraryFolderKey(ctx, header.userId, `restore:${header.operationId}`, destinationId);
  const restored: Restored = { kind: "restored", count: state.count, operationId: state.operationId, at: state.at, destinationId, ...counts, normalization: { kind: "pending", cursor: null, step: 0 } };
  await ctx.db.patch(header._id, { state: restored, updatedAt: Date.now(), expiresAt: Date.now() + FOLDER_HANDLE_RETENTION_MS });
  await advanceLibraryVersion(ctx, header.userId, "saved");
  if (header.restoreHeldBy && !await publishHeldFolderOutcome(ctx, header, restorationOutcome(header, restored), "restore")) throw new Error("SYNC_HELD_FRAME_UNAVAILABLE");
  await ctx.scheduler.runAfter(0, internal.librarySync.materializeFolderEffect, { id: header._id, generation: header.generation, operationId: state.operationId, step: 0 });
  return { kind: "restored", read: page.page.length };
}

async function releaseDestination(ctx: MutationCtx, header: Header, destinationId: Id<"savedFolders"> | null) {
  if (!destinationId) return;
  const folder = await ctx.db.get(destinationId);
  if (folder?.userId === header.userId && folder.transition === header._id) await ctx.db.patch(folder._id, { transition: undefined });
}

async function startFolderExpiry(ctx: MutationCtx, header: Header, outcome: SyncOutcome = unavailable()): Promise<void> {
  const state = header.state;
  if (state.kind !== "deleted" && state.kind !== "restoring") throw new Error("SAVED_FOLDER_EXPIRY_INVARIANT");
  const releaseFolderId = state.kind === "restoring" && state.destination.kind === "existing" ? state.destination.id : null;
  if (state.kind === "restoring") {
    const published = await publishHeldFolderOutcome(ctx, header, outcome, "restore");
    if (header.restoreHeldBy && !published && await ctx.db.get(header.userId)) throw new Error("SYNC_HELD_FRAME_UNAVAILABLE");
  }
  await ctx.db.patch(header._id, { state: { kind: "expiring", count: state.count, cursor: null, step: 0, releaseFolderId }, expiresAt: Date.now() + FOLDER_WORK_LEASE_MS, updatedAt: Date.now() });
  await ctx.scheduler.runAfter(0, internal.librarySync.materializeFolderEffect, { id: header._id, generation: header.generation, operationId: header.operationId, step: 0 });
}

/** Expiry cannot purge an in-progress lease or change already-visible staged membership. */
export async function expireFolderTransition(ctx: MutationCtx, header: Header): Promise<void> {
  if (header.expiresAt > Date.now()) return;
  if (header.state.kind === "restored") {
    if (header.state.normalization.kind === "pending") {
      await ctx.db.patch(header._id, { expiresAt: Date.now() + FOLDER_WORK_LEASE_MS });
      await ctx.scheduler.runAfter(0, internal.librarySync.materializeFolderEffect, { id: header._id, generation: header.generation, operationId: header.state.operationId, step: header.state.normalization.step });
    } else {
      await ctx.db.patch(header._id, { state: { kind: "purging", reason: "expired", count: header.state.count }, expiresAt: Date.now() + FOLDER_WORK_LEASE_MS });
      await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation });
    }
    return;
  }
  if (header.state.kind === "deleted" || header.state.kind === "restoring") {
    await startFolderExpiry(ctx, header);
  } else if (header.state.kind === "expiring") {
    await ctx.db.patch(header._id, { expiresAt: Date.now() + FOLDER_WORK_LEASE_MS });
    await ctx.scheduler.runAfter(0, internal.librarySync.materializeFolderEffect, { id: header._id, generation: header.generation, operationId: header.operationId, step: header.state.step });
  }
}

export async function materializeFolderEffect(ctx: MutationCtx, work: Work & { operationId: string; step: number }): Promise<FolderEffectStep> {
  const header = await ctx.db.get(work.id);
  if (!header || header.generation !== work.generation) return { kind: "ignored", read: 0 };
  const state = header.state;
  const progress = state.kind === "restored" && state.normalization.kind === "pending" && state.operationId === work.operationId ? state.normalization
    : state.kind === "expiring" && header.operationId === work.operationId ? state : null;
  if (!progress || progress.step !== work.step) return { kind: "ignored", read: 0 };
  if (!await ctx.db.get(header.userId)) { await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation }); return { kind: "ignored", read: 0 }; }
  const page = await ctx.db.query("savedFolderManifestMembers").withIndex("by_user_manifest_ordinal", q => q.eq("userId", header.userId).eq("manifestId", header._id))
    .paginate({ cursor: progress.cursor, numItems: FOLDER_EFFECT_PAGE, maximumRowsRead: FOLDER_EFFECT_PAGE, maximumBytesRead: 64 * 1024 });
  for (const member of page.page) {
    const item = await ctx.db.get(member.itemId);
    if (!item || item.userId !== header.userId) continue;
    const stage = item.folderStage;
    if (stage && (stage.manifestId !== header._id || stage.generation !== header.generation || stage.memberId !== member._id)) throw new Error("SAVED_FOLDER_STAGE_INVARIANT");
    if (state.kind === "restored" && stage) {
      if (stage.restoreId !== state.operationId || item.folderId !== header.folderId || item.folderUpdatedAt !== member.membershipAt) throw new Error("SAVED_FOLDER_STAGE_INVARIANT");
      await ctx.db.patch(item._id, { folderId: state.destinationId, folderUpdatedAt: state.at, folderStage: undefined, updatedAt: Math.max(item.updatedAt, state.at) });
      await stampLibrarySyncMark(ctx, header.userId, `membership:${item.hadithId}`, { id: state.operationId, at: state.at, command: { kind: "folder_restore" } });
      await touchSavedFolderMemberships(ctx, header.userId, [state.destinationId]);
    } else if (item.folderId === header.folderId && (item.folderUpdatedAt ?? 0) <= header.requestedAt) {
      await ctx.db.patch(item._id, { folderId: undefined, folderUpdatedAt: header.requestedAt, folderStage: undefined, updatedAt: Math.max(item.updatedAt, header.requestedAt) });
      await stampLibrarySyncMark(ctx, header.userId, `membership:${item.hadithId}`, { id: header.operationId, at: header.requestedAt, command: { kind: "folder_delete" } });
    }
  }
  if (state.kind === "restored") {
    if (page.isDone) await releaseDestination(ctx, header, state.destinationId);
    await ctx.db.patch(header._id, { state: { ...state, normalization: page.isDone ? { kind: "done" } : { kind: "pending", cursor: page.continueCursor, step: work.step + 1 } }, updatedAt: Date.now() });
  } else if (state.kind === "expiring") {
    if (page.isDone) {
      await releaseDestination(ctx, header, state.releaseFolderId);
      await ctx.db.patch(header._id, { state: { kind: "purging", reason: "expired", count: state.count }, updatedAt: Date.now() });
      await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation });
    } else await ctx.db.patch(header._id, { state: { ...state, cursor: page.continueCursor, step: work.step + 1 }, updatedAt: Date.now(), expiresAt: Date.now() + FOLDER_WORK_LEASE_MS });
  }
  if (!page.isDone) await ctx.scheduler.runAfter(0, internal.librarySync.materializeFolderEffect, { ...work, step: work.step + 1 });
  return { kind: state.kind === "expiring" ? "expired" : "materialized", read: page.page.length };
}
