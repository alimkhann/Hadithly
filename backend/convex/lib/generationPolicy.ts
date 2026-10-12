import { subscriptionAccess, type SubscriptionFields } from "./revenueCat";
import { v } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import { canonicalizeLocaleTag } from "./preferences";
import { textDigest } from "./evidenceReviewPolicy";
import { untrustedProviderDataBlock } from "./grounding";

export const GENERATION_MODEL = "gemini-2.5-flash-lite";
export const GENERATION_PROMPT_VERSION = "q1-v2";
export const WINDOW_MS = 7 * 24 * 60 * 60 * 1000;
export const LEASE_MS = 120_000;
export const PROVIDER_TIMEOUT_MS = 40_000;
export const PRICING_VERSION = "gemini-2026-10-12";

export function generationSourceAllowed(hadith: Doc<"hadiths">): boolean {
  return !!hadith.arabicText.trim() && new TextEncoder().encode(untrustedProviderDataBlock(hadith)).byteLength <= 64_000;
}
const locales = new Set(["en", "ar", "ru", "kk", "ky", "uz", "tr", "id", "ur", "fr", "es-419", "pt-BR", "sw", "hi", "bn", "de", "it", "pl", "uk", "fa", "ms", "ha", "so", "zh-Hans", "ja", "ko"]);

export function generationLanguage(value: string): string {
  if (value.length > 35) throw new Error("INVALID_TRANSLATION_LANGUAGE");
  const language = canonicalizeLocaleTag(value);
  if (!language || !locales.has(language)) throw new Error("INVALID_TRANSLATION_LANGUAGE");
  return language;
}

export async function generationIdentity(hadith: Doc<"hadiths">, language: string) {
  const sourceDigest = await textDigest(JSON.stringify([hadith.arabicText, hadith.englishText ?? null,
    hadith.narrator ?? null, hadith.referenceDisplay]));
  const canonicalId = `${hadith.provider}:${hadith.collectionSlug}:${hadith.providerHadithId}`;
  const generationKey = await textDigest(JSON.stringify([canonicalId, language, sourceDigest, GENERATION_MODEL, GENERATION_PROMPT_VERSION]));
  return { generationKey, sourceDigest };
}

export function generationLimit(user: SubscriptionFields, now: number): 5 | 100 {
  return subscriptionAccess(user, now) !== null ? 100 : 5;
}

export function rollingAllowance(input: { now: number; limit: number; successes: number[]; reservations: number[] }) {
  const successes = input.successes.filter(time => time > input.now - WINDOW_MS && time <= input.now);
  const reservations = input.reservations.filter(time => time > input.now);
  const releases = [...successes.map(time => time + WINDOW_MS), ...reservations].sort((a, b) => a - b);
  const count = releases.length;
  return { limit: input.limit, used: successes.length, reserved: reservations.length,
    remaining: Math.max(0, input.limit - count),
    retryAt: count >= input.limit ? releases[count - input.limit] ?? null : null,
    windowMs: WINDOW_MS };
}

export const telemetryValidator = v.object({ inputTokens: v.number(), outputTokens: v.number(), thinkingTokens: v.number(),
  tokenUsageKnown: v.boolean(), durationMs: v.number() });

export function tokenCostMicroUsd(input: { inputTokens: number; outputTokens: number; thinkingTokens: number }) {
  for (const count of [input.inputTokens, input.outputTokens, input.thinkingTokens]) {
    if (!Number.isSafeInteger(count) || count < 0 || count > 2_000_000) throw new Error("INVALID_COST_TELEMETRY");
  }
  // $0.10/$0.40 per million = 0.10/0.40 microdollars per token.
  return Math.ceil(input.inputTokens * 0.1 + (input.outputTokens + input.thinkingTokens) * 0.4);
}
