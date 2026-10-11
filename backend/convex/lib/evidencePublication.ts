import type { Doc } from "../_generated/dataModel";
import type { QueryCtx, MutationCtx } from "../_generated/server";
import { canonicalJson } from "./offlineDumps";

export async function currentPublicationPermissions(ctx: QueryCtx | MutationCtx, revision: Doc<"evidencePublicationRevisions"> | null, use: "comparison" | "offline") {
  const bindings = [];
  let valid = revision?.status === "published" && !!revision.permissionDependencies?.length;
  for (const dependency of revision?.permissionDependencies ?? []) {
    const row = await ctx.db.get(dependency.id);
    bindings.push(row);
    const current = row && ("grant" in row ? row.grant : "policy" in row ? row.policy : null);
    valid = valid && canonicalJson(current) === canonicalJson(dependency.snapshot);
    if (dependency.kind === "grant") {
      const grant = dependency.snapshot;
      valid = valid && grant.revokedAt === undefined && (grant.expiresAt === undefined || grant.expiresAt > Date.now()) && (use === "offline" ? grant.offline : grant.comparison && grant.modelProcessing);
    } else {
      const policy = dependency.snapshot.assessment;
      valid = valid && policy.kind === "permitted" && policy.expiresAt > Date.now() && (use === "offline" ? policy.terms.offline : policy.terms.comparison && policy.terms.modelProcessing);
    }
  }
  return { valid, bindings };
}
