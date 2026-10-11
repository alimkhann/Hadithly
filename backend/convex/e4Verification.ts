// Disposable development proof. This changes only E3's self-authored fixtures.
import { internalMutation, internalQuery } from "./_generated/server";
import { APPEAL_WINDOW_MS } from "./lib/evidenceCasePolicy";
import { revokeEvidencePublication, queueEvidenceCase } from "./evidenceCases";
const TARGETS = ["local_dump:e3_fixture:9001", "local_dump:e3_fixture:9002"];
function developmentOnly() {
  if (!process.env.CONVEX_CLOUD_URL?.includes("festive-cobra-664")) throw new Error("Development fixtures only");
}
export const baseline = internalQuery({ args: {}, handler: async ctx => {
  developmentOnly();
  const hadiths = await Promise.all(TARGETS.map(target => ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", target)).unique()));
  const hadithIds = new Set(hadiths.flatMap(row => row ? [row._id] : []));
  const submissions = (await ctx.db.query("communitySubmissions").take(100)).filter(row => hadithIds.has(row.hadithId));
  const submissionIds = new Set<string>(submissions.map(row => row._id));
  const translations = (await ctx.db.query("translations").take(100)).filter(row => hadithIds.has(row.hadithId));
  const translationIds = new Set<string>(translations.map(row => row._id));
  const tables = ["communitySubmissions", "evidenceItems", "evidenceExtractions", "evidenceReviewJobs", "evidenceReviewPasses", "evidenceProvenance", "evidenceLicenseAssessments", "evidencePermissionGrants", "evidencePublicationRevisions", "evidenceAppeals", "evidenceCases", "evidenceReviewSpendEvents", "translationReports", "translations", "users"] as const;
  const result: Record<string, string[]> = {};
  for (const table of tables) {
    const rows = await ctx.db.query(table).take(100);
    result[table] = rows.filter(row => !(
      submissionIds.has(row._id) || translationIds.has(row._id) ||
      "submissionId" in row && row.submissionId !== undefined && submissionIds.has(row.submissionId) ||
      "translationId" in row && row.translationId !== undefined && translationIds.has(row.translationId) ||
      "target" in row && (row.target.kind === "submission" ? submissionIds.has(row.target.submissionId) : translationIds.has(row.target.translationId)) ||
      "grant" in row && TARGETS.includes(row.grant.canonicalId)
    )).map(row => row._id).sort();
  }
  return result;
} });
export const prepareAppeals = internalMutation({ args: {}, handler: async ctx => {
  developmentOnly(); let prepared = 0;
  for (const target of TARGETS) {
    const hadith = await ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", target)).unique();
    if (!hadith) continue;
    const rows = (await ctx.db.query("communitySubmissions").take(100)).filter(row => row.hadithId === hadith._id);
    for (const submission of rows) {
      if (submission.proposedContent !== "This is a test text.") continue;
      const cases = await ctx.db.query("evidenceCases").withIndex("by_submission", q => q.eq("target.submissionId", submission._id)).collect();
      const reportResolved = cases.some(row => row.kind === "report" && row.state.kind === "resolved" && row.state.outcome === "published");
      if (submission.legacyStatus === "e4_fixture_decision" && submission.status === "rejected" && !reportResolved) {
        // Older proof controllers counted failed pass rows as a resolved report.
        // Repair only that synthetic state through a fresh guarded recheck.
        await ctx.db.patch(submission._id, { legacyStatus: undefined, status: "held" });
        await queueEvidenceCase(ctx, { kind: "recheck", target: { kind: "submission", submissionId: submission._id }, reason: "review", expiresAt: submission.expiresAt ?? Date.now() + APPEAL_WINDOW_MS });
        continue;
      }
      if (submission.status !== "approved" || !reportResolved || submission.legacyStatus === "e4_fixture_decision" || (submission.reviewedAt ?? Date.now()) + 8000 > Date.now()) continue;
      // Seed a private adverse decision to exercise the real owned appeal API.
      // No model verdict, scan result, or permission is fabricated here.
      await revokeEvidencePublication(ctx, submission._id, "review");
      await ctx.db.patch(submission._id, { status: "rejected", firstRejectedAt: Date.now(), expiresAt: Date.now() + APPEAL_WINDOW_MS, legacyStatus: "e4_fixture_decision" });
      prepared++;
    }
  }
  return { prepared };
} });
export const readback = internalQuery({ args: {}, handler: async ctx => {
  developmentOnly(); const states = [];
  for (const target of TARGETS) {
    const hadith = await ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", target)).unique(); if (!hadith) continue;
    const submissions = (await ctx.db.query("communitySubmissions").take(100)).filter(row => row.hadithId === hadith._id);
    for (const submission of submissions) {
      const appeals = await ctx.db.query("evidenceAppeals").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
      const passes = await ctx.db.query("evidenceReviewPasses").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
      const cases = await ctx.db.query("evidenceCases").withIndex("by_submission", q => q.eq("target.submissionId", submission._id)).collect();
      const revisions = await ctx.db.query("evidencePublicationRevisions").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
      const spend = await ctx.db.query("evidenceReviewSpendEvents").withIndex("by_submission_time", q => q.eq("submissionId", submission._id)).collect();
      states.push({ status: submission.status, appeal: appeals[0]?.status ?? "none", passes: revisions.filter(row => row.outputSha256).length * 2, attemptedPasses: spend.length * 2, recordedPasses: passes.length, reportResolved: cases.some(row => row.kind === "report" && row.state.kind === "resolved" && row.state.outcome === "published") });
    }
  }
  return states;
} });
