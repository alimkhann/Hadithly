import { useEffect, useMemo, useState } from "react";

import { collections, readerHadiths } from "@/data/sample";
import { apiFetch } from "@/lib/api";

export type ApiBook = {
  collection: string;
  slug: string;
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
  authenticityConfidence: string;
};

export type ApiPage<T> = {
  items: T[];
  page: number;
  pageSize: number;
  hasMore: boolean;
  sourceRoute?: string;
};

export function useBooks() {
  const [books, setBooks] = useState<ApiBook[]>(() =>
    collections.map((collection) => ({
      collection: collection.title,
      slug: collection.slug,
    })),
  );
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    setIsLoading(true);
    apiFetch<ApiBook[]>("/api/hadith/books")
      .then((nextBooks) => {
        if (active && nextBooks.length > 0) setBooks(nextBooks);
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

export function useHadithPage(collectionSlug: string, pageSize = 20) {
  const fallback = useMemo(
    () =>
      readerHadiths.filter(
        (hadith) => hadith.collectionSlug === collectionSlug,
      ),
    [collectionSlug],
  );
  const [items, setItems] = useState<ApiHadith[]>([]);
  const [isLoading, setIsLoading] = useState(false);
  const [error, setError] = useState<Error | null>(null);

  useEffect(() => {
    let active = true;
    setIsLoading(true);
    apiFetch<ApiPage<ApiHadith>>(
      `/api/hadith/book/${collectionSlug}/hadith?page=1&pageSize=${pageSize}`,
    )
      .then((page) => {
        if (active) setItems(page.items);
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
  }, [collectionSlug, pageSize]);

  return { items, fallback, isLoading, error };
}

export function toCollectionCard(book: ApiBook) {
  const fixture = collections.find(
    (collection) => collection.slug === book.slug,
  );
  return {
    slug: book.slug,
    title: book.collection,
    arabic: fixture?.arabic ?? "",
    count: fixture?.count ?? 0,
    coverage: fixture?.coverage ?? 0,
    grade:
      fixture?.grade ??
      (book.slug === "bukhari" || book.slug === "muslim" ? "Sahih" : "Sunan"),
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
    grade: hadith.authenticityGrade
      ? titleCase(hadith.authenticityGrade)
      : "Unknown",
    ratingPercent: null,
    narrator: hadith.narrator ?? "",
    book: hadith.chapterName ?? hadith.collectionName,
  };
}

function titleCase(value: string) {
  return value.slice(0, 1).toUpperCase() + value.slice(1);
}
