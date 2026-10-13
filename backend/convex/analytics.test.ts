/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import schema from "./schema";
import { internal } from "./_generated/api";
import { DAY, HOUR, parseSummary } from "./lib/analyticsPolicy";
import { METRICS } from "./lib/analyticsCatalog";
import { sendAggregate } from "./actions/analytics";

const modules = import.meta.glob("./**/*.ts");
const fixed = Date.parse("2026-10-13T10:00:00Z");
const body = (index = 0) => ({ version: 1, platform: "ios" as const,
  batchId: `12345678-1234-4123-8123-${index.toString().padStart(12, "0")}`,
  hour: Math.floor(Date.now() / HOUR), counters: [{ metric: "onboarding_completed.guest", count: 1 }] });
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(fixed); vi.stubEnv("ANALYTICS_ENABLED", "1"); });
afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

test("ten families and exact fields reject forbidden content at every input level", () => {
  expect(new Set(METRICS.map(metric => metric.split(".")[0])).size).toBe(10);
  expect(parseSummary(body(), fixed)).not.toBeNull();
  for (const key of ["locale", "text", "translation", "notes", "evidence", "search", "canonicalId", "collection", "email", "token", "userId", "url", "properties", "environment"])
    expect(parseSummary({ ...body(), [key]: "PRIVATE_CANARY" }, fixed)).toBeNull();
  expect(parseSummary({ ...body(), counters: [{ ...body().counters[0], text: "PRIVATE_CANARY" }] }, fixed)).toBeNull();
  expect(parseSummary({ ...body(), counters: [{ metric: "reader_open_result.PRIVATE_CANARY", count: 1 }] }, fixed)).toBeNull();
  for (const count of [0, -1, 41, 1.5, Infinity, NaN])
    expect(parseSummary({ ...body(), counters: [{ ...body().counters[0], count }] }, fixed)).toBeNull();
  expect(parseSummary({ ...body(), counters: [...body().counters, ...body().counters] }, fixed)).toBeNull();
  expect(parseSummary({ ...body(), version: 2 }, fixed)).toBeNull();
  expect(parseSummary({ ...body(), hour: body().hour + 1 }, fixed)).toBeNull();
  expect(parseSummary({ ...body(), hour: body().hour - 24 }, fixed)).toBeNull();
});

test("real HTTP rejects credentials, content, oversized bytes and client environment", async () => {
  const t = convexTest(schema, modules), headers = { "Content-Type": "application/json" };
  expect((await t.fetch("/analytics/summary", { method: "POST", headers, body: JSON.stringify(body()) })).status).toBe(204);
  for (const name of ["Authorization", "Cookie", "Origin"]) expect((await t.fetch("/analytics/summary", {
    method: "POST", headers: { ...headers, [name]: "PRIVATE_CANARY" }, body: JSON.stringify(body(2)) })).status).toBe(403);
  expect((await t.fetch("/analytics/summary", { method: "POST", headers, body: "x".repeat(4097) })).status).toBe(413);
  expect((await t.fetch("/analytics/summary", { method: "POST", headers, body: JSON.stringify({ ...body(2), token: "PRIVATE_CANARY" }) })).status).toBe(400);
  const receipt = await t.run(ctx => ctx.db.query("analyticsReceipts").unique());
  expect(Object.keys(receipt ?? {}).sort()).toEqual(["_creationTime", "_id", "batchId", "expiresAt"]);
  expect(JSON.stringify(await t.run(ctx => ctx.db.query("analyticsBuckets").collect()))).not.toContain(body().batchId);
});

test("concurrent retries increment only once; expiry removes receipt and rejects old replay", async () => {
  const t = convexTest(schema, modules);
  const results = await Promise.all(Array.from({ length: 12 }, () => t.mutation(internal.analytics.accept, body())));
  expect(results.filter(value => value === "accepted")).toHaveLength(1);
  expect((await t.run(ctx => ctx.db.query("analyticsBuckets").unique()))?.summaries).toBe(1);
  const expired = body(); vi.setSystemTime(fixed + DAY);
  await t.mutation(internal.analytics.retain, {});
  expect(await t.run(ctx => ctx.db.query("analyticsReceipts").collect())).toHaveLength(0);
  expect(await t.mutation(internal.analytics.accept, expired)).toBe("invalid");
});

test("atomic admission caps and monthly rollover", async () => {
  const t = convexTest(schema, modules);
  await t.mutation(internal.analytics.accept, body());
  await t.run(async ctx => { const row = await ctx.db.query("analyticsState").unique(); if (row)
    await ctx.db.patch(row._id, { admittedMonthly: 49_999 }); });
  const results = await Promise.all(Array.from({ length: 8 }, (_, i) => t.mutation(internal.analytics.accept, body(i + 1))));
  expect(results.filter(value => value === "accepted")).toHaveLength(1);
  vi.setSystemTime(Date.parse("2026-11-01T01:00:00Z"));
  expect(await t.mutation(internal.analytics.accept, body(20))).toBe("accepted");
  expect((await t.query(internal.analytics.health, {})).admittedMonthly).toBe(1);
});

test("settlement delay prevents late counts being lost; threshold, leases and attempts are bounded", async () => {
  const t = convexTest(schema, modules); vi.stubEnv("ANALYTICS_POSTHOG_KEY", "test_project_key");
  for (let i = 0; i < 10; i++) await t.mutation(internal.analytics.accept, body(i));
  const args = { uuid: body().batchId };
  expect(await t.mutation(internal.analytics.claim, args)).toBeNull();
  vi.setSystemTime(Date.parse("2026-10-15T00:00:00Z"));
  const job = await t.mutation(internal.analytics.claim, args);
  expect(job?.counters[0].count).toBe(10);
  expect(await t.mutation(internal.analytics.claim, args)).toBeNull();
  if (!job) throw new Error("missing export");
  await t.mutation(internal.analytics.settle, { id: job.id, attempt: 0, success: true });
  expect((await t.run(ctx => ctx.db.get(job.id)))?.exported).toBe(false);
  await t.mutation(internal.analytics.settle, { id: job.id, attempt: job.attempt, success: false });
  vi.setSystemTime(Date.now() + 60_001);
  const second = await t.mutation(internal.analytics.claim, { uuid: body(90).batchId });
  expect(second?.uuid).toBe(job.uuid);
  if (!second) throw new Error("missing retry");
  await t.mutation(internal.analytics.settle, { id: second.id, attempt: second.attempt, success: true });
  expect(await t.mutation(internal.analytics.claim, args)).toBeNull();
  expect((await t.run(ctx => ctx.db.get(job.id)))?.expiresAt).toBe(Date.now() + 90 * DAY);
});

test("below-threshold buckets expire without ever exporting", async () => {
  const t = convexTest(schema, modules); vi.stubEnv("ANALYTICS_POSTHOG_KEY", "test_project_key");
  await t.mutation(internal.analytics.accept, body());
  vi.setSystemTime(fixed + 8 * DAY);
  expect(await t.mutation(internal.analytics.claim, { uuid: body().batchId })).toBeNull();
  await t.mutation(internal.analytics.retain, {});
  expect(await t.run(ctx => ctx.db.query("analyticsBuckets").collect())).toHaveLength(0);
});

test("expiry drains a full daily admission burst within the same cleanup cycle", async () => {
  const t = convexTest(schema, modules);
  await t.run(async ctx => {
    for (let i = 0; i < 2000; i++) await ctx.db.insert("analyticsReceipts", { batchId: body(i).batchId, expiresAt: Date.now() - 1 });
  });
  await t.mutation(internal.analytics.retain, {});
  await t.finishAllScheduledFunctions(() => vi.runAllTimers());
  expect(await t.run(ctx => ctx.db.query("analyticsReceipts").collect())).toHaveLength(0);
});
test("export-only month rollover resets the previous month's failures", async () => {
  const t = convexTest(schema, modules); vi.stubEnv("ANALYTICS_POSTHOG_KEY", "test_project_key");
  for (let i = 0; i < 10; i++) await t.mutation(internal.analytics.accept, body(i));
  await t.run(async ctx => {
    const row = await ctx.db.query("analyticsState").unique(); if (row) await ctx.db.patch(row._id, { exportFailures: 7 });
    await ctx.db.insert("analyticsBuckets", { day: "2026-10-12", platform: "android", summaries: 10,
      counters: [{ metric: "onboarding_completed.guest", count: 10 }], exported: false, expiresAt: fixed + 90 * DAY });
    const bucket = await ctx.db.query("analyticsBuckets").withIndex("by_day_platform", q => q.eq("day", "2026-10-13").eq("platform", "ios")).unique();
    if (bucket) await ctx.db.patch(bucket._id, { expiresAt: fixed + 90 * DAY });
  });
  vi.setSystemTime(Date.parse("2026-11-02T00:00:00Z"));
  expect((await t.mutation(internal.analytics.claim, { uuid: body(90).batchId }))?.health.exportFailures).toBe(0);
  expect((await t.mutation(internal.analytics.claim, { uuid: body(91).batchId }))?.health.exportFailures).toBe(0);
});

test("SDK shutdown cannot resend after a network failure", async () => {
  vi.useRealTimers();
  const fetch = vi.fn(async () => { throw new Error("OFFLINE"); }); vi.stubGlobal("fetch", fetch);
  expect(await sendAggregate({ uuid: body().batchId, day: "2026-10-13", platform: "android", environment: "development",
    counters: [{ metric: "onboarding_completed.guest", count: 10 }] }, "test_project_key")).toBe(false);
  expect(fetch).toHaveBeenCalledTimes(1);
});

test("actual SDK payload contains only counts, day buckets and aggregate identity; 429 gets one attempt", async () => {
  vi.useRealTimers();
  const requests: string[] = [];
  vi.stubGlobal("fetch", vi.fn(async (url, options) => { expect(String(url)).toContain("eu.i.posthog.com");
    requests.push(String(options.body)); return new Response("{}", { status: 429 }); }));
  expect(await sendAggregate({ uuid: body().batchId, day: "2026-10-13", platform: "ios", environment: "development",
    counters: [{ metric: "onboarding_completed.guest", count: 10 }] }, "test_project_key")).toBe(false);
  expect(requests).toHaveLength(1);
  const parsed = JSON.parse(requests[0]);
  expect(parsed.batch).toHaveLength(1);
  const event = parsed.batch[0];
  expect(event.event).toBe("onboarding_completed");
  expect(event.properties.distinct_id).toBe("aggregate:2026-10-13:ios:development");
  expect(Object.keys(event.properties).sort()).toEqual(["$geoip_disable", "$process_person_profile", "count", "day", "distinct_id", "environment", "platform", "schema_version", "variant", "measurement_month", "admitted_monthly", "exported_monthly", "export_failures", "rejected_monthly", "suppressed_buckets", "observed_hour"].sort());
  expect(requests[0]).not.toContain(body().batchId);
});

test("early verification export is internal, explicit and exclusive to named development deployment", async () => {
  const t = convexTest(schema, modules); vi.stubEnv("ANALYTICS_POSTHOG_KEY", "test_project_key");
  for (let i = 0; i < 10; i++) await t.mutation(internal.analytics.accept, body(i));
  vi.stubEnv("ANALYTICS_VERIFY_CURRENT_DAY", "1"); vi.stubEnv("CONVEX_CLOUD_URL", "https://giddy-ox-648.eu-west-1.convex.cloud");
  expect(await t.mutation(internal.analytics.claim, { uuid: body().batchId, verifyCurrentDay: true })).toBeNull();
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  expect(await t.mutation(internal.analytics.claim, { uuid: body().batchId })).toBeNull();
  const job = await t.mutation(internal.analytics.claim, { uuid: body().batchId, verifyCurrentDay: true });
  expect(job).not.toBeNull();
  if (job) await t.mutation(internal.analytics.settle, { id: job.id, attempt: job.attempt, success: true });
  expect(await t.mutation(internal.analytics.accept, body(11))).toBe("invalid");
  expect((await t.query(internal.analytics.health, {})).admittedDaily).toBe(10);
});

test("measurement health counts rejections without retaining invalid summaries and warns at each budget", async () => {
  const t = convexTest(schema, modules);
  await t.mutation(internal.analytics.recordRejection, {});
  expect((await t.query(internal.analytics.health, {})).rejectedMonthly).toBe(1);
  expect(await t.run(ctx => ctx.db.query("analyticsReceipts").collect())).toHaveLength(0);
  await t.run(async ctx => { const row = await ctx.db.query("analyticsState").unique(); if (row) await ctx.db.patch(row._id, { exportedMonthly: 8000 }); });
  expect((await t.query(internal.analytics.health, {})).warning).toBe(true);
});
