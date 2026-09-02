import { internalMutation, internalQuery, mutation, query } from "./_generated/server";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";

export const DEFAULT_AI_GENERATION_LIMIT = 20;
export const PRO_AI_GENERATION_LIMIT = 500;

/**
 * Upserts the signed-in user from their Clerk identity. Called by the app
 * right after sign-in. preferredLanguage is only applied on first creation
 * unless explicitly provided.
 */
export const ensureCurrentUser = mutation({
  args: { preferredLanguage: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const now = Date.now();
    const existing = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        email: existing.email ?? identity.email,
        displayName: existing.displayName ?? identity.name,
        avatarUrl: existing.avatarUrl ?? identity.pictureUrl,
        preferredLanguage:
          args.preferredLanguage ?? existing.preferredLanguage,
        updatedAt: now,
      });
      return existing._id;
    }

    return await ctx.db.insert("users", {
      clerkId: identity.clerkId,
      email: identity.email,
      displayName: identity.name,
      avatarUrl: identity.pictureUrl,
      preferredLanguage: args.preferredLanguage ?? "en",
      subscriptionTier: "free",
      aiGenerationsThisMonth: 0,
      aiGenerationLimit: DEFAULT_AI_GENERATION_LIMIT,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const getCurrentUser = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    return await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
      .unique();
  },
});

/**
 * Permanently removes the authenticated user's Hadithly data. The client calls
 * this before deleting the Clerk identity so the Convex JWT is still valid.
 * It is deliberately idempotent: a retry after a partial client-side failure
 * can still finish deleting the Clerk account.
 */
export const deleteCurrentUser = mutation({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
      .unique();

    if (!user) return false;

    const [
      bookmarks,
      favorites,
      notes,
      readingProgress,
      pushTokens,
      submissions,
      contributedTranslations,
      generatedTranslations,
      reports,
      auditRows,
    ] = await Promise.all([
      ctx.db.query("bookmarks").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("favorites").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("readingProgress").withIndex("by_user_collection", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("pushTokens").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("communitySubmissions").withIndex("by_submitted_by", (q) => q.eq("submittedBy", user._id)).collect(),
      ctx.db.query("translations").withIndex("by_contributor_user", (q) => q.eq("contributorUserId", user._id)).collect(),
      ctx.db.query("translations").withIndex("by_generated_user", (q) => q.eq("generatedByUserId", user._id)).collect(),
      ctx.db.query("translationReports").withIndex("by_reporter", (q) => q.eq("reporterUserId", user._id)).collect(),
      ctx.db.query("adminAuditLog").withIndex("by_actor", (q) => q.eq("actorUserId", user._id)).collect(),
    ]);

    for (const row of [
      ...bookmarks,
      ...favorites,
      ...notes,
      ...readingProgress,
      ...pushTokens,
      ...submissions,
      ...reports,
    ]) {
      await ctx.db.delete(row._id);
    }

    const contributedIds = new Set(contributedTranslations.map((row) => row._id.toString()));
    for (const translation of contributedTranslations) {
      await ctx.db.delete(translation._id);
    }
    for (const translation of generatedTranslations) {
      if (!contributedIds.has(translation._id.toString())) {
        await ctx.db.patch(translation._id, { generatedByUserId: undefined });
      }
    }
    for (const auditRow of auditRows) {
      await ctx.db.patch(auditRow._id, { actorUserId: undefined });
    }

    await ctx.db.delete(user._id);
    return true;
  },
});

/** Internal: resolve a user row by Clerk id. Safe to call from actions
 * (no auth context needed) — used by AI/webhook flows. */
export const getByClerkId = internalQuery({
  args: { clerkId: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique(),
});

/**
 * Internal: sync a RevenueCat entitlement by Clerk id. Called from the
 * RevenueCat webhook httpAction. app_user_id is the Clerk user id.
 */
export const syncRevenueCatEntitlement = internalMutation({
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
    const now = Date.now();
    const existing = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();

    if (!existing) {
      return await ctx.db.insert("users", {
        clerkId: args.clerkId,
        preferredLanguage: "en",
        subscriptionTier: args.subscriptionTier,
        revenueCatAppUserId: args.revenueCatAppUserId,
        entitlementProductId: args.entitlementProductId,
        entitlementExpiresAt: args.entitlementExpiresAt,
        entitlementUpdatedAt: now,
        aiGenerationsThisMonth: 0,
        aiGenerationLimit:
          args.subscriptionTier === "free"
            ? DEFAULT_AI_GENERATION_LIMIT
            : PRO_AI_GENERATION_LIMIT,
        createdAt: now,
        updatedAt: now,
      });
    }

    await ctx.db.patch(existing._id, {
      subscriptionTier: args.subscriptionTier,
      revenueCatAppUserId: args.revenueCatAppUserId,
      entitlementProductId: args.entitlementProductId,
      entitlementExpiresAt: args.entitlementExpiresAt,
      entitlementUpdatedAt: now,
      aiGenerationLimit:
        args.subscriptionTier === "free"
          ? DEFAULT_AI_GENERATION_LIMIT
          : PRO_AI_GENERATION_LIMIT,
      updatedAt: now,
    });
    return existing._id;
  },
});
