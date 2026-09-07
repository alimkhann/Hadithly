import { internalMutation, internalQuery, query } from "./_generated/server";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import {
  authenticityClaimValidator,
  canonicalHadithIdentity,
  licenseRecordDescriptorValidator,
  licenseTermsValidator,
  migrateLegacyAuthenticity,
  providerValidator,
} from "./lib/contentPolicy";
import type { AuthenticityClaim } from "./lib/contentPolicy";
import {
  canonicalLocaleParam,
  canonicalPositionParam,
  parseCanonicalHadithPath,
} from "./lib/canonicalLinks";
import { isRTLLocale } from "./lib/preferences";

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

/** Public: full-text search over cached English text + live translations. */export const search = query({
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

/**
 * Public: resolve a canonical hadith link
 * (`/hadith/{collectionSlug}/{providerHadithId}`) to the current cached
 * content revision for the web fallback and native link routing.
 *
 * No user identity is involved and no private reading position is exposed:
 * this mirrors the F1 public daily-selection precedent. Text is returned
 * only when the source's license record is verified for display; otherwise
 * the page shows identity, source, authenticity scope, and app actions only.
 * AI is never generated here — only already-cached live translations are
 * read. A malformed, stale, or unsupported-locale link degrades to a safe
 * fallback; it never errors the page.
 */
export const canonicalLinkTranslationValidator = v.object({
  language: v.string(),
  content: v.string(),
  sourceKind: v.union(
    v.literal("official"),
    v.literal("community"),
    v.literal("gemini_ai"),
  ),
  sourceLabel: v.string(),
  isRTL: v.boolean(),
});

export type CanonicalLinkTranslation = {
  language: string;
  content: string;
  sourceKind: "official" | "community" | "gemini_ai";
  sourceLabel: string;
  isRTL: boolean;
};

export const canonicalLinkResultValidator = v.union(
  v.object({
    status: v.literal("not_found"),
    route: v.union(
      v.object({
        collectionSlug: v.string(),
        providerHadithId: v.string(),
      }),
      v.null(),
    ),
  }),
  v.object({
    status: v.literal("resolved"),
    canonicalId: v.string(),
    collectionSlug: v.string(),
    collectionName: v.string(),
    providerHadithId: v.string(),
    referenceDisplay: v.string(),
    narrator: v.optional(v.string()),
    sourceName: v.string(),
    sourceUrl: v.string(),
    authenticity: authenticityClaimValidator,
    license: licenseTermsValidator,
    contentVersion: v.number(),
    // The requested position parameter validated at the boundary. F3 always
    // lands at the hadith start; R2 consumes this for exact restoration.
    positionVersion: v.optional(v.number()),
    text: v.union(
      v.object({
        visible: v.literal(false),
        translationRequested: v.boolean(),
      }),
      v.object({
        visible: v.literal(true),
        arabicText: v.string(),
        providerEnglish: v.optional(v.string()),
        translation: v.optional(canonicalLinkTranslationValidator),
        // True when the requested locale had no exact match and a base
        // language or provider English text is shown instead. The page
        // labels this fallback explicitly; it is never silent.
        translationFallback: v.boolean(),
        translationRequested: v.boolean(),
      }),
    ),
  }),
);

export type CanonicalLinkResult = {
  status: "resolved";
  canonicalId: string;
  collectionSlug: string;
  collectionName: string;
  providerHadithId: string;
  referenceDisplay: string;
  narrator?: string;
  sourceName: string;
  sourceUrl: string;
  authenticity: AuthenticityClaim;
  license: {
    kind: "unverified";
  } | {
    kind: "verified";
    licenseName: string;
    licenseUrl: string;
    permitsDisplay: boolean;
    permitsRedistribution: boolean;
    permitsOfflineDistribution: boolean;
    verifiedAt: number;
  };
  contentVersion: number;
  positionVersion?: number;
  text:
    | { visible: false; translationRequested: boolean }
    | {
        visible: true;
        arabicText: string;
        providerEnglish?: string;
        translation?: CanonicalLinkTranslation;
        translationFallback: boolean;
        translationRequested: boolean;
      };
} | {
  status: "not_found";
  route: { collectionSlug: string; providerHadithId: string } | null;
};

const PROVIDER_FALLBACK_ORDER: Array<
  "sunnah_now" | "sunnah_com" | "local_dump"
> = ["sunnah_now", "sunnah_com", "local_dump"];

export const resolveCanonicalLink = query({
  args: {
    collectionSlug: v.string(),
    providerHadithId: v.string(),
    locale: v.optional(v.string()),
    pos: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<CanonicalLinkResult> => {
    const route = parseCanonicalHadithPath(
      `/hadith/${args.collectionSlug}/${args.providerHadithId}`,
    );
    if (!route) {
      return { status: "not_found", route: null };
    }

    const locale = canonicalLocaleParam(args.locale);
    const positionVersion = canonicalPositionParam(args.pos) ?? undefined;

    let hadith: Doc<"hadiths"> | null = null;
    for (const provider of PROVIDER_FALLBACK_ORDER) {
      const candidate = await ctx.db
        .query("hadiths")
        .withIndex("by_provider_ref", (q) =>
          q
            .eq("provider", provider)
            .eq("collectionSlug", route.collectionSlug)
            .eq("providerHadithId", route.providerHadithId),
        )
        .unique();
      if (candidate) {
        hadith = candidate;
        break;
      }
    }
    if (!hadith) {
      return { status: "not_found", route };
    }

    const license = hadith.licenseRecordId
      ? await ctx.db.get(hadith.licenseRecordId)
      : undefined;
    const terms = license?.terms ?? { kind: "unverified" as const };
    const displayPermitted =
      terms.kind === "verified" && terms.permitsDisplay === true;

    const identity = canonicalHadithIdentity({
      provider: hadith.provider,
      collectionSlug: hadith.collectionSlug,
      providerHadithId: hadith.providerHadithId,
    });

    if (!displayPermitted) {
      return {
        status: "resolved",
        canonicalId: identity.canonicalId,
        collectionSlug: hadith.collectionSlug,
        collectionName: hadith.collectionName,
        providerHadithId: hadith.providerHadithId,
        referenceDisplay: hadith.referenceDisplay,
        narrator: hadith.narrator,
        sourceName: license?.sourceName ?? hadith.authenticity?.sourceName ?? "",
        sourceUrl: license?.sourceUrl ?? hadith.authenticity?.sourceUrl ?? "",
        authenticity: hadith.authenticity ??
          migrateLegacyAuthenticity({
            collectionSlug: hadith.collectionSlug,
            authenticityGrade: hadith.authenticityGrade,
            authenticityAppliesTo: hadith.authenticityAppliesTo ?? "none",
            authenticitySource: hadith.authenticitySource,
            authenticityConfidence:
              hadith.authenticityConfidence ?? "unavailable",
          }),
        license: terms,
        contentVersion: hadith.sourceUpdatedAt ?? hadith.createdAt,
        positionVersion,
        text: {
          visible: false,
          translationRequested: locale.requested && locale.locale !== null,
        },
      };
    }

    const translation = locale.requested && locale.locale !== null
      ? await resolveLiveTranslation(ctx, hadith._id, locale.locale)
      : null;

    return {
      status: "resolved",
      canonicalId: identity.canonicalId,
      collectionSlug: hadith.collectionSlug,
      collectionName: hadith.collectionName,
      providerHadithId: hadith.providerHadithId,
      referenceDisplay: hadith.referenceDisplay,
      narrator: hadith.narrator,
      sourceName: license?.sourceName ?? hadith.authenticity?.sourceName ?? "",
      sourceUrl: license?.sourceUrl ?? hadith.authenticity?.sourceUrl ?? "",
      authenticity: hadith.authenticity ??
        migrateLegacyAuthenticity({
          collectionSlug: hadith.collectionSlug,
          authenticityGrade: hadith.authenticityGrade,
          authenticityAppliesTo: hadith.authenticityAppliesTo ?? "none",
          authenticitySource: hadith.authenticitySource,
          authenticityConfidence:
            hadith.authenticityConfidence ?? "unavailable",
        }),
      license: terms,
      contentVersion: hadith.sourceUpdatedAt ?? hadith.createdAt,
      positionVersion,
      text: {
        visible: true,
        arabicText: hadith.arabicText,
        providerEnglish: hadith.englishText,
        translation: translation?.translation,
        translationFallback: translation?.fallback ?? false,
        translationRequested: locale.requested && locale.locale !== null,
      },
    };
  },
});

/**
 * Reads only already-live cached translations for the requested language,
 * falling back to the base language first, then provider English. Never
 * generates anything: a web page load must not spend a user's quota or
 * provider spend. The `fallback` flag labels a non-exact language match.
 */
async function resolveLiveTranslation(
  ctx: QueryCtx,
  hadithId: Id<"hadiths">,
  requestedLocale: string,
): Promise<{
  translation?: CanonicalLinkTranslation;
  fallback: boolean;
}> {
  for (const language of translationFallbackChain(requestedLocale)) {
    const row = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", hadithId)
          .eq("language", language)
          .eq("isDefault", true),
      )
      .first();
    if (row && row.status === "live") {
      return {
        translation: {
          language: row.language,
          content: row.content,
          sourceKind: row.source,
          sourceLabel: row.sourceLabel,
          isRTL: isRTLLocale(row.language),
        },
        fallback: row.language !== requestedLocale,
      };
    }
  }
  return { fallback: true };
}

/**
 * Exact locale, base language, then nothing — provider English is the
 * renderer's own labeled fallback, not a translation row.
 */
function translationFallbackChain(requestedLocale: string): string[] {
  const chain = [requestedLocale];
  const base = requestedLocale.split("-")[0];
  if (base !== requestedLocale) chain.push(base);
  return chain;
}

type QueryCtx = import("./_generated/server").QueryCtx;
