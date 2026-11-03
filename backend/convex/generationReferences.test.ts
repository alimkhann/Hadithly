/// <reference types="vite/client" />
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import { fixture, passes, reviewClaim, text } from "../test/evidenceFixtures";
import { currentGenerationReferences, referencesForGeneration, generationReferenceBlock } from "./lib/generationReferences";
import { publicTranslationAvailable, PublicationReadBudget } from "./lib/evidencePublication";
import { textDigest } from "./lib/evidenceReviewPolicy";
import { generationIdentity } from "./lib/generationPolicy";

const provider = vi.hoisted(() => vi.fn());
vi.mock("@google/genai", async importOriginal => {
  const actual = await importOriginal<typeof import("@google/genai")>();
  return { ...actual, GoogleGenAI: class { models = { generateContent: provider }; } };
});
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(1_800_000_000_000); provider.mockReset();
  vi.stubEnv("GEMINI_API_KEY", "fixture-not-real"); vi.stubEnv("AI_ALLOW_UNATTESTED_DEV", "true");
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); });

function response(usedReferenceIds = ["reference:0"]) {
  return { text: JSON.stringify({ translation: "Подготовленный тестовый перевод.", confidence: 0.9, riskFlags: [], glossaryNotes: [], usedReferenceIds }),
    usageMetadata: { promptTokenCount: 3000, candidatesTokenCount: 500, thoughtsTokenCount: 0 } };
}

async function published(expiry?: number) {
  const f = await fixture();
  const grantId = f.grantId;
  if (expiry && grantId) await f.t.run(ctx => ctx.db.patch(grantId, { grant: { ...f.grant, expiresAt: expiry } }));
  const claim = await reviewClaim(f);
  expect(await f.t.mutation(internal.evidenceReview.finish, { submissionId: f.draft.submissionId, token: claim.token, passes: passes(claim.packet) })).toBe(true);
  const translation = await f.t.run(ctx => ctx.db.query("translations").withIndex("by_hadith_language_default", q =>
    q.eq("hadithId", f.hadithId).eq("language", "en").eq("isDefault", true)).unique());
  if (!translation?.evidencePublicationId) throw new Error("Missing published comparison");
  await f.t.run(async ctx => {
    const licenseId = await ctx.db.insert("licenseRecords", { sourceKey: "generation-reference-fixture", sourceName: "Fixture source", sourceUrl: "https://example.org/original",
      terms: { kind: "verified", licenseName: "Fixture permission", licenseUrl: "https://example.org/permission", permitsDisplay: true, permitsRedistribution: false, permitsOfflineDistribution: false, verifiedAt: 1 }, createdAt: 1, updatedAt: 1 });
    await ctx.db.patch(f.hadithId, { licenseRecordId: licenseId });
  });
  const hadith = await f.t.run(ctx => ctx.db.get(f.hadithId));
  if (!hadith) throw new Error("Missing hadith");
  return { ...f, translation, hadith };
}

async function generate(f: Awaited<ReturnType<typeof published>>) {
  const args = { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" };
  const challenge = await f.owner.mutation(api.generationIntegrity.beginChallenge, args);
  return f.owner.action(api.actions.ai.translateHadith, { ...args, challengeId: challenge.challengeId, proof: { kind: "unavailable" } });
}

test.each(["free", "pro"])("%s receives a real authorized comparison in one provider call and shares the cited cache", async tier => {
  const f = await published();
  if (tier === "pro") {
    const ticket = await f.t.mutation(internal.subscriptions.beginRefresh, { clerkId: "e3_owner", deny: false, ownershipConflict: false });
    if (!ticket) throw new Error("Missing subscription fixture");
    await f.t.mutation(internal.subscriptions.applySnapshot, { ...ticket, observedAt: Date.now(), ownershipConflict: false,
      purchases: [{ productId: "com.hadithly.app.pro.monthly", store: "app_store", paidUntil: Date.now() + 1_000_000, until: Date.now() + 1_000_000, phase: "paid" }] });
  }
  expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: tier === "pro" ? 100 : 5 });
  provider.mockResolvedValue(response());
  const result = await generate(f);
  expect(result).toMatchObject({ groundingUsed: true, cached: false, citations: [{ url: f.grant.citation.url }] });
  expect(result.citations[0]?.title).toContain(f.grant.attribution);
  expect(result.citations[0]?.title).toContain(f.grant.licenseName);
  expect(result.sourceReferenceUrl).toBeUndefined();
  expect(provider).toHaveBeenCalledTimes(1);
  const request = provider.mock.calls[0][0];
  expect(request.contents).toContain("UNTRUSTED_COMPARISON_DATA");
  expect(request.contents).toContain(text); expect(request.contents).toContain('"id":"reference:0"');
  expect(request.config.tools).toBeUndefined(); expect(request.config.httpOptions.retryOptions.attempts).toBe(1);
  expect(await f.outsider.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" })).toMatchObject({ translationId: result.translationId, cached: true, groundingUsed: true });
  expect(provider).toHaveBeenCalledTimes(1);
  expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toHaveLength(1);
  expect(await f.t.run(ctx => ctx.db.query("aiUsageCharges").collect())).toHaveLength(1);
  const cost = await f.t.run(ctx => ctx.db.query("aiCostEvents").unique());
  expect(cost).toMatchObject({ groundingUsed: true, inputTokens: 3000 });
  expect(JSON.stringify(cost)).not.toContain(text); expect(JSON.stringify(cost)).not.toContain(f.grant.citation.url);
});

test("unused supplied comparisons do not become citations or a grounding claim", async () => {
  const f = await published(); provider.mockResolvedValue(response([]));
  const generated = await generate(f);
  expect(generated).toMatchObject({ groundingUsed: false, citations: [] });
  expect(provider.mock.calls[0][0].contents).toContain(text);
  expect(await f.outsider.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" })).toMatchObject({ translationId: generated.translationId, cached: true, citations: [] });
  expect(provider).toHaveBeenCalledTimes(1);
});

test("invented and duplicate reference IDs fail without success or allowance consumption", async () => {
  for (const ids of [["https://invented.example/source"], ["reference:0", "reference:0"]]) {
    const f = await published(); provider.mockResolvedValue(response(ids));
    await expect(generate(f)).rejects.toThrow("AI_GENERATION_RETRY");
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ used: 0, reserved: 0, remaining: 5 });
    expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toEqual([]);
    expect(await f.t.run(ctx => ctx.db.query("aiCostEvents").collect())).toMatchObject([{ outcome: "failed", failureReason: "completion_rejected" }]);
  }
});

test("revocation during the provider call prevents publication and releases allowance", async () => {
  const f = await published();
  if (!f.grantId) throw new Error("Missing grant");
  const grantId = f.grantId;
  provider.mockImplementation(async () => {
    await f.t.run(ctx => ctx.db.patch(grantId, { grant: { ...f.grant, revokedAt: Date.now() } }));
    return response();
  });
  await expect(generate(f)).rejects.toThrow("AI_GENERATION_RETRY");
  expect(provider).toHaveBeenCalledTimes(1);
  expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ used: 0, reserved: 0, remaining: 5 });
  expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toEqual([]);
  expect(await f.t.run(ctx => ctx.db.query("aiCostEvents").unique())).toMatchObject({ outcome: "failed", inputTokens: 3000 });
});

test("permission expiry invalidates already-loaded AI and exposes its exact retry deadline", async () => {
  const expiry = Date.now() + 10_000, f = await published(expiry); provider.mockResolvedValue(response());
  const result = await generate(f);
  const ids = { translationIds: [result.translationId] };
  // Use the public cache's typed ID rather than the action's platform-neutral string.
  const row = await f.t.query(internal.translations.getDefaultForHadithLanguage, { hadithId: f.hadithId, language: "ru" });
  if (!row) throw new Error("Missing generated row");
  expect(await f.t.query(api.translations.watchPublications, { translationIds: [row._id] })).toEqual([{ translationId: ids.translationIds[0], available: true, validUntil: expiry }]);
  expect(await f.t.run(ctx => publicTranslationAvailable(ctx, row, new Set(), new PublicationReadBudget(2)))).toBe(false);
  vi.setSystemTime(expiry);
  expect(await f.t.query(api.translations.watchPublications, { translationIds: [row._id] })).toEqual([{ translationId: row._id, available: false, validUntil: expiry }]);
  expect(await f.t.query(api.translations.getReaderDefaults, { hadithInternalIds: ["sunnah_now:bukhari:1"], language: "ru" })).toMatchObject([{ translation: null }]);
});

test("changed text or publication language cannot masquerade as the captured reference", async () => {
  const f = await published();
  const references = await f.t.run(ctx => referencesForGeneration(ctx, f.hadith, "ru"));
  expect(references).toHaveLength(1);
  const bindings = references.map(reference => reference.binding);
  await f.t.run(ctx => ctx.db.patch(f.translation._id, { language: "uk" }));
  expect(await f.t.run(ctx => referencesForGeneration(ctx, f.hadith, "ru"))).toEqual([]);
  expect(await f.t.run(ctx => currentGenerationReferences(ctx, f.hadith, bindings))).toBeNull();
  await f.t.run(ctx => ctx.db.patch(f.draft.submissionId, { language: "uk" }));
  expect(await f.t.run(ctx => currentGenerationReferences(ctx, f.hadith, bindings))).toBeNull();
  await f.t.run(async ctx => {
    await ctx.db.patch(f.draft.submissionId, { language: "en" });
    await ctx.db.patch(f.translation._id, { language: "en", content: "Changed source" });
  });
  expect(await f.t.run(ctx => currentGenerationReferences(ctx, f.hadith, bindings))).toBeNull();
});

test.each(["https://127.0.0.1/reference", "https://example.org/api/storage/private", "https://example.org/reference?token=fixture"])("private or capability-bearing citation is never used: %s", async url => {
  const f = await published(), publicationId = f.translation.evidencePublicationId;
  if (!publicationId) throw new Error("Missing publication");
  await f.t.run(ctx => ctx.db.patch(publicationId, { citations: [{ ...f.grant.citation, url }] }));
  expect(await f.t.run(ctx => referencesForGeneration(ctx, f.hadith, "ru"))).toEqual([]);
});

test("comparison/model-processing permission is required before text enters the prompt", async () => {
  const f = await published();
  if (!f.grantId) throw new Error("Missing grant");
  const grantId = f.grantId;
  await f.t.run(ctx => ctx.db.patch(grantId, { grant: { ...f.grant, modelProcessing: false } }));
  provider.mockResolvedValue(response([]));
  expect(await generate(f)).toMatchObject({ groundingUsed: false, citations: [] });
  expect(provider.mock.calls[0][0].contents).not.toContain(text);
});

test("a citation changed during generation cannot be attached to text produced from the earlier reference", async () => {
  const f = await published();
  const publicationId = f.translation.evidencePublicationId;
  if (!publicationId) throw new Error("Missing publication");
  provider.mockImplementation(async () => {
    await f.t.run(ctx => ctx.db.patch(publicationId, { citations: [{ ...f.grant.citation, url: "https://example.org/changed-reference" }] }));
    return response();
  });
  await expect(generate(f)).rejects.toThrow("AI_GENERATION_RETRY");
  expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ used: 0, reserved: 0 });
  expect(await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect())).toEqual([]);
});

test("a replacement reference gets a new generation key while retaining global cache reuse", async () => {
  const f = await published(); provider.mockResolvedValue(response());
  const original = await generate(f);
  const publicationId = f.translation.evidencePublicationId;
  if (!publicationId) throw new Error("Missing publication");
  await f.t.run(async ctx => {
    const previous = await ctx.db.get(publicationId);
    if (!previous) throw new Error("Missing prior publication");
    const { _id: _publicationId, _creationTime: _created, ...fields } = previous;
    const translationId = await ctx.db.insert("translations", { hadithId: f.hadithId, language: "en", content: "Updated authorized comparison.",
      source: "community", sourceLabel: "Replacement fixture", status: "live", isDefault: true, groundingUsed: false, createdAt: Date.now(), updatedAt: Date.now() });
    const revisionId = await ctx.db.insert("evidencePublicationRevisions", { ...fields, translationId, outputSha256: await textDigest("Updated authorized comparison.") });
    await ctx.db.patch(translationId, { evidencePublicationId: revisionId });
    await ctx.db.patch(f.translation._id, { isDefault: false });
  });
  const replacement = await generate(f);
  expect(replacement.translationId).not.toBe(original.translationId);
  expect(provider).toHaveBeenCalledTimes(2);
  expect(provider.mock.calls[1][0].contents).toContain("Updated authorized comparison.");
  const events = await f.t.run(ctx => ctx.db.query("aiUsageEvents").collect());
  expect(events).toHaveLength(2); expect(new Set(events.map(row => row.generationKey)).size).toBe(2);
  expect(await f.outsider.action(api.actions.ai.translateHadith, { hadithInternalId: "sunnah_now:bukhari:1", targetLanguage: "ru" })).toMatchObject({ translationId: replacement.translationId, cached: true });
  expect(provider).toHaveBeenCalledTimes(2);
});

test("legacy ungrounded cache remains reusable when comparisons later become available", async () => {
  const f = await published();
  const identity = await generationIdentity(f.hadith, "ru");
  const translationId = await f.t.run(ctx => ctx.db.insert("translations", { ...identity, hadithId: f.hadithId, language: "ru", content: "Existing cached translation",
    source: "gemini_ai", sourceLabel: "AI", status: "live", isDefault: true, groundingUsed: false, citations: [], createdAt: 1, updatedAt: 1 }));
  expect(await generate(f)).toMatchObject({ translationId, cached: true, groundingUsed: false });
  expect(provider).not.toHaveBeenCalled();
});

test("first reading retains comparison attribution and expiry for a newly grounded AI key", async () => {
  const expiry = Date.now() + 10_000, f = await published(expiry); provider.mockResolvedValue(response());
  await f.t.run(ctx => ctx.db.patch(f.hadithId, { volumeId: "1", authenticity: { kind: "collection_scope", normalizedGrade: "sahih", claimScope: "collection",
    sourceLabel: "Documented collection", sourceName: "Fixture source", sourceUrl: "https://example.org/original", verificationMethod: "manual_collection_mapping" } }));
  await generate(f);
  const row = await f.t.query(internal.translations.getDefaultForHadithLanguage, { hadithId: f.hadithId, language: "ru" });
  if (!row) throw new Error("Missing generated comparison row");
  await f.t.mutation(internal.firstReading.prepareSlot, { locale: "ru", rank: 0, hadithId: f.hadithId, source: { kind: "ai_translation", translationId: row._id } });
  const reading = await f.t.query(api.firstReading.get, { translationLocale: "ru", timezone: "Asia/Almaty" });
  expect(reading).toMatchObject({ kind: "ready", validUntil: expiry, reading: { text: { language: "ru", isAI: true } } });
  if (reading.kind !== "ready") throw new Error("Missing first reading");
  expect(reading.reading.text.credits).toContainEqual({ scope: "translation", attribution: f.grant.attribution, licenseName: f.grant.licenseName, url: f.grant.permissionUrl });
  vi.setSystemTime(expiry);
  expect(await f.t.query(api.firstReading.get, { translationLocale: "ru", timezone: "Asia/Almaty" })).toMatchObject({ kind: "unavailable" });
});

test("serialized comparison metadata cannot exceed the prompt bound", async () => {
  const f = await published(), publicationId = f.translation.evidencePublicationId;
  if (!publicationId) throw new Error("Missing publication");
  const current = await f.t.run(ctx => referencesForGeneration(ctx, f.hadith, "ru"));
  expect(new TextEncoder().encode(generationReferenceBlock(current)).byteLength).toBeLessThanOrEqual(24_000);
  await f.t.run(ctx => ctx.db.patch(publicationId, { citations: [{ ...f.grant.citation, title: "x".repeat(24_000) }] }));
  expect(await f.t.run(ctx => referencesForGeneration(ctx, f.hadith, "ru"))).toEqual([]);
});

test("an older in-flight action can finish without publishing its guessed reference URL", async () => {
  const f = await published();
  const admission = await f.t.mutation(internal.quotas.admit, { hadithId: f.hadithId, language: "ru", signal: "service" });
  if (admission.kind !== "claimed") throw new Error("Missing generation claim");
  const completed = await f.t.mutation(internal.quotas.finish, { jobId: admission.jobId, attempt: admission.attempt,
    telemetry: { inputTokens: 100, outputTokens: 50, thinkingTokens: 0, tokenUsageKnown: true, durationMs: 100 },
    output: { translation: "Legacy action result", confidence: 0.9, riskFlags: [], sourceReferenceUrl: "https://sunnah.com/bukhari:1" } });
  expect(completed?.translation.sourceReferenceUrl).toBeUndefined();
  expect(completed?.translation.content).toBe("Legacy action result");
});
