"use node";
import { reportFailure } from "../lib/reportFailure";
import { v } from "convex/values";
import { action, internalAction } from "../_generated/server";
import type { ActionCtx } from "../_generated/server";
import { internal } from "../_generated/api";
import { requireIdentity } from "../lib/identity";
import { parseRevenueCatSnapshot, revenueCatPolicy } from "../lib/revenueCat";

async function reconcile(ctx: ActionCtx, clerkId: string, deny: boolean, ownershipConflict: boolean, userInitiated = false): Promise<boolean> {
  const ticket = await ctx.runMutation(internal.subscriptions.beginRefresh, { clerkId, deny, ownershipConflict, userInitiated });
  if (!ticket) return false;
  const key = process.env.REVENUECAT_REST_API_KEY;
  if (!key) throw new Error("SUBSCRIPTIONS_NOT_CONFIGURED");
  const response = await fetch(`https://api.revenuecat.com/v1/subscribers/${encodeURIComponent(clerkId)}`, {
    headers: { Authorization: `Bearer ${key}` }, signal: AbortSignal.timeout(8000),
  });
  if (!response.ok) throw new Error("SUBSCRIPTION_REFRESH_UNAVAILABLE");
  const snapshot = parseRevenueCatSnapshot(await response.json(), clerkId, revenueCatPolicy());
  const result = await ctx.runMutation(internal.subscriptions.applySnapshot, { ...ticket, ...snapshot });
  if (result === false) throw new Error("SUBSCRIPTION_REFRESH_SUPERSEDED");
  return result.pro;
}
export const processDelivery = internalAction({
  args: { eventId: v.string(), attempt: v.number() },
  handler: async (ctx, args): Promise<void> => {
    if (await ctx.runQuery(internal.subscriptions.deliveryCompleted, { eventId: args.eventId })) return;
    try {
      const targets = await ctx.runQuery(internal.subscriptions.deliveryTargets, { eventId: args.eventId });
      for (let i = 0; i < targets.length; i += 5) {
        await Promise.all(targets.slice(i, i + 5).map(target =>
          reconcile(ctx, target.clerkId, target.deny, target.ownershipConflict)));
      }
      await ctx.runMutation(internal.subscriptions.completeDelivery, { eventId: args.eventId });
    } catch {
      await reportFailure(ctx, "subscription_refresh");
      if (args.attempt < 3) await ctx.scheduler.runAfter([60000, 300000, 900000][args.attempt],
        internal.actions.subscriptions.processDelivery, { ...args, attempt: args.attempt + 1 });
      else await ctx.runMutation(internal.subscriptions.failDelivery, { eventId: args.eventId });
    }
  },
});
export const refresh = action({
  args: {}, handler: async (ctx): Promise<boolean> => {
    const { clerkId } = await requireIdentity(ctx);
    return reconcile(ctx, clerkId, false, false, true);
  },
});
