import { mutation, query } from "./_generated/server";
import { v } from "convex/values";

export const submitTranslation = mutation({
  args: {
    hadithId: v.id("hadiths"),
    language: v.string(),
    submittedBy: v.id("users"),
    proposedContent: v.string(),
    replacesTranslationId: v.optional(v.id("translations")),
    aiReview: v.object({
      model: v.string(),
      score: v.number(),
      riskFlags: v.array(v.string()),
      missingMeaning: v.optional(v.array(v.string())),
      addedMeaning: v.optional(v.array(v.string())),
      glossaryIssues: v.optional(v.array(v.string())),
      recommendation: v.union(v.literal("approve"), v.literal("community_review"), v.literal("admin_review"), v.literal("reject"))
    })
  },
  handler: async (ctx, args) => {
    const status = args.aiReview.recommendation === "reject" ? "rejected" : args.aiReview.recommendation === "admin_review" ? "needs_admin" : "pending";
    return await ctx.db.insert("communitySubmissions", {
      ...args,
      status,
      upvotes: 0,
      downvotes: 0,
      createdAt: Date.now()
    });
  }
});

export const pendingQueue = query({
  args: {},
  handler: async (ctx) =>
    await ctx.db
      .query("communitySubmissions")
      .withIndex("by_status", (q) => q.eq("status", "pending"))
      .take(50)
});

export const reportTranslation = mutation({
  args: {
    translationId: v.id("translations"),
    reporterUserId: v.optional(v.id("users")),
    reason: v.string()
  },
  handler: async (ctx, args) =>
    await ctx.db.insert("translationReports", {
      ...args,
      status: "open",
      createdAt: Date.now()
    })
});
