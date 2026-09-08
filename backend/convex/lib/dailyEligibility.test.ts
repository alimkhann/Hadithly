import { describe, expect, test } from "vitest";
import {
  chooseDailyCandidate,
  dailyCollectionOrder,
  isDailyEligible,
  localDateInTimezone,
} from "./dailyEligibility";
import type { AuthenticityClaim } from "./contentPolicy";

const sourceGrade = (normalizedGrade: "sahih" | "hasan" | "daif"): AuthenticityClaim => ({
  kind: "hadith_grade",
  normalizedGrade,
  claimScope: "hadith",
  sourceLabel: "Source-provided grade",
  sourceName: "Test source",
  sourceUrl: "https://example.test/hadith/1",
  verificationMethod: "source_provided",
});

const collectionScope: AuthenticityClaim = {
  kind: "collection_scope",
  normalizedGrade: "sahih",
  claimScope: "collection",
  sourceLabel: "Documented Sahih collection",
  sourceName: "Test source",
  sourceUrl: "https://example.test/collection",
  verificationMethod: "manual_collection_mapping",
};

describe("daily eligibility", () => {
  test("accepts only source-provided Sahih or Hasan hadith grades", () => {
    expect(isDailyEligible(sourceGrade("sahih"))).toBe(true);
    expect(isDailyEligible(sourceGrade("hasan"))).toBe(true);
    expect(isDailyEligible(sourceGrade("daif"))).toBe(false);
  });

  test("accepts documented collection-level Sahih scope", () => {
    expect(isDailyEligible(collectionScope)).toBe(true);
    expect(
      isDailyEligible({
        kind: "unverified",
        claimScope: "none",
        sourceLabel: "Authenticity not verified",
        sourceName: "Test source",
        sourceUrl: "https://example.test",
        verificationMethod: "unavailable",
      }),
    ).toBe(false);
  });

  test("uses canonical order, not cache order", () => {
    const first = { canonicalId: "sunnah_now:bukhari:1", authenticity: collectionScope };
    const second = { canonicalId: "sunnah_now:bukhari:2", authenticity: collectionScope };
    const date = "2026-09-07";

    expect(chooseDailyCandidate([first, second], date)).toEqual(
      chooseDailyCandidate([second, first], date),
    );
  });

  test("rotates collection lookup without duplicating or dropping a collection", () => {
    const collections = ["bukhari", "muslim", "tirmidhi"];
    const ordered = dailyCollectionOrder(collections, "2026-09-07");
    expect(ordered).toHaveLength(collections.length);
    expect(new Set(ordered)).toEqual(new Set(collections));
  });
});

describe("local date and IANA timezone", () => {
  test.each([
    ["Asia/Almaty", "2026-09-06T19:30:00.000Z", "2026-09-07"],
    ["America/Los_Angeles", "2026-09-07T02:30:00.000Z", "2026-09-06"],
    ["Europe/Paris", "2026-03-29T00:30:00.000Z", "2026-03-29"],
    ["Europe/Paris", "2026-03-29T22:30:00.000Z", "2026-03-30"],
  ])("resolves %s at %s to %s", (timezone, instant, expected) => {
    expect(localDateInTimezone(Date.parse(instant), timezone)).toBe(expected);
  });

  test("rejects a non-IANA timezone", () => {
    expect(() => localDateInTimezone(0, "UTC+6")).toThrow("Invalid IANA timezone");
  });
});
