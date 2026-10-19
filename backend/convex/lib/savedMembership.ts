import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { Doc, Id } from "../_generated/dataModel";
import { librarySyncMark, stampLibrarySyncMark } from "./librarySyncMarks";

type MembershipValue = { folderId: Id<"savedFolders"> | undefined; at: number | null };
type MembershipDecision = "write" | "unchanged" | "newer_cloud" | "tie_cloud";

export async function assertSavedFolderStable(ctx: MutationCtx | QueryCtx, folder: Doc<"savedFolders">) {
  if (!folder.transition) return;
  const header = await ctx.db.get(folder.transition);
  if (header?.userId === folder.userId && (header.state.kind === "restoring" || header.state.kind === "restored" && header.state.normalization.kind === "pending" || header.state.kind === "expiring")) throw new Error("SAVED_FOLDER_BUSY");
}

/** Resolves at most one staging slot or owner tombstone; no redirect history. */
export async function effectiveSavedMembership(ctx: MutationCtx | QueryCtx, item: Doc<"savedItems">): Promise<MembershipValue> {
  if (item.folderStage) {
    const stage = item.folderStage, header = await ctx.db.get(stage.manifestId);
    if (header?.userId === item.userId && header.generation === stage.generation && header.state.kind === "restored" && header.state.operationId === stage.restoreId) {
      const destination = await ctx.db.get(header.state.destinationId);
      return { folderId: destination?.userId === item.userId ? destination._id : undefined, at: Math.max(item.folderUpdatedAt ?? 0, header.state.at) };
    }
  }
  if (!item.folderId) return { folderId: undefined, at: item.folderUpdatedAt ?? null };
  const folder = await ctx.db.get(item.folderId);
  if (folder?.userId === item.userId) return { folderId: folder._id, at: item.folderUpdatedAt ?? null };
  const deletion = await librarySyncMark(ctx, item.userId, `folder:${item.folderId}`);
  return { folderId: undefined, at: deletion?.detail.kind === "folder_manifest" ? Math.max(item.folderUpdatedAt ?? 0, deletion.at) : item.folderUpdatedAt ?? null };
}

export async function discardSavedFolderStage(ctx: MutationCtx, item: Doc<"savedItems">, disposition: "missing" | "superseded") {
  const stage = item.folderStage;
  if (!stage) return;
  const header = await ctx.db.get(stage.manifestId);
  if (header?.userId === item.userId && header.generation === stage.generation && header.state.kind === "restoring" && header.state.operationId === stage.restoreId) {
    const member = await ctx.db.get(stage.memberId);
    if (!member || member.userId !== item.userId || member.manifestId !== header._id || member.itemId !== item._id || member.disposition !== "restored" || header.state.restored < 1) throw new Error("SAVED_FOLDER_STAGE_INVARIANT");
    await ctx.db.patch(member._id, { disposition });
    await ctx.db.patch(header._id, { state: { ...header.state, restored: header.state.restored - 1, [disposition]: header.state[disposition] + 1 } });
  }
  await ctx.db.patch(item._id, { folderStage: undefined });
}

/** Invalidates a paged membership scan on either side of an accepted change. */
export async function touchSavedFolderMemberships(ctx: MutationCtx, userId: Id<"users">, folderIds: (Id<"savedFolders"> | undefined)[]) {
  for (const id of new Set(folderIds)) {
    if (id === undefined) continue;
    const folder = await ctx.db.get(id);
    if (folder?.userId === userId) await ctx.db.patch(id, { membershipEpoch: (folder.membershipEpoch ?? 0) + 1 });
  }
}

/** Reads a fixed-size scan guard without collecting the folder's members. */
export async function savedFolderScanGuard(ctx: QueryCtx | MutationCtx, folder: Doc<"savedFolders">) {
  const latest = await ctx.db.query("savedItems").withIndex("by_user_folder_updated", q =>
    q.eq("userId", folder.userId).eq("folderId", folder._id)).order("desc").first();
  return { epoch: folder.membershipEpoch ?? 0, latestAt: latest ? latest.folderUpdatedAt ?? 0 : null };
}

export async function removeEmptySavedMembership(ctx: MutationCtx, item: Doc<"savedItems">) {
  if (item.bookmarkCreatedAt !== undefined || item.favoriteCreatedAt !== undefined || item.noteContent !== undefined) return;
  const effective = await effectiveSavedMembership(ctx, item);
  await discardSavedFolderStage(ctx, item, "missing");
  await touchSavedFolderMemberships(ctx, item.userId, [item.folderId, effective.folderId]);
  await ctx.db.delete(item._id);
}

/** Same-value observations at an older/equal clock cannot replace causal Undo authority. */
export function decideMembershipWrite(current: MembershipValue, incoming: { folderId: Id<"savedFolders"> | undefined; at: number }): MembershipDecision {
  if (current.at !== null && incoming.at <= current.at) {
    if (current.folderId === incoming.folderId) return "unchanged";
    return incoming.at === current.at ? "tie_cloud" : "newer_cloud";
  }
  return "write";
}

/** Owns ordinary placement writes and their clock/operation mark in one transaction. */
export async function writeSavedMembership(
  ctx: MutationCtx,
  item: Doc<"savedItems">,
  change: { kind: "dated"; folder: Doc<"savedFolders"> | null; at: number; operation: { id: string; kind: "membership_put" | "legacy" } }
    | { kind: "claim_if_unset"; folder: Doc<"savedFolders"> },
): Promise<{ kind: MembershipDecision | "missing_folder" | "unversioned_cloud" }> {
  if (change.folder && change.folder.userId !== item.userId) return { kind: "missing_folder" };
  const key = `membership:${item.hadithId}`;
  const previous = await librarySyncMark(ctx, item.userId, key);
  const current = await effectiveSavedMembership(ctx, item);
  const clock = Math.max(current.at ?? -Infinity, previous?.at ?? -Infinity);
  const folderId = change.folder?._id;
  if (change.kind === "claim_if_unset") {
    if (current.folderId === folderId) return { kind: "unchanged" };
    if (current.folderId !== undefined || Number.isFinite(clock) || item.folderStage !== undefined) return { kind: "unversioned_cloud" };
    await ctx.db.patch(item._id, { folderId });
    await touchSavedFolderMemberships(ctx, item.userId, [folderId]);
    return { kind: "write" };
  }
  const decision = decideMembershipWrite({ folderId: current.folderId, at: Number.isFinite(clock) ? clock : null }, { folderId, at: change.at });
  if (decision !== "write") return { kind: decision };
  await discardSavedFolderStage(ctx, item, "superseded");
  await ctx.db.patch(item._id, { folderId, folderUpdatedAt: change.at, updatedAt: Math.max(item.updatedAt, change.at) });
  await touchSavedFolderMemberships(ctx, item.userId, [item.folderId, current.folderId, folderId]);
  await stampLibrarySyncMark(ctx, item.userId, key, { id: change.operation.id, at: change.at, command: { kind: change.operation.kind } });
  return { kind: "write" };
}
