// Disposable development-only proof fixtures. No user evidence is sampled.
import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { deleteEvidenceForSubmission } from "./evidence";
import { deleteContribution } from "./translations";
import { textDigest } from "./lib/evidenceReviewPolicy";
import type { MutationCtx } from "./_generated/server";

const TARGETS = ["local_dump:e3_fixture:9001", "local_dump:e3_fixture:9002"];
const PROPOSAL = "This is a test text.";
function developmentOnly() {
  if (!process.env.CONVEX_CLOUD_URL?.includes("festive-cobra-664")) throw new Error("Development fixtures only");
}
async function fixtureHadith(ctx: MutationCtx, target: string) {
  const existing = await ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", target)).unique();
  if (existing) return existing._id;
  return ctx.db.insert("hadiths", { provider: "local_dump", canonicalId: target, collectionSlug: "e3_fixture", providerHadithId: target.split(":")[2] ?? "",
    arabicText: "هذا نص للاختبار.", englishText: PROPOSAL, referenceDisplay: "E3 fixture 9001", collectionName: "Synthetic verification, not a hadith", createdAt: Date.now() });
}
async function fixtureGrant(target: string, language: string, sha256: string, textSha256: string, sourceUrl: string) {
  return { sourceKind: sourceUrl ? "approved_translation" as const : "evidence" as const, sourceUrl, artifactSha256: sha256, textSha256, canonicalId: target, language,
    citation: { url: "https://hadithly.app", title: "Hadithly self-authored test source", location: "Synthetic fixture, not a hadith" },
    rightsHolder: "Hadithly verification fixture author", permissionUrl: "https://hadithly.app", permissionSha256: await textDigest("Hadithly created this disposable fixture and permits its use for E3 verification."),
    licenseName: "Self-authored disposable verification fixture", attribution: "Hadithly verification", access: true, comparison: true, modelProcessing: true, adaptation: true, display: true, redistribution: true, offline: false,
    conditions: "attribution_only" as const, verifiedAt: Date.now() };
}
export const seed = internalMutation({ args: {}, handler: async ctx => {
  developmentOnly();
  for (const target of TARGETS) {
    const hadithId = await fixtureHadith(ctx, target); const hadith = await ctx.db.get(hadithId); if (!hadith) throw new Error("Missing fixture");
    const sha = await textDigest(hadith.arabicText);
    const existing = await ctx.db.query("evidencePermissionGrants").withIndex("by_artifact", q => q.eq("grant.artifactSha256", sha)).collect();
    if (existing.some(row => row.grant.canonicalId === target && row.grant.language === "ar" && row.grant.revokedAt === undefined)) continue;
    await ctx.runMutation(internal.evidenceReview.recordPermission, { grant: await fixtureGrant(target, "ar", sha, sha, "https://hadithly.app") });
  }
  return { canonicalIds: TARGETS };
} });
export const prepareReady = internalMutation({ args: {}, handler: async ctx => {
  developmentOnly();
  const hadiths = await Promise.all(TARGETS.map(async target => ({ target, id: await fixtureHadith(ctx, target) })));
  const rows = await ctx.db.query("communitySubmissions").take(100);
  let prepared = 0;
  for (const submission of rows) {
    const hadith = hadiths.find(row => row.id === submission.hadithId);
    if (!hadith || submission.proposedContent !== PROPOSAL || !["held", "evidence_ready"].includes(submission.status)) continue;
    const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
    if (items.length !== 1 || items[0]?.state !== "ready") continue;
    if (await ctx.db.query("evidenceReviewPasses").withIndex("by_submission", q => q.eq("submissionId", submission._id)).first()) continue;
    const item = items[0];
    const extraction = await ctx.db.query("evidenceExtractions").withIndex("by_item", q => q.eq("evidenceItemId", item._id)).unique();
    if (!extraction || extraction.text.trim() !== PROPOSAL) throw new Error("Synthetic fixture OCR mismatch");
    if (await ctx.db.query("evidencePermissionGrants").withIndex("by_submission", q => q.eq("submissionId", submission._id)).first()) continue;
    // Keep opt-in proof counts stable; production receipts remain random.
    await ctx.db.patch(submission._id, { auditReceipt: `00000001${crypto.randomUUID().slice(8)}` });
    await ctx.runMutation(internal.evidenceReview.recordPermission, { grant: await fixtureGrant(hadith.target, "en", extraction.sha256, await textDigest(extraction.text), ""), submissionId: submission._id });
    prepared++;
  }
  return { prepared };
} });
export const readback = internalQuery({ args: {}, handler: async ctx => {
  developmentOnly();
  const hadiths = await Promise.all(TARGETS.map(target => ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", target)).unique()));
  const hadithIds = new Set(hadiths.flatMap(row => row ? [row._id] : []));
  const submissions = (await ctx.db.query("communitySubmissions").take(100)).filter(row => hadithIds.has(row.hadithId));
  const passes = [];
  for (const submission of submissions) for (const pass of await ctx.db.query("evidenceReviewPasses").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect()) if (pass.result) passes.push({ model: pass.result.model, modelVersion: pass.result.modelVersion, confidence: pass.result.verdict.confidence, injection: pass.result.verdict.injection, consistent: pass.result.verdict.consistent });
  const failures = [];
  for (const submission of submissions) {
    const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", submission._id)).unique();
    if (job?.status === "failed") failures.push(job.reasons);
  }
  const states = [];
  for (const submission of submissions) states.push({ status: submission.status, reviewPassCount: (await ctx.db.query("evidenceReviewPasses").withIndex("by_submission", q=>q.eq("submissionId",submission._id)).collect()).length, items: (await ctx.db.query("evidenceItems").withIndex("by_submission", q=>q.eq("submissionId",submission._id)).collect()).map(item=>({state:item.state,attempts:item.processingAttempts ?? 0})) });
  return { submissions: states, passes, failures, live: (await ctx.db.query("translations").take(100)).filter(row => hadithIds.has(row.hadithId) && row.status === "live").length };
} });
export const cleanup = internalMutation({ args: {}, handler: async ctx => {
  developmentOnly();
  let removed = 0;
  for (const target of TARGETS) {
    const hadith = await ctx.db.query("hadiths").withIndex("by_canonical_id", q => q.eq("canonicalId", target)).unique(); if (!hadith) continue;
    for (const translation of (await ctx.db.query("translations").take(100)).filter(row => row.hadithId === hadith._id)) await deleteContribution(ctx, translation);
    for (const submission of (await ctx.db.query("communitySubmissions").take(100)).filter(row => row.hadithId === hadith._id)) {
      await deleteEvidenceForSubmission(ctx, submission._id);
      for (const event of await ctx.db.query("evidenceReviewSpendEvents").withIndex("by_submission_time", q => q.eq("submissionId", submission._id)).collect()) await ctx.db.delete(event._id);
      await ctx.db.delete(submission._id); removed++;
    }
    for (const grant of (await ctx.db.query("evidencePermissionGrants").collect()).filter(row => row.grant.canonicalId === target)) await ctx.db.delete(grant._id);
    await ctx.db.delete(hadith._id);
  }
  return { removed };
} });
