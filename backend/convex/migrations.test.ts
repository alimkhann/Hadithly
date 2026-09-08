/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { internal } from "./_generated/api";
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
