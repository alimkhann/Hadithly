/**
 * Sunnah.now provider logic, adapted from legacy packages/hadith-provider.
 * Pure TypeScript (no Node APIs) so Node actions can import it directly.
 *
 * Security rule: this module is only ever imported by Convex actions.
 * The API key lives in Convex env vars (SUNNAH_NOW_API_KEY) and never
 * reaches a client.
 */

import {
  SUNNAH_NOW_LICENSE_RECORD,
  authenticityForProviderHadith,
  canonicalHadithIdentity,
} from "./contentPolicy";
import type {
  AuthenticityClaim,
  HadithProviderName,
  LicenseRecordDescriptor,
} from "./contentPolicy";

export type { HadithProviderName } from "./contentPolicy";

export type HadithRecord = {
  provider: HadithProviderName;
  canonicalId: string;
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
  authenticity: AuthenticityClaim;
  licenseRecord: LicenseRecordDescriptor;
};

export type SunnahNowBook = {
  collection: string;
  slug: string;
};

type SunnahNowLanguageText = {
  text?: string;
  narrator?: string;
};

export type SunnahNowHadith = {
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
  return canonicalHadithIdentity({
    provider,
    collectionSlug,
    providerHadithId,
  }).canonicalId;
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

async function request(path: string): Promise<unknown> {
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

  const body: unknown = await response.json();
  return body;
}

export async function fetchBooks(): Promise<SunnahNowBook[]> {
  return parseBooks(await request("/api/early-access/books"));
}

export function normalizeHadith(
  collectionSlug: string,
  hadith: SunnahNowHadith,
): HadithRecord {
  const providerHadithId = String(hadith.id);
  const identity = canonicalHadithIdentity({
    provider: "sunnah_now",
    collectionSlug,
    providerHadithId,
  });
  const language = hadith.language ?? {};
  const chapterLanguage = hadith.metadata?.chapter?.language ?? {};
  const arabicText = language.ar?.text ?? "";
  const englishText = language.en?.text;
  const narrator = language.en?.narrator;
  const chapterName = chapterLanguage.en?.text || chapterLanguage.ar?.text;
  const chapterArabicName = chapterLanguage.ar?.text;
  const collection = collectionName(collectionSlug);

  return {
    ...identity,
    volumeId: optionalString(hadith.metadata?.volume?.id),
    chapterId: optionalString(hadith.metadata?.chapter?.id),
    arabicText,
    englishText,
    narrator,
    referenceDisplay: `${collection} · Hadith ${providerHadithId}`,
    collectionName: collection,
    bookName: chapterArabicName,
    chapterName,
    authenticity: authenticityForProviderHadith(collectionSlug),
    licenseRecord: SUNNAH_NOW_LICENSE_RECORD,
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

type ChunkableHadith = {
  arabicText: string;
  englishText?: string;
  narrator?: string;
};

/**
 * Reader pages are chunked by content size (not a fixed count) so long
 * Arabic + translation pairs never produce an overwhelming screen.
 */
export function chunkReaderHadiths<T extends ChunkableHadith>(
  items: T[],
  requestedPageSize: number,
): T[][] {
  const maxItems = Math.max(1, Math.min(10, requestedPageSize));
  const maxChars = 5200;
  const pages: T[][] = [];
  let current: T[] = [];
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
    const response = parseSunnahNowHadiths(await request(path));
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
  const response = parseSunnahNowHadiths(
    await request(`${path}?${search.toString()}`),
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

/**
 * Fetches every hadith of one volume in a single provider call, normalized.
 * The reader action caches the full volume so later page turns never touch
 * the provider again.
 */
export async function fetchVolumeHadiths(params: {
  collectionSlug: string;
  volumeId: string;
}): Promise<HadithRecord[]> {
  const path = listPath(params);
  const response = parseSunnahNowHadiths(await request(path));
  return response.map((hadith) => normalizeHadith(params.collectionSlug, hadith));
}

function parseBooks(value: unknown): SunnahNowBook[] {
  if (!Array.isArray(value)) throw new Error("Sunnah.now returned invalid books");
  return value.map((entry) => {
    if (!isRecord(entry) || typeof entry.slug !== "string") {
      throw new Error("Sunnah.now returned an invalid book");
    }
    const slug = entry.slug.trim();
    if (!DEFAULT_COLLECTION_ORDER.some((candidate) => candidate === slug)) {
      throw new Error(`Sunnah.now returned an unsupported collection: ${slug}`);
    }
    return { collection: collectionName(slug), slug };
  });
}

export function parseSunnahNowHadiths(value: unknown): SunnahNowHadith[] {
  if (!Array.isArray(value)) {
    throw new Error("Sunnah.now returned invalid hadith data");
  }
  return value.map(parseHadith);
}

function parseHadith(value: unknown): SunnahNowHadith {
  if (!isRecord(value)) throw new Error("Sunnah.now returned an invalid hadith");
  const id = parseProviderId(value.id);
  const language = parseLanguageMap(value.language);
  const metadata = isRecord(value.metadata) ? value.metadata : undefined;
  const volume = metadata && isRecord(metadata.volume)
    ? { id: parseOptionalProviderId(metadata.volume.id) }
    : undefined;
  const chapterRecord = metadata && isRecord(metadata.chapter)
    ? metadata.chapter
    : undefined;
  const chapter = chapterRecord
    ? {
        id: parseOptionalProviderId(chapterRecord.id),
        language: parseLanguageMap(chapterRecord.language),
      }
    : undefined;

  return {
    id,
    ...(language ? { language } : {}),
    ...(volume || chapter ? { metadata: { volume, chapter } } : {}),
  };
}

function parseLanguageMap(
  value: unknown,
): Record<string, SunnahNowLanguageText> | undefined {
  if (!isRecord(value)) return undefined;
  const languages: Record<string, SunnahNowLanguageText> = {};
  for (const [language, rawText] of Object.entries(value)) {
    if (!isRecord(rawText)) continue;
    const text = typeof rawText.text === "string" ? rawText.text : undefined;
    const narrator =
      typeof rawText.narrator === "string" ? rawText.narrator : undefined;
    if (text !== undefined || narrator !== undefined) {
      languages[language] = { text, narrator };
    }
  }
  return languages;
}

function parseProviderId(value: unknown): string | number {
  if (typeof value === "number" && Number.isFinite(value)) return value;
  if (typeof value === "string" && value.trim().length > 0) return value.trim();
  throw new Error("Sunnah.now returned an invalid hadith id");
}

function parseOptionalProviderId(value: unknown): string | number | undefined {
  return value === undefined || value === null ? undefined : parseProviderId(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
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
