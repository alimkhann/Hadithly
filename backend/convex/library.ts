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
import { DEFAULT_COLLECTION_ORDER } from "./lib/sunnahNow";
import {
  DAILY_TIME_PATTERN,
  assertIanaTimezone,
  normalizeDeliveryBucket,
} from "./lib/notifyContent";
import { canonicalizeLocaleTag } from "./lib/preferences";
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
 *
 * N1: clients send their IANA timezone plus UI and translation locales so
 * the cron can schedule in true local time and materialize the body in the
 * chosen translation. tzOffsetMinutes is a legacy read-only fallback.
 */
export const savePushToken = mutation({
  args: {
    token: v.string(),
    platform: v.union(v.literal("ios"), v.literal("android")),
    timezone: v.optional(v.string()),
    uiLocale: v.optional(v.string()),
    translationLocale: v.optional(v.string()),
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

    if (args.timezone !== undefined) assertIanaTimezone(args.timezone);
    for (const tag of [args.uiLocale, args.translationLocale]) {
      if (tag !== undefined && canonicalizeLocaleTag(tag) === null) {
        throw new Error(`Invalid locale: ${tag}`);
      }
    }

    const now = Date.now();
    const patch = {
      userId: user._id,
      platform: args.platform,
      ...(args.timezone !== undefined ? { timezone: args.timezone } : {}),
      ...(args.uiLocale !== undefined ? { uiLocale: args.uiLocale } : {}),
      ...(args.translationLocale !== undefined
        ? { translationLocale: args.translationLocale }
        : {}),
      ...(args.tzOffsetMinutes !== undefined
        ? { tzOffsetMinutes: args.tzOffsetMinutes }
        : {}),
      lastSeenAt: now,
      updatedAt: now,
    };
    if (existing) {
      // Re-registration proves the token is alive: clear retry state so a
      // previously flaky device converges back to normal delivery.
      await ctx.db.patch(existing._id, {
        ...patch,
        consecutiveFailures: 0,
        nextRetryAt: undefined,
        lastError: undefined,
      });
      return existing._id;
    }
    return await ctx.db.insert("pushTokens", {
      token: args.token,
      dailyTime: "08:00",
      deliveryBucket: normalizeDeliveryBucket("08:00") ?? "08:00",
      enabled: true,
      consecutiveFailures: 0,
      ...patch,
    });
  },
});

/** Updates the daily hadith notification preferences on all of the user's devices. */
export const setDailyNotification = mutation({
  args: {
    enabled: v.boolean(),
    dailyTime: v.string(),
    timezone: v.optional(v.string()),
    uiLocale: v.optional(v.string()),
    translationLocale: v.optional(v.string()),
    tzOffsetMinutes: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    if (!DAILY_TIME_PATTERN.test(args.dailyTime.trim())) {
      throw new Error(`Invalid dailyTime: ${args.dailyTime}`);
    }
    if (args.timezone !== undefined) {
      assertIanaTimezone(args.timezone);
    }
    for (const tag of [args.uiLocale, args.translationLocale]) {
      if (tag !== undefined && canonicalizeLocaleTag(tag) === null) {
        throw new Error(`Invalid locale: ${tag}`);
      }
    }
    const rows = await ctx.db
      .query("pushTokens")
      .withIndex("by_user", (q) => q.eq("userId", user._id))
      .collect();
    const bucket = normalizeDeliveryBucket(args.dailyTime);
    if (bucket === null) throw new Error(`Invalid dailyTime: ${args.dailyTime}`);
    const now = Date.now();
    for (const row of rows) {
      await ctx.db.patch(row._id, {
        enabled: args.enabled,
        dailyTime: args.dailyTime,
        deliveryBucket: bucket,
        timezone: args.timezone ?? row.timezone,
        uiLocale: args.uiLocale ?? row.uiLocale,
        translationLocale: args.translationLocale ?? row.translationLocale,
        tzOffsetMinutes: args.tzOffsetMinutes ?? row.tzOffsetMinutes,
        // A preference change re-arms delivery for today: the user asked
        // for a new time, so today's stamp must not suppress it.
        lastSentDate: undefined,
        consecutiveFailures: 0,
        nextRetryAt: undefined,
        lastError: undefined,
        lastSeenAt: now,
        updatedAt: now,
      });
    }
    return rows.length;
  },
});

/**
 * Internal: one bounded page of enabled tokens in a delivery bucket, for
 * the daily send cron. Indexed — never scans the whole table.
 */
export const listBucketPage = internalQuery({
  args: {
    bucket: v.string(),
    cursor: v.optional(v.string()),
    limit: v.number(),
  },
  handler: async (ctx, args) => {
    const take = Math.min(Math.max(args.limit, 1), 500);
    const page = await ctx.db
      .query("pushTokens")
      .withIndex("by_enabled_bucket", (q) =>
        q.eq("enabled", true).eq("deliveryBucket", args.bucket),
      )
      .order("asc")
      .paginate({ cursor: args.cursor ?? null, numItems: take });
    return {
      rows: page.page,
      isDone: page.isDone,
      cursor: page.continueCursor ?? undefined,
    };
  },
});

/** Internal: stamp a token with the local date its push went out. */
export const markPushSent = internalMutation({
  args: { tokenId: v.id("pushTokens"), sentDate: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.tokenId, {
      lastSentDate: args.sentDate,
      consecutiveFailures: 0,
      nextRetryAt: undefined,
      lastError: undefined,
      lastSeenAt: Date.now(),
    });
  },
});

/** Internal: record a transient send failure with bounded retry state. */
export const recordPushFailure = internalMutation({
  args: {
    tokenId: v.id("pushTokens"),
    error: v.string(),
    nextRetryAt: v.number(),
  },
  handler: async (ctx, args) => {
    const row = await ctx.db.get(args.tokenId);
    if (!row) return;
    await ctx.db.patch(args.tokenId, {
      consecutiveFailures: (row.consecutiveFailures ?? 0) + 1,
      nextRetryAt: args.nextRetryAt,
      lastError: args.error.slice(0, 300),
      lastSeenAt: Date.now(),
    });
  },
});

/** Internal: delete a token the provider reports as permanently dead. */
export const removeStaleToken = internalMutation({
  args: { tokenId: v.id("pushTokens"), reason: v.string() },
  handler: async (ctx, args) => {
    await ctx.db.delete(args.tokenId);
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

// ── H3 unified Saved and private folders ─────────────────────────────────

const FOLDER_NAME_LIMIT = 64;

export function normalizedFolderName(name: string): { name: string; normalizedName: string } {
  const displayName = name.trim().normalize("NFC");
  if (!displayName) throw new Error("FOLDER_NAME_EMPTY");
  if (/\p{Cc}/u.test(displayName)) throw new Error("FOLDER_NAME_CONTROL_CHARACTER");
  if (Array.from(displayName).length > FOLDER_NAME_LIMIT) {
    throw new Error("FOLDER_NAME_TOO_LONG");
  }
  return { name: displayName, normalizedName: displayName.toLocaleLowerCase() };
}

async function savedItemByHadith(
  ctx: QueryCtx | MutationCtx,
  userId: Id<"users">,
  hadithId: Id<"hadiths">,
) {
  return await ctx.db
    .query("savedItems")
    .withIndex("by_user_hadith", (q) => q.eq("userId", userId).eq("hadithId", hadithId))
    .unique();
}

async function legacyBookmarksByHadith(
  ctx: MutationCtx,
  userId: Id<"users">,
  hadithId: Id<"hadiths">,
) {
  return (await ctx.db.query("bookmarks").withIndex("by_user", (q) => q.eq("userId", userId)).collect())
    .filter((row) => row.hadithId === hadithId);
}

async function legacyFavoritesByHadith(
  ctx: MutationCtx,
  userId: Id<"users">,
  hadithId: Id<"hadiths">,
) {
  return (await ctx.db.query("favorites").withIndex("by_user", (q) => q.eq("userId", userId)).collect())
    .filter((row) => row.hadithId === hadithId);
}

async function ensureSavedItem(
  ctx: MutationCtx,
  userId: Id<"users">,
  hadithId: Id<"hadiths">,
) {
  const existing = await savedItemByHadith(ctx, userId, hadithId);
  if (existing) return existing;
  const now = Date.now();
  const _id = await ctx.db.insert("savedItems", { userId, hadithId, createdAt: now, updatedAt: now });
  const created = await ctx.db.get(_id);
  if (!created) throw new Error("SAVED_ITEM_CREATE_FAILED");
  return created;
}

export async function materializeLegacySavedItem(
  ctx: MutationCtx,
  userId: Id<"users">,
  hadithId: Id<"hadiths">,
) {
  const item = await ensureSavedItem(ctx, userId, hadithId);
  const [bookmarks, favorites, note] = await Promise.all([
    legacyBookmarksByHadith(ctx, userId, hadithId),
    legacyFavoritesByHadith(ctx, userId, hadithId),
    ctx.db.query("notes").withIndex("by_user_hadith", (q) =>
      q.eq("userId", userId).eq("hadithId", hadithId),
    ).unique(),
  ]);
  const bookmarkCreatedAt = bookmarks.reduce<number | undefined>(
    (earliest, row) => Math.min(earliest ?? row.createdAt, row.createdAt),
    item.bookmarkCreatedAt,
  );
  const favoriteCreatedAt = favorites.reduce<number | undefined>(
    (earliest, row) => Math.min(earliest ?? row.createdAt, row.createdAt),
    item.favoriteCreatedAt,
  );
  const noteIsNewer = note !== null && (item.noteUpdatedAt === undefined || note.updatedAt > item.noteUpdatedAt);
  const patch = {
    ...(bookmarkCreatedAt === undefined ? {} : { bookmarkCreatedAt }),
    ...(favoriteCreatedAt === undefined ? {} : { favoriteCreatedAt }),
    ...(noteIsNewer ? {
      noteContent: note.content,
      noteCreatedAt: note.createdAt,
      noteUpdatedAt: note.updatedAt,
    } : {}),
  };
  if (Object.keys(patch).length > 0) {
    const updatedAt = Math.max(
      item.updatedAt,
      bookmarkCreatedAt ?? -Infinity,
      favoriteCreatedAt ?? -Infinity,
      note?.updatedAt ?? -Infinity,
    );
    await ctx.db.patch(item._id, { ...patch, updatedAt });
    return { ...item, ...patch, updatedAt };
  }
  return item;
}

async function removeEmptySavedItem(ctx: MutationCtx, item: Doc<"savedItems">) {
  if (
    item.bookmarkCreatedAt === undefined &&
    item.favoriteCreatedAt === undefined &&
    item.noteContent === undefined
  ) {
    await ctx.db.delete(item._id);
  }
}

/** New-client bookmark mutation. It dual-writes the legacy projection until the rollout closes. */
export const toggleSavedBookmark = mutation({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const item = await materializeLegacySavedItem(ctx, user._id, args.hadithId);
    const legacy = await legacyBookmarksByHadith(ctx, user._id, args.hadithId);
    if (item.bookmarkCreatedAt !== undefined) {
      await ctx.db.patch(item._id, { bookmarkCreatedAt: undefined, updatedAt: Date.now() });
      await Promise.all(legacy.map((row) => ctx.db.delete(row._id)));
      await removeEmptySavedItem(ctx, { ...item, bookmarkCreatedAt: undefined });
      return { bookmarked: false };
    }
    const createdAt = Date.now();
    await ctx.db.patch(item._id, { bookmarkCreatedAt: createdAt, updatedAt: createdAt });
    if (legacy.length === 0) await ctx.db.insert("bookmarks", { userId: user._id, hadithId: args.hadithId, createdAt });
    return { bookmarked: true };
  },
});

/** New-client favorite mutation. It dual-writes the legacy projection until the rollout closes. */
export const toggleSavedFavorite = mutation({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const item = await materializeLegacySavedItem(ctx, user._id, args.hadithId);
    const legacy = await legacyFavoritesByHadith(ctx, user._id, args.hadithId);
    if (item.favoriteCreatedAt !== undefined) {
      await ctx.db.patch(item._id, { favoriteCreatedAt: undefined, updatedAt: Date.now() });
      await Promise.all(legacy.map((row) => ctx.db.delete(row._id)));
      await removeEmptySavedItem(ctx, { ...item, favoriteCreatedAt: undefined });
      return { favorited: false };
    }
    const createdAt = Date.now();
    await ctx.db.patch(item._id, { favoriteCreatedAt: createdAt, updatedAt: createdAt });
    if (legacy.length === 0) await ctx.db.insert("favorites", { userId: user._id, hadithId: args.hadithId, createdAt });
    return { favorited: true };
  },
});

export const upsertSavedNote = mutation({
  args: { hadithId: v.id("hadiths"), content: v.string() },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const item = await ensureSavedItem(ctx, user._id, args.hadithId);
    const now = Date.now();
    const createdAt = item.noteCreatedAt ?? now;
    await ctx.db.patch(item._id, { noteContent: args.content, noteCreatedAt: createdAt, noteUpdatedAt: now, updatedAt: now });
    const legacy = await ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", user._id).eq("hadithId", args.hadithId)).unique();
    if (legacy) await ctx.db.patch(legacy._id, { content: args.content, updatedAt: now });
    else await ctx.db.insert("notes", { userId: user._id, hadithId: args.hadithId, content: args.content, createdAt, updatedAt: now });
  },
});

export const deleteSavedNote = mutation({
  args: { hadithId: v.id("hadiths") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return;
    const item = await savedItemByHadith(ctx, user._id, args.hadithId);
    if (item) {
      await ctx.db.patch(item._id, { noteContent: undefined, noteCreatedAt: undefined, noteUpdatedAt: undefined, updatedAt: Date.now() });
      await removeEmptySavedItem(ctx, { ...item, noteContent: undefined, noteCreatedAt: undefined, noteUpdatedAt: undefined });
    }
    const legacy = await ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", user._id).eq("hadithId", args.hadithId)).unique();
    if (legacy) await ctx.db.delete(legacy._id);
  },
});

/** Idempotent inverse used by the short-lived Saved undo banner. */
export const restoreSavedFacet = mutation({
  args: {
    hadithId: v.id("hadiths"),
    facet: v.union(v.literal("bookmark"), v.literal("favorite"), v.literal("note")),
    createdAt: v.number(),
    content: v.optional(v.string()),
    updatedAt: v.optional(v.number()),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const item = await materializeLegacySavedItem(ctx, user._id, args.hadithId);
    if (args.facet === "bookmark") {
      await ctx.db.patch(item._id, { bookmarkCreatedAt: item.bookmarkCreatedAt ?? args.createdAt, updatedAt: Date.now() });
      const legacy = await legacyBookmarksByHadith(ctx, user._id, args.hadithId);
      if (legacy.length === 0) await ctx.db.insert("bookmarks", { userId: user._id, hadithId: args.hadithId, createdAt: args.createdAt });
    } else if (args.facet === "favorite") {
      await ctx.db.patch(item._id, { favoriteCreatedAt: item.favoriteCreatedAt ?? args.createdAt, updatedAt: Date.now() });
      const legacy = await legacyFavoritesByHadith(ctx, user._id, args.hadithId);
      if (legacy.length === 0) await ctx.db.insert("favorites", { userId: user._id, hadithId: args.hadithId, createdAt: args.createdAt });
    } else {
      if (args.content === undefined || args.updatedAt === undefined) throw new Error("INVALID_NOTE_RESTORE");
      const noteUpdatedAt = Math.max(item.noteUpdatedAt ?? -Infinity, args.updatedAt);
      if (noteUpdatedAt === args.updatedAt) await ctx.db.patch(item._id, { noteContent: args.content, noteCreatedAt: args.createdAt, noteUpdatedAt: args.updatedAt, updatedAt: Date.now() });
      const legacy = await ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", user._id).eq("hadithId", args.hadithId)).unique();
      if (!legacy) await ctx.db.insert("notes", { userId: user._id, hadithId: args.hadithId, content: args.content, createdAt: args.createdAt, updatedAt: args.updatedAt });
    }
    return true;
  },
});

export const createSavedFolder = mutation({
  args: { name: v.string() },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const name = normalizedFolderName(args.name);
    const existing = await ctx.db.query("savedFolders").withIndex("by_user_normalized_name", (q) => q.eq("userId", user._id).eq("normalizedName", name.normalizedName)).unique();
    if (existing) throw new Error("FOLDER_NAME_TAKEN");
    const now = Date.now();
    return await ctx.db.insert("savedFolders", { userId: user._id, ...name, createdAt: now, updatedAt: now });
  },
});

export const assignSavedFolder = mutation({
  args: { hadithId: v.id("hadiths"), folderId: v.optional(v.id("savedFolders")) },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    if (args.folderId !== undefined) {
      const folder = await ctx.db.get(args.folderId);
      if (!folder || folder.userId !== user._id) throw new Error("SAVED_FOLDER_NOT_FOUND");
    }
    const item = await materializeLegacySavedItem(ctx, user._id, args.hadithId);
    if (
      item.bookmarkCreatedAt === undefined &&
      item.favoriteCreatedAt === undefined &&
      item.noteContent === undefined
    ) throw new Error("SAVED_ITEM_NOT_FOUND");
    const now = Date.now();
    await ctx.db.patch(item._id, { folderId: args.folderId, folderUpdatedAt: now, updatedAt: now });
  },
});

export const deleteSavedFolder = mutation({
  args: { folderId: v.id("savedFolders") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return null;
    const folder = await ctx.db.get(args.folderId);
    if (!folder || folder.userId !== user._id) throw new Error("SAVED_FOLDER_NOT_FOUND");
    const items = await ctx.db.query("savedItems").withIndex("by_folder", (q) => q.eq("folderId", folder._id)).collect();
    const deletedAt = Date.now();
    for (const item of items) await ctx.db.patch(item._id, {
      folderId: undefined,
      folderUpdatedAt: deletedAt,
      updatedAt: deletedAt,
    });
    await ctx.db.delete(folder._id);
    return { name: folder.name, hadithIds: items.map((item) => item.hadithId), deletedAt };
  },
});

/** Restores a just-deleted private folder without clobbering a newer move. */
export const restoreSavedFolder = mutation({
  args: {
    name: v.string(),
    hadithIds: v.array(v.id("hadiths")),
    deletedAt: v.number(),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) throw new Error("User not found. Call users:ensureCurrentUser first.");
    const name = normalizedFolderName(args.name);
    let folder = await ctx.db.query("savedFolders")
      .withIndex("by_user_normalized_name", (q) => q.eq("userId", user._id).eq("normalizedName", name.normalizedName))
      .unique();
    if (!folder) {
      const now = Date.now();
      const folderId = await ctx.db.insert("savedFolders", { userId: user._id, ...name, createdAt: now, updatedAt: now });
      folder = await ctx.db.get(folderId);
      if (!folder) throw new Error("SAVED_FOLDER_CREATE_FAILED");
    }
    const restoredHadithIds: Id<"hadiths">[] = [];
    for (const hadithId of args.hadithIds) {
      const item = await savedItemByHadith(ctx, user._id, hadithId);
      if (!item || item.folderId !== undefined || item.folderUpdatedAt !== args.deletedAt) continue;
      await ctx.db.patch(item._id, { folderId: folder._id, folderUpdatedAt: Date.now(), updatedAt: Date.now() });
      restoredHadithIds.push(hadithId);
    }
    return { folderId: folder._id, restoredHadithIds };
  },
});

export const listSavedSnapshot = query({
  args: {},
  handler: async (ctx) => {
    const identity = await requireIdentity(ctx);
    const user = await userByClerkId(ctx, identity.clerkId);
    if (!user) return { folders: [], items: [] };
    const [items, folders, bookmarks, favorites, notes] = await Promise.all([
      ctx.db.query("savedItems").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("savedFolders").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("bookmarks").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("favorites").withIndex("by_user", (q) => q.eq("userId", user._id)).collect(),
      ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", user._id)).collect(),
    ]);
    const merged = new Map<string, {
      hadithId: Id<"hadiths">; bookmarkCreatedAt?: number; favoriteCreatedAt?: number; noteContent?: string; noteCreatedAt?: number; noteUpdatedAt?: number; folderId?: Id<"savedFolders">; createdAt: number; updatedAt: number;
    }>();
    for (const item of items) merged.set(item.hadithId, { ...item });
    for (const row of bookmarks) {
      const item = merged.get(row.hadithId) ?? { hadithId: row.hadithId, createdAt: row.createdAt, updatedAt: row.createdAt };
      item.bookmarkCreatedAt = Math.min(item.bookmarkCreatedAt ?? row.createdAt, row.createdAt);
      item.createdAt = Math.min(item.createdAt, row.createdAt);
      merged.set(row.hadithId, item);
    }
    for (const row of favorites) {
      const item = merged.get(row.hadithId) ?? { hadithId: row.hadithId, createdAt: row.createdAt, updatedAt: row.createdAt };
      item.favoriteCreatedAt = Math.min(item.favoriteCreatedAt ?? row.createdAt, row.createdAt);
      item.createdAt = Math.min(item.createdAt, row.createdAt);
      merged.set(row.hadithId, item);
    }
    for (const row of notes) {
      const item = merged.get(row.hadithId) ?? { hadithId: row.hadithId, createdAt: row.createdAt, updatedAt: row.updatedAt };
      if ((item.noteUpdatedAt ?? -Infinity) < row.updatedAt) {
        item.noteContent = row.content;
        item.noteCreatedAt = row.createdAt;
        item.noteUpdatedAt = row.updatedAt;
      }
      item.createdAt = Math.min(item.createdAt, row.createdAt);
      item.updatedAt = Math.max(item.updatedAt, row.updatedAt);
      merged.set(row.hadithId, item);
    }
    const detailed = await Promise.all([...merged.values()].map(async (item) => ({
      ...item,
      hadith: await hadithSummary(ctx, item.hadithId),
    })));
    return {
      folders: folders.sort((a, b) => a.createdAt - b.createdAt).map((folder) => ({ _id: folder._id, name: folder.name, createdAt: folder.createdAt })),
      items: detailed.filter((item) => item.hadith !== null).sort((a, b) => b.updatedAt - a.updatedAt),
    };
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

/**
 * Private per-collection progress for Library. The outline is the authority
 * for total counts; a semantic position supplies the latest hadith anchor.
 * Guests receive the public count state without any user data.
 */
export const listCollectionProgressSummaries = query({
  args: {},
  handler: async (ctx) => {
    const outlines = await ctx.db.query("collectionOutlines").collect();
    const outlineBySlug = new Map(outlines.map((outline) => [outline.collectionSlug, outline]));
    const rawIdentity = await ctx.auth.getUserIdentity();
    const clerkId = identitySubject(rawIdentity);
    const user = clerkId ? await userByClerkId(ctx, clerkId) : null;
    const progress = user
      ? await ctx.db
        .query("readingProgress")
        .withIndex("by_user_collection", (q) => q.eq("userId", user._id))
        .collect()
      : [];
    const progressBySlug = new Map(progress.map((row) => [row.collectionSlug, row]));

    return Promise.all(DEFAULT_COLLECTION_ORDER.map(async (collectionSlug) => {
      const outline = outlineBySlug.get(collectionSlug);
      const totalHadiths = outline?.volumes.reduce((total, volume) => total + volume.hadithCount, 0);
      const row = progressBySlug.get(collectionSlug);
      if (!outline || !totalHadiths) {
        return { collectionSlug, state: "unavailable" as const, totalHadiths: null, readOrdinal: null };
      }
      if (!row) {
        return { collectionSlug, state: "unopened" as const, totalHadiths, readOrdinal: null };
      }
      const hadith = await ctx.db.get(row.hadithId);
      const anchorId = row.position?.anchor.providerHadithId ?? hadith?.providerHadithId;
      const readOrdinal = anchorId ? parseOrdinal(anchorId) : null;
      if (!hadith || hadith.collectionSlug !== collectionSlug || readOrdinal === null) {
        return { collectionSlug, state: "stale" as const, totalHadiths, readOrdinal: null };
      }
      return {
        collectionSlug,
        state: readOrdinal >= totalHadiths ? "completed" as const : "in_progress" as const,
        totalHadiths,
        readOrdinal,
      };
    }));
  },
});

/** Internal helpers ─────────────────────────────────────────────────────── */

async function userByClerkId(ctx: QueryCtx, clerkId: string) {
  return await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", clerkId))
    .unique();
}

function identitySubject(value: unknown): string | null {
  if (typeof value !== "object" || value === null) return null;
  const subject = Reflect.get(value, "subject");
  return typeof subject === "string" && subject.length > 0 ? subject : null;
}

function parseOrdinal(providerHadithId: string): number | null {
  if (!/^\d+$/.test(providerHadithId)) return null;
  const ordinal = Number(providerHadithId);
  return Number.isSafeInteger(ordinal) && ordinal > 0 ? ordinal : null;
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
