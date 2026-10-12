import { internalMutation, internalQuery, query } from "./_generated/server";
import { internal } from "./_generated/api";
import { admitRate } from "./quotas";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";
import { purchaseAccess, subscriptionAccess } from "./lib/revenueCat";

export const beginRefresh = internalMutation({
  args: { clerkId: v.string(), deny: v.boolean(), ownershipConflict: v.boolean(), userInitiated: v.optional(v.boolean()) },
  handler: async (ctx, args) => {
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", args.clerkId)).unique();
    if (!user) return null;
    if (args.userInitiated && await admitRate(ctx, `subscription:${user._id}`, 5, user._id)) throw new Error("SUBSCRIPTION_RATE_LIMITED");
    const revision = (user.subscriptionRefreshRevision ?? 0) + 1;
    await ctx.db.patch(user._id, { subscriptionRefreshRevision: revision,
      ...(args.deny ? { subscriptionTier: "free" as const, subscriptionPurchases: [], entitlementExpiresAt: undefined } : {}),
      ...(args.ownershipConflict ? { subscriptionOwnershipConflict: true } : {}) });
    return { userId: user._id, revision };
  },
});
export const applySnapshot = internalMutation({
  args: { userId: v.id("users"), revision: v.number(), observedAt: v.number(), purchases: v.array(purchaseAccess), ownershipConflict: v.boolean() },
  handler: async (ctx, args) => {
    const user = await ctx.db.get(args.userId);
    if (!user || user.subscriptionRefreshRevision !== args.revision || args.observedAt < (user.subscriptionSnapshotAt ?? 0)) return false;
    const ownershipConflict = user.subscriptionOwnershipConflict === true || args.ownershipConflict;
    const access = subscriptionAccess({ subscriptionTier: "free", subscriptionPurchases: args.purchases, subscriptionOwnershipConflict: ownershipConflict }, Date.now());
    await ctx.db.patch(user._id, { subscriptionPurchases: args.purchases, subscriptionOwnershipConflict: ownershipConflict,
      subscriptionSnapshotAt: args.observedAt, subscriptionTier: access ? "pro" : "free", entitlementExpiresAt: access?.until,
      entitlementUpdatedAt: Date.now(), updatedAt: Date.now() });
    return { applied: true, pro: access !== null };
  },
});
export const deliveryCompleted = internalQuery({
  args: { eventId: v.string() }, handler: async (ctx, args) =>
    (await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_event", q => q.eq("eventId", args.eventId)).unique())?.state === "completed",
});
export const completeDelivery = internalMutation({
  args: { eventId: v.string() }, handler: async (ctx, args) => {
    const prior = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_event", q => q.eq("eventId", args.eventId)).unique();
    if (prior) {
      await ctx.db.patch(prior._id, { state: "completed" });
      for (const target of await ctx.db.query("subscriptionWebhookTargets").withIndex("by_receipt", q => q.eq("receiptId", prior._id)).collect()) await ctx.db.delete(target._id);
    }
  },
});

export const deliveryArgs = {
  eventId: v.string(), accountIds: v.array(v.string()), deny: v.boolean(), transferDestinations: v.array(v.string()),
};
export const enqueueDelivery = internalMutation({
  args: deliveryArgs, handler: async (ctx, args) => {
    const prior = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_event", q => q.eq("eventId", args.eventId)).unique();
    if (prior && prior.state !== "failed") return;
    const receiptId = prior?._id ?? await ctx.db.insert("subscriptionWebhookReceipts", { eventId: args.eventId, createdAt: Date.now(), queuedAt: Date.now(), state: "queued" });
    if (prior) await ctx.db.patch(prior._id, { state: "queued", queuedAt: Date.now() });
    else for (const clerkId of args.accountIds) {
      const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", clerkId)).unique();
      if (user) await ctx.db.insert("subscriptionWebhookTargets", { receiptId, userId: user._id, deny: args.deny, ownershipConflict: args.transferDestinations.includes(clerkId) });
    }
    await ctx.scheduler.runAfter(0, internal.actions.subscriptions.processDelivery, { eventId: args.eventId, attempt: 0 });
  },
});
export const deliveryTargets = internalQuery({
  args: { eventId: v.string() }, handler: async (ctx, args) => {
    const receipt = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_event", q => q.eq("eventId", args.eventId)).unique();
    if (!receipt || receipt.state === "completed") return [];
    const targets = await ctx.db.query("subscriptionWebhookTargets").withIndex("by_receipt", q => q.eq("receiptId", receipt._id)).collect();
    const result: { clerkId: string; deny: boolean; ownershipConflict: boolean }[] = [];
    for (const target of targets) {
      const user = await ctx.db.get(target.userId);
      if (user) result.push({ clerkId: user.clerkId, deny: target.deny, ownershipConflict: target.ownershipConflict });
    }
    return result;
  },
});
export const recoverDeliveries = internalMutation({
  args: {}, handler: async ctx => {
    const failed = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_state", q => q.eq("state", "failed")).take(20);
    const overdue = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_queue", q =>
      q.eq("state", "queued").lt("queuedAt", Date.now() - 3600000)).take(20 - failed.length);
    for (const row of [...failed, ...overdue]) {
      await ctx.db.patch(row._id, { state: "queued", queuedAt: Date.now() });
      await ctx.scheduler.runAfter(0, internal.actions.subscriptions.processDelivery, { eventId: row.eventId, attempt: 0 });
    }
  },
});
export const failDelivery = internalMutation({
  args: { eventId: v.string() }, handler: async (ctx, args) => {
    const row = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_event", q => q.eq("eventId", args.eventId)).unique();
    if (row && row.state !== "completed") await ctx.db.patch(row._id, { state: "failed" });
  },
});
export const pruneReceipts = internalMutation({
  args: {}, handler: async ctx => {
    const rows = await ctx.db.query("subscriptionWebhookReceipts").withIndex("by_time", q => q.lt("createdAt", Date.now() - 90 * 86400000)).take(100);
    for (const row of rows) {
      for (const target of await ctx.db.query("subscriptionWebhookTargets").withIndex("by_receipt", q => q.eq("receiptId", row._id)).collect()) await ctx.db.delete(target._id);
      await ctx.db.delete(row._id);
    }
    if (rows.length === 100) await ctx.scheduler.runAfter(0, internal.subscriptions.pruneReceipts, {});
  },
});

export const getStatus = query({
  args: {}, handler: async ctx => {
    const { clerkId } = await requireIdentity(ctx);
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", clerkId)).unique();
    if (!user) throw new Error("Unauthenticated");
    const access = subscriptionAccess(user, Date.now());
    return { subscriptionTier: access ? "pro" : "free", entitlementExpiresAt: access?.until ?? null,
      phase: access?.phase ?? (user.subscriptionOwnershipConflict ? "account_conflict" : "free"), store: access?.store ?? null };
  },
});
