import { describe, expect, it } from "vitest";

import {
  buildCollectionDetail,
  buildApiCacheKey,
  toCollectionCard,
  toReaderHadith,
  type ApiBook,
  type ApiCollectionDetail,
  type ApiHadith,
} from "./hadith";

const book: ApiBook = {
  collection: "Sahih Muslim",
  slug: "muslim",
};

const trustedDetail: ApiCollectionDetail = {
  book,
  volumes: [
    {
      volumeId: "1",
      title: "Volume 1",
      firstChapterTitle: "The Book of Faith",
      hadithCount: 380,
      route: {
        collectionSlug: "muslim",
        volumeId: "1",
      },
    },
  ],
  chapters: [
    {
      chapterId: "1",
      title: "The Book of Faith",
      hadithCount: 380,
      route: {
        collectionSlug: "muslim",
        chapterId: "1",
      },
    },
  ],
  indexTrusted: true,
};

const pageItems: ApiHadith[] = [
  {
    id: "sunnah_now:muslim:1",
    providerHadithId: "1",
    collectionSlug: "muslim",
    chapterId: "1",
    arabicText: "arabic",
    englishText: "english",
    referenceDisplay: "Sahih Muslim · Hadith 1",
    collectionName: "Sahih Muslim",
    chapterName: "Faith",
    authenticityGrade: "sahih",
    authenticityAppliesTo: "collection",
    authenticityConfidence: "manual_mapping",
  },
  {
    id: "sunnah_now:muslim:2",
    providerHadithId: "2",
    collectionSlug: "muslim",
    chapterId: "1",
    arabicText: "arabic 2",
    englishText: "english 2",
    referenceDisplay: "Sahih Muslim · Hadith 2",
    collectionName: "Sahih Muslim",
    chapterName: "Faith",
    authenticityAppliesTo: "collection",
    authenticityConfidence: "manual_mapping",
  },
];

describe("hadith mobile view models", () => {
  it("uses provider book names without local fixture fallback", () => {
    expect(toCollectionCard(book)).toEqual({
      slug: "muslim",
      title: "Sahih Muslim",
      arabic: undefined,
      count: undefined,
      coverage: undefined,
      grade: "Sahih",
    });
  });

  it("builds collection detail volumes only from trusted provider indexes", () => {
    expect(buildCollectionDetail(trustedDetail).volumes).toEqual([
      {
        volumeId: "1",
        title: "Volume 1",
        firstChapterTitle: "The Book of Faith",
        hadithCount: 380,
        route: {
          collectionSlug: "muslim",
          volumeId: "1",
        },
      },
    ]);

    expect(
      buildCollectionDetail({
        book,
        volumes: [],
        chapters: [],
        indexTrusted: false,
      }).volumes,
    ).toEqual([]);
  });

  it("maps collection-level authenticity distinctly from hadith grades", () => {
    expect(toReaderHadith(pageItems[0]!).grade).toBe("Collection: Sahih");
  });

  it("builds stable API cache keys with params and language", () => {
    expect(
      buildApiCacheKey("/api/hadith/book/muslim/hadith", {
        page: 2,
        pageSize: 8,
        chapterId: "1",
        language: "kk",
      }),
    ).toBe("/api/hadith/book/muslim/hadith?chapterId=1&language=kk&page=2&pageSize=8");
  });
});
