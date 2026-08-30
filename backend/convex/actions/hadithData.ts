"use node";

/**
 * Hadith data actions — the only place Sunnah.now is ever called.
 * Secrets stay in Convex env vars; clients see only cached/normalized docs.
 */

import { v } from "convex/values";
import { action } from "../_generated/server";
import { api, internal } from "../_generated/api";
import {
  buildCollectionOutline,
  chunkReaderHadiths,
  fetchBooks,
  fetchReaderPage,
  fetchVolumeHadiths,
} from "../lib/sunnahNow";

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

type ReaderPageResult = {
  items: Array<
    import("../lib/sunnahNow").HadithRecord & { _id: string }
  >;
  page: number;
  pageSize: number;
  totalPages: number;
  hasMore: boolean;
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
        _id: upsertIds[index] as string,
        ...item,
      }));
      return serveVolumeChunk(
        withIds,
        resolvePageNumber(withIds, args, page, pageSize),
        pageSize,
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
      _id: upsertIds[index] as string,
      ...item,
    }));

    return {
      items,
      page: providerPage.page,
      pageSize: providerPage.pageSize,
      totalPages: providerPage.totalPages,
      hasMore: providerPage.hasMore,
    };
  },
});

/**
 * With a target hadith number, computes the page that contains it; without,
 * falls back to the requested page.
 */
function resolvePageNumber(
  volumeHadiths: Array<{ providerHadithId: string }>,
  args: { targetHadithNumber?: string },
  fallbackPage: number,
  pageSize: number,
): number {
  if (!args.targetHadithNumber) return fallbackPage;
  const index = volumeHadiths.findIndex(
    (item) => item.providerHadithId === args.targetHadithNumber,
  );
  if (index < 0) return fallbackPage;
  return Math.floor(index / pageSize) + 1;
}

/**
 * Slices the cached volume into content-sized reader pages using the same
 * chunking as the provider path, so page boundaries are identical whether a
 * page comes from the cache or the provider.
 */
function serveVolumeChunk(
  cached: Array<
    import("../lib/sunnahNow").HadithRecord & {
      _id: string;
    }
  >,
  page: number,
  pageSize: number,
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
  };
}
