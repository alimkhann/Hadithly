/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { normalizeHadith } from "./lib/sunnahNow";
import { firstReadingPublicUrl } from "./lib/firstReadingPolicy";

const modules = import.meta.glob("./**/*.ts");
const development = "https://festive-cobra-664.eu-west-1.convex.cloud";
afterEach(() => vi.unstubAllEnvs());

test("owner confirmation preserves the license identity and enables admitted generation without comparison references", async () => {
  vi.stubEnv("CONVEX_CLOUD_URL", development);
  const t = convexTest(schema, modules);
  const [hadithId] = await t.mutation(internal.hadiths.upsertPage, { items: [normalizeHadith("bukhari", { id: "7" })] });
  await t.run(ctx => ctx.db.patch(hadithId, { arabicText: "نص عربي" }));
  const before = await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" });
  expect(before?.terms.kind).toBe("unverified");
  expect(await t.mutation(internal.quotas.admit, { hadithId, language: "ru", signal: "service" })).toMatchObject({ kind: "rejected", code: "AI_SOURCE_UNAVAILABLE" });
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  const confirmed = await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" });
  expect(confirmed?._id).toBe(before?._id);
  expect(confirmed?.terms).toMatchObject({ kind: "verified", licenseName: "Owner-confirmed Sunnah.now display and AI translation permission", licenseUrl: "", permitsDisplay: true, permitsRedistribution: false, permitsOfflineDistribution: false });
  expect(firstReadingPublicUrl(confirmed?.terms.kind === "verified" ? confirmed.terms.licenseUrl : undefined)).toBeNull();
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  expect(await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" })).toEqual(confirmed);
  expect(await t.mutation(internal.quotas.admit, { hadithId, language: "ru", signal: "service" })).toMatchObject({ kind: "claimed", references: [] });
});

test("creates a missing record but never replaces already verified terms", async () => {
  vi.stubEnv("CONVEX_CLOUD_URL", development);
  const t = convexTest(schema, modules);
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  const record = await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" });
  if (!record || record.terms.kind !== "verified") throw new Error("Missing verified record");
  const terms = record.terms;
  await t.run(ctx => ctx.db.patch(record._id, { terms: { ...terms, licenseName: "Existing", permitsRedistribution: true, permitsOfflineDistribution: true } }));
  const existing = await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" });
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  expect(await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" })).toEqual(existing);
});

test.each(["https://giddy-ox-648.convex.cloud", "https://unknown.convex.cloud", ""])("rejects deployment %s", async url => {
  vi.stubEnv("CONVEX_CLOUD_URL", url);
  const t = convexTest(schema, modules);
  await expect(t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {})).rejects.toThrow("DEVELOPMENT_ONLY");
  expect(await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" })).toBeNull();
});
