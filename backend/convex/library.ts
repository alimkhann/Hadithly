import { mutation, query } from "./_generated/server";
import type { QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";

// ── Bookmarks ────────────────────────────────────────────────────────────

export const toggleBookmark = mutation({
  args: {
    hadithId: v.id("hadiths"),
    scrollOffset: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");

    const existing = await ctx.db
      .query("bookmarks")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect()
      .then((rows) => rows.find((row) => row.hadithId === args.hadithId));

    if (existing) {
      await ctx.db.delete(existing._id);
      return { bookmarked: false };
    }
    await ctx.db.insert("bookmarks", {
      userId: user._id,
      hadithId: args.hadithId,
      scrollOffset: args.scrollOffset,
      createdAt: Date.now(),
    });
    return { bookmarked: true };
  },
});

export const listBookmarks = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("bookmarks")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    return rows.sort((a, b) => b.createdAt - a.createdAt);
  },
});

// ── Favorites ────────────────────────────────────────────────────────────

export const toggleFavorite = mutation({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");

    const existing = await ctx.db
      .query("favorites")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect()
      .then((rows) => rows.find((row) => row.hadithId === args.hadithId));

    if (existing) {
      await ctx.db.delete(existing._id);
      return { favorited: false };
    }
    await ctx.db.insert("favorites", {
      userId: user._id,
      hadithId: args.hadithId,
      createdAt: Date.now(),
    });
    return { favorited: true };
  },
});

export const listFavorites = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("favorites")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    return rows.sort((a, b) => b.createdAt - a.createdAt);
  },
});

// ── Notes ────────────────────────────────────────────────────────────────

export const upsertNote = mutation({
  args: {
    hadithId: v.id("hadiths"),
    content: v.string(),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");

    const existing = await ctx.db
      .query("notes")
      .withIndex("by_user_hadith", (q) =>
        q.eq("userId", user._id).eq("hadithId", args.hadithId),
      )
      .unique();
    const now = Date.now();
    if (existing) {
      await ctx.db.patch(existing._id, {
        content: args.content,
        updatedAt: now,
      });
      return existing._id;
    }
    return await ctx.db.insert("notes", {
      userId: user._id,
      hadithId: args.hadithId,
      content: args.content,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const deleteNote = mutation({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return;
    const existing = await ctx.db
      .query("notes")
      .withIndex("by_user_hadith", (q) =>
        q.eq("userId", user._id).eq("hadithId", args.hadithId),
      )
      .unique();
    if (existing) await ctx.db.delete(existing._id);
  },
});

export const listNotes = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("notes")
      .withIndex("by_user_hadith", (q) => q.eq("userId", user._id))
      .collect();
    return rows.sort((a, b) => b.updatedAt - a.updatedAt);
  },
});

export const getNote = query({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return null;
    return await ctx.db
      .query("notes")
      .withIndex("by_user_hadith", (q) =>
        q.eq("userId", user._id).eq("hadithId", args.hadithId),
      )
      .unique();
  },
});

// ── Reading progress (private, never shared or ranked) ───────────────────

export const saveReadingProgress = mutation({
  args: {
    collectionSlug: v.string(),
    hadithId: v.id("hadiths"),
    scrollOffset: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return;

    const existing = await ctx.db
      .query("readingProgress")
      .withIndex("by_user_collection", (q) =>
        q.eq("userId", user._id).eq("collectionSlug", args.collectionSlug),
      )
      .unique();

    if (existing) {
      await ctx.db.patch(existing._id, {
        hadithId: args.hadithId,
        scrollOffset: args.scrollOffset,
        updatedAt: Date.now(),
      });
      return existing._id;
    }
    return await ctx.db.insert("readingProgress", {
      userId: user._id,
      collectionSlug: args.collectionSlug,
      hadithId: args.hadithId,
      scrollOffset: args.scrollOffset,
      updatedAt: Date.now(),
    });
  },
});

export const listReadingProgress = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    return await ctx.db
      .query("readingProgress")
      .withIndex("by_user_collection", (q) => q.eq("userId", user._id))
      .collect();
  },
});

// ── Push tokens ──────────────────────────────────────────────────────────

export const savePushToken = mutation({
  args: {
    token: v.string(),
    platform: v.union(v.literal("ios"), v.literal("android")),
    dailyTime: v.optional(v.string()),
    enabled: v.boolean(),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    await ctx.db.insert("pushTokens", {
      userId: user._id,
      token: args.token,
      platform: args.platform,
      dailyTime: args.dailyTime,
      enabled: args.enabled,
      updatedAt: Date.now(),
    });
  },
});

// ── Internal helpers ─────────────────────────────────────────────────────

async function userByClerkId(ctx: QueryCtx, clerkId: string) {
  return await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", clerkId))
    .unique();
}
