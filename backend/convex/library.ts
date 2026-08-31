import {
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import type { QueryCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
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

/**
 * Detailed shapes for the Saved tab: each row joined with a summary of its
 * hadith so the app never needs a second round trip to render a list.
 */
export const listBookmarksDetailed = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("bookmarks")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    const detailed = await Promise.all(
      rows.map(async (row) => ({
        _id: row._id,
        createdAt: row.createdAt,
        hadith: await hadithSummary(ctx, row.hadithId),
      })),
    );
    return detailed.sort((a, b) => b.createdAt - a.createdAt);
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

export const listFavoritesDetailed = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("favorites")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    const detailed = await Promise.all(
      rows.map(async (row) => ({
        _id: row._id,
        createdAt: row.createdAt,
        hadith: await hadithSummary(ctx, row.hadithId),
      })),
    );
    return detailed.sort((a, b) => b.createdAt - a.createdAt);
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

/**
 * Registers (or refreshes) a device push token. Upserts by token so
 * re-registrations never pile up rows, and never clobbers the user's
 * notification preferences — those live in setDailyNotification.
 */
export const savePushToken = mutation({
  args: {
    token: v.string(),
    platform: v.union(v.literal("ios"), v.literal("android")),
    tzOffsetMinutes: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");

    const existing = await ctx.db
      .query("pushTokens")
      .withIndex("by_token", (q) => q.eq("token", args.token))
      .unique();

    const patch = {
      userId: user._id,
      platform: args.platform,
      ...(args.tzOffsetMinutes !== undefined
        ? { tzOffsetMinutes: args.tzOffsetMinutes }
        : {}),
      updatedAt: Date.now(),
    };
    if (existing) {
      await ctx.db.patch(existing._id, patch);
      return existing._id;
    }
    return await ctx.db.insert("pushTokens", {
      token: args.token,
      dailyTime: "08:00",
      enabled: true,
      ...patch,
    });
  },
});

/** Updates the daily hadith notification preferences on all of the user's devices. */
export const setDailyNotification = mutation({
  args: {
    enabled: v.boolean(),
    dailyTime: v.string(),
    tzOffsetMinutes: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const rows = await ctx.db
      .query("pushTokens")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    const now = Date.now();
    for (const row of rows) {
      await ctx.db.patch(row._id, {
        enabled: args.enabled,
        dailyTime: args.dailyTime,
        tzOffsetMinutes: args.tzOffsetMinutes ?? row.tzOffsetMinutes,
        updatedAt: now,
      });
    }
    return rows.length;
  },
});

/** Internal: every enabled push token, for the daily send cron. */
export const listEnabledPushTokens = internalQuery({
  args: {},
  handler: async (ctx) => {
    return await ctx.db.query("pushTokens").collect();
  },
});

/** Internal: stamp a token with the local date its push went out. */
export const markPushSent = internalMutation({
  args: { tokenId: v.id("pushTokens"), sentDate: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.tokenId, { lastSentDate: args.sentDate });
  },
});

export const listNotesDetailed = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("notes")
      .withIndex("by_user_hadith", (q) => q.eq("userId", user._id))
      .collect();
    const detailed = await Promise.all(
      rows.map(async (row) => ({
        _id: row._id,
        content: row.content,
        createdAt: row.createdAt,
        updatedAt: row.updatedAt,
        hadith: await hadithSummary(ctx, row.hadithId),
      })),
    );
    return detailed.sort((a, b) => b.updatedAt - a.updatedAt);
  },
});

/** Reading progress joined with the hadith, for the continue-reading card. */
export const listReadingProgressDetailed = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return [];
    const rows = await ctx.db
      .query("readingProgress")
      .withIndex("by_user_collection", (q) => q.eq("userId", user._id))
      .collect();
    const detailed = await Promise.all(
      rows.map(async (row) => ({
        collectionSlug: row.collectionSlug,
        hadithId: row.hadithId,
        updatedAt: row.updatedAt,
        hadith: await hadithSummary(ctx, row.hadithId),
      })),
    );
    return detailed.filter((row) => row.hadith !== null);
  },
});

/** Internal helpers ─────────────────────────────────────────────────────── */

async function userByClerkId(ctx: QueryCtx, clerkId: string) {
  return await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", clerkId))
    .unique();
}

/** The hadith fields the Saved tab and Today tab render. Null when the
 * cached hadith no longer exists (e.g. the cache was cleared). */
async function hadithSummary(ctx: QueryCtx, hadithId: Doc<"hadiths">["_id"]) {
  const hadith = await ctx.db.get(hadithId);
  if (!hadith) return null;
  return {
    _id: hadith._id,
    providerHadithId: hadith.providerHadithId,
    collectionSlug: hadith.collectionSlug,
    collectionName: hadith.collectionName,
    volumeId: hadith.volumeId ?? null,
    arabicText: hadith.arabicText,
    englishText: hadith.englishText ?? null,
    referenceDisplay: hadith.referenceDisplay,
  };
}
