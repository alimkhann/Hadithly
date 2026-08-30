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
  fetchBooks,
  fetchReaderPage,
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
 * a volume). Provider responses are normalized and cached in the `hadiths`
 * table, which also powers search and AI translation grounding.
 */
export const getReaderPage = action({
  args: {
    collectionSlug: v.string(),
    volumeId: v.optional(v.string()),
    page: v.optional(v.number()),
    pageSize: v.optional(v.number()),
  },
  handler: async (ctx, args): Promise<ReaderPageResult> => {
    const providerPage = await fetchReaderPage({
      collectionSlug: args.collectionSlug,
      volumeId: args.volumeId,
      page: args.page,
      pageSize: args.pageSize,
    });

    const ids = await ctx.runMutation(internal.hadiths.upsertPage, {
      items: providerPage.items,
    });

    const items = providerPage.items.map((item, index) => ({
      _id: ids[index] as string,
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
