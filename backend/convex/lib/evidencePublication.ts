import type { Doc, Id } from "../_generated/dataModel";
import type { QueryCtx, MutationCtx } from "../_generated/server";
import { canonicalJson } from "./offlineDumps";
import { textDigest, pathWithinPolicy } from "./evidenceReviewPolicy";
import { storageHashMatches } from "../evidence";
import { generationIdentity } from "./generationPolicy";

export class PublicationReadBudget {
  private failed = false;
  private readsLeft: number;
  constructor(limit: number) { this.readsLeft = limit; }
  get remaining(): number { return this.readsLeft; }
  get exhausted(): boolean { return this.failed; }
  spend(count: number): boolean {
    if (this.failed || count > this.readsLeft) { this.failed = true; return false; }
    this.readsLeft -= count;
    return true;
  }
}

export async function knownMeaningReversal(ctx: QueryCtx | MutationCtx, hadith: Doc<"hadiths">, language: string, content: string): Promise<boolean> {
  const contentSha256 = await textDigest(content);
  const incident = await ctx.db.query("firstReadingBlockedTexts").withIndex("by_exact_text", q =>
    q.eq("locale", language).eq("canonicalId", `${hadith.provider}:${hadith.collectionSlug}:${hadith.providerHadithId}`)
      .eq("contentSha256", contentSha256)).unique();
  return incident?.reason === "meaning_reversal";
}

export async function currentPublicationPermissions(ctx: QueryCtx | MutationCtx, revision: Doc<"evidencePublicationRevisions"> | null, use: "comparison" | "offline" | "display", budget?: PublicationReadBudget) {
  const bindings = [];
  let valid = revision?.status === "published" && !!revision.permissionDependencies?.length;
  for (const dependency of revision?.permissionDependencies ?? []) {
    const requiredUse = use === "display" && dependency.use === "comparison" ? "comparison" : use;
    if (budget && !budget.spend(1)) return { valid: false, bindings };
    const row = await ctx.db.get(dependency.id);
    bindings.push(row);
    const current = row && ("grant" in row ? row.grant : "policy" in row ? row.policy : null);
    valid = valid && canonicalJson(current) === canonicalJson(dependency.snapshot);
    if (dependency.kind === "grant") {
      const grant = dependency.snapshot;
      valid = valid && grant.revokedAt === undefined && (grant.expiresAt === undefined || grant.expiresAt > Date.now()) && grant.conditions === "attribution_only" && grant.access && (requiredUse === "offline" ? grant.offline : requiredUse === "display" ? grant.adaptation && grant.display && grant.redistribution : grant.comparison && grant.modelProcessing);
    } else {
      const policy = dependency.snapshot.assessment;
      valid = valid && policy.kind === "permitted" && policy.expiresAt > Date.now() && policy.terms.conditions === "attribution_only" && policy.terms.access && (requiredUse === "offline" ? policy.terms.offline : requiredUse === "display" ? policy.terms.adaptation && policy.terms.display && policy.terms.redistribution : policy.terms.comparison && policy.terms.modelProcessing);
    }
  }
  return { valid, bindings };
}

export async function publicTranslationAvailable(ctx: QueryCtx | MutationCtx, row: Doc<"translations"> | null, visited: ReadonlySet<string> = new Set(), budget?: PublicationReadBudget): Promise<boolean> {
  if (!row || row.status !== "live") return false;
  if (budget && !budget.spend(2)) return false;
  const hadith = await ctx.db.get(row.hadithId);
  if (!hadith) return false;
  // Standalone suitability affects first reading only; a known meaning reversal
  // must also disappear from ordinary reader, cache and publication reads.
  if (await knownMeaningReversal(ctx, hadith, row.language, row.content)) return false;
  if (row.source === "gemini_ai" && row.generationKey) {
    if (budget && !budget.spend(1)) return false;
    const license = hadith.licenseRecordId ? await ctx.db.get(hadith.licenseRecordId) : null;
    if (row.generationKey !== (await generationIdentity(hadith, row.language)).generationKey ||
      license?.terms.kind !== "verified" || !license.terms.permitsDisplay) return false;
  }
  if (!row.evidencePublicationId) return row.source !== "community";
  if (budget && !budget.spend(1)) return false;
  const revision = await ctx.db.get(row.evidencePublicationId);
  if (visited.has(row.evidencePublicationId) || visited.size >= 20) return false;
  if (!revision || revision.translationId !== row._id || revision.outputSha256 !== await textDigest(row.content)) return false;
  if (!(await currentPublicationPermissions(ctx, revision, "display", budget)).valid) return false;
  if (!revision.scanBindings?.length || revision.scanBindings.length > 3) return false;
  for (const binding of revision.scanBindings) {
    if (budget && !budget.spend(2)) return false;
    const item = await ctx.db.get(binding.itemId), stored = await ctx.db.system.get(binding.storageId);
    if (!item || item.submissionId !== revision.submissionId || item.state !== "ready" || !stored || !storageHashMatches(stored.sha256, binding.sha256)) return false;
  }
  for (const dependency of revision.accessDependencies ?? []) {
    if (budget && !budget.spend(1)) return false;
    const row = await ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", dependency.origin).eq("policy.sourceKind", dependency.sourceKind)).unique();
    const policy = row?.policy.assessment;
    if (policy?.kind === "avoid" || dependency.sourceKind === "sunnah_com" && (!policy || policy.kind !== "permitted" || !policy.terms.access || policy.expiresAt <= Date.now() || !pathWithinPolicy(dependency.path, policy.pathPrefix))) return false;
  }
  const ancestry = new Set([...visited, revision._id]);
  for (const id of revision.comparisonPublicationIds ?? []) {
    if (budget && !budget.spend(2)) return false;
    const comparison = await ctx.db.get(id);
    if (!comparison || !(await currentPublicationPermissions(ctx, comparison, "comparison", budget)).valid || !comparison.translationId || !await publicTranslationAvailable(ctx, await ctx.db.get(comparison.translationId), ancestry, budget)) return false;
  }
  const dependencyQuery = ctx.db.query("evidenceSourceDependencies").withIndex("by_submission", q => q.eq("submissionId", revision.submissionId));
  const dependencies = budget ? await dependencyQuery.take(budget.remaining + 1) : await dependencyQuery.collect();
  if (budget && !budget.spend(dependencies.length)) return false;
  for (const dependency of dependencies) {
    const policyQuery = ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", dependency.origin));
    const policies = budget ? await policyQuery.take(budget.remaining + 1) : await policyQuery.collect();
    if (budget && !budget.spend(policies.length)) return false;
    if (policies.some(policy => policy.policy.assessment.kind === "avoid")) return false;
  }
  const abuseQuery = ctx.db.query("evidenceAbuseEvents").withIndex("by_submission", q => q.eq("submissionId", revision.submissionId));
  const abuse = budget ? await abuseQuery.take(budget.remaining + 1) : await abuseQuery.collect();
  if (budget && !budget.spend(abuse.length)) return false;
  const deletionQuery = ctx.db.query("evidenceDeletionStates").withIndex("by_submission", q => q.eq("submissionId", revision.submissionId));
  const deletion = budget ? await deletionQuery.take(budget.remaining + 1) : await deletionQuery.collect();
  if (budget && !budget.spend(deletion.length)) return false;
  return !abuse.some(row => row.status !== "none") && !deletion.some(row => row.status !== "active");
}

export async function publicationExpiry(ctx: QueryCtx | MutationCtx, id: Id<"evidencePublicationRevisions">, visited: ReadonlySet<string> = new Set(), budget?: PublicationReadBudget): Promise<number | null> {
  if (visited.has(id) || visited.size >= 20) return 0;
  if (budget && !budget.spend(1)) return 0;
  const revision = await ctx.db.get(id);
  if (!revision) return 0;
  const deadlines = revision.permissionDependencies?.flatMap(dependency => dependency.kind === "grant" ? dependency.snapshot.expiresAt === undefined ? [] : [dependency.snapshot.expiresAt] : dependency.snapshot.assessment.kind === "permitted" ? [dependency.snapshot.assessment.expiresAt] : [0]) ?? [];
  for (const dependency of revision.accessDependencies ?? []) {
    if (dependency.sourceKind !== "sunnah_com") continue;
    if (budget && !budget.spend(1)) return 0;
    const row = await ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", dependency.origin).eq("policy.sourceKind", "sunnah_com")).unique();
    deadlines.push(row?.policy.assessment.kind === "permitted" ? row.policy.assessment.expiresAt : 0);
  }
  for (const comparisonId of revision.comparisonPublicationIds ?? []) {
    const deadline = await publicationExpiry(ctx, comparisonId, new Set([...visited, id]), budget);
    if (deadline !== null) deadlines.push(deadline);
  }
  return deadlines.length ? Math.min(...deadlines) : null;
}
