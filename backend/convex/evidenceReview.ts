import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation, internalQuery } from "./_generated/server";
import { paginationOptsValidator } from "convex/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { storageHashMatches } from "./evidence";
import { assessPermission, decidePublication, injectionSuspected, pathWithinPolicy, permissionGrant, POLICY_VERSION, REVIEW_MODELS, reviewPass, sourcePolicy, textDigest } from "./lib/evidenceReviewPolicy";
import type { PermissionGrant, ReviewPacket, ReviewSource } from "./lib/evidenceReviewPolicy";
import { currentPublicationPermissions, publicTranslationAvailable } from "./lib/evidencePublication";
import { canonicalJson } from "./lib/offlineDumps";
import { APPEAL_WINDOW_MS, DAY_MS, sampleAudit } from "./lib/evidenceCasePolicy";
import { appendEvidenceAudit, automatedActor } from "./lib/evidenceAudit";
import { finishEvidenceCase, queueEvidenceCase, revokeEvidencePublication } from "./evidenceCases";

export const CONSENT_VERSION = "e3-contribution-v1";
const RELATED: Readonly<Record<string, readonly string[]>> = {
  kk: ["ky", "uz", "tr"], ky: ["kk", "uz", "tr"], uz: ["kk", "ky", "tr"], tr: ["kk", "ky", "uz"],
  ur: ["fa", "hi"], fa: ["ur"], hi: ["ur", "bn"], bn: ["hi"], id: ["ms"], ms: ["id"], ru: ["uk"], uk: ["ru"], "es-419": ["pt-BR"], "pt-BR": ["es-419"],
};
const SUNNAH_COM_COLLECTIONS: Readonly<Record<string, string>> = {
  "abu-dawood": "abudawud", "sunan-nasai": "nasai", "ibn-majah": "ibnmajah", "mishkat-al-masabih": "mishkat",
  bukhari: "bukhari", muslim: "muslim", abu_dawood: "abudawud", sunan_nasai: "nasai", tirmidhi: "tirmidhi", ibn_majah: "ibnmajah", mishkat: "mishkat",
};
type Ctx = MutationCtx | QueryCtx;
type Assessment = { itemId: Id<"evidenceItems">; sha256: string; textSha256: string; language: string; status: "affirmative" | "ambiguous" | "denied"; grant: PermissionGrant | null; grantId?: Id<"evidencePermissionGrants"> };

function safePublicUrl(raw: string): boolean {
  try { const url = new URL(raw); return url.protocol === "https:" && !url.username && !url.password && !url.search && (!url.port || url.port === "443") && raw.length <= 2048; } catch { return false; }
}
function kindForUrl(url: string): "evidence" | "sunnah_com" {
  const host = new URL(url).hostname;
  return host === "sunnah.com" || host.endsWith(".sunnah.com") ? "sunnah_com" : "evidence";
}
async function policyFor(ctx: Ctx, url: string, kind: "evidence" | "sunnah_now" | "sunnah_com") {
  return ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", new URL(url).origin).eq("policy.sourceKind", kind)).unique();
}
async function permissionFor(ctx: Ctx, input: { kind: PermissionGrant["sourceKind"]; sha256: string; text: string; url: string; canonicalId: string; language: string; publication: boolean; reference?: string; arabicReference?: string; submissionId?: Id<"communitySubmissions"> }) {
  const textSha256 = await textDigest(input.text);
  const policy = input.url && (input.kind === "evidence" || input.kind === "sunnah_now" || input.kind === "sunnah_com") ? await policyFor(ctx, input.url, input.kind) : null;
  const args = { artifactSha256: input.sha256, textSha256, sourceUrl: input.url, canonicalId: input.canonicalId, language: input.language, publication: input.publication, now: Date.now() };
  const grants = await ctx.db.query("evidencePermissionGrants").withIndex("by_scope", q => q.eq("grant.artifactSha256", input.sha256).eq("grant.textSha256", textSha256).eq("grant.canonicalId", input.canonicalId).eq("grant.sourceKind", input.kind).eq("grant.sourceUrl", input.url).eq("submissionId", input.url ? undefined : input.submissionId).eq("grant.language", input.language)).collect();
  for (const row of grants) {
    if (row.grant.sourceKind === input.kind && assessPermission({ ...args, grant: row.grant }) === "affirmative" && policy?.policy.assessment.kind !== "avoid") return { status: "affirmative" as const, grant: row.grant, grantId: row._id, policy, textSha256 };
  }
  // A reviewed source policy grants rights. Exact canonical reference checks
  // and retained hashes bind the individual page without another manual grant.
  const assessed = policy?.policy.assessment;
  const [, collection] = input.canonicalId.split(":");
  const normalize = (text: string) => text.normalize("NFKC").toLowerCase().replace(/\p{M}/gu, "").replace(/[أإآ]/g, "ا").replace(/[^\p{L}\p{N}]+/gu, " ").trim();
  const reference = input.reference ? normalize(input.reference) : "";
  const content = ` ${normalize(input.text)} `;
  const matchesReference = input.kind === "sunnah_now" ||
    input.kind === "sunnah_com" && !!collection && !!input.arabicReference && normalize(input.arabicReference).length >= 8 &&
      new URL(input.url).pathname.startsWith(`/${SUNNAH_COM_COLLECTIONS[collection] ?? collection}:`) && content.includes(` ${normalize(input.arabicReference)} `) ||
    input.kind === "evidence" && !!reference && content.includes(` ${reference} `);
  if (matchesReference && safePublicUrl(input.url) && policy && assessed?.kind === "permitted" && assessed.expiresAt > Date.now() && pathWithinPolicy(new URL(input.url).pathname, assessed.pathPrefix) && assessed.languages.includes(input.language)) {
    const grant: PermissionGrant = { ...assessed.terms, sourceKind: input.kind, sourceUrl: input.url, artifactSha256: input.sha256, textSha256, canonicalId: input.canonicalId, language: input.language,
      citation: { url: input.url, title: assessed.terms.attribution, location: input.reference ?? input.canonicalId }, verifiedAt: policy.policy.checkedAt, expiresAt: assessed.expiresAt };
    const status = assessPermission({ ...args, grant });
    return { status, grant: status === "affirmative" ? grant : null, policy, textSha256 };
  }
  return { status: policy?.policy.assessment.kind === "avoid" ? "denied" as const : "ambiguous" as const, grant: null, policy, textSha256 };
}
async function evidenceLanguage(ctx: Ctx, input: { sha256: string; text: string; url: string; kind: "evidence" | "sunnah_com"; canonicalId: string; submissionId: Id<"communitySubmissions"> }) {
  const hash = await textDigest(input.text);
  const grants = await ctx.db.query("evidencePermissionGrants").withIndex("by_scope", q => q.eq("grant.artifactSha256", input.sha256).eq("grant.textSha256", hash).eq("grant.canonicalId", input.canonicalId).eq("grant.sourceKind", input.kind).eq("grant.sourceUrl", input.url).eq("submissionId", input.url ? undefined : input.submissionId)).take(30);
  const languages = [...new Set(grants.filter(row => row.grant.sourceKind === input.kind && row.grant.textSha256 === hash && row.grant.sourceUrl === input.url && row.grant.canonicalId === input.canonicalId && row.grant.revokedAt === undefined).map(row => row.grant.language))];
  if (languages.length === 1) return languages[0] ?? "und";
  const policy = input.url ? await policyFor(ctx, input.url, input.kind) : null;
  return policy?.policy.assessment.kind === "permitted" && policy.policy.assessment.languages.length === 1 ? policy.policy.assessment.languages[0] ?? "und" : "und";
}

async function snapshotFor(ctx: Ctx, submission: Doc<"communitySubmissions">) {
  const hadith = await ctx.db.get(submission.hadithId);
  if (!hadith || !await ctx.db.get(submission.submittedBy)) return null;
  const canonicalId = hadith.canonicalId ?? `${hadith.provider}:${hadith.collectionSlug}:${hadith.providerHadithId}`;
  const items = (await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect()).sort((a, b) => a._id.localeCompare(b._id));
  const extractions = await ctx.db.query("evidenceExtractions").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
  const abuseRows = await ctx.db.query("evidenceAbuseEvents").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
  const deletionRows = await ctx.db.query("evidenceDeletionStates").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
  const sources: ReviewSource[] = [], assessments: Assessment[] = [], permissions: PermissionGrant[] = [], bindings: unknown[] = [];
  const permissionDependencies: NonNullable<Doc<"evidencePublicationRevisions">["permissionDependencies"]> = [];
  const comparisonPublicationIds: Id<"evidencePublicationRevisions">[] = [];
  const scanBindings: NonNullable<Doc<"evidencePublicationRevisions">["scanBindings"]> = [];
  const accessDependencies: NonNullable<Doc<"evidencePublicationRevisions">["accessDependencies"]> = [];
  const retain = (permission: Awaited<ReturnType<typeof permissionFor>>, use?: "comparison") => {
    if (!permission.grant) return;
    permissions.push(permission.grant);
    if ("grantId" in permission && permission.grantId) permissionDependencies.push({ kind: "grant", id: permission.grantId, snapshot: permission.grant, use });
    else if (permission.policy) permissionDependencies.push({ kind: "policy", id: permission.policy._id, snapshot: permission.policy.policy, use });
  };
  let clean = items.length >= 1 && items.length <= 3 && extractions.length === items.length;
  let licensed = submission.contributionConsentVersion === CONSENT_VERSION, provenance = true;
  for (const [i, item] of items.entries()) {
    const extraction = extractions.find(row => row.evidenceItemId === item._id);
    if (item.state !== "ready" || !extraction || !extraction.text.trim() || !extraction.spans.length) { clean = false; provenance = false; continue; }
    const url = item.source.kind === "url" ? extraction.finalUrl ?? item.source.url : "";
    const accessPolicies = [];
    if (item.source.kind === "url") {
      const chain = extraction.accessChain ?? [item.source.url];
      if (chain.at(-1) !== extraction.finalUrl) clean = false;
      for (const hop of chain) {
        accessDependencies.push({ origin: new URL(hop).origin, path: new URL(hop).pathname, sourceKind: kindForUrl(hop) });
        const policy = await policyFor(ctx, hop, kindForUrl(hop));
        accessPolicies.push(policy);
        const assessment = policy?.policy.assessment;
        if (assessment?.kind === "avoid" || kindForUrl(hop) === "sunnah_com" && (!assessment || assessment.kind !== "permitted" || !assessment.terms.access || assessment.expiresAt <= Date.now() || !pathWithinPolicy(new URL(hop).pathname, assessment.pathPrefix))) clean = false;
      }
    }
    const storageId = item.source.kind === "file" ? item.source.storageId : extraction.sourceStorageId;
    const stored = storageId ? await ctx.db.system.get(storageId) : null;
    if (storageId) scanBindings.push({ itemId: item._id, storageId, sha256: extraction.sha256 });
    if (!stored || !storageHashMatches(stored.sha256, extraction.sha256) || item.source.kind === "file" && item.source.sha256 !== extraction.sha256) clean = false;
    const kind = url ? kindForUrl(url) : "evidence";
    const language = await evidenceLanguage(ctx, { kind, sha256: extraction.sha256, text: extraction.text, url, canonicalId, submissionId: submission._id });
    const permission = await permissionFor(ctx, { kind, sha256: extraction.sha256, text: extraction.text, url, canonicalId, language, publication: true, reference: hadith.referenceDisplay, arabicReference: hadith.arabicText, submissionId: submission._id });
    assessments.push({ itemId: item._id, sha256: extraction.sha256, textSha256: permission.textSha256, language, status: permission.status, grant: permission.grant, grantId: "grantId" in permission ? permission.grantId : undefined });
    licensed = licensed && permission.status === "affirmative"; provenance = provenance && !!permission.grant;
    if (permission.grant) {
      retain(permission);
      sources.push({ id: `evidence:${i}`, kind, language, text: extraction.text, citation: permission.grant.citation, spans: extraction.spans.map((span, index) => ({ id: `span:${index}`, start: span.start, end: span.end, text: extraction.text.slice(span.start, span.end) })) });
    }
    bindings.push({ item, extraction, stored, permission, accessPolicies });
  }
  const url = hadith.provider === "sunnah_now" ? "https://sunnah.now/" : hadith.provider === "sunnah_com" ? `https://sunnah.com/${SUNNAH_COM_COLLECTIONS[hadith.collectionSlug] ?? hadith.collectionSlug}:${hadith.providerHadithId}` : "https://hadithly.app";
  const arabic = await permissionFor(ctx, { kind: hadith.provider === "sunnah_now" ? "sunnah_now" : hadith.provider === "sunnah_com" ? "sunnah_com" : "approved_translation", sha256: await textDigest(hadith.arabicText), text: hadith.arabicText, url, canonicalId, language: "ar", publication: true, arabicReference: hadith.arabicText });
  licensed = licensed && arabic.status === "affirmative"; provenance = provenance && !!arabic.grant;
  if (arabic.grant) {
    sources.push({ id: "arabic:0", kind: "arabic", language: "ar", text: hadith.arabicText, citation: arabic.grant.citation, spans: [] });
    retain(arabic);
  }
  bindings.push({ hadith, arabic });
  if (hadith.provider === "sunnah_now" && hadith.englishText) {
    const english = await permissionFor(ctx, { kind: "sunnah_now", sha256: await textDigest(hadith.englishText), text: hadith.englishText, url, canonicalId, language: "en", publication: false });
    if (english.grant) sources.push({ id: "sunnah_now:english", kind: "sunnah_now", language: "en", text: hadith.englishText, citation: english.grant.citation, spans: [] });
    if (english.grant) retain(english, "comparison");
    bindings.push({ english });
  }
  for (const language of [...new Set([submission.language, ...(RELATED[submission.language] ?? [])])]) {
    const candidates = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", hadith._id).eq("language", language).eq("isDefault", true)).take(10);
    for (const candidate of candidates) {
      if (candidate.status !== "live" || candidate.legacyEvidenceMissing || sources.length >= 12) continue;
      const kind = candidate.source === "gemini_ai" ? "ai_translation" : "approved_translation";
      if (candidate.evidencePublicationId) {
        const revision = await ctx.db.get(candidate.evidencePublicationId);
        if (revision?.submissionId === submission._id) continue;
        const current = await currentPublicationPermissions(ctx, revision, "comparison");
        const reusable = current.valid && await publicTranslationAvailable(ctx, candidate) && revision?.translationId === candidate._id && revision.outputSha256 === await textDigest(candidate.content);
        bindings.push({ candidate, revision, current });
        if (reusable && revision?.citations?.[0]) { comparisonPublicationIds.push(revision._id); sources.push({ id: `translation:${sources.length}`, kind: language === submission.language ? "approved_translation" : "related_language", language, text: candidate.content, citation: revision.citations[0], spans: [] }); }
        continue;
      }
      const permission = await permissionFor(ctx, { kind, sha256: await textDigest(candidate.content), text: candidate.content, url: candidate.sourceReferenceUrl ?? "", canonicalId, language, publication: false, submissionId: submission._id });
      bindings.push({ candidate, permission });
      if (permission.grant) retain(permission, "comparison");
      if (permission.grant) sources.push({ id: `translation:${sources.length}`, kind: language !== submission.language && kind !== "ai_translation" ? "related_language" : kind,
        language, text: candidate.content, citation: permission.grant.citation, spans: [] });
    }
  }
  const cases = await ctx.db.query("evidenceCases").withIndex("by_submission", q => q.eq("target.submissionId", submission._id)).collect();
  const concerns: string[] = [];
  for (const row of cases.filter(row => row.state.kind !== "resolved")) {
    const reports = await ctx.db.query("translationReports").withIndex("by_case", q => q.eq("caseId", row._id)).take(10);
    concerns.push(...reports.map(report => report.reason));
  }
  const appeals = await ctx.db.query("evidenceAppeals").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
  concerns.push(...appeals.flatMap(appeal => appeal.status === "processing" && appeal.reason ? [appeal.reason] : []));
  const packet: ReviewPacket = { policyVersion: POLICY_VERSION, untrustedData: { canonicalId, language: submission.language, proposedTranslation: submission.proposedContent, sources, ...(concerns.length ? { concerns: concerns.slice(0, 10) } : {}) } };
  if (JSON.stringify(packet).length > 120_000) clean = false;
  const abuse = abuseRows.some(row => row.status !== "none") || deletionRows.some(row => row.status !== "active");
  const defaults = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", hadith._id).eq("language", submission.language).eq("isDefault", true)).collect();
  const binding = await textDigest(canonicalJson({ packet, bindings, defaults, consent: submission.contributionConsentVersion, replacement: submission.replacesTranslationId, abuseRows, deletionRows }));
  return { packet, clean, licensed, provenance, abuse, assessments, permissions, permissionDependencies, comparisonPublicationIds, scanBindings, accessDependencies, binding };
}

export const recordPermission = internalMutation({
  args: { grant: permissionGrant, submissionId: v.optional(v.id("communitySubmissions")) },
  handler: async (ctx, { grant, submissionId }) => {
    if (![grant.artifactSha256, grant.textSha256, grant.permissionSha256].every(value => /^[a-f0-9]{64}$/.test(value)) || !safePublicUrl(grant.citation.url) || !safePublicUrl(grant.permissionUrl) || grant.sourceUrl && !safePublicUrl(grant.sourceUrl) ||
        !grant.rightsHolder.trim() || !grant.attribution.trim() || !grant.licenseName.trim() || grant.verifiedAt > Date.now() || !/^(sunnah_now|sunnah_com|local_dump):[a-z][a-z0-9_-]*:[0-9.]+$/.test(grant.canonicalId) || !/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(grant.language) || injectionSuspected(JSON.stringify(grant.citation))) throw new Error("Invalid permission record");
    if (!grant.sourceUrl && (!submissionId || !await ctx.db.get(submissionId))) throw new Error("Private artifact permission requires a submission");
    const scopeSubmissionId = grant.sourceUrl ? undefined : submissionId;
    const existing = await ctx.db.query("evidencePermissionGrants").withIndex("by_scope", q => q.eq("grant.artifactSha256", grant.artifactSha256).eq("grant.textSha256", grant.textSha256).eq("grant.canonicalId", grant.canonicalId).eq("grant.sourceKind", grant.sourceKind).eq("grant.sourceUrl", grant.sourceUrl).eq("submissionId", scopeSubmissionId).eq("grant.language", grant.language)).unique();
    const id = existing?._id ?? await ctx.db.insert("evidencePermissionGrants", { grant, submissionId: scopeSubmissionId, createdAt: Date.now() });
    if (existing) await ctx.db.patch(id, { grant });
    if (scopeSubmissionId) await ctx.scheduler.runAfter(0, internal.evidenceReview.reassessSubmission, { submissionId: scopeSubmissionId });
    await ctx.scheduler.runAfter(0, internal.evidenceCases.reassessPublished, { paginationOpts: { cursor: null, numItems: 25 } });
    if (grant.sourceUrl) await ctx.scheduler.runAfter(0, internal.evidenceReview.reassessSourcePolicy, { origin: new URL(grant.sourceUrl).origin, paginationOpts: { cursor: null, numItems: 25 } });
    return id;
  },
});
export const recordSourcePolicy = internalMutation({
  args: { policy: sourcePolicy },
  handler: async (ctx, { policy }) => {
    if (!safePublicUrl(policy.origin) || new URL(policy.origin).origin !== policy.origin || policy.checkedAt > Date.now()) throw new Error("Invalid source policy");
    if (policy.assessment.kind === "permitted" && (!safePublicUrl(policy.assessment.terms.permissionUrl) || !/^[a-f0-9]{64}$/.test(policy.assessment.terms.permissionSha256) || !policy.assessment.pathPrefix.startsWith("/") || !policy.assessment.languages.length || policy.assessment.expiresAt <= Date.now() || !policy.assessment.terms.rightsHolder.trim() || !policy.assessment.terms.attribution.trim())) throw new Error("Invalid source policy");
    const row = await policyFor(ctx, policy.origin, policy.sourceKind);
    const id = row?._id ?? await ctx.db.insert("evidenceSourcePolicies", { policy });
    if (row) await ctx.db.patch(id, { policy });
    await ctx.scheduler.runAfter(0, internal.evidenceReview.reassessSourcePolicy, { origin: policy.origin, paginationOpts: { cursor: null, numItems: 25 } });
    await ctx.scheduler.runAfter(0, internal.evidenceCases.reassessPublished, { paginationOpts: { cursor: null, numItems: 25 } });
    return id;
  },
});
async function reassessHeldSubmission(ctx: MutationCtx, submissionId: Id<"communitySubmissions">): Promise<void> {
    const submission = await ctx.db.get(submissionId);
    if (!submission || !["held", "revoked"].includes(submission.status)) return;
    if ((submission.expiresAt ?? 0) <= Date.now()) return;
    const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", submission._id)).unique();
    if (!job || submission.status !== "revoked" && !job.reasons.every(reason => ["license", "provenance", "support", "scan"].includes(reason))) return;
    if (job.reasons.includes("scan")) {
      const current = await snapshotFor(ctx, submission);
      if (!current?.clean) return;
    }
    for (const table of ["evidenceProvenance", "evidenceLicenseAssessments"] as const) {
      const assessments = await ctx.db.query(table).withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
      for (const assessment of assessments) await ctx.db.delete(assessment._id);
    }
    await ctx.db.delete(job._id);
    await ctx.db.patch(submission._id, { status: "evidence_ready" });
    await ctx.scheduler.runAfter(0, internal.actions.evidenceReview.reviewSubmission, { submissionId: submission._id });
}
export const reassessSubmission = internalMutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args): Promise<void> => { await reassessHeldSubmission(ctx, args.submissionId); },
});
export const reassessSourcePolicy = internalMutation({
 args: { origin: v.string(), paginationOpts: paginationOptsValidator },
 handler: async (ctx, args): Promise<void> => {
  const page = await ctx.db.query("evidenceSourceDependencies").withIndex("by_origin", q => q.eq("origin", args.origin)).paginate(args.paginationOpts);
  for (const dependency of page.page) {
    await reassessHeldSubmission(ctx, dependency.submissionId);
  }
  if (!page.isDone) await ctx.scheduler.runAfter(0, internal.evidenceReview.reassessSourcePolicy, { origin: args.origin, paginationOpts: { cursor: page.continueCursor, numItems: 25 } });
 },
});
export const accessRules = internalQuery({ args: {}, handler: async ctx => {
  const policies = await ctx.db.query("evidenceSourcePolicies").withIndex("by_kind", q => q.eq("policy.sourceKind", "sunnah_com")).take(21);
  const avoided = await ctx.db.query("evidenceSourcePolicies").withIndex("by_assessment", q => q.eq("policy.assessment.kind", "avoid")).take(101);
  if (policies.length > 20 || avoided.length > 100) throw new Error("Source access policy exceeds limit");
  return {
    accessScopes: policies.flatMap(row => row.policy.sourceKind === "sunnah_com" && row.policy.assessment.kind === "permitted" && row.policy.assessment.terms.access && row.policy.assessment.expiresAt > Date.now() ? [{ origin: row.policy.origin, pathPrefix: row.policy.assessment.pathPrefix }] : []).slice(0, 20),
    deniedOrigins: avoided.map(row => row.policy.origin),
  };
} });
async function recordAssessments(ctx: MutationCtx, submissionId: Id<"communitySubmissions">, snapshot: NonNullable<Awaited<ReturnType<typeof snapshotFor>>>) {
  for (const item of snapshot.assessments) {
    await ctx.db.insert("evidenceProvenance", { submissionId, evidenceItemId: item.itemId, status: item.grant ? "verified" : "unresolved", artifactSha256: item.sha256, textSha256: item.textSha256,
      canonicalId: snapshot.packet.untrustedData.canonicalId, language: item.language, citation: item.grant?.citation, grantId: item.grantId, createdAt: Date.now() });
    await ctx.db.insert("evidenceLicenseAssessments", { submissionId, evidenceItemId: item.itemId, status: item.status, grantId: item.grantId, createdAt: Date.now() });
  }
}
async function releaseWorker(ctx: MutationCtx, token: string) {
  const lease = await ctx.db.query("evidenceWorkerLease").withIndex("by_name", q => q.eq("name", "reviewer")).unique();
  if (lease?.token === token) await ctx.db.delete(lease._id);
}
async function unavailableReview(ctx: MutationCtx, job: Doc<"evidenceReviewJobs">, submission: Doc<"communitySubmissions">, reason: string, models: Array<{ model: string; revision: string }> = REVIEW_MODELS.map(model => ({ model, revision: "unavailable" }))): Promise<void> {
  await releaseWorker(ctx, job.token);
  await ctx.db.patch(job._id, { status: "failed", reasons: ["review_unavailable", reason] });
  await ctx.db.patch(submission._id, { status: "review_unavailable" });
  let caseId = job.caseId;
  if (!caseId) {
    caseId = await queueEvidenceCase(ctx, { kind: "exception", target: { kind: "submission", submissionId: submission._id }, reason: "review", expiresAt: submission.expiresAt ?? Date.now() + APPEAL_WINDOW_MS });
    await ctx.db.patch(caseId, { attempts: 1 });
  }
  await finishEvidenceCase(ctx, caseId, "private", models, true);
  await appendEvidenceAudit(ctx, { receipt: submission.auditReceipt ?? crypto.randomUUID(), actor: automatedActor, reason: "review", before: "under_review", after: "review_unavailable", models });
}
export const claim = internalMutation({
  args: { submissionId: v.id("communitySubmissions"), reviewEnabled: v.boolean() },
  handler: async (ctx, args) => {
    const submission = await ctx.db.get(args.submissionId);
    if (!submission || submission.status !== "evidence_ready" || (submission.expiresAt ?? 0) <= Date.now()) return null;
    if (await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", submission._id)).first()) return null;
    const worker = await ctx.db.query("evidenceWorkerLease").withIndex("by_name", q => q.eq("name", "reviewer")).unique();
    if (worker && worker.deadline > Date.now()) return null;
    if (worker) await ctx.db.delete(worker._id);
    const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
    const existingDependencies = await ctx.db.query("evidenceSourceDependencies").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
    const origins = new Set(existingDependencies.map(row => row.origin));
    const extractionRows = await ctx.db.query("evidenceExtractions").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
    const hadith = await ctx.db.get(submission.hadithId);
    const allOrigins = [ ...(hadith?.provider === "sunnah_now" ? ["https://sunnah.now"] : hadith?.provider === "sunnah_com" ? ["https://sunnah.com"] : []), ...items.flatMap(item => item.source.kind === "url" ? [new URL(item.source.url).origin] : []), ...extractionRows.flatMap(row => (row.accessChain ?? (row.finalUrl ? [row.finalUrl] : [])).map(url => new URL(url).origin)) ];
    for (const origin of new Set(allOrigins)) if (!origins.has(origin)) await ctx.db.insert("evidenceSourceDependencies", { submissionId: submission._id, origin });
    for (const item of items) {
      if (item.source.kind !== "url") continue;
      const origin = new URL(item.source.url).origin, kind = kindForUrl(item.source.url);
      if (!await policyFor(ctx, origin, kind)) await ctx.db.insert("evidenceSourcePolicies", { policy: { origin, sourceKind: kind, assessment: { kind: "unknown" }, checkedAt: Date.now() } });
    }
    const snapshot = await snapshotFor(ctx, submission);
    if (!snapshot) return null;
    const cases = await ctx.db.query("evidenceCases").withIndex("by_submission", q => q.eq("target.submissionId", submission._id)).collect();
    const activeCase = cases.find(row => row.state.kind === "queued" && row.state.dueAt <= Date.now());
    const receipt = submission.auditReceipt ?? crypto.randomUUID();
    if (!submission.auditReceipt) await ctx.db.patch(submission._id, { auditReceipt: receipt });
    const decision = decidePublication({ ...snapshot, passes: [] });
    const blockers = decision.reasons.filter(reason => reason !== "independence");
    if (blockers.length) {
      await recordAssessments(ctx, submission._id, snapshot);
      await ctx.db.insert("evidenceReviewJobs", { submissionId: submission._id, token: "", deadline: 0, snapshotSha256: snapshot.binding, status: "complete", policyVersion: POLICY_VERSION, reasons: blockers, createdAt: Date.now() });
      await ctx.db.patch(submission._id, { status: decision.kind === "reject" ? "rejected" : "held", reviewedAt: Date.now() });
      if (decision.kind === "reject") await ctx.db.patch(submission._id, { firstRejectedAt: submission.firstRejectedAt ?? Date.now(), expiresAt: (submission.firstRejectedAt ?? Date.now()) + APPEAL_WINDOW_MS });
      await revokeEvidencePublication(ctx, submission._id, "review");
      await finishEvidenceCase(ctx, activeCase?._id, "private", []);
      if (!activeCase) await ctx.db.insert("evidenceCases", { kind: "exception", target: { kind: "submission", submissionId: submission._id }, state: { kind: "resolved", outcome: "private", closedAt: Date.now() }, attempts: 0, receipt, reason: "review", expiresAt: submission.expiresAt ?? Date.now() + APPEAL_WINDOW_MS, createdAt: Date.now() });
      await appendEvidenceAudit(ctx, { receipt, actor: automatedActor, reason: "review", before: "evidence_ready", after: decision.kind === "reject" ? "rejected" : "held", models: [] });
      return null;
    }
    if (!args.reviewEnabled) return null;
    const targetSpend = await ctx.db.query("evidenceReviewSpendEvents").withIndex("by_submission_time", q => q.eq("submissionId", submission._id).gte("createdAt", Date.now() - APPEAL_WINDOW_MS)).take(6);
    const globalSpend = await ctx.db.query("evidenceReviewGlobalSpendEvents").withIndex("by_time", q => q.gte("createdAt", Date.now() - DAY_MS)).take(100);
    if (targetSpend.length >= 6 || globalSpend.length >= 100 || activeCase && activeCase.attempts >= 3) {
      await ctx.db.patch(submission._id, { status: "review_unavailable" });
      await finishEvidenceCase(ctx, activeCase?._id, "private", [], true, true);
      await appendEvidenceAudit(ctx, { receipt, actor: automatedActor, reason: "retry_exhausted", before: "evidence_ready", after: "review_unavailable", models: [] });
      return null;
    }
    const token = crypto.randomUUID();
    await ctx.db.insert("evidenceReviewSpendEvents", { submissionId: submission._id, createdAt: Date.now() });
    await ctx.db.insert("evidenceReviewGlobalSpendEvents", { createdAt: Date.now() });
    if (activeCase) await ctx.db.patch(activeCase._id, { attempts: activeCase.attempts + 1, state: { kind: "running", dueAt: Date.now() + 180_000, token } });
    await ctx.db.insert("evidenceWorkerLease", { name: "reviewer", token, deadline: Date.now() + 180_000 });
    await recordAssessments(ctx, submission._id, snapshot);
    await ctx.db.insert("evidenceReviewJobs", { submissionId: submission._id, token, deadline: Date.now() + 180_000, snapshotSha256: snapshot.binding, status: "running", policyVersion: POLICY_VERSION, reasons: [], caseId: activeCase?._id, createdAt: Date.now() });
    await ctx.db.patch(submission._id, { status: "under_review" });
    return { token, packet: snapshot.packet };
  },
});
export const finish = internalMutation({
  args: { submissionId: v.id("communitySubmissions"), token: v.string(), passes: v.array(reviewPass) },
  handler: async (ctx, args) => {
    await releaseWorker(ctx, args.token);
    const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", args.submissionId)).unique(), submission = await ctx.db.get(args.submissionId);
    if (!job || !submission || job.token !== args.token) return false;
    if (job.status === "complete") return submission.status === "approved";
    if (job.status !== "running" || job.deadline <= Date.now() || submission.status !== "under_review" || (submission.expiresAt ?? 0) <= Date.now()) return false;
    if (job.caseId) { const active = await ctx.db.get(job.caseId); if (!active || active.state.kind !== "running" || active.state.token !== args.token || active.expiresAt <= Date.now()) return false; }
    const snapshot = await snapshotFor(ctx, submission);
    if (!snapshot) return false;
    const decision = decidePublication({ ...snapshot, passes: args.passes });
    if (job.snapshotSha256 !== snapshot.binding || job.policyVersion !== POLICY_VERSION) {
      const models = args.passes.slice(0, 2).map(pass => ({ model: pass.model, revision: pass.modelVersion }));
      if (!snapshot.clean || !snapshot.licensed || !snapshot.provenance || snapshot.abuse) await revokeEvidencePublication(ctx, submission._id, "review", automatedActor, models);
      await unavailableReview(ctx, job, submission, "stale_snapshot", models);
      return false;
    }
    for (const result of args.passes.slice(0, 2)) await ctx.db.insert("evidenceReviewPasses", { submissionId: submission._id, status: "complete", snapshotSha256: job.snapshotSha256, policyVersion: POLICY_VERSION, result, createdAt: Date.now() });
    await ctx.db.patch(job._id, { status: "complete", reasons: decision.reasons });
    const models = args.passes.slice(0, 2).map(pass => ({ model: pass.model, revision: pass.modelVersion }));
    if (decision.kind !== "publish") {
      await ctx.db.patch(submission._id, { status: decision.kind === "reject" ? "rejected" : "held", reviewedAt: Date.now(), ...(decision.kind === "reject" ? { firstRejectedAt: submission.firstRejectedAt ?? Date.now(), expiresAt: (submission.firstRejectedAt ?? Date.now()) + APPEAL_WINDOW_MS } : {}) });
      const retryable = decision.kind === "exception" && snapshot.clean && snapshot.licensed && snapshot.provenance && !snapshot.abuse;
      let caseId = job.caseId;
      if (retryable && !caseId) {
        caseId = await queueEvidenceCase(ctx, { kind: "exception", target: { kind: "submission", submissionId: submission._id }, reason: "review", expiresAt: submission.expiresAt ?? Date.now() + APPEAL_WINDOW_MS });
        await ctx.db.patch(caseId, { attempts: 1 });
        await ctx.db.patch(job._id, { caseId });
      }
      if (!retryable) await revokeEvidencePublication(ctx, submission._id, "review", automatedActor, models);
      await finishEvidenceCase(ctx, caseId, "private", models, retryable);
      await appendEvidenceAudit(ctx, { receipt: submission.auditReceipt ?? crypto.randomUUID(), actor: automatedActor, reason: "review", before: "under_review", after: decision.kind === "reject" ? "rejected" : "held", models });
      return false;
    }
    // Replace the old publication only after the new snapshot passed. A report
    // alone is not authority to remove licensed content while review is pending.
    await revokeEvidencePublication(ctx, submission._id, "review", automatedActor, models, true);
    const defaults = await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", submission.hadithId).eq("language", submission.language).eq("isDefault", true)).collect();
    for (const row of defaults) await ctx.db.patch(row._id, { isDefault: false, updatedAt: Date.now() });
    const citations = snapshot.assessments.flatMap(item => item.grant ? [item.grant.citation] : []);
    const revisionId = await ctx.db.insert("evidencePublicationRevisions", { submissionId: submission._id, status: "published", snapshotSha256: snapshot.binding, policyVersion: POLICY_VERSION, citations, outputSha256: await textDigest(submission.proposedContent), permissionDependencies: snapshot.permissionDependencies, comparisonPublicationIds: snapshot.comparisonPublicationIds, scanBindings: snapshot.scanBindings, accessDependencies: snapshot.accessDependencies, previousDefaultIds: defaults.map(row => row._id),
      permissions: snapshot.permissions.map(grant => ({ licenseName: grant.licenseName, permissionUrl: grant.permissionUrl, attribution: grant.attribution, offline: grant.offline })), createdAt: Date.now() });
    const translationId = await ctx.db.insert("translations", { hadithId: submission.hadithId, language: submission.language, content: submission.proposedContent, source: "community", sourceLabel: "Community",
      contributorUserId: submission.submittedBy, status: "live", isDefault: true, groundingUsed: false,
      citations: snapshot.permissions.flatMap(grant => [{ url: grant.citation.url, title: `${grant.citation.title} · ${grant.citation.location}` }, { url: grant.permissionUrl, title: `${grant.licenseName} · ${grant.attribution}` }]),
      sourceReferenceUrl: citations[0]?.url, evidencePublicationId: revisionId, approvedAt: Date.now(), createdAt: Date.now(), updatedAt: Date.now() });
    await ctx.db.patch(revisionId, { translationId });
    await ctx.db.patch(submission._id, { status: "approved", reviewedAt: Date.now(), expiresAt: undefined, firstRejectedAt: undefined });
    await finishEvidenceCase(ctx, job.caseId, "published", models);
    const receipt = submission.auditReceipt ?? crypto.randomUUID();
    await appendEvidenceAudit(ctx, { receipt, actor: automatedActor, reason: "review", before: "under_review", after: "published", models });
    if (!job.caseId && sampleAudit(receipt)) await queueEvidenceCase(ctx, { kind: "audit", target: { kind: "submission", submissionId: submission._id }, reason: "audit", expiresAt: Date.now() + APPEAL_WINDOW_MS });
    return true;
  },
});
export const fail = internalMutation({
  args: { submissionId: v.id("communitySubmissions"), token: v.string(), reason: v.optional(v.union(v.literal("provider_authorization"), v.literal("provider_limit"), v.literal("provider_unavailable"), v.literal("invalid_response"))) },
  handler: async (ctx, args) => {
    await releaseWorker(ctx, args.token);
    const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", args.submissionId)).unique(), submission = await ctx.db.get(args.submissionId);
    if (!job || !submission || job.status !== "running" || job.token !== args.token || submission.status !== "under_review") return false;
    await unavailableReview(ctx, job, submission, args.reason ?? "provider_unavailable");
    return true;
  },
});
export const dispatch = internalMutation({
  args: {},
  handler: async ctx => {
    const stale = await ctx.db.query("evidenceReviewJobs").withIndex("by_status_deadline", q => q.eq("status", "running").lte("deadline", Date.now())).take(10);
    for (const job of stale) { const submission = await ctx.db.get(job.submissionId); if (submission?.status === "under_review") await unavailableReview(ctx, job, submission, "review_timeout"); }
    const rows = await ctx.db.query("communitySubmissions").withIndex("by_status", q => q.eq("status", "evidence_ready")).take(10);
    for (const row of rows) await ctx.scheduler.runAfter(0, internal.actions.evidenceReview.reviewSubmission, { submissionId: row._id });
    // Adopt completed uncertain reviews from the pre-E4 pipeline once. New jobs
    // already bind their case, so recovery cannot replenish a retry budget.
    const held = await ctx.db.query("communitySubmissions").withIndex("by_status", q => q.eq("status", "held")).take(10);
    for (const submission of held) {
      if ((submission.expiresAt ?? 0) <= Date.now()) continue;
      const job = await ctx.db.query("evidenceReviewJobs").withIndex("by_submission", q => q.eq("submissionId", submission._id)).unique();
      if (!job || job.caseId || job.status !== "complete" || !job.reasons.length || !job.reasons.every(reason => ["confidence", "consistency", "comparisons", "citations", "independence", "invalid_review"].includes(reason))) continue;
      const caseId = await queueEvidenceCase(ctx, { kind: "exception", target: { kind: "submission", submissionId: submission._id }, reason: "review", expiresAt: submission.expiresAt ?? Date.now() });
      await ctx.db.patch(caseId, { attempts: 1 }); await ctx.db.patch(job._id, { caseId });
    }
  },
});
