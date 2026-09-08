import { describe, expect, it } from "vitest";

import {
  deriveSourceReferenceUrl,
  extractCitations,
  extractTranslationJson,
  parseTranslationPayload,
} from "../lib/translation-grounding";

describe("extractTranslationJson", () => {
  it("returns the object from a plain JSON string", () => {
    expect(extractTranslationJson('{"translation":"x"}')).toBe(
      '{"translation":"x"}',
    );
  });

  it("strips code fences and surrounding prose", () => {
    const raw = 'Here is the result:\n```json\n{"translation":"x"}\n```\nthanks';
    expect(extractTranslationJson(raw)).toBe('{"translation":"x"}');
  });

  it("returns null when there is no object", () => {
    expect(extractTranslationJson("no json here")).toBeNull();
    expect(extractTranslationJson("")).toBeNull();
  });
});

describe("parseTranslationPayload", () => {
  it("parses and validates a well-formed payload", () => {
    const payload = parseTranslationPayload(
      '{"translation":"Hello","confidence":0.9,"riskFlags":[],"glossaryNotes":[]}',
    );
    expect(payload?.translation).toBe("Hello");
    expect(payload?.confidence).toBe(0.9);
  });

  it("applies schema defaults for omitted arrays", () => {
    const payload = parseTranslationPayload(
      '{"translation":"Hi","confidence":0.5}',
    );
    expect(payload?.riskFlags).toEqual([]);
    expect(payload?.glossaryNotes).toEqual([]);
  });

  it("returns null for malformed or schema-invalid JSON", () => {
    expect(parseTranslationPayload("{not json}")).toBeNull();
    expect(
      parseTranslationPayload('{"confidence":0.5}'),
    ).toBeNull(); // missing required translation
  });
});

describe("extractCitations", () => {
  it("maps grounding chunks to deduped citations with domains", () => {
    const citations = extractCitations([
      { web: { uri: "https://www.sunnah.com/bukhari/1", title: "Bukhari 1" } },
      { web: { uri: "https://www.sunnah.com/bukhari/1", title: "dup" } },
      { web: { uri: "https://example.org/x" } },
      { web: { uri: "" } },
      {},
    ]);
    expect(citations).toEqual([
      {
        url: "https://www.sunnah.com/bukhari/1",
        title: "Bukhari 1",
        domain: "sunnah.com",
      },
      { url: "https://example.org/x", title: undefined, domain: "example.org" },
    ]);
  });

  it("returns an empty array when there are no chunks", () => {
    expect(extractCitations(undefined)).toEqual([]);
    expect(extractCitations([])).toEqual([]);
  });
});

describe("deriveSourceReferenceUrl", () => {
  it("builds a sunnah.com link from the provider id", () => {
    expect(
      deriveSourceReferenceUrl({
        collectionSlug: "bukhari",
        providerHadithId: "1",
      }),
    ).toBe("https://sunnah.com/bukhari:1");
  });

  it("falls back to the reference display number", () => {
    expect(
      deriveSourceReferenceUrl({
        collectionSlug: "muslim",
        referenceDisplay: "Book 1, Hadith 47",
      }),
    ).toBe("https://sunnah.com/muslim:47");
  });

  it("returns undefined without a slug or number", () => {
    expect(deriveSourceReferenceUrl({ providerHadithId: "1" })).toBeUndefined();
    expect(
      deriveSourceReferenceUrl({ collectionSlug: "bukhari" }),
    ).toBeUndefined();
  });
});
