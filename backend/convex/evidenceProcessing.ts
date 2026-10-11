import { v } from "convex/values";
import { internal } from "./_generated/api";
import { internalMutation, mutation } from "./_generated/server";
import type { MutationCtx } from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import { requireIdentity } from "./lib/identity";
import { storageHashMatches } from "./evidence";

const MAX_ATTEMPTS = 3;
const LEASE_MS = 3 * 60 * 1000;

async function scheduleNext(ctx: MutationCtx): Promise<void> {
  const active = await ctx.db.query("evidenceWorkerLease").withIndex("by_name", q => q.eq("name", "processor")).unique();
  if (active && active.deadline > Date.now()) return;
  if (active) await ctx.db.delete(active._id);
  const queued = await ctx.db.query("evidenceItems").withIndex("by_processing_queue", q => q.eq("processingQueued", true)).take(25);
  for (const item of queued) {
    const submission = await ctx.db.get(item.submissionId);
    if (submission?.status === "awaiting_processing" && (submission.expiresAt ?? 0) > Date.now()) {
      await ctx.scheduler.runAfter(0, internal.actions.evidenceProcessing.processItem, { itemId: item._id });
      return;
    }
    await ctx.db.patch(item._id, { processingQueued: false });
  }
}

const span = v.object({
  start: v.number(), end: v.number(),
  source: v.union(
    v.object({ kind: v.literal("html_chars"), start: v.number(), end: v.number() }),
    v.object({ kind: v.literal("page_box"), page: v.number(), x: v.number(), y: v.number(), width: v.number(), height: v.number() }),
  ),
});

const processingResult = v.union(
  v.object({ kind: v.literal("infected") }),
  v.object({ kind: v.literal("failed"), retryable: v.boolean() }),
  v.object({ kind: v.literal("ready"), mime: v.string(), sha256: v.string(), finalUrl: v.optional(v.string()), sourceStorageId: v.optional(v.id("_storage")), accessChain: v.optional(v.array(v.string())), text: v.string(), spans: v.array(span) }),
);

async function updateSubmission(ctx: MutationCtx, submissionId: Id<"communitySubmissions">): Promise<void> {
  const submission = await ctx.db.get(submissionId);
  if (!submission || submission.status !== "awaiting_processing") return;
  const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
  if (items.some(item => item.state === "infected")) {
    const extractions = await ctx.db.query("evidenceExtractions").withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
    for (const extraction of extractions) {
      if (extraction.sourceStorageId) await ctx.storage.delete(extraction.sourceStorageId);
      await ctx.db.delete(extraction._id);
    }
    for (const item of items) {
      const source = item.source;
      if (source.kind === "file" && source.storageId) await ctx.storage.delete(source.storageId);
      await ctx.db.patch(item._id, {
        ...(source.kind === "file" ? { source: { kind: "file" as const, declaredMime: source.declaredMime, declaredSize: source.declaredSize, declaredSha256: source.declaredSha256, displayName: source.displayName } } : {}),
        state: item.state === "infected" ? "infected" : "failed", retryable: false, processingLease: undefined, processingQueued: false,
      });
    }
    await ctx.db.patch(submissionId, { status: "infected" });
  } else if (items.every(item => item.state === "ready")) {
    await ctx.db.patch(submissionId, { status: "evidence_ready" });
    await ctx.scheduler.runAfter(0, internal.actions.evidenceReview.reviewSubmission, { submissionId });
  } else if (items.every(item => item.state === "ready" || item.state === "failed") && items.some(item => item.state === "failed")) {
    await ctx.db.patch(submissionId, { status: "processing_failed" });
  }
}

export const claim = internalMutation({
  args: { itemId: v.id("evidenceItems") },
  handler: async (ctx, args) => {
    const item = await ctx.db.get(args.itemId);
    if (!item) return null;
    const submission = await ctx.db.get(item.submissionId);
    if (!submission || submission.status !== "awaiting_processing" || (submission.expiresAt ?? 0) <= Date.now()) return null;
    const eligible = item.state === "quarantined_unscanned" || item.state === "pending_safe_fetch";
    if (!eligible || (item.processingAttempts ?? 0) >= MAX_ATTEMPTS) return null;
    const active = await ctx.db.query("evidenceWorkerLease").withIndex("by_name", q => q.eq("name", "processor")).unique();
    if (active && active.deadline > Date.now()) return null;
    if (active) await ctx.db.delete(active._id);
    const token = crypto.randomUUID();
    await ctx.db.insert("evidenceWorkerLease", { name: "processor", token, deadline: Date.now() + LEASE_MS });
    await ctx.db.patch(item._id, { state: "processing", processingQueued: false, processingAttempts: (item.processingAttempts ?? 0) + 1, processingLease: { token, deadline: Date.now() + LEASE_MS }, retryable: undefined, updatedAt: Date.now() });
    return { token, source: item.source, submissionId: item.submissionId, language: submission.language };
  },
});

export const finish = internalMutation({
  args: { itemId: v.id("evidenceItems"), token: v.string(), result: processingResult },
  handler: async (ctx, args) => {
    const worker = await ctx.db.query("evidenceWorkerLease").withIndex("by_name", q => q.eq("name", "processor")).unique();
    if (worker?.token === args.token) await ctx.db.delete(worker._id);
    const item = await ctx.db.get(args.itemId);
    if (!item || item.state !== "processing" || item.processingLease?.token !== args.token || item.processingLease.deadline <= Date.now()) { await scheduleNext(ctx); return false; }
    const submission = await ctx.db.get(item.submissionId);
    if (!submission || submission.status !== "awaiting_processing" || (submission.expiresAt ?? 0) <= Date.now()) { await scheduleNext(ctx); return false; }
    const now = Date.now();
    if (args.result.kind === "ready") {
      const result = args.result;
      const finalUrl = result.finalUrl ? new URL(result.finalUrl) : null;
      const snapshot = result.sourceStorageId ? await ctx.db.system.get(result.sourceStorageId) : null;
      const accessChain = result.accessChain;
      if (accessChain && (item.source.kind !== "url" || accessChain.length < 1 || accessChain.length > 4 || accessChain[0] !== item.source.url || accessChain.at(-1) !== result.finalUrl || accessChain.some(raw => {
        try { const url = new URL(raw); return url.protocol !== "https:" || !!url.username || !!url.password; } catch { return true; }
      }))) throw new Error("Invalid access chain");
      if (!/^[a-f0-9]{64}$/.test(result.sha256) || result.text.length > 100_000 || result.spans.length > 3_000 ||
          !["text/html", "application/pdf", "image/png", "image/jpeg", "image/webp"].includes(result.mime) ||
          (item.source.kind === "url" && (!finalUrl || finalUrl.protocol !== "https:" || finalUrl.username || finalUrl.password || result.mime === "text/html" && result.spans.some(entry => entry.source.kind !== "html_chars"))) ||
          (item.source.kind === "file" && (finalUrl !== null || result.mime === "text/html")) ||
          (item.source.kind === "url" && (!snapshot || snapshot.size > 10_000_000 || !storageHashMatches(snapshot.sha256, result.sha256))) ||
          (item.source.kind === "file" && result.sourceStorageId !== undefined) ||
          (item.source.kind === "file" && (result.sha256 !== item.source.sha256 || result.mime !== item.source.verifiedMime)) ||
          result.spans.some(entry => !Number.isInteger(entry.start) || !Number.isInteger(entry.end) || entry.start < 0 || entry.end > result.text.length || entry.start >= entry.end ||
            (entry.source.kind === "html_chars" ? !Number.isInteger(entry.source.start) || !Number.isInteger(entry.source.end) || entry.source.start < 0 || entry.source.start >= entry.source.end :
              !Number.isInteger(entry.source.page) || entry.source.page < 1 || entry.source.page > 25 || [entry.source.x, entry.source.y, entry.source.width, entry.source.height].some(value => !Number.isInteger(value) || value < 0 || value > 12_000)) ||
            result.text.slice(entry.start, entry.end).trim().length === 0)) throw new Error("Invalid processor result");
      const existing = await ctx.db.query("evidenceExtractions").withIndex("by_item", q => q.eq("evidenceItemId", item._id)).unique();
      if (existing) await ctx.db.delete(existing._id);
      await ctx.db.insert("evidenceExtractions", { submissionId: item.submissionId, evidenceItemId: item._id, trust: "untrusted", mime: result.mime, sha256: result.sha256, finalUrl: result.finalUrl, sourceStorageId: result.sourceStorageId, accessChain, text: result.text, spans: result.spans, createdAt: now });
      await ctx.db.patch(item._id, { state: "ready", processingLease: undefined, updatedAt: now });
    } else if (args.result.kind === "infected") {
      if (item.source.kind === "file" && item.source.storageId) {
        await ctx.storage.delete(item.source.storageId);
        await ctx.db.patch(item._id, { source: { kind: "file", declaredMime: item.source.declaredMime, declaredSize: item.source.declaredSize, declaredSha256: item.source.declaredSha256, displayName: item.source.displayName }, state: "infected", processingLease: undefined, updatedAt: now });
      } else await ctx.db.patch(item._id, { state: "infected", processingLease: undefined, updatedAt: now });
    } else {
      const retry = args.result.retryable && (item.processingAttempts ?? 0) < MAX_ATTEMPTS;
      await ctx.db.patch(item._id, { state: "failed", retryable: retry, processingLease: undefined, updatedAt: now });
    }
    await updateSubmission(ctx, item.submissionId);
    await scheduleNext(ctx);
    return true;
  },
});

export const retryOwnEvidenceProcessing = mutation({
  args: { submissionId: v.id("communitySubmissions"), itemId: v.id("evidenceItems") },
  handler: async (ctx, args) => {
    const identity = await requireIdentity(ctx);
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
    const submission = await ctx.db.get(args.submissionId);
    const item = await ctx.db.get(args.itemId);
    if (!user || !submission || !item || submission.submittedBy !== user._id || item.submissionId !== submission._id) throw new Error("Evidence item not found");
    if (!["awaiting_processing", "processing_failed"].includes(submission.status) || item.state !== "failed" || !item.retryable || (item.processingAttempts ?? 0) >= MAX_ATTEMPTS || (submission.expiresAt ?? 0) <= Date.now()) throw new Error("Evidence cannot be retried");
    await ctx.db.patch(item._id, { state: item.source.kind === "url" ? "pending_safe_fetch" : "quarantined_unscanned", processingQueued: true, retryable: undefined });
    await ctx.db.patch(submission._id, { status: "awaiting_processing" });
    await scheduleNext(ctx);
    return true;
  },
});

export const recoverStalled = internalMutation({
  args: {},
  handler: async ctx => {
    const rows = await ctx.db.query("evidenceItems").withIndex("by_processing_deadline", q => q.eq("state", "processing").lt("processingLease.deadline", Date.now())).take(25);
    let recovered = 0;
    for (const item of rows) {
      if (!item.processingLease || item.processingLease.deadline > Date.now()) continue;
      const submission = await ctx.db.get(item.submissionId);
      if (!submission || submission.status !== "awaiting_processing") continue;
      const retryable = (item.processingAttempts ?? 0) < MAX_ATTEMPTS;
      await ctx.db.patch(item._id, { state: "failed", retryable, processingLease: undefined, updatedAt: Date.now() });
      await updateSubmission(ctx, item.submissionId);
      recovered++;
    }
    await scheduleNext(ctx);
    return recovered;
  },
});

export const dispatchPending = internalMutation({
  args: {},
  handler: async ctx => {
    await scheduleNext(ctx);
  },
});

export const retryFailedAutomatically = internalMutation({ args: {}, handler: async ctx => {
  const failed = await ctx.db.query("evidenceItems").withIndex("by_retryable", q => q.eq("state", "failed").eq("retryable", true)).take(10);
  for (const item of failed) {
    const submission = await ctx.db.get(item.submissionId);
    if (!submission || !["awaiting_processing", "processing_failed"].includes(submission.status) || (submission.expiresAt ?? 0) <= Date.now() || (item.processingAttempts ?? 0) >= MAX_ATTEMPTS) continue;
    if (item.updatedAt + 60_000 * 2 ** (item.processingAttempts ?? 0) > Date.now()) continue;
    await ctx.db.patch(item._id, { state: item.source.kind === "url" ? "pending_safe_fetch" : "quarantined_unscanned", processingQueued: true, retryable: undefined });
    await ctx.db.patch(submission._id, { status: "awaiting_processing" });
  }
  await scheduleNext(ctx);
} });
