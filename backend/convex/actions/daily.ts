"use node";

/**
 * Daily hadith: deterministic per-UTC-date pick over the cached `hadiths`
 * table, plus scheduled APNs/FCM delivery driven by convex/crons.ts.
 *
 * The pick walks DEFAULT_COLLECTION_ORDER starting at a date-derived offset,
 * so every reader sees the same hadith on the same day without any shared
 * mutable state. Collections with nothing cached yet are skipped; when the
 * whole cache is empty (fresh deployment) the first volume of Bukhari is
 * fetched from the provider once to seed it.
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
import { apnsConfigured, sendApnsPush } from "../lib/apns";
import { fcmConfigured, sendFcmPush } from "../lib/fcm";

type DailyHadith = {
  _id: string;
  providerHadithId: string;
  collectionSlug: string;
  collectionName: string;
  volumeId: string | null;
  arabicText: string;
  englishText: string | null;
  referenceDisplay: string;
};

type CachedHadith = {
  _id: string;
  providerHadithId: string;
  collectionSlug: string;
  collectionName: string;
  volumeId?: string;
  arabicText: string;
  englishText?: string;
  referenceDisplay: string;
};

type DailyIo = Pick<ActionCtx, "runQuery" | "runMutation">;

function dateHash(date: string): number {
  let hash = 0;
  for (let index = 0; index < date.length; index += 1) {
    hash = (hash * 31 + date.charCodeAt(index)) >>> 0;
  }
  return hash;
}

/**
 * Resolves today's hadith from the cache, seeding the cache from the
 * provider when nothing is stored yet.
 */
async function pickDailyHadith(io: DailyIo): Promise<CachedHadith | null> {
  const dayUtc = new Date().toISOString().slice(0, 10);
  const seed = dateHash(dayUtc);

  for (let offset = 0; offset < DEFAULT_COLLECTION_ORDER.length; offset += 1) {
    const slug =
      DEFAULT_COLLECTION_ORDER[
        (seed + offset) % DEFAULT_COLLECTION_ORDER.length
      ];
    const items = await io.runQuery(internal.hadiths.listByCollection, {
      provider: "sunnah_now",
      collectionSlug: slug,
    });
    if (items.length > 0) {
      return items[seed % items.length];
    }
  }

  // Fresh cache: pull one volume once so the daily pick always has material.
  try {
    const volumeItems = await fetchVolumeHadiths({
      collectionSlug: "bukhari",
      volumeId: "1",
    });
    if (volumeItems.length === 0) return null;
    const upsertIds = await io.runMutation(internal.hadiths.upsertPage, {
      items: volumeItems,
    });
    const index = seed % volumeItems.length;
    return { _id: upsertIds[index], ...volumeItems[index] };
  } catch {
    return null;
  }
}

function toDailyHadith(hadith: CachedHadith): DailyHadith {
  return {
    _id: hadith._id,
    providerHadithId: hadith.providerHadithId,
    collectionSlug: hadith.collectionSlug,
    collectionName: hadith.collectionName,
    volumeId: hadith.volumeId ?? null,
    arabicText: hadith.arabicText,
    englishText: hadith.englishText ?? null,
    referenceDisplay: hadith.referenceDisplay,
  };
}

/** Public: today's hadith for the Today tab. */
export const getDailyHadith = action({
  args: {},
  handler: async (ctx): Promise<DailyHadith | null> => {
    const picked = await pickDailyHadith({
      runQuery: ctx.runQuery,
      runMutation: ctx.runMutation,
    });
    return picked ? toDailyHadith(picked) : null;
  },
});

type PushTokenDoc = {
  _id: Id<"pushTokens">;
  token: string;
  platform: "ios" | "android";
  dailyTime?: string;
  tzOffsetMinutes?: number;
  enabled: boolean;
  lastSentDate?: string;
};

type SendResult = {
  sent: number;
  failed: number;
  skipped: number;
  apnsConfigured: boolean;
  fcmConfigured: boolean;
};

/** Internal: cron entry — sends the daily hadith to every due device. */
export const sendDueDailyPushes = internalAction({
  args: {},
  handler: async (ctx): Promise<SendResult> => {
    const hasApns = apnsConfigured();
    const hasFcm = fcmConfigured();
    if (!hasApns && !hasFcm) {
      return {
        sent: 0,
        failed: 0,
        skipped: 0,
        apnsConfigured: false,
        fcmConfigured: false,
      };
    }

    const now = Date.now();
    const tokens = await ctx.runQuery(internal.library.listEnabledPushTokens, {});
    const due: PushTokenDoc[] = [];
    for (const token of tokens as PushTokenDoc[]) {
      if (!token.enabled || !token.dailyTime) continue;
      const local = localClock(now, token.tzOffsetMinutes ?? 0);
      const [hour, minute] = token.dailyTime.split(":").map(Number);
      const dueMinutes = hour * 60 + minute;
      const nowMinutes = local.hour * 60 + local.minute;
      if (
        nowMinutes >= dueMinutes &&
        nowMinutes < dueMinutes + 15 &&
        token.lastSentDate !== local.date
      ) {
        due.push(token);
      }
    }
    if (due.length === 0) {
      return {
        sent: 0,
        failed: 0,
        skipped: tokens.length,
        apnsConfigured: hasApns,
        fcmConfigured: hasFcm,
      };
    }

    const picked = await pickDailyHadith({
      runQuery: ctx.runQuery,
      runMutation: ctx.runMutation,
    });
    if (!picked) {
      return {
        sent: 0,
        failed: 0,
        skipped: due.length,
        apnsConfigured: hasApns,
        fcmConfigured: hasFcm,
      };
    }
    const hadith = toDailyHadith(picked);

    let sent = 0;
    let failed = 0;
    let skipped = 0;
    for (const token of due) {
      const local = localClock(now, token.tzOffsetMinutes ?? 0);
      try {
        const title = "Hadith of the day";
        const subtitle = `${hadith.collectionName} · ${hadith.referenceDisplay}`;
        const body = hadith.englishText ?? hadith.arabicText.slice(0, 180);
        const custom = {
          hadithId: hadith._id,
          collectionSlug: hadith.collectionSlug,
          ...(hadith.volumeId ? { volumeId: hadith.volumeId } : {}),
          providerHadithId: hadith.providerHadithId,
        };
        if (token.platform === "ios") {
          if (!hasApns) {
            skipped += 1;
            continue;
          }
          await sendApnsPush(token.token, {
            alert: { title, subtitle, body },
            custom,
          });
        } else {
          if (!hasFcm) {
            skipped += 1;
            continue;
          }
          await sendFcmPush(token.token, {
            title,
            body: `${subtitle}\n${body}`,
            data: custom,
          });
        }
        await ctx.runMutation(internal.library.markPushSent, {
          tokenId: token._id,
          sentDate: local.date,
        });
        sent += 1;
      } catch (error) {
        failed += 1;
        console.error(
          `daily push to token ${token._id} failed:`,
          error instanceof Error ? error.message : error,
        );
      }
    }

    return {
      sent,
      failed,
      skipped,
      apnsConfigured: hasApns,
      fcmConfigured: hasFcm,
    };
  },
});

/** Clock of the device's timezone, derived from its stored UTC offset. */
function localClock(nowMs: number, tzOffsetMinutes: number) {
  // Clients send the conventional UTC - local offset (matching JavaScript's
  // Date.getTimezoneOffset and iOS's existing payload), so subtract it.
  const shifted = new Date(nowMs - tzOffsetMinutes * 60 * 1000);
  return {
    hour: shifted.getUTCHours(),
    minute: shifted.getUTCMinutes(),
    date: shifted.toISOString().slice(0, 10),
  };
}
