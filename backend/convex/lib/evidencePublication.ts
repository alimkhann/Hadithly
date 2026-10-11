import type { Doc, Id } from "../_generated/dataModel";
import type { QueryCtx, MutationCtx } from "../_generated/server";
import { canonicalJson } from "./offlineDumps";
import { textDigest, pathWithinPolicy } from "./evidenceReviewPolicy";
import { storageHashMatches } from "../evidence";

export async function currentPublicationPermissions(ctx: QueryCtx | MutationCtx, revision: Doc<"evidencePublicationRevisions"> | null, use: "comparison" | "offline" | "display") {
  const bindings = [];
  let valid = revision?.status === "published" && !!revision.permissionDependencies?.length;
  for (const dependency of revision?.permissionDependencies ?? []) {
    const requiredUse = use === "display" && dependency.use === "comparison" ? "comparison" : use;
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

export async function publicTranslationAvailable(ctx: QueryCtx | MutationCtx, row: Doc<"translations"> | null, visited: ReadonlySet<string> = new Set()): Promise<boolean> {
  if (!row || row.status !== "live") return false;
  if (!row.evidencePublicationId) return row.source !== "community";
  const revision = await ctx.db.get(row.evidencePublicationId);
  if (visited.has(row.evidencePublicationId) || visited.size >= 20) return false;
  if (!revision || revision.translationId !== row._id || revision.outputSha256 !== await textDigest(row.content)) return false;
  if (!(await currentPublicationPermissions(ctx, revision, "display")).valid) return false;
  if (!revision.scanBindings?.length || revision.scanBindings.length > 3) return false;
  for (const binding of revision.scanBindings) {
    const item = await ctx.db.get(binding.itemId), stored = await ctx.db.system.get(binding.storageId);
    if (!item || item.submissionId !== revision.submissionId || item.state !== "ready" || !stored || !storageHashMatches(stored.sha256, binding.sha256)) return false;
  }
  for (const dependency of revision.accessDependencies ?? []) {
    const row = await ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", dependency.origin).eq("policy.sourceKind", dependency.sourceKind)).unique();
    const policy = row?.policy.assessment;
    if (policy?.kind === "avoid" || dependency.sourceKind === "sunnah_com" && (!policy || policy.kind !== "permitted" || !policy.terms.access || policy.expiresAt <= Date.now() || !pathWithinPolicy(dependency.path, policy.pathPrefix))) return false;
  }
  const ancestry = new Set([...visited, revision._id]);
  for (const id of revision.comparisonPublicationIds ?? []) {
    const comparison = await ctx.db.get(id);
    if (!comparison || !(await currentPublicationPermissions(ctx, comparison, "comparison")).valid || !comparison.translationId || !await publicTranslationAvailable(ctx, await ctx.db.get(comparison.translationId), ancestry)) return false;
  }
  const dependencies = await ctx.db.query("evidenceSourceDependencies").withIndex("by_submission", q => q.eq("submissionId", revision.submissionId)).collect();
  for (const dependency of dependencies) {
    const policies = await ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", dependency.origin)).collect();
    if (policies.some(policy => policy.policy.assessment.kind === "avoid")) return false;
  }
  const abuse = await ctx.db.query("evidenceAbuseEvents").withIndex("by_submission", q => q.eq("submissionId", revision.submissionId)).collect();
  const deletion = await ctx.db.query("evidenceDeletionStates").withIndex("by_submission", q => q.eq("submissionId", revision.submissionId)).collect();
  return !abuse.some(row => row.status !== "none") && !deletion.some(row => row.status !== "active");
}

export async function publicationExpiry(ctx: QueryCtx | MutationCtx, id: Id<"evidencePublicationRevisions">, visited: ReadonlySet<string> = new Set()): Promise<number | null> {
  if (visited.has(id) || visited.size >= 20) return 0;
  const revision = await ctx.db.get(id);
  if (!revision) return 0;
  const deadlines = revision.permissionDependencies?.flatMap(dependency => dependency.kind === "grant" ? dependency.snapshot.expiresAt === undefined ? [] : [dependency.snapshot.expiresAt] : dependency.snapshot.assessment.kind === "permitted" ? [dependency.snapshot.assessment.expiresAt] : [0]) ?? [];
  for (const dependency of revision.accessDependencies ?? []) {
    if (dependency.sourceKind !== "sunnah_com") continue;
    const row = await ctx.db.query("evidenceSourcePolicies").withIndex("by_origin_kind", q => q.eq("policy.origin", dependency.origin).eq("policy.sourceKind", "sunnah_com")).unique();
    deadlines.push(row?.policy.assessment.kind === "permitted" ? row.policy.assessment.expiresAt : 0);
  }
  for (const comparisonId of revision.comparisonPublicationIds ?? []) {
    const deadline = await publicationExpiry(ctx, comparisonId, new Set([...visited, id]));
    if (deadline !== null) deadlines.push(deadline);
  }
  return deadlines.length ? Math.min(...deadlines) : null;
}
