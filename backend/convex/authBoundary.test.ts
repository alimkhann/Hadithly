/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { afterEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import {
  authorizeRevenueCatWebhook,
} from "./lib/revenueCat";

const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

describe("identity boundary", () => {
  test("protected user functions reject missing identity", async () => {
    const t = convexTest(schema, modules);

    await expect(t.query(api.users.getCurrentUser)).rejects.toThrow(
      "Unauthenticated",
    );
    await expect(t.mutation(api.users.deleteCurrentUser, { authorization: "unauthenticated-fixture" })).rejects.toThrow(
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

});

describe("deletion boundary", () => {
  test("removes private rows and anonymizes retained records idempotently", async () => {
    vi.useFakeTimers();
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

    await expect(authenticated.mutation(api.users.deleteCurrentUser, { authorization: (await authenticated.mutation(api.users.prepareAccountDeletion, {})).authorization })).resolves.toMatchObject({ deleted: true });
    await expect(authenticated.mutation(api.users.deleteCurrentUser, { authorization: (await authenticated.mutation(api.users.prepareAccountDeletion, {})).authorization })).resolves.toMatchObject({ deleted: false });

    await t.finishAllScheduledFunctions(vi.runAllTimers);
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

test("an erasure request cannot be undone by automatic account bootstrap", async () => {
  vi.useFakeTimers();
  try {
    const t = convexTest(schema, modules);
    const a = t.withIdentity({ subject: "deletion-retry-fixture", tokenIdentifier: "https://clerk.example|deletion-retry-fixture" });
    await a.mutation(api.users.ensureCurrentUser, {});
    const grant = await a.mutation(api.users.prepareAccountDeletion, {});
    await a.mutation(api.users.deleteCurrentUser, { authorization: grant.authorization });
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    await expect(a.mutation(api.users.ensureCurrentUser, {})).rejects.toThrow("ACCOUNT_DELETION_PENDING");
  } finally { vi.useRealTimers(); }
});


test("deletion authorization cannot start another account's erasure and retries need no recreated user", async () => {
  vi.useFakeTimers();
  const t = convexTest(schema, modules);
  const a = t.withIdentity({ subject: "delete-owner-a", tokenIdentifier: "fixture:delete-owner-a" });
  const b = t.withIdentity({ subject: "delete-owner-b", tokenIdentifier: "fixture:delete-owner-b" });
  await a.mutation(api.users.ensureCurrentUser, {});
  const bId = await b.mutation(api.users.ensureCurrentUser, {});
  const grant = await a.mutation(api.users.prepareAccountDeletion, {});
  expect(grant.subject).toBe("delete-owner-a");
  expect(await t.run(ctx => ctx.db.query("accountDeletionMarkers").collect())).toHaveLength(0);
  await expect(b.mutation(api.users.deleteCurrentUser, { authorization: grant.authorization })).rejects.toThrow("ACCOUNT_DELETION_OWNER_MISMATCH");
  expect(await t.run(ctx => ctx.db.get(bId))).not.toBeNull();
  expect(await t.run(ctx => ctx.db.query("accountDeletionMarkers").collect())).toHaveLength(0);
  expect(await a.mutation(api.users.deleteCurrentUser, { authorization: grant.authorization })).toEqual({ subject: "delete-owner-a", deleted: true });
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  const retry = await a.mutation(api.users.prepareAccountDeletion, {});
  expect(await a.mutation(api.users.deleteCurrentUser, { authorization: retry.authorization })).toEqual({ subject: "delete-owner-a", deleted: false });
  await expect(a.mutation(api.users.ensureCurrentUser, {})).rejects.toThrow("ACCOUNT_DELETION_PENDING");
  expect(await b.mutation(api.users.ensureCurrentUser, {})).toBe(bId);
  const markers = await t.run(ctx => ctx.db.query("accountDeletionMarkers").collect());
  expect(markers).toHaveLength(1);
  expect(JSON.stringify(markers)).not.toContain("delete-owner-a");
  expect(await t.run(ctx => ctx.db.query("accountDeletionAuthorizations").collect())).toHaveLength(0);
});

test("expired deletion authorization has no effects and an account never bootstrapped can be erased", async () => {
  vi.useFakeTimers();
  const t = convexTest(schema, modules);
  const a = t.withIdentity({ subject: "never-bootstrapped", tokenIdentifier: "fixture:never-bootstrapped" });
  const first = await a.mutation(api.users.prepareAccountDeletion, {});
  vi.setSystemTime(first.validUntil + 1);
  await expect(a.mutation(api.users.deleteCurrentUser, { authorization: first.authorization })).rejects.toThrow("ACCOUNT_DELETION_AUTHORIZATION_EXPIRED");
  expect(await t.run(ctx => ctx.db.query("accountDeletionMarkers").collect())).toHaveLength(0);
  const retry = await a.mutation(api.users.prepareAccountDeletion, {});
  expect(await a.mutation(api.users.deleteCurrentUser, { authorization: retry.authorization })).toEqual({ subject: "never-bootstrapped", deleted: false });
  await expect(a.mutation(api.users.ensureCurrentUser, {})).rejects.toThrow("ACCOUNT_DELETION_PENDING");
  expect(await t.run(ctx => ctx.db.query("users").collect())).toHaveLength(0);
});
