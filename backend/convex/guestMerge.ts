import { mutation } from "./_generated/server";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";

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

    return { bookmarksMerged, bookmarksSkipped, notesMerged, notesSkipped };
  },
});
