import {
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import { v } from "convex/values";
import { optionalIdentity, requireIdentity } from "./lib/identity";

/** Internal: record a translation report (called from the AI action). */
export const insertReport = internalMutation({
  args: {
    translationId: v.id("translations"),
    reporterUserId: v.optional(v.id("users")),
    reason: v.string(),
  },
  handler: async (ctx, args) =>
    await ctx.db.insert("translationReports", {
      ...args,
      status: "open",
      createdAt: Date.now(),
    }),
});

/** Verified operator capability for the optional exception tool. */
export const canModerate = query({
  args: {},
  handler: async (ctx) => {
    const identity = await optionalIdentity(ctx);
    if (!identity) return false;
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
      .unique();
    return user?.isAdmin === true;
  },
});

/**
 * Retired manual publication route. Automated evidence review owns publication.
 */
export const approveSubmission = mutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (): Promise<never> => {
    throw new Error("Publication requires the evidence review pipeline.");
  },
});

export const rejectSubmission = mutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (): Promise<never> => {
    throw new Error("Rejection requires the evidence exception pipeline.");
  },
});

/** Dashboard/CLI bootstrap only; clients cannot grant admin access. */
export const setAdmin = internalMutation({
  args: { clerkId: v.string(), isAdmin: v.boolean() },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();
    if (!user) throw new Error("User not found");
    await ctx.db.patch(user._id, { isAdmin: args.isAdmin });
  },
});
