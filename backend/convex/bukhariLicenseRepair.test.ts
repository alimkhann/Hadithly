/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { normalizeHadith } from "./lib/sunnahNow";

afterEach(() => vi.unstubAllEnvs());
async function fixture() {
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  const t = convexTest(schema, import.meta.glob("./**/*.ts"));
  const [hadithId] = await t.mutation(internal.hadiths.upsertPage, { items: [normalizeHadith("bukhari", { id: "7" })] });
  await t.run(ctx => ctx.db.patch(hadithId, { arabicText: "نص عربي" }));
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  return { t, hadithId };
}

test.each(["missing", "dangling"])("repairs a %s link and admits generation once", async kind => {
  const { t, hadithId } = await fixture();
  await t.run(async ctx => {
    if (kind === "missing") await ctx.db.patch(hadithId, { licenseRecordId: undefined });
    else {
      const id = await ctx.db.insert("licenseRecords", { sourceKey: "obsolete", sourceName: "Obsolete", sourceUrl: "", terms: { kind: "unverified" }, createdAt: 0, updatedAt: 0 });
      await ctx.db.patch(hadithId, { licenseRecordId: id });
      await ctx.db.delete(id);
    }
  });
  expect(await t.query(internal.migrations.inspectBukhariSevenLicense, {})).toMatchObject({ pointer: kind, linkedSourceKey: null, linkedTermsKind: null, matchesCanonicalSourceLicense: false });
  expect(await t.mutation(internal.quotas.admit, { hadithId, language: "ru", signal: "service" })).toMatchObject({ kind: "rejected", code: "AI_SOURCE_UNAVAILABLE" });
  expect(await t.mutation(internal.migrations.repairBukhariSevenLicense, {})).toBe("repaired");
  expect(await t.mutation(internal.migrations.repairBukhariSevenLicense, {})).toBe("already_linked");
  expect(await t.query(internal.migrations.inspectBukhariSevenLicense, {})).toMatchObject({ pointer: "linked", linkedSourceKey: "sunnah_now", linkedTermsKind: "verified", matchesCanonicalSourceLicense: true });
  expect(await t.mutation(internal.quotas.admit, { hadithId, language: "ru", signal: "service" })).toMatchObject({ kind: "claimed", references: [] });
});

test("refuses to replace a valid different binding", async () => {
  const { t, hadithId } = await fixture();
  const otherId = await t.run(async ctx => {
    const id = await ctx.db.insert("licenseRecords", { sourceKey: "other", sourceName: "Other", sourceUrl: "", terms: { kind: "unverified" }, createdAt: 0, updatedAt: 0 });
    await ctx.db.patch(hadithId, { licenseRecordId: id });
    return id;
  });
  await expect(t.mutation(internal.migrations.repairBukhariSevenLicense, {})).rejects.toThrow("EXISTING_LICENSE_BINDING");
  expect((await t.run(ctx => ctx.db.get(hadithId)))?.licenseRecordId).toBe(otherId);
});

test("rejects unknown deployments and an unverified canonical source", async () => {
  const { t } = await fixture();
  vi.stubEnv("CONVEX_CLOUD_URL", "https://unknown.convex.cloud");
  await expect(t.query(internal.migrations.inspectBukhariSevenLicense, {})).rejects.toThrow("DEVELOPMENT_ONLY");
  await expect(t.mutation(internal.migrations.repairBukhariSevenLicense, {})).rejects.toThrow("DEVELOPMENT_ONLY");
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  const license = await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" });
  if (!license) throw new Error("Missing source");
  await t.run(ctx => ctx.db.patch(license._id, { terms: { kind: "unverified" } }));
  await expect(t.mutation(internal.migrations.repairBukhariSevenLicense, {})).rejects.toThrow("SOURCE_LICENSE_UNAVAILABLE");
});
