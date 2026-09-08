/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import type { WithoutSystemFields } from "convex/server";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import type { Doc } from "./_generated/dataModel";
import schema from "./schema";
import type { AuthenticityClaim } from "./lib/contentPolicy";

const modules = import.meta.glob("./**/*.ts");

describe("persisted daily selection", () => {
  test("keeps the first eligible selection for one local date and timezone", async () => {
    const t = convexTest(schema, modules);
    const [firstId, secondId] = await t.run(async (ctx) => {
      const base = {
        provider: "sunnah_now",
        collectionSlug: "bukhari",
        volumeId: "1",
        arabicText: "text",
        collectionName: "Sahih al-Bukhari",
        authenticity: {
          kind: "collection_scope",
          normalizedGrade: "sahih",
          claimScope: "collection",
          sourceLabel: "Documented Sahih collection",
          sourceName: "Sunnah.com",
          sourceUrl: "https://sunnah.com/bukhari/about",
          verificationMethod: "manual_collection_mapping",
        } satisfies AuthenticityClaim,
        createdAt: 1_000,
      } satisfies Omit<
        WithoutSystemFields<Doc<"hadiths">>,
        "canonicalId" | "providerHadithId" | "referenceDisplay"
      >;
      const firstId = await ctx.db.insert("hadiths", {
        ...base,
        canonicalId: "sunnah_now:bukhari:1",
        providerHadithId: "1",
        referenceDisplay: "Sahih al-Bukhari · Hadith 1",
      });
      const secondId = await ctx.db.insert("hadiths", {
        ...base,
        canonicalId: "sunnah_now:bukhari:2",
        providerHadithId: "2",
        referenceDisplay: "Sahih al-Bukhari · Hadith 2",
      });
      return [firstId, secondId];
    });

    await expect(
      t.mutation(internal.dailySelections.persist, {
        localDate: "2026-09-07",
        timezone: "Asia/Almaty",
        hadithId: firstId,
      }),
    ).resolves.toBe(firstId);
    await expect(
      t.mutation(internal.dailySelections.persist, {
        localDate: "2026-09-07",
        timezone: "Asia/Almaty",
        hadithId: secondId,
      }),
    ).resolves.toBe(firstId);
    await expect(
      t.mutation(internal.dailySelections.persist, {
        localDate: "2026-09-07",
        timezone: "America/Los_Angeles",
        hadithId: secondId,
      }),
    ).resolves.toBe(secondId);
  });

  test("rejects an ineligible hadith", async () => {
    const t = convexTest(schema, modules);
    const hadithId = await t.run(async (ctx) =>
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:tirmidhi:1",
        providerHadithId: "1",
        collectionSlug: "tirmidhi",
        arabicText: "text",
        referenceDisplay: "Jami` at-Tirmidhi · Hadith 1",
        collectionName: "Jami` at-Tirmidhi",
        authenticity: {
          kind: "unverified",
          claimScope: "none",
          sourceLabel: "Authenticity not verified",
          sourceName: "Sunnah.now",
          sourceUrl: "https://sunnah.now",
          verificationMethod: "unavailable",
        },
        createdAt: 1_000,
      }),
    );

    await expect(
      t.mutation(internal.dailySelections.persist, {
        localDate: "2026-09-07",
        timezone: "Asia/Almaty",
        hadithId,
      }),
    ).rejects.toThrow("not eligible for Daily Hadith");
  });

  test("serves an eligible daily hadith without authentication", async () => {
    const t = convexTest(schema, modules);
    await t.run(async (ctx) =>
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:3",
        providerHadithId: "3",
        collectionSlug: "bukhari",
        arabicText: "text",
        referenceDisplay: "Sahih al-Bukhari · Hadith 3",
        collectionName: "Sahih al-Bukhari",
        authenticity: {
          kind: "collection_scope",
          normalizedGrade: "sahih",
          claimScope: "collection",
          sourceLabel: "Documented Sahih collection",
          sourceName: "Sunnah.com",
          sourceUrl: "https://sunnah.com/bukhari/about",
          verificationMethod: "manual_collection_mapping",
        },
        createdAt: 1_000,
      }),
    );

    await expect(
      t.action(api.actions.daily.getDailyHadith, {
        timezone: "Asia/Almaty",
      }),
    ).resolves.toMatchObject({
      canonicalId: "sunnah_now:bukhari:3",
      authenticity: {
        kind: "collection_scope",
        claimScope: "collection",
      },
    });
  });
});
