/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import {
  authorizeRevenueCatWebhook,
  parseRevenueCatEvent,
} from "./lib/revenueCat";

const modules = import.meta.glob("./**/*.ts");

describe("identity boundary", () => {
  test("protected user functions reject missing identity", async () => {
    const t = convexTest(schema, modules);

    await expect(t.query(api.users.getCurrentUser)).rejects.toThrow(
      "Unauthenticated",
    );
    await expect(t.mutation(api.users.deleteCurrentUser)).rejects.toThrow(
      "Unauthenticated",
    );
    await expect(t.query(api.library.listBookmarks)).rejects.toThrow(
      "Unauthenticated",
    );
  });
});

describe("RevenueCat boundary", () => {
  test("accepts only exact raw or Bearer webhook secrets", () => {
    expect(
      authorizeRevenueCatWebhook({ expected: undefined, provided: null }),
    ).toEqual({ kind: "misconfigured" });
    expect(
      authorizeRevenueCatWebhook({ expected: "secret", provided: null }),
    ).toEqual({ kind: "unauthorized" });
    expect(
      authorizeRevenueCatWebhook({ expected: "secret", provided: "wrong" }),
    ).toEqual({ kind: "unauthorized" });
    expect(
      authorizeRevenueCatWebhook({ expected: "secret", provided: "secret" }),
    ).toEqual({ kind: "authorized" });
    expect(
      authorizeRevenueCatWebhook({
        expected: "secret",
        provided: "Bearer secret",
      }),
    ).toEqual({ kind: "authorized" });
  });

  test("retains access until RevenueCat sends expiration", () => {
    const future = 2_000;
    expect(
      parseRevenueCatEvent({
        now: 1_000,
        body: {
          event: {
            app_user_id: "user_1",
            entitlement_ids: ["pro"],
            type: "CANCELLATION",
            expiration_at_ms: future,
          },
        },
      }),
    ).toMatchObject({
      kind: "valid",
      event: { subscriptionTier: "pro" },
    });
    expect(
      parseRevenueCatEvent({
        now: future,
        body: {
          app_user_id: "user_1",
          entitlement_id: "pro",
          type: "BILLING_ISSUE",
          expiration_at_ms: future,
        },
      }),
    ).toMatchObject({
      kind: "valid",
      event: { subscriptionTier: "pro" },
    });
    expect(
      parseRevenueCatEvent({
        now: 1_000,
        body: {
          event: {
            app_user_id: "user_1",
            entitlement_ids: ["pro"],
            type: "EXPIRATION",
            expiration_at_ms: 2_000,
          },
        },
      }),
    ).toMatchObject({
      kind: "valid",
      event: { subscriptionTier: "free" },
    });
  });

  test("does not let delayed webhooks overwrite newer entitlement state", async () => {
    const t = convexTest(schema, modules);
    const clerkId = "user_subscriber";
    const userId = await t.run(async (ctx) =>
      await ctx.db.insert("users", {
        clerkId,
        preferredLanguage: "en",
        subscriptionTier: "free",
        aiGenerationsThisMonth: 0,
        aiGenerationLimit: 20,
        createdAt: 1_000,
        updatedAt: 1_000,
      }),
    );

    await expect(
      t.mutation(internal.users.syncRevenueCatEntitlement, {
        clerkId,
        revenueCatAppUserId: clerkId,
        subscriptionTier: "pro",
        eventTimestampMs: 2_000,
      }),
    ).resolves.toEqual({ kind: "updated", userId });
    await expect(
      t.mutation(internal.users.syncRevenueCatEntitlement, {
        clerkId,
        revenueCatAppUserId: clerkId,
        subscriptionTier: "free",
        eventTimestampMs: 1_000,
      }),
    ).resolves.toEqual({ kind: "ignored_stale_event" });

    await expect(t.run(async (ctx) => await ctx.db.get(userId))).resolves.toMatchObject({
      subscriptionTier: "pro",
      revenueCatEventTimestamp: 2_000,
    });
  });

  test("a delayed webhook cannot create a deleted or unknown user", async () => {
    const t = convexTest(schema, modules);

    const result = await t.mutation(
      internal.users.syncRevenueCatEntitlement,
      {
        clerkId: "user_deleted",
        revenueCatAppUserId: "user_deleted",
        eventTimestampMs: 1_000,
        subscriptionTier: "pro",
      },
    );

    expect(result).toEqual({ kind: "ignored_unknown_user" });
    expect(await t.run(async (ctx) => await ctx.db.query("users").collect())).toEqual(
      [],
    );
  });
});

describe("deletion boundary", () => {
  test("removes private rows and anonymizes retained records idempotently", async () => {
    const t = convexTest(schema, modules);
    const clerkId = "user_delete_me";
    const seeded = await t.run(async (ctx) => {
      const now = 1_000;
      const userId = await ctx.db.insert("users", {
        clerkId,
        preferredLanguage: "en",
        subscriptionTier: "free",
        aiGenerationsThisMonth: 0,
        aiGenerationLimit: 20,
        createdAt: now,
        updatedAt: now,
      });
      const hadithId = await ctx.db.insert("hadiths", {
        provider: "local_dump",
        providerHadithId: "1",
        collectionSlug: "test",
        arabicText: "text",
        referenceDisplay: "1",
        collectionName: "Test",
        authenticityAppliesTo: "none",
        authenticityConfidence: "unavailable",
        createdAt: now,
      });
      await ctx.db.insert("bookmarks", { userId, hadithId, createdAt: now });
      await ctx.db.insert("favorites", { userId, hadithId, createdAt: now });
      await ctx.db.insert("notes", {
        userId,
        hadithId,
        content: "private",
        createdAt: now,
        updatedAt: now,
      });
      await ctx.db.insert("readingProgress", {
        userId,
        collectionSlug: "test",
        hadithId,
        updatedAt: now,
      });
      await ctx.db.insert("pushTokens", {
        userId,
        token: "token",
        platform: "ios",
        enabled: true,
        updatedAt: now,
      });
      await ctx.db.insert("communitySubmissions", {
        hadithId,
        language: "en",
        submittedBy: userId,
        proposedContent: "proposal",
        aiReview: {
          model: "test",
          score: 1,
          riskFlags: [],
          recommendation: "approve",
        },
        status: "pending",
        createdAt: now,
      });
      const contributedTranslationId = await ctx.db.insert("translations", {
        hadithId,
        language: "en",
        content: "contributed",
        source: "community",
        sourceLabel: "Community",
        contributorUserId: userId,
        status: "live",
        isDefault: false,
        groundingUsed: false,
        createdAt: now,
        updatedAt: now,
      });
      const generatedTranslationId = await ctx.db.insert("translations", {
        hadithId,
        language: "fr",
        content: "generated",
        source: "gemini_ai",
        sourceLabel: "AI",
        generatedByUserId: userId,
        status: "live",
        isDefault: false,
        groundingUsed: false,
        createdAt: now,
        updatedAt: now,
      });
      await ctx.db.insert("translationReports", {
        translationId: generatedTranslationId,
        reporterUserId: userId,
        reason: "test",
        status: "open",
        createdAt: now,
      });
      const auditId = await ctx.db.insert("adminAuditLog", {
        actorUserId: userId,
        action: "test",
        targetType: "translation",
        targetId: generatedTranslationId,
        createdAt: now,
      });
      return {
        contributedTranslationId,
        generatedTranslationId,
        auditId,
      };
    });
    const authenticated = t.withIdentity({ subject: clerkId });

    await expect(authenticated.mutation(api.users.deleteCurrentUser)).resolves.toBe(
      true,
    );
    await expect(authenticated.mutation(api.users.deleteCurrentUser)).resolves.toBe(
      false,
    );

    const state = await t.run(async (ctx) => ({
      users: await ctx.db.query("users").collect(),
      bookmarks: await ctx.db.query("bookmarks").collect(),
      favorites: await ctx.db.query("favorites").collect(),
      notes: await ctx.db.query("notes").collect(),
      readingProgress: await ctx.db.query("readingProgress").collect(),
      pushTokens: await ctx.db.query("pushTokens").collect(),
      submissions: await ctx.db.query("communitySubmissions").collect(),
      reports: await ctx.db.query("translationReports").collect(),
      contributed: await ctx.db.get(seeded.contributedTranslationId),
      generated: await ctx.db.get(seeded.generatedTranslationId),
      audit: await ctx.db.get(seeded.auditId),
    }));

    expect(state.users).toHaveLength(0);
    expect(state.bookmarks).toHaveLength(0);
    expect(state.favorites).toHaveLength(0);
    expect(state.notes).toHaveLength(0);
    expect(state.readingProgress).toHaveLength(0);
    expect(state.pushTokens).toHaveLength(0);
    expect(state.submissions).toHaveLength(0);
    expect(state.reports).toHaveLength(0);
    expect(state.contributed).toBeNull();
    expect(state.generated?.generatedByUserId).toBeUndefined();
    expect(state.audit?.actorUserId).toBeUndefined();
  });
});
