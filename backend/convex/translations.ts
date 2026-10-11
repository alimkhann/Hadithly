import { internalQuery, query } from "./_generated/server";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { publicTranslationAvailable, publicationExpiry } from "./lib/evidencePublication";
import { generationIdentity, generationLanguage } from "./lib/generationPolicy";
import { canonicalizeLocaleTag } from "./lib/preferences";

export async function availableDefault(ctx: QueryCtx | MutationCtx, hadith: Doc<"hadiths">, language: string) {
  const rows = await ctx.db.query("translations").withIndex("by_hadith_language_default", q =>
    q.eq("hadithId", hadith._id).eq("language", language).eq("isDefault", true)).collect();
  const key = (await generationIdentity(hadith, language)).generationKey;
  rows.sort((a, b) => Number(a.source === "gemini_ai") - Number(b.source === "gemini_ai"));
  for (const row of rows) {
    if (row.source === "gemini_ai" && row.generationKey && row.generationKey !== key) continue;
    if (await publicTranslationAvailable(ctx, row)) return row;
  }
  return null;
}

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

export function publicTranslation(row: Doc<"translations">) {
  return {
    _id: row._id, _creationTime: row._creationTime, hadithId: row.hadithId, language: row.language, content: row.content,
    source: row.source, sourceLabel: row.sourceLabel, aiModel: row.aiModel, aiPromptVersion: row.aiPromptVersion,
    status: row.status, isDefault: row.isDefault, groundingUsed: row.groundingUsed, groundingSourceCount: row.groundingSourceCount,
    citations: row.citations, sourceReferenceUrl: row.sourceReferenceUrl, createdAt: row.createdAt, updatedAt: row.updatedAt,
    approvedAt: row.approvedAt, ...(row.source === "gemini_ai" ? { confidence: row.confidence, riskFlags: row.riskFlags } : {}),
  };
}

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

/** Cache-only page read: guests can reuse the exact selected locale. */
export const getReaderDefaults = query({
  args: { hadithInternalIds: v.array(v.string()), language: v.string() },
  handler: async (ctx, args) => {
    if (args.hadithInternalIds.length > 10) throw new Error("Too many reader hadiths");
    const language = generationLanguage(args.language);
    return Promise.all([...new Set(args.hadithInternalIds)].map(async internalId => {
      const hadith = await ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", internalId)).unique();
      // Pre-F1 cache rows may lack canonicalId.
      const parts = internalId.split(":");
      const legacy = !hadith && parts.length === 3 && parts[0] === "sunnah_now" ? await ctx.db.query("hadiths")
        .withIndex("by_provider_ref", q => q.eq("provider", "sunnah_now").eq("collectionSlug", parts[1]).eq("providerHadithId", parts[2])).unique() : null;
      const source = hadith ?? legacy;
      const row = source ? await availableDefault(ctx, source, language) : null;
      return { hadithInternalId: internalId, translation: row ? publicTranslation(row) : null };
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
    const language = canonicalizeLocaleTag(args.language);
    if (!language) return null;
    const row = await availableDefault(ctx, hadith, language);
    return row ? publicTranslation(row) : null;
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
    const hadith = await ctx.db.get(args.hadithId);
    const language = canonicalizeLocaleTag(args.language);
    return hadith && language ? await availableDefault(ctx, hadith, language) : null;
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
