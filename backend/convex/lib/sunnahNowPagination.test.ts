import { describe, expect, test } from "vitest";
import { aggregateVolumeOutline, chunkReaderHadiths } from "./sunnahNow";
import type { HadithRecord } from "./sunnahNow";
import {
  SUNNAH_NOW_LICENSE_RECORD,
  authenticityForProviderHadith,
} from "./contentPolicy";

type FixtureHadith = {
  id: string;
  arabicText: string;
  englishText?: string;
  narrator?: string;
};

function hadith(id: string, lengths: { arabic: number; english?: number; narrator?: number }): FixtureHadith {
  return {
    id,
    arabicText: "ا".repeat(lengths.arabic),
    englishText: lengths.english === undefined ? undefined : "e".repeat(lengths.english),
    narrator: lengths.narrator === undefined ? undefined : "n".repeat(lengths.narrator),
  };
}

describe("reader content-sized pagination", () => {
  test("is deterministic and preserves source order", () => {
    const input = [
      hadith("1", { arabic: 900, english: 800 }),
      hadith("2", { arabic: 1_600, english: 1_600 }),
      hadith("3", { arabic: 1_000, english: 1_000 }),
      hadith("4", { arabic: 20, english: 20 }),
    ];

    const first = chunkReaderHadiths(input, 10);
    const second = chunkReaderHadiths(input, 10);
    expect(first.map((page) => page.map((item) => item.id))).toEqual([
      ["1", "2"],
      ["3", "4"],
    ]);
    expect(second).toEqual(first);
    expect(first.flat()).toEqual(input);
  });

  test("keeps one very long hadith intact and caps short pages by item count", () => {
    const long = hadith("long", { arabic: 12_000, english: 12_000 });
    expect(chunkReaderHadiths([long], 10)).toEqual([[long]]);

    const short = Array.from({ length: 12 }, (_, index) => hadith(String(index + 1), { arabic: 1 }));
    expect(chunkReaderHadiths(short, 10).map((page) => page.length)).toEqual([10, 2]);
  });

  test("aggregates source-provided chapters in source order", () => {
    const items = [
      record({ id: "1", volume: "2", chapter: "c1", chapterName: "Faith" }),
      record({ id: "2", volume: "2", chapter: "c1", chapterName: "Faith" }),
      record({ id: "3", volume: "2", chapter: "c2", chapterName: "Prayer" }),
      record({ id: "4", volume: "1", chapter: "c1", chapterName: "Faith" }),
    ];
    const outline = aggregateVolumeOutline(items);
    expect(outline.map((volume) => volume.volumeId)).toEqual(["1", "2"]);
    const volume2 = outline[1];
    expect(volume2.title).toBe("Volume 2");
    expect(volume2.hadithCount).toBe(3);
    expect(volume2.firstChapterTitle).toBe("Faith");
    expect(volume2.chapters.map((chapter) => chapter.title)).toEqual([
      "Faith",
      "Prayer",
    ]);
    expect(volume2.chapters[0]).toMatchObject({
      chapterId: "c1",
      hadithCount: 2,
      firstProviderHadithId: "1",
    });
    expect(volume2.chapters[1]).toMatchObject({
      chapterId: "c2",
      hadithCount: 1,
      firstProviderHadithId: "3",
    });
  });

  test("never invents chapters and still counts unchaptered hadiths", () => {
    const items = [
      record({ id: "1", volume: "1" }),
      record({
        id: "2",
        volume: "1",
        chapterName: "Named without id",
      }),
      record({ id: "3" }),
    ];
    const outline = aggregateVolumeOutline(items);
    expect(outline).toHaveLength(1);
    expect(outline[0].hadithCount).toBe(2);
    expect(outline[0].chapters).toHaveLength(1);
    expect(outline[0].chapters[0]).toMatchObject({
      title: "Named without id",
      hadithCount: 1,
      firstProviderHadithId: "2",
    });
    expect(outline[0].chapters[0].chapterId).toBeUndefined();
  });

  test("keeps the Arabic chapter title only when it differs", () => {
    const items = [
      record({
        id: "1",
        volume: "1",
        chapter: "c1",
        chapterName: "Faith",
        arabicTitle: "كتاب الإيمان",
      }),
      record({
        id: "2",
        volume: "1",
        chapter: "c2",
        chapterName: "كتاب الصلاة",
        arabicTitle: "كتاب الصلاة",
      }),
    ];
    const outline = aggregateVolumeOutline(items);
    expect(outline[0].chapters[0].arabicTitle).toBe("كتاب الإيمان");
    expect(outline[0].chapters[1].arabicTitle).toBeUndefined();
  });

  test("starts a new page only after the content boundary is exceeded", () => {
    const exact = [
      hadith("1", { arabic: 2_600 }),
      hadith("2", { arabic: 2_600 }),
    ];
    expect(chunkReaderHadiths(exact, 10).map((page) => page.map((item) => item.id)))
      .toEqual([["1", "2"]]);

    const exceeded = [...exact, hadith("3", { arabic: 1 })];
    expect(chunkReaderHadiths(exceeded, 10).map((page) => page.map((item) => item.id)))
      .toEqual([["1", "2"], ["3"]]);
  });
});

function record(input: {
  id: string;
  volume?: string;
  chapter?: string;
  chapterName?: string;
  arabicTitle?: string;
}): HadithRecord {
  return {
    provider: "sunnah_now",
    canonicalId: `sunnah_now:bukhari:${input.id}`,
    providerHadithId: input.id,
    collectionSlug: "bukhari",
    volumeId: input.volume,
    chapterId: input.chapter,
    arabicText: "نص",
    referenceDisplay: `Sahih al-Bukhari · Hadith ${input.id}`,
    collectionName: "Sahih al-Bukhari",
    bookName: input.arabicTitle,
    chapterName: input.chapterName,
    authenticity: authenticityForProviderHadith("bukhari"),
    licenseRecord: SUNNAH_NOW_LICENSE_RECORD,
  };
}
