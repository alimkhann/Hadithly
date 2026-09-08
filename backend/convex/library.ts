import {
  internalMutation,
  internalQuery,
  mutation,
  query,
} from "./_generated/server";
import type { QueryCtx } from "./_generated/server";
import type { Doc } from "./_generated/dataModel";
import type { Id } from "./_generated/dataModel";
import type { MutationCtx } from "./_generated/server";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";
import {
  legacyReadingPosition,
  parseReadingPosition,
  readingPositionValidator,
  resolveReadingPosition,
  type ReadingPosition,
} from "./lib/readingPositions";

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
    // Current clients send position. Optional legacy fields keep deployed
    // clients valid during the R1 compatibility window.
    position: v.optional(readingPositionValidator),
    collectionSlug: v.optional(v.string()),
    hadithId: v.optional(v.id("hadiths")),
    scrollOffset: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return;

    if (args.position !== undefined) {
      const position = parseReadingPosition(args.position);
      const resolved = await resolveReadingPositionWrite(ctx, position);
      if (!resolved) throw new Error("POSITION_ANCHOR_NOT_FOUND");
      return await applyReadingPosition(
        ctx,
        user._id,
        resolved.position,
        resolved.hadith._id,
      );
    }

    if (args.collectionSlug === undefined || args.hadithId === undefined) {
      throw new Error("INVALID_READING_POSITION: expected position or legacy fields");
    }
    const hadith = await ctx.db.get(args.hadithId);
    if (!hadith || hadith.collectionSlug !== args.collectionSlug) {
      throw new Error("POSITION_ANCHOR_NOT_FOUND");
    }
    const existing = await progressByCollection(ctx, user._id, args.collectionSlug);
    if (
      existing?.hadithId === args.hadithId &&
      (existing.scrollOffset ?? 0) === (args.scrollOffset ?? 0)
    ) {
      return { status: "unchanged", rowId: existing._id };
    }
    const position = legacyReadingPosition({
      provider: hadith.provider,
      collectionSlug: hadith.collectionSlug,
      providerHadithId: hadith.providerHadithId,
      volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown",
      ...(hadith.chapterId === undefined ? {} : { chapterId: hadith.chapterId }),
      updatedAt: Date.now(),
    });
    return await applyReadingPosition(ctx, user._id, position, hadith._id);
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
      rows.map(async (row) => {
        let hadith = await ctx.db.get(row.hadithId);
        const storedPosition = row.position;
        if (!hadith && storedPosition) {
          hadith = await ctx.db
            .query("hadiths")
            .withIndex("by_provider_ref", (q) =>
              q
                .eq("provider", storedPosition.anchor.provider)
                .eq("collectionSlug", storedPosition.anchor.collectionSlug)
                .eq("providerHadithId", storedPosition.anchor.providerHadithId),
            )
            .unique();
        }
        const position = row.position ?? (hadith
          ? legacyReadingPosition({
              provider: hadith.provider,
              collectionSlug: hadith.collectionSlug,
              providerHadithId: hadith.providerHadithId,
              volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown",
              ...(hadith.chapterId === undefined ? {} : { chapterId: hadith.chapterId }),
              updatedAt: row.updatedAt,
            })
          : undefined);
        return {
          collectionSlug: row.collectionSlug,
          hadithId: hadith?._id ?? row.hadithId,
          scrollOffset: row.scrollOffset,
          updatedAt: row.updatedAt,
          position,
          hadith: hadith ? hadithSummaryFromDocument(hadith) : null,
        };
      }),
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
  return hadithSummaryFromDocument(hadith);
}

function hadithSummaryFromDocument(hadith: Doc<"hadiths">) {
  return {
    _id: hadith._id,
    provider: hadith.provider,
    canonicalId: hadith.canonicalId,
    providerHadithId: hadith.providerHadithId,
    collectionSlug: hadith.collectionSlug,
    collectionName: hadith.collectionName,
    volumeId: hadith.volumeId ?? null,
    chapterId: hadith.chapterId ?? null,
    arabicText: hadith.arabicText,
    englishText: hadith.englishText ?? null,
    referenceDisplay: hadith.referenceDisplay,
  };
}

async function progressByCollection(
  ctx: MutationCtx,
  userId: Id<"users">,
  collectionSlug: string,
) {
  return await ctx.db
    .query("readingProgress")
    .withIndex("by_user_collection", (q) =>
      q.eq("userId", userId).eq("collectionSlug", collectionSlug),
    )
    .unique();
}

export async function resolveReadingPositionWrite(
  ctx: QueryCtx,
  position: ReadingPosition,
): Promise<{ position: ReadingPosition; hadith: Doc<"hadiths"> } | null> {
  const exact = await ctx.db
    .query("hadiths")
    .withIndex("by_provider_ref", (q) =>
      q
        .eq("provider", position.anchor.provider)
        .eq("collectionSlug", position.anchor.collectionSlug)
        .eq("providerHadithId", position.anchor.providerHadithId),
    )
    .unique();
  if (exact) return { position, hadith: exact };

  const candidates = await ctx.db
    .query("hadiths")
    .withIndex("by_collection", (q) =>
      q
        .eq("provider", position.anchor.provider)
        .eq("collectionSlug", position.anchor.collectionSlug),
    )
    .collect();
  if (candidates.length === 0) return null;
  const resolution = resolveReadingPosition(position, {
    contentVersion: "legacy",
    layoutSignature: "legacy",
    pages: [{
      pageKey: "legacy",
      displayPageIndex: 1,
      anchors: candidates.map((hadith) => ({
        provider: hadith.provider,
        collectionSlug: hadith.collectionSlug,
        providerHadithId: hadith.providerHadithId,
        volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown",
        ...(hadith.chapterId === undefined ? {} : { chapterId: hadith.chapterId }),
      })),
    }],
  });
  const resolvedAnchor = resolution.anchor;
  if (!resolvedAnchor) return null;
  const hadith = candidates.find((candidate) =>
    candidate.provider === resolvedAnchor.provider &&
    candidate.collectionSlug === resolvedAnchor.collectionSlug &&
    candidate.providerHadithId === resolvedAnchor.providerHadithId
  );
  if (!hadith) return null;
  return {
    position: legacyReadingPosition({
      provider: hadith.provider,
      collectionSlug: hadith.collectionSlug,
      providerHadithId: hadith.providerHadithId,
      volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown",
      ...(hadith.chapterId === undefined ? {} : { chapterId: hadith.chapterId }),
      updatedAt: position.updatedAt,
    }),
    hadith,
  };
}

export async function applyReadingPosition(
  ctx: MutationCtx,
  userId: Id<"users">,
  position: ReadingPosition,
  hadithId: Id<"hadiths">,
): Promise<{ status: "applied" | "unchanged"; rowId: Id<"readingProgress"> }> {
  const existing = await progressByCollection(
    ctx,
    userId,
    position.anchor.collectionSlug,
  );
  if (existing && existing.updatedAt >= position.updatedAt) {
    return { status: "unchanged", rowId: existing._id };
  }
  const projection = {
    collectionSlug: position.anchor.collectionSlug,
    position,
    hadithId,
    bookId: position.volumeId,
    scrollOffset: position.rawPageOffset,
    updatedAt: position.updatedAt,
  };
  if (existing) {
    await ctx.db.patch(existing._id, projection);
    return { status: "applied", rowId: existing._id };
  }
  const rowId = await ctx.db.insert("readingProgress", {
    userId,
    ...projection,
  });
  return { status: "applied", rowId };
}
