/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import schema from "./schema";
import { internal } from "./_generated/api";
import { safeEvent, parseWebFailure, sentryDestination } from "./lib/diagnosticsPolicy";

const modules = import.meta.glob("./**/*.ts");
const instances: ReturnType<typeof convexTest>[] = [];
function setup() { const t = convexTest(schema, modules); instances.push(t); return t; }
beforeEach(() => { vi.useFakeTimers(); vi.setSystemTime(new Date("2026-10-13T00:00:00Z")); vi.stubEnv("DIAGNOSTICS_ENABLED", "1"); });
afterEach(async () => {
  for (const t of instances.splice(0)) await t.finishAllScheduledFunctions(() => vi.runAllTimers());
  vi.useRealTimers(); vi.unstubAllEnvs(); vi.unstubAllGlobals();
});

test("public input accepts exact fields only; no content or identity can enter a vendor event", () => {
  const safe = { operation: "canonical_resolver", release: "hadithly@123456abcdef", environment: "development" };
  expect(parseWebFailure(safe)).toEqual(safe);
  for (const key of ["token", "user", "message", "notes", "evidence", "query", "arabicText", "translation", "url"])
    expect(parseWebFailure({ ...safe, [key]: "PRIVATE_TEST_CANARY" })).toBeNull();
  expect(parseWebFailure({ ...safe, release: "PRIVATE_TEST_CANARY" })).toBeNull();
  const body = JSON.stringify(safeEvent({ surface: "web", operation: "canonical_resolver", eventId: "0".repeat(32) }));
  expect(body).not.toContain("PRIVATE_TEST_CANARY");
  expect(JSON.parse(body).tags).toEqual({ surface: "web", operation: "canonical_resolver" });
  expect(sentryDestination("https://" + "a".repeat(32) + "@o1.ingest.de.sentry.io/1")?.url).toBe("https://o1.ingest.de.sentry.io/api/1/envelope/");
  for (const dsn of ["http://example.com/1", "https://user@evil.test/1", "https://" + "a".repeat(32) + "@o1.ingest.sentry.io/1?secret=test"])
    expect(sentryDestination(dsn)).toBeNull();
});

test("actual HTTP ingress validates origin, body cap and exact safe fields", async () => {
  const t = setup();
  vi.stubEnv("DIAGNOSTICS_WEB_ORIGIN", "https://hadithly-la1-preview.vercel.app");
  const body = { operation: "synthetic", release: "hadithly@123456abcdef", environment: "development" };
  const headers = { Origin: "https://hadithly-la1-preview.vercel.app", "Content-Type": "application/json" };
  expect((await t.fetch("/diagnostics/web", { method: "POST", headers, body: JSON.stringify(body) })).status).toBe(204);
  expect((await t.fetch("/diagnostics/web", { method: "POST", headers: { ...headers, Origin: "https://untrusted.example" }, body: JSON.stringify(body) })).status).toBe(403);
  expect((await t.fetch("/diagnostics/web", { method: "POST", headers, body: JSON.stringify({ ...body, token: "PRIVATE_TEST_CANARY" }) })).status).toBe(400);
  expect((await t.fetch("/diagnostics/web", { method: "POST", headers, body: "x".repeat(513) })).status).toBe(413);
  const row = await t.run(ctx => ctx.db.query("diagnosticsState").unique());
  expect(row?.webReports).toBe(1);
});

test("concurrent admission stays singleton and rate limited", async () => {
  const t = setup();
  const results = await Promise.all(Array.from({ length: 20 }, () => t.mutation(internal.diagnostics.recordFailure,
    { operation: "generation", surface: "backend" })));
  expect(results.filter(Boolean)).toHaveLength(1);
  expect(await t.run(ctx => ctx.db.query("diagnosticsState").collect())).toHaveLength(1);
  const row = await t.run(ctx => ctx.db.query("diagnosticsState").unique());
  expect(row?.reports).toBe(1);
});

test("web budget cannot consume backend reserve or manufacture API failure health", async () => {
  const t = setup();
  await t.mutation(internal.diagnostics.heartbeat, {});
  await t.run(async ctx => {
    const row = await ctx.db.query("diagnosticsState").unique();
    if (!row) throw new Error("fixture missing");
    await ctx.db.patch(row._id, { webReports: 200 });
  });
  expect(await t.mutation(internal.diagnostics.recordFailure, { operation: "synthetic", surface: "web" })).toBe(false);
  expect(await t.mutation(internal.diagnostics.recordFailure, { operation: "generation", surface: "backend" })).toBe(true);
  expect((await t.query(internal.diagnostics.health, { component: "api" })).status).toBe("ready");
});

test("five real sampled failures degrade health, expiry recovers, scheduler has independent stale health", async () => {
  const t = setup();
  await t.mutation(internal.diagnostics.heartbeat, {});
  for (let i = 0; i < 5; i++) {
    await t.mutation(internal.diagnostics.recordFailure, { operation: "generation", surface: "backend" });
    vi.setSystemTime(Date.now() + 61_000);
  }
  expect((await t.query(internal.diagnostics.health, { component: "api" })).status).toBe("degraded");
  vi.setSystemTime(Date.now() + 10 * 60_000);
  expect((await t.query(internal.diagnostics.health, { component: "api" })).status).toBe("ready");
  vi.setSystemTime(Date.now() + 45 * 60_000);
  expect((await t.query(internal.diagnostics.health, { component: "notifications" })).status).toBe("degraded");
  await t.mutation(internal.diagnostics.heartbeat, {});
  expect((await t.query(internal.diagnostics.health, { component: "notifications" })).status).toBe("ready");
});

test("monthly cap is atomic and rollover erases old aggregate failure state", async () => {
  const t = setup();
  await t.mutation(internal.diagnostics.heartbeat, {});
  await t.run(async ctx => {
    const row = await ctx.db.query("diagnosticsState").unique();
    if (!row) throw new Error("fixture missing");
    await ctx.db.patch(row._id, { reports: 799 });
  });
  const results = await Promise.all(Array.from({ length: 8 }, () => t.mutation(internal.diagnostics.recordFailure, { operation: "synthetic", surface: "backend" })));
  expect(results.filter(Boolean)).toHaveLength(1);
  vi.setSystemTime(new Date("2026-11-01T00:01:00Z"));
  await t.mutation(internal.diagnostics.heartbeat, {});
  const row = await t.run(ctx => ctx.db.query("diagnosticsState").unique());
  expect(row?.reports).toBe(0); expect(row?.lastFailureAt).toBe(0);
});

test("vendor outage performs one safe request and never recurses or retries", async () => {
  const t = setup();
  vi.stubEnv("DIAGNOSTICS_SENTRY_DSN", "https://" + "a".repeat(32) + "@o1.ingest.de.sentry.io/1");
  const fetcher = vi.fn(async () => new Response(null, { status: 429 })); vi.stubGlobal("fetch", fetcher);
  expect(await t.action(internal.actions.diagnostics.send, { surface: "backend", operation: "synthetic" })).toBe("dropped");
  expect(fetcher).toHaveBeenCalledTimes(1);
  const request = fetcher.mock.calls[0]; expect(request).toBeDefined();
  expect(await t.run(ctx => ctx.db.query("diagnosticsState").collect())).toHaveLength(0);
});
