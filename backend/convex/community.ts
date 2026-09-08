import {
  internalMutation,
  mutation,
  query,
} from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { v } from "convex/values";
import { optionalIdentity, requireIdentity } from "./lib/identity";

const aiReviewValidator = v.object({
  model: v.string(),
  score: v.number(),
  riskFlags: v.array(v.string()),
  missingMeaning: v.optional(v.array(v.string())),
  addedMeaning: v.optional(v.array(v.string())),
  glossaryIssues: v.optional(v.array(v.string())),
  recommendation: v.union(
    v.literal("approve"),
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
    replacesTranslationId: v.optional(v.id("translations")),
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
      replacesTranslationId: args.replacesTranslationId,
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

async function requireAdmin(ctx: QueryCtx | MutationCtx) {
  const identity = await requireIdentity(ctx);
  const user = await ctx.db
    .query("users")
    .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
    .unique();
  if (!user?.isAdmin) throw new Error("Forbidden: admin access required");
  return user;
}

/** Public but identity-derived: lets the app reveal moderation only to admins. */
export const canModerate = query({
  args: {},
  handler: async (ctx) => {
    const identity = await optionalIdentity(ctx);
    if (!identity) return false;
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", identity.clerkId))
      .unique();
    return user?.isAdmin === true;
  },
});

/** Admin-only queue. No vote counts, rankings, or contributor statistics. */
export const listPendingSubmissions = query({
  args: {},
  handler: async (ctx) => {
    await requireAdmin(ctx);
    const [pending, needsAdmin] = await Promise.all([
      ctx.db
        .query("communitySubmissions")
        .withIndex("by_status", (q) => q.eq("status", "pending"))
        .take(50),
      ctx.db
        .query("communitySubmissions")
        .withIndex("by_status", (q) => q.eq("status", "needs_admin"))
        .take(50),
    ]);
    const rows = [...pending, ...needsAdmin]
      .sort((a, b) => a.createdAt - b.createdAt)
      .slice(0, 50);

    return await Promise.all(
      rows.map(async (submission) => {
        const [hadith, contributor] = await Promise.all([
          ctx.db.get(submission.hadithId),
          ctx.db.get(submission.submittedBy),
        ]);
        return {
          ...submission,
          hadith: hadith
            ? {
                referenceDisplay: hadith.referenceDisplay,
                arabicText: hadith.arabicText,
                englishText: hadith.englishText,
              }
            : null,
          contributor: contributor
            ? {
                displayName: contributor.displayName,
                email: contributor.email,
              }
            : null,
        };
      }),
    );
  },
});

/**
 * Admin-only approval. The approved text becomes the reader's default for
 * this hadith/language; the previous default remains live as a non-default
 * alternative for auditability.
 */
export const approveSubmission = mutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const submission = await ctx.db.get(args.submissionId);
    if (!submission) throw new Error("Submission not found");
    if (submission.status === "approved") return;

    const previousDefault = await ctx.db
      .query("translations")
      .withIndex("by_hadith_language_default", (q) =>
        q
          .eq("hadithId", submission.hadithId)
          .eq("language", submission.language)
          .eq("isDefault", true),
      )
      .first();
    const now = Date.now();
    if (previousDefault) {
      await ctx.db.patch(previousDefault._id, {
        isDefault: false,
        updatedAt: now,
      });
    }

    await ctx.db.patch(args.submissionId, {
      status: "approved",
      reviewedAt: now,
    });
    await ctx.db.insert("translations", {
      hadithId: submission.hadithId,
      language: submission.language,
      content: submission.proposedContent,
      source: "community",
      sourceLabel: "Community",
      status: "live",
      isDefault: true,
      contributorUserId: submission.submittedBy,
      groundingUsed: false,
      approvedAt: now,
      createdAt: now,
      updatedAt: now,
    });
    await ctx.db.insert("adminAuditLog", {
      actorUserId: admin._id,
      action: "approve_submission",
      targetType: "communitySubmissions",
      targetId: args.submissionId,
      metadata: { language: submission.language },
      createdAt: now,
    });
  },
});

export const rejectSubmission = mutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    const admin = await requireAdmin(ctx);
    const submission = await ctx.db.get(args.submissionId);
    if (!submission) throw new Error("Submission not found");
    await ctx.db.patch(args.submissionId, {
      status: "rejected",
      reviewedAt: Date.now(),
    });
    await ctx.db.insert("adminAuditLog", {
      actorUserId: admin._id,
      action: "reject_submission",
      targetType: "communitySubmissions",
      targetId: args.submissionId,
      metadata: { language: submission.language },
      createdAt: Date.now(),
    });
  },
});

/** Dashboard/CLI bootstrap only; clients cannot grant admin access. */
export const setAdmin = internalMutation({
  args: { clerkId: v.string(), isAdmin: v.boolean() },
  handler: async (ctx, args) => {
    const user = await ctx.db
      .query("users")
      .withIndex("by_clerk_id", (q) => q.eq("clerkId", args.clerkId))
      .unique();
    if (!user) throw new Error("User not found");
    await ctx.db.patch(user._id, { isAdmin: args.isAdmin });
  },
});
