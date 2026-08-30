import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const savePushToken = mutation({
  args: {
    userId: v.id("users"),
    token: v.string(),
    platform: v.union(v.literal("ios"), v.literal("android"), v.literal("web")),
    dailyTime: v.optional(v.string()),
    enabled: v.boolean(),
  },
  handler: async (ctx, args) =>
    await ctx.db.insert("pushTokens", {
      ...args,
      updatedAt: Date.now(),
    }),
});

export const listEnabledPushTokens = query({
  args: { limit: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const tokens = await ctx.db.query("pushTokens").collect();
    return tokens.filter((token) => token.enabled).slice(0, args.limit ?? 1000);
  },
});

export const addBookmark = mutation({
  args: {
    userId: v.id("users"),
    hadithId: v.id("hadiths"),
    scrollOffset: v.optional(v.number()),
  },
  handler: async (ctx, args) =>
    await ctx.db.insert("bookmarks", {
      ...args,
      createdAt: Date.now(),
    }),
});

export const upsertNote = mutation({
  args: {
    userId: v.id("users"),
    hadithId: v.id("hadiths"),
    content: v.string(),
  },
  handler: async (ctx, args) => {
    const existing = await ctx.db
      .query("notes")
      .withIndex("by_user_hadith", (q) =>
        q.eq("userId", args.userId).eq("hadithId", args.hadithId),
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
      ...args,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const listBookmarks = query({
  args: { userId: v.id("users") },
  handler: async (ctx, args) =>
    await ctx.db
      .query("bookmarks")
      .withIndex("by_user", (q) => q.eq("userId", args.userId))
      .collect(),
});
