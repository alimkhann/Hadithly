import { httpAction } from "./_generated/server";
import { httpRouter } from "convex/server";
import { internal } from "./_generated/api";

/**
 * RevenueCat webhook. app_user_id is the Clerk user id (the app configures
 * RevenueCat with the Clerk id). Entitlement changes sync straight into the
 * users table, which drives AI quota limits.
 */
const revenueCatWebhook = httpAction(async (ctx, request) => {
  const expected = process.env.REVENUECAT_WEBHOOK_SECRET;
  if (!expected) {
    return new Response(
      JSON.stringify({ error: "RevenueCat webhook is not configured" }),
      {
        status: 503,
        headers: { "Content-Type": "application/json" },
      },
    );
  }
  const provided = request.headers.get("authorization");
  if (provided !== expected && provided !== `Bearer ${expected}`) {
    return new Response(JSON.stringify({ error: "Unauthorized" }), {
      status: 401,
      headers: { "Content-Type": "application/json" },
    });
  }

  const event = await request
    .json()
    .then((body) => body as Record<string, unknown> | null)
    .catch(() => null);
  if (!event) {
    return new Response(JSON.stringify({ error: "Invalid RevenueCat webhook" }), {
      status: 400,
      headers: { "Content-Type": "application/json" },
    });
  }

  const revenueCatEvent = (event.event ?? event) as Record<string, unknown>;
  const appUserId = revenueCatEvent.app_user_id;
  if (!appUserId || typeof appUserId !== "string") {
    return new Response(
      JSON.stringify({ error: "RevenueCat event missing app_user_id" }),
      {
        status: 400,
        headers: { "Content-Type": "application/json" },
      },
    );
  }

  const entitlementIds = Array.isArray(revenueCatEvent.entitlement_ids)
    ? (revenueCatEvent.entitlement_ids as unknown[])
    : [];
  const isProEvent =
    entitlementIds.includes("pro") ||
    revenueCatEvent.entitlement_id === "pro" ||
    (typeof revenueCatEvent.product_id === "string" &&
      revenueCatEvent.product_id.toLowerCase().includes("pro"));
  const eventType =
    typeof revenueCatEvent.type === "string" ? revenueCatEvent.type : "";
  const expirationAt =
    typeof revenueCatEvent.expiration_at_ms === "number"
      ? revenueCatEvent.expiration_at_ms
      : undefined;
  // Cancellation and billing-issue events can arrive while the paid period
  // is still active. RevenueCat emits EXPIRATION when access actually ends.
  const isRevocation =
    eventType === "EXPIRATION" ||
    ((eventType === "CANCELLATION" || eventType === "BILLING_ISSUE") &&
      expirationAt !== undefined &&
      expirationAt <= Date.now());
  const isTrial = revenueCatEvent.period_type === "TRIAL";

  await ctx.runMutation(internal.users.syncRevenueCatEntitlement, {
    clerkId: appUserId,
    revenueCatAppUserId: appUserId,
    subscriptionTier:
      isProEvent && !isRevocation ? (isTrial ? "trial" : "pro") : "free",
    entitlementProductId:
      typeof revenueCatEvent.product_id === "string"
        ? revenueCatEvent.product_id
        : undefined,
    entitlementExpiresAt:
      expirationAt,
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
