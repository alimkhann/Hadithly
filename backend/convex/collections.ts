import { internalMutation, query } from "./_generated/server";
import { v } from "convex/values";
import { DEFAULT_COLLECTION_ORDER } from "./lib/sunnahNow";

export const upsertCollection = internalMutation({
  args: {
    slug: v.string(),
    collection: v.string(),
    name: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("collections")
      .withIndex("by_slug", (q) => q.eq("slug", args.slug))
      .unique();
    const sortOrder = DEFAULT_COLLECTION_ORDER.indexOf(
      args.slug as (typeof DEFAULT_COLLECTION_ORDER)[number],
    );
    if (existing) {
      await ctx.db.patch(existing._id, {
        collection: args.collection,
        name: args.name,
        sortOrder: sortOrder >= 0 ? sortOrder : existing.sortOrder,
      });
      return existing._id;
    }
    return await ctx.db.insert("collections", {
      ...args,
      sortOrder: sortOrder >= 0 ? sortOrder : undefined,
    });
  },
});

/** Public: cached collections in canonical reading order. */
export const list = query({
  args: {},
  handler: async (ctx) => {
    const rows = await ctx.db.query("collections").collect();
    return rows.sort((a, b) => (a.sortOrder ?? 999) - (b.sortOrder ?? 999));
  },
});

export const upsertOutline = internalMutation({
  args: {
    collectionSlug: v.string(),
    volumes: v.array(
      v.object({
        volumeId: v.string(),
        title: v.string(),
        firstChapterTitle: v.optional(v.string()),
        firstChapterArabicTitle: v.optional(v.string()),
        hadithCount: v.number(),
      }),
    ),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("collectionOutlines")
      .withIndex("by_collection_slug", (q) =>
        q.eq("collectionSlug", args.collectionSlug),
      )
      .unique();
    if (existing) {
      await ctx.db.patch(existing._id, {
        volumes: args.volumes,
        indexedAt: now,
      });
      return existing._id;
    }
    return await ctx.db.insert("collectionOutlines", {
      ...args,
      indexedAt: now,
    });
  },
});

/** Public: cached volume outline for a collection. */
export const getOutline = query({
  args: { collectionSlug: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("collectionOutlines")
      .withIndex("by_collection_slug", (q) =>
        q.eq("collectionSlug", args.collectionSlug),
      )
      .unique(),
});
