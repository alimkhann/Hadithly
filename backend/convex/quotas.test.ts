/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { fixture as evidenceFixture, passes } from "../test/evidenceFixtures";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { normalizeHadith } from "./lib/sunnahNow";
import { generationIdentity, generationLanguage, LEASE_MS, rollingAllowance, tokenCostMicroUsd, WINDOW_MS } from "./lib/generationPolicy";
import { validPlayIntegrity } from "./lib/playIntegrity";
import { allowUnattestedDevelopment } from "./generationIntegrity";

const provider = vi.hoisted(() => vi.fn());
vi.mock("@google/genai", async importOriginal => {
  const actual = await importOriginal<typeof import("@google/genai")>();
  return { ...actual, GoogleGenAI: class { models = { generateContent: provider }; } };
});
const modules = import.meta.glob("./**/*.ts");
const telemetry = { inputTokens: 2000, outputTokens: 500, thinkingTokens: 0, tokenUsageKnown: true, durationMs: 100 };
const output = { translation: "Faithful fixture translation", confidence: 0.9, riskFlags: [] };

async function fixture(count = 8) {
  const t = convexTest(schema, modules);
  const owner = t.withIdentity({ subject: "q1-owner", tokenIdentifier: "fixture:q1-owner" });
  const userId = await owner.mutation(api.users.ensureCurrentUser, {});
  const hadithIds = await t.mutation(internal.hadiths.upsertPage, {
    items: Array.from({ length: count }, (_, i) => normalizeHadith("bukhari", { id: String(i + 1) })),
  });
  await t.run(async ctx => {
    for (const id of hadithIds) await ctx.db.patch(id, { arabicText: "نص عربي", englishText: "Public source" });
    const license = await ctx.db.query("licenseRecords").unique();
    if (!license) throw new Error("Missing fixture license");
    await ctx.db.patch(license._id, { terms: { kind: "verified", licenseName: "Fixture", licenseUrl: "https://example.test/terms", permitsDisplay: true,
      permitsRedistribution: false, permitsOfflineDistribution: false, verifiedAt: Date.now() } });
  });
  const admit = (index = 0, clerkId = "q1-owner") => t.mutation(internal.quotas.admit, { hadithId: hadithIds[index], language: "ru", clerkId, signal: "app_attest" });
  return { t, owner, userId, hadithIds, admit };
}

beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(1_800_000_000_000); provider.mockReset(); });
afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

async function seedCharges(f: Awaited<ReturnType<typeof fixture>>, times: number[]) {
  await f.t.run(async ctx => {
    for (const [i, createdAt] of times.entries()) {
      const translationId = await ctx.db.insert("translations", { hadithId: f.hadithIds[0], language: "kk", content: "fixture", source: "gemini_ai", sourceLabel: "AI", status: "live", groundingUsed: false, isDefault: false, createdAt, updatedAt: createdAt });
      const eventId = await ctx.db.insert("aiUsageEvents", { generationKey: `seed-${i}`, translationId, createdAt });
      await ctx.db.insert("aiUsageCharges", { userId: f.userId, eventId, createdAt });
    }
  });
}

describe("Q1 rolling allowance", () => {
  test("the exact seven-day boundary expires; future events cannot count", () => {
    const now = Date.now();
    expect(rollingAllowance({ now, limit: 5, successes: [now - WINDOW_MS, now - WINDOW_MS + 1, now, now + 1], reservations: [now, now + 1] }))
      .toMatchObject({ used: 2, reserved: 1, remaining: 2, retryAt: null });
  });
  test("window boundary executes the indexed query", async () => {
    const f = await fixture(); const now = Date.now();
    await seedCharges(f, [now - WINDOW_MS + 1, now, now, now, now]);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ remaining: 0, retryAt: now + 1 });
    vi.setSystemTime(now + 1);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ remaining: 1 });
  });
  test("upgrade/downgrade preserve history; retry waits for enough events", async () => {
    const f = await fixture(); const now = Date.now();
    await seedCharges(f, Array.from({ length: 10 }, (_, i) => now - 10_000 + i * 100));
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 5, remaining: 0, retryAt: now - 9_500 + WINDOW_MS });
    await f.t.mutation(internal.users.syncRevenueCatEntitlement, { clerkId: "q1-owner", revenueCatAppUserId: "q1-owner", eventTimestampMs: now, subscriptionTier: "pro", entitlementExpiresAt: now + 100 });
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 100, used: 10, remaining: 90 });
    vi.setSystemTime(now + 100);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 5, used: 10, remaining: 0 });
  });
  test("admitted work remains valid across entitlement downgrade", async () => {
    const f = await fixture(); await f.t.run(async ctx => ctx.db.patch(f.userId, { subscriptionTier: "pro" }));
    await seedCharges(f, Array(5).fill(Date.now()));
    const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    await f.t.run(async ctx => ctx.db.patch(f.userId, { subscriptionTier: "free" }));
    expect(await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output })).not.toBeNull();
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ used: 6, remaining: 0 });
  });
  test("remaining allowance includes live reservations", async () => {
    const f = await fixture(); await seedCharges(f, Array(4).fill(Date.now()));
    const claims = await Promise.all(Array.from({ length: 8 }, (_, i) => f.admit(i)));
    expect(claims.filter(x => x.kind === "claimed")).toHaveLength(1);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ used: 4, reserved: 1, remaining: 0, retryAt: Date.now() + LEASE_MS });
  });
});

describe("Q1 global success invariant", () => {
  test("parallel user/service requests acquire one global flight", async () => {
    const f = await fixture();
    const claims = await Promise.all([f.admit(), f.admit(), f.t.mutation(internal.quotas.admit, { hadithId: f.hadithIds[0], language: "ru", signal: "service" })]);
    expect(claims.filter(x => x.kind === "claimed")).toHaveLength(1);
    const claim = claims.find(x => x.kind === "claimed"); if (!claim || claim.kind !== "claimed") throw new Error("No claim");
    await Promise.all(Array.from({ length: 8 }, () => f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output })));
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
    expect(await f.t.run(ctx => ctx.db.query("aiCostEvents").collect())).toHaveLength(1);
    expect(await f.admit()).toMatchObject({ kind: "cached" });
  });
  test("service success has one global event and zero user charges", async () => {
    const f = await fixture(); const claim = await f.t.mutation(internal.quotas.admit, { hadithId: f.hadithIds[0], language: "ru", signal: "service" });
    if (claim.kind !== "claimed") throw new Error("No claim");
    await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
    expect(await f.t.run(ctx => ctx.db.query("aiUsageCharges").collect())).toHaveLength(0);
  });
  test.each(["official", "gemini_ai"] as const)("%s cache and full-quota reads insert zero usage events", async source => {
    const f = await fixture(); await seedCharges(f, Array(5).fill(Date.now()));
    await f.t.run(ctx => ctx.db.insert("translations", { hadithId: f.hadithIds[0], language: "ru", content: "cached", source, sourceLabel: source, isDefault: true, status: "live", groundingUsed: false, createdAt: Date.now(), updatedAt: Date.now() }));
    expect(await f.admit()).toMatchObject({ kind: "cached" });
    expect(await f.owner.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" })).toMatchObject({ translation: "cached", cached: true });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(5);
    expect(provider).not.toHaveBeenCalled();
  });
  test("a newly approved/default winner between admission and completion remains free", async () => {
    const f = await fixture(); const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    await f.t.run(ctx => ctx.db.insert("translations", { hadithId: f.hadithIds[0], language: "ru", content: "official", source: "official", sourceLabel: "Official", isDefault: true, status: "live", groundingUsed: false, createdAt: Date.now(), updatedAt: Date.now() }));
    expect(await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output })).toMatchObject({ cached: true, translation: { content: "official" } });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(0);
  });
  test("failure releases reservations; retry produces exactly one success", async () => {
    const f = await fixture(); const first = await f.admit(); if (first.kind !== "claimed") throw new Error("No claim");
    await f.t.mutation(internal.quotas.finish, { jobId: first.jobId, attempt: first.attempt, telemetry });
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ remaining: 5, used: 0, reserved: 0 });
    const next = await f.admit(); if (next.kind !== "claimed") throw new Error("No retry");
    expect(next).toMatchObject({ jobId: first.jobId, attempt: first.attempt + 1 });
    await f.t.mutation(internal.quotas.finish, { jobId: next.jobId, attempt: next.attempt, telemetry, output });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
    expect(await f.t.run(ctx => ctx.db.query("aiCostEvents").collect())).toHaveLength(2);
  });
  test("expired worker cannot publish after takeover", async () => {
    const f = await fixture(); const first = await f.admit(); if (first.kind !== "claimed") throw new Error("No claim");
    vi.setSystemTime(Date.now() + LEASE_MS);
    const next = await f.admit(); if (next.kind !== "claimed") throw new Error("No takeover");
    expect(await f.t.mutation(internal.quotas.finish, { jobId: first.jobId, attempt: first.attempt, telemetry, output })).toBeNull();
    await f.t.mutation(internal.quotas.finish, { jobId: next.jobId, attempt: next.attempt, telemetry, output });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
  });
  test("changed source cannot publish stale output", async () => {
    const f = await fixture(); const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    await f.t.run(ctx => ctx.db.patch(f.hadithIds[0], { arabicText: "changed source" }));
    expect(await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output })).toBeNull();
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(0);
  });
  test("deletion keeps global flight/cache/event; erases private charges/credentials", async () => {
    const f = await fixture(); const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    await f.owner.mutation(api.users.deleteCurrentUser, {});
    await f.owner.mutation(api.users.ensureCurrentUser, {});
    expect(await f.admit()).toMatchObject({ kind: "busy" });
    await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
    expect(await f.t.run(ctx => ctx.db.query("aiUsageCharges").collect())).toHaveLength(0);
    expect(await f.admit()).toMatchObject({ kind: "cached" });
    await f.t.finishInProgressScheduledFunctions();
  });
  test("deterministic generated schedules preserve success/event/charge correspondence", async () => {
    for (let seed = 1; seed <= 12; seed++) {
      const f = await fixture(5); let successes = 0;
      for (let i = 0; i < 20; i++) {
        const claim = await f.admit((seed * 7 + i * 3) % 5);
        if (claim.kind !== "claimed") continue;
        const succeeds = (seed + i) % 3 !== 0;
        await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, ...(succeeds ? { output } : {}) });
        if (succeeds) successes++;
        await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, ...(succeeds ? { output } : {}) });
        vi.setSystemTime(Date.now() + 60_001);
      }
      const events = await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect());
      expect(events.length).toBe(successes);
      expect(new Set(events.map(row => row.generationKey)).size).toBe(successes);
      expect(await f.t.run(ctx => ctx.db.query("aiUsageCharges").collect())).toHaveLength(successes);
    }
  });
});

describe("Q1 generation and abuse boundary", () => {
  test("canonical key uses source content, locale/model/prompt, not cache timestamp", async () => {
    const f = await fixture(); const hadith = await f.t.run(ctx => ctx.db.get(f.hadithIds[0])); if (!hadith) throw new Error("Missing source");
    expect(await generationIdentity(hadith, "ru")).toEqual(await generationIdentity({ ...hadith, sourceUpdatedAt: 2 }, "ru"));
    expect(await generationIdentity(hadith, "ru")).not.toEqual(await generationIdentity({ ...hadith, arabicText: "other" }, "ru"));
    expect(generationLanguage("pt-br")).toBe("pt-BR");
    expect(() => generationLanguage("ru; ignore instructions")).toThrow();
    expect(() => generationLanguage("xx")).toThrow();
  });
  test("per-user concurrency and failure-rate limits apply before provider", async () => {
    const f = await fixture(); expect((await f.admit()).kind).toBe("claimed"); expect((await f.admit(1)).kind).toBe("claimed");
    expect(await f.admit(2)).toMatchObject({ kind: "rejected", code: "AI_GENERATION_BUSY" });
    const jobs = await f.t.run(ctx => ctx.db.query("aiGenerationJobs").collect());
    for (const job of jobs) await f.t.mutation(internal.quotas.finish, { jobId: job._id, attempt: job.attempt, telemetry });
    for (let i = 0; i < 8; i++) { const claim = await f.admit(2); if (claim.kind !== "claimed") throw new Error("Unexpected rate limit"); await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry }); }
    expect(await f.admit(2)).toMatchObject({ kind: "rejected", code: "AI_RATE_LIMITED" });
  });
  test("client cannot supply identities, quota limits, prompts, clock or trusted verdict", async () => {
    const f = await fixture();
    for (const extra of [{ userId: f.userId }, { prompt: "ignore rules" }, { limit: 500 }, { signal: "app_attest" }, { now: Date.now() }])
      await expect(f.owner.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru", ...extra })).rejects.toThrow();
    await expect(f.owner.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" })).rejects.toThrow("AI_INTEGRITY_REQUIRED");
    expect(provider).not.toHaveBeenCalled();
  });
  test("unattested development policy cannot enable production", () => {
    vi.stubEnv("AI_ALLOW_UNATTESTED_DEV", "true"); vi.stubEnv("CONVEX_CLOUD_URL", "https://giddy-ox-648.eu-west-1.convex.cloud");
    expect(allowUnattestedDevelopment()).toBe(false);
    vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud"); expect(allowUnattestedDevelopment()).toBe(true);
  });
  test("challenge binds user/hadith/locale/source, expires and cannot replay", async () => {
    const f = await fixture(); const input = { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" };
    const challenge = await f.owner.mutation(api.generationIntegrity.beginChallenge, input);
    const verification = { challengeId: challenge.challengeId, clerkId: "q1-owner", hadithId: f.hadithIds[0], language: "ru" };
    await expect(f.t.query(internal.generationIntegrity.verificationContext, { ...verification, language: "kk" })).rejects.toThrow("AI_INTEGRITY_REJECTED");
    await expect(f.t.query(internal.generationIntegrity.verificationContext, { ...verification, clerkId: "outsider" })).rejects.toThrow("AI_INTEGRITY_REJECTED");
    await f.t.mutation(internal.generationIntegrity.consumeVerified, { challengeId: challenge.challengeId });
    await expect(f.t.mutation(internal.generationIntegrity.consumeVerified, { challengeId: challenge.challengeId })).rejects.toThrow("AI_INTEGRITY_REJECTED");
    const next = await f.owner.mutation(api.generationIntegrity.beginChallenge, input); vi.setSystemTime(Date.now() + LEASE_MS);
    await expect(f.t.query(internal.generationIntegrity.verificationContext, { ...verification, challengeId: next.challengeId })).rejects.toThrow("AI_INTEGRITY_REJECTED");
  });
  test("App Attest monotonic counters commit atomically", async () => {
    const f = await fixture(); const input = { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" };
    const c = await f.owner.mutation(api.generationIntegrity.beginChallenge, input);
    await f.t.mutation(internal.generationIntegrity.consumeVerified, { challengeId: c.challengeId, credential: { keyId: "fixture-key", publicKey: "fixture-public-key", signCount: 0 } });
    const challenges = await Promise.all([f.owner.mutation(api.generationIntegrity.beginChallenge, input), f.owner.mutation(api.generationIntegrity.beginChallenge, input)]);
    const results = await Promise.allSettled(challenges.map(c => f.t.mutation(internal.generationIntegrity.consumeVerified, { challengeId: c.challengeId, credential: { keyId: "fixture-key", publicKey: "fixture-public-key", signCount: 1, previousCount: 0 } })));
    expect(results.filter(x => x.status === "fulfilled")).toHaveLength(1);
  });
  test("Play Integrity rejects wrong hash/package/certificate/verdict/time", () => {
    const now = Date.now(), expected = { packageName: "com.hadithly.app", requestHash: "hash", certificateDigests: ["cert"], now };
    const payload = { requestDetails: { requestPackageName: expected.packageName, requestHash: "hash", timestampMillis: String(now) }, appIntegrity: { appRecognitionVerdict: "PLAY_RECOGNIZED", packageName: expected.packageName, certificateSha256Digest: ["cert"] }, deviceIntegrity: { deviceRecognitionVerdict: ["MEETS_DEVICE_INTEGRITY"] }, accountDetails: { appLicensingVerdict: "LICENSED" } };
    expect(validPlayIntegrity({ tokenPayloadExternal: payload }, expected)).toBe(true);
    for (const changed of [{ requestDetails: { ...payload.requestDetails, requestHash: "tampered" } }, { requestDetails: { ...payload.requestDetails, timestampMillis: String(now - LEASE_MS) } }, { appIntegrity: { ...payload.appIntegrity, packageName: "other" } }, { appIntegrity: { ...payload.appIntegrity, certificateSha256Digest: ["other"] } }, { deviceIntegrity: { deviceRecognitionVerdict: [] } }, { accountDetails: { appLicensingVerdict: "UNLICENSED" } }])
      expect(validPlayIntegrity({ tokenPayloadExternal: { ...payload, ...changed } }, expected)).toBe(false);
  });
  test("one bounded ungrounded provider call; numeric telemetry contains no text", async () => {
    const f = await fixture(); vi.stubEnv("GEMINI_API_KEY", "fixture-not-real"); vi.stubEnv("AI_ALLOW_UNATTESTED_DEV", "true"); vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
    provider.mockResolvedValue({ text: JSON.stringify({ ...output, glossaryNotes: [] }), usageMetadata: { promptTokenCount: 2000, candidatesTokenCount: 500, thoughtsTokenCount: 0 } });
    const challenge = await f.owner.mutation(api.generationIntegrity.beginChallenge, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" });
    expect(await f.owner.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru", challengeId: challenge.challengeId, proof: { kind: "unavailable" } })).toMatchObject({ cached: false, groundingUsed: false });
    expect(provider).toHaveBeenCalledTimes(1);
    const config = provider.mock.calls[0][0].config;
    expect(config.tools).toBeUndefined(); expect(config.httpOptions.retryOptions.attempts).toBe(1);
    const cost = await f.t.run(ctx => ctx.db.query("aiCostEvents").unique());
    expect(cost).toMatchObject({ estimatedMicroUsd: 400, outcome: "published", groundingUsed: false });
    for (const text of [output.translation, "Public source", "نص عربي", "q1-owner", "prompt", "proof"]) expect(JSON.stringify(cost)).not.toContain(text);
    expect(tokenCostMicroUsd({ inputTokens: 2000, outputTokens: 400, thinkingTokens: 100 })).toBe(400);
  });
  test("malformed output fails without repair call or quota event", async () => {
    const f = await fixture(); vi.stubEnv("GEMINI_API_KEY", "fixture-not-real"); provider.mockResolvedValue({ text: "not JSON", usageMetadata: { promptTokenCount: 100 } });
    await expect(f.t.action(internal.actions.ai.generateServiceTranslation, { hadithId: f.hadithIds[0], language: "ru" })).rejects.toThrow("AI_GENERATION_RETRY");
    expect(provider).toHaveBeenCalledTimes(1); expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(0);
    expect(await f.t.run(ctx => ctx.db.query("aiCostEvents").unique())).toMatchObject({ outcome: "failed", inputTokens: 100 });
  });
});

describe("Q1 permission and proof races", () => {
  test("source permission revoked during generation prevents publication and charge", async () => {
    const f = await fixture(); const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    await f.t.run(async ctx => { const hadith = await ctx.db.get(f.hadithIds[0]); if (!hadith?.licenseRecordId) throw new Error("No license"); await ctx.db.patch(hadith.licenseRecordId, { terms: { kind: "unverified" } }); });
    expect(await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output })).toBeNull();
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(0);
    expect(await f.t.run(ctx => ctx.db.query("aiUsageCharges").collect())).toHaveLength(0);
  });
  test("source changes invalidate page, notification and already-loaded AI", async () => {
    const f = await fixture(); const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    const finished = await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry, output }); if (!finished) throw new Error("No output");
    await f.t.run(ctx => ctx.db.patch(f.hadithIds[0], { arabicText: "جديد" }));
    expect(await f.t.query(internal.translations.listLiveDefaultsForHadithLanguage, { hadithId: f.hadithIds[0], language: "ru" })).toHaveLength(0);
    expect(await f.t.query(api.translations.getReaderDefaults, { hadithInternalIds: ["sunnah_now:bukhari:1"], language: "ru" })).toMatchObject([{ translation: null }]);
    expect(await f.t.query(api.translations.watchPublications, { translationIds: [finished.translation._id] })).toMatchObject([{ available: false }]);
  });
  test("authoritative claim rejects proof verified for an older source", async () => {
    const f = await fixture(); const hadith = await f.t.run(ctx => ctx.db.get(f.hadithIds[0])); if (!hadith) throw new Error("No source");
    const { generationKey } = await generationIdentity(hadith, "ru");
    await f.t.run(ctx => ctx.db.patch(f.hadithIds[0], { arabicText: "جديد" }));
    expect(await f.t.mutation(internal.quotas.admit, { hadithId: f.hadithIds[0], language: "ru", clerkId: "q1-owner", signal: "app_attest", verifiedGenerationKey: generationKey })).toMatchObject({ kind: "rejected", code: "AI_INTEGRITY_REJECTED" });
  });
  test("monthly global ceiling includes failed attempts and resets only at UTC boundary", async () => {
    const f = await fixture(); vi.stubEnv("AI_MONTHLY_ATTEMPT_LIMIT", "1");
    const claim = await f.admit(); if (claim.kind !== "claimed") throw new Error("No claim");
    await f.t.mutation(internal.quotas.finish, { jobId: claim.jobId, attempt: claim.attempt, telemetry });
    expect(await f.admit(1)).toMatchObject({ kind: "rejected", code: "AI_SERVICE_LIMIT" });
    const date = new Date(Date.now()); vi.setSystemTime(Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 1));
    expect((await f.admit(1)).kind).toBe("claimed");
  });
});


test("actual E3-approved community publication is free and wins before AI", async () => {
  const { t, owner, hadithId, draft } = await evidenceFixture();
  const claim = await t.mutation(internal.evidenceReview.claim, { submissionId: draft.submissionId, reviewEnabled: true });
  if (!claim) throw new Error("No evidence review claim");
  expect(await t.mutation(internal.evidenceReview.finish, { submissionId: draft.submissionId, token: claim.token, passes: passes(claim.packet) })).toBe(true);
  await t.run(ctx => ctx.db.insert("translations", { hadithId, language: "en", content: "obsolete AI", source: "gemini_ai", sourceLabel: "AI", status: "live", isDefault: true, groundingUsed: false, createdAt: Date.now(), updatedAt: Date.now() }));
  const cached = await owner.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "en" });
  expect(cached).toMatchObject({ source: "community", cached: true });
  expect(await t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(0);
  expect(await t.run(ctx => ctx.db.query("aiUsageCharges").collect())).toHaveLength(0);
  expect(provider).not.toHaveBeenCalled();
});

test("public action races call the provider once and retries reuse the result", async () => {
  const f = await fixture(); vi.stubEnv("GEMINI_API_KEY", "fixture-not-real"); vi.stubEnv("AI_ALLOW_UNATTESTED_DEV", "true"); vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  let release: () => void = () => {}; let started: () => void = () => {};
  const gate = new Promise<void>(resolve => { release = resolve; });
  const began = new Promise<void>(resolve => { started = resolve; });
  provider.mockImplementation(async () => { started(); await gate; return { text: JSON.stringify({ ...output, glossaryNotes: [] }), usageMetadata: { promptTokenCount: 100, candidatesTokenCount: 100 } }; });
  const input = { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" };
  const firstChallenge = await f.owner.mutation(api.generationIntegrity.beginChallenge, input);
  const secondChallenge = await f.owner.mutation(api.generationIntegrity.beginChallenge, input);
  const first = f.owner.action(api.actions.ai.translateHadith, { ...input, challengeId: firstChallenge.challengeId, proof: { kind: "unavailable" } });
  await began;
  try {
    await expect(f.owner.action(api.actions.ai.translateHadith, { ...input, challengeId: secondChallenge.challengeId, proof: { kind: "unavailable" } })).rejects.toThrow("AI_GENERATION_BUSY");
  } finally { release(); }
  await first;
  expect(await f.owner.action(api.actions.ai.translateHadith, input)).toMatchObject({ cached: true });
  expect(provider).toHaveBeenCalledTimes(1);
  expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
});

test("cost reservation settles known tokens but keeps unknown failure spend", async () => {
  const f = await fixture(); vi.stubEnv("AI_MONTHLY_BUDGET_USD", "0.04");
  const known = await f.admit(); if (known.kind !== "claimed") throw new Error("No claim");
  await f.t.mutation(internal.quotas.finish, { jobId: known.jobId, attempt: known.attempt, telemetry });
  expect(await f.t.run(ctx => ctx.db.query("aiSpendBudgets").unique())).toMatchObject({ committedMicroUsd: 400 });
  const unknown = await f.admit(1); if (unknown.kind !== "claimed") throw new Error("No claim");
  await f.t.mutation(internal.quotas.finish, { jobId: unknown.jobId, attempt: unknown.attempt,
    telemetry: { inputTokens: 0, outputTokens: 0, thinkingTokens: 0, durationMs: 100, tokenUsageKnown: false } });
  expect(await f.t.run(ctx => ctx.db.query("aiSpendBudgets").unique())).toMatchObject({ committedMicroUsd: 20_400 });
  expect(await f.admit(2)).toMatchObject({ kind: "rejected", code: "AI_SERVICE_LIMIT" });
  expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ used: 0, remaining: 5 });
});

test("development App Attest environment stays separate from unavailable-proof admission", async () => {
  const { isNamedDevelopmentDeployment } = await import("./generationIntegrity");
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.convex.cloud");
  vi.stubEnv("AI_ALLOW_UNATTESTED_DEV", "false");
  expect(isNamedDevelopmentDeployment()).toBe(true);
  expect(allowUnattestedDevelopment()).toBe(false);
  vi.stubEnv("AI_ALLOW_UNATTESTED_DEV", "true");
  expect(allowUnattestedDevelopment()).toBe(true);
  vi.stubEnv("CONVEX_CLOUD_URL", "https://giddy-ox-648.eu-west-1.convex.cloud");
  expect(isNamedDevelopmentDeployment()).toBe(false);
  expect(allowUnattestedDevelopment()).toBe(false);
});
