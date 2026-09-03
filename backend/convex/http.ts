import { httpAction } from "./_generated/server";
import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";
import {
  authorizeRevenueCatWebhook,
  parseRevenueCatEvent,
} from "./lib/revenueCat";

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

  const body: unknown = await request.json().catch(() => null);
  const parsed = parseRevenueCatEvent({ body, now: Date.now() });
  if (parsed.kind === "invalid") {
    return new Response(JSON.stringify({ error: parsed.message }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  await ctx.runMutation(internal.users.syncRevenueCatEntitlement, {
    clerkId: parsed.event.appUserId,
    revenueCatAppUserId: parsed.event.appUserId,
    subscriptionTier: parsed.event.subscriptionTier,
    entitlementProductId: parsed.event.entitlementProductId,
    entitlementExpiresAt: parsed.event.entitlementExpiresAt,
  });

  return new Response(JSON.stringify({ ok: true }), {
    status: 200,
    headers: { "Content-Type": "application/json" },
  });
});

export const http = httpRouter();

http.route({
  path: "/webhooks/revenuecat",
  method: "POST",
  handler: revenueCatWebhook,
});

export default http;
