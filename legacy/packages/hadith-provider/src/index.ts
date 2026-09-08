import type {
  Book,
  CollectionIndex,
  Hadith,
  HadithProviderName,
  HadithSearchQuery,
  ListHadithParams,
  Paginated,
  SearchResult,
} from "@hadithly/types";

type FetchLike = typeof fetch;

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

export interface HadithProvider {
  listBooks(): Promise<Book[]>;
  getBook(slug: string): Promise<Book>;
  getCollectionIndex(slug: string): Promise<CollectionIndex>;
  listHadiths(params: ListHadithParams): Promise<Paginated<Hadith>>;
  getHadith(slug: string, id: string): Promise<Hadith>;
  search(query: HadithSearchQuery): Promise<SearchResult[]>;
}

export type SunnahNowProviderOptions = {
  apiKey: string;
  baseUrl?: string;
  fetch?: FetchLike;
  cachedSearch?: (query: HadithSearchQuery) => Promise<SearchResult[]>;
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
    Hadith,
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

export function createInternalHadithId(
  provider: HadithProviderName,
  collectionSlug: string,
  providerHadithId: string,
) {
  return `${provider}:${collectionSlug}:${providerHadithId}`;
}

export class SunnahNowProvider implements HadithProvider {
  private readonly apiKey: string;
  private readonly baseUrl: string;
  private readonly fetchImpl: FetchLike;
  private readonly cachedSearch?: (
    query: HadithSearchQuery,
  ) => Promise<SearchResult[]>;

  constructor(options: SunnahNowProviderOptions) {
    this.apiKey = options.apiKey;
    this.baseUrl = options.baseUrl ?? "https://api.sunnah.now";
    this.fetchImpl = options.fetch ?? fetch;
    this.cachedSearch = options.cachedSearch;
  }

  async listBooks(): Promise<Book[]> {
    const response = await this.request<Book[]>("/api/early-access/books");
    return response.map((book) => ({
      collection: book.collection,
      slug: book.slug,
    }));
  }

  async getBook(slug: string): Promise<Book> {
    const response = await this.request<{ metadata?: Book }>(
      `/api/early-access/book/${encodeURIComponent(slug)}`,
    );
    return (
      response.metadata ?? {
        collection: collectionName(slug),
        slug,
      }
    );
  }

  async getCollectionIndex(slug: string): Promise<CollectionIndex> {
    const book = await this.getBook(slug);
    const volumes = new Map<string, CollectionIndex["volumes"][number]>();
    let page = 1;
    let hasMore = true;

    while (hasMore && page <= 500) {
      const nextPage = await this.listHadiths({
        collectionSlug: slug,
        page,
        pageSize: 50,
      });

      for (const hadith of nextPage.items) {
        if (!hadith.volumeId) continue;
        const existing = volumes.get(hadith.volumeId);
        const firstChapterTitle =
          existing?.firstChapterTitle ?? hadith.chapterName;
        const firstChapterArabicTitle =
          existing?.firstChapterArabicTitle ?? hadith.bookName;
        volumes.set(hadith.volumeId, {
          volumeId: hadith.volumeId,
          title: `Volume ${hadith.volumeId}`,
          firstChapterTitle,
          firstChapterArabicTitle,
          hadithCount: (existing?.hadithCount ?? 0) + 1,
          route: {
            collectionSlug: slug,
            volumeId: hadith.volumeId,
          },
        });
      }

      hasMore = nextPage.hasMore && nextPage.items.length > 0;
      page += 1;
    }

    return {
      book,
      volumes: Array.from(volumes.values()).sort(
        (left, right) => Number(left.volumeId) - Number(right.volumeId),
      ),
      chapters: [],
      indexTrusted: volumes.size > 0,
      source: "sunnah_now",
      indexedAt: Date.now(),
    };
  }

  async listHadiths(params: ListHadithParams): Promise<Paginated<Hadith>> {
    const page = params.page ?? 1;
    const pageSize = params.pageSize ?? 50;
    const path = this.listPath(params);
    if (params.volumeId) {
      const response = await this.request<SunnahNowHadith[]>(path);
      const normalized = response
        .map((hadith) => normalizeHadith(params.collectionSlug, hadith))
        .filter((hadith) =>
          params.chapterId ? hadith.chapterId === params.chapterId : true,
        );
      const pages = chunkReaderHadiths(normalized, pageSize);
      const pageIndex = Math.max(0, page - 1);
      return {
        items: pages[pageIndex] ?? [],
        page,
        pageSize,
        hasMore: pageIndex < pages.length - 1,
        sourceRoute: path,
      };
    }
    const search = new URLSearchParams({
      page: String(page),
      pageSize: String(pageSize),
    });
    const response = await this.request<SunnahNowHadith[]>(
      `${path}?${search.toString()}`,
    );

    return {
      items: response.map((hadith) =>
        normalizeHadith(params.collectionSlug, hadith),
      ),
      page,
      pageSize,
      hasMore: response.length >= pageSize,
      sourceRoute: path,
    };
  }

  async getHadith(slug: string, id: string): Promise<Hadith> {
    void slug;
    void id;
    throw new Error(
      "Direct Sunnah.now hadith reads are disabled because /book/:slug/hadith/:id is currently slug-unsafe. Use paginated reads plus Convex cache.",
    );
  }

  async search(query: HadithSearchQuery): Promise<SearchResult[]> {
    return this.cachedSearch?.(query) ?? [];
  }

  private listPath(params: ListHadithParams) {
    const slug = encodeURIComponent(params.collectionSlug);
    if (params.volumeId) {
      return `/api/early-access/book/${slug}/volume/${encodeURIComponent(params.volumeId)}`;
    }
    return `/api/early-access/book/${slug}/hadith`;
  }

  private async request<T>(path: string): Promise<T> {
    const response = await this.fetchImpl(`${this.baseUrl}${path}`, {
      headers: {
        "X-API-Key": this.apiKey,
        accept: "application/json",
      },
    });

    if (!response.ok) {
      throw new Error(`Sunnah.now request failed with HTTP ${response.status}`);
    }

    return (await response.json()) as T;
  }
}

function normalizeHadith(
  collectionSlug: string,
  hadith: SunnahNowHadith,
): Hadith {
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
    id: createInternalHadithId("sunnah_now", collectionSlug, providerHadithId),
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

function collectionName(slug: string) {
  return COLLECTION_NAMES[slug] ?? slug;
}

function optionalString(value: number | string | undefined) {
  return value === undefined || value === null ? undefined : String(value);
}

function chunkReaderHadiths(items: Hadith[], requestedPageSize: number) {
  const maxItems = Math.max(1, Math.min(10, requestedPageSize));
  const maxChars = 5200;
  const pages: Hadith[][] = [];
  let current: Hadith[] = [];
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
