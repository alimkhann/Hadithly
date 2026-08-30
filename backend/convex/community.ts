import { internalMutation } from "./_generated/server";
import { v } from "convex/values";

const aiReviewValidator = v.object({
  model: v.string(),
  score: v.number(),
  riskFlags: v.array(v.string()),
  missingMeaning: v.optional(v.array(v.string())),
  addedMeaning: v.optional(v.array(v.string())),
  glossaryIssues: v.optional(v.array(v.string())),
  recommendation: v.union(
    v.literal("approve"),
    v.literal("community_review"),
    v.literal("admin_review"),
    v.literal("reject"),
  ),
});

/** Internal: record a community submission (called from the AI action). */
export const insertSubmission = internalMutation({
  args: {
    clerkId: v.string(),
    hadithId: v.id("hadiths"),
    language: v.string(),
    proposedContent: v.string(),
    aiReview: aiReviewValidator,
    status: v.union(
      v.literal("pending"),
      v.literal("rejected"),
      v.literal("needs_admin"),
    ),
  },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();
    if (!user) throw new Error("User not found");

    return await ctx.db.insert("communitySubmissions", {
      hadithId: args.hadithId,
      language: args.language,
      submittedBy: user._id,
      proposedContent: args.proposedContent,
      aiReview: args.aiReview,
      status: args.status,
      createdAt: Date.now(),
    });
  },
});

/** Internal: record a translation report (called from the AI action). */
export const insertReport = internalMutation({
  args: {
    translationId: v.id("translations"),
    reporterUserId: v.optional(v.id("users")),
    reason: v.string(),
  },
  handler: async (ctx, args) =>
    await ctx.db.insert("translationReports", {
      ...args,
      status: "open",
      createdAt: Date.now(),
    }),
});

/**
 * Internal: admin approval flow. When an admin approves a submission, the
 * proposed content becomes a live community translation. Called from the
 * dashboard or an admin tool — never exposed to clients.
 */
export const approveSubmission = internalMutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    const submission = await ctx.db.get(args.submissionId);
    if (!submission) throw new Error("Submission not found");
    if (submission.status === "approved") return;

    await ctx.db.patch(args.submissionId, {
      status: "approved",
      reviewedAt: Date.now(),
    });
    await ctx.db.insert("translations", {
      hadithId: submission.hadithId,
      language: submission.language,
      content: submission.proposedContent,
      source: "community",
      sourceLabel: "Community",
      status: "live",
      isDefault: false,
      contributorUserId: submission.submittedBy,
      groundingUsed: false,
      approvedAt: Date.now(),
      createdAt: Date.now(),
      updatedAt: Date.now(),
    });
    await ctx.db.insert("adminAuditLog", {
      action: "approve_submission",
      targetType: "communitySubmissions",
      targetId: args.submissionId,
      metadata: { language: submission.language },
      createdAt: Date.now(),
    });
  },
});

export const rejectSubmission = internalMutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    await ctx.db.patch(args.submissionId, {
      status: "rejected",
      reviewedAt: Date.now(),
    });
  },
});
