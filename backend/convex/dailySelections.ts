import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { isDailyEligible } from "./lib/dailyEligibility";
import { migrateLegacyAuthenticity } from "./lib/contentPolicy";

export const getHadithId = internalQuery({
  args: { localDate: v.string(), timezone: v.string() },
  handler: async (ctx, args) => {
    const selection = await ctx.db
      .query("dailySelections")
      .withIndex("by_local_date_timezone", (q) =>
        q.eq("localDate", args.localDate).eq("timezone", args.timezone),
      )
      .unique();
    return selection?.hadithId ?? null;
  },
});

/**
 * Keeps the first eligible choice for a local day. If an old stored choice is
 * no longer eligible, the next eligible choice replaces it.
 */
export const persist = internalMutation({
  args: {
    localDate: v.string(),
    timezone: v.string(),
    hadithId: v.id("hadiths"),
  },
  handler: async (ctx, args) => {
    if (!/^\d{4}-\d{2}-\d{2}$/.test(args.localDate)) {
      throw new Error("Invalid local date");
    }
    const candidate = await ctx.db.get(args.hadithId);
    if (!candidate) throw new Error("Daily Hadith candidate does not exist");
    const candidateClaim = candidate.authenticity ?? migrateLegacyAuthenticity({
      collectionSlug: candidate.collectionSlug,
      authenticityGrade: candidate.authenticityGrade,
      authenticityAppliesTo: candidate.authenticityAppliesTo ?? "none",
      authenticitySource: candidate.authenticitySource,
      authenticityConfidence: candidate.authenticityConfidence ?? "unavailable",
    });
    if (!isDailyEligible(candidateClaim)) {
      throw new Error("Hadith is not eligible for Daily Hadith");
    }

    const existing = await ctx.db
      .query("dailySelections")
      .withIndex("by_local_date_timezone", (q) =>
        q.eq("localDate", args.localDate).eq("timezone", args.timezone),
      )
      .unique();
    if (existing) {
      const existingHadith = await ctx.db.get(existing.hadithId);
      const existingClaim = existingHadith?.authenticity ??
        (existingHadith
          ? migrateLegacyAuthenticity({
              collectionSlug: existingHadith.collectionSlug,
              authenticityGrade: existingHadith.authenticityGrade,
              authenticityAppliesTo:
                existingHadith.authenticityAppliesTo ?? "none",
              authenticitySource: existingHadith.authenticitySource,
              authenticityConfidence:
                existingHadith.authenticityConfidence ?? "unavailable",
            })
          : undefined);
      if (isDailyEligible(existingClaim)) return existing.hadithId;
      await ctx.db.patch(existing._id, { hadithId: args.hadithId });
      return args.hadithId;
    }

    await ctx.db.insert("dailySelections", {
      localDate: args.localDate,
      timezone: args.timezone,
      hadithId: args.hadithId,
      createdAt: Date.now(),
    });
    return args.hadithId;
  },
});
