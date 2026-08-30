/**
 * Sunnah.now provider logic, adapted from legacy packages/hadith-provider.
 * Pure TypeScript (no Node APIs) so Node actions can import it directly.
 *
 * Security rule: this module is only ever imported by Convex actions.
 * The API key lives in Convex env vars (SUNNAH_NOW_API_KEY) and never
 * reaches a client.
 */

export type HadithProviderName = "sunnah_now" | "sunnah_com" | "local_dump";

export type HadithRecord = {
  provider: HadithProviderName;
  providerHadithId: string;
  collectionSlug: string;
  volumeId?: string;
  chapterId?: string;
  arabicText: string;
  englishText?: string;
  narrator?: string;
  referenceDisplay: string;
  collectionName: string;
  bookName?: string;
  chapterName?: string;
  authenticityGrade?: "sahih" | "hasan" | "daif" | "mawdu" | "mixed" | "unknown";
  authenticityAppliesTo: "hadith" | "collection" | "none";
  authenticitySource?: string;
  authenticityConfidence: "source_provided" | "manual_mapping" | "unavailable";
};

export type SunnahNowBook = {
  collection: string;
  slug: string;
};

type SunnahNowLanguageText = {
  text?: string;
  narrator?: string;
};

type SunnahNowHadith = {
  id: number | string;
  metadata?: {
    volume?: { id?: number | string };
    chapter?: {
      id?: number | string;
      language?: Record<string, SunnahNowLanguageText>;
    };
  };
  language?: Record<string, SunnahNowLanguageText>;
};

const COLLECTION_NAMES: Record<string, string> = {
  "abu-dawood": "Abu Dawood",
  bukhari: "Sahih al-Bukhari",
  "ibn-majah": "Ibn Majah",
  "mishkat-al-masabih": "Mishkat al-Masabih",
  muslim: "Sahih Muslim",
  "sunan-nasai": "Sunan an-Nasa'i",
  tirmidhi: "Jami` at-Tirmidhi",
};

const COLLECTION_AUTHENTICITY: Record<
  string,
  Pick<
    HadithRecord,
    | "authenticityGrade"
    | "authenticityAppliesTo"
    | "authenticitySource"
    | "authenticityConfidence"
  >
> = {
  bukhari: {
    authenticityGrade: "sahih",
    authenticityAppliesTo: "collection",
    authenticitySource: "Collection-level mapping",
    authenticityConfidence: "manual_mapping",
  },
  muslim: {
    authenticityGrade: "sahih",
    authenticityAppliesTo: "collection",
    authenticitySource: "Collection-level mapping",
    authenticityConfidence: "manual_mapping",
  },
};

export const DEFAULT_COLLECTION_ORDER = [
  "bukhari",
  "muslim",
  "sunan-nasai",
  "abu-dawood",
  "tirmidhi",
  "ibn-majah",
  "mishkat-al-masabih",
] as const;

export function createInternalHadithId(
  provider: HadithProviderName,
  collectionSlug: string,
  providerHadithId: string,
) {
  return `${provider}:${collectionSlug}:${providerHadithId}`;
}

export function parseInternalHadithId(internalId: string): {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
} | null {
  const parts = internalId.split(":");
  if (parts.length !== 3) return null;
  const [provider, collectionSlug, providerHadithId] = parts;
  if (
    provider !== "sunnah_now" &&
    provider !== "sunnah_com" &&
    provider !== "local_dump"
  ) {
    return null;
  }
  return { provider, collectionSlug, providerHadithId };
}

export function collectionName(slug: string) {
  return COLLECTION_NAMES[slug] ?? slug;
}

async function request<T>(path: string): Promise<T> {
  const apiKey = process.env.SUNNAH_NOW_API_KEY;
  if (!apiKey) {
    throw new Error("SUNNAH_NOW_API_KEY is not configured");
  }
  const baseUrl = process.env.SUNNAH_NOW_BASE_URL ?? "https://api.sunnah.now";
  const response = await fetch(`${baseUrl}${path}`, {
    headers: {
      "X-API-Key": apiKey,
      accept: "application/json",
    },
  });

  if (!response.ok) {
    throw new Error(`Sunnah.now request failed with HTTP ${response.status}`);
  }

  return (await response.json()) as T;
}

export async function fetchBooks(): Promise<SunnahNowBook[]> {
  const response = await request<SunnahNowBook[]>("/api/early-access/books");
  return response.map((book) => ({
    collection: book.collection,
    slug: book.slug,
  }));
}

export function normalizeHadith(
  collectionSlug: string,
  hadith: SunnahNowHadith,
): HadithRecord {
  const providerHadithId = String(hadith.id);
  const language = hadith.language ?? {};
  const chapterLanguage = hadith.metadata?.chapter?.language ?? {};
  const arabicText = language.ar?.text ?? "";
  const englishText = language.en?.text;
  const narrator = language.en?.narrator;
  const chapterName = chapterLanguage.en?.text || chapterLanguage.ar?.text;
  const chapterArabicName = chapterLanguage.ar?.text;
  const collection = collectionName(collectionSlug);
  const authenticity = COLLECTION_AUTHENTICITY[collectionSlug] ?? {
    authenticityAppliesTo: "none" as const,
    authenticityConfidence: "unavailable" as const,
  };

  return {
    provider: "sunnah_now",
    providerHadithId,
    collectionSlug,
    volumeId: optionalString(hadith.metadata?.volume?.id),
    chapterId: optionalString(hadith.metadata?.chapter?.id),
    arabicText,
    englishText,
    narrator,
    referenceDisplay: `${collection} · Hadith ${providerHadithId}`,
    collectionName: collection,
    bookName: chapterArabicName,
    chapterName,
    ...authenticity,
  };
}

function optionalString(value: number | string | undefined) {
  return value === undefined || value === null ? undefined : String(value);
}

function listPath(params: { collectionSlug: string; volumeId?: string }) {
  const slug = encodeURIComponent(params.collectionSlug);
  if (params.volumeId) {
    return `/api/early-access/book/${slug}/volume/${encodeURIComponent(params.volumeId)}`;
  }
  return `/api/early-access/book/${slug}/hadith`;
}

export type ReaderPage = {
  items: HadithRecord[];
  page: number;
  pageSize: number;
  totalPages: number;
  hasMore: boolean;
};

/**
 * Reader pages are chunked by content size (not a fixed count) so long
 * Arabic + translation pairs never produce an overwhelming screen.
 */
export function chunkReaderHadiths(
  items: HadithRecord[],
  requestedPageSize: number,
): HadithRecord[][] {
  const maxItems = Math.max(1, Math.min(10, requestedPageSize));
  const maxChars = 5200;
  const pages: HadithRecord[][] = [];
  let current: HadithRecord[] = [];
  let currentChars = 0;

  for (const item of items) {
    const itemChars =
      item.arabicText.length +
      (item.englishText?.length ?? 0) +
      (item.narrator?.length ?? 0);
    const shouldStartNext =
      current.length > 0 &&
      (current.length >= maxItems || currentChars + itemChars > maxChars);
    if (shouldStartNext) {
      pages.push(current);
      current = [];
      currentChars = 0;
    }
    current.push(item);
    currentChars += itemChars;
  }

  if (current.length > 0) pages.push(current);
  return pages;
}

export async function fetchReaderPage(params: {
  collectionSlug: string;
  volumeId?: string;
  page?: number;
  pageSize?: number;
}): Promise<ReaderPage> {
  const page = params.page ?? 1;
  const pageSize = params.pageSize ?? 10;
  const path = listPath(params);

  if (params.volumeId) {
    // Volume reads return the whole volume; chunk into reader pages locally.
    const response = await request<SunnahNowHadith[]>(path);
    const normalized = response.map((hadith) =>
      normalizeHadith(params.collectionSlug, hadith),
    );
    const pages = chunkReaderHadiths(normalized, pageSize);
    const pageIndex = Math.max(0, page - 1);
    return {
      items: pages[pageIndex] ?? [],
      page,
      pageSize,
      totalPages: pages.length,
      hasMore: pageIndex < pages.length - 1,
    };
  }

  const search = new URLSearchParams({
    page: String(page),
    pageSize: String(pageSize),
  });
  const response = await request<SunnahNowHadith[]>(
    `${path}?${search.toString()}`,
  );

  return {
    items: response.map((hadith) =>
      normalizeHadith(params.collectionSlug, hadith),
    ),
    page,
    pageSize,
    totalPages: 1,
    hasMore: response.length >= pageSize,
  };
}

export type VolumeOutlineEntry = {
  volumeId: string;
  title: string;
  firstChapterTitle?: string;
  firstChapterArabicTitle?: string;
  hadithCount: number;
};

/**
 * Builds a volume outline for a collection by paginating the provider.
 * Cached in the collectionOutlines table by the caller action.
 */
export async function buildCollectionOutline(
  collectionSlug: string,
): Promise<VolumeOutlineEntry[]> {
  const volumes = new Map<string, VolumeOutlineEntry>();
  let page = 1;
  let hasMore = true;

  while (hasMore && page <= 500) {
    const nextPage = await fetchReaderPage({
      collectionSlug,
      page,
      pageSize: 50,
    });

    for (const hadith of nextPage.items) {
      if (!hadith.volumeId) continue;
      const existing = volumes.get(hadith.volumeId);
      volumes.set(hadith.volumeId, {
        volumeId: hadith.volumeId,
        title: `Volume ${hadith.volumeId}`,
        firstChapterTitle: existing?.firstChapterTitle ?? hadith.chapterName,
        firstChapterArabicTitle:
          existing?.firstChapterArabicTitle ?? hadith.bookName,
        hadithCount: (existing?.hadithCount ?? 0) + 1,
      });
    }

    hasMore = nextPage.hasMore && nextPage.items.length > 0;
    page += 1;
  }

  return Array.from(volumes.values()).sort(
    (left, right) => Number(left.volumeId) - Number(right.volumeId),
  );
}
