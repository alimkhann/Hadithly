/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, describe, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { parseRevenueCatEvent, parseRevenueCatSnapshot, revenueCatPolicy, subscriptionAccess } from "./lib/revenueCat";

const modules = import.meta.glob("./**/*.ts");
const monthly = "com.hadithly.app.pro.monthly";
const play = "hadithly_pro_annual:annual";
const now = 1800000000000;
const provider = vi.fn();
function subscription(overrides: Record<string, unknown> = {}) {
  return { store: "app_store", ownership_type: "PURCHASED", is_sandbox: false, refunded_at: null,
    expires_date: new Date(now + 1000).toISOString(), grace_period_expires_date: null,
    billing_issues_detected_at: null, unsubscribe_detected_at: null, ...overrides };
}
function snapshot(rows: Record<string, unknown> = { [monthly]: subscription() }, original = "user_owner") {
  return { request_date_ms: now, subscriber: { original_app_user_id: original, entitlements: { pro: { product_identifier: monthly } }, subscriptions: rows } };
}
function event(type = "INITIAL_PURCHASE", id = "event-one", overrides: Record<string, unknown> = {}) {
  return { event: { id, app_id: "app_fixture", environment: "PRODUCTION", app_user_id: "user_owner", type, ...overrides } };
}
async function fixture() {
  const t = convexTest(schema, modules), owner = t.withIdentity({ subject: "user_owner" });
  const userId = await owner.mutation(api.users.ensureCurrentUser, {});
  return { t, owner, userId };
}
async function drain(t: ReturnType<typeof convexTest>) {
  await t.finishAllScheduledFunctions(() => vi.runAllTimers());
}
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(now);
  vi.stubEnv("REVENUECAT_ENVIRONMENT", "PRODUCTION");
  vi.stubEnv("REVENUECAT_APP_IDS", "app_fixture");
  vi.stubEnv("REVENUECAT_PLAY_PRODUCTS", play);
  vi.stubEnv("REVENUECAT_REST_API_KEY", "fixture-read-key");
  vi.stubEnv("REVENUECAT_WEBHOOK_SECRET", "fixture-webhook");
  provider.mockReset().mockImplementation(async () => Response.json(snapshot()));
  vi.stubGlobal("fetch", provider);
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); });

describe("Q2 authoritative access", () => {
  test.each([
    ["paid", subscription(), true, "paid"],
    ["cancelled", subscription({ unsubscribe_detected_at: new Date(now).toISOString() }), true, "cancelled"],
    ["grace", subscription({ expires_date: new Date(now - 1).toISOString(), grace_period_expires_date: new Date(now + 1000).toISOString(), billing_issues_detected_at: new Date(now).toISOString() }), true, "grace"],
    ["account hold", subscription({ expires_date: new Date(now).toISOString(), billing_issues_detected_at: new Date(now).toISOString() }), false, undefined],
    ["expired", subscription({ expires_date: new Date(now).toISOString() }), false, undefined],
    ["refund/revocation", subscription({ refunded_at: new Date(now).toISOString() }), false, undefined],
    ["family", subscription({ ownership_type: "FAMILY_SHARED" }), false, undefined],
    ["sandbox", subscription({ is_sandbox: true }), false, undefined],
    ["missing expiry", subscription({ expires_date: null }), false, undefined],
  ])("%s", (_name, row, active, phase) => {
    const result = parseRevenueCatSnapshot(snapshot({ [monthly]: row }), "user_owner", revenueCatPolicy());
    const access = subscriptionAccess({ subscriptionTier: "free", subscriptionPurchases: result.purchases }, now);
    expect(access !== null).toBe(active);
    expect(access?.phase).toBe(phase);
  });
  test("one active Play purchase survives an Apple expiry, with one shared allowance", async () => {
    const f = await fixture();
    provider.mockResolvedValueOnce(Response.json(snapshot({ [monthly]: subscription({ expires_date: new Date(now - 1).toISOString() }), [play]: subscription({ store: "play_store" }) })));
    expect(await f.owner.action(api.actions.subscriptions.refresh, {})).toBe(true);
    expect(await f.owner.query(api.subscriptions.getStatus, {})).toMatchObject({ subscriptionTier: "pro", store: "play_store" });
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 100 });
    vi.setSystemTime(now + 1000);
    expect(await f.owner.query(api.subscriptions.getStatus, {})).toMatchObject({ subscriptionTier: "free" });
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 5 });
  });
  test("exact pro/catalog only; product substring, weekly and another account cannot grant", () => {
    const body = snapshot({ "accidental_pro_weekly": subscription() });
    expect(parseRevenueCatSnapshot(body, "user_owner", revenueCatPolicy()).purchases).toEqual([]);
    const noPro = { ...snapshot(), subscriber: { ...snapshot().subscriber, entitlements: { another_pro: { product_identifier: monthly } } } };
    expect(parseRevenueCatSnapshot(noPro, "user_owner", revenueCatPolicy()).purchases).toEqual([]);
    expect(parseRevenueCatSnapshot(snapshot(undefined, "user_other"), "user_owner", revenueCatPolicy())).toMatchObject({ ownershipConflict: true, purchases: [] });
    expect(subscriptionAccess({ subscriptionTier: "pro" }, now)).toBeNull();
  });
  test("modern Play REST product keys are joined to their exact base plan, never a weekly plan", () => {
    const body = snapshot({ hadithly_pro_annual: subscription({ store: "play_store", product_plan_identifier: "annual" }) });
    body.subscriber.entitlements.pro.product_identifier = "hadithly_pro_annual";
    expect(parseRevenueCatSnapshot(body, "user_owner", revenueCatPolicy()).purchases).toMatchObject([{ productId: play }]);
    const weekly = snapshot({ hadithly_pro_annual: subscription({ store: "play_store", product_plan_identifier: "weekly" }) });
    weekly.subscriber.entitlements.pro.product_identifier = "hadithly_pro_annual";
    expect(parseRevenueCatSnapshot(weekly, "user_owner", revenueCatPolicy()).purchases).toEqual([]);
  });
  test("sandbox cannot be configured on production; distinct store IDs are required", () => {
    vi.stubEnv("REVENUECAT_ENVIRONMENT", "SANDBOX"); vi.stubEnv("CONVEX_CLOUD_URL", "https://giddy-ox-648.eu-west-1.convex.cloud");
    expect(revenueCatPolicy).toThrow("SUBSCRIPTIONS_NOT_CONFIGURED");
    vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud"); expect(revenueCatPolicy().environment).toBe("SANDBOX");
    vi.stubEnv("REVENUECAT_PLAY_PRODUCTS", monthly); expect(revenueCatPolicy).toThrow();
  });
  test("older concurrent snapshot cannot overwrite the latest refresh, or recreate deletion", async () => {
    const f = await fixture();
    const first = await f.t.mutation(internal.subscriptions.beginRefresh, { clerkId: "user_owner", deny: false, ownershipConflict: false });
    const second = await f.t.mutation(internal.subscriptions.beginRefresh, { clerkId: "user_owner", deny: false, ownershipConflict: false });
    if (!first || !second) throw new Error("Missing fixture");
    const data = parseRevenueCatSnapshot(snapshot(), "user_owner", revenueCatPolicy());
    expect(await f.t.mutation(internal.subscriptions.applySnapshot, { ...first, ...data })).toBe(false);
    expect(await f.t.mutation(internal.subscriptions.applySnapshot, { ...second, ...data })).toMatchObject({ pro: true });
    await f.owner.mutation(api.users.deleteCurrentUser, {});
    expect(await f.t.mutation(internal.subscriptions.applySnapshot, { ...second, ...data })).toBe(false);
    provider.mockClear(); expect(await f.owner.action(api.actions.subscriptions.refresh, {})).toBe(false);
    expect(provider).not.toHaveBeenCalled();
  });
});

describe("Q2 HTTP to reconciliation to quota", () => {
  async function post(t: ReturnType<typeof convexTest>, body: unknown, authorization = "fixture-webhook") {
    return t.fetch("/webhooks/revenuecat", { method: "POST", headers: { Authorization: authorization, "Content-Type": "application/json" }, body: JSON.stringify(body) });
  }
  test("purchase, cancellation, grace, expiry/refund, renewal and replay use real webhook/action/mutation/query boundaries", async () => {
    const f = await fixture();
    expect((await post(f.t, event(), "wrong")).status).toBe(401);
    expect((await post(f.t, event("TEST"))).status).toBe(200);
    expect((await post(f.t, event("INITIAL_PURCHASE", "sandbox", { environment: "SANDBOX" }))).status).toBe(200);
    expect((await post(f.t, event("INITIAL_PURCHASE", "wrong-app", { app_id: "other" }))).status).toBe(400);
    expect(provider).not.toHaveBeenCalled();
    for (const [index, type, row, limit] of [
      [0, "INITIAL_PURCHASE", subscription(), 100],
      [1, "CANCELLATION", subscription({ unsubscribe_detected_at: new Date(now).toISOString() }), 100],
      [2, "BILLING_ISSUE", subscription({ expires_date: new Date(now - 1).toISOString(), grace_period_expires_date: new Date(now + 1000).toISOString(), billing_issues_detected_at: new Date(now).toISOString() }), 100],
      [3, "EXPIRATION", subscription({ expires_date: new Date(now).toISOString() }), 5],
      [4, "RENEWAL", subscription(), 100],
      [5, "CANCELLATION", subscription({ refunded_at: new Date(now).toISOString() }), 5],
    ] as const) {
      provider.mockResolvedValueOnce(Response.json(snapshot({ [monthly]: row })));
      const body = event(type, `event-${index}`);
      expect((await post(f.t, body)).status).toBe(200);
      await drain(f.t);
      expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit });
      const calls = provider.mock.calls.length;
      expect((await post(f.t, body)).status).toBe(200); await drain(f.t);
      expect(provider.mock.calls.length).toBe(calls);
    }
    expect(await f.t.run(ctx => ctx.db.query("subscriptionWebhookReceipts").collect())).toHaveLength(6);
  });
  test("an old critical event reconciles current access; transient failure retries; ordinary outage preserves finite paid time", async () => {
    const f = await fixture();
    provider.mockImplementation(async () => Response.json(snapshot({ [monthly]: subscription({ expires_date: new Date(now + 3600000).toISOString() }) })));
    expect(await f.owner.action(api.actions.subscriptions.refresh, {})).toBe(true);
    provider.mockRejectedValueOnce(new Error("fixture outage"));
    expect((await post(f.t, event("EXPIRATION", "old-event"))).status).toBe(200);
    await drain(f.t);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 100 });
    provider.mockRejectedValue(new Error("fixture outage"));
    expect((await post(f.t, event("BILLING_ISSUE", "outage"))).status).toBe(200);
    // Advance through all bounded retries; the finite grant eventually expires with the clock.
    await drain(f.t);
    expect(await f.t.run(ctx => ctx.db.get(f.userId))).toMatchObject({ subscriptionTier: "pro" });
    expect(await f.t.query(internal.subscriptions.deliveryCompleted, { eventId: "outage" })).toBe(false);
    provider.mockImplementation(async () => Response.json({ ...snapshot(), request_date_ms: Date.now(), subscriber: { ...snapshot().subscriber, subscriptions: { [monthly]: subscription({ expires_date: new Date(Date.now() + 1000).toISOString() }) } } }));
    expect((await post(f.t, event("BILLING_ISSUE", "outage"))).status).toBe(200); await drain(f.t);
    expect(await f.t.query(internal.subscriptions.deliveryCompleted, { eventId: "outage" })).toBe(true);
  });
  test("a prohibited transfer suspends destination ownership; no arbitrary alias fanout", async () => {
    const f = await fixture();
    expect(parseRevenueCatEvent(event("TRANSFER", "transfer", { transferred_from: ["user_original"], transferred_to: ["user_owner"] }), revenueCatPolicy()).kind).toBe("valid");
    expect((await post(f.t, event("TRANSFER", "transfer", { transferred_from: ["user_original"], transferred_to: ["user_owner"] }))).status).toBe(200);
    await drain(f.t);
    expect(await f.owner.query(api.subscriptions.getStatus, {})).toMatchObject({ subscriptionTier: "free", phase: "account_conflict" });
    expect(await f.owner.action(api.actions.subscriptions.refresh, {})).toBe(false);
  });
  test("hourly recovery resumes a fully failed delivery and deletion removes retry bindings", async () => {
    const f = await fixture();
    provider.mockRejectedValue(new Error("long outage"));
    await post(f.t, event("RENEWAL", "durable")); await drain(f.t);
    expect(provider).toHaveBeenCalledTimes(4);
    expect(await f.t.run(ctx => ctx.db.query("subscriptionWebhookTargets").collect())).toHaveLength(1);
    provider.mockImplementation(async () => Response.json({ ...snapshot({ [monthly]: subscription({ expires_date: new Date(Date.now() + 3600000).toISOString() }) }), request_date_ms: Date.now() }));
    vi.advanceTimersByTime(3600000);
    await f.t.mutation(internal.subscriptions.recoverDeliveries, {}); await drain(f.t);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 100 });
    expect(await f.t.run(ctx => ctx.db.query("subscriptionWebhookTargets").collect())).toHaveLength(0);
    provider.mockRejectedValue(new Error("long outage"));
    await post(f.t, event("RENEWAL", "deleted")); await drain(f.t);
    await f.owner.mutation(api.users.deleteCurrentUser, {});
    expect(await f.t.run(ctx => ctx.db.query("subscriptionWebhookTargets").collect())).toHaveLength(0);
    provider.mockClear(); await f.t.mutation(internal.subscriptions.recoverDeliveries, {}); await drain(f.t);
    expect(provider).not.toHaveBeenCalled();
  });
  test("hourly recovery repairs queued work whose original worker vanished", async () => {
    const f = await fixture();
    await f.t.run(async ctx => {
      const receiptId = await ctx.db.insert("subscriptionWebhookReceipts", { eventId: "lost-worker", state: "queued", createdAt: now - 7200000, queuedAt: now - 3600001 });
      await ctx.db.insert("subscriptionWebhookTargets", { receiptId, userId: f.userId, deny: false, ownershipConflict: false });
    });
    await f.t.mutation(internal.subscriptions.recoverDeliveries, {}); await drain(f.t);
    expect(await f.t.query(internal.subscriptions.deliveryCompleted, { eventId: "lost-worker" })).toBe(true);
    expect(await f.owner.query(api.quotas.getTranslationAllowance, {})).toMatchObject({ limit: 100 });
    expect(provider).toHaveBeenCalledTimes(1);
  });
  test("public refresh derives identity and is bounded", async () => {
    const f = await fixture();
    await expect(f.t.action(api.actions.subscriptions.refresh, {})).rejects.toThrow("Unauthenticated");
    for (let i = 0; i < 5; i++) await f.owner.action(api.actions.subscriptions.refresh, {});
    await expect(f.owner.action(api.actions.subscriptions.refresh, {})).rejects.toThrow("SUBSCRIPTION_RATE_LIMITED");
    expect(provider).toHaveBeenCalledTimes(5);
  });
  test("90-day retention drains batches and erases retry bindings without removing recent receipts", async () => {
    const f = await fixture();
    const cutoff = now - 90 * 86400000;
    await f.t.run(async ctx => {
      for (let i = 0; i < 101; i++) {
        const receiptId = await ctx.db.insert("subscriptionWebhookReceipts", { eventId: `expired-${i}`, state: "failed", createdAt: cutoff - 1 });
        await ctx.db.insert("subscriptionWebhookTargets", { receiptId, userId: f.userId, deny: false, ownershipConflict: false });
      }
      await ctx.db.insert("subscriptionWebhookReceipts", { eventId: "retained-boundary", state: "completed", createdAt: cutoff });
      await ctx.db.insert("subscriptionWebhookReceipts", { eventId: "recent", state: "completed", createdAt: now });
    });
    await f.t.mutation(internal.subscriptions.pruneReceipts, {}); await drain(f.t);
    expect(await f.t.run(ctx => ctx.db.query("subscriptionWebhookTargets").collect())).toHaveLength(0);
    expect((await f.t.run(ctx => ctx.db.query("subscriptionWebhookReceipts").collect())).map(row => row.eventId).sort()).toEqual(["recent", "retained-boundary"]);
    expect(provider).not.toHaveBeenCalled();
    expect(await f.owner.query(api.users.getCurrentUser, {})).not.toBeNull();
  });
});
