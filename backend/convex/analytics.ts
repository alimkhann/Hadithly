import { v } from "convex/values";
import { internalMutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { DAY, HOUR, UUID, parseSummary, mergeCounters, isMetric, type Counter } from "./lib/analyticsPolicy";
import { diagnosticsEnvironment } from "./lib/diagnosticsPolicy";

const counter = v.object({ metric: v.string(), count: v.number() });
export const platform = v.union(v.literal("ios"), v.literal("android"));
export const enabled = () => process.env.ANALYTICS_ENABLED === "1";

export const accept = internalMutation({
  args: { version: v.number(), platform, batchId: v.string(), hour: v.number(), counters: v.array(counter) },
  handler: async (ctx, args): Promise<"accepted" | "duplicate" | "disabled" | "limited" | "invalid"> => {
    if (!enabled()) return "disabled";
    const now = Date.now(), summary = parseSummary(args, now);
    if (!summary) return "invalid";
    if (await ctx.db.query("analyticsReceipts").withIndex("by_batch", q => q.eq("batchId", summary.batchId)).unique()) return "duplicate";
    const today = new Date(now).toISOString().slice(0, 10), month = today.slice(0, 7);
    const day = new Date(summary.hour * HOUR).toISOString().slice(0, 10);
    const bucket = await ctx.db.query("analyticsBuckets").withIndex("by_day_platform", q => q.eq("day", day).eq("platform", summary.platform)).unique();
    if (bucket?.exported) return "invalid";
    const state = await ctx.db.query("analyticsState").unique();
    const daily = state?.day === today ? state.admittedDaily : 0;
    const monthly = state?.month === month ? state.admittedMonthly : 0;
    if (daily >= 2000 || monthly >= 50_000) return "limited";
    const values = { day: today, month, admittedDaily: daily + 1, admittedMonthly: monthly + 1,
      exportedMonthly: state?.month === month ? state.exportedMonthly : 0,
      rejectedMonthly: state?.month === month ? state.rejectedMonthly ?? 0 : 0,
      lastExportAt: state?.lastExportAt ?? 0, exportFailures: state?.month === month ? state.exportFailures : 0 };
    if (state) await ctx.db.replace(state._id, values); else await ctx.db.insert("analyticsState", values);
    const current: Counter[] = [];
    for (const item of bucket?.counters ?? []) if (isMetric(item.metric)) current.push({ metric: item.metric, count: item.count });
    if (bucket) await ctx.db.patch(bucket._id, { summaries: bucket.summaries + 1,
      counters: mergeCounters(current, summary.counters) });
    else await ctx.db.insert("analyticsBuckets", { day, platform: summary.platform, summaries: 1,
      counters: summary.counters, exported: false, expiresAt: (Math.floor(summary.hour / 24) + 1) * DAY + 7 * DAY });
    await ctx.db.insert("analyticsReceipts", { batchId: summary.batchId, expiresAt: summary.hour * HOUR + DAY });
    return "accepted";
  },
});

export const claim = internalMutation({
  args: { uuid: v.string(), verifyCurrentDay: v.optional(v.boolean()) }, handler: async (ctx, args) => {
    if (!enabled() || !process.env.ANALYTICS_POSTHOG_KEY || !UUID.test(args.uuid)) return null;
    const now = Date.now(), today = new Date(now).toISOString().slice(0, 10), month = today.slice(0, 7);
    const verification = args.verifyCurrentDay === true && process.env.ANALYTICS_VERIFY_CURRENT_DAY === "1"
      && process.env.CONVEX_CLOUD_URL === "https://festive-cobra-664.eu-west-1.convex.cloud";
    const candidates = await ctx.db.query("analyticsBuckets").withIndex("by_pending", q => q.eq("exported", false)).take(100);
    const bucket = candidates.find(row => (Date.parse(`${row.day}T00:00:00Z`) + 2 * DAY <= now || verification && row.day === today) && row.summaries >= 10
      && row.expiresAt > now && (row.attempts ?? 0) < 3 && (row.nextAttemptAt ?? 0) <= now);
    if (!bucket) return null;
    const state = await ctx.db.query("analyticsState").unique();
    if (!state) return null;
    const used = state.month === month ? state.exportedMonthly : 0;
    if (used + bucket.counters.length > 10_000) return null;
    const attempts = (bucket.attempts ?? 0) + 1;
    await ctx.db.patch(state._id, { month, admittedMonthly: state.month === month ? state.admittedMonthly : 0,
      rejectedMonthly: state.month === month ? state.rejectedMonthly ?? 0 : 0,
      exportFailures: state.month === month ? state.exportFailures : 0,
      exportedMonthly: used + bucket.counters.length });
    const uuid = bucket.exportId ?? args.uuid;
    await ctx.db.patch(bucket._id, { attempts, exportId: uuid, nextAttemptAt: now + 30_000 });
    return { id: bucket._id, attempt: attempts, uuid, day: bucket.day, platform: bucket.platform,
      counters: bucket.counters, environment: diagnosticsEnvironment(), health: { month,
        admittedMonthly: state.month === month ? state.admittedMonthly : 0, exportedMonthly: used + bucket.counters.length,
        exportFailures: state.month === month ? state.exportFailures : 0, rejectedMonthly: state.month === month ? state.rejectedMonthly ?? 0 : 0,
        suppressedBuckets: candidates.filter(row => row.summaries < 10 && row.expiresAt > now).length, observedHour: Math.floor(now / HOUR) } };
  },
});

export const settle = internalMutation({
  args: { id: v.id("analyticsBuckets"), attempt: v.number(), success: v.boolean() }, handler: async (ctx, args) => {
    const row = await ctx.db.get(args.id);
    if (!row || row.attempts !== args.attempt || row.exported) return;
    await ctx.db.patch(row._id, args.success ? { exported: true, expiresAt: Date.now() + 90 * DAY }
      : { nextAttemptAt: Date.now() + (args.attempt === 1 ? 60_000 : 300_000) });
    const state = await ctx.db.query("analyticsState").unique();
    if (state) await ctx.db.patch(state._id, args.success ? { lastExportAt: Date.now() }
      : { exportFailures: state.exportFailures + 1 });
  },
});

export const retain = internalMutation({ args: {}, handler: async (ctx): Promise<void> => {
  let remaining = false;
  for (const table of ["analyticsReceipts", "analyticsBuckets"] as const) {
    const rows = await ctx.db.query(table).withIndex("by_expiry", q => q.lte("expiresAt", Date.now())).take(100);
    for (const row of rows) await ctx.db.delete(row._id);
    remaining ||= rows.length === 100;
  }
  if (remaining) await ctx.scheduler.runAfter(0, internal.analytics.retain, {});
} });
export const recordRejection = internalMutation({ args: {}, handler: async ctx => {
  if (!enabled()) return;
  const today = new Date().toISOString().slice(0, 10), month = today.slice(0, 7);
  const state = await ctx.db.query("analyticsState").unique();
  if (state) await ctx.db.patch(state._id, { rejectedMonthly: Math.min(50_000, (state.month === month ? state.rejectedMonthly ?? 0 : 0) + 1),
    ...(state.month !== month ? { month, admittedMonthly: 0, exportedMonthly: 0, exportFailures: 0 } : {}) });
  else await ctx.db.insert("analyticsState", { day: today, month, admittedDaily: 0, admittedMonthly: 0, exportedMonthly: 0,
    lastExportAt: 0, exportFailures: 0, rejectedMonthly: 1 });
} });
export const health = internalQuery({ args: {}, handler: async ctx => {
  const state = await ctx.db.query("analyticsState").unique();
  const pending = await ctx.db.query("analyticsBuckets").withIndex("by_pending", q => q.eq("exported", false)).take(100);
  const oldest = pending.find(row => row.expiresAt > Date.now());
  return { enabled: enabled(), pendingBuckets: pending.length, suppressedBuckets: pending.filter(row => row.summaries < 10).length,
    exportLagDays: oldest ? Math.max(0, Math.floor((Date.now() - Date.parse(`${oldest.day}T00:00:00Z`)) / DAY) - 2) : 0, ...(state ? { day: state.day, month: state.month, admittedDaily: state.admittedDaily,
    admittedMonthly: state.admittedMonthly, exportedMonthly: state.exportedMonthly, lastExportAt: state.lastExportAt,
    exportFailures: state.exportFailures, rejectedMonthly: state.rejectedMonthly ?? 0,
    capExhausted: state.admittedDaily >= 2000 || state.admittedMonthly >= 50_000 || state.exportedMonthly >= 10_000,
    warning: state.admittedDaily >= 1600 || state.admittedMonthly >= 40_000 || state.exportedMonthly >= 8000 } : {}) };
} });
