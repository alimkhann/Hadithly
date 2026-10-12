import { internalMutation, query } from "./_generated/server";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { v } from "convex/values";
import { requireIdentity } from "./lib/identity";
import { availableDefault } from "./translations";
import { publicTranslationAvailable } from "./lib/evidencePublication";
import { GENERATION_MODEL, GENERATION_PROMPT_VERSION, LEASE_MS, PRICING_VERSION, WINDOW_MS,
  generationIdentity, generationLanguage, generationLimit, generationSourceAllowed, rollingAllowance, telemetryValidator, tokenCostMicroUsd } from "./lib/generationPolicy";

export async function allowanceFor(ctx: QueryCtx | MutationCtx, user: Doc<"users">, now: number) {
  const charges = await ctx.db.query("aiUsageCharges").withIndex("by_user_time", q =>
    q.eq("userId", user._id).gt("createdAt", now - WINDOW_MS).lte("createdAt", now)).collect();
  const pending = await ctx.db.query("aiGenerationJobs").withIndex("by_user_status_expiry", q =>
    q.eq("userId", user._id).eq("status", "pending").gt("expiresAt", now)).take(3);
  return rollingAllowance({ now, limit: generationLimit(user, now), successes: charges.map(row => row.createdAt),
    reservations: pending.map(row => row.expiresAt) });
}

export const getTranslationAllowance = query({
  args: {},
  handler: async ctx => {
    const identity = await requireIdentity(ctx);
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
    if (!user) throw new Error("Unauthenticated: account no longer exists");
    return allowanceFor(ctx, user, Date.now());
  },
});

/** Fixed one-minute abuse buckets; they are not usage or entitlement counters. */
export async function admitRate(ctx: MutationCtx, key: string, limit: number, userId?: Id<"users">): Promise<number | null> {
  const now = Date.now();
  const bucket = await ctx.db.query("aiRateLimits").withIndex("by_key", q => q.eq("key", key)).unique();
  if (bucket && now < bucket.startedAt + 60_000 && bucket.count >= limit) return bucket.startedAt + 60_000;
  if (bucket) await ctx.db.patch(bucket._id, now >= bucket.startedAt + 60_000
    ? { startedAt: now, count: 1 } : { count: bucket.count + 1 });
  else await ctx.db.insert("aiRateLimits", { key, userId, startedAt: now, count: 1 });
  return null;
}

type Admission =
  | { kind: "cached"; translation: Doc<"translations"> }
  | { kind: "busy"; retryAt: number }
  | { kind: "rejected"; code: string; retryAt: number | null }
  | { kind: "claimed"; jobId: Id<"aiGenerationJobs">; attempt: number; hadith: Doc<"hadiths"> };

export const admit = internalMutation({
  args: { hadithId: v.id("hadiths"), language: v.string(), clerkId: v.optional(v.string()),
    verifiedGenerationKey: v.optional(v.string()),
    signal: v.union(v.literal("app_attest"), v.literal("play_integrity"), v.literal("unavailable_dev"), v.literal("service")) },
  handler: async (ctx, args): Promise<Admission> => {
    const now = Date.now(), language = generationLanguage(args.language);
    const hadith = await ctx.db.get(args.hadithId);
    if (!hadith) return { kind: "rejected", code: "UNKNOWN_HADITH", retryAt: null };
    const cached = await availableDefault(ctx, hadith, language);
    if (cached) return { kind: "cached", translation: cached };
    const identity = await generationIdentity(hadith, language);
    if (args.verifiedGenerationKey && args.verifiedGenerationKey !== identity.generationKey)
      return { kind: "rejected", code: "AI_INTEGRITY_REJECTED", retryAt: null };
    const job = await ctx.db.query("aiGenerationJobs").withIndex("by_key", q => q.eq("generationKey", identity.generationKey)).unique();
    if (job?.status === "pending" && job.expiresAt > now) return { kind: "busy", retryAt: job.expiresAt };
    // A withdrawn result must not be recreated under an already-successful key.
    const success = await ctx.db.query("aiUsageEvents").withIndex("by_key", q => q.eq("generationKey", identity.generationKey)).unique();
    if (success) return { kind: "rejected", code: "AI_TRANSLATION_UNAVAILABLE", retryAt: null };
    const license = hadith.licenseRecordId ? await ctx.db.get(hadith.licenseRecordId) : null;
    if (license?.terms.kind !== "verified" || !license.terms.permitsDisplay || !generationSourceAllowed(hadith))
      return { kind: "rejected", code: "AI_SOURCE_UNAVAILABLE", retryAt: null };
    const clerkId = args.clerkId;
    const user = clerkId ? await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", clerkId)).unique() : null;
    if (args.signal !== "service" && !user) return { kind: "rejected", code: "Unauthenticated", retryAt: null };
    if (args.signal === "service" && args.clerkId) return { kind: "rejected", code: "INVALID_GENERATION_ORIGIN", retryAt: null };
    if (user) {
      const allowance = await allowanceFor(ctx, user, now);
      if (!allowance.remaining) return { kind: "rejected", code: "AI_GENERATION_QUOTA_EXCEEDED", retryAt: allowance.retryAt };
      if (allowance.reserved >= 2) return { kind: "rejected", code: "AI_GENERATION_BUSY", retryAt: now + 5_000 };
      const retryAt = await admitRate(ctx, `generation:${user._id}`, args.signal === "unavailable_dev" ? 5 : 10, user._id);
      if (retryAt) return { kind: "rejected", code: "AI_RATE_LIMITED", retryAt };
    }
    const active = await ctx.db.query("aiGenerationJobs").withIndex("by_status_expiry", q => q.eq("status", "pending").gt("expiresAt", now)).take(10);
    if (active.length >= 10) return { kind: "rejected", code: "AI_GENERATION_BUSY", retryAt: active[0].expiresAt };
    const globalBucket = await ctx.db.query("aiRateLimits").withIndex("by_key", q => q.eq("key", "generation:global")).unique();
    if (globalBucket && now < globalBucket.startedAt + 60000 && globalBucket.count >= 60)
      return { kind: "rejected", code: "AI_RATE_LIMITED", retryAt: globalBucket.startedAt + 60000 };
    // The global daily bound includes failed provider attempts, unlike allowance.
    const dailyRetry = await admitDailySpend(ctx, now, false);
    if (dailyRetry) return { kind: "rejected", code: "AI_SERVICE_LIMIT", retryAt: dailyRetry };
    const freePool = !user || generationLimit(user, now) === 5;
    const spend = await reserveMonthlySpend(ctx, now, freePool);
    if (spend.kind === "rejected") return { kind: "rejected", code: "AI_SERVICE_LIMIT", retryAt: spend.retryAt };
    await admitDailySpend(ctx, now, true);
    await admitRate(ctx, "generation:global", 60);
    const attempt = (job?.attempt ?? 0) + 1;
    const fields = { ...identity, hadithId: hadith._id, language, userId: user?._id,
      origin: user ? "user" : "service", status: "pending", attempt, expiresAt: now + LEASE_MS, createdAt: now, translationId: undefined } satisfies Omit<Doc<"aiGenerationJobs">, "_id" | "_creationTime">;
    const jobId = job ? job._id : await ctx.db.insert("aiGenerationJobs", fields);
    if (job) await ctx.db.patch(job._id, fields);
    await ctx.db.insert("aiSpendReservations", { jobId, attempt, monthKey: spend.monthKey, reservedMicroUsd: spend.reservedMicroUsd, freePool, settled: false });
    return { kind: "claimed", jobId, attempt, hadith };
  },
});

async function admitDailySpend(ctx: MutationCtx, now: number, consume: boolean) {
  const key = "generation:daily", start = Math.floor(now / 86_400_000) * 86_400_000;
  const row = await ctx.db.query("aiRateLimits").withIndex("by_key", q => q.eq("key", key)).unique();
  if (row?.startedAt === start && row.count >= 500) return start + 86_400_000;
  if (!consume) return null;
  if (row) await ctx.db.patch(row._id, { startedAt: start, count: row.startedAt === start ? row.count + 1 : 1 });
  else await ctx.db.insert("aiRateLimits", { key, startedAt: start, count: 1 });
  return null;
}

// Reserve above the maximum source/output size at the pinned token rates.
// Unknown and abandoned attempts keep the reservation. Known usage releases
// unused money, so ordinary short translations do not hit a tiny attempt cap.
async function reserveMonthlySpend(ctx: MutationCtx, now: number, freePool: boolean): Promise<
  { kind: "reserved"; monthKey: string; reservedMicroUsd: number } | { kind: "rejected"; retryAt: number }
> {
  const date = new Date(now), start = Date.UTC(date.getUTCFullYear(), date.getUTCMonth(), 1);
  const next = Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1);
  const configured = Number(process.env.AI_MONTHLY_ATTEMPT_LIMIT ?? "25000");
  const limit = Number.isSafeInteger(configured) && configured > 0 && configured <= 100_000 ? configured : 25000;
  const configuredUsd = Number(process.env.AI_MONTHLY_BUDGET_USD ?? "10");
  const budgetMicroUsd = Math.floor((Number.isFinite(configuredUsd) && configuredUsd >= 0.02 && configuredUsd <= 1000 ? configuredUsd : 10) * 1_000_000);
  const reservedMicroUsd = 20_000, monthKey = String(start);
  const budget = await ctx.db.query("aiSpendBudgets").withIndex("by_month", q => q.eq("monthKey", monthKey)).unique();
  if ((budget?.committedMicroUsd ?? 0) + reservedMicroUsd > budgetMicroUsd) return { kind: "rejected", retryAt: next };
  const configuredFreeUsd = Number(process.env.AI_FREE_MONTHLY_BUDGET_USD ?? "2");
  const freeLimit = Math.min(budgetMicroUsd, Math.floor((Number.isFinite(configuredFreeUsd) && configuredFreeUsd >= 0 && configuredFreeUsd <= 1000 ? configuredFreeUsd : 2) * 1_000_000));
  // Pre-Q2 spend has no pool attribution. Count it as free until this month ends.
  const freeCommitted = budget?.freeCommittedMicroUsd ?? budget?.committedMicroUsd ?? 0;
  if (freePool && freeCommitted + reservedMicroUsd > freeLimit) return { kind: "rejected", retryAt: next };
  const key = "generation:monthly";
  const row = await ctx.db.query("aiRateLimits").withIndex("by_key", q => q.eq("key", key)).unique();
  if (row?.startedAt === start && row.count >= limit) return { kind: "rejected", retryAt: next };
  if (row) await ctx.db.patch(row._id, { startedAt: start, count: row.startedAt === start ? row.count + 1 : 1 });
  else await ctx.db.insert("aiRateLimits", { key, startedAt: start, count: 1 });
  if (budget) await ctx.db.patch(budget._id, { committedMicroUsd: budget.committedMicroUsd + reservedMicroUsd, freeCommittedMicroUsd: freeCommitted + (freePool ? reservedMicroUsd : 0) });
  else await ctx.db.insert("aiSpendBudgets", { monthKey, committedMicroUsd: reservedMicroUsd, freeCommittedMicroUsd: freePool ? reservedMicroUsd : 0 });
  return { kind: "reserved", monthKey, reservedMicroUsd };
}

export const finish = internalMutation({
  args: { jobId: v.id("aiGenerationJobs"), attempt: v.number(), telemetry: telemetryValidator,
    output: v.optional(v.object({ translation: v.string(), confidence: v.number(), riskFlags: v.array(v.string()), sourceReferenceUrl: v.optional(v.string()) })) },
  handler: async (ctx, args) => {
    const now = Date.now(), job = await ctx.db.get(args.jobId);
    if (!job) throw new Error("UNKNOWN_GENERATION");
    if (job.status === "completed" && job.attempt === args.attempt) {
      const row = job.translationId ? await ctx.db.get(job.translationId) : null;
      return row && await publicTranslationAvailable(ctx, row) ? { translation: row, cached: true } : null;
    }
    const priorCost = await ctx.db.query("aiCostEvents").withIndex("by_job_attempt", q => q.eq("jobId", job._id).eq("attempt", args.attempt)).unique();
    if (priorCost) return null;
    if (!Number.isSafeInteger(args.telemetry.durationMs) || args.telemetry.durationMs < 0 || args.telemetry.durationMs > LEASE_MS) throw new Error("INVALID_COST_TELEMETRY");
    const estimatedMicroUsd = tokenCostMicroUsd(args.telemetry);
    const reservation = await ctx.db.query("aiSpendReservations").withIndex("by_job_attempt", q => q.eq("jobId", job._id).eq("attempt", args.attempt)).unique();
    if (reservation && !reservation.settled) {
      const budget = await ctx.db.query("aiSpendBudgets").withIndex("by_month", q => q.eq("monthKey", reservation.monthKey)).unique();
      if (!budget) throw new Error("MISSING_SPEND_RESERVATION");
      const charged = args.telemetry.tokenUsageKnown ? estimatedMicroUsd : reservation.reservedMicroUsd;
      await ctx.db.patch(budget._id, { committedMicroUsd: budget.committedMicroUsd - reservation.reservedMicroUsd + charged,
        freeCommittedMicroUsd: (budget.freeCommittedMicroUsd ?? budget.committedMicroUsd) - (reservation.freePool !== false ? reservation.reservedMicroUsd - charged : 0) });
      await ctx.db.patch(reservation._id, { settled: true });
    }
    const stale = job.status !== "pending" || job.attempt !== args.attempt || job.expiresAt <= now;
    const hadith = await ctx.db.get(job.hadithId);
    const license = hadith?.licenseRecordId ? await ctx.db.get(hadith.licenseRecordId) : null;
    const sourceChanged = !hadith || (await generationIdentity(hadith, job.language)).sourceDigest !== job.sourceDigest ||
      license?.terms.kind !== "verified" || !license.terms.permitsDisplay;
    let outcome: "published" | "cached" | "failed" | "stale" = stale || sourceChanged ? "stale" : "failed";
    let translation: Doc<"translations"> | null = null;
    if (!stale && !sourceChanged && hadith) {
      translation = await availableDefault(ctx, hadith, job.language);
      if (translation) outcome = "cached";
      else if (args.output) {
        const text = args.output.translation.trim();
        if (!text || text.length > 24_000 || !Number.isFinite(args.output.confidence) || args.output.confidence < 0 || args.output.confidence > 1 || args.output.riskFlags.length > 30)
          throw new Error("INVALID_GENERATION_OUTPUT");
        for (const row of await ctx.db.query("translations").withIndex("by_hadith_language_default", q => q.eq("hadithId", hadith._id).eq("language", job.language).eq("isDefault", true)).collect())
          await ctx.db.patch(row._id, { isDefault: false });
        const user = job.userId ? await ctx.db.get(job.userId) : null;
        const translationId = await ctx.db.insert("translations", { hadithId: job.hadithId, language: job.language,
          content: text, source: "gemini_ai", sourceLabel: "AI", aiModel: GENERATION_MODEL, aiPromptVersion: GENERATION_PROMPT_VERSION,
          generationKey: job.generationKey, sourceDigest: job.sourceDigest, generatedByUserId: user?._id, status: "live", isDefault: true,
          confidence: args.output.confidence, riskFlags: args.output.riskFlags, groundingUsed: false, citations: [], sourceReferenceUrl: args.output.sourceReferenceUrl,
          createdAt: now, updatedAt: now });
        const eventId = await ctx.db.insert("aiUsageEvents", { generationKey: job.generationKey, translationId, createdAt: now });
        if (user) await ctx.db.insert("aiUsageCharges", { userId: user._id, eventId, createdAt: now });
        translation = await ctx.db.get(translationId);
        outcome = "published";
      }
    }
    await ctx.db.insert("aiCostEvents", { ...args.telemetry, jobId: job._id, attempt: args.attempt, model: GENERATION_MODEL,
      pricingVersion: PRICING_VERSION, estimatedMicroUsd, groundingUsed: false, outcome, createdAt: now });
    if (!stale) await ctx.db.patch(job._id, { status: translation ? "completed" : "failed", translationId: translation?._id, expiresAt: now });
    return translation ? { translation, cached: outcome === "cached" } : null;
  },
});
