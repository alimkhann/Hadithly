import { paginationOptsValidator } from "convex/server";
import { internalMutation } from "./_generated/server";
import {
  SUNNAH_NOW_LICENSE_RECORD,
  canonicalHadithIdentity,
  migrateLegacyAuthenticity,
} from "./lib/contentPolicy";
import { legacyReadingPosition } from "./lib/readingPositions";

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
