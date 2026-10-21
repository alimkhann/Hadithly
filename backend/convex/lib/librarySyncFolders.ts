import type { MutationCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";
import type { SyncFolderReference } from "./librarySyncPolicy";

export async function resolveLibraryFolder(ctx: MutationCtx, userId: Id<"users">, reference: SyncFolderReference) {
  if (reference.kind === "none") return null;
  const id = reference.kind === "server" ? ctx.db.normalizeId("savedFolders", reference.id)
    : (await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", reference.key)).unique())?.folderId;
  const row = id ? await ctx.db.get(id) : null;
  return row?.userId === userId ? row : null;
}

export async function bindLibraryFolderKey(ctx: MutationCtx, userId: Id<"users">, key: string, folderId: Id<"savedFolders">) {
  if ((await ctx.db.get(folderId))?.userId !== userId) throw new Error("SYNC_FOLDER_OWNER_MISMATCH");
  const existing = await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", key)).unique();
  if (!existing) await ctx.db.insert("librarySyncFolderKeys", { userId, key, folderId });
  else if (existing.folderId !== folderId) throw new Error("SYNC_FOLDER_KEY_REUSED");
}
