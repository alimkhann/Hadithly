/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import type { WithoutSystemFields } from "convex/server";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc, Id } from "./_generated/dataModel";
import schema from "./schema";
import { runDuePushes, type PushSenders } from "./actions/daily";
import type { AuthenticityClaim } from "./lib/contentPolicy";
import { localDateInTimezone } from "./lib/dailyEligibility";

const modules = import.meta.glob("./**/*.ts");

const TEST_TOKEN_IDENTIFIER = "https://clerk.hadithly.app|notify_test";
const NOW = Date.parse("2026-09-18T03:05:00Z"); // 08:05 Asia/Almaty.

function identity(subject: string) {
  return { subject, tokenIdentifier: TEST_TOKEN_IDENTIFIER };
}

function sahihScope(): AuthenticityClaim {
  return {
    kind: "collection_scope",
    normalizedGrade: "sahih",
    claimScope: "collection",
    sourceLabel: "Documented Sahih collection",
    sourceName: "Sunnah.com",
    sourceUrl: "https://sunnah.com/bukhari/about",
    verificationMethod: "manual_collection_mapping",
  } satisfies AuthenticityClaim;
}

async function seedUser(t: ReturnType<typeof convexTest>, clerkId: string) {
  return await t.run(async (ctx) => {
    return await ctx.db.insert("users", {
      clerkId,
      preferredLanguage: "en",
      subscriptionTier: "free",
      aiGenerationsThisMonth: 0,
      aiGenerationLimit: 5,
      createdAt: 1,
      updatedAt: 1,
    });
  });
}

async function seedHadith(
  t: ReturnType<typeof convexTest>,
  overrides: Partial<WithoutSystemFields<Doc<"hadiths">>> = {},
) {
  return await t.run(async (ctx) => {
    return await ctx.db.insert("hadiths", {
      provider: "sunnah_now",
      canonicalId: "sunnah_now:bukhari:57",
      providerHadithId: "57",
      collectionSlug: "bukhari",
      collectionName: "Sahih al-Bukhari",
      volumeId: "2",
      arabicText: "إنما الأعمال بالنيات",
      englishText: "Actions are only by intentions.",
      referenceDisplay: "Hadith 57",
      authenticity: sahihScope(),
      createdAt: 1_000,
      ...overrides,
    });
  });
}

async function persistToday(
  t: ReturnType<typeof convexTest>,
  timezone: string,
  hadithId: Id<"hadiths">,
) {
  const localDate = localDateInTimezone(NOW, timezone);
  await t.mutation(internal.dailySelections.persist, {
    localDate,
    timezone,
    hadithId,
  });
  return localDate;
}

function stubIo(t: ReturnType<typeof convexTest>) {
  return {
    // oxlint-disable-next-line @typescript-eslint/no-explicit-any
    runQuery: (fn: any, args: any) => (t as any).query(fn, args),
    // oxlint-disable-next-line @typescript-eslint/no-explicit-any
    runMutation: (fn: any, args: any) => (t as any).mutation(fn, args),
    runAction: () => {
      throw new Error("service generation is unreachable in tests");
    },
  };
}

function recordingSenders(): PushSenders & {
  apns: { token: string; body: string }[];
  fcm: { token: string; body: string }[];
} {
  const apns: { token: string; body: string }[] = [];
  const fcm: { token: string; body: string }[] = [];
  return {
    apns,
    fcm,
    sendApns: async (token, payload) => {
      apns.push({ token, body: payload.alert.body });
    },
    sendFcm: async (token, payload) => {
      fcm.push({ token, body: payload.body });
    },
  };
}

describe("N1 push token registration", () => {
  test("stores IANA zone, locales, and the delivery bucket", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_register"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    const tokenId = await asUser.mutation(api.library.savePushToken, {
      token: "apns-token-1",
      platform: "ios",
      timezone: "Asia/Almaty",
      uiLocale: "en",
      translationLocale: "kk",
    });
    const row = await t.run(async (ctx) => ctx.db.get(tokenId));
    expect(row).toMatchObject({
      timezone: "Asia/Almaty",
      uiLocale: "en",
      translationLocale: "kk",
      dailyTime: "08:00",
      deliveryBucket: "08:00",
      enabled: true,
    });
    expect(row?.lastSeenAt).toBeDefined();
  });

  test("rejects invalid zones and locales, keeps legacy offset working", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_legacy"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await expect(
      asUser.mutation(api.library.savePushToken, {
        token: "x",
        platform: "ios",
        timezone: "Mars/Olympus",
      }),
    ).rejects.toThrow("Invalid IANA timezone");
    await expect(
      asUser.mutation(api.library.savePushToken, {
        token: "x",
        platform: "ios",
        translationLocale: "!!",
      }),
    ).rejects.toThrow("Invalid locale");
    // Pre-N1 clients send only the fixed offset: still accepted, but the
    // row stays un-schedulable until the client sends an IANA zone.
    const tokenId = await asUser.mutation(api.library.savePushToken, {
      token: "legacy-offset-token",
      platform: "android",
      tzOffsetMinutes: -360,
    });
    const row = await t.run(async (ctx) => ctx.db.get(tokenId));
    expect(row?.timezone).toBeUndefined();
    expect(row?.deliveryBucket).toBe("08:00");
  });

  test("re-registration clears retry state (convergent refresh)", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_reregister"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    const tokenId = await asUser.mutation(api.library.savePushToken, {
      token: "flaky-token",
      platform: "ios",
      timezone: "Asia/Almaty",
    });
    await t.mutation(internal.library.recordPushFailure, {
      tokenId,
      error: "socket hang up",
      nextRetryAt: NOW + 60_000,
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "flaky-token",
      platform: "ios",
      timezone: "Asia/Almaty",
    });
    const row = await t.run(async (ctx) => ctx.db.get(tokenId));
    expect(row?.consecutiveFailures).toBe(0);
    expect(row?.nextRetryAt).toBeUndefined();
  });
});

describe("N1 daily notification preferences", () => {
  test("validates the time, recomputes the bucket, and re-arms today", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_prefs"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "pref-token",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "en",
    });
    await expect(
      asUser.mutation(api.library.setDailyNotification, {
        enabled: true,
        dailyTime: "8:00",
      }),
    ).rejects.toThrow("Invalid dailyTime");
    const count = await asUser.mutation(api.library.setDailyNotification, {
      enabled: true,
      dailyTime: "18:37",
      timezone: "Asia/Almaty",
      translationLocale: "ur",
    });
    expect(count).toBe(1);
    const rows = await t.run(async (ctx) =>
      ctx.db.query("pushTokens").collect(),
    );
    expect(rows[0]).toMatchObject({
      dailyTime: "18:37",
      deliveryBucket: "18:30",
      translationLocale: "ur",
      consecutiveFailures: 0,
    });
    expect(rows[0].lastSentDate).toBeUndefined();
  });
});

describe("N1 bucket paging and retry bookkeeping", () => {
  test("listBucketPage serves only enabled rows in the bucket", async () => {
    const t = convexTest(schema, modules);
    const userId = await seedUser(t, "notify_bucket_user");
    const tokenIds = await t.run(async (ctx) => {
      const base = {
        userId,
        platform: "android" as const,
        dailyTime: "08:00",
        deliveryBucket: "08:00",
        timezone: "Asia/Almaty",
        enabled: true,
        consecutiveFailures: 0,
        lastSeenAt: NOW,
        updatedAt: NOW,
      };
      const inBucket = await ctx.db.insert("pushTokens", {
        ...base,
        token: "in-bucket",
      });
      await ctx.db.insert("pushTokens", {
        ...base,
        token: "other-bucket",
        deliveryBucket: "09:00",
      });
      await ctx.db.insert("pushTokens", {
        ...base,
        token: "disabled-bucket",
        enabled: false,
      });
      return inBucket;
    });
    void tokenIds;
    const page = await t.query(internal.library.listBucketPage, {
      bucket: "08:00",
      limit: 200,
    });
    expect(page.rows.map((r) => r.token)).toEqual(["in-bucket"]);
    expect(page.isDone).toBe(true);
  });

  test("markPushSent stamps the date; recordPushFailure bounds retries", async () => {
    const t = convexTest(schema, modules);
    const userId = await seedUser(t, "notify_retry_user");
    const tokenId = await t.run(async (ctx) =>
      ctx.db.insert("pushTokens", {
        userId,
        token: "retry-token",
        platform: "ios" as const,
        dailyTime: "08:00",
        deliveryBucket: "08:00",
        timezone: "Asia/Almaty",
        enabled: true,
        updatedAt: NOW,
      }),
    );
    await t.mutation(internal.library.markPushSent, {
      tokenId,
      sentDate: "2026-09-18",
    });
    let row = await t.run(async (ctx) => ctx.db.get(tokenId));
    expect(row?.lastSentDate).toBe("2026-09-18");
    expect(row?.consecutiveFailures).toBe(0);
    await t.mutation(internal.library.recordPushFailure, {
      tokenId,
      error: "socket hang up",
      nextRetryAt: NOW + 120_000,
    });
    row = await t.run(async (ctx) => ctx.db.get(tokenId));
    expect(row?.consecutiveFailures).toBe(1);
    expect(row?.nextRetryAt).toBe(NOW + 120_000);
  });
});

describe("N1 migration", () => {
  test("fills buckets without inventing timezones; reruns are no-ops", async () => {
    const t = convexTest(schema, modules);
    const userId = await seedUser(t, "notify_migrate_user");
    await t.run(async (ctx) => {
      await ctx.db.insert("pushTokens", {
        userId,
        token: "legacy-row",
        platform: "ios" as const,
        dailyTime: "08:07",
        tzOffsetMinutes: -300,
        enabled: true,
        updatedAt: 1,
      });
    });
    const first = await t.mutation(internal.migrations.migrateN1PushTokens, {
      paginationOpts: { numItems: 10, cursor: null },
    });
    expect(first.migrated).toBe(1);
    const row = await t.run(async (ctx) =>
      ctx.db
        .query("pushTokens")
        .withIndex("by_token", (q) => q.eq("token", "legacy-row"))
        .unique(),
    );
    expect(row?.deliveryBucket).toBe("08:00");
    expect(row?.timezone).toBeUndefined();
    expect(row?.lastSeenAt).toBeDefined();
    const second = await t.mutation(internal.migrations.migrateN1PushTokens, {
      paginationOpts: { numItems: 10, cursor: null },
    });
    expect(second).toMatchObject({ migrated: 0, unchanged: 1, isDone: true });
  });
});

describe("N1 cron loop", () => {
  test("sends English to a due device and never duplicates the local date", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_loop_en"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "due-android",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "en",
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    const senders = recordingSenders();
    const io = stubIo(t);
    const first = await runDuePushes(io, NOW, senders, {
      hasApns: true,
      hasFcm: true,
    });
    expect(first.sent).toBe(1);
    expect(first.failed).toBe(0);
    expect(senders.fcm).toHaveLength(1);
    expect(senders.fcm[0].body).toContain("Actions are only by intentions.");
    expect(senders.fcm[0].body).not.toContain("إنما");
    // Same tick again: the stamped local date suppresses the duplicate.
    const second = await runDuePushes(stubIo(t), NOW, recordingSenders(), {
      hasApns: true,
      hasFcm: true,
    });
    expect(second.sent).toBe(0);
    expect(second.skippedReasons["duplicate-local-date"]).toBe(1);
  });

  test("never sends Arabic-only or the wrong language as a silent fallback", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_loop_kk"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "due-kk",
      platform: "ios",
      timezone: "Asia/Almaty",
      translationLocale: "kk",
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    const senders = recordingSenders();
    const result = await runDuePushes(stubIo(t), NOW, senders, {
      hasApns: true,
      hasFcm: true,
    });
    // No cached kk text and no reachable service generation in tests.
    expect(result.sent).toBe(0);
    expect(result.skippedReasons["unresolved-translation"]).toBe(1);
    expect(senders.apns).toHaveLength(0);
  });

  test("prefers approved text over cached AI and labels AI bodies", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_loop_approved"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "due-ur",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "ur",
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    await t.run(async (ctx) => {
      const base = {
        hadithId,
        language: "ur",
        status: "live" as const,
        isDefault: true,
        groundingUsed: false,
        createdAt: 1,
        updatedAt: 1,
      };
      await ctx.db.insert("translations", {
        ...base,
        content: "AI Urdu draft.",
        source: "gemini_ai",
        sourceLabel: "AI",
      });
      await ctx.db.insert("translations", {
        ...base,
        content: "Approved Urdu rendering.",
        source: "official",
        sourceLabel: "Official",
      });
    });
    const senders = recordingSenders();
    const result = await runDuePushes(stubIo(t), NOW, senders, {
      hasApns: true,
      hasFcm: true,
    });
    expect(result.sent).toBe(1);
    expect(senders.fcm[0].body).toBe("Approved Urdu rendering.");
    expect(senders.fcm[0].body).not.toContain("AI translation");
  });

  test("labels cached AI text", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_loop_ai"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "due-ai",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "ru",
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    await t.run(async (ctx) => {
      await ctx.db.insert("translations", {
        hadithId,
        language: "ru",
        content: "Деяния — по намерениям.",
        source: "gemini_ai",
        sourceLabel: "AI",
        status: "live",
        isDefault: true,
        groundingUsed: false,
        createdAt: 1,
        updatedAt: 1,
      });
    });
    const senders = recordingSenders();
    const result = await runDuePushes(stubIo(t), NOW, senders, {
      hasApns: true,
      hasFcm: true,
    });
    expect(result.sent).toBe(1);
    expect(senders.fcm[0].body).toContain("AI translation");
  });

  test("deletes permanently dead tokens and retries transient failures", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_loop_fail"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "dead-ios",
      platform: "ios",
      timezone: "Asia/Almaty",
      translationLocale: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "flaky-android",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "en",
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    const senders = recordingSenders();
    senders.sendApns = async () => {
      throw new Error("APNs rejected push (410): Gone");
    };
    senders.sendFcm = async () => {
      throw new Error("socket hang up");
    };
    const result = await runDuePushes(stubIo(t), NOW, senders, {
      hasApns: true,
      hasFcm: true,
    });
    expect(result.failed).toBe(2);
    expect(result.removedStale).toBe(1);
    const remaining = await t.run(async (ctx) =>
      ctx.db.query("pushTokens").collect(),
    );
    expect(remaining.map((r) => r.token)).toEqual(["flaky-android"]);
    expect(remaining[0].consecutiveFailures).toBe(1);
    expect(remaining[0].nextRetryAt).toBeGreaterThan(NOW);
  });

  test("stops the run on provider backpressure", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("notify_loop_bp"));
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "bp-1",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "en",
    });
    await asUser.mutation(api.library.savePushToken, {
      token: "bp-2",
      platform: "android",
      timezone: "Asia/Almaty",
      translationLocale: "en",
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    const senders = recordingSenders();
    senders.sendFcm = async () => {
      throw new Error("FCM rejected push (429): slow down");
    };
    const result = await runDuePushes(stubIo(t), NOW, senders, {
      hasApns: true,
      hasFcm: true,
    });
    // First send hits backpressure and halts the run; the second token
    // stays unstamped for the next tick.
    expect(result.failed).toBe(1);
    expect(result.sent).toBe(0);
    expect(senders.fcm).toHaveLength(0);
  });

  test("skips pre-N1 rows without a zone observably", async () => {
    const t = convexTest(schema, modules);
    const userId = await seedUser(t, "notify_loop_legacy");
    await t.run(async (ctx) => {
      await ctx.db.insert("pushTokens", {
        userId,
        token: "legacy-no-zone",
        platform: "android" as const,
        dailyTime: "08:00",
        deliveryBucket: "08:00",
        enabled: true,
        consecutiveFailures: 0,
        lastSeenAt: NOW,
        updatedAt: NOW,
      });
    });
    const hadithId = await seedHadith(t);
    await persistToday(t, "Asia/Almaty", hadithId);
    const result = await runDuePushes(stubIo(t), NOW, recordingSenders(), {
      hasApns: true,
      hasFcm: true,
    });
    expect(result.sent).toBe(0);
    expect(result.skippedReasons["missing-timezone"]).toBe(1);
  });
});
