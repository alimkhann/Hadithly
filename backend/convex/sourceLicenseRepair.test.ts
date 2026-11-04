/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { normalizeHadith } from "./lib/sunnahNow";

afterEach(() => vi.unstubAllEnvs());
test("runner aggregates bounded pages and resumes from its returned cursor", async () => {
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  const t = convexTest(schema, import.meta.glob("./**/*.ts"));
  const ids = await t.mutation(internal.hadiths.upsertPage, { items: Array.from({ length: 201 }, (_, i) => normalizeHadith("bukhari", { id: String(i + 1) })) });
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  await t.run(async ctx => { for (const id of ids) await ctx.db.patch(id, { licenseRecordId: undefined }); });
  const first = await t.action(internal.migrations.runSunnahNowLinkRepair, { cursor: null, maxPages: 1 });
  expect(first).toMatchObject({ scanned: 100, repaired: 100, conflicts: 0, isDone: false, pages: 1 });
  const rest = await t.action(internal.migrations.runSunnahNowLinkRepair, { cursor: first.continueCursor, maxPages: 5 });
  expect(rest).toMatchObject({ scanned: 101, repaired: 101, conflicts: 0, isDone: true, pages: 2 });
  const repeat = await t.action(internal.migrations.runSunnahNowLinkRepair, { cursor: null, maxPages: 5 });
  expect(repeat).toMatchObject({ scanned: 201, repaired: 0, isDone: true, pages: 3 });
});

test("runner rejects out-of-bounds page counts and non-development deployment", async () => {
  const t = convexTest(schema, import.meta.glob("./**/*.ts"));
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  for (const maxPages of [0, 101, 1.5]) await expect(t.action(internal.migrations.runSunnahNowLinkRepair, { cursor: null, maxPages })).rejects.toThrow("INVALID_PAGE_COUNT");
  vi.stubEnv("CONVEX_CLOUD_URL", "https://unknown.convex.cloud");
  await expect(t.action(internal.migrations.runSunnahNowLinkRepair, { cursor: null, maxPages: 1 })).rejects.toThrow("DEVELOPMENT_ONLY");
});

test("bounded pages repair only missing Sunnah.now links and preserve every other field", async () => {
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  const t = convexTest(schema, import.meta.glob("./**/*.ts"));
  const ids = await t.mutation(internal.hadiths.upsertPage, { items: Array.from({ length: 5 }, (_, i) => normalizeHadith("bukhari", { id: String(i + 1) })) });
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  await t.run(async ctx => {
    const other = await ctx.db.insert("licenseRecords", { sourceKey: "other", sourceName: "Other", sourceUrl: "", terms: { kind: "unverified" }, createdAt: 0, updatedAt: 0 });
    const dangling = await ctx.db.insert("licenseRecords", { sourceKey: "deleted", sourceName: "Deleted", sourceUrl: "", terms: { kind: "unverified" }, createdAt: 0, updatedAt: 0 });
    await ctx.db.patch(ids[0], { licenseRecordId: undefined });
    await ctx.db.patch(ids[1], { licenseRecordId: dangling });
    await ctx.db.delete(dangling);
    await ctx.db.patch(ids[2], { licenseRecordId: other });
    await ctx.db.patch(ids[4], { provider: "local_dump", licenseRecordId: undefined });
  });
  const before = await t.run(async ctx => Promise.all(ids.map(id => ctx.db.get(id))));
  const sourceBefore = await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" });
  const run = async () => {
    let cursor: string | null = null, scanned = 0, repaired = 0, conflicts = 0;
    do {
      const page: { scanned: number; repaired: number; conflicts: number; continueCursor: string; isDone: boolean } =
        await t.mutation(internal.migrations.repairSunnahNowLinks, { paginationOpts: { cursor, numItems: 2 } });
      scanned += page.scanned; repaired += page.repaired; conflicts += page.conflicts;
      cursor = page.isDone ? null : page.continueCursor;
    } while (cursor);
    return { scanned, repaired, conflicts };
  };
  expect(await run()).toEqual({ scanned: 4, repaired: 2, conflicts: 1 });
  expect(await run()).toEqual({ scanned: 4, repaired: 0, conflicts: 1 });
  const after = await t.run(async ctx => Promise.all(ids.map(id => ctx.db.get(id))));
  for (let i = 0; i < ids.length; i++) {
    expect(after[i]).toEqual({ ...before[i], ...([0, 1].includes(i) ? { licenseRecordId: sourceBefore?._id } : {}) });
  }
  expect(await t.query(internal.offlineDumps.getLicenseBySourceKey, { sourceKey: "sunnah_now" })).toEqual(sourceBefore);
});

test("requires a named development deployment and a verified source", async () => {
  const t = convexTest(schema, import.meta.glob("./**/*.ts"));
  vi.stubEnv("CONVEX_CLOUD_URL", "https://unknown.convex.cloud");
  await expect(t.mutation(internal.migrations.repairSunnahNowLinks, { paginationOpts: { cursor: null, numItems: 100 } })).rejects.toThrow("DEVELOPMENT_ONLY");
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  await expect(t.mutation(internal.migrations.repairSunnahNowLinks, { paginationOpts: { cursor: null, numItems: 100 } })).rejects.toThrow("SOURCE_LICENSE_UNAVAILABLE");
  await t.run(ctx => ctx.db.insert("licenseRecords", { sourceKey: "sunnah_now", sourceName: "Sunnah.now", sourceUrl: "", terms: { kind: "unverified" }, createdAt: 0, updatedAt: 0 }));
  await expect(t.mutation(internal.migrations.repairSunnahNowLinks, { paginationOpts: { cursor: null, numItems: 100 } })).rejects.toThrow("SOURCE_LICENSE_UNAVAILABLE");
  await expect(t.mutation(internal.migrations.repairSunnahNowLinks, { paginationOpts: { cursor: null, numItems: 101 } })).rejects.toThrow("INVALID_PAGE_SIZE");
});
