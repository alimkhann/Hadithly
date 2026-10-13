import { v } from "convex/values";
import { internalAction, internalMutation, internalQuery } from "./_generated/server";
import { internal } from "./_generated/api";
import { operation, surface, MONTHLY_REPORT_CAP, REPORT_INTERVAL_MS, HEALTH_WINDOW_MS,
  HEARTBEAT_STALE_MS, diagnosticsEnvironment } from "./lib/diagnosticsPolicy";
import { DIAGNOSTICS_RELEASE } from "./lib/diagnosticsRelease";

export const recordFailure = internalMutation({
  args: { operation, surface, webRelease: v.optional(v.string()) },
  handler: async (ctx, args): Promise<boolean> => {
    if (process.env.DIAGNOSTICS_ENABLED !== "1") return false;
    const now = Date.now(), month = new Date(now).toISOString().slice(0, 7);
    const existing = await ctx.db.query("diagnosticsState").unique();
    const row = existing?.month === month ? existing : null;
    const web = args.surface === "web";
    if (row && (web ? row.webReports >= 200 : row.reports >= 800)) return false;
    const recent = row && now - row.windowStart < HEALTH_WINDOW_MS;
    const failures = recent ? row.failures + 1 : 1;
    const send = !row || now - (web ? row.lastWebReportAt : row.lastReportAt) >= REPORT_INTERVAL_MS
      || (args.operation === "synthetic" && diagnosticsEnvironment() === "development");
    if (!send) return false;
    const values = { month, reports: (row?.reports ?? 0) + (web ? 0 : 1), webReports: (row?.webReports ?? 0) + (web ? 1 : 0),
      failures: web ? row?.failures ?? 0 : Math.min(5, failures), windowStart: web ? row?.windowStart ?? 0 : recent ? row.windowStart : now,
      lastFailureAt: web ? row?.lastFailureAt ?? 0 : now, lastReportAt: web ? row?.lastReportAt ?? 0 : now,
      lastWebReportAt: web ? now : row?.lastWebReportAt ?? 0,
      heartbeatAt: existing?.heartbeatAt ?? 0, alertTestUntil: existing?.alertTestUntil ?? 0 };
    if (existing) await ctx.db.replace(existing._id, values);
    else await ctx.db.insert("diagnosticsState", values);
    if (send) await ctx.scheduler.runAfter(0, internal.actions.diagnostics.send, {
      operation: args.operation, surface: args.surface,
      ...(args.surface === "web" && args.webRelease && /^hadithly@[a-f0-9]{12}$/.test(args.webRelease) ? { release: args.webRelease } : {}),
    });
    return send;
  },
});

export const heartbeat = internalMutation({
  args: {}, handler: async ctx => {
    if (process.env.DIAGNOSTICS_ENABLED !== "1") return;
    const row = await ctx.db.query("diagnosticsState").unique();
    const month = new Date().toISOString().slice(0, 7);
    if (row?.month === month) await ctx.db.patch(row._id, { heartbeatAt: Date.now() });
    else {
      const values = { month, reports: 0, webReports: 0, failures: 0, windowStart: 0, lastFailureAt: 0,
        lastReportAt: 0, lastWebReportAt: 0, heartbeatAt: Date.now(), alertTestUntil: 0 };
      if (row) await ctx.db.replace(row._id, values);
      else await ctx.db.insert("diagnosticsState", values);
    }
  },
});

export const health = internalQuery({
  args: { component: v.union(v.literal("api"), v.literal("notifications"), v.literal("alert_test")) },
  handler: async (ctx, args) => {
    const row = await ctx.db.query("diagnosticsState").unique(), now = Date.now();
    const enabled = process.env.DIAGNOSTICS_ENABLED === "1";
    const currentMonth = row?.month === new Date(now).toISOString().slice(0, 7);
    const quota = currentMonth && row.reports >= 800;
    const unhealthy = !enabled || (args.component === "alert_test" ? (row?.alertTestUntil ?? 0) > now
      : args.component === "notifications" ? !row || now - row.heartbeatAt > HEARTBEAT_STALE_MS
      : quota || (row && row.failures >= 5 && now - row.lastFailureAt < HEALTH_WINDOW_MS));
    return { status: unhealthy ? "degraded" : "ready", release: DIAGNOSTICS_RELEASE,
      environment: diagnosticsEnvironment(), component: args.component };
  },
});

export const synthetic = internalAction({
  args: {}, handler: async (ctx): Promise<boolean> => {
    if (diagnosticsEnvironment() !== "development") throw new Error("DEVELOPMENT_ONLY");
    return await ctx.runMutation(internal.diagnostics.recordFailure, { operation: "synthetic", surface: "backend" });
  },
});

export const alertTest = internalMutation({
  args: { enabled: v.boolean() }, handler: async (ctx, args) => {
    if (diagnosticsEnvironment() !== "development") throw new Error("DEVELOPMENT_ONLY");
    const row = await ctx.db.query("diagnosticsState").unique();
    if (!row) throw new Error("DIAGNOSTICS_NOT_READY");
    await ctx.db.patch(row._id, { alertTestUntil: args.enabled ? Date.now() + 15 * 60_000 : 0 });
  },
});
