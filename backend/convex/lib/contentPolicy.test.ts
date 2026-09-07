import { describe, expect, test } from "vitest";
import {
  SUNNAH_NOW_LICENSE_RECORD,
  authenticityForProviderHadith,
  canonicalHadithIdentity,
  migrateLegacyAuthenticity,
} from "./contentPolicy";
import { normalizeHadith, parseSunnahNowHadiths } from "./sunnahNow";

describe("canonical content contract", () => {
  test("builds one stable identity from provider-owned fields", () => {
    expect(
      canonicalHadithIdentity({
        provider: "sunnah_now",
        collectionSlug: "bukhari",
        providerHadithId: "7",
      }),
    ).toEqual({
      provider: "sunnah_now",
      collectionSlug: "bukhari",
      providerHadithId: "7",
      canonicalId: "sunnah_now:bukhari:7",
    });
  });

  test("records provider licensing as unverified without inventing permission", () => {
    expect(SUNNAH_NOW_LICENSE_RECORD).toMatchObject({
      sourceKey: "sunnah_now",
      sourceName: "Sunnah.now",
      terms: { kind: "unverified" },
    });
  });

  test.each(["bukhari", "muslim"])(
    "maps %s to a documented manual collection claim",
    (collectionSlug) => {
      expect(authenticityForProviderHadith(collectionSlug)).toMatchObject({
        kind: "collection_scope",
        normalizedGrade: "sahih",
        claimScope: "collection",
        verificationMethod: "manual_collection_mapping",
        sourceName: "Sunnah.com",
      });
    },
  );

  test("does not infer a grade from provider text", () => {
    const normalized = normalizeHadith("tirmidhi", {
      id: "12",
      language: {
        ar: { text: "صحيح" },
        en: { text: "Grade: Sahih. Provider-controlled prose." },
      },
    });

    expect(normalized.authenticity).toMatchObject({
      kind: "unverified",
      claimScope: "none",
      verificationMethod: "unavailable",
    });
    expect(normalized.authenticity).not.toHaveProperty("normalizedGrade");
  });

  test("rejects malformed provider records before normalization", () => {
    expect(() =>
      parseSunnahNowHadiths([
        { id: null, language: { en: { text: "provider text" } } },
      ]),
    ).toThrow("invalid hadith id");
    expect(() => parseSunnahNowHadiths({ id: "1" })).toThrow(
      "invalid hadith data",
    );
  });
});

describe("F1 authenticity migration", () => {
  test.each(["bukhari", "muslim"])(
    "migrates the existing %s mapping as collection scope, not a hadith grade",
    (collectionSlug) => {
      const migrated = migrateLegacyAuthenticity({
        collectionSlug,
        authenticityGrade: "sahih",
        authenticityAppliesTo: "collection",
        authenticitySource: "Collection-level mapping",
        authenticityConfidence: "manual_mapping",
      });

      expect(migrated).toMatchObject({
        kind: "collection_scope",
        normalizedGrade: "sahih",
        claimScope: "collection",
        verificationMethod: "manual_collection_mapping",
      });
      expect(migrated.kind).not.toBe("hadith_grade");
    },
  );

  test("does not bless an unknown manual mapping", () => {
    expect(
      migrateLegacyAuthenticity({
        collectionSlug: "tirmidhi",
        authenticityGrade: "sahih",
        authenticityAppliesTo: "collection",
        authenticitySource: "Collection-level mapping",
        authenticityConfidence: "manual_mapping",
      }),
    ).toEqual({
      kind: "unverified",
      claimScope: "none",
      sourceLabel: "Authenticity not verified",
      sourceName: "Sunnah.now",
      sourceUrl: "https://sunnah.now",
      verificationMethod: "unavailable",
    });
  });

  test("does not bless a Bukhari row that is not the exact legacy mapping", () => {
    const migrated = migrateLegacyAuthenticity({
      collectionSlug: "bukhari",
      authenticityGrade: "sahih",
      authenticityAppliesTo: "collection",
      authenticitySource: "provider prose",
      authenticityConfidence: "manual_mapping",
    });

    expect(migrated.kind).toBe("unverified");
    expect(migrated).not.toHaveProperty("normalizedGrade");
  });

  test("does not preserve an untraceable legacy source-provided grade", () => {
    const migrated = migrateLegacyAuthenticity({
      collectionSlug: "tirmidhi",
      authenticityGrade: "hasan",
      authenticityAppliesTo: "hadith",
      authenticitySource: "Provider",
      authenticityConfidence: "source_provided",
    });

    expect(migrated.kind).toBe("unverified");
    expect(migrated).not.toHaveProperty("normalizedGrade");
  });
});
