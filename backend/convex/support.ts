import { internalMutation, internalQuery, query } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import { internal } from "./_generated/api";
import { v } from "convex/values";
import { paginationOptsValidator } from "convex/server";
import { requireIdentity } from "./lib/identity";
import { DAY, supportFields, noticeKind, validEmail } from "./lib/supportPolicy";
import type { NoticeKind } from "./lib/supportPolicy";
import { monthlyGenerationSpendPolicy } from "./lib/generationPolicy";

async function state(ctx: MutationCtx) {
  const now = Date.now(), day = new Date(now).toISOString().slice(0, 10), month = day.slice(0, 7), minute = Math.floor(now / 60_000);
  let row = await ctx.db.query("operationsState").unique();
  if (!row) {
    const id = await ctx.db.insert("operationsState", { day, month, minute, ingressMinute: 0, ingressDaily: 0,
      supportDaily: 0, supportMonthly: 0, mailDaily: 0, mailMonthly: 0, suppressed: false });
    row = await ctx.db.get(id);
  }
  if (!row) throw new Error("OPERATIONS_STATE_MISSING");
  const current = { ...row,
    ingressMinute: row.minute === minute ? row.ingressMinute : 0, ingressDaily: row.day === day ? row.ingressDaily : 0,
    supportDaily: row.day === day ? row.supportDaily : 0, supportMonthly: row.month === month ? row.supportMonthly : 0,
    mailDaily: row.day === day ? row.mailDaily : 0, mailMonthly: row.month === month ? row.mailMonthly : 0,
    day, month, minute };
  const { _id, _creationTime, ...fields } = current;
  await ctx.db.patch(_id, fields);
  return current;
}
async function queueNotice(ctx: MutationCtx, kind: NoticeKind, reference: string) {
  const prior = await ctx.db.query("operationsMail").withIndex("by_kind_reference", q => q.eq("kind", kind).eq("reference", reference)).unique();
  if (prior) return;
  const mailId = await ctx.db.insert("operationsMail", { kind, reference, state: "queued",
    expiresAt: Date.now() + (kind.endsWith("_budget") ? 32 : 30) * DAY });
  await ctx.scheduler.runAfter(0, internal.actions.support.sendNotice, { mailId });
}
export const ingress = internalMutation({ args: {}, handler: async ctx => {
  if (process.env.SUPPORT_ENABLED !== "1") return false;
  const row = await state(ctx);
  if (row.ingressMinute >= 10 || row.ingressDaily >= 1000) return false;
  await ctx.db.patch(row._id, { ingressMinute: row.ingressMinute + 1, ingressDaily: row.ingressDaily + 1 });
  return true;
} });
export const accept = internalMutation({ args: { ...supportFields, emailHash: v.string() }, handler: async (ctx, args) => {
  if (process.env.SUPPORT_ENABLED !== "1") return "disabled";
  const row = await state(ctx);
  const prior = await ctx.db.query("supportRequests").withIndex("by_reference", q => q.eq("requestId", args.requestId)).unique();
  if (prior) return "duplicate";
  const rate = await ctx.db.query("supportRates").withIndex("by_hash", q => q.eq("emailHash", args.emailHash)).unique();
  if (row.supportDaily >= 20 || row.supportMonthly >= 200 || rate && rate.expiresAt > Date.now() && rate.count >= 3) return "limited";
  if (rate) await ctx.db.patch(rate._id, { count: rate.expiresAt > Date.now() ? rate.count + 1 : 1,
    expiresAt: rate.expiresAt > Date.now() ? rate.expiresAt : Date.now() + DAY });
  else await ctx.db.insert("supportRates", { emailHash: args.emailHash, count: 1, expiresAt: Date.now() + DAY });
  const { emailHash, ...fields } = args;
  await ctx.db.insert("supportRequests", { ...fields, expiresAt: Date.now() + 30 * DAY });
  await ctx.db.patch(row._id, { supportDaily: row.supportDaily + 1, supportMonthly: row.supportMonthly + 1 });
  await queueNotice(ctx, "support", args.requestId);
  if (row.supportMonthly + 1 === 160) await queueNotice(ctx, "support_budget", row.month);
  return "accepted";
} });
export const inbox = query({ args: { paginationOpts: paginationOptsValidator }, handler: async (ctx, args) => {
  const { clerkId } = await requireIdentity(ctx);
  const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", clerkId)).unique();
  if (user?.isAdmin !== true) throw new Error("Operator access required");
  return ctx.db.query("supportRequests").withIndex("by_expiry", q => q.gt("expiresAt", Date.now()))
    .paginate({ ...args.paginationOpts, numItems: Math.min(50, args.paginationOpts.numItems) });
} });
export const claimMail = internalMutation({ args: { mailId: v.id("operationsMail") }, handler: async (ctx, args) => {
  const mail = await ctx.db.get(args.mailId);
  if (!mail || mail.state !== "queued" || mail.expiresAt <= Date.now() || process.env.OPERATIONS_MAIL_ENABLED !== "1"
    || !process.env.RESEND_API_KEY || !validEmail(process.env.OPERATIONS_EMAIL ?? "")) return null;
  const row = await state(ctx);
  if (row.suppressed || row.mailDaily >= 50 || row.mailMonthly >= 500) return null;
  await ctx.db.patch(row._id, { mailDaily: row.mailDaily + 1, mailMonthly: row.mailMonthly + 1 });
  await ctx.db.patch(mail._id, { state: "attempted" });
  return { kind: mail.kind, reference: mail.reference };
} });
export const finishMail = internalMutation({ args: { mailId: v.id("operationsMail"), providerId: v.optional(v.string()) }, handler: async (ctx, args) => {
  const mail = await ctx.db.get(args.mailId);
  if (mail?.state !== "attempted") return;
  if (args.providerId) await ctx.db.patch(mail._id, { state: "sent", providerId: args.providerId });
} });
export const mailEvent = internalMutation({ args: { providerId: v.string(), outcome: v.union(v.literal("delivered"), v.literal("bounced"), v.literal("complained")) }, handler: async (ctx, args) => {
  const mail = await ctx.db.query("operationsMail").withIndex("by_provider", q => q.eq("providerId", args.providerId)).unique();
  if (!mail) return false;
  if (args.outcome === "bounced" || args.outcome === "complained") {
    const row = await state(ctx); await ctx.db.patch(row._id, { suppressed: true });
    await ctx.db.patch(mail._id, { state: args.outcome });
  } else if (mail.state === "sent") await ctx.db.patch(mail._id, { state: "delivered" });
  return true;
} });
export const budgetWarnings = internalMutation({ args: {}, handler: async ctx => {
  const month = new Date().toISOString().slice(0, 7);
  const policy = monthlyGenerationSpendPolicy(Date.now());
  const budget = await ctx.db.query("aiSpendBudgets").withIndex("by_month", q => q.eq("monthKey", policy.monthKey)).unique();
  if (budget && budget.committedMicroUsd >= Math.ceil(policy.budgetMicroUsd * 0.8))
    await queueNotice(ctx, "ai_budget", month);
  const review = await ctx.db.query("reviewMonthlyBudgets").withIndex("by_month", q => q.eq("month", month)).unique();
  if (review && review.attempts >= 80) await queueNotice(ctx, "review_budget", month);
} });
export const testNotice = internalMutation({ args: {}, handler: async ctx => {
  await queueNotice(ctx, "test", new Date().toISOString().slice(0, 10));
} });
export const dispatch = internalMutation({ args: {}, handler: async ctx => {
  if (process.env.OPERATIONS_MAIL_ENABLED !== "1") return;
  const queued = await ctx.db.query("operationsMail").withIndex("by_state", q => q.eq("state", "queued")).take(10);
  for (const mail of queued) if (mail.expiresAt > Date.now()) await ctx.scheduler.runAfter(0, internal.actions.support.sendNotice, { mailId: mail._id });
} });
export const health = internalQuery({ args: {}, handler: async ctx => {
  const row = await ctx.db.query("operationsState").unique();
  return { mailEnabled: process.env.OPERATIONS_MAIL_ENABLED === "1", suppressed: row?.suppressed ?? false,
    supportEnabled: process.env.SUPPORT_ENABLED === "1", mailMonthly: row?.mailMonthly ?? 0 };
} });
export const retain = internalMutation({ args: {}, handler: async ctx => {
  for (const table of ["supportRequests", "supportRates", "operationsMail"] as const) {
    const rows = await ctx.db.query(table).withIndex("by_expiry", q => q.lte("expiresAt", Date.now())).take(100);
    for (const row of rows) await ctx.db.delete(row._id);
    if (rows.length === 100) await ctx.scheduler.runAfter(0, internal.support.retain, {});
  }
  const old = await ctx.db.query("reviewMonthlyBudgets").withIndex("by_month", q => q.lt("month", new Date(Date.now() - 90 * DAY).toISOString().slice(0, 7))).take(12);
  for (const row of old) await ctx.db.delete(row._id);
} });
