import { v } from "convex/values";
import { query, internalMutation, type QueryCtx, type MutationCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { isDailyEligible, localDateInTimezone } from "./lib/dailyEligibility";
import { READER_COLLECTIONS } from "./lib/contentPolicy";
import { PROVIDER_HADITH_ID_PATTERN } from "./lib/canonicalLinks";
import { generationIdentity } from "./lib/generationPolicy";
import { textDigest } from "./lib/evidenceReviewPolicy";
import { PublicationReadBudget, publicTranslationAvailable, publicationExpiry } from "./lib/evidencePublication";
import { firstReadingLocale, firstReadingPublicUrl, firstReadingSource } from "./lib/firstReadingPolicy";
import type { FirstReadingLocale, FirstReadingSource, FirstReadingResult, FirstReadingDocument, FirstReadingDailySummary, FirstReadingCredit } from "./lib/firstReadingPolicy";

type Context = QueryCtx | MutationCtx;
type Resolved = { reading: FirstReadingDocument; validUntil: number | null };
const MAX_DEFAULTS = 4;

async function resolve(ctx: Context, hadithId: Id<"hadiths">, source: FirstReadingSource, locale: FirstReadingLocale, budget: PublicationReadBudget): Promise<Resolved | null> {
  if (!budget.spend(2)) return null;
  const hadith = await ctx.db.get(hadithId);
  const license = hadith?.licenseRecordId ? await ctx.db.get(hadith.licenseRecordId) : null;
  if (!hadith?.arabicText.trim() || !isDailyEligible(hadith.authenticity) || !hadith.authenticity || license?.terms.kind !== "verified" || !license.terms.permitsDisplay) return null;
  const canonicalId = `${hadith.provider}:${hadith.collectionSlug}:${hadith.providerHadithId}`;
  if (hadith.provider !== "sunnah_now" || !READER_COLLECTIONS.some(slug => slug === hadith.collectionSlug) ||
    !PROVIDER_HADITH_ID_PATTERN.test(hadith.providerHadithId) || hadith.canonicalId && hadith.canonicalId !== canonicalId) return null;
  const base = { canonicalId, provider: hadith.provider, collectionSlug: hadith.collectionSlug,
    providerHadithId: hadith.providerHadithId, collectionName: hadith.collectionName,
    volumeId: hadith.volumeId ?? null, referenceDisplay: hadith.referenceDisplay,
    authenticity: hadith.authenticity, arabicText: hadith.arabicText, referenceUrl: firstReadingPublicUrl(license.sourceUrl) };
  const reference = firstReadingPublicUrl(license.sourceUrl);
  const credits: FirstReadingCredit[] = [{ scope: "original", attribution: license.sourceName,
    licenseName: license.terms.licenseName, url: firstReadingPublicUrl(license.terms.licenseUrl) }];
  if (source.kind === "arabic_original") {
    return locale === "ar" ? { reading: { ...base, text: { kind: "original", text: hadith.arabicText, language: locale, sourceLabel: license.sourceName, sourceUrl: reference, credits, isAI: false } }, validUntil: null } : null;
  }
  if (source.kind === "provider_english") {
    return locale === "en" && hadith.englishText?.trim() ? { reading: { ...base, text: { kind: "translation", text: hadith.englishText, language: locale, sourceLabel: license.sourceName, sourceUrl: reference, credits, isAI: false } }, validUntil: null } : null;
  }
  if (!budget.spend(1)) return null;
  const row = await ctx.db.get(source.translationId);
  if (!row || row.hadithId !== hadithId || row.language !== locale || !row.content.trim() || !row.isDefault) return null;
  if (!budget.spend(1)) return null;
  const digest = await textDigest(row.content);
  const blocked = await ctx.db.query("firstReadingBlockedTexts").withIndex("by_exact_text", q =>
    q.eq("locale", locale).eq("canonicalId", canonicalId).eq("contentSha256", digest)).unique();
  if (blocked) return null;
  if (source.kind === "ai_translation" && (row.source !== "gemini_ai" || !row.generationKey || row.generationKey !== (await generationIdentity(hadith, locale)).generationKey)) return null;
  if (source.kind === "published_translation" && !row.evidencePublicationId) return null;
  let sourceUrl = row.citations?.map(citation => firstReadingPublicUrl(citation.url)).find(url => url !== null) ?? null;
  let directExpiry: number | null = null;
  if (source.kind === "licensed_translation") {
    if (row.source !== "official" || !budget.spend(1)) return null;
    const permission = (await ctx.db.get(source.permissionGrantId))?.grant;
    if (!permission || permission.sourceKind !== "approved_translation" || permission.canonicalId !== canonicalId ||
      permission.language !== locale || permission.textSha256 !== await textDigest(row.content) ||
      !permission.access || !permission.display || permission.conditions !== "attribution_only" || permission.revokedAt !== undefined ||
      permission.expiresAt !== undefined && (!Number.isFinite(permission.expiresAt) || permission.expiresAt <= Date.now())) return null;
    sourceUrl = firstReadingPublicUrl(permission.citation.url);
    directExpiry = permission.expiresAt ?? null;
    credits.push({ scope: "translation", attribution: permission.attribution, licenseName: permission.licenseName,
      url: firstReadingPublicUrl(permission.permissionUrl) });
  }
  if (!await publicTranslationAvailable(ctx, row, new Set(), budget)) return null;
  if (row.evidencePublicationId) {
    if (!budget.spend(1)) return null;
    const revision = await ctx.db.get(row.evidencePublicationId);
    if (!revision?.permissions?.length || revision.permissions.length > 8) return null;
    for (const permission of revision.permissions) {
      credits.push({ scope: "translation", attribution: permission.attribution, licenseName: permission.licenseName,
        url: firstReadingPublicUrl(permission.permissionUrl) });
    }
  }
  if (credits.some(credit => !credit.attribution.trim() || !credit.licenseName.trim())) return null;
  const publicationDeadline = row.evidencePublicationId ? await publicationExpiry(ctx, row.evidencePublicationId, new Set(), budget) : null;
  const deadlines = [directExpiry, publicationDeadline].filter((value): value is number => value !== null);
  const validUntil = deadlines.length ? Math.min(...deadlines) : null;
  if (validUntil !== null && (!Number.isFinite(validUntil) || validUntil <= Date.now())) return null;
  return { reading: { ...base, text: { kind: "translation", text: row.content, language: locale,
    sourceLabel: row.source === "gemini_ai" ? "AI translation" : row.sourceLabel,
    sourceUrl, credits, isAI: row.source === "gemini_ai" } }, validUntil };
}

function automaticSource(row: Doc<"translations">): FirstReadingSource | null {
  if (row.evidencePublicationId) return { kind: "published_translation", translationId: row._id };
  if (row.source === "gemini_ai" && row.generationKey) return { kind: "ai_translation", translationId: row._id };
  return null;
}

async function contentDigest(reading: FirstReadingDocument): Promise<string> {
  return textDigest(JSON.stringify([reading.canonicalId, reading.arabicText, reading.text]));
}

export const get = query({
  args: { translationLocale: v.string(), timezone: v.string() },
  handler: async (ctx, args): Promise<FirstReadingResult> => {
    const locale = firstReadingLocale(args.translationLocale);
    const localDate = localDateInTimezone(Date.now(), args.timezone);
    const budget = new PublicationReadBudget(128);
    const selected = await ctx.db.query("dailySelections").withIndex("by_local_date_timezone", q => q.eq("localDate", localDate).eq("timezone", args.timezone)).unique();
    const dailyHadith = selected ? await ctx.db.get(selected.hadithId) : null;
    const daily: FirstReadingDailySummary | null = dailyHadith ? {
      canonicalId: `${dailyHadith.provider}:${dailyHadith.collectionSlug}:${dailyHadith.providerHadithId}`,
      referenceDisplay: dailyHadith.referenceDisplay, hasExactText: false,
    } : null;
    if (dailyHadith) {
      const sources: FirstReadingSource[] = locale === "ar" ? [{ kind: "arabic_original" }] : locale === "en" ? [{ kind: "provider_english" }] : [];
      if (sources.length === 0) {
        const rows = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", dailyHadith._id).eq("language", locale).eq("isDefault", true)).take(MAX_DEFAULTS + 1);
        if (rows.length <= MAX_DEFAULTS) for (const row of rows) { const source = automaticSource(row); if (source) sources.push(source); }
      }
      for (const source of sources) {
        const exact = await resolve(ctx, dailyHadith._id, source, locale, budget);
        if (exact) return { kind: "ready", locale, origin: "daily", ...exact, daily: daily ? { ...daily, hasExactText: true } : null };
      }
    }
    const slots = await ctx.db.query("firstReadingSlots").withIndex("by_locale_rank", q => q.eq("locale", locale)).order("asc").take(4);
    if (slots.length <= 3) for (const slot of slots) {
      if (budget.exhausted) break;
      const exact = await resolve(ctx, slot.hadithId, slot.source, locale, budget);
      if (!exact || await contentDigest(exact.reading) !== slot.contentDigest) continue;
      const origin = exact.reading.canonicalId === daily?.canonicalId ? "daily" : "starter";
      return { kind: "ready", locale, origin, ...exact, daily: daily && origin === "daily" ? { ...daily, hasExactText: true } : daily };
    }
    return { kind: "unavailable", locale, reason: "not_prepared", daily };
  },
});

export const prepareSlot = internalMutation({
  args: { locale: v.string(), rank: v.union(v.literal(0), v.literal(1), v.literal(2)), hadithId: v.id("hadiths"), source: firstReadingSource },
  handler: async (ctx, args): Promise<Id<"firstReadingSlots">> => {
    const locale = firstReadingLocale(args.locale);
    const exact = await resolve(ctx, args.hadithId, args.source, locale, new PublicationReadBudget(128));
    if (!exact) throw new Error("FIRST_READING_NOT_AUTHORIZED");
    const entry = { ...args, locale, contentDigest: await contentDigest(exact.reading), updatedAt: Date.now() };
    const existing = await ctx.db.query("firstReadingSlots").withIndex("by_locale_rank", q => q.eq("locale", locale).eq("rank", args.rank)).unique();
    if (existing) { await ctx.db.replace(existing._id, entry); return existing._id; }
    return ctx.db.insert("firstReadingSlots", entry);
  },
});


export const blockTranslation = internalMutation({
  args: { translationId: v.id("translations"), contentSha256: v.string(), reason: v.union(v.literal("meaning_reversal"), v.literal("unsuitable_standalone")) },
  handler: async (ctx, args): Promise<Id<"firstReadingBlockedTexts">> => {
    const row = await ctx.db.get(args.translationId);
    const hadith = row ? await ctx.db.get(row.hadithId) : null;
    if (!row || !hadith || await textDigest(row.content) !== args.contentSha256) throw new Error("FIRST_READING_TEXT_CHANGED");
    const locale = firstReadingLocale(row.language);
    const canonicalId = `${hadith.provider}:${hadith.collectionSlug}:${hadith.providerHadithId}`;
    const existing = await ctx.db.query("firstReadingBlockedTexts").withIndex("by_exact_text", q =>
      q.eq("locale", locale).eq("canonicalId", canonicalId).eq("contentSha256", args.contentSha256)).unique();
    if (existing) return existing._id;
    return ctx.db.insert("firstReadingBlockedTexts", { locale, canonicalId, contentSha256: args.contentSha256, reason: args.reason, createdAt: Date.now() });
  },
});
