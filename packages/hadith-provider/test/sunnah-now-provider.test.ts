import { describe, expect, it, vi } from "vitest";

import { SunnahNowProvider, createInternalHadithId } from "../src/index";

const booksResponse = [
  { collection: "Sahih al-Bukhari", slug: "bukhari" },
  { collection: "Sahih Muslim", slug: "muslim" },
];

const hadithResponse = [
  {
    id: 1,
    metadata: {
      volume: { id: 1 },
      chapter: {
        id: 1,
        language: {
          en: { text: "How the Divine Revelation started" },
          ar: { text: "باب بدء الوحي" },
        },
      },
    },
    language: {
      ar: { text: "حَدَّثَنَا الْحُمَيْدِيُّ..." },
      en: {
        narrator: "Narrated 'Umar bin Al-Khattab:",
        text: "I heard Allah's Messenger saying...",
      },
    },
  },
];

function jsonResponse(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  });
}

describe("createInternalHadithId", () => {
  it("includes provider, collection slug, and provider hadith id", () => {
    expect(createInternalHadithId("sunnah_now", "bukhari", "1")).toBe(
      "sunnah_now:bukhari:1",
    );
    expect(createInternalHadithId("sunnah_now", "muslim", "1")).toBe(
      "sunnah_now:muslim:1",
    );
  });
});

describe("SunnahNowProvider", () => {
  it("lists books using X-API-Key without leaking credentials into query params", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(booksResponse));
    const provider = new SunnahNowProvider({
      apiKey: "test-key",
      fetch: fetchMock,
    });

    await expect(provider.listBooks()).resolves.toEqual([
      { collection: "Sahih al-Bukhari", slug: "bukhari" },
      { collection: "Sahih Muslim", slug: "muslim" },
    ]);

    const [url, init] = fetchMock.mock.calls[0]!;
    expect(String(url)).toBe("https://api.sunnah.now/api/early-access/books");
    expect(String(url)).not.toContain("test-key");
    expect(new Headers(init?.headers).get("X-API-Key")).toBe("test-key");
  });

  it("normalizes paginated hadiths into stable internal records", async () => {
    const fetchMock = vi.fn().mockResolvedValue(jsonResponse(hadithResponse));
    const provider = new SunnahNowProvider({
      apiKey: "test-key",
      fetch: fetchMock,
    });

    const result = await provider.listHadiths({
      collectionSlug: "bukhari",
      page: 2,
      pageSize: 1,
    });

    expect(result.items).toHaveLength(1);
    expect(result.items[0]).toMatchObject({
      id: "sunnah_now:bukhari:1",
      provider: "sunnah_now",
      providerHadithId: "1",
      collectionSlug: "bukhari",
      volumeId: "1",
      chapterId: "1",
      arabicText: "حَدَّثَنَا الْحُمَيْدِيُّ...",
      englishText: "I heard Allah's Messenger saying...",
      narrator: "Narrated 'Umar bin Al-Khattab:",
      chapterName: "How the Divine Revelation started",
      referenceDisplay: "Sahih al-Bukhari · Hadith 1",
    });
    expect(result.page).toBe(2);
    expect(result.pageSize).toBe(1);
    expect(result.hasMore).toBe(true);
    expect(result.sourceRoute).toBe("/api/early-access/book/bukhari/hadith");
  });

  it("refuses direct single-hadith reads because Sunnah.now currently returns slug-unsafe results", async () => {
    const fetchMock = vi
      .fn()
      .mockResolvedValue(jsonResponse(hadithResponse[0]));
    const provider = new SunnahNowProvider({
      apiKey: "test-key",
      fetch: fetchMock,
    });

    await expect(provider.getHadith("bukhari", "1")).rejects.toThrow(
      "Direct Sunnah.now hadith reads are disabled",
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("searches only injected cached records for MVP", async () => {
    const provider = new SunnahNowProvider({
      apiKey: "test-key",
      fetch: vi.fn(),
      cachedSearch: async () => [
        {
          id: "sunnah_now:bukhari:1",
          provider: "sunnah_now",
          providerHadithId: "1",
          collectionSlug: "bukhari",
          arabicText: "arabic",
          englishText: "intentions",
          referenceDisplay: "Sahih al-Bukhari · Hadith 1",
          collectionName: "Sahih al-Bukhari",
          authenticityAppliesTo: "collection",
          authenticityConfidence: "manual_mapping",
        },
      ],
    });

    await expect(
      provider.search({ query: "intentions", language: "en" }),
    ).resolves.toHaveLength(1);
  });
});
