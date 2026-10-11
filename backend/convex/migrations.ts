import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { internalMutation } from "./_generated/server";
import {
  SUNNAH_NOW_LICENSE_RECORD,
  authenticityForProviderHadith,
  canonicalHadithIdentity,
  migrateLegacyAuthenticity,
} from "./lib/contentPolicy";
import { legacyReadingPosition } from "./lib/readingPositions";
import { normalizeDeliveryBucket } from "./lib/notifyContent";

/**
 * Backfills the F1 content contract in bounded, repeatable pages. Re-running
 * the migration leaves current rows unchanged and removes legacy claim fields.
 */
export const migrateF1Hadiths = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const now = Date.now();
    const existingLicense = await ctx.db
      .query("licenseRecords")
      .withIndex("by_source_key", (q) =>
        q.eq("sourceKey", SUNNAH_NOW_LICENSE_RECORD.sourceKey),
      )
      .unique();
    const licenseRecordId = existingLicense?._id ??
      await ctx.db.insert("licenseRecords", {
        ...SUNNAH_NOW_LICENSE_RECORD,
        createdAt: now,
        updatedAt: now,
      });
    const result = await ctx.db.query("hadiths").paginate(args.paginationOpts);
    for (const hadith of result.page) {
      const identity = canonicalHadithIdentity({
        provider: hadith.provider,
        collectionSlug: hadith.collectionSlug,
        providerHadithId: hadith.providerHadithId,
      });
      await ctx.db.patch(hadith._id, {
        canonicalId: identity.canonicalId,
        authenticity: hadith.authenticity ?? migrateLegacyAuthenticity({
          collectionSlug: hadith.collectionSlug,
          authenticityGrade: hadith.authenticityGrade,
          authenticityAppliesTo: hadith.authenticityAppliesTo ?? "none",
          authenticitySource: hadith.authenticitySource,
          authenticityConfidence:
            hadith.authenticityConfidence ?? "unavailable",
        }),
        ...(hadith.provider === "sunnah_now" ? { licenseRecordId } : {}),
        authenticityGrade: undefined,
        authenticityAppliesTo: undefined,
        authenticitySource: undefined,
        authenticityConfidence: undefined,
      });
    }

    return {
      migrated: result.page.length,
      continueCursor: result.continueCursor,
      isDone: result.isDone,
    };
  },
});

/**
 * Repairs the R6 source-truth label on rows cached before the fix: stored
 * `collection_scope` claims that still credit Sunnah.com are recomputed from
 * the current policy (Sunnah.now, still visibly manual). Bounded, repeatable
 * pages; re-running leaves corrected rows unchanged. Rows without a stored
 * claim are left for the F1 backfill, which owns them.
 */
export const migrateR6SourceLabels = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db.query("hadiths").paginate(args.paginationOpts);
    let repaired = 0;
    let unchanged = 0;
    for (const hadith of result.page) {
      const claim = hadith.authenticity;
      if (
        claim?.kind === "collection_scope" &&
        claim.verificationMethod === "manual_collection_mapping" &&
        claim.sourceName === "Sunnah.com"
      ) {
        await ctx.db.patch(hadith._id, {
          authenticity: authenticityForProviderHadith(hadith.collectionSlug),
        });
        repaired += 1;
      } else {
        unchanged += 1;
      }
    }

    return {
      scanned: result.page.length,
      repaired,
      unchanged,
      continueCursor: result.continueCursor,
      isDone: result.isDone,
    };
  },
});

/**
 * Materializes R1 positions on legacy progress rows in bounded, repeatable
 * pages. Compatibility fields remain for deployed clients.
 */
export const migrateR1ReadingProgress = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db
      .query("readingProgress")
      .paginate(args.paginationOpts);
    let migrated = 0;
    let unchanged = 0;
    let deferred = 0;

    for (const row of result.page) {
      if (row.position !== undefined) {
        unchanged += 1;
        continue;
      }
      const hadith = await ctx.db.get(row.hadithId);
      if (!hadith) {
        deferred += 1;
        continue;
      }
      const position = legacyReadingPosition({
        provider: hadith.provider,
        collectionSlug: hadith.collectionSlug,
        providerHadithId: hadith.providerHadithId,
        volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown",
        ...(hadith.chapterId === undefined ? {} : { chapterId: hadith.chapterId }),
        updatedAt: row.updatedAt,
      });
      await ctx.db.patch(row._id, {
        collectionSlug: position.anchor.collectionSlug,
        position,
        bookId: position.volumeId,
        scrollOffset: position.rawPageOffset,
      });
      migrated += 1;
    }

    return {
      scanned: result.page.length,
      migrated,
      unchanged,
      deferred,
      continueCursor: result.continueCursor,
      isDone: result.isDone,
    };
  },
});

/**
 * H3's bounded dual-read backfill. Each invocation migrates one legacy source
 * page. It only adds missing Saved facets or fills an older note, so replaying
 * a page or switching clients during the rollout cannot lose data.
 */
export const migrateH3SavedItems = internalMutation({
  args: {
    source: v.union(v.literal("bookmarks"), v.literal("favorites"), v.literal("notes")),
    paginationOpts: paginationOptsValidator,
  },
  handler: async (ctx, args) => {
    let migrated = 0;
    let unchanged = 0;
    if (args.source === "bookmarks") {
      const result = await ctx.db.query("bookmarks").paginate(args.paginationOpts);
      for (const row of result.page) {
        const existing = await ctx.db.query("savedItems").withIndex("by_user_hadith", (q) => q.eq("userId", row.userId).eq("hadithId", row.hadithId)).unique();
        if (existing?.bookmarkCreatedAt !== undefined) { unchanged += 1; continue; }
        const now = Date.now();
        if (existing) await ctx.db.patch(existing._id, { bookmarkCreatedAt: row.createdAt, updatedAt: Math.max(existing.updatedAt, row.createdAt) });
        else await ctx.db.insert("savedItems", { userId: row.userId, hadithId: row.hadithId, bookmarkCreatedAt: row.createdAt, createdAt: row.createdAt, updatedAt: now });
        migrated += 1;
      }
      return { source: args.source, migrated, unchanged, continueCursor: result.continueCursor, isDone: result.isDone };
    }
    if (args.source === "favorites") {
      const result = await ctx.db.query("favorites").paginate(args.paginationOpts);
      for (const row of result.page) {
        const existing = await ctx.db.query("savedItems").withIndex("by_user_hadith", (q) => q.eq("userId", row.userId).eq("hadithId", row.hadithId)).unique();
        if (existing?.favoriteCreatedAt !== undefined) { unchanged += 1; continue; }
        const now = Date.now();
        if (existing) await ctx.db.patch(existing._id, { favoriteCreatedAt: row.createdAt, updatedAt: Math.max(existing.updatedAt, row.createdAt) });
        else await ctx.db.insert("savedItems", { userId: row.userId, hadithId: row.hadithId, favoriteCreatedAt: row.createdAt, createdAt: row.createdAt, updatedAt: now });
        migrated += 1;
      }
      return { source: args.source, migrated, unchanged, continueCursor: result.continueCursor, isDone: result.isDone };
    }
    const result = await ctx.db.query("notes").paginate(args.paginationOpts);
    for (const row of result.page) {
      const existing = await ctx.db.query("savedItems").withIndex("by_user_hadith", (q) => q.eq("userId", row.userId).eq("hadithId", row.hadithId)).unique();
      if (existing?.noteUpdatedAt !== undefined && existing.noteUpdatedAt >= row.updatedAt) { unchanged += 1; continue; }
      const now = Date.now();
      if (existing) await ctx.db.patch(existing._id, { noteContent: row.content, noteCreatedAt: row.createdAt, noteUpdatedAt: row.updatedAt, updatedAt: Math.max(existing.updatedAt, row.updatedAt) });
      else await ctx.db.insert("savedItems", { userId: row.userId, hadithId: row.hadithId, noteContent: row.content, noteCreatedAt: row.createdAt, noteUpdatedAt: row.updatedAt, createdAt: row.createdAt, updatedAt: now });
      migrated += 1;
    }
    return { source: args.source, migrated, unchanged, continueCursor: result.continueCursor, isDone: result.isDone };
  },
});

/**
 * N1's bounded push-token backfill. Fills delivery buckets from dailyTime,
 * zeroes retry state, and stamps lastSeenAt — but never invents an IANA
 * timezone from a fixed offset (one offset maps to many zones with
 * different DST rules). Rows without a zone stay un-schedulable until the
 * client re-registers; the cron skips them with `missing-timezone`.
 * Idempotent: re-running leaves current rows unchanged.
 */
export const migrateN1PushTokens = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db.query("pushTokens").paginate(args.paginationOpts);
    let migrated = 0;
    let unchanged = 0;
    const now = Date.now();
    for (const row of result.page) {
      const bucket = row.dailyTime ? normalizeDeliveryBucket(row.dailyTime) : null;
      const patch: {
        deliveryBucket?: string;
        consecutiveFailures?: number;
        lastSeenAt?: number;
      } = {};
      if (bucket !== null && row.deliveryBucket !== bucket) {
        patch.deliveryBucket = bucket;
      }
      if (row.consecutiveFailures === undefined) {
        patch.consecutiveFailures = 0;
      }
      if (row.lastSeenAt === undefined) {
        patch.lastSeenAt = now;
      }
      if (Object.keys(patch).length === 0) {
        unchanged += 1;
        continue;
      }
      await ctx.db.patch(row._id, patch);
      migrated += 1;
    }
    return { migrated, unchanged, continueCursor: result.continueCursor, isDone: result.isDone };
  },
});

/** Q1 never invents event dates from the old monthly aggregate. */
export const migrateQ1Users = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const page = await ctx.db.query("users").paginate(args.paginationOpts);
    let erased = 0;
    for (const user of page.page) {
      if (user.aiGenerationsThisMonth === undefined && user.aiGenerationLimit === undefined) continue;
      await ctx.db.patch(user._id, { aiGenerationsThisMonth: undefined, aiGenerationLimit: undefined });
      erased++;
    }
    return { erased, isDone: page.isDone, continueCursor: page.continueCursor };
  },
});

/** Only the seven cached outlines, run once after Q1 deployment. */
export const materializeQ1CollectionCounts = internalMutation({
  args: {},
  handler: async ctx => {
    let written = 0;
    for (const outline of await ctx.db.query("collectionOutlines").take(8)) {
      const existing = await ctx.db.query("collectionCounts").withIndex("by_collection", q => q.eq("collectionSlug", outline.collectionSlug)).unique();
      const totalHadiths = outline.volumes.reduce((sum, volume) => sum + volume.hadithCount, 0);
      if (existing && existing.totalHadiths === totalHadiths && existing.indexedAt === outline.indexedAt) continue;
      const fields = { collectionSlug: outline.collectionSlug, totalHadiths, indexedAt: outline.indexedAt };
      if (existing) await ctx.db.patch(existing._id, fields);
      else await ctx.db.insert("collectionCounts", fields);
      written++;
    }
    return { written };
  },
});
