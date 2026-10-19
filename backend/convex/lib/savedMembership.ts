import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { Doc, Id } from "../_generated/dataModel";
import { librarySyncMark, stampLibrarySyncMark } from "./librarySyncMarks";

type MembershipValue = { folderId: Id<"savedFolders"> | undefined; at: number | null };
type MembershipDecision = "write" | "unchanged" | "newer_cloud" | "tie_cloud";

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
  await touchSavedFolderMemberships(ctx, item.userId, [item.folderId]);
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
  const clock = Math.max(item.folderUpdatedAt ?? -Infinity, previous?.at ?? -Infinity);
  const folderId = change.folder?._id;
  if (change.kind === "claim_if_unset") {
    if (item.folderId === folderId) return { kind: "unchanged" };
    if (item.folderId !== undefined || Number.isFinite(clock)) return { kind: "unversioned_cloud" };
    await ctx.db.patch(item._id, { folderId });
    await touchSavedFolderMemberships(ctx, item.userId, [folderId]);
    return { kind: "write" };
  }
  const decision = decideMembershipWrite({ folderId: item.folderId, at: Number.isFinite(clock) ? clock : null }, { folderId, at: change.at });
  if (decision !== "write") return { kind: decision };
  await ctx.db.patch(item._id, { folderId, folderUpdatedAt: change.at, updatedAt: Math.max(item.updatedAt, change.at) });
  await touchSavedFolderMemberships(ctx, item.userId, [item.folderId, folderId]);
  await stampLibrarySyncMark(ctx, item.userId, key, { id: change.operation.id, at: change.at, command: { kind: change.operation.kind } });
  return { kind: "write" };
}
