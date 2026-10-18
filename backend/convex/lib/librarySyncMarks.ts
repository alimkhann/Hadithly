import type { MutationCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";
import type { SyncOperation } from "./librarySyncPolicy";

export async function librarySyncMark(ctx: MutationCtx, userId: Id<"users">, key: string) {
  return ctx.db.query("librarySyncMarks").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", key)).unique();
}
export async function stampLibrarySyncMark(ctx: MutationCtx, userId: Id<"users">, key: string, operation: Pick<SyncOperation, "id" | "at"> & { command: { kind: string } }, at = operation.at) {
  const previous = await librarySyncMark(ctx, userId, key);
  if (previous && previous.at > at) return;
  const value = { userId, key, operationId: operation.id, commandKind: operation.command.kind, at };
  if (previous) await ctx.db.replace(previous._id, value);
  else await ctx.db.insert("librarySyncMarks", value);
}
export async function recordLegacyLibraryWrite(ctx: MutationCtx, userId: Id<"users">, key: string, at = Date.now()) {
  await stampLibrarySyncMark(ctx, userId, key, { id: `legacy:${crypto.randomUUID()}`, at, command: { kind: "legacy" } });
}
