/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { buildEnglishSnippet } from "./hadiths";
import {
  authenticityForProviderHadith,
  migrateLegacyAuthenticity,
} from "./lib/contentPolicy";
import type { AuthenticityClaim } from "./lib/contentPolicy";
import { chunkReaderHadiths, normalizeHadith } from "./lib/sunnahNow";

const modules = import.meta.glob("./**/*.ts");

const STALE_BUKHARI_CLAIM: AuthenticityClaim = {
  kind: "collection_scope",
  normalizedGrade: "sahih",
  claimScope: "collection",
  sourceLabel: "Documented Sahih collection",
  sourceName: "Sunnah.com",
  sourceUrl: "https://sunnah.com/bukhari/about",
  verificationMethod: "manual_collection_mapping",
};

describe("R6 round 3: Arabic narrator", () => {
  test("normalizeHadith plumbs the Arabic narrator separately from English", () => {
    const normalized = normalizeHadith("bukhari", {
      id: "57",
      language: {
        ar: { text: "نص الحديث", narrator: "رواه عمر بن الخطاب" },
        en: { text: "The hadith text.", narrator: "Narrated Umar" },
      },
    });

    expect(normalized.narrator).toBe("Narrated Umar");
    expect(normalized.narratorAr).toBe("رواه عمر بن الخطاب");
  });

  test("missing Arabic falls back to undefined narratorAr without breaking", () => {
    const normalized = normalizeHadith("bukhari", {
      id: "57",
      language: {
        en: { text: "The hadith text.", narrator: "Narrated Umar" },
      },
    });

    expect(normalized.arabicText).toBe("");
    expect(normalized.narrator).toBe("Narrated Umar");
    expect(normalized.narratorAr).toBeUndefined();
  });

  test("upsertPage stores narratorAr and old rows without it keep working", async () => {
    const t = convexTest(schema, modules);
    const items = [
      normalizeHadith("bukhari", {
        id: "1",
        language: {
          ar: { text: "نص", narrator: "الراوي" },
          en: { text: "Text.", narrator: "Narrator" },
        },
      }),
    ];

    await t.mutation(internal.hadiths.upsertPage, { items });
    const legacyId = await t.run(async (ctx) =>
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:2",
        providerHadithId: "2",
        collectionSlug: "bukhari",
        arabicText: "نص قديم",
        referenceDisplay: "Sahih al-Bukhari · Hadith 2",
        collectionName: "Sahih al-Bukhari",
        createdAt: 1_000,
      }),
    );

    const stored = await t.query(internal.hadiths.getByProviderRef, {
      provider: "sunnah_now",
      collectionSlug: "bukhari",
      providerHadithId: "1",
    });
    expect(stored?.narratorAr).toBe("الراوي");
    expect(stored?.narrator).toBe("Narrator");

    const legacy = await t.query(internal.hadiths.getById, {
      hadithId: legacyId,
    });
    expect(legacy?.narratorAr).toBeUndefined();
    expect(legacy?.arabicText).toBe("نص قديم");
  });

  test("reader chunking counts the Arabic narrator toward the page boundary", () => {
    const first = {
      arabicText: "ا".repeat(2_500),
      englishText: "e".repeat(2_500),
      narratorAr: "ر".repeat(300),
    };
    const second = { arabicText: "ا".repeat(100) };

    expect(chunkReaderHadiths([first, second], 10)).toHaveLength(2);
    expect(
      chunkReaderHadiths(
        [{ ...first, narratorAr: undefined }, second],
        10,
      ),
    ).toHaveLength(1);
  });
});

describe("R6 round 3: source truth", () => {
  test("provider English is credited to Sunnah.now, never Sunnah.com", () => {
    for (const slug of ["bukhari", "muslim"]) {
      const claim = authenticityForProviderHadith(slug);
      expect(claim.sourceName).toBe("Sunnah.now");
      expect(claim.sourceUrl).toBe("https://sunnah.now");
      expect(JSON.stringify(claim)).not.toContain("Sunnah.com");
      expect(JSON.stringify(claim)).not.toContain("sunnah.com");
    }
  });

  test("manual collection mappings stay visibly manual, never grades", () => {
    for (const slug of ["bukhari", "muslim"]) {
      const claim = authenticityForProviderHadith(slug);
      expect(claim).toMatchObject({
        kind: "collection_scope",
        normalizedGrade: "sahih",
        claimScope: "collection",
        sourceLabel: "Documented Sahih collection",
        verificationMethod: "manual_collection_mapping",
      });
      expect(claim.kind).not.toBe("hadith_grade");
      if (claim.kind === "collection_scope") {
        expect(claim.verificationMethod).not.toBe("source_provided");
      }
    }
    expect(
      migrateLegacyAuthenticity({
        collectionSlug: "bukhari",
        authenticityGrade: "sahih",
        authenticityAppliesTo: "collection",
        authenticitySource: "Collection-level mapping",
        authenticityConfidence: "manual_mapping",
      }).sourceName,
    ).toBe("Sunnah.now");
  });

  test("normalized rows carry the corrected claim end to end", () => {
    const normalized = normalizeHadith("bukhari", {
      id: "57",
      language: { en: { text: "Provider English text." } },
    });
    expect(normalized.authenticity.sourceName).toBe("Sunnah.now");
    expect(normalized.licenseRecord.sourceName).toBe("Sunnah.now");
    expect(JSON.stringify(normalized)).not.toContain("Sunnah.com");
  });

  test("stale labels are stored on rows, so the repair migration owns the fix", async () => {
    const t = convexTest(schema, modules);
    const staleId = await t.run(async (ctx) =>
      await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:57",
        providerHadithId: "57",
        collectionSlug: "bukhari",
        arabicText: "نص",
        englishText: "Provider English text.",
        referenceDisplay: "Sahih al-Bukhari · Hadith 57",
        collectionName: "Sahih al-Bukhari",
        authenticity: STALE_BUKHARI_CLAIM,
        createdAt: 1_000,
      }),
    );

    // The read path returns the stored claim verbatim: the fix cannot land
    // by changing constructors alone.
    const before = await t.query(internal.hadiths.getByProviderRef, {
      provider: "sunnah_now",
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(before?.authenticity.sourceName).toBe("Sunnah.com");

    const first = await t.mutation(internal.migrations.migrateR6SourceLabels, {
      paginationOpts: { cursor: null, numItems: 10 },
    });
    expect(first).toMatchObject({ scanned: 1, repaired: 1, unchanged: 0 });

    const after = await t.run(async (ctx) => await ctx.db.get(staleId));
    expect(after?.authenticity).toMatchObject({
      kind: "collection_scope",
      normalizedGrade: "sahih",
      claimScope: "collection",
      sourceName: "Sunnah.now",
      sourceUrl: "https://sunnah.now",
      verificationMethod: "manual_collection_mapping",
    });
    expect(JSON.stringify(after?.authenticity)).not.toContain("Sunnah.com");

    const second = await t.mutation(internal.migrations.migrateR6SourceLabels, {
      paginationOpts: { cursor: null, numItems: 10 },
    });
    expect(second).toMatchObject({ scanned: 1, repaired: 0, unchanged: 1 });
  });
});

describe("R6 round 3: English-text search", () => {
  async function seedSearchRows() {
    const t = convexTest(schema, modules);
    const longText = `${"Setup preamble sentence one. Setup preamble sentence two. Setup preamble sentence three. "}The believer is humble before the charity call${" and keeps walking in patience. ".repeat(12)}`;
    await t.run(async (ctx) => {
      const base = {
        provider: "sunnah_now",
        collectionSlug: "bukhari",
        arabicText: "نص",
        collectionName: "Sahih al-Bukhari",
        createdAt: 1_000,
      } as const;
      await ctx.db.insert("hadiths", {
        ...base,
        canonicalId: "sunnah_now:bukhari:1",
        providerHadithId: "1",
        englishText: longText,
        referenceDisplay: "Sahih al-Bukhari · Hadith 1",
      });
      // Pre-backfill row without a canonicalId stays searchable.
      await ctx.db.insert("hadiths", {
        ...base,
        providerHadithId: "2",
        englishText: "A short charity reminder.",
        referenceDisplay: "Sahih al-Bukhari · Hadith 2",
      });
      await ctx.db.insert("hadiths", {
        ...base,
        collectionSlug: "muslim",
        collectionName: "Sahih Muslim",
        canonicalId: "sunnah_now:muslim:3",
        providerHadithId: "3",
        englishText: "Another charity reminder from the collection.",
        referenceDisplay: "Sahih Muslim · Hadith 3",
      });
      for (let index = 4; index <= 30; index += 1) {
        await ctx.db.insert("hadiths", {
          ...base,
          canonicalId: `sunnah_now:bukhari:${index}`,
          providerHadithId: String(index),
          englishText: `Filler charity row ${index}.`,
          referenceDisplay: `Sahih al-Bukhari · Hadith ${index}`,
        });
      }
    });
    return t;
  }

  test("blank text returns no rows without touching the index", async () => {
    const t = await seedSearchRows();
    await expect(
      t.query(api.hadiths.searchEnglish, { text: "   " }),
    ).resolves.toEqual([]);
  });

  test("returns the contract shape with a match-centered snippet", async () => {
    const t = await seedSearchRows();
    const results = await t.query(api.hadiths.searchEnglish, {
      text: "charity",
      collectionSlug: "bukhari",
      limit: 10,
    });
    expect(results.length).toBeGreaterThan(0);
    const first = results.find((row) => row.providerHadithId === "1");
    expect(first).toMatchObject({
      canonicalId: "sunnah_now:bukhari:1",
      collectionSlug: "bukhari",
      providerHadithId: "1",
      referenceDisplay: "Sahih al-Bukhari · Hadith 1",
    });
    expect(first?.hadithId).toBeDefined();
    expect(first?.snippet).toContain("charity");
    expect(first?.snippet.length).toBeLessThanOrEqual(160 + 6);
    expect(first?.snippet.startsWith("...")).toBe(true);
    expect(first?.snippet.endsWith("...")).toBe(true);
  });

  test("derives canonicalId for pre-backfill rows", async () => {
    const t = await seedSearchRows();
    const results = await t.query(api.hadiths.searchEnglish, {
      text: "charity",
      collectionSlug: "bukhari",
      limit: 10,
    });
    const legacy = results.find((row) => row.providerHadithId === "2");
    expect(legacy?.canonicalId).toBe("sunnah_now:bukhari:2");
    expect(legacy?.snippet).toBe("A short charity reminder.");
  });

  test("clamps the limit 1..25 with a default of 10", async () => {
    const t = await seedSearchRows();
    await expect(
      t.query(api.hadiths.searchEnglish, { text: "charity" }),
    ).resolves.toHaveLength(10);
    await expect(
      t.query(api.hadiths.searchEnglish, { text: "charity", limit: 100 }),
    ).resolves.toHaveLength(25);
    await expect(
      t.query(api.hadiths.searchEnglish, { text: "charity", limit: 0 }),
    ).resolves.toHaveLength(1);
  });

  test("collection filter narrows to one collection", async () => {
    const t = await seedSearchRows();
    const results = await t.query(api.hadiths.searchEnglish, {
      text: "charity",
      collectionSlug: "muslim",
      limit: 25,
    });
    expect(results.length).toBeGreaterThan(0);
    for (const row of results) {
      expect(row.collectionSlug).toBe("muslim");
    }
  });

  test("snippet helper trims the correct end", () => {
    const text = `${"Leading charity mention. "}${"filler sentence. ".repeat(20)}`;
    const leading = buildEnglishSnippet(text, "charity");
    expect(leading.startsWith("Leading charity")).toBe(true);
    expect(leading.endsWith("...")).toBe(true);

    const short = buildEnglishSnippet("A short charity reminder.", "charity");
    expect(short).toBe("A short charity reminder.");

    const stemOnly = buildEnglishSnippet(
      `${"x".repeat(200)} tail`,
      "nomatchterm",
    );
    expect(stemOnly.endsWith("...")).toBe(true);
    expect(stemOnly.startsWith("...")).toBe(false);
  });
});
