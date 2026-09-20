"use node";

/**
 * Daily hadith: one persisted eligible pick per local date and IANA timezone,
 * plus scheduled APNs/FCM delivery driven by convex/crons.ts.
 */

import { v } from "convex/values";
import { action, internalAction } from "../_generated/server";
import type { ActionCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";
import { internal } from "../_generated/api";
import {
  DEFAULT_COLLECTION_ORDER,
  fetchVolumeHadiths,
} from "../lib/sunnahNow";
import type { HadithProviderName } from "../lib/sunnahNow";
import type { AuthenticityClaim } from "../lib/contentPolicy";
import {
  chooseDailyCandidate,
  dailyCollectionOrder,
  isDailyEligible,
  localDateInTimezone,
} from "../lib/dailyEligibility";
import { apnsConfigured, sendApnsPush } from "../lib/apns";
import { fcmConfigured, sendFcmPush } from "../lib/fcm";
import {
  MAX_SENDS_PER_RUN,
  STALE_TOKEN_DAYS,
  allDeliveryBuckets,
  buildNotificationPayload,
  classifyPushError,
  retryDelayMs,
  selectDueTokens,
  type NotificationTranslation,
  type SkipReason,
} from "../lib/notifyContent";

type DailyHadith = {
  _id: string;
  provider: HadithProviderName;
  canonicalId: string;
  providerHadithId: string;
  collectionSlug: string;
  collectionName: string;
  volumeId: string | null;
  arabicText: string;
  englishText: string | null;
  translation: DailyTranslation | null;
  referenceDisplay: string;
  authenticity: AuthenticityClaim;
};

type DailyTranslation = {
  text: string;
  language: string;
  source: string;
  sourceLabel: string;
  isAI: boolean;
};

/**
 * Deliberately narrow, device-local widget contract. This is the only
 * server payload the Daily widget may persist: no account, Saved, note, or
 * reading-position data can cross this boundary.
 */
type DailyWidgetPayload = {
  collectionSlug: string;
  providerHadithId: string;
  reference: string;
  text: string;
  arabicText: string;
  locale: string;
  arabicVisible: boolean;
  translationVisible: boolean;
  isAI: boolean;
  sourceScope: string;
  localDate: string;
  timezone: string;
  updatedAt: number;
};

type CachedHadith = {
  _id: Id<"hadiths">;
  provider: HadithProviderName;
  canonicalId: string;
  providerHadithId: string;
  collectionSlug: string;
  collectionName: string;
  volumeId?: string;
  arabicText: string;
  englishText?: string;
  referenceDisplay: string;
  authenticity: AuthenticityClaim;
};

type DailyIo = Pick<ActionCtx, "runQuery" | "runMutation">;

/**
 * Resolves today's hadith from the cache, seeding the cache from the
 * provider when nothing is stored yet.
 */
async function pickDailyHadith(
  io: DailyIo,
  timezone: string,
  nowMs: number,
): Promise<CachedHadith | null> {
  const localDate = localDateInTimezone(nowMs, timezone);
  const persistedId = await io.runQuery(
    internal.dailySelections.getHadithId,
    { localDate, timezone },
  );
  if (persistedId) {
    const persisted = await io.runQuery(internal.hadiths.getById, {
      hadithId: persistedId,
    });
    if (persisted && isDailyEligible(persisted.authenticity)) return persisted;
  }

  for (const slug of dailyCollectionOrder(DEFAULT_COLLECTION_ORDER, localDate)) {
    const items = await io.runQuery(internal.hadiths.listByCollection, {
      provider: "sunnah_now",
      collectionSlug: slug,
    });
    const candidate = chooseDailyCandidate(items, localDate);
    if (candidate) {
      return await persistDailyCandidate(io, {
        localDate,
        timezone,
        candidate,
      });
    }
  }

  // No eligible cached material: fetch a documented Sahih collection once.
  try {
    const volumeItems = await fetchVolumeHadiths({
      collectionSlug: "bukhari",
      volumeId: "1",
    });
    if (volumeItems.length === 0) return null;
    const upsertIds = await io.runMutation(internal.hadiths.upsertPage, {
      items: volumeItems,
    });
    const candidates = volumeItems.map((item, index) => ({
      _id: upsertIds[index],
      ...item,
    }));
    const candidate = chooseDailyCandidate(candidates, localDate);
    return candidate
      ? await persistDailyCandidate(io, { localDate, timezone, candidate })
      : null;
  } catch {
    return null;
  }
}

async function persistDailyCandidate(
  io: DailyIo,
  input: {
    localDate: string;
    timezone: string;
    candidate: CachedHadith;
  },
): Promise<CachedHadith | null> {
  const hadithId = await io.runMutation(internal.dailySelections.persist, {
    localDate: input.localDate,
    timezone: input.timezone,
    hadithId: input.candidate._id,
  });
  return await io.runQuery(internal.hadiths.getById, { hadithId });
}

function providerEnglishTranslation(hadith: CachedHadith): DailyTranslation | null {
  if (!hadith.englishText?.trim()) return null;
  return {
    text: hadith.englishText,
    language: "en",
    source: hadith.provider,
    sourceLabel: "Sunnah.now",
    isAI: false,
  };
}

/**
 * Daily content may reuse a globally cached translation but may not generate
 * one.  The explicit reader action is the only policy-gated generation path;
 * this keeps a home refresh cheap, signed-out safe, and impossible to use as
 * a quota bypass.
 */
async function resolveDailyTranslation(
  io: DailyIo,
  hadith: CachedHadith,
  language: string,
): Promise<DailyTranslation | null> {
  if (language === "en") return providerEnglishTranslation(hadith);
  const cached = await io.runQuery(
    internal.translations.getDefaultForHadithLanguage,
    { hadithId: hadith._id, language },
  );
  if (!cached) return null;
  return {
    text: cached.content,
    language,
    source: cached.source,
    sourceLabel: cached.source === "gemini_ai" ? "AI translation" : cached.sourceLabel,
    isAI: cached.source === "gemini_ai",
  };
}

function toDailyHadith(
  hadith: CachedHadith,
  translation: DailyTranslation | null,
): DailyHadith {
  return {
    _id: hadith._id,
    provider: hadith.provider,
    canonicalId: hadith.canonicalId,
    providerHadithId: hadith.providerHadithId,
    collectionSlug: hadith.collectionSlug,
    collectionName: hadith.collectionName,
    volumeId: hadith.volumeId ?? null,
    arabicText: hadith.arabicText,
    englishText: hadith.englishText ?? null,
    translation,
    referenceDisplay: hadith.referenceDisplay,
    authenticity: hadith.authenticity,
  };
}

function sourceScopeForWidget(authenticity: AuthenticityClaim): string {
  if (authenticity.claimScope === "collection") {
    return `Sahih collection scope · ${authenticity.sourceName}`;
  }
  if (authenticity.claimScope === "hadith") {
    return `${authenticity.normalizedGrade} hadith grade · ${authenticity.sourceName}`;
  }
  return authenticity.sourceLabel;
}

/**
 * W1 consumes only text materialized by N1's live-default policy. Unlike the
 * notification cron, a widget refresh never asks Gemini to create content.
 * It also deliberately ignores community rows: N1's public reading contract
 * is official text first, then its globally cached AI text.
 */
async function resolveMaterializedWidgetTranslation(
  io: DailyIo,
  hadith: CachedHadith,
  language: string,
): Promise<DailyTranslation | null> {
  if (language === "en") return providerEnglishTranslation(hadith);
  const live = await io.runQuery(
    internal.translations.listLiveDefaultsForHadithLanguage,
    { hadithId: hadith._id, language },
  );
  const best = live
    .filter((row) => row.source === "official" || row.source === "gemini_ai")
    .sort((a, b) => (a.source === "official" ? 0 : 1) - (b.source === "official" ? 0 : 1))[0];
  if (!best) return null;
  return {
    text: best.content,
    language,
    source: best.source,
    sourceLabel: best.source === "gemini_ai" ? "AI translation" : best.sourceLabel,
    isAI: best.source === "gemini_ai",
  };
}

/** Public: today's hadith for the Today tab. */
export const getDailyHadith = action({
  args: { timezone: v.string(), translationLocale: v.string() },
  handler: async (ctx, args): Promise<DailyHadith | null> => {
    const io = {
      runQuery: ctx.runQuery,
      runMutation: ctx.runMutation,
    };
    const picked = await pickDailyHadith(io, args.timezone, Date.now());
    if (!picked) return null;
    return toDailyHadith(
      picked,
      await resolveDailyTranslation(io, picked, args.translationLocale),
    );
  },
});

/** Public: the safe, cacheable payload consumed by native Daily widgets. */
export const getDailyWidgetPayload = action({
  args: { timezone: v.string(), translationLocale: v.string(), arabicVisible: v.optional(v.boolean()), translationVisible: v.optional(v.boolean()) },
  handler: async (ctx, args): Promise<DailyWidgetPayload | null> => {
    const io = { runQuery: ctx.runQuery, runMutation: ctx.runMutation };
    const picked = await pickDailyHadith(io, args.timezone, Date.now());
    if (!picked) return null;
    const translation = await resolveMaterializedWidgetTranslation(
      io,
      picked,
      args.translationLocale,
    );
    if (!translation?.text.trim()) return null;
    return {
      collectionSlug: picked.collectionSlug,
      providerHadithId: picked.providerHadithId,
      reference: picked.referenceDisplay,
      text: translation.text,
      arabicText: picked.arabicText,
      locale: args.translationLocale,
      arabicVisible: args.arabicVisible ?? true,
      translationVisible: args.translationVisible ?? true,
      isAI: translation.isAI,
      sourceScope: sourceScopeForWidget(picked.authenticity),
      localDate: localDateInTimezone(Date.now(), args.timezone),
      timezone: args.timezone,
      updatedAt: Date.now(),
    };
  },
});

type PushTokenDoc = {
  _id: Id<"pushTokens">;
  token: string;
  platform: "ios" | "android";
  dailyTime?: string;
  timezone?: string;
  uiLocale?: string;
  translationLocale?: string;
  deliveryBucket?: string;
  enabled: boolean;
  lastSentDate?: string;
  consecutiveFailures?: number;
  nextRetryAt?: number;
  lastError?: string;
  lastSeenAt?: number;
};

type SendResult = {
  sent: number;
  failed: number;
  skipped: number;
  skippedReasons: Record<string, number>;
  removedStale: number;
  apnsConfigured: boolean;
  fcmConfigured: boolean;
};

type CronIo = Pick<ActionCtx, "runQuery" | "runMutation" | "runAction">;

function emptyResult(hasApns: boolean, hasFcm: boolean): SendResult {
  return {
    sent: 0,
    failed: 0,
    skipped: 0,
    skippedReasons: {},
    removedStale: 0,
    apnsConfigured: hasApns,
    fcmConfigured: hasFcm,
  };
}

/**
 * Resolution order for one notification body: approved/official text first,
 * reusable cached AI second, one globally cached labeled service generation
 * only when policy permits (Gemini key configured). Returns null when
 * nothing usable exists — the caller skips with an observable reason and
 * never falls back to Arabic-only or the wrong language.
 */
async function resolveNotificationTranslation(
  io: CronIo,
  hadith: CachedHadith,
  language: string,
): Promise<NotificationTranslation | null> {
  if (language === "en") {
    const english = providerEnglishTranslation(hadith);
    return english ? { ...english, language: "en" } : null;
  }
  const live = await io.runQuery(
    internal.translations.listLiveDefaultsForHadithLanguage,
    { hadithId: hadith._id, language },
  );
  const rank = (source: string) =>
    source === "official" ? 0 : source === "gemini_ai" ? 2 : 1;
  const best = [...live].sort((a, b) => rank(a.source) - rank(b.source))[0];
  if (best) {
    return {
      text: best.content,
      language,
      isAI: best.source === "gemini_ai",
    };
  }
  try {
    const generated = await io.runAction(
      internal.actions.ai.generateServiceTranslation,
      { hadithId: hadith._id, language },
    );
    if (!generated.content.trim()) return null;
    return { text: generated.content, language, isAI: true };
  } catch (error) {
    console.error(
      `service translation for ${hadith.canonicalId}/${language} failed:`,
      error instanceof Error ? error.message : error,
    );
    return null;
  }
}

export type PushSenders = {
  sendApns: (
    token: string,
    payload: { alert: { title: string; body: string }; custom: Record<string, string> },
  ) => Promise<unknown>;
  sendFcm: (
    token: string,
    payload: { title: string; body: string; data: Record<string, string> },
  ) => Promise<unknown>;
};

/**
 * The cron loop with injectable senders and clock. The action below wires
 * the real providers; tests wire record-only fakes. Idempotent: re-running
 * a tick converges (lastSentDate guards duplicates, retries are bounded
 * per local date, permanent failures delete the token).
 */
export async function runDuePushes(
  io: CronIo,
  now: number,
  senders: PushSenders,
  providers: { hasApns: boolean; hasFcm: boolean },
): Promise<SendResult> {
    const { hasApns, hasFcm } = providers;
    const result = emptyResult(hasApns, hasFcm);
    const skip = (reason: SkipReason) => {
      result.skipped += 1;
      result.skippedReasons[reason] =
        (result.skippedReasons[reason] ?? 0) + 1;
    };
    const staleCutoff = now - STALE_TOKEN_DAYS * 24 * 60 * 60 * 1000;
    // One persisted pick per timezone (local dates differ across zones) and
    // one resolved translation per (hadith, locale) within this run.
    const picks = new Map<string, CachedHadith | null>();
    const translations = new Map<string, NotificationTranslation | null>();

    let stopped = false;
    for (const bucket of allDeliveryBuckets()) {
      if (stopped || result.sent + result.failed >= MAX_SENDS_PER_RUN) break;
      let cursor: string | null | undefined = undefined;
      let isDone = false;
      while (
        !stopped &&
        !isDone &&
        result.sent + result.failed < MAX_SENDS_PER_RUN
      ) {
        const page: {
          rows: PushTokenDoc[];
          isDone: boolean;
          cursor: string | null | undefined;
        } = await io.runQuery(internal.library.listBucketPage, {
          bucket,
          cursor: cursor ?? undefined,
          limit: 200,
        });
        cursor = page.cursor;
        isDone = page.isDone;
        const { due, skipped } = selectDueTokens(page.rows, now);
        for (const { token, reason } of skipped) {
          // Opportunistic hygiene: a bucket read is the only indexed way
          // to find tokens whose app was uninstalled long ago.
          if (
            token.lastSeenAt !== undefined &&
            token.lastSeenAt < staleCutoff
          ) {
            await io.runMutation(internal.library.removeStaleToken, {
              tokenId: token._id,
              reason: "unseen",
            });
            result.removedStale += 1;
            continue;
          }
          skip(reason);
        }
        for (const { token, localDate } of due) {
          if (result.sent + result.failed >= MAX_SENDS_PER_RUN) break;
          const timezone = token.timezone as string;
          const locale = (token.translationLocale ?? "en").trim() || "en";
          if (!picks.has(timezone)) {
            picks.set(
              timezone,
              await pickDailyHadith(
                { runQuery: io.runQuery, runMutation: io.runMutation },
                timezone,
                now,
              ),
            );
          }
          const picked = picks.get(timezone);
          if (!picked) {
            skip("missing-content");
            continue;
          }
          const cacheKey = `${picked._id}:${locale}`;
          if (!translations.has(cacheKey)) {
            translations.set(
              cacheKey,
              await resolveNotificationTranslation(
                {
                  runQuery: io.runQuery,
                  runMutation: io.runMutation,
                  runAction: io.runAction,
                },
                picked,
                locale,
              ),
            );
          }
          const translation = translations.get(cacheKey);
          if (!translation) {
            skip(
              locale === "en" ? "missing-content" : "unresolved-translation",
            );
            continue;
          }
          const payload = buildNotificationPayload({
            collectionName: picked.collectionName,
            referenceDisplay: picked.referenceDisplay,
            translation,
            hadithId: picked._id as string,
            collectionSlug: picked.collectionSlug,
            providerHadithId: picked.providerHadithId,
            volumeId: picked.volumeId,
          });
          const providerOk =
            (token.platform === "ios" && hasApns) ||
            (token.platform === "android" && hasFcm);
          if (!providerOk) {
            skip("provider-unconfigured");
            continue;
          }
          try {
            if (token.platform === "ios") {
              await senders.sendApns(token.token, {
                alert: { title: payload.title, body: payload.body },
                custom: payload.data,
              });
            } else {
              await senders.sendFcm(token.token, {
                title: payload.title,
                body: payload.body,
                data: payload.data,
              });
            }
            await io.runMutation(internal.library.markPushSent, {
              tokenId: token._id,
              sentDate: localDate,
            });
            result.sent += 1;
          } catch (error) {
            const kind = classifyPushError(error);
            const message =
              error instanceof Error ? error.message : String(error);
            if (kind === "permanent") {
              await io.runMutation(internal.library.removeStaleToken, {
                tokenId: token._id,
                reason: "permanent",
              });
              result.removedStale += 1;
              result.failed += 1;
            } else if (kind === "backpressure") {
              await io.runMutation(internal.library.recordPushFailure, {
                tokenId: token._id,
                error: message,
                nextRetryAt: now + retryDelayMs(
                  (token.consecutiveFailures ?? 0) + 1,
                ),
              });
              result.failed += 1;
              // Stop this run; the next tick resumes the remainder.
              stopped = true;
              break;
            } else {
              await io.runMutation(internal.library.recordPushFailure, {
                tokenId: token._id,
                error: message,
                nextRetryAt: now + retryDelayMs(
                  (token.consecutiveFailures ?? 0) + 1,
                ),
              });
              result.failed += 1;
            }
            console.error(
              `daily push to token ${token._id} failed:`,
              message,
            );
          }
        }
      }
    }
    return result;
}

/**
 * Internal: cron entry — sends the daily hadith to every due device.
 * nowMs is injectable for deterministic tests; the scheduler passes nothing.
 */
export const sendDueDailyPushes = internalAction({
  args: { nowMs: v.optional(v.number()) },
  handler: async (ctx, args): Promise<SendResult> => {
    const hasApns = apnsConfigured();
    const hasFcm = fcmConfigured();
    if (!hasApns && !hasFcm) {
      return emptyResult(false, false);
    }
    return await runDuePushes(
      ctx,
      args.nowMs ?? Date.now(),
      { sendApns: sendApnsPush, sendFcm: sendFcmPush },
      { hasApns, hasFcm },
    );
  },
});
