import { v } from "convex/values";

export const CASE_POLICY_VERSION = "e4-v1";
export const DAY_MS = 86_400_000;
export const APPEAL_WINDOW_MS = 30 * DAY_MS;
export const MAX_CASE_ATTEMPTS = 3;
export const caseReason = v.union(v.literal("contributor_appeal"), v.literal("report"), v.literal("rights"), v.literal("privacy"), v.literal("unsafe"), v.literal("incorrect"), v.literal("policy"), v.literal("audit"), v.literal("retry_exhausted"), v.literal("expired"), v.literal("review"), v.literal("withdrawal"), v.literal("account_deletion"));
export const caseState = v.union(
  v.object({ kind: v.literal("queued"), dueAt: v.number() }),
  v.object({ kind: v.literal("running"), dueAt: v.number(), token: v.string() }),
  v.object({ kind: v.literal("resolved"), outcome: v.union(v.literal("published"), v.literal("private"), v.literal("expired"), v.literal("deleted")), closedAt: v.number() }),
);
export function retryAt(attempts: number, now: number): number | null {
  return attempts >= MAX_CASE_ATTEMPTS ? null : now + Math.min(60 * 60_000, 60_000 * 2 ** attempts);
}
export function appealAllowed(status: string, deadline: number | undefined, alreadyRequested: boolean, now: number): boolean {
  return ["held", "rejected", "review_unavailable", "revoked"].includes(status) && deadline !== undefined && deadline > now && !alreadyRequested;
}
export function sampleAudit(receipt: string): boolean {
  // Stable 5% sampling. Random receipts are assigned by trusted mutations.
  return /^[0-9a-f]$/.test(receipt[0] ?? "") && parseInt(receipt.slice(0, 8), 16) % 20 === 0;
}
