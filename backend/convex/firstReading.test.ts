/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { afterEach, expect, test, vi } from "vitest";
import schema from "./schema";
import { api, internal } from "./_generated/api";
import { fixture, passes, reviewClaim } from "../test/evidenceFixtures";
import type { Id } from "./_generated/dataModel";
import type { FirstReadingResult, FirstReadingSource } from "./lib/firstReadingPolicy";
import { generationIdentity } from "./lib/generationPolicy";
import { localDateInTimezone } from "./lib/dailyEligibility";
import { textDigest, type PermissionGrant } from "./lib/evidenceReviewPolicy";
import { mkdirSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";

const modules = import.meta.glob("./**/*.ts");
const get = makeFunctionReference<"query", { translationLocale: string; timezone: string }, FirstReadingResult>("firstReading:get");
const prepare = makeFunctionReference<"mutation", { locale: string; rank: 0 | 1 | 2; hadithId: Id<"hadiths">; source: FirstReadingSource }, Id<"firstReadingSlots">>("firstReading:prepareSlot");
const timezone = "Asia/Almaty";
afterEach(() => { vi.restoreAllMocks(); vi.useRealTimers(); });

function exportFixture(name: string, value: FirstReadingResult) {
  const directory = process.env.HADITHLY_FIRST_READING_FIXTURE_DIR;
  if (!directory) return;
  mkdirSync(directory, { recursive: true });
  writeFileSync(resolve(directory, `${name}.json`), JSON.stringify(value, null, 2) + "\n");
}

async function setup() {
  const t = convexTest(schema, modules);
  const licenseId = await t.run(ctx => ctx.db.insert("licenseRecords", {
    sourceKey: "first-reading-fixture", sourceName: "Fixture source", sourceUrl: "https://example.org/reference",
    terms: { kind: "verified", licenseName: "Fixture display permission", licenseUrl: "https://example.org/permission",
      permitsDisplay: true, permitsRedistribution: false, permitsOfflineDistribution: false, verifiedAt: 1 },
    createdAt: 1, updatedAt: 1,
  }));
  async function hadith(number: string) {
    return t.run(ctx => ctx.db.insert("hadiths", {
      provider: "sunnah_now", canonicalId: `sunnah_now:bukhari:${number}`, collectionSlug: "bukhari", providerHadithId: number,
      volumeId: "1", collectionName: "Sahih al-Bukhari", arabicText: `نص ${number}`, englishText: `Existing English ${number}`,
      referenceDisplay: `Bukhari ${number}`, licenseRecordId: licenseId, createdAt: 1,
      authenticity: { kind: "collection_scope", normalizedGrade: "sahih", claimScope: "collection",
        sourceLabel: "Documented collection", sourceName: "Fixture source", sourceUrl: "https://example.org/reference", verificationMethod: "manual_collection_mapping" },
    }));
  }
  async function translated(hadithId: Id<"hadiths">, language: string) {
    return t.run(async ctx => {
      const item = await ctx.db.get(hadithId);
      if (!item) throw new Error("Missing hadith fixture");
      const identity = await generationIdentity(item, language);
      return ctx.db.insert("translations", { hadithId, language, content: `Exact ${language} translation`,
        source: "gemini_ai", sourceLabel: "Must not override AI label", generationKey: identity.generationKey,
        status: "live", isDefault: true, groundingUsed: false,
        sourceReferenceUrl: "https://private.convex.cloud/api/storage/private?token=fixture", createdAt: 1, updatedAt: 1 });
    });
  }
  return { t, licenseId, hadith, translated };
}

test("an empty locale is honest, guest safe, and never generates or picks Daily", async () => {
  const f = await setup();
  const fetch = vi.spyOn(globalThis, "fetch");
  const result = await f.t.query(get, { translationLocale: "ru", timezone });
  expect(result).toEqual({ kind: "unavailable", locale: "ru", reason: "not_prepared", daily: null });
  exportFixture("unavailable-ru", result);
  expect(fetch).not.toHaveBeenCalled();
  await f.t.run(async ctx => {
    for (const table of ["dailySelections", "aiGenerationJobs", "aiUsageEvents", "aiSpendReservations"] as const) expect(await ctx.db.query(table).collect()).toHaveLength(0);
  });
});

test("prepared English display does not require offline redistribution permission", async () => {
  const f = await setup(), hadithId = await f.hadith("1");
  const args = { locale: "en", rank: 0, hadithId, source: { kind: "provider_english" } } as const;
  const ids = await Promise.all([f.t.mutation(prepare, args), f.t.mutation(prepare, args)]);
  expect(ids[0]).toBe(ids[1]);
  const result = await f.t.query(get, { translationLocale: "en", timezone });
  expect(result).toMatchObject({ kind: "ready", origin: "starter", reading: { canonicalId: "sunnah_now:bukhari:1", text: { text: "Existing English 1", language: "en", isAI: false } } });
  exportFixture("starter-en", result);
  expect(await f.t.query(get, { translationLocale: "fr", timezone })).toMatchObject({ kind: "unavailable", locale: "fr" });
});

test("Arabic original is modeled deliberately and cannot supply another locale", async () => {
  const f = await setup(), hadithId = await f.hadith("1");
  await f.t.mutation(prepare, { locale: "ar", rank: 0, hadithId, source: { kind: "arabic_original" } });
  const result = await f.t.query(get, { translationLocale: "ar", timezone });
  expect(result).toMatchObject({ kind: "ready", reading: { text: { kind: "original", language: "ar", text: "نص 1" } } });
  exportFixture("original-ar", result);
  await expect(f.t.mutation(prepare, { locale: "ru", rank: 0, hadithId, source: { kind: "arabic_original" } })).rejects.toThrow("NOT_AUTHORIZED");
});

test("a translated starter preserves today's exact canonical identity", async () => {
  const f = await setup(), dailyId = await f.hadith("2"), starterId = await f.hadith("1");
  const translationId = await f.translated(starterId, "ru");
  const dailySelection = { timezone, localDate: localDateInTimezone(Date.now(), timezone), hadithId: dailyId, createdAt: 1 };
  await f.t.run(ctx => ctx.db.insert("dailySelections", dailySelection));
  await f.t.mutation(prepare, { locale: "ru", rank: 0, hadithId: starterId, source: { kind: "ai_translation", translationId } });
  const result = await f.t.query(get, { translationLocale: "ru", timezone });
  expect(result).toMatchObject({ kind: "ready", origin: "starter", locale: "ru", reading: { canonicalId: "sunnah_now:bukhari:1", text: { language: "ru", sourceLabel: "AI translation", isAI: true, sourceUrl: null }, referenceUrl: "https://example.org/reference" }, daily: { canonicalId: "sunnah_now:bukhari:2", hasExactText: false } });
  expect(JSON.stringify(result)).not.toContain("private.convex.cloud");
  exportFixture("starter-ru", result);
  expect(await f.t.run(ctx => ctx.db.query("dailySelections").collect())).toMatchObject([dailySelection]);
  await f.translated(dailyId, "ru");
  const dailyResult = await f.t.query(get, { translationLocale: "ru", timezone });
  expect(dailyResult).toMatchObject({ kind: "ready", origin: "daily", reading: { canonicalId: "sunnah_now:bukhari:2" }, daily: { hasExactText: true } });
  exportFixture("daily-ru", dailyResult);
});

test("changed text and withdrawn permission cannot survive prepared references", async () => {
  const f = await setup(), hadithId = await f.hadith("1");
  await f.t.mutation(prepare, { locale: "en", rank: 0, hadithId, source: { kind: "provider_english" } });
  await f.t.run(ctx => ctx.db.patch(hadithId, { englishText: "Changed content" }));
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
  await f.t.mutation(prepare, { locale: "en", rank: 0, hadithId, source: { kind: "provider_english" } });
  await f.t.run(ctx => ctx.db.patch(f.licenseId, { terms: { kind: "unverified" } }));
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
});

test("AI records without current source identity are not silently promoted to starters", async () => {
  const f = await setup(), hadithId = await f.hadith("1"), translationId = await f.translated(hadithId, "ru");
  await f.t.run(ctx => ctx.db.patch(translationId, { generationKey: undefined }));
  await expect(f.t.mutation(prepare, { locale: "ru", rank: 0, hadithId, source: { kind: "ai_translation", translationId } })).rejects.toThrow("NOT_AUTHORIZED");
});

test("unsupported regional tags and invalid timezones do not silently fall back", async () => {
  const f = await setup();
  await expect(f.t.query(get, { translationLocale: "ur-PK", timezone })).rejects.toThrow("UNSUPPORTED_FIRST_READING_LANGUAGE");
  await expect(f.t.query(get, { translationLocale: "ru", timezone: "not/a/timezone" })).rejects.toThrow("Invalid IANA timezone");
});

test("official starter permission is bound to exact text, identity and language", async () => {
  const f = await setup(), hadithId = await f.hadith("1");
  const text = "Official exact text";
  const now = Date.now();
  const grant = {
    sourceKind: "approved_translation", sourceUrl: "https://example.org/translation", artifactSha256: "a".repeat(64),
    textSha256: await textDigest(text), canonicalId: "sunnah_now:bukhari:1", language: "fr",
    citation: { url: "https://example.org/translation", title: "Fixture translation", location: "1" },
    rightsHolder: "Fixture translator", permissionUrl: "https://example.org/permission", permissionSha256: "b".repeat(64),
    licenseName: "Fixture display permission", attribution: "Fixture translator", access: true, comparison: false,
    modelProcessing: false, adaptation: false, display: true, redistribution: false, offline: false,
    conditions: "attribution_only", verifiedAt: now, expiresAt: now + 60_000,
  } satisfies PermissionGrant;
  const [translationId, permissionGrantId] = await f.t.run(async ctx => [
    await ctx.db.insert("translations", { hadithId, language: "fr", content: text, source: "official", sourceLabel: "Fixture translator", status: "live", isDefault: true, groundingUsed: false, createdAt: now, updatedAt: now }),
    await ctx.db.insert("evidencePermissionGrants", { grant, createdAt: now }),
  ] as const);
  const args = { locale: "fr", rank: 0, hadithId, source: { kind: "licensed_translation", translationId, permissionGrantId } } as const;
  await f.t.mutation(prepare, args);
  expect(await f.t.query(get, { translationLocale: "fr", timezone })).toMatchObject({ kind: "ready", validUntil: now + 60_000, reading: { text: { text, sourceUrl: "https://example.org/translation" } } });
  await f.t.run(ctx => ctx.db.patch(permissionGrantId, { grant: { ...grant, language: "en" } }));
  expect(await f.t.query(get, { translationLocale: "fr", timezone })).toMatchObject({ kind: "unavailable" });
  await expect(f.t.mutation(prepare, args)).rejects.toThrow("NOT_AUTHORIZED");
});


test("prepared targets reject providers, collections and identities the native reader cannot open", async () => {
  const f = await setup(), hadithId = await f.hadith("1");
  const args = { locale: "en", rank: 0, hadithId, source: { kind: "provider_english" } } as const;
  await f.t.mutation(prepare, args);
  for (const patch of [
    { provider: "sunnah_com", canonicalId: "sunnah_com:bukhari:1" },
    { provider: "sunnah_now", collectionSlug: "unknown", canonicalId: "sunnah_now:unknown:1" },
    { collectionSlug: "bukhari", canonicalId: "sunnah_now:bukhari:2" },
    { canonicalId: "sunnah_now:bukhari:1", providerHadithId: "../1" },
  ] as const) {
    await f.t.run(ctx => ctx.db.patch(hadithId, patch));
    await expect(f.t.mutation(prepare, args)).rejects.toThrow("NOT_AUTHORIZED");
    expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
  }
});

async function publishedStarter(expiresAt?: number) {
  vi.useFakeTimers();
  const f = await fixture();
  if (expiresAt !== undefined && f.grantId) await f.t.run(ctx => ctx.db.patch(f.grantId!, { grant: { ...f.grant, expiresAt } }));
  const claim = await reviewClaim(f);
  expect(await f.t.mutation(internal.evidenceReview.finish, {
    submissionId: f.draft.submissionId, token: claim.token, passes: passes(claim.packet),
  })).toBe(true);
  const translation = await f.t.run(ctx => ctx.db.query("translations")
    .withIndex("by_hadith_language_default", q => q.eq("hadithId", f.hadithId).eq("language", "en").eq("isDefault", true)).unique());
  if (!translation?.evidencePublicationId) throw new Error("Missing publication fixture");
  await f.t.run(async ctx => {
    const licenseRecordId = await ctx.db.insert("licenseRecords", {
      sourceKey: "published-first-reading-fixture", sourceName: "Fixture original", sourceUrl: "https://example.org/original",
      terms: { kind: "verified", licenseName: "Fixture display permission", licenseUrl: "https://example.org/permission",
        permitsDisplay: true, permitsRedistribution: false, permitsOfflineDistribution: false, verifiedAt: 1 }, createdAt: 1, updatedAt: 1,
    });
    await ctx.db.patch(f.hadithId, { licenseRecordId, authenticity: {
      kind: "collection_scope", normalizedGrade: "sahih", claimScope: "collection", sourceLabel: "Documented collection",
      sourceName: "Fixture source", sourceUrl: "https://example.org/original", verificationMethod: "manual_collection_mapping",
    } });
  });
  await f.t.mutation(prepare, { locale: "en", rank: 0, hadithId: f.hadithId,
    source: { kind: "published_translation", translationId: translation._id } });
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "ready" });
  return { ...f, translation, publicationId: translation.evidencePublicationId };
}

test("public starter resolution removes revoked grants and evidence publications", async () => {
  const f = await publishedStarter();
  if (!f.grantId) throw new Error("Missing fixture grant");
  await f.t.run(ctx => ctx.db.patch(f.grantId!, { grant: { ...f.grant, revokedAt: Date.now() } }));
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
  await f.t.run(async ctx => {
    await ctx.db.patch(f.grantId!, { grant: f.grant });
    await ctx.db.patch(f.publicationId, { status: "revoked" });
  });
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
});

test("public starter validity ends at the publication permission deadline", async () => {
  const expiry = Date.now() + 60_000;
  const f = await publishedStarter(expiry);
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "ready", validUntil: expiry });
  vi.setSystemTime(expiry + 1);
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
});

test("the actual public resolver fails closed on oversized publication dependency sets", async () => {
  const f = await publishedStarter();
  await f.t.run(async ctx => {
    for (let index = 0; index < 140; index++) await ctx.db.insert("evidenceSourceDependencies", {
      submissionId: f.draft.submissionId, origin: `https://fixture-${index}.example.org`,
    });
  });
  expect(await f.t.query(get, { translationLocale: "en", timezone })).toMatchObject({ kind: "unavailable" });
});


test("an exact-text incident block covers Daily and prepared references without altering translations", async () => {
  const f = await setup(), dailyId = await f.hadith("18"), safeId = await f.hadith("258");
  const badId = await f.translated(dailyId, "kk"), safeTranslationId = await f.translated(safeId, "kk");
  const source = { kind: "ai_translation", translationId: badId } as const;
  await f.t.mutation(prepare, { locale: "kk", rank: 0, hadithId: dailyId, source });
  await f.t.mutation(prepare, { locale: "kk", rank: 1, hadithId: safeId, source: { kind: "ai_translation", translationId: safeTranslationId } });
  await f.t.run(ctx => ctx.db.insert("dailySelections", { timezone, localDate: localDateInTimezone(Date.now(), timezone), hadithId: dailyId, createdAt: 1 }));
  expect(await f.t.query(get, { translationLocale: "kk", timezone })).toMatchObject({ kind: "ready", origin: "daily" });
  const before = await f.t.run(ctx => ctx.db.get(badId));
  if (!before) throw new Error("Missing blocked fixture");
  const args = { translationId: badId, contentSha256: await textDigest(before.content), reason: "meaning_reversal" } as const;
  const first = await f.t.mutation(internal.firstReading.blockTranslation, args);
  expect(await f.t.mutation(internal.firstReading.blockTranslation, args)).toBe(first);
  expect(await f.t.query(get, { translationLocale: "kk", timezone })).toMatchObject({ kind: "ready", origin: "starter", reading: { canonicalId: "sunnah_now:bukhari:258" }, daily: { canonicalId: "sunnah_now:bukhari:18", hasExactText: false } });
  expect(await f.t.run(ctx => ctx.db.get(badId))).toEqual(before);
  await expect(f.t.mutation(prepare, { locale: "kk", rank: 0, hadithId: dailyId, source })).rejects.toThrow("NOT_AUTHORIZED");
  await f.t.run(ctx => ctx.db.patch(badId, { content: "Different exact text version" }));
  await expect(f.t.mutation(internal.firstReading.blockTranslation, args)).rejects.toThrow("TEXT_CHANGED");
  expect(await f.t.query(get, { translationLocale: "kk", timezone })).toMatchObject({ kind: "ready", origin: "daily" });
});

test("a known meaning reversal is unavailable through ordinary reader, cache and publication reads", async () => {
  const f = await setup(), hadithId = await f.hadith("18");
  const translationId = await f.translated(hadithId, "kk");
  const ref = { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "18", language: "kk" } as const;
  expect(await f.t.query(api.translations.getDefaultForProviderRef, ref)).toMatchObject({ _id: translationId });
  const before = await f.t.run(ctx => ctx.db.get(translationId));
  if (!before) throw new Error("Missing incident fixture");
  await f.t.mutation(internal.firstReading.blockTranslation, { translationId, contentSha256: await textDigest(before.content), reason: "meaning_reversal" });
  expect(await f.t.query(api.translations.getDefaultForProviderRef, ref)).toBeNull();
  expect(await f.t.query(api.translations.getReaderDefaults, { hadithInternalIds: ["sunnah_now:bukhari:18"], language: "kk" })).toEqual([
    { hadithInternalId: "sunnah_now:bukhari:18", translation: null },
  ]);
  expect(await f.t.query(internal.translations.getDefaultForHadithLanguage, { hadithId, language: "kk" })).toBeNull();
  expect(await f.t.query(internal.translations.listLiveDefaultsForHadithLanguage, { hadithId, language: "kk" })).toEqual([]);
  expect(await f.t.query(api.translations.watchPublications, { translationIds: [translationId] })).toEqual([
    { translationId, available: false, validUntil: null },
  ]);
  expect(await f.t.run(ctx => ctx.db.get(translationId))).toEqual(before);
  await f.t.run(ctx => ctx.db.patch(translationId, { content: "Corrected exact text version" }));
  expect(await f.t.query(api.translations.getDefaultForProviderRef, ref)).toMatchObject({ _id: translationId, content: "Corrected exact text version" });
});

test("a standalone first-reading exclusion does not suppress an ordinary reader translation", async () => {
  const f = await setup(), hadithId = await f.hadith("264");
  const translationId = await f.translated(hadithId, "kk");
  const row = await f.t.run(ctx => ctx.db.get(translationId));
  if (!row) throw new Error("Missing standalone fixture");
  await f.t.mutation(internal.firstReading.blockTranslation, { translationId, contentSha256: await textDigest(row.content), reason: "unsuitable_standalone" });
  expect(await f.t.query(api.translations.getDefaultForProviderRef, { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "264", language: "kk" })).toMatchObject({ _id: translationId });
});
