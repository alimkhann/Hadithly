import { internalMutation, internalQuery, query } from "./_generated/server";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import {
  authenticityClaimValidator,
  canonicalHadithIdentity,
  licenseRecordDescriptorValidator,
  migrateLegacyAuthenticity,
  providerValidator,
} from "./lib/contentPolicy";
import type { AuthenticityClaim } from "./lib/contentPolicy";

export const hadithInput = v.object({
  provider: providerValidator,
  canonicalId: v.string(),
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
  authenticity: authenticityClaimValidator,
  licenseRecord: licenseRecordDescriptorValidator,
  sourceUpdatedAt: v.optional(v.number()),
});

export type HadithDocument = {
  _id: Id<"hadiths">;
  provider: Doc<"hadiths">["provider"];
  canonicalId: string;
  providerHadithId: string;
  collectionSlug: string;
  volumeId?: string;
  chapterId?: string;
  arabicText: string;
  englishText?: string;
  narrator?: string;
  referenceDisplay: string;
  collectionName: string;
  bookName?: string;
  chapterName?: string;
  authenticity: AuthenticityClaim;
};

/**
 * Internal: upsert a page of provider hadiths into the cache.
 * Called by the sunnah_now data actions after a provider fetch.
 */
export const upsertPage = internalMutation({
  args: { items: v.array(hadithInput) },
  handler: async (ctx, args) => {
    const now = Date.now();
    const ids = [];
    const licenseIds = new Map<string, Id<"licenseRecords">>();
    for (const item of args.items) {
      const { licenseRecord, ...currentItem } = item;
      let licenseRecordId = licenseIds.get(licenseRecord.sourceKey);
      if (!licenseRecordId) {
        const existingLicense = await ctx.db
          .query("licenseRecords")
          .withIndex("by_source_key", (q) =>
            q.eq("sourceKey", licenseRecord.sourceKey),
          )
          .unique();
        licenseRecordId = existingLicense?._id ??
          await ctx.db.insert("licenseRecords", {
            ...licenseRecord,
            createdAt: now,
            updatedAt: now,
          });
        licenseIds.set(licenseRecord.sourceKey, licenseRecordId);
      }
      const existing = await ctx.db
        .query("hadiths")
        .withIndex("by_provider_ref", (q) =>
          q
            .eq("provider", currentItem.provider)
            .eq("collectionSlug", currentItem.collectionSlug)
            .eq("providerHadithId", currentItem.providerHadithId),
        )
        .unique();

      if (existing) {
        await ctx.db.patch(existing._id, {
          ...currentItem,
          licenseRecordId,
          authenticityGrade: undefined,
          authenticityAppliesTo: undefined,
          authenticitySource: undefined,
          authenticityConfidence: undefined,
          sourceUpdatedAt: currentItem.sourceUpdatedAt ?? now,
        });
        ids.push(existing._id);
      } else {
        ids.push(
          await ctx.db.insert("hadiths", {
            ...currentItem,
            licenseRecordId,
            createdAt: now,
            sourceUpdatedAt: currentItem.sourceUpdatedAt ?? now,
          }),
        );
      }
    }
    return ids;
  },
});

/** Internal: resolve a cached hadith by its stable internal id
 * (`provider:collectionSlug:providerHadithId`). */
export const getByProviderRef = internalQuery({
  args: {
    provider: providerValidator,
    collectionSlug: v.string(),
    providerHadithId: v.string(),
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
    return hadith ? currentHadith(hadith) : null;
  },
});

export const getById = internalQuery({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const hadith = await ctx.db.get(args.hadithId);
    return hadith ? currentHadith(hadith) : null;
  },
});

/**
 * Internal: every cached hadith of one volume, in canonical hadith-number
 * order. The reader action uses the count to decide whether the volume is
 * fully cached before serving pages without a provider call.
 */
export const listByVolume = internalQuery({
  args: {
    provider: providerValidator,
    collectionSlug: v.string(),
    volumeId: v.string(),
  },
  handler: async (ctx, args) => {
    const items = await ctx.db
      .query("hadiths")
      .withIndex("by_collection_volume", (q) =>
        q
          .eq("provider", args.provider)
          .eq("collectionSlug", args.collectionSlug)
          .eq("volumeId", args.volumeId),
      )
      .collect();
    return items.map(currentHadith).sort(
      (left, right) =>
        Number(left.providerHadithId) - Number(right.providerHadithId),
    );
  },
});

/**
 * Internal: every cached hadith of one collection, ordered by hadith number.
 * Powers the deterministic daily hadith pick.
 */
export const listByCollection = internalQuery({
  args: { provider: providerValidator, collectionSlug: v.string() },
  handler: async (ctx, args) => {
    const items = await ctx.db
      .query("hadiths")
      .withIndex("by_collection", (q) =>
        q
          .eq("provider", args.provider)
          .eq("collectionSlug", args.collectionSlug),
      )
      .collect();
    return items.map(currentHadith).sort(
      (left, right) =>
        Number(left.providerHadithId) - Number(right.providerHadithId),
    );
  },
});

function currentHadith(hadith: Doc<"hadiths">): HadithDocument {
  const identity = canonicalHadithIdentity({
    provider: hadith.provider,
    collectionSlug: hadith.collectionSlug,
    providerHadithId: hadith.providerHadithId,
  });
  const authenticity = hadith.authenticity ?? migrateLegacyAuthenticity({
    collectionSlug: hadith.collectionSlug,
    authenticityGrade: hadith.authenticityGrade,
    authenticityAppliesTo: hadith.authenticityAppliesTo ?? "none",
    authenticitySource: hadith.authenticitySource,
    authenticityConfidence: hadith.authenticityConfidence ?? "unavailable",
  });
  return {
    _id: hadith._id,
    ...identity,
    volumeId: hadith.volumeId,
    chapterId: hadith.chapterId,
    arabicText: hadith.arabicText,
    englishText: hadith.englishText,
    narrator: hadith.narrator,
    referenceDisplay: hadith.referenceDisplay,
    collectionName: hadith.collectionName,
    bookName: hadith.bookName,
    chapterName: hadith.chapterName,
    authenticity,
  };
}

/** Public: full-text search over cached English text + live translations. */
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

    if (sourceResults.length >= limit || !args.language) {
      return sourceResults.map(currentHadith);
    }
    const language = args.language;

    const translationResults = await ctx.db
      .query("translations")
      .withSearchIndex("search_content", (q) =>
        q
          .search("content", args.query)
          .eq("language", language)
          .eq("status", "live"),
      )
      .take(limit - sourceResults.length);

    const translatedHadiths: Array<Doc<"hadiths">> = [];
    for (const translation of translationResults) {
      const hadith = await ctx.db.get(translation.hadithId);
      if (
        hadith &&
        (!args.collectionSlug || hadith.collectionSlug === args.collectionSlug)
      ) {
        translatedHadiths.push(hadith);
      }
    }
    return [...sourceResults, ...translatedHadiths]
      .slice(0, limit)
      .map(currentHadith);
  },
});
