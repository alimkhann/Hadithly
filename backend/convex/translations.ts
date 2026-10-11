import { internalMutation, internalQuery, query } from "./_generated/server";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import type { MutationCtx } from "./_generated/server";
import { publicTranslationAvailable, publicationExpiry } from "./lib/evidencePublication";

export async function deleteContribution(ctx: MutationCtx, translation: Doc<"translations">) {
  const revision = translation.evidencePublicationId ? await ctx.db.get(translation.evidencePublicationId) : null;
  // Keep surviving replacements connected to earlier defaults when an
  // intermediate contributor deletes their account.
  for (const isDefault of [false, true]) {
    const descendants = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", translation.hadithId).eq("language", translation.language).eq("isDefault", isDefault)).collect();
    for (const descendant of descendants) {
      if (descendant._id === translation._id || !descendant.evidencePublicationId) continue;
      const childRevision = await ctx.db.get(descendant.evidencePublicationId);
      if (childRevision?.previousDefaultIds?.includes(translation._id)) {
        const prior = childRevision.previousDefaultIds.flatMap(id => id === translation._id ? revision?.previousDefaultIds ?? [] : [id]);
        await ctx.db.patch(childRevision._id, { previousDefaultIds: [...new Set(prior)] });
      }
    }
  }
  await ctx.db.delete(translation._id);
  if (!translation.isDefault) return;
  const current = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", translation.hadithId).eq("language", translation.language).eq("isDefault", true)).first();
  if (current) return;
  for (const previousId of revision?.previousDefaultIds ?? []) {
    const previous = await ctx.db.get(previousId);
    if (previous && await publicTranslationAvailable(ctx, previous)) { await ctx.db.patch(previous._id, { isDefault: true, updatedAt: Date.now() }); return; }
  }
}

function publicTranslation(row: Doc<"translations">) {
  return {
    _id: row._id, _creationTime: row._creationTime, hadithId: row.hadithId, language: row.language, content: row.content,
    source: row.source, sourceLabel: row.sourceLabel, aiModel: row.aiModel, aiPromptVersion: row.aiPromptVersion,
    status: row.status, isDefault: row.isDefault, groundingUsed: row.groundingUsed, groundingSourceCount: row.groundingSourceCount,
    citations: row.citations, sourceReferenceUrl: row.sourceReferenceUrl, createdAt: row.createdAt, updatedAt: row.updatedAt,
    approvedAt: row.approvedAt, ...(row.source === "gemini_ai" ? { confidence: row.confidence, riskFlags: row.riskFlags } : {}),
  };
}

const citationsValidator = v.optional(
  v.array(
    v.object({
      url: v.string(),
      title: v.optional(v.string()),
      domain: v.optional(v.string()),
    }),
  ),
);

export const watchPublications = query({
  args: { translationIds: v.array(v.id("translations")) },
  handler: async (ctx, args) => {
    if (args.translationIds.length > 40) throw new Error("Too many loaded translations");
    return Promise.all([...new Set(args.translationIds)].map(async translationId => {
      const row = await ctx.db.get(translationId);
      return { translationId, available: await publicTranslationAvailable(ctx, row), validUntil: row?.evidencePublicationId ? await publicationExpiry(ctx, row.evidencePublicationId) : null };
    }));
  },
});

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
    const row = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", hadith._id)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .first();
    return row && await publicTranslationAvailable(ctx, row) ? publicTranslation(row) : null;
  },
});

/** Internal: resolve a translation before accepting a replacement/report. */
export const getById = internalQuery({
  args: { translationId: v.id("translations") },
  handler: async (ctx, args) => await ctx.db.get(args.translationId),
});

/**
 * The cache lookup used by Today.  It intentionally returns only a live,
 * default translation for one exact locale: Today must never silently change
 * the reader's selected language, and merely opening home must never trigger
 * a new AI generation.
 */
export const getDefaultForHadithLanguage = internalQuery({
  args: { hadithId: v.id("hadiths"), language: v.string() },
  handler: async (ctx, args) => {
    const translation = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", args.hadithId)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .first();
    return translation && await publicTranslationAvailable(ctx, translation) ? translation : null;
  },
});

/**
 * Internal: every live default translation for a hadith + language. The
 * notification resolver sorts approved/official text before reusable cached
 * AI so a single-row lookup can never shadow an approved translation.
 */
export const listLiveDefaultsForHadithLanguage = internalQuery({
  args: { hadithId: v.id("hadiths"), language: v.string() },
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", args.hadithId)
          .eq("language", args.language)
          .eq("isDefault", true),
      )
      .collect();
    const available = await Promise.all(rows.map(row => publicTranslationAvailable(ctx, row)));
    return rows.filter((_, index) => available[index]);
  },
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
    if (existing && await publicTranslationAvailable(ctx, existing)) return existing._id;
    if (existing) await ctx.db.patch(existing._id, { isDefault: false });

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
