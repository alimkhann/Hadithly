/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import {
  canonicalLocaleParam,
  canonicalPositionParam,
  parseCanonicalHadithPath,
  parseCanonicalLink,
} from "./lib/canonicalLinks";

const modules = import.meta.glob("./**/*.ts");

describe("canonical path parsing", () => {
  test("accepts the canonical two-segment path", () => {
    expect(parseCanonicalHadithPath("/hadith/bukhari/57")).toEqual({
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(parseCanonicalHadithPath("/hadith/muslim/4.5")).toEqual({
      collectionSlug: "muslim",
      providerHadithId: "4.5",
    });
    expect(parseCanonicalHadithPath("/hadith/nasai/1000/")).toEqual({
      collectionSlug: "nasai",
      providerHadithId: "1000",
    });
  });

  test("rejects malformed, truncated, and padded paths", () => {
    expect(parseCanonicalHadithPath("/hadith/bukhari")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/57/extra")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith//57")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith//bukhari/57")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/57//")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/Bukhari/57")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/57abc")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/.5")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/57.")).toBeNull();
    expect(parseCanonicalHadithPath("/hadith/bukhari/0")).toBeNull();
    expect(parseCanonicalHadithPath("/reader/bukhari/57")).toBeNull();
    expect(parseCanonicalHadithPath("")).toBeNull();
  });

  test("validates the full URL including host and scheme", () => {
    expect(parseCanonicalLink("https://hadithly.app/hadith/bukhari/57")).toEqual({
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(parseCanonicalLink("https://hadithly.app/hadith/bukhari/57?locale=ur&pos=v3")).toEqual({
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(parseCanonicalLink("http://hadithly.app/hadith/bukhari/57")).toBeNull();
    expect(parseCanonicalLink("https://evil.example/hadith/bukhari/57")).toBeNull();
    expect(parseCanonicalLink("https://hadithly.app.evil.example/hadith/bukhari/57")).toBeNull();
    expect(parseCanonicalLink("https://hadithly.app/privacy/")).toBeNull();
    expect(parseCanonicalLink("https://hadithly.app/hadith/bukhari/%35%37")).toBeNull();
    expect(parseCanonicalLink("https://hadithly.app/hadith/bukhari%2F57")).toBeNull();
    expect(parseCanonicalLink("not a url")).toBeNull();
  });

  test("canonicalizes the locale parameter and leaves it null-safe", () => {
    expect(canonicalLocaleParam(undefined)).toEqual({ requested: false, locale: null });
    expect(canonicalLocaleParam("")).toEqual({ requested: false, locale: null });
    expect(canonicalLocaleParam("ur")).toEqual({ requested: true, locale: "ur" });
    expect(canonicalLocaleParam("pt_BR")).toEqual({ requested: true, locale: "pt-BR" });
    expect(canonicalLocaleParam("es-419")).toEqual({ requested: true, locale: "es-419" });
    expect(canonicalLocaleParam("not a locale")).toEqual({ requested: true, locale: null });
  });

  test("validates the versioned position parameter", () => {
    expect(canonicalPositionParam("v3")).toBe(3);
    expect(canonicalPositionParam("v0")).toBe(0);
    expect(canonicalPositionParam(undefined)).toBeNull();
    expect(canonicalPositionParam("v")).toBeNull();
    expect(canonicalPositionParam("3")).toBeNull();
    expect(canonicalPositionParam("vx")).toBeNull();
    expect(canonicalPositionParam("v99999999999999")).toBeNull();
  });
});

describe("resolveCanonicalLink query", () => {
  function setup() {
    return convexTest(schema, modules);
  }

  async function seedLicensedHadith(t: ReturnType<typeof setup>) {
    const verifiedLicense = await t.run(async (ctx) =>
      await ctx.db.insert("licenseRecords", {
        sourceKey: "licensed_source",
        sourceName: "Licensed Source",
        sourceUrl: "https://licensed.example",
        terms: {
          kind: "verified",
          licenseName: "Test Display License",
          licenseUrl: "https://licensed.example/license",
          permitsDisplay: true,
          permitsRedistribution: true,
          permitsOfflineDistribution: false,
          verifiedAt: Date.now(),
        },
        createdAt: 1,
        updatedAt: 1,
      }),
    );
    const hadithId = await t.run(async (ctx) =>
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now" as const,
        canonicalId: "sunnah_now:bukhari:57",
        providerHadithId: "57",
        collectionSlug: "bukhari",
        volumeId: "1",
        arabicText: "نَحْوُ نَصٍّ عَرَبِيٍّ",
        englishText: "A provider English rendering.",
        narrator: "Umar ibn al-Khattab",
        referenceDisplay: "Bukhari · Hadith 57",
        collectionName: "Sahih al-Bukhari",
        bookName: "Book of Faith",
        authenticity: {
          kind: "collection_scope" as const,
          normalizedGrade: "sahih" as const,
          claimScope: "collection" as const,
          sourceLabel: "Documented Sahih collection",
          sourceName: "Sunnah.com",
          sourceUrl: "https://sunnah.com/bukhari/about",
          verificationMethod: "manual_collection_mapping" as const,
        },
        licenseRecordId: verifiedLicense,
        createdAt: 2,
        sourceUpdatedAt: 77,
      }),
    );
    return { hadithId };
  }

  test("resolves a licensed hadith with visible text", async () => {
    const t = setup();
    await seedLicensedHadith(t);
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(result.status).toBe("resolved");
    if (result.status !== "resolved") return;
    expect(result.canonicalId).toBe("sunnah_now:bukhari:57");
    expect(result.contentVersion).toBe(77);
    expect(result.sourceName).toBe("Licensed Source");
    expect(result.authenticity.kind).toBe("collection_scope");
    expect(result.text.visible).toBe(true);
    if (result.text.visible) {
      expect(result.text.arabicText).toBe("نَحْوُ نَصٍّ عَرَبِيٍّ");
      expect(result.text.providerEnglish).toBe("A provider English rendering.");
      expect(result.text.translation).toBeUndefined();
      expect(result.text.translationRequested).toBe(false);
    }
  });

  test("resolves the requested translation and labels RTL", async () => {
    const t = setup();
    const { hadithId } = await seedLicensedHadith(t);
    await t.run(async (ctx) => {
      await ctx.db.insert("translations", {
        hadithId,
        language: "ur",
        content: "اردو ترجمہ",
        source: "official" as const,
        sourceLabel: "Official",
        status: "live" as const,
        isDefault: true,
        groundingUsed: false,
        createdAt: 3,
        updatedAt: 3,
      });
    });
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
      locale: "ur",
    });
    expect(result.status).toBe("resolved");
    if (result.status !== "resolved" || !result.text.visible) return;
    expect(result.text.translationRequested).toBe(true);
    expect(result.text.translation).toEqual({
      language: "ur",
      content: "اردو ترجمہ",
      sourceKind: "official",
      sourceLabel: "Official",
      isRTL: true,
    });
    expect(result.text.translationFallback).toBe(false);
  });

  test("falls back from a regional locale to its base language, labeled", async () => {
    const t = setup();
    const { hadithId } = await seedLicensedHadith(t);
    await t.run(async (ctx) => {
      await ctx.db.insert("translations", {
        hadithId,
        language: "es",
        content: "Traducción al español",
        source: "community" as const,
        sourceLabel: "Community",
        status: "live" as const,
        isDefault: true,
        groundingUsed: false,
        createdAt: 3,
        updatedAt: 3,
      });
    });
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
      locale: "es-419",
    });
    if (result.status !== "resolved" || !result.text.visible) return;
    expect(result.text.translation?.language).toBe("es");
    expect(result.text.translationFallback).toBe(true);
  });

  test("an unsupported requested locale degrades to labeled provider English", async () => {
    const t = setup();
    await seedLicensedHadith(t);
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
      locale: "zz",
    });
    if (result.status !== "resolved" || !result.text.visible) return;
    expect(result.text.translation).toBeUndefined();
    expect(result.text.translationRequested).toBe(true);
    expect(result.text.translationFallback).toBe(true);
    expect(result.text.providerEnglish).toBe("A provider English rendering.");
  });

  test("an unverified license hides the text entirely", async () => {
    const t = setup();
    const license = await t.run(async (ctx) =>
      await ctx.db.insert("licenseRecords", {
        sourceKey: "sunnah_now",
        sourceName: "Sunnah.now",
        sourceUrl: "https://sunnah.now",
        terms: { kind: "unverified" as const },
        createdAt: 1,
        updatedAt: 1,
      }),
    );
    await t.run(async (ctx) => {
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now" as const,
        providerHadithId: "57",
        collectionSlug: "bukhari",
        arabicText: "نَحْوُ نَصٍّ عَرَبِيٍّ",
        referenceDisplay: "Bukhari · Hadith 57",
        collectionName: "Sahih al-Bukhari",
        licenseRecordId: license,
        createdAt: 2,
      });
    });
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(result.status).toBe("resolved");
    if (result.status !== "resolved") return;
    expect(result.text.visible).toBe(false);
    if (result.text.visible) return;
    expect("arabicText" in result.text).toBe(false);
    // The fixture row carries no authenticity claim, so the legacy
    // migration degrades it to the explicit unverified claim.
    expect(result.authenticity.kind).toBe("unverified");
  });

  test("a stale or removed hadith reports not_found with its route", async () => {
    const t = setup();
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "9999",
    });
    expect(result).toEqual({
      status: "not_found",
      route: { collectionSlug: "bukhari", providerHadithId: "9999" },
    });
  });

  test("a malformed reference reports not_found without a route", async () => {
    const t = setup();
    await seedLicensedHadith(t);
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "Bukhari",
      providerHadithId: "57",
    });
    expect(result).toEqual({ status: "not_found", route: null });
  });

  test("a malformed position parameter degrades to the hadith start", async () => {
    const t = setup();
    await seedLicensedHadith(t);
    const malformed = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
      pos: "anchor:mid",
    });
    if (malformed.status === "resolved") {
      expect(malformed.positionVersion).toBeUndefined();
    }
    const wellFormed = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
      pos: "v12",
    });
    if (wellFormed.status === "resolved") {
      expect(wellFormed.positionVersion).toBe(12);
    }
  });

  test("pending translations are not shown", async () => {
    const t = setup();
    const { hadithId } = await seedLicensedHadith(t);
    await t.run(async (ctx) => {
      await ctx.db.insert("translations", {
        hadithId,
        language: "ur",
        content: "pending draft",
        source: "gemini_ai" as const,
        sourceLabel: "AI",
        status: "pending" as const,
        isDefault: true,
        groundingUsed: false,
        createdAt: 3,
        updatedAt: 3,
      });
    });
    const result = await t.query(api.hadiths.resolveCanonicalLink, {
      collectionSlug: "bukhari",
      providerHadithId: "57",
      locale: "ur",
    });
    if (result.status !== "resolved" || !result.text.visible) return;
    expect(result.text.translation).toBeUndefined();
    expect(result.text.translationFallback).toBe(true);
  });
});
