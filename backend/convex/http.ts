import { httpAction } from "./_generated/server";
import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import {
  authorizeRevenueCatWebhook,
  parseRevenueCatEvent,
  revenueCatPolicy,
} from "./lib/revenueCat";
import { requireIdentity } from "./lib/identity";
import { verifyEvidenceFile } from "./lib/evidenceFiles";
import { MAX_EVIDENCE_BYTES } from "./lib/evidencePolicy";
import { parseWebFailure, diagnosticsEnvironment } from "./lib/diagnosticsPolicy";
import { parseSummary } from "./lib/analyticsPolicy";
import { boundedText, parseSupport, record, verifyMailSignature } from "./lib/supportPolicy";

/**
 * RevenueCat webhook. app_user_id is the Clerk user id (the app configures
 * RevenueCat with the Clerk id). Entitlement changes sync straight into the
 * users table, which drives AI quota limits.
 */
const revenueCatWebhook = httpAction(async (ctx, request) => {
  const authorization = authorizeRevenueCatWebhook({
    expected: process.env.REVENUECAT_WEBHOOK_SECRET,
    provided: request.headers.get("authorization"),
  });
  if (authorization.kind === "misconfigured") {
    return new Response(
      JSON.stringify({ error: "RevenueCat webhook is not configured" }),
      {
        status: 503,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  if (authorization.kind === "unauthorized") {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  let policy;
  try { policy = revenueCatPolicy(); } catch { return Response.json({ error: "Subscriptions not configured" }, { status: 503 }); }
  if (!policy.appIds.length) return Response.json({ error: "Subscriptions not configured" }, { status: 503 });
  const parsed = parseRevenueCatEvent(await request.json().catch(() => null), policy);
  if (parsed.kind === "invalid") return Response.json({ error: "Invalid RevenueCat event" }, { status: 400 });
  if (parsed.kind === "ignored") return Response.json({ ok: true });
  await ctx.runMutation(internal.subscriptions.enqueueDelivery, { eventId: parsed.delivery.id,
    accountIds: parsed.delivery.accountIds, deny: parsed.delivery.deny, transferDestinations: parsed.delivery.transferDestinations });

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

export const http = httpRouter();

const supportCors = { "Access-Control-Allow-Origin": "https://hadithly.app", "Vary": "Origin", "Cache-Control": "no-store" };
http.route({ path: "/support/request", method: "OPTIONS", handler: httpAction(async () => new Response(null,
  { status: 204, headers: { ...supportCors, "Access-Control-Allow-Methods": "POST", "Access-Control-Allow-Headers": "Content-Type" } })) });
http.route({ path: "/support/request", method: "POST", handler: httpAction(async (ctx, request) => {
  const reply = (status: number) => new Response(null, { status, headers: supportCors });
  if (request.headers.get("origin") !== "https://hadithly.app" || request.headers.has("authorization") || request.headers.has("cookie")) return reply(403);
  if (process.env.SUPPORT_ENABLED !== "1" || process.env.OPERATIONS_MAIL_ENABLED !== "1" || !process.env.RESEND_API_KEY
    || !process.env.OPERATIONS_EMAIL || !process.env.SUPPORT_TURNSTILE_SECRET || !process.env.SUPPORT_RATE_SECRET) return reply(503);
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json") return reply(400);
  const text = await boundedText(request, 12_288); if (text === null) return reply(413);
  let raw: unknown; try { raw = JSON.parse(text); } catch { return reply(400); }
  const parsed = parseSupport(raw); if (!parsed) return reply(400);
  if (!await ctx.runMutation(internal.support.ingress, {})) return reply(429);
  const emailHash = await ctx.runAction(internal.actions.support.verifyChallenge, { token: parsed.token, email: parsed.email });
  if (!emailHash) return reply(403);
  const { token, website, ...fields } = parsed;
  const result = await ctx.runMutation(internal.support.accept, { ...fields, emailHash });
  return reply(result === "accepted" || result === "duplicate" ? 202 : result === "limited" ? 429 : 503);
}) });
http.route({ path: "/webhooks/operations-mail", method: "POST", handler: httpAction(async (ctx, request) => {
  const secret = process.env.RESEND_WEBHOOK_SECRET; if (!secret) return new Response(null, { status: 503 });
  const text = await boundedText(request, 20_000); if (text === null) return new Response(null, { status: 413 });
  if (!await verifyMailSignature(text, request.headers, secret, Date.now())) return new Response(null, { status: 401 });
  let raw: unknown; try { raw = JSON.parse(text); } catch { return new Response(null, { status: 400 }); }
  if (!record(raw) || typeof raw.type !== "string") return new Response(null, { status: 400 });
  if (raw.type !== "email.delivered" && raw.type !== "email.bounced" && raw.type !== "email.complained") return new Response(null, { status: 204 });
  if (!record(raw.data) || typeof raw.data.from !== "string") return new Response(null, { status: 400 });
  // The one free webhook is team-wide. Other domains must not enter retry loops.
  if (raw.data.from !== "Hadithly operations <operations@updates.hadithly.app>"
    && raw.data.from !== "operations@updates.hadithly.app") return new Response(null, { status: 204 });
  if (typeof raw.data.email_id !== "string" || !/^[a-zA-Z0-9-]{1,100}$/.test(raw.data.email_id)) return new Response(null, { status: 400 });
  const outcome = raw.type === "email.delivered" ? "delivered" : raw.type === "email.bounced" ? "bounced" : "complained";
  const found = await ctx.runMutation(internal.support.mailEvent, { providerId: raw.data.email_id, outcome });
  return new Response(null, { status: found ? 204 : 503 });
}) });

http.route({ path: "/analytics/summary", method: "POST", handler: httpAction(async (ctx, request) => {
  if (process.env.ANALYTICS_ENABLED !== "1") return new Response(null, { status: 503 });
  const reject = async (status: number) => { await ctx.runMutation(internal.analytics.recordRejection, {}); return new Response(null, { status }); };
  if (request.headers.has("authorization") || request.headers.has("cookie") || request.headers.has("origin"))
    return reject(403);
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json" || !request.body)
    return reject(400);
  const reader = request.body.getReader(), chunks: Uint8Array[] = []; let size = 0;
  for (;;) {
    const { done, value } = await reader.read(); if (done) break;
    size += value.byteLength;
    if (size > 4096) { await reader.cancel(); return reject(413); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.byteLength; }
  let raw: unknown; try { raw = JSON.parse(new TextDecoder().decode(bytes)); } catch { return reject(400); }
  const summary = parseSummary(raw, Date.now());
  if (!summary) return reject(400);
  const result = await ctx.runMutation(internal.analytics.accept, summary);
  return new Response(null, { status: result === "accepted" || result === "duplicate" ? 204
    : result === "limited" ? 429 : result === "disabled" ? 503 : 400 });
}) });

for (const [path, component] of [["/health/public", "api"], ["/health/notifications", "notifications"], ["/health/alert-test", "alert_test"]] as const) {
  http.route({ path, method: "GET", handler: httpAction(async ctx => {
    try {
      const health = await ctx.runQuery(internal.diagnostics.health, { component });
      return Response.json(health, { status: health.status === "ready" ? 200 : 503,
        headers: { "Cache-Control": "no-store" } });
    } catch { return Response.json({ status: "degraded" }, { status: 503, headers: { "Cache-Control": "no-store" } }); }
  }) });
}

function diagnosticOrigin(): string {
  const configured = process.env.DIAGNOSTICS_WEB_ORIGIN ?? "https://hadithly.app";
  try {
    const url = new URL(configured);
    return url.protocol === "https:" && url.origin === configured ? configured : "https://hadithly.app";
  } catch { return "https://hadithly.app"; }
}
function diagnosticCors() { return { "Access-Control-Allow-Origin": diagnosticOrigin(), "Vary": "Origin" }; }
http.route({ path: "/diagnostics/web", method: "OPTIONS", handler: httpAction(async () => new Response(null,
  { status: 204, headers: { ...diagnosticCors(), "Access-Control-Allow-Methods": "POST", "Access-Control-Allow-Headers": "Content-Type" } })) });
http.route({ path: "/diagnostics/web", method: "POST", handler: httpAction(async (ctx, request) => {
  const cors = diagnosticCors();
  if (request.headers.get("origin") !== diagnosticOrigin()) return new Response(null, { status: 403 });
  if (request.headers.get("content-type")?.split(";")[0] !== "application/json" || !request.body)
    return new Response(null, { status: 400, headers: cors });
  const reader = request.body.getReader(), chunks: Uint8Array[] = [];
  let size = 0;
  while (true) {
    const item = await reader.read();
    if (item.done) break;
    size += item.value.length;
    if (size > 512) { await reader.cancel(); return new Response(null, { status: 413, headers: cors }); }
    chunks.push(item.value);
  }
  const bytes = new Uint8Array(size); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  let value: unknown;
  try { value = JSON.parse(new TextDecoder().decode(bytes)); } catch { value = null; }
  const parsed = parseWebFailure(value);
  if (!parsed || parsed.environment !== diagnosticsEnvironment()
    || (parsed.operation === "synthetic" && parsed.environment !== "development"))
    return new Response(null, { status: 400, headers: cors });
  try {
    await ctx.runMutation(internal.diagnostics.recordFailure, { surface: "web", operation: parsed.operation, webRelease: parsed.release });
  } catch { /* No recursive reporting and no product failure. */ }
  return new Response(null, { status: 204, headers: cors });
}) });

http.route({
  path: "/webhooks/revenuecat",
  method: "POST",
  handler: revenueCatWebhook,
});

/** Authenticated raw upload; evidence storage IDs and download URLs never leave Convex. */
http.route({
  path: "/evidence/upload",
  method: "POST",
  handler: httpAction(async (ctx, request) => {
    let clerkId: string;
    try { clerkId = (await requireIdentity(ctx)).clerkId; }
    catch { return new Response(JSON.stringify({ error: "Sign in is required" }), { status: 401 }); }
    const submissionId = request.headers.get("x-evidence-submission-id") ?? "";
    const itemId = request.headers.get("x-evidence-item-id") ?? "";
    try {
      const slot = await ctx.runQuery(internal.evidence.authorizeUpload, { clerkId, submissionId, itemId });
      if (slot.state === "quarantined_unscanned") return Response.json({ state: "quarantined_unscanned" });
      if (slot.state !== "reserved") throw new Error("Evidence slot must be retried from the draft");
      if (request.headers.get("content-type")?.split(";")[0] !== slot.declaredMime) throw new Error("Evidence content type does not match the selected file");
      const advertised = Number(request.headers.get("content-length"));
      if (Number.isFinite(advertised) && advertised > MAX_EVIDENCE_BYTES) throw new Error("Evidence file exceeds the 10 MB limit");
      if (!request.body) throw new Error("Evidence file is empty");
      const reader = request.body.getReader();
      const chunks: Uint8Array[] = [];
      let size = 0;
      while (true) {
        const next = await reader.read();
        if (next.done) break;
        size += next.value.length;
        if (size > MAX_EVIDENCE_BYTES) {
          await reader.cancel();
          throw new Error("Evidence file exceeds the 10 MB limit");
        }
        chunks.push(next.value);
      }
      if (size !== slot.declaredSize) throw new Error("Evidence file size changed; select it again");
      const bytes = new Uint8Array(size);
      let offset = 0;
      for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
      const verified = await verifyEvidenceFile(bytes, slot.declaredMime);
      if (verified.sha256 !== slot.declaredSha256) throw new Error("Evidence file changed after selection");
      const storageId = await ctx.storage.store(new Blob([bytes], { type: verified.mime }));
      let bound = false;
      try {
        await ctx.runMutation(internal.evidence.bindUpload, { clerkId, submissionId, itemId, storageId });
        bound = true;
        await ctx.runMutation(internal.evidence.completeUpload, { itemId, storageId, verifiedMime: verified.mime, sha256: verified.sha256, size: verified.size, width: verified.width, height: verified.height, pageCount: verified.pageCount });
      } catch (error) {
        if (bound) await ctx.runMutation(internal.evidence.failUpload, { itemId, storageId });
        else await ctx.storage.delete(storageId);
        throw error;
      }
      return Response.json({ state: "quarantined_unscanned", size: verified.size });
    } catch (error) {
      const message = error instanceof Error ? error.message : "Evidence upload failed";
      return Response.json({ error: message }, { status: 400 });
    }
  }),
});

export default http;
