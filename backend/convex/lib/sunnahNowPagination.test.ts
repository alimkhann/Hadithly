import { describe, expect, test } from "vitest";
import { chunkReaderHadiths } from "./sunnahNow";

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
