import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

const provider = v.union(
  v.literal("sunnah_now"),
  v.literal("sunnah_com"),
  v.literal("local_dump"),
);
const authenticityGrade = v.union(
  v.literal("sahih"),
  v.literal("hasan"),
  v.literal("daif"),
  v.literal("mawdu"),
  v.literal("mixed"),
  v.literal("unknown"),
);
const hadithInput = v.object({
  provider,
  providerHadithId: v.string(),
  collectionSlug: v.string(),
  bookId: v.optional(v.string()),
  chapterId: v.optional(v.string()),
  volumeId: v.optional(v.string()),
  arabicText: v.string(),
  englishText: v.optional(v.string()),
  narrator: v.optional(v.string()),
  referenceDisplay: v.string(),
  collectionName: v.string(),
  bookName: v.optional(v.string()),
  chapterName: v.optional(v.string()),
  authenticityGrade: v.optional(authenticityGrade),
  authenticityAppliesTo: v.union(
    v.literal("hadith"),
    v.literal("collection"),
    v.literal("none"),
  ),
  authenticitySource: v.optional(v.string()),
  authenticityConfidence: v.union(
    v.literal("source_provided"),
    v.literal("manual_mapping"),
    v.literal("unavailable"),
  ),
  sourceUpdatedAt: v.optional(v.number()),
});

export const upsertPage = mutation({
  args: { items: v.array(hadithInput) },
  handler: async (ctx, args) => {
    const now = Date.now();
    const ids = [];
    for (const item of args.items) {
      const existing = await ctx.db
        .query("hadiths")
        .withIndex("by_provider_ref", (q) =>
          q
            .eq("provider", item.provider)
            .eq("collectionSlug", item.collectionSlug)
            .eq("providerHadithId", item.providerHadithId),
        )
        .unique();

      if (existing) {
        await ctx.db.patch(existing._id, {
          ...item,
          sourceUpdatedAt: item.sourceUpdatedAt ?? now,
        });
        ids.push(existing._id);
      } else {
        ids.push(
          await ctx.db.insert("hadiths", {
            ...item,
            createdAt: now,
            sourceUpdatedAt: item.sourceUpdatedAt ?? now,
          }),
        );
      }
    }
    return ids;
  },
});

export const getByProviderRef = query({
  args: {
    provider,
    collectionSlug: v.string(),
    providerHadithId: v.string(),
  },
  handler: async (ctx, args) =>
    await ctx.db
      .query("hadiths")
      .withIndex("by_provider_ref", (q) =>
        q
          .eq("provider", args.provider)
          .eq("collectionSlug", args.collectionSlug)
          .eq("providerHadithId", args.providerHadithId),
      )
      .unique(),
});

export const search = query({
  args: {
    query: v.string(),
    collectionSlug: v.optional(v.string()),
    language: v.optional(v.string()),
    limit: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const limit = Math.min(args.limit ?? 20, 50);
    const sourceResults = await ctx.db
      .query("hadiths")
      .withSearchIndex("search_english", (q) => {
        const search = q.search("englishText", args.query);
        return args.collectionSlug
          ? search.eq("collectionSlug", args.collectionSlug)
          : search;
      })
      .take(limit);

    if (sourceResults.length >= limit || !args.language) return sourceResults;

    const translationResults = await ctx.db
      .query("translations")
      .withSearchIndex("search_content", (q) =>
        q
          .search("content", args.query)
          .eq("language", args.language)
          .eq("status", "live"),
      )
      .take(limit - sourceResults.length);

    const translatedHadiths = [];
    for (const translation of translationResults) {
      const hadith = await ctx.db.get(translation.hadithId);
      if (
        hadith &&
        (!args.collectionSlug || hadith.collectionSlug === args.collectionSlug)
      ) {
        translatedHadiths.push(hadith);
      }
    }
    return [...sourceResults, ...translatedHadiths].slice(0, limit);
  },
});
