import { internalMutation, internalQuery, query } from "./_generated/server";
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

/** Public: the default live translation for a hadith + language. */
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

/** Internal: resolve a translation before accepting a replacement/report. */
export const getById = internalQuery({
  args: { translationId: v.id("translations") },
  handler: async (ctx, args) => await ctx.db.get(args.translationId),
});

/**
 * Internal: cache a generated AI translation. There is intentionally no
 * vote/rating tracking — translation quality is a curation concern, not a
 * popularity contest.
 */
export const cacheGeminiTranslation = internalMutation({
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
    const existing = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", args.hadithId)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .first();
    if (existing) return existing._id;

    const now = Date.now();
    return await ctx.db.insert("translations", {
      hadithId: args.hadithId,
      language: args.language,
      content: args.content,
      source: "gemini_ai",
      sourceLabel: "AI",
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
      createdAt: now,
      updatedAt: now,
    });
  },
});

/** Internal: publish an approved community submission as a live translation. */
export const publishCommunityTranslation = internalMutation({
  args: {
    hadithId: v.id("hadiths"),
    language: v.string(),
    content: v.string(),
    contributorUserId: v.id("users"),
    contributorDisplayName: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    return await ctx.db.insert("translations", {
      hadithId: args.hadithId,
      language: args.language,
      content: args.content,
      source: "community",
      sourceLabel: "Community",
      status: "live",
      isDefault: false,
      contributorUserId: args.contributorUserId,
      contributorDisplayName: args.contributorDisplayName,
      groundingUsed: false,
      approvedAt: now,
      createdAt: now,
      updatedAt: now,
    });
  },
});
