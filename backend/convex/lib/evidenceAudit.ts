import type { Doc } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { CASE_POLICY_VERSION } from "./evidenceCasePolicy";
import { POLICY_VERSION } from "./evidenceReviewPolicy";

type Facts = Pick<Doc<"evidenceAuditFacts">, "receipt" | "actor" | "reason" | "before" | "after" | "models">;
export async function appendEvidenceAudit(ctx: MutationCtx, facts: Facts): Promise<void> {
  await ctx.db.insert("evidenceAuditFacts", { ...facts, policyVersion: CASE_POLICY_VERSION, publicationPolicyVersion: POLICY_VERSION, createdAt: Date.now() });
}
export const automatedActor = { kind: "automated" } as const;
