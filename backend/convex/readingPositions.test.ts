/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import {
  parseReadingPosition,
  resolveReadingPosition,
  type ReadingPosition,
  type ReadingPositionTopology,
} from "./lib/readingPositions";

const modules = import.meta.glob("./**/*.ts");
const TEST_TOKEN_IDENTIFIER = "https://clerk.example|user_position_test";

function identity(subject: string) {
  return { subject, tokenIdentifier: TEST_TOKEN_IDENTIFIER };
}

function position(overrides: Partial<ReadingPosition> = {}): ReadingPosition {
  return {
    schemaVersion: 1,
    anchor: {
      provider: "sunnah_now",
      collectionSlug: "bukhari",
      providerHadithId: "50",
    },
    contentVersion: "cv1:content-a",
    volumeId: "1",
    chapterId: "10",
    pageKey: "pg1:page-a",
    displayPageIndex: 2,
    rawPageOffset: 144.5,
    normalizedOffset: 0.375,
    layoutSignature: "ls1:layout-a",
    updatedAt: 2_000,
    ...overrides,
  };
}

describe("ReadingPosition V1 contract", () => {
  test("round trips the complete wire shape", () => {
    expect(parseReadingPosition(position())).toEqual(position());
    expect(parseReadingPosition(position({
      anchor: { provider: "sunnah_now", collectionSlug: "muslim", providerHadithId: "0" },
    })).anchor.providerHadithId).toBe("0");
  });

  test("rejects invalid numeric and identity fields", () => {
    expect(() => parseReadingPosition(position({ displayPageIndex: 1.5 })))
      .toThrow("INVALID_READING_POSITION");
    expect(() => parseReadingPosition(position({ normalizedOffset: 1.01 })))
      .toThrow("INVALID_READING_POSITION");
    expect(() => parseReadingPosition(position({ rawPageOffset: -1 })))
      .toThrow("INVALID_READING_POSITION");
    expect(() => parseReadingPosition(position({
      anchor: { provider: "sunnah_now", collectionSlug: "Bad Slug", providerHadithId: "50" },
    }))).toThrow("INVALID_READING_POSITION");
  });

  test("uses raw hints only for an exact content, layout, page, and anchor match", () => {
    const topology: ReadingPositionTopology = {
      contentVersion: "cv1:content-a",
      layoutSignature: "ls1:layout-a",
      pages: [
        {
          pageKey: "pg1:page-a",
          displayPageIndex: 2,
          anchors: [
            { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "50", volumeId: "1", chapterId: "10" },
          ],
        },
      ],
    };
    expect(resolveReadingPosition(position(), topology)).toMatchObject({
      kind: "raw",
      displayPageIndex: 2,
      rawPageOffset: 144.5,
      normalizedOffset: 0.375,
    });
    expect(resolveReadingPosition(position(), { ...topology, contentVersion: "cv1:content-b" }))
      .toMatchObject({ kind: "semantic", displayPageIndex: 2, normalizedOffset: 0.375 });
    expect(resolveReadingPosition(position(), { ...topology, layoutSignature: "ls1:layout-b" }))
      .toMatchObject({ kind: "semantic", displayPageIndex: 2, normalizedOffset: 0.375 });
  });

  test("chooses the nearest provider hadith and resets offset when the anchor is missing", () => {
    const result = resolveReadingPosition(position({
      anchor: { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "50" },
      volumeId: "2",
      chapterId: undefined,
    }), {
      contentVersion: "cv1:content-b",
      layoutSignature: "ls1:layout-b",
      pages: [
        {
          pageKey: "pg1:one",
          displayPageIndex: 1,
          anchors: [
            { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "1", volumeId: "1" },
          ],
        },
        {
          pageKey: "pg1:two",
          displayPageIndex: 2,
          anchors: [
            { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "49", volumeId: "2" },
            { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "80", volumeId: "2" },
          ],
        },
      ],
    });
    expect(result).toMatchObject({
      kind: "nearest",
      anchor: { providerHadithId: "49" },
      displayPageIndex: 2,
      normalizedOffset: 0,
    });
  });
});

describe("ReadingPosition persistence and migration", () => {
  test("migrates an old row at offset zero and remains idempotent", async () => {
    const t = convexTest(schema, modules);
    const ids = await t.run(async (ctx) => {
      const userId = await ctx.db.insert("users", {
        clerkId: "legacy_position_user",
        preferredLanguage: "en",
        subscriptionTier: "free",
        aiGenerationsThisMonth: 0,
        aiGenerationLimit: 20,
        createdAt: 1,
        updatedAt: 1,
      });
      const hadithId = await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:57",
        providerHadithId: "57",
        collectionSlug: "bukhari",
        volumeId: "2",
        chapterId: "4",
        arabicText: "text",
        referenceDisplay: "Bukhari 57",
        collectionName: "Bukhari",
        authenticityAppliesTo: "none",
        authenticityConfidence: "unavailable",
        createdAt: 10,
      });
      const progressId = await ctx.db.insert("readingProgress", {
        userId,
        collectionSlug: "bukhari",
        hadithId,
        scrollOffset: 99,
        updatedAt: 500,
      });
      return { progressId };
    });

    const beforeMigration = await t.withIdentity(identity("legacy_position_user"))
      .query(api.library.listReadingProgressDetailed, {});
    expect(beforeMigration[0].position).toMatchObject({
      anchor: { providerHadithId: "57" },
      rawPageOffset: 0,
      normalizedOffset: 0,
    });

    const first = await t.mutation(internal.migrations.migrateR1ReadingProgress, {
      paginationOpts: { cursor: null, numItems: 10 },
    });
    const second = await t.mutation(internal.migrations.migrateR1ReadingProgress, {
      paginationOpts: { cursor: null, numItems: 10 },
    });
    const row = await t.run(async (ctx) => await ctx.db.get(ids.progressId));

    expect(first).toMatchObject({ migrated: 1, isDone: true });
    expect(second).toMatchObject({ migrated: 0, unchanged: 1, isDone: true });
    expect(row?.position).toMatchObject({
      schemaVersion: 1,
      anchor: { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "57" },
      volumeId: "2",
      chapterId: "4",
      rawPageOffset: 0,
      normalizedOffset: 0,
      updatedAt: 500,
    });
  });

  test("new writes are latest-wins and exact retries are no-ops", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "position_writer",
        preferredLanguage: "en",
        subscriptionTier: "free",
        aiGenerationsThisMonth: 0,
        aiGenerationLimit: 20,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:50",
        providerHadithId: "50",
        collectionSlug: "bukhari",
        volumeId: "1",
        chapterId: "10",
        arabicText: "text",
        referenceDisplay: "Bukhari 50",
        collectionName: "Bukhari",
        authenticityAppliesTo: "none",
        authenticityConfidence: "unavailable",
        createdAt: 10,
      });
    });
    const asUser = t.withIdentity(identity("position_writer"));

    await expect(asUser.mutation(api.library.saveReadingProgress, { position: position() }))
      .resolves.toMatchObject({ status: "applied" });
    await expect(asUser.mutation(api.library.saveReadingProgress, { position: position() }))
      .resolves.toMatchObject({ status: "unchanged" });
    await expect(asUser.mutation(api.library.saveReadingProgress, {
      position: position({ pageKey: "pg1:stale", updatedAt: 1_000 }),
    })).resolves.toMatchObject({ status: "unchanged" });

    const rows = await asUser.query(api.library.listReadingProgressDetailed, {});
    expect(rows).toHaveLength(1);
    expect(rows[0].position).toEqual(position());

    const replacementId = await t.run(async (ctx) => {
      const old = await ctx.db
        .query("hadiths")
        .withIndex("by_provider_ref", (q) =>
          q.eq("provider", "sunnah_now")
            .eq("collectionSlug", "bukhari")
            .eq("providerHadithId", "50"),
        )
        .unique();
      if (!old) throw new Error("Missing position fixture");
      await ctx.db.delete(old._id);
      return await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:50",
        providerHadithId: "50",
        collectionSlug: "bukhari",
        volumeId: "1",
        chapterId: "10",
        arabicText: "replacement cache row",
        referenceDisplay: "Bukhari 50",
        collectionName: "Bukhari",
        authenticityAppliesTo: "none",
        authenticityConfidence: "unavailable",
        createdAt: 20,
      });
    });
    const afterCacheReplacement = await asUser.query(
      api.library.listReadingProgressDetailed,
      {},
    );
    expect(afterCacheReplacement[0].hadith?._id).toBe(replacementId);
    expect(afterCacheReplacement[0].position).toEqual(position());
  });

  test("guest merge accepts V1 and keeps the newer position per collection", async () => {
    const t = convexTest(schema, modules);
    const hadithId = await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "position_guest",
        preferredLanguage: "en",
        subscriptionTier: "free",
        aiGenerationsThisMonth: 0,
        aiGenerationLimit: 20,
        createdAt: 1,
        updatedAt: 1,
      });
      return await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:50",
        providerHadithId: "50",
        collectionSlug: "bukhari",
        volumeId: "1",
        chapterId: "10",
        arabicText: "text",
        referenceDisplay: "Bukhari 50",
        collectionName: "Bukhari",
        authenticityAppliesTo: "none",
        authenticityConfidence: "unavailable",
        createdAt: 10,
      });
    });
    const asUser = t.withIdentity(identity("position_guest"));
    const empty = { bookmarks: [], notes: [], favorites: [] };

    await asUser.mutation(api.guestMerge.mergeGuestData, {
      ...empty,
      readingProgress: [{ position: position() }],
    });
    await asUser.mutation(api.guestMerge.mergeGuestData, {
      ...empty,
      readingProgress: [{ collectionSlug: "bukhari", hadithId, updatedAt: 1_000 }],
    });

    const rows = await asUser.query(api.library.listReadingProgressDetailed, {});
    expect(rows[0].position).toEqual(position());
  });

  test("a write whose anchor disappeared converges on the nearest provider hadith", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) => {
      await ctx.db.insert("users", {
        clerkId: "missing_anchor_writer",
        preferredLanguage: "en",
        subscriptionTier: "free",
        aiGenerationsThisMonth: 0,
        aiGenerationLimit: 20,
        createdAt: 1,
        updatedAt: 1,
      });
      for (const providerHadithId of ["49", "80"]) {
        await ctx.db.insert("hadiths", {
          provider: "sunnah_now",
          canonicalId: `sunnah_now:bukhari:${providerHadithId}`,
          providerHadithId,
          collectionSlug: "bukhari",
          volumeId: "1",
          arabicText: "text",
          referenceDisplay: `Bukhari ${providerHadithId}`,
          collectionName: "Bukhari",
          authenticityAppliesTo: "none",
          authenticityConfidence: "unavailable",
          createdAt: 10,
        });
      }
    });
    const asUser = t.withIdentity(identity("missing_anchor_writer"));
    await asUser.mutation(api.library.saveReadingProgress, { position: position() });
    const rows = await asUser.query(api.library.listReadingProgressDetailed, {});

    expect(rows[0].position).toMatchObject({
      anchor: { providerHadithId: "49" },
      contentVersion: "legacy",
      rawPageOffset: 0,
      normalizedOffset: 0,
      updatedAt: 2_000,
    });
  });
});
