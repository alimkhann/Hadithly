import { useEffect, useMemo, useState } from "react";

import { apiFetch } from "./api";
import { DEFAULT_READER_PAGE_SIZE } from "./reader-state";

export type ApiBook = {
  collection: string;
  slug: string;
  arabicName?: string;
  hadithCount?: number;
  authenticityGrade?: string;
};

export type ApiCollectionChapter = {
  chapterId: string;
  title: string;
  arabicTitle?: string;
  hadithCount?: number;
  route: {
    collectionSlug: string;
    volumeId?: string;
    chapterId: string;
  };
};

export type ApiCollectionVolume = {
  volumeId: string;
  title: string;
  arabicTitle?: string;
  firstChapterTitle?: string;
  firstChapterArabicTitle?: string;
  hadithCount?: number;
  route: {
    collectionSlug: string;
    volumeId: string;
  };
};

export type ApiCollectionDetail = {
  book: ApiBook;
  volumes: ApiCollectionVolume[];
  chapters: ApiCollectionChapter[];
  indexTrusted: boolean;
  source?: string;
  indexedAt?: number;
};

export type ApiHadith = {
  id: string;
  providerHadithId: string;
  collectionSlug: string;
  volumeId?: string;
  chapterId?: string;
  arabicText: string;
  englishText?: string;
  narrator?: string;
  referenceDisplay: string;
  collectionName: string;
  chapterName?: string;
  authenticityGrade?: string;
  authenticityAppliesTo: "hadith" | "collection" | "none";
  authenticitySource?: string;
  authenticityConfidence: string;
};

export type ApiPage<T> = {
  items: T[];
  page: number;
  pageSize: number;
  hasMore: boolean;
  sourceRoute?: string;
};

export type TranslationCitation = {
  url: string;
  title?: string;
  domain?: string;
};

export type ApiTranslationResponse = {
  translation: string;
  confidence: number;
  riskFlags: string[];
  glossaryNotes: string[];
  source: "official" | "gemini_ai" | "community";
  sourceLabel: "Official" | "Gemini AI" | "Community";
  cached: boolean;
  aiModel?: string;
  ratingPercent?: number;
  groundingUsed?: boolean;
  citations?: TranslationCitation[];
  sourceReferenceUrl?: string;
};

export function useBooks() {
  const [books, setBooks] = useState<ApiBook[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    setIsLoading(true);
    cachedApiFetch<ApiBook[]>("/api/hadith/books")
      .then((nextBooks) => {
        if (active) setBooks(nextBooks);
      })
      .catch((nextError) => {
        if (active)
          setError(
            nextError instanceof Error
              ? nextError
              : new Error("Failed to load books"),
          );
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, []);

  return { books, isLoading, error };
}

export function useBook(collectionSlug: string) {
  const [book, setBook] = useState<ApiBook | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    setIsLoading(true);
    setError(null);
    cachedApiFetch<ApiBook>(`/api/hadith/book/${collectionSlug}`)
      .then((nextBook) => {
        if (active) setBook(nextBook);
      })
      .catch((nextError) => {
        if (active)
          setError(
            nextError instanceof Error
              ? nextError
              : new Error("Failed to load collection"),
          );
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, [collectionSlug]);

  return { book, isLoading, error };
}

export function useCollectionDetail(collectionSlug: string) {
  const [detail, setDetail] = useState<ApiCollectionDetail | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    setIsLoading(true);
    setError(null);
    cachedApiFetch<ApiCollectionDetail>(
      `/api/hadith/book/${collectionSlug}/index`,
    )
      .then((nextDetail) => {
        if (active) setDetail(nextDetail);
      })
      .catch((nextError) => {
        if (active)
          setError(
            nextError instanceof Error
              ? nextError
              : new Error("Failed to load collection index"),
          );
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, [collectionSlug]);

  return { detail, isLoading, error };
}

export function useHadithPage({
  collectionSlug,
  page = 1,
  pageSize = DEFAULT_READER_PAGE_SIZE,
  volumeId,
  chapterId,
}: {
  collectionSlug: string;
  page?: number;
  pageSize?: number;
  volumeId?: string;
  chapterId?: string;
}) {
  const [items, setItems] = useState<ApiHadith[]>([]);
  const [pageInfo, setPageInfo] = useState<ApiPage<ApiHadith> | null>(null);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    setIsLoading(true);
    setError(null);
    const search = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    });
    if (volumeId) search.set("volumeId", volumeId);
    if (chapterId) search.set("chapterId", chapterId);
    cachedApiFetch<ApiPage<ApiHadith>>(
      `/api/hadith/book/${collectionSlug}/hadith?${search.toString()}`,
    )
      .then((page) => {
        if (active) {
          setItems(page.items);
          setPageInfo(page);
        }
      })
      .catch((nextError) => {
        if (active)
          setError(
            nextError instanceof Error
              ? nextError
              : new Error("Failed to load hadiths"),
          );
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, [chapterId, collectionSlug, page, pageSize, volumeId]);

  return {
    items,
    pageInfo,
    page: pageInfo?.page ?? page,
    pageSize: pageInfo?.pageSize ?? pageSize,
    hasMore: pageInfo?.hasMore ?? false,
    isLoading,
    error,
  };
}

export function toCollectionCard(book: ApiBook) {
  return {
    slug: book.slug,
    title: book.collection,
    arabic: book.arabicName,
    count: book.hadithCount,
    coverage: undefined,
    grade:
      book.authenticityGrade ??
      (book.slug === "bukhari" || book.slug === "muslim" ? "Sahih" : "Sunan"),
  };
}

export function buildCollectionDetail(detail: ApiCollectionDetail) {
  return {
    card: toCollectionCard(detail.book),
    volumes: detail.indexTrusted ? detail.volumes : [],
    chapters: detail.indexTrusted ? detail.chapters : [],
  };
}

export function toReaderHadith(hadith: ApiHadith) {
  return {
    id: hadith.id,
    collectionSlug: hadith.collectionSlug,
    reference: hadith.referenceDisplay,
    arabic: hadith.arabicText,
    translation: hadith.englishText ?? "Translation is not available yet.",
    sourceLabel: "Official",
    grade: formatAuthenticity(hadith),
    ratingPercent: null,
    narrator: hadith.narrator ?? "",
    book: hadith.chapterName ?? hadith.collectionName,
    providerHadithId: hadith.providerHadithId,
  };
}

export function buildApiCacheKey(
  path: string,
  params: Record<string, string | number | undefined> = {},
) {
  const search = new URLSearchParams();
  Object.entries(params)
    .filter(
      (entry): entry is [string, string | number] => entry[1] !== undefined,
    )
    .sort(([left], [right]) => left.localeCompare(right))
    .forEach(([key, value]) => search.set(key, String(value)));
  const query = search.toString();
  return query ? `${path}?${query}` : path;
}

async function cachedApiFetch<T>(path: string, init?: RequestInit): Promise<T> {
  if (init?.method && init.method !== "GET") {
    return apiFetch<T>(path, init);
  }
  const cacheKey = `hadithly:api-cache:v1:${path}`;
  const storage = await getAsyncStorage();
  const cached = await storage.getItem(cacheKey);
  if (cached) {
    void apiFetch<T>(path, init)
      .then((fresh) => storage.setItem(cacheKey, JSON.stringify(fresh)))
      .catch(() => undefined);
    return JSON.parse(cached) as T;
  }
  const fresh = await apiFetch<T>(path, init);
  await storage.setItem(cacheKey, JSON.stringify(fresh));
  return fresh;
}

async function getAsyncStorage() {
  const module = await import("@react-native-async-storage/async-storage");
  return module.default;
}

export async function generateTranslation(args: {
  hadithId: string;
  targetLanguage: string;
  sourceLanguage?: string;
  token?: string | null;
}) {
  return await apiFetch<ApiTranslationResponse>("/api/translate/generate", {
    method: "POST",
    headers: {
      "content-type": "application/json",
      ...(args.token ? { authorization: `Bearer ${args.token}` } : {}),
    },
    body: JSON.stringify({
      hadithId: args.hadithId,
      targetLanguage: args.targetLanguage,
      sourceLanguage: args.sourceLanguage ?? "en",
    }),
  });
}

export function useSearchHadiths(query: string, language?: string) {
  const [items, setItems] = useState<ApiHadith[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);
  const trimmed = query.trim();

  useEffect(() => {
    if (!trimmed) {
      setItems([]);
      return;
    }
    let active = true;
    setIsLoading(true);
    setError(null);
    const search = new URLSearchParams({ q: trimmed });
    if (language) search.set("language", language);
    cachedApiFetch<ApiHadith[]>(`/api/hadith/search?${search.toString()}`)
      .then((results) => {
        if (active) setItems(results);
      })
      .catch((nextError) => {
        if (active)
          setError(
            nextError instanceof Error
              ? nextError
              : new Error("Failed to search hadiths"),
          );
      })
      .finally(() => {
        if (active) setIsLoading(false);
      });
    return () => {
      active = false;
    };
  }, [language, trimmed]);

  return { items, isLoading, error };
}

function formatAuthenticity(hadith: ApiHadith) {
  if (!hadith.authenticityGrade) return "Grade unavailable";
  const grade = titleCase(hadith.authenticityGrade);
  if (hadith.authenticityAppliesTo === "collection") {
    return `Collection: ${grade}`;
  }
  if (hadith.authenticityAppliesTo === "none") {
    return "Grade unavailable";
  }
  return grade;
}

function titleCase(value: string) {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}
