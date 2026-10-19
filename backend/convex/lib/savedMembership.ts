import type { MutationCtx } from "../_generated/server";
import type { Doc, Id } from "../_generated/dataModel";
import { librarySyncMark, stampLibrarySyncMark } from "./librarySyncMarks";

type MembershipValue = { folderId: Id<"savedFolders"> | undefined; at: number | null };
type MembershipDecision = "write" | "unchanged" | "newer_cloud" | "tie_cloud";

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
    return { kind: "write" };
  }
  const decision = decideMembershipWrite({ folderId: item.folderId, at: Number.isFinite(clock) ? clock : null }, { folderId, at: change.at });
  if (decision !== "write") return { kind: decision };
  await ctx.db.patch(item._id, { folderId, folderUpdatedAt: change.at, updatedAt: Math.max(item.updatedAt, change.at) });
  await stampLibrarySyncMark(ctx, item.userId, key, { id: change.operation.id, at: change.at, command: { kind: change.operation.kind } });
  return { kind: "write" };
}
