"use node";

/**
 * Hadith data actions — the only place Sunnah.now is ever called.
 * Secrets stay in Convex env vars; clients see only cached/normalized docs.
 */

import { v } from "convex/values";
import { createHash } from "node:crypto";
import { action } from "../_generated/server";
import { api, internal } from "../_generated/api";
import {
  buildCollectionOutline,
  chunkReaderHadiths,
  fetchBooks,
  fetchReaderPage,
  fetchVolumeHadiths,
} from "../lib/sunnahNow";
import type { HadithRecord } from "../lib/sunnahNow";
import { READER_PAGINATION_VERSION } from "../lib/readingPositions";

const OUTLINE_TTL_MS = 7 * 24 * 60 * 60 * 1000;

type CollectionDoc = {
  _id: string;
  slug: string;
  collection: string;
  name: string;
  sortOrder?: number;
};

type OutlineDoc = {
  _id: string;
  collectionSlug: string;
  volumes: Array<{
    volumeId: string;
    title: string;
    firstChapterTitle?: string;
    firstChapterArabicTitle?: string;
    hadithCount: number;
  }>;
  indexedAt: number;
} | null;

type ReaderHadithRecord = Omit<HadithRecord, "licenseRecord">;

type ReaderPageResult = {
  items: Array<ReaderHadithRecord & { _id: string }>;
  page: number;
  pageSize: number;
  totalPages: number;
  hasMore: boolean;
  contentVersion: string;
  paginationVersion: number;
  pageKey: string;
};

/** Public: list the collections (cached from the provider). */
export const listBooks = action({
  args: {},
  handler: async (ctx): Promise<CollectionDoc[]> => {
    const books = await fetchBooks();
    for (const book of books) {
      await ctx.runMutation(internal.collections.upsertCollection, {
        slug: book.slug,
        collection: book.collection,
        name: book.slug,
      });
    }
    return await ctx.runQuery(api.collections.list, {});
  },
});

/**
 * Public: volume outline for a collection, cached for a week.
 * The first call per collection paginates the provider (slow); later calls
 * read from the cache (fast).
 */
export const getCollectionOutline = action({
  args: { collectionSlug: v.string(), refresh: v.optional(v.boolean()) },
  handler: async (ctx, args): Promise<OutlineDoc> => {
    const cached = await ctx.runQuery(api.collections.getOutline, {
      collectionSlug: args.collectionSlug,
    });
    if (
      cached &&
      !args.refresh &&
      Date.now() - cached.indexedAt < OUTLINE_TTL_MS &&
      cached.volumes.length > 0
    ) {
      return cached;
    }

    const volumes = await buildCollectionOutline(args.collectionSlug);
    await ctx.runMutation(internal.collections.upsertOutline, {
      collectionSlug: args.collectionSlug,
      volumes,
    });
    return await ctx.runQuery(api.collections.getOutline, {
      collectionSlug: args.collectionSlug,
    });
  },
});

/**
 * Public: one reader page of hadiths for a collection (optionally scoped to
 * a volume). Volume reads are cache-first: once a volume is fully cached
 * (cached count matches the outline's hadith count), pages are served from
 * the `hadiths` table with no provider call. Provider responses are
 * normalized and cached in the `hadiths` table, which also powers search and
 * AI translation grounding.
 */
export const getReaderPage = action({
  args: {
    collectionSlug: v.string(),
    volumeId: v.optional(v.string()),
    page: v.optional(v.number()),
    pageSize: v.optional(v.number()),
    // When set (continue-reading, saved items, daily hadith), the volume
    // path serves the page containing this hadith number instead of `page`.
    targetHadithNumber: v.optional(v.string()),
  },
  handler: async (ctx, args): Promise<ReaderPageResult> => {
    const page = args.page ?? 1;
    const pageSize = args.pageSize ?? 10;

    if (args.volumeId) {
      const outline = await ctx.runQuery(api.collections.getOutline, {
        collectionSlug: args.collectionSlug,
      });
      const volume = outline?.volumes.find(
        (entry) => entry.volumeId === args.volumeId,
      );

      if (volume && volume.hadithCount > 0) {
        const cached = await ctx.runQuery(internal.hadiths.listByVolume, {
          provider: "sunnah_now",
          collectionSlug: args.collectionSlug,
          volumeId: args.volumeId,
        });
        if (cached.length >= volume.hadithCount) {
          return serveVolumeChunk(
            cached,
            resolvePageNumber(cached, args, page, pageSize),
            pageSize,
            args.volumeId,
          );
        }
      }

      // First visit to the volume: pull it once, cache it in full, then
      // serve every later page turn from the `hadiths` table.
      const volumeItems = await fetchVolumeHadiths({
        collectionSlug: args.collectionSlug,
        volumeId: args.volumeId,
      });
      const upsertIds = await ctx.runMutation(internal.hadiths.upsertPage, {
        items: volumeItems,
      });
      const withIds = volumeItems.map((item, index) => ({
        _id: upsertIds[index],
        ...readerHadith(item),
      }));
      return serveVolumeChunk(
        withIds,
        resolvePageNumber(withIds, args, page, pageSize),
        pageSize,
        args.volumeId,
      );
    }

    const providerPage = await fetchReaderPage({
      collectionSlug: args.collectionSlug,
      volumeId: args.volumeId,
      page,
      pageSize,
    });

    const upsertIds = await ctx.runMutation(internal.hadiths.upsertPage, {
      items: providerPage.items,
    });

    const items = providerPage.items.map((item, index) => ({
      _id: upsertIds[index],
      ...readerHadith(item),
    }));

    return {
      items,
      page: providerPage.page,
      pageSize: providerPage.pageSize,
      totalPages: providerPage.totalPages,
      hasMore: providerPage.hasMore,
      ...pageIdentity(items, items, args.volumeId ?? "collection"),
    };
  },
});

/**
 * With a target hadith number, computes the page that contains it; without,
 * falls back to the requested page.
 */
function resolvePageNumber(
  volumeHadiths: ReaderHadithRecord[],
  args: { targetHadithNumber?: string },
  fallbackPage: number,
  pageSize: number,
): number {
  if (!args.targetHadithNumber) return fallbackPage;
  const pageIndex = chunkReaderHadiths(volumeHadiths, pageSize).findIndex(
    (items) =>
      items.some(
        (item) => item.providerHadithId === args.targetHadithNumber,
      ),
  );
  if (pageIndex < 0) return fallbackPage;
  return pageIndex + 1;
}

/**
 * Slices the cached volume into content-sized reader pages using the same
 * chunking as the provider path, so page boundaries are identical whether a
 * page comes from the cache or the provider.
 */
function serveVolumeChunk(
  cached: Array<ReaderHadithRecord & { _id: string }>,
  page: number,
  pageSize: number,
  volumeId: string,
): ReaderPageResult {
  const pages = chunkReaderHadiths(cached, pageSize);
  const pageIndex = Math.max(0, page - 1);
  const items = (pages[pageIndex] ?? []).map((item) => {
    const { _id: cachedId, ...record } = item;
    return { _id: cachedId, ...record };
  });
  return {
    items,
    page,
    pageSize,
    totalPages: pages.length,
    hasMore: pageIndex < pages.length - 1,
    ...pageIdentity(cached, items, volumeId),
  };
}

function pageIdentity(
  contentItems: ReaderHadithRecord[],
  pageItems: ReaderHadithRecord[],
  volumeId: string,
): { contentVersion: string; paginationVersion: number; pageKey: string } {
  const contentHash = createHash("sha256");
  for (const item of contentItems) {
    contentHash.update(JSON.stringify([
      item.canonicalId,
      item.volumeId ?? null,
      item.chapterId ?? null,
      item.arabicText,
      item.englishText ?? null,
      item.narrator ?? null,
      item.referenceDisplay,
      item.collectionName,
      item.bookName ?? null,
      item.chapterName ?? null,
      item.authenticity,
    ]));
    contentHash.update("\n");
  }
  const contentVersion = `cv1:${contentHash.digest("hex")}`;
  const pageHash = createHash("sha256");
  pageHash.update(JSON.stringify([
    contentVersion,
    READER_PAGINATION_VERSION,
    volumeId,
    pageItems.map((item) => item.canonicalId),
  ]));
  return {
    contentVersion,
    paginationVersion: READER_PAGINATION_VERSION,
    pageKey: `pg1:${pageHash.digest("hex")}`,
  };
}

function readerHadith(hadith: HadithRecord): ReaderHadithRecord {
  return {
    provider: hadith.provider,
    canonicalId: hadith.canonicalId,
    providerHadithId: hadith.providerHadithId,
    collectionSlug: hadith.collectionSlug,
    volumeId: hadith.volumeId,
    chapterId: hadith.chapterId,
    arabicText: hadith.arabicText,
    englishText: hadith.englishText,
    narrator: hadith.narrator,
    referenceDisplay: hadith.referenceDisplay,
    collectionName: hadith.collectionName,
    bookName: hadith.bookName,
    chapterName: hadith.chapterName,
    authenticity: hadith.authenticity,
  };
}
