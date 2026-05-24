import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const upsertCurrentUser = mutation({
  args: {
    clerkId: v.string(),
    email: v.optional(v.string()),
    displayName: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    preferredLanguage: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        email: args.email,
        displayName: args.displayName,
        avatarUrl: args.avatarUrl,
        preferredLanguage: args.preferredLanguage ?? existing.preferredLanguage,
        updatedAt: now,
      });
      return existing._id;
    }

    return await ctx.db.insert("users", {
      clerkId: args.clerkId,
      email: args.email,
      displayName: args.displayName,
      avatarUrl: args.avatarUrl,
      preferredLanguage: args.preferredLanguage ?? "en",
      subscriptionTier: "free",
      aiGenerationsThisMonth: 0,
      aiGenerationLimit: 20,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const getByClerkId = query({
  args: { clerkId: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique(),
});

export const syncRevenueCatEntitlement = mutation({
  args: {
    clerkId: v.string(),
    revenueCatAppUserId: v.string(),
    subscriptionTier: v.union(
      v.literal("free"),
      v.literal("trial"),
      v.literal("pro"),
    ),
    entitlementProductId: v.optional(v.string()),
    entitlementExpiresAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();
    if (!existing) throw new Error("User not found");

    await ctx.db.patch(existing._id, {
      subscriptionTier: args.subscriptionTier,
      revenueCatAppUserId: args.revenueCatAppUserId,
      entitlementProductId: args.entitlementProductId,
      entitlementExpiresAt: args.entitlementExpiresAt,
      entitlementUpdatedAt: Date.now(),
      aiGenerationLimit:
        args.subscriptionTier === "pro" ? 500 : existing.aiGenerationLimit,
      updatedAt: Date.now(),
    });
    return existing._id;
  },
});
