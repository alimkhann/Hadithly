import type { MutationCtx, QueryCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";

type Domain = "saved" | "position";
export async function libraryVersion(ctx: QueryCtx | MutationCtx, userId: Id<"users">, kind: Domain) {
  const row = await ctx.db.query("librarySyncVersions").withIndex("by_user_kind", q => q.eq("userId", userId).eq("kind", kind)).unique();
  return row?.version ?? 0;
}
export async function advanceLibraryVersion(ctx: MutationCtx, userId: Id<"users">, kind: Domain) {
  const row = await ctx.db.query("librarySyncVersions").withIndex("by_user_kind", q => q.eq("userId", userId).eq("kind", kind)).unique();
  const version = (row?.version ?? 0) + 1;
  if (row) await ctx.db.patch(row._id, { version });
  else await ctx.db.insert("librarySyncVersions", { userId, kind, version });
  return version;
}
