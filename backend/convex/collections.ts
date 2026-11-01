import { convexToJson } from "convex/values";
import { outlineVolume, prepareOutline, unpackVolumes, volumeMetadata } from "./lib/outlineStorage";
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
    volumes: v.array(outlineVolume),
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const count = await ctx.db.query("collectionCounts").withIndex("by_collection", q => q.eq("collectionSlug", args.collectionSlug)).unique();
    const summary = { collectionSlug: args.collectionSlug, totalHadiths: args.volumes.reduce((sum, volume) => sum + volume.hadithCount, 0), indexedAt: now };
    if (count) await ctx.db.patch(count._id, summary);
    else await ctx.db.insert("collectionCounts", summary);
    const existing = await ctx.db
      .query("collectionOutlines")
      .withIndex("by_collection_slug", (q) =>
        q.eq("collectionSlug", args.collectionSlug),
      )
      .unique();
    const fields = await prepareOutline({ ...args, indexedAt: now });
    if (existing) {
      await ctx.db.replace(existing._id, fields);
      return existing._id;
    }
    return await ctx.db.insert("collectionOutlines", fields);
  },
});

/** Public: cached volume outline for a collection. */
export const getOutline = query({
  args: { collectionSlug: v.string() },
  handler: async (ctx, args) => {
    const row = await ctx.db.query("collectionOutlines")
      .withIndex("by_collection_slug", q => q.eq("collectionSlug", args.collectionSlug)).unique();
    if (!row) return null;
    const volumes = "packedVolumes" in row ? await unpackVolumes(row.packedVolumes) : row.volumes;
    if ("packedVolumes" in row && JSON.stringify(convexToJson(volumeMetadata(volumes))) !== JSON.stringify(convexToJson(row.volumes))) {
      throw new Error("Invalid packed collection outline metadata");
    }
    return { _id: row._id, _creationTime: row._creationTime, collectionSlug: row.collectionSlug,
      indexedAt: row.indexedAt, volumes };
  },
});
