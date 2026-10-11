import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { mutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { caseReason, APPEAL_WINDOW_MS } from "./lib/evidenceCasePolicy";
import { appendEvidenceAudit } from "./lib/evidenceAudit";
import { evidenceUser, queueEvidenceCase, revokeEvidencePublication, takeDownEvidence, resolveContributorCaseStatus } from "./evidenceCases";
import { internal } from "./_generated/api";
import { canonicalJson } from "./lib/offlineDumps";
import { textDigest } from "./lib/evidenceReviewPolicy";

async function operator(ctx: QueryCtx | MutationCtx) {
  const user = await evidenceUser(ctx);
  if (user.isAdmin !== true) throw new Error("Operator authorization required");
  return user;
}
export const listCases = query({
  args: { kind: v.union(v.literal("exception"), v.literal("appeal"), v.literal("audit"), v.literal("incident")), paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    await operator(ctx);
    const page = await ctx.db.query("evidenceCases").withIndex("by_kind", q => q.eq("kind", args.kind)).paginate({ ...args.paginationOpts, numItems: Math.min(args.paginationOpts.numItems, 25) });
    return { ...page, page: await Promise.all(page.page.map(async row => ({ caseId: row._id, kind: row.kind, state: row.state.kind, outcome: row.state.kind === "resolved" ? row.state.outcome : null, attempts: row.attempts, reason: row.reason, expiresAt: row.expiresAt, receipt: row.receipt, version: await textDigest(canonicalJson(row)) }))) };
  },
});
export const auditFacts = query({ args: { receipt: v.string() }, handler: async (ctx, args) => {
  await operator(ctx);
  return ctx.db.query("evidenceAuditFacts").withIndex("by_receipt", q => q.eq("receipt", args.receipt)).take(50);
} });
export const act = mutation({
  args: { caseId: v.id("evidenceCases"), expectedVersion: v.string(), action: v.union(v.literal("recheck"), v.literal("suppress"), v.literal("takedown")), reason: caseReason },
  handler: async (ctx, args) => {
    const user = await operator(ctx);
    const row = await ctx.db.get(args.caseId);
    if (!row || await textDigest(canonicalJson(row)) !== args.expectedVersion) throw new Error("Case changed; refresh before acting");
    let mapping = await ctx.db.query("evidenceAuditActors").withIndex("by_user", q => q.eq("userId", user._id)).unique();
    if (!mapping) { const id = await ctx.db.insert("evidenceAuditActors", { userId: user._id, key: crypto.randomUUID() }); mapping = await ctx.db.get(id); }
    if (!mapping) throw new Error("Operator audit identity unavailable");
    const actor = { kind: "operator", verified: true, key: mapping.key } as const;
    if (args.action === "takedown") { await takeDownEvidence(ctx, row, args.reason, actor); return true; }
    if (row.target.kind !== "submission") throw new Error("Unbound content requires takedown");
    const submissionId = row.target.submissionId, submission = await ctx.db.get(submissionId);
    if (!submission || submission.status === "expired" || submission.expiresAt !== undefined && submission.expiresAt <= Date.now()) throw new Error("Suggestion expired");
    if (args.action === "suppress") {
      await revokeEvidencePublication(ctx, submissionId, args.reason, actor);
      const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", submissionId)).unique();
      if (job) await ctx.db.patch(job._id, { status: "failed", reasons: ["operator_suppression"] });
      await ctx.db.patch(submissionId, { status: "held", expiresAt: submission.expiresAt ?? Date.now() + APPEAL_WINDOW_MS });
      await ctx.db.patch(row._id, { state: { kind: "resolved", outcome: "private", closedAt: Date.now() } });
      await resolveContributorCaseStatus(ctx, row, "private");
    } else {
      if (row.state.kind !== "resolved") throw new Error("Automatic recheck is already active");
      await queueEvidenceCase(ctx, { kind: row.kind === "report" ? "incident" : row.kind, target: row.target, reason: args.reason, expiresAt: submission.expiresAt ?? Date.now() + APPEAL_WINDOW_MS });
      await ctx.scheduler.runAfter(0, internal.evidenceCases.dispatch, {});
    }
    await appendEvidenceAudit(ctx, { receipt: row.receipt, actor, reason: args.reason, before: row.state.kind, after: args.action === "suppress" ? "private" : "queued", models: [] });
    return true;
  },
});
