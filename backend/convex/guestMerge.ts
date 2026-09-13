import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";
import type { Doc } from "./_generated/dataModel";
import type { Id } from "./_generated/dataModel";
import type { ReadingPosition } from "./lib/readingPositions";
import {
  legacyReadingPosition,
  parseReadingPosition,
  readingPositionValidator,
} from "./lib/readingPositions";
import { applyReadingPosition, resolveReadingPositionWrite } from "./library";
import { materializeLegacySavedItem, normalizedFolderName } from "./library";

/**
 * Merges guest-mode items collected on-device (SwiftData) into the signed-in
 * user's Convex records. Called once right after the first sign-in. The client
 * clears its local store only after this succeeds, so the operation is
 * idempotent: re-sending already-merged items is a no-op.
 *
 * Duplicate bookmarks are skipped. Conflicting notes keep whichever version
 * has the later updatedAt, so a newer offline edit always wins.
 */
export const mergeGuestData = mutation({
  args: {
    bookmarks: v.array(
      v.object({
        hadithId: v.id("hadiths"),
        createdAt: v.number(),
      }),
    ),
    notes: v.array(
      v.object({
        hadithId: v.id("hadiths"),
        content: v.string(),
        createdAt: v.number(),
        updatedAt: v.number(),
      }),
    ),
    // Added in Phase 3; optional so older clients keep working.
    favorites: v.optional(
      v.array(
        v.object({
          hadithId: v.id("hadiths"),
          createdAt: v.number(),
        }),
      ),
    ),
    readingProgress: v.optional(
      v.array(
        v.union(
          v.object({ position: readingPositionValidator }),
          v.object({
            collectionSlug: v.string(),
            hadithId: v.id("hadiths"),
            updatedAt: v.number(),
          }),
        ),
      ),
    ),
    // Optional V2 Saved projection. Older clients continue to send only the
    // legacy arrays above. Local ids are request-scoped and never become
    // server identities.
    savedFolders: v.optional(v.array(v.object({
      localId: v.string(),
      name: v.string(),
      createdAt: v.number(),
    }))),
    savedItems: v.optional(v.array(v.object({
      hadithId: v.id("hadiths"),
      bookmarkCreatedAt: v.optional(v.number()),
      favoriteCreatedAt: v.optional(v.number()),
      noteContent: v.optional(v.string()),
      noteCreatedAt: v.optional(v.number()),
      noteUpdatedAt: v.optional(v.number()),
      folderLocalId: v.optional(v.string()),
      createdAt: v.number(),
      updatedAt: v.number(),
    }))),
  },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
      .unique();
    if (!user) {
      throw new Error(
        "User not found: call users:ensureCurrentUser before merging guest data",
      );
    }

    // Resolve guest folders before applying items. Retrying the same payload
    // reuses the owner's normalized name, so it never creates a duplicate.
    const folderIds = new Map<string, Id<"savedFolders">>();
    for (const incoming of args.savedFolders ?? []) {
      const name = normalizedFolderName(incoming.name);
      const existing = await ctx.db.query("savedFolders")
        .withIndex("by_user_normalized_name", (q) => q.eq("userId", user._id).eq("normalizedName", name.normalizedName))
        .unique();
      const folderId = existing?._id ?? await ctx.db.insert("savedFolders", {
        userId: user._id,
        ...name,
        createdAt: incoming.createdAt,
        updatedAt: incoming.createdAt,
      });
      folderIds.set(incoming.localId, folderId);
    }

    let bookmarksMerged = 0;
    let bookmarksSkipped = 0;
    for (const item of args.bookmarks) {
      const hadith = await ctx.db.get(item.hadithId);
      if (!hadith) {
        bookmarksSkipped += 1;
        continue;
      }
      const existing = await ctx.db
        .query("bookmarks")
        .withIndex("by_user", (q) => q.eq("userId", user._id))
        .collect()
        .then((rows) => rows.find((row) => row.hadithId === item.hadithId));
      if (existing) {
        bookmarksSkipped += 1;
        continue;
      }
      await ctx.db.insert("bookmarks", {
        userId: user._id,
        hadithId: item.hadithId,
        createdAt: item.createdAt,
      });
      bookmarksMerged += 1;
    }

    let notesMerged = 0;
    let notesSkipped = 0;
    for (const item of args.notes) {
      const hadith = await ctx.db.get(item.hadithId);
      if (!hadith) {
        notesSkipped += 1;
        continue;
      }
      const existing = await ctx.db
        .query("notes")
        .withIndex("by_user_hadith", (q) =>
          q.eq("userId", user._id).eq("hadithId", item.hadithId),
        )
        .unique();
      if (existing) {
        if (existing.updatedAt >= item.updatedAt) {
          notesSkipped += 1;
          continue;
        }
        await ctx.db.patch(existing._id, {
          content: item.content,
          updatedAt: item.updatedAt,
        });
        notesMerged += 1;
        continue;
      }
      await ctx.db.insert("notes", {
        userId: user._id,
        hadithId: item.hadithId,
        content: item.content,
        createdAt: item.createdAt,
        updatedAt: item.updatedAt,
      });
      notesMerged += 1;
    }

    let favoritesMerged = 0;
    let favoritesSkipped = 0;
    for (const item of args.favorites ?? []) {
      const hadith = await ctx.db.get(item.hadithId);
      if (!hadith) {
        favoritesSkipped += 1;
        continue;
      }
      const existing = await ctx.db
        .query("favorites")
        .withIndex("by_user", (q) => q.eq("userId", user._id))
        .collect()
        .then((rows) => rows.find((row) => row.hadithId === item.hadithId));
      if (existing) {
        favoritesSkipped += 1;
        continue;
      }
      await ctx.db.insert("favorites", {
        userId: user._id,
        hadithId: item.hadithId,
        createdAt: item.createdAt,
      });
      favoritesMerged += 1;
    }

    // Fold every effective guest Saved item into the canonical record after
    // writing legacy projections. This keeps old payloads and new payloads
    // convergent and makes the legacy tables readable throughout rollout.
    let savedItemsMerged = 0;
    let savedItemsSkipped = 0;
    for (const incoming of args.savedItems ?? []) {
      if (
        incoming.bookmarkCreatedAt === undefined &&
        incoming.favoriteCreatedAt === undefined &&
        incoming.noteContent === undefined
      ) {
        savedItemsSkipped += 1;
        continue;
      }
      const hadith = await ctx.db.get(incoming.hadithId);
      if (!hadith) {
        savedItemsSkipped += 1;
        continue;
      }
      const item = await materializeLegacySavedItem(ctx, user._id, incoming.hadithId);
      const bookmarkCreatedAt = incoming.bookmarkCreatedAt === undefined
        ? item.bookmarkCreatedAt
        : Math.min(item.bookmarkCreatedAt ?? incoming.bookmarkCreatedAt, incoming.bookmarkCreatedAt);
      const favoriteCreatedAt = incoming.favoriteCreatedAt === undefined
        ? item.favoriteCreatedAt
        : Math.min(item.favoriteCreatedAt ?? incoming.favoriteCreatedAt, incoming.favoriteCreatedAt);
      const incomingNoteWins = incoming.noteContent !== undefined && incoming.noteUpdatedAt !== undefined
        && (item.noteUpdatedAt === undefined || incoming.noteUpdatedAt > item.noteUpdatedAt);
      const folderId = incoming.folderLocalId === undefined
        ? item.folderId
        : folderIds.get(incoming.folderLocalId) ?? item.folderId;
      const changed = bookmarkCreatedAt !== item.bookmarkCreatedAt
        || favoriteCreatedAt !== item.favoriteCreatedAt
        || incomingNoteWins
        || folderId !== item.folderId;
      if (!changed) {
        savedItemsSkipped += 1;
        continue;
      }
      const updatedAt = Math.max(item.updatedAt, incoming.updatedAt, incoming.noteUpdatedAt ?? -Infinity);
      await ctx.db.patch(item._id, {
        ...(bookmarkCreatedAt === undefined ? {} : { bookmarkCreatedAt }),
        ...(favoriteCreatedAt === undefined ? {} : { favoriteCreatedAt }),
        ...(incomingNoteWins ? {
          noteContent: incoming.noteContent,
          noteCreatedAt: incoming.noteCreatedAt ?? incoming.createdAt,
          noteUpdatedAt: incoming.noteUpdatedAt,
        } : {}),
        ...(folderId === undefined ? {} : { folderId, folderUpdatedAt: incoming.updatedAt }),
        updatedAt,
      });
      // New V2 payloads also maintain the legacy projection for shipped apps.
      if (incoming.bookmarkCreatedAt !== undefined) {
        const existing = await ctx.db.query("bookmarks").withIndex("by_user", (q) => q.eq("userId", user._id)).collect();
        if (!existing.some((row) => row.hadithId === incoming.hadithId)) {
          await ctx.db.insert("bookmarks", { userId: user._id, hadithId: incoming.hadithId, createdAt: incoming.bookmarkCreatedAt });
        }
      }
      if (incoming.favoriteCreatedAt !== undefined) {
        const existing = await ctx.db.query("favorites").withIndex("by_user", (q) => q.eq("userId", user._id)).collect();
        if (!existing.some((row) => row.hadithId === incoming.hadithId)) {
          await ctx.db.insert("favorites", { userId: user._id, hadithId: incoming.hadithId, createdAt: incoming.favoriteCreatedAt });
        }
      }
      if (incomingNoteWins && incoming.noteContent !== undefined && incoming.noteUpdatedAt !== undefined) {
        const existing = await ctx.db.query("notes").withIndex("by_user_hadith", (q) => q.eq("userId", user._id).eq("hadithId", incoming.hadithId)).unique();
        if (existing) await ctx.db.patch(existing._id, { content: incoming.noteContent, updatedAt: incoming.noteUpdatedAt });
        else await ctx.db.insert("notes", { userId: user._id, hadithId: incoming.hadithId, content: incoming.noteContent, createdAt: incoming.noteCreatedAt ?? incoming.createdAt, updatedAt: incoming.noteUpdatedAt });
      }
      savedItemsMerged += 1;
    }

    // Legacy-only payloads must be materialized too. It is intentionally after
    // the legacy writes above, and it never deletes an old row.
    const legacyHadithIds = new Set([
      ...args.bookmarks.map((item) => item.hadithId),
      ...(args.favorites ?? []).map((item) => item.hadithId),
      ...args.notes.map((item) => item.hadithId),
    ]);
    for (const hadithId of legacyHadithIds) await materializeLegacySavedItem(ctx, user._id, hadithId);

    let progressMerged = 0;
    let progressSkipped = 0;
    for (const item of args.readingProgress ?? []) {
      let current: ReadingPosition;
      let hadith: Doc<"hadiths"> | null;
      if ("position" in item) {
        current = parseReadingPosition(item.position);
        const resolved = await resolveReadingPositionWrite(ctx, current);
        hadith = resolved?.hadith ?? null;
        if (resolved) current = resolved.position;
      } else {
        hadith = await ctx.db.get(item.hadithId);
        if (!hadith) {
          progressSkipped += 1;
          continue;
        }
        current = legacyReadingPosition({
          provider: hadith.provider,
          collectionSlug: hadith.collectionSlug,
          providerHadithId: hadith.providerHadithId,
          volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown",
          ...(hadith.chapterId === undefined ? {} : { chapterId: hadith.chapterId }),
          updatedAt: item.updatedAt,
        });
      }
      if (!hadith) {
        progressSkipped += 1;
        continue;
      }
      const result = await applyReadingPosition(ctx, user._id, current, hadith._id);
      if (result.status === "applied") progressMerged += 1;
      else progressSkipped += 1;
    }

    return {
      bookmarksMerged,
      bookmarksSkipped,
      notesMerged,
      notesSkipped,
      favoritesMerged,
      favoritesSkipped,
      savedItemsMerged,
      savedItemsSkipped,
      progressMerged,
      progressSkipped,
    };
  },
});
