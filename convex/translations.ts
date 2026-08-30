import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

const citationsValidator = v.optional(
  v.array(
    v.object({
      url: v.string(),
      title: v.optional(v.string()),
      domain: v.optional(v.string()),
    }),
  ),
);

export const getDefault = query({
  args: {
    hadithId: v.id("hadiths"),
    language: v.string(),
  },
  handler: async (ctx, args) =>
    await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", args.hadithId)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .first(),
});

export const getDefaultForProviderRef = query({
  args: {
    provider: v.union(
      v.literal("sunnah_now"),
      v.literal("sunnah_com"),
      v.literal("local_dump"),
    ),
    collectionSlug: v.string(),
    providerHadithId: v.string(),
    language: v.string(),
  },
  handler: async (ctx, args) => {
    const hadith = await ctx.db
      .query("hadiths")
      .withIndex("by_provider_ref", (q) =>
        q
          .eq("provider", args.provider)
          .eq("collectionSlug", args.collectionSlug)
          .eq("providerHadithId", args.providerHadithId),
      )
      .unique();
    if (!hadith) return null;
    return await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", hadith._id)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .first();
  },
});

export const cacheGeminiTranslation = mutation({
  args: {
    hadithId: v.id("hadiths"),
    language: v.string(),
    content: v.string(),
    aiModel: v.string(),
    confidence: v.optional(v.number()),
    riskFlags: v.optional(v.array(v.string())),
    generatedByUserId: v.optional(v.id("users")),
    groundingUsed: v.optional(v.boolean()),
    groundingSourceCount: v.optional(v.number()),
    citations: citationsValidator,
    sourceReferenceUrl: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    return await ctx.db.insert("translations", {
      hadithId: args.hadithId,
      language: args.language,
      content: args.content,
      source: "gemini_ai",
      sourceLabel: "Gemini AI",
      aiModel: args.aiModel,
      aiPromptVersion: "v1",
      generatedByUserId: args.generatedByUserId,
      status: "live",
      isDefault: true,
      confidence: args.confidence,
      riskFlags: args.riskFlags,
      groundingUsed: args.groundingUsed ?? false,
      groundingSourceCount: args.groundingSourceCount,
      citations: args.citations,
      sourceReferenceUrl: args.sourceReferenceUrl,
      upvotes: 0,
      downvotes: 0,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const cacheGeminiTranslationForProviderRef = mutation({
  args: {
    provider: v.union(
      v.literal("sunnah_now"),
      v.literal("sunnah_com"),
      v.literal("local_dump"),
    ),
    collectionSlug: v.string(),
    providerHadithId: v.string(),
    language: v.string(),
    content: v.string(),
    aiModel: v.string(),
    confidence: v.optional(v.number()),
    riskFlags: v.optional(v.array(v.string())),
    groundingUsed: v.optional(v.boolean()),
    groundingSourceCount: v.optional(v.number()),
    citations: citationsValidator,
    sourceReferenceUrl: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const hadith = await ctx.db
      .query("hadiths")
      .withIndex("by_provider_ref", (q) =>
        q
          .eq("provider", args.provider)
          .eq("collectionSlug", args.collectionSlug)
          .eq("providerHadithId", args.providerHadithId),
      )
      .unique();
    if (!hadith) throw new Error("Hadith must be cached before translation");

    const existing = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", hadith._id)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .first();
    if (existing) return existing._id;

    const now = Date.now();
    return await ctx.db.insert("translations", {
      hadithId: hadith._id,
      language: args.language,
      content: args.content,
      source: "gemini_ai",
      sourceLabel: "Gemini AI",
      aiModel: args.aiModel,
      aiPromptVersion: "v1",
      status: "live",
      isDefault: true,
      confidence: args.confidence,
      riskFlags: args.riskFlags,
      groundingUsed: args.groundingUsed ?? false,
      groundingSourceCount: args.groundingSourceCount,
      citations: args.citations,
      sourceReferenceUrl: args.sourceReferenceUrl,
      upvotes: 0,
      downvotes: 0,
      ratingPercent: 100,
      createdAt: now,
      updatedAt: now,
    });
  },
});

function ratingPercent(upvotes: number, downvotes: number) {
  const total = upvotes + downvotes;
  return total === 0 ? undefined : Math.round((upvotes / total) * 100);
}

export const castVote = mutation({
  args: {
    userId: v.id("users"),
    translationId: v.id("translations"),
    vote: v.union(v.literal("up"), v.literal("down")),
    reason: v.optional(
      v.union(
        v.literal("meaning"),
        v.literal("language"),
        v.literal("missing_nuance"),
        v.literal("grammar"),
        v.literal("inappropriate"),
        v.literal("other"),
      ),
    ),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("translationVotes")
      .withIndex("by_user_translation", (q) =>
        q.eq("userId", args.userId).eq("translationId", args.translationId),
      )
      .unique();

    if (existing) {
      const translation = await ctx.db.get(args.translationId);
      if (!translation) throw new Error("Translation not found");
      const oldUp = existing.vote === "up" ? 1 : 0;
      const oldDown = existing.vote === "down" ? 1 : 0;
      const newUp = args.vote === "up" ? 1 : 0;
      const newDown = args.vote === "down" ? 1 : 0;
      const upvotes = translation.upvotes - oldUp + newUp;
      const downvotes = translation.downvotes - oldDown + newDown;
      await ctx.db.patch(existing._id, {
        vote: args.vote,
        reason: args.reason,
        createdAt: Date.now(),
      });
      await ctx.db.patch(args.translationId, {
        upvotes,
        downvotes,
        ratingPercent: ratingPercent(upvotes, downvotes),
        updatedAt: Date.now(),
      });
      return existing._id;
    }

    const translation = await ctx.db.get(args.translationId);
    if (!translation) throw new Error("Translation not found");
    const upvotes = translation.upvotes + (args.vote === "up" ? 1 : 0);
    const downvotes = translation.downvotes + (args.vote === "down" ? 1 : 0);
    await ctx.db.patch(args.translationId, {
      upvotes,
      downvotes,
      ratingPercent: ratingPercent(upvotes, downvotes),
      updatedAt: Date.now(),
    });

    return await ctx.db.insert("translationVotes", {
      userId: args.userId,
      translationId: args.translationId,
      vote: args.vote,
      reason: args.reason,
      createdAt: Date.now(),
    });
  },
});
