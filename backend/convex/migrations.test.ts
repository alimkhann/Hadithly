/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

describe("F1 storage migration fixtures", () => {
  test("migrates only known manual collection claims and is idempotent", async () => {
    const t = convexTest(schema, modules);
    const [bukhariId, unknownId] = await t.run(async (ctx) => {
      const bukhariId = await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        providerHadithId: "1",
        collectionSlug: "bukhari",
        arabicText: "text",
        referenceDisplay: "Sahih al-Bukhari · Hadith 1",
        collectionName: "Sahih al-Bukhari",
        authenticityGrade: "sahih",
        authenticityAppliesTo: "collection",
        authenticitySource: "Collection-level mapping",
        authenticityConfidence: "manual_mapping",
        createdAt: 1_000,
      });
      const unknownId = await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        providerHadithId: "2",
        collectionSlug: "tirmidhi",
        arabicText: "Grade: Sahih",
        referenceDisplay: "Jami` at-Tirmidhi · Hadith 2",
        collectionName: "Jami` at-Tirmidhi",
        authenticityGrade: "sahih",
        authenticityAppliesTo: "collection",
        authenticitySource: "Collection-level mapping",
        authenticityConfidence: "manual_mapping",
        createdAt: 1_000,
      });
      return [bukhariId, unknownId];
    });

    const first = await t.mutation(internal.migrations.migrateF1Hadiths, {
      paginationOpts: { cursor: null, numItems: 10 },
    });
    expect(first).toMatchObject({ migrated: 2, isDone: true });
    const initialLicense = await t.run(async (ctx) =>
      await ctx.db.query("licenseRecords").unique(),
    );
    expect(initialLicense?.terms).toEqual({ kind: "unverified" });
    await t.run(async (ctx) => {
      if (!initialLicense) throw new Error("Missing license fixture");
      await ctx.db.patch(initialLicense._id, {
        terms: {
          kind: "verified",
          licenseName: "Fixture license",
          licenseUrl: "https://example.test/license",
          permitsDisplay: true,
          permitsRedistribution: false,
          permitsOfflineDistribution: false,
          verifiedAt: 2_000,
        },
      });
    });
    await t.mutation(internal.migrations.migrateF1Hadiths, {
      paginationOpts: { cursor: null, numItems: 10 },
    });

    const [bukhari, unknown, licenses] = await t.run(async (ctx) =>
      await Promise.all([
        ctx.db.get(bukhariId),
        ctx.db.get(unknownId),
        ctx.db.query("licenseRecords").collect(),
      ]),
    );
    expect(bukhari).toMatchObject({
      canonicalId: "sunnah_now:bukhari:1",
      authenticity: {
        kind: "collection_scope",
        normalizedGrade: "sahih",
        claimScope: "collection",
        verificationMethod: "manual_collection_mapping",
      },
    });
    expect(bukhari).not.toHaveProperty("authenticityGrade");
    expect(unknown?.authenticity).toMatchObject({
      kind: "unverified",
      claimScope: "none",
      verificationMethod: "unavailable",
    });
    expect(unknown?.authenticity).not.toHaveProperty("normalizedGrade");
    expect(licenses).toHaveLength(1);
    expect(licenses[0]).toMatchObject({
      sourceKey: "sunnah_now",
      terms: { kind: "verified", licenseName: "Fixture license" },
    });
  });
});

describe("H3 Saved dual-read migration fixtures", () => {
  test("unifies all legacy facets without deleting their exact target", async () => {
    const t = convexTest(schema, modules);
    const { userId, hadithId } = await t.run(async (ctx) => {
      const userId = await ctx.db.insert("users", { clerkId: "h3-user", preferredLanguage: "en", subscriptionTier: "free", aiGenerationsThisMonth: 0, aiGenerationLimit: 5, createdAt: 1, updatedAt: 1 });
      const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", providerHadithId: "57", collectionSlug: "bukhari", arabicText: "text", referenceDisplay: "Bukhari 57", collectionName: "Bukhari", createdAt: 1 });
      await ctx.db.insert("bookmarks", { userId, hadithId, createdAt: 10 });
      await ctx.db.insert("favorites", { userId, hadithId, createdAt: 11 });
      await ctx.db.insert("notes", { userId, hadithId, content: "private", createdAt: 12, updatedAt: 13 });
      return { userId, hadithId };
    });
    const sources: Array<"bookmarks" | "favorites" | "notes"> = ["bookmarks", "favorites", "notes"];
    for (const source of sources) {
      await t.mutation(internal.migrations.migrateH3SavedItems, { source, paginationOpts: { cursor: null, numItems: 10 } });
      await t.mutation(internal.migrations.migrateH3SavedItems, { source, paginationOpts: { cursor: null, numItems: 10 } });
    }
    const state = await t.run(async (ctx) => ({
      items: await ctx.db.query("savedItems").withIndex("by_user_hadith", (q) => q.eq("userId", userId).eq("hadithId", hadithId)).collect(),
      bookmarks: await ctx.db.query("bookmarks").withIndex("by_user", (q) => q.eq("userId", userId)).collect(),
      favorites: await ctx.db.query("favorites").withIndex("by_user", (q) => q.eq("userId", userId)).collect(),
      notes: await ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", userId).eq("hadithId", hadithId)).collect(),
    }));
    expect(state.items).toHaveLength(1);
    expect(state.items[0]).toMatchObject({ hadithId, bookmarkCreatedAt: 10, favoriteCreatedAt: 11, noteContent: "private", noteCreatedAt: 12, noteUpdatedAt: 13 });
    expect(state.bookmarks).toHaveLength(1);
    expect(state.favorites).toHaveLength(1);
    expect(state.notes).toHaveLength(1);
  });

  test("paginates, dual-reads for rollback, restores folders, and transfers fewer Saved bytes", async () => {
    const t = convexTest(schema, modules);
    const { userId, hadithIds } = await t.run(async (ctx) => {
      const userId = await ctx.db.insert("users", { clerkId: "h3-paged", preferredLanguage: "en", subscriptionTier: "free", aiGenerationsThisMonth: 0, aiGenerationLimit: 5, createdAt: 1, updatedAt: 1 });
      const hadithIds = await Promise.all(["71", "72", "73"].map(async (providerHadithId) =>
        await ctx.db.insert("hadiths", { provider: "sunnah_now", providerHadithId, collectionSlug: "bukhari", arabicText: "text", referenceDisplay: `Bukhari ${providerHadithId}`, collectionName: "Bukhari", createdAt: 1 }),
      ));
      await ctx.db.insert("bookmarks", { userId, hadithId: hadithIds[0], createdAt: 10 });
      await ctx.db.insert("favorites", { userId, hadithId: hadithIds[0], createdAt: 11 });
      await ctx.db.insert("notes", { userId, hadithId: hadithIds[0], content: "newest", createdAt: 12, updatedAt: 13 });
      await ctx.db.insert("bookmarks", { userId, hadithId: hadithIds[1], createdAt: 14 });
      await ctx.db.insert("favorites", { userId, hadithId: hadithIds[2], createdAt: 15 });
      return { userId, hadithIds };
    });
    for (const source of ["bookmarks", "favorites", "notes"] as const) {
      let cursor: string | null = null;
      do {
        const page: { continueCursor: string | null; isDone: boolean } = await t.mutation(internal.migrations.migrateH3SavedItems, { source, paginationOpts: { cursor, numItems: 1 } });
        cursor = page.continueCursor;
        if (page.isDone) break;
      } while (cursor !== null);
    }
    const asUser = t.withIdentity({ subject: "h3-paged", tokenIdentifier: "https://clerk.example|h3" });
    const snapshot = await asUser.query(api.library.listSavedSnapshot, {});
    expect(snapshot.items).toHaveLength(3);
    expect(snapshot.items.filter((item) => item.hadithId === hadithIds[0])).toHaveLength(1);
    expect(snapshot.items.find((item) => item.hadithId === hadithIds[0])).toMatchObject({ bookmarkCreatedAt: 10, favoriteCreatedAt: 11, noteContent: "newest" });
    // The legacy projection remains readable for a rollback client.
    expect(await asUser.query(api.library.listBookmarksDetailed, {})).toHaveLength(2);

    const folderId = await asUser.mutation(api.library.createSavedFolder, { name: "  Read later  " });
    await asUser.mutation(api.library.assignSavedFolder, { hadithId: hadithIds[0], folderId });
    const deletion = await asUser.mutation(api.library.deleteSavedFolder, { folderId });
    expect((await asUser.query(api.library.listSavedSnapshot, {})).items.find((item) => item.hadithId === hadithIds[0])?.folderId).toBeUndefined();
    if (!deletion) throw new Error("Expected folder deletion receipt");
    await asUser.mutation(api.library.restoreSavedFolder, deletion);
    expect((await asUser.query(api.library.listSavedSnapshot, {})).items.find((item) => item.hadithId === hadithIds[0])?.folderId).toBeDefined();
    await expect(asUser.mutation(api.library.createSavedFolder, { name: "\n" })).rejects.toThrow("FOLDER_NAME_EMPTY");
    await expect(asUser.mutation(api.library.createSavedFolder, { name: "a".repeat(65) })).rejects.toThrow("FOLDER_NAME_TOO_LONG");

    const [bookmarks, favorites, notes] = await Promise.all([
      asUser.query(api.library.listBookmarksDetailed, {}),
      asUser.query(api.library.listFavoritesDetailed, {}),
      asUser.query(api.library.listNotesDetailed, {}),
    ]);
    const legacyBytes = Buffer.byteLength(JSON.stringify(bookmarks), "utf8") + Buffer.byteLength(JSON.stringify(favorites), "utf8") + Buffer.byteLength(JSON.stringify(notes), "utf8");
    const snapshotBytes = Buffer.byteLength(JSON.stringify(snapshot), "utf8");
    expect(snapshotBytes).toBeLessThan(legacyBytes);
    expect(JSON.stringify(snapshot)).not.toContain("readingProgress");
    expect(await t.run(async (ctx) => ctx.db.get(userId))).not.toBeNull();
  });
});
