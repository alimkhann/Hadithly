import { v, type Infer } from "convex/values";
import type { AuthenticityClaim, HadithProviderName } from "./contentPolicy";
import { canonicalizeLocaleTag } from "./preferences";

export const FIRST_READING_LOCALES = ["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn"] as const;
export type FirstReadingLocale = typeof FIRST_READING_LOCALES[number];

export function firstReadingLocale(input: string): FirstReadingLocale {
  const canonical = canonicalizeLocaleTag(input);
  const locale = FIRST_READING_LOCALES.find(value => value === canonical);
  if (!locale) throw new Error("UNSUPPORTED_FIRST_READING_LANGUAGE");
  return locale;
}

export const firstReadingSource = v.union(
  v.object({ kind: v.literal("arabic_original") }),
  v.object({ kind: v.literal("provider_english") }),
  v.object({ kind: v.literal("ai_translation"), translationId: v.id("translations") }),
  v.object({ kind: v.literal("published_translation"), translationId: v.id("translations") }),
  v.object({ kind: v.literal("licensed_translation"), translationId: v.id("translations"), permissionGrantId: v.id("evidencePermissionGrants") }),
);
export type FirstReadingSource = Infer<typeof firstReadingSource>;

export type FirstReadingCredit = { scope: "original" | "translation"; attribution: string; licenseName: string; url: string | null };
type ReadingAttribution = { text: string; sourceLabel: string; sourceUrl: string | null; credits: FirstReadingCredit[] };
export type FirstReadingText =
  | (ReadingAttribution & { kind: "original"; language: "ar"; isAI: false })
  | (ReadingAttribution & { kind: "translation"; language: FirstReadingLocale; isAI: boolean });
export type FirstReadingDocument = {
  canonicalId: string;
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
  collectionName: string;
  volumeId: string | null;
  referenceDisplay: string;
  referenceUrl: string | null;
  authenticity: AuthenticityClaim;
  arabicText: string;
  text: FirstReadingText;
};
export type FirstReadingDailySummary = {
  canonicalId: string;
  referenceDisplay: string;
  hasExactText: boolean;
};
export type FirstReadingResult =
  | { kind: "ready"; locale: FirstReadingLocale; origin: "daily" | "starter"; reading: FirstReadingDocument; validUntil: number | null; daily: FirstReadingDailySummary | null }
  | { kind: "unavailable"; locale: FirstReadingLocale; reason: "not_prepared"; daily: FirstReadingDailySummary | null };

export function firstReadingPublicUrl(raw: string | undefined): string | null {
  if (!raw) return null;
  try {
    const url = new URL(raw);
    if (url.protocol !== "https:" || url.username || url.password || url.hostname === "localhost" || url.hostname.endsWith(".local") || /^\[|^\d+(?:\.\d+){3}$/.test(url.hostname)) return null;
    if (url.pathname.startsWith("/api/storage/") || [...url.searchParams.keys()].some(key => /token|signature|credential|secret|api.?key/i.test(key))) return null;
    return url.toString();
  } catch { return null; }
}
