/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, beforeEach, expect, test, vi } from "vitest";
import { createHmac } from "node:crypto";
import schema from "./schema";
import { api, internal } from "./_generated/api";
import { DAY, parseSupport, verifyMailSignature } from "./lib/supportPolicy";
import { fixture } from "../test/evidenceFixtures";
import { textDigest } from "./lib/evidenceReviewPolicy";

const modules = import.meta.glob("./**/*.ts");
const input = (n = 1) => ({ requestId: `aaaaaaaa-aaaa-4aaa-8aaa-${n.toString().padStart(12, "0")}`, email: `synthetic${n}@example.invalid`,
  message: "Synthetic support request. No real user data.", topic: "reading" as const, platform: "ios" as const, token: "synthetic-token", website: "" });
const fields = (n = 1) => { const { token, website, ...rest } = input(n); return { ...rest, emailHash: `synthetic-hash-${n}` }; };
beforeEach(() => {
  vi.useFakeTimers(); vi.setSystemTime(Date.parse("2026-10-14T06:00:00Z"));
  vi.stubEnv("SUPPORT_ENABLED", "1"); vi.stubEnv("OPERATIONS_MAIL_ENABLED", "1");
  vi.stubEnv("OPERATIONS_EMAIL", "operator@example.invalid"); vi.stubEnv("RESEND_API_KEY", "synthetic-api-key");
  vi.stubEnv("SUPPORT_TURNSTILE_SECRET", "synthetic-turnstile"); vi.stubEnv("SUPPORT_RATE_SECRET", "synthetic-rate-secret-longer-than-32-characters");
});
afterEach(() => { vi.useRealTimers(); vi.unstubAllEnvs(); vi.unstubAllGlobals(); });
test("closed form contract rejects extra fields, headers, spam, oversize and control characters", async () => {
  expect(parseSupport(input())).not.toBeNull();
  for (const key of ["userId", "to", "from", "subject", "attachments", "html", "url"]) expect(parseSupport({ ...input(), [key]: "canary" })).toBeNull();
  for (const patch of [{ email: "a@example.com\r\nBcc: victim@example.com" }, { website: "spam" }, { message: "x".repeat(2001) }, { token: "" }, { message: "canary\u0000canary" }, { platform: "other" }]) expect(parseSupport({ ...input(), ...patch })).toBeNull();
  const t = convexTest(schema, modules);
  const headers = { "Content-Type": "application/json", Origin: "https://hadithly.app" };
  expect((await t.fetch("/support/request", { method: "POST", headers: { ...headers, Origin: "https://evil.example" }, body: JSON.stringify(input()) })).status).toBe(403);
  expect((await t.fetch("/support/request", { method: "POST", headers, body: "x".repeat(12289) })).status).toBe(413);
  expect((await t.fetch("/support/request", { method: "POST", headers: { ...headers, Cookie: "private" }, body: JSON.stringify(input()) })).status).toBe(403);
  expect(await t.run(ctx => ctx.db.query("supportRequests").collect())).toHaveLength(0);
});
test("actual HTTP performs server challenge validation and accepts without exporting contact or message", async () => {
  const t = convexTest(schema, modules); const outbound: string[] = [];
  vi.stubGlobal("fetch", async (url: string, init: RequestInit) => {
    outbound.push(String(init.body));
    if (url.includes("siteverify")) return Response.json({ success: true, hostname: "hadithly.app", action: "support" });
    return Response.json({ id: "provider-message" });
  });
  const response = await t.fetch("/support/request", { method: "POST", headers: { Origin: "https://hadithly.app", "Content-Type": "application/json" }, body: JSON.stringify(input()) });
  expect(response.status).toBe(202);
  await t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(outbound).toHaveLength(2);
  expect(outbound.join("\n")).not.toContain(input().email);
  expect(outbound.join("\n")).not.toContain(input().message);
  expect(JSON.parse(outbound[1])).toMatchObject({ to: ["operator@example.invalid"], subject: "Hadithly operational notice" });
  const stored = await t.run(ctx => ctx.db.query("supportRequests").unique());
  expect(stored?.message).toBe(input().message); expect(JSON.stringify(stored)).not.toContain("synthetic-token");
  expect(await t.run(ctx => ctx.db.query("operationsMail").unique())).toMatchObject({ state: "sent", providerId: "provider-message" });
});
test("challenge hostname, action, provider outage, and kill switch fail closed", async () => {
  const t = convexTest(schema, modules), headers = { Origin: "https://hadithly.app", "Content-Type": "application/json" };
  for (const challenge of [{ success: false }, { success: true, hostname: "evil.example", action: "support" }, { success: true, hostname: "hadithly.app", action: "other" }]) {
    vi.stubGlobal("fetch", async () => Response.json(challenge));
    expect((await t.fetch("/support/request", { method: "POST", headers, body: JSON.stringify(input()) })).status).toBe(403);
  }
  vi.stubGlobal("fetch", async () => { throw new Error("network canary"); });
  expect((await t.fetch("/support/request", { method: "POST", headers, body: JSON.stringify(input()) })).status).toBe(403);
  vi.stubEnv("SUPPORT_ENABLED", "0");
  expect((await t.fetch("/support/request", { method: "POST", headers, body: JSON.stringify(input()) })).status).toBe(503);
  expect(await t.run(ctx => ctx.db.query("supportRequests").collect())).toHaveLength(0);
});
test("atomic support admission enforces duplicate, per-address, daily and monthly limits", async () => {
  const t = convexTest(schema, modules);
  expect(await t.mutation(internal.support.accept, fields())).toBe("accepted");
  expect(await t.mutation(internal.support.accept, fields())).toBe("duplicate");
  const attempts = await Promise.all(Array.from({ length: 7 }, (_, i) => t.mutation(internal.support.accept, { ...fields(i + 2), emailHash: fields().emailHash })));
  expect(attempts.filter(value => value === "accepted")).toHaveLength(2);
  await t.run(async ctx => { const row = await ctx.db.query("operationsState").unique(); if (row) await ctx.db.patch(row._id, { supportMonthly: 199 }); });
  const race = await Promise.all([20, 21, 22].map(n => t.mutation(internal.support.accept, fields(n))));
  expect(race.filter(value => value === "accepted")).toHaveLength(1);
  vi.setSystemTime(Date.parse("2026-11-01T01:00:00Z"));
  expect(await t.mutation(internal.support.accept, fields(30))).toBe("accepted");
  await t.run(async ctx => { const row = await ctx.db.query("operationsState").unique(); if (row) await ctx.db.patch(row._id, { supportDaily: 20 }); });
  expect(await t.mutation(internal.support.accept, fields(31))).toBe("limited");
});
test("ingress limits challenge calls before verification and resets each minute", async () => {
  const t = convexTest(schema, modules);
  const attempts = await Promise.all(Array.from({ length: 20 }, () => t.mutation(internal.support.ingress, {})));
  expect(attempts.filter(Boolean)).toHaveLength(10);
  vi.advanceTimersByTime(60_001); expect(await t.mutation(internal.support.ingress, {})).toBe(true);
});
test("operator inbox denies guests and non-operators, expires exact deadline, retention drains bursts", async () => {
  const t = convexTest(schema, modules); await t.mutation(internal.support.accept, fields());
  const options = { paginationOpts: { cursor: null, numItems: 50 } };
  await expect(t.query(api.support.inbox, options)).rejects.toThrow();
  const clerkId = "synthetic-operator";
  const userId = await t.run(ctx => ctx.db.insert("users", { clerkId, subscriptionTier: "free", preferredLanguage: "en", createdAt: 1, updatedAt: 1 }));
  const operator = t.withIdentity({ subject: clerkId });
  await expect(operator.query(api.support.inbox, options)).rejects.toThrow("Operator");
  await t.run(ctx => ctx.db.patch(userId, { isAdmin: true }));
  expect((await operator.query(api.support.inbox, options)).page).toHaveLength(1);
  await t.run(async ctx => {
    for (let i = 2; i <= 60; i++) { const { emailHash, ...request } = fields(i); await ctx.db.insert("supportRequests", { ...request, expiresAt: Date.now() + 30 * DAY }); }
  });
  const first = await operator.query(api.support.inbox, options);
  const second = await operator.query(api.support.inbox, { paginationOpts: { cursor: first.continueCursor, numItems: 50 } });
  expect(first.page).toHaveLength(50); expect(second.page).toHaveLength(10); expect(second.isDone).toBe(true);
  expect(new Set([...first.page, ...second.page].map(row => row.requestId)).size).toBe(60);
  vi.advanceTimersByTime(30 * DAY);
  expect((await operator.query(api.support.inbox, options)).page).toHaveLength(0);
  await t.mutation(internal.support.retain, {});
  expect(await t.run(ctx => ctx.db.query("supportRequests").collect())).toHaveLength(0);
  expect(await t.run(ctx => ctx.db.query("supportRates").collect())).toHaveLength(0);
});
test("mail concurrency, monthly cap, and ambiguous timeout never duplicate provider calls", async () => {
  const t = convexTest(schema, modules); await t.mutation(internal.support.testNotice, {});
  const mail = await t.run(ctx => ctx.db.query("operationsMail").unique()); if (!mail) throw new Error("mail fixture missing");
  const claims = await Promise.all(Array.from({ length: 10 }, () => t.mutation(internal.support.claimMail, { mailId: mail._id })));
  expect(claims.filter(Boolean)).toHaveLength(1);
  expect(await t.mutation(internal.support.claimMail, { mailId: mail._id })).toBeNull();
  await t.run(async ctx => { await ctx.db.patch(mail._id, { state: "queued" }); const state = await ctx.db.query("operationsState").unique(); if (state) await ctx.db.patch(state._id, { mailMonthly: 500 }); });
  expect(await t.mutation(internal.support.claimMail, { mailId: mail._id })).toBeNull();
  await t.run(async ctx => { const state = await ctx.db.query("operationsState").unique(); if (state) await ctx.db.patch(state._id, { mailMonthly: 0 }); });
  const fetchMock = vi.fn(async () => { throw new Error("timeout"); }); vi.stubGlobal("fetch", fetchMock);
  await t.action(internal.actions.support.sendNotice, { mailId: mail._id });
  await t.action(internal.actions.support.sendNotice, { mailId: mail._id });
  expect(fetchMock).toHaveBeenCalledTimes(1);
});
test("webhook authenticates raw bytes and timestamp; bounce suppresses all mail despite late delivery", async () => {
  const t = convexTest(schema, modules); await t.mutation(internal.support.testNotice, {});
  const mail = await t.run(ctx => ctx.db.query("operationsMail").unique()); if (!mail) throw new Error("mail fixture missing");
  await t.mutation(internal.support.claimMail, { mailId: mail._id });
  await t.mutation(internal.support.finishMail, { mailId: mail._id, providerId: "synthetic-provider" });
  const key = "synthetic-secret", secret = `whsec_${Buffer.from(key).toString("base64")}`; vi.stubEnv("RESEND_WEBHOOK_SECRET", secret);
  const timestamp = String(Math.floor(Date.now() / 1000)), body = JSON.stringify({ type: "email.bounced", data: { email_id: "synthetic-provider", to: ["private-canary"] } });
  const signature = createHmac("sha256", key).update(`synthetic-event.${timestamp}.${body}`).digest("base64");
  const headers = new Headers({ "svix-id": "synthetic-event", "svix-timestamp": timestamp, "svix-signature": `v1,${signature}` });
  expect(await verifyMailSignature(body, headers, secret, Date.now())).toBe(true);
  expect(await verifyMailSignature(body + " ", headers, secret, Date.now())).toBe(false);
  expect(await verifyMailSignature(body, headers, secret, Date.now() + 301_000)).toBe(false);
  expect((await t.fetch("/webhooks/operations-mail", { method: "POST", headers, body })).status).toBe(204);
  await t.mutation(internal.support.mailEvent, { providerId: "synthetic-provider", outcome: "delivered" });
  expect(await t.query(internal.support.health, {})).toMatchObject({ suppressed: true });
  expect((await t.run(ctx => ctx.db.get(mail._id)))?.state).toBe("bounced");
  expect(JSON.stringify(await t.run(ctx => ctx.db.query("operationsState").collect()))).not.toContain("private-canary");
});
test("monthly AI and evidence warnings deduplicate; review cap cannot leak extra paid requests", async () => {
  const t = convexTest(schema, modules), month = "2026-10";
  await t.run(async ctx => { await ctx.db.insert("aiSpendBudgets", { monthKey: String(Date.UTC(2026, 9, 1)), committedMicroUsd: 8_000_000 }); await ctx.db.insert("reviewMonthlyBudgets", { month, attempts: 80 }); });
  await t.mutation(internal.support.budgetWarnings, {}); await t.mutation(internal.support.budgetWarnings, {});
  expect(await t.run(ctx => ctx.db.query("operationsMail").collect())).toHaveLength(2);
  const f = await fixture();
  await f.t.run(ctx => ctx.db.insert("reviewMonthlyBudgets", { month, attempts: 100 }));
  expect(await f.t.mutation(internal.evidenceReview.claim, { submissionId: f.draft.submissionId, reviewEnabled: true })).toBeNull();
  expect(await f.t.run(ctx => ctx.db.query("evidenceReviewGlobalSpendEvents").collect())).toHaveLength(0);
});
test("real quota reservations cross the AI warning boundary with canonical key and default config", async () => {
  vi.stubEnv("AI_MONTHLY_BUDGET_USD", "NaN");
  const t = convexTest(schema, modules), monthKey = String(Date.UTC(2026, 9, 1));
  const hadithId = await t.run(async ctx => {
    const licenseRecordId = await ctx.db.insert("licenseRecords", { sourceKey: "synthetic", sourceName: "Synthetic", sourceUrl: "https://example.invalid/",
      terms: { kind: "verified", licenseName: "Synthetic", licenseUrl: "https://example.invalid/license", permitsDisplay: true, permitsRedistribution: false, permitsOfflineDistribution: false, verifiedAt: 1 }, createdAt: 1, updatedAt: 1 });
    await ctx.db.insert("aiSpendBudgets", { monthKey, committedMicroUsd: 7_980_000, freeCommittedMicroUsd: 0 });
    return ctx.db.insert("hadiths", { provider: "local_dump", providerHadithId: "1", collectionSlug: "synthetic", arabicText: "Synthetic", referenceDisplay: "Synthetic 1", collectionName: "Synthetic", licenseRecordId, createdAt: 1 });
  });
  await t.mutation(internal.support.budgetWarnings, {});
  expect(await t.run(ctx => ctx.db.query("operationsMail").collect())).toHaveLength(0);
  expect((await t.mutation(internal.quotas.admit, { hadithId, language: "ru", signal: "service" })).kind).toBe("claimed");
  await t.mutation(internal.support.budgetWarnings, {});
  expect(await t.run(ctx => ctx.db.query("operationsMail").unique())).toMatchObject({ kind: "ai_budget", reference: "2026-10" });
});
test("early-month budget warning remains deduplicated on day31 after retention", async () => {
  vi.setSystemTime(Date.parse("2026-10-01T00:00:00Z")); const t = convexTest(schema, modules);
  await t.run(ctx => ctx.db.insert("reviewMonthlyBudgets", { month: "2026-10", attempts: 80 }));
  await t.mutation(internal.support.budgetWarnings, {});
  vi.setSystemTime(Date.parse("2026-10-31T01:00:00Z"));
  await t.mutation(internal.support.retain, {}); await t.mutation(internal.support.budgetWarnings, {});
  expect(await t.run(ctx => ctx.db.query("operationsMail").collect())).toHaveLength(1);
});
test("multibyte over-limit review leaves the ready queue before paid admission", async () => {
  const f = await fixture(), arabicText = "ن".repeat(70_000), digest = await textDigest(arabicText);
  await f.t.run(ctx => ctx.db.patch(f.hadithId, { arabicText }));
  await f.t.mutation(internal.evidenceReview.recordPermission, { grant: { ...f.grant, sourceKind: "sunnah_now", sourceUrl: "https://sunnah.now/", artifactSha256: digest, textSha256: digest, language: "ar" } });
  expect(await f.t.mutation(internal.evidenceReview.claim, { submissionId: f.draft.submissionId, reviewEnabled: true })).toBeNull();
  expect((await f.t.run(ctx => ctx.db.get(f.draft.submissionId)))?.status).toBe("held");
  expect(await f.t.run(ctx => ctx.db.query("reviewMonthlyBudgets").collect())).toHaveLength(0);
  expect(await f.t.run(ctx => ctx.db.query("evidenceReviewGlobalSpendEvents").collect())).toHaveLength(0);
});
