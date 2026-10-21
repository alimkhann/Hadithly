import type { Doc } from "../_generated/dataModel";
import type { MutationCtx, QueryCtx } from "../_generated/server";
import { requireIdentity } from "./identity";
import { textDigest } from "./evidenceReviewPolicy";

type Context = MutationCtx | QueryCtx;
export async function requireLibraryUser(ctx: Context) {
  const identity = await requireIdentity(ctx);
  const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
  if (!user) throw new Error("SYNC_ACCOUNT_MISSING");
  return user;
}
export type LibrarySyncProtocol = "inline_v1" | "manifest_v2";
export async function requireLibraryBinding(ctx: Context, capability: string): Promise<{ user: Doc<"users">; protocol: LibrarySyncProtocol }> {
  const user = await requireLibraryUser(ctx);
  const digest = await textDigest(capability);
  const binding = await ctx.db.query("librarySyncBindings").withIndex("by_digest", q => q.eq("digest", digest)).unique();
  if (!binding || binding.userId !== user._id) throw new Error("SYNC_OWNER_MISMATCH");
  if (binding.expiresAt <= Date.now()) throw new Error("SYNC_BINDING_EXPIRED");
  return { user, protocol: binding.protocol ?? "inline_v1" };
}
