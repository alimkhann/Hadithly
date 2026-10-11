import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import type { Doc, Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { internalMutation, mutation } from "./_generated/server";
import { internal } from "./_generated/api";
import { requireIdentity } from "./lib/identity";
import { admitEvidenceRequest } from "./lib/evidenceAdmission";
import { APPEAL_WINDOW_MS, appealAllowed, DAY_MS, retryAt } from "./lib/evidenceCasePolicy";
import { appendEvidenceAudit, automatedActor } from "./lib/evidenceAudit";
import { injectionSuspected } from "./lib/evidenceReviewPolicy";
import { publicTranslationAvailable } from "./lib/evidencePublication";
import { deleteEvidenceForSubmission } from "./evidence";
import { deleteContribution } from "./translations";

type Case = Doc<"evidenceCases">;
type Actor = Doc<"evidenceAuditFacts">["actor"];
type Models = Doc<"evidenceAuditFacts">["models"];
export async function evidenceUser(ctx: QueryCtx | MutationCtx) {
  const identity = await requireIdentity(ctx);
  const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
  if (!user) throw new Error("Sign in is required");
  return user;
}
export function privateExplanation(raw: string): string {
  const reason = raw.trim();
  if (reason.length < 8 || reason.length > 2000 || /[\x00-\x08\x0b\x0c\x0e-\x1f]/.test(reason) || injectionSuspected(reason)) throw new Error("Explain the issue in 8 to 2000 characters without instructions to the reviewer");
  return reason;
}
export async function queueEvidenceCase(ctx: MutationCtx, input: Pick<Case, "kind" | "target" | "reason" | "expiresAt">): Promise<Id<"evidenceCases">> {
  const target = input.target;
  const existing = target.kind === "submission"
    ? await ctx.db.query("evidenceCases").withIndex("by_submission", q => q.eq("target.submissionId", target.submissionId)).collect()
    : await ctx.db.query("evidenceCases").withIndex("by_translation", q => q.eq("target.translationId", target.translationId)).collect();
  const active = existing.find(row => row.state.kind !== "resolved");
  if (active) {
    if (input.kind === "appeal") await ctx.db.patch(active._id, { kind: "appeal", reason: "contributor_appeal" });
    return active._id;
  }
  const id = await ctx.db.insert("evidenceCases", { ...input, attempts: 0, receipt: crypto.randomUUID(), state: { kind: "queued", dueAt: Date.now() }, createdAt: Date.now() });
  await ctx.scheduler.runAfter(0, internal.evidenceCases.dispatch, {});
  return id;
}

export async function revokeEvidencePublication(ctx: MutationCtx, submissionId: Id<"communitySubmissions">, reason: Case["reason"], actor: Actor = automatedActor, models: Models = [], replacing = false): Promise<void> {
  const submission = await ctx.db.get(submissionId);
  if (!submission) return;
  const revisions = await ctx.db.query("evidencePublicationRevisions").withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
  for (const revision of revisions) {
    if (revision.status !== "published") continue;
    await ctx.db.patch(revision._id, { status: "revoked" });
    const translation = revision.translationId ? await ctx.db.get(revision.translationId) : null;
    if (translation) {
      await ctx.db.patch(translation._id, { status: "archived", isDefault: false, updatedAt: Date.now() });
      if (translation.isDefault) {
        const current = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", translation.hadithId).eq("language", translation.language).eq("isDefault", true)).first();
        if (!current) for (const previousId of revision.previousDefaultIds ?? []) {
          const previous = await ctx.db.get(previousId);
          if (previous && await publicTranslationAvailable(ctx, previous)) { await ctx.db.patch(previous._id, { isDefault: true, updatedAt: Date.now() }); break; }
        }
      }
    }
    const receipt = submission.auditReceipt ?? crypto.randomUUID();
    if (!submission.auditReceipt) await ctx.db.patch(submissionId, { auditReceipt: receipt });
    await appendEvidenceAudit(ctx, { receipt, actor, reason, before: "published", after: "revoked", models });
  }
  if (!replacing && revisions.some(row => row.status === "published")) await ctx.db.patch(submissionId, { status: "revoked", expiresAt: submission.firstRejectedAt !== undefined ? submission.firstRejectedAt + APPEAL_WINDOW_MS : Date.now() + APPEAL_WINDOW_MS, firstRejectedAt: submission.firstRejectedAt ?? Date.now() });
}

export async function resolveContributorCaseStatus(ctx: MutationCtx, row: Case, outcome: "published" | "private"): Promise<void> {
  if (row.target.kind === "submission") {
    const submissionId = row.target.submissionId;
    const appeals = await ctx.db.query("evidenceAppeals").withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
    for (const appeal of appeals) if (appeal.status === "processing") await ctx.db.patch(appeal._id, { status: outcome });
  }
  const reports = await ctx.db.query("translationReports").withIndex("by_case", q => q.eq("caseId", row._id)).collect();
  for (const report of reports) await ctx.db.patch(report._id, { status: outcome === "published" ? "dismissed" : "reviewed" });
}

export async function finishEvidenceCase(ctx: MutationCtx, caseId: Id<"evidenceCases"> | undefined, outcome: "published" | "private", models: Models, unavailable = false, budgetExhausted = false): Promise<void> {
  if (!caseId) return;
  const row = await ctx.db.get(caseId);
  if (!row || row.state.kind === "resolved") return;
  const next = unavailable && !budgetExhausted ? retryAt(row.attempts, Date.now()) : null;
  if (next !== null && next < row.expiresAt) {
    await ctx.db.patch(row._id, { state: { kind: "queued", dueAt: next } });
    await ctx.scheduler.runAfter(next - Date.now(), internal.evidenceCases.dispatch, {});
    return;
  }
  await ctx.db.patch(row._id, { state: { kind: "resolved", outcome, closedAt: Date.now() }, kind: row.kind === "report" && outcome === "private" ? "incident" : row.kind, context: undefined });
  if (row.target.kind === "submission") {
    const submissionId = row.target.submissionId;
    if (outcome === "private") {
      const revisions = await ctx.db.query("evidencePublicationRevisions").withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
      let retainPrior = false;
      if (unavailable || budgetExhausted) for (const revision of revisions) {
        const translation = revision.translationId ? await ctx.db.get(revision.translationId) : null;
        if (await publicTranslationAvailable(ctx, translation)) { retainPrior = true; break; }
      }
      if (retainPrior) await ctx.db.patch(submissionId, { status: "approved", expiresAt: undefined });
      else await revokeEvidencePublication(ctx, submissionId, unavailable ? "retry_exhausted" : row.reason, automatedActor, models);
    }
  }
  await resolveContributorCaseStatus(ctx, row, outcome);
  await appendEvidenceAudit(ctx, { receipt: row.receipt, actor: automatedActor, reason: unavailable ? "retry_exhausted" : row.reason, before: row.state.kind, after: outcome, models });
}

export const requestAppeal = mutation({
  args: { submissionId: v.id("communitySubmissions"), reason: v.string() },
  handler: async (ctx, args) => {
    const user = await evidenceUser(ctx), submission = await ctx.db.get(args.submissionId);
    if (!submission || submission.submittedBy !== user._id) throw new Error("Suggestion not found");
    const existing = await ctx.db.query("evidenceAppeals").withIndex("by_submission", q => q.eq("submissionId", submission._id)).first();
    if (existing && existing.status !== "not_requested") return { status: existing.status };
    if (!appealAllowed(submission.status, submission.expiresAt, false, Date.now())) throw new Error("The appeal window is closed");
    const reason = privateExplanation(args.reason);
    await admitEvidenceRequest(ctx, user._id, "appeal");
    if (existing) await ctx.db.delete(existing._id);
    await ctx.db.insert("evidenceAppeals", { submissionId: submission._id, ownerUserId: user._id, status: "processing", reason, expiresAt: submission.expiresAt, createdAt: Date.now() });
    await queueEvidenceCase(ctx, { kind: "appeal", target: { kind: "submission", submissionId: submission._id }, reason: "contributor_appeal", expiresAt: submission.expiresAt ?? Date.now() });
    return { status: "processing" };
  },
});

export async function acceptTranslationReport(ctx: MutationCtx, args: { translationId: Id<"translations">; reporterUserId: Id<"users">; reason: string }): Promise<void> {
  const translation = await ctx.db.get(args.translationId);
  if (!translation) throw new Error("Translation not found");
  const existing = await ctx.db.query("translationReports").withIndex("by_reporter_target", q => q.eq("reporterUserId", args.reporterUserId).eq("translationId", translation._id)).first();
  if (existing) return;
  const reason = privateExplanation(args.reason);
  await admitEvidenceRequest(ctx, args.reporterUserId, "report");
  const revision = translation.evidencePublicationId ? await ctx.db.get(translation.evidencePublicationId) : null;
  const deadline = Date.now() + APPEAL_WINDOW_MS;
  const caseId = await queueEvidenceCase(ctx, { kind: revision ? "report" : "incident", target: revision ? { kind: "submission", submissionId: revision.submissionId } : { kind: "translation", translationId: translation._id }, reason: "report", expiresAt: deadline });
  await ctx.db.insert("translationReports", { ...args, reason, status: "open", caseId, expiresAt: deadline, createdAt: Date.now() });
}

export const dispatch = internalMutation({ args: {}, handler: async ctx => {
  const stale = await ctx.db.query("evidenceCases").withIndex("by_due", q => q.eq("state.kind", "running").lte("state.dueAt", Date.now())).take(10);
  for (const row of stale) await finishEvidenceCase(ctx, row._id, "private", [], true);
  const queued = await ctx.db.query("evidenceCases").withIndex("by_due", q => q.eq("state.kind", "queued").lte("state.dueAt", Date.now())).take(10);
  for (const row of queued) {
    if (row.expiresAt <= Date.now()) { await ctx.db.patch(row._id, { state: { kind: "resolved", outcome: "expired", closedAt: Date.now() } }); continue; }
    if (row.target.kind === "translation") {
      // An allegation cannot remove existing official/AI content. Without
      // licensed review provenance, resolve the incident privately. An actual
      // rights/safety failure or an audited takedown has separate authority.
      await finishEvidenceCase(ctx, row._id, "private", []);
      continue;
    }
    const submissionId = row.target.submissionId;
    const submission = await ctx.db.get(submissionId);
    if (!submission || ["expired", "infected", "draft", "awaiting_processing"].includes(submission.status)) { await finishEvidenceCase(ctx, row._id, "private", []); continue; }
    if (submission.status === "under_review") continue;
    const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", submissionId)).unique();
    if (job?.status === "running") continue;
    if (job) await ctx.db.delete(job._id);
    for (const table of ["evidenceProvenance", "evidenceLicenseAssessments"] as const) {
      const assessments = await ctx.db.query(table).withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
      for (const assessment of assessments) await ctx.db.delete(assessment._id);
    }
    await ctx.db.patch(submissionId, { status: "evidence_ready", expiresAt: submission.expiresAt ?? row.expiresAt });
    await ctx.scheduler.runAfter(0, internal.actions.evidenceReview.reviewSubmission, { submissionId });
  }
} });

export const reassessPublished = internalMutation({
  args: { paginationOpts: paginationOptsValidator }, handler: async (ctx, args): Promise<void> => {
    const page = await ctx.db.query("evidencePublicationRevisions").withIndex("by_status", q => q.eq("status", "published")).paginate(args.paginationOpts);
    for (const revision of page.page) {
      const translation = revision.translationId ? await ctx.db.get(revision.translationId) : null;
      if (!await publicTranslationAvailable(ctx, translation)) {
        await revokeEvidencePublication(ctx, revision.submissionId, "rights");
        const submission = await ctx.db.get(revision.submissionId);
        if (submission && (submission.expiresAt ?? 0) > Date.now()) await queueEvidenceCase(ctx, { kind: "recheck", target: { kind: "submission", submissionId: submission._id }, reason: "policy", expiresAt: submission.expiresAt ?? Date.now() });
      }
    }
    if (!page.isDone) await ctx.scheduler.runAfter(0, internal.evidenceCases.reassessPublished, { paginationOpts: { cursor: page.continueCursor, numItems: 25 } });
  },
});

export const migrateLegacyPublications = internalMutation({ args: { paginationOpts: paginationOptsValidator }, handler: async (ctx, args) => {
  const page = await ctx.db.query("translations").withIndex("by_source_status", q => q.eq("source", "community").eq("status", "live")).paginate(args.paginationOpts);
  let migrated = 0;
  for (const translation of page.page) {
    if (translation.evidencePublicationId) continue;
    const contributor = translation.contributorUserId;
    const submissions = contributor ? await ctx.db.query("communitySubmissions").withIndex("by_submitted_by", q => q.eq("submittedBy", contributor)).collect() : [];
    const submission = submissions.find(row => row.hadithId === translation.hadithId && row.language === translation.language && row.proposedContent === translation.content);
    if (submission) {
      const receipt = submission.auditReceipt ?? crypto.randomUUID();
      const revisionId = await ctx.db.insert("evidencePublicationRevisions", { submissionId: submission._id, translationId: translation._id, status: "revoked", previousDefaultIds: [], createdAt: Date.now() });
      await ctx.db.patch(translation._id, { evidencePublicationId: revisionId, status: "archived", isDefault: false, updatedAt: Date.now() });
      await ctx.db.patch(submission._id, { status: "revoked", auditReceipt: receipt, firstRejectedAt: Date.now(), expiresAt: Date.now() + APPEAL_WINDOW_MS });
      await queueEvidenceCase(ctx, { kind: "incident", target: { kind: "submission", submissionId: submission._id }, reason: "rights", expiresAt: Date.now() + APPEAL_WINDOW_MS });
      await appendEvidenceAudit(ctx, { receipt, actor: automatedActor, reason: "rights", before: "published", after: "revoked", models: [] });
    } else {
      await ctx.db.patch(translation._id, { status: "archived", isDefault: false, updatedAt: Date.now() });
      const id = await queueEvidenceCase(ctx, { kind: "incident", target: { kind: "translation", translationId: translation._id }, reason: "rights", expiresAt: Date.now() + APPEAL_WINDOW_MS });
      const incident = await ctx.db.get(id);
      if (incident) await appendEvidenceAudit(ctx, { receipt: incident.receipt, actor: automatedActor, reason: "rights", before: "published", after: "revoked", models: [] });
    }
    migrated++;
  }
  return { migrated, isDone: page.isDone, continueCursor: page.continueCursor };
} });

export async function takeDownEvidence(ctx: MutationCtx, row: Case, reason: Case["reason"], actor: Actor): Promise<void> {
  if (row.target.kind === "submission") {
    const submission = await ctx.db.get(row.target.submissionId);
    if (submission) {
      await revokeEvidencePublication(ctx, submission._id, reason, actor);
      await deleteEvidenceForSubmission(ctx, submission._id);
      await ctx.db.delete(submission._id);
    }
  } else {
    const translationId = row.target.translationId;
    const translation = await ctx.db.get(translationId);
    if (translation) await deleteContribution(ctx, translation);
    const reports = await ctx.db.query("translationReports").withIndex("by_translation", q => q.eq("translationId", translationId)).collect();
    for (const report of reports) await ctx.db.delete(report._id);
    await ctx.db.delete(row._id);
  }
  await appendEvidenceAudit(ctx, { receipt: row.receipt, actor, reason, before: row.state.kind, after: "deleted", models: [] });
  await ctx.scheduler.runAfter(0, internal.evidenceCases.reassessPublished, { paginationOpts: { cursor: null, numItems: 25 } });
}

export const retain = internalMutation({ args: {}, handler: async ctx => {
  const cases = await ctx.db.query("evidenceCases").withIndex("by_expiry", q => q.lte("expiresAt", Date.now())).take(25);
  for (const row of cases) {
    if (row.target.kind === "translation") {
      const translation = await ctx.db.get(row.target.translationId);
      if (translation?.status !== "live") await takeDownEvidence(ctx, row, "expired", automatedActor);
      else await ctx.db.delete(row._id);
    } else await ctx.db.delete(row._id);
  }
  const reports = await ctx.db.query("translationReports").withIndex("by_expiry", q => q.lte("expiresAt", Date.now())).take(25);
  for (const report of reports) await ctx.db.delete(report._id);
  const requests = await ctx.db.query("evidenceRequestEvents").withIndex("by_time", q => q.lt("createdAt", Date.now() - DAY_MS)).take(100);
  for (const request of requests) await ctx.db.delete(request._id);
  const spend = await ctx.db.query("evidenceReviewSpendEvents").withIndex("by_time", q => q.lt("createdAt", Date.now() - APPEAL_WINDOW_MS)).take(100);
  for (const event of spend) await ctx.db.delete(event._id);
  const globalSpend = await ctx.db.query("evidenceReviewGlobalSpendEvents").withIndex("by_time", q => q.lt("createdAt", Date.now() - DAY_MS)).take(100);
  for (const event of globalSpend) await ctx.db.delete(event._id);
  if (cases.length === 25 || reports.length === 25 || requests.length === 100 || spend.length === 100 || globalSpend.length === 100) await ctx.scheduler.runAfter(0, internal.evidenceCases.retain, {});
} });
