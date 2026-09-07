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
  referenceDisplay: string;
  authenticity: AuthenticityClaim;
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

function toDailyHadith(hadith: CachedHadith): DailyHadith {
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
    referenceDisplay: hadith.referenceDisplay,
    authenticity: hadith.authenticity,
  };
}

/** Public: today's hadith for the Today tab. */
export const getDailyHadith = action({
  args: { timezone: v.string() },
  handler: async (ctx, args): Promise<DailyHadith | null> => {
    const picked = await pickDailyHadith({
      runQuery: ctx.runQuery,
      runMutation: ctx.runMutation,
    }, args.timezone, Date.now());
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
    const tokens: PushTokenDoc[] = await ctx.runQuery(
      internal.library.listEnabledPushTokens,
      {},
    );
    const due: PushTokenDoc[] = [];
    for (const token of tokens) {
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
    }, "Etc/UTC", now);
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
