import type { Id } from "../_generated/dataModel";
import type { MutationCtx } from "../_generated/server";
import { DAY_MS } from "./evidenceCasePolicy";

export async function admitEvidenceRequest(ctx: MutationCtx, userId: Id<"users">, kind: "submission" | "report" | "appeal"): Promise<void> {
  const cap = kind === "appeal" ? 3 : 5;
  const events = await ctx.db.query("evidenceRequestEvents").withIndex("by_user_kind_time", q => q.eq("userId", userId).eq("kind", kind).gte("createdAt", Date.now() - DAY_MS)).take(cap);
  if (events.length >= cap) throw new Error(kind === "submission" ? "Daily evidence submission limit reached" : "Daily contribution request limit reached");
  const blocked = await ctx.db.query("evidenceAbuseEvents").withIndex("by_owner", q => q.eq("ownerUserId", userId)).collect();
  if (blocked.some(row => row.status === "blocked")) throw new Error("Contribution requests are unavailable");
  await ctx.db.insert("evidenceRequestEvents", { userId, kind, createdAt: Date.now() });
}
