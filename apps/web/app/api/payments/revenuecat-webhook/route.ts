import { jsonError } from "@/lib/hadith-provider";
import { updateRevenueCatEntitlement } from "@/lib/convex-server";

export async function POST(request: Request) {
  const expected = process.env.REVENUECAT_WEBHOOK_SECRET;
  const provided = request.headers.get("authorization");
  if (expected && provided !== expected && provided !== `Bearer ${expected}`) {
    return jsonError("Unauthorized", 401);
  }
  const event = await request.json().catch(() => null);
  if (!event) {
    return jsonError("Invalid RevenueCat webhook", 400);
  }
  const revenueCatEvent = event.event ?? event;
  const appUserId = revenueCatEvent.app_user_id;
  if (!appUserId || typeof appUserId !== "string") {
    return jsonError("RevenueCat event missing app_user_id", 400);
  }

  const entitlementIds = Array.isArray(revenueCatEvent.entitlement_ids)
    ? revenueCatEvent.entitlement_ids
    : [];
  const isProEvent =
    entitlementIds.includes("pro") ||
    revenueCatEvent.entitlement_id === "pro" ||
    revenueCatEvent.product_id?.toLowerCase?.().includes("pro");
  const isRevocation = ["EXPIRATION", "CANCELLATION", "BILLING_ISSUE"].includes(
    revenueCatEvent.type,
  );

  const entitlementSync = await updateRevenueCatEntitlement({
    clerkId: appUserId,
    revenueCatAppUserId: appUserId,
    subscriptionTier: isProEvent && !isRevocation ? "pro" : "free",
    entitlementProductId: revenueCatEvent.product_id,
    entitlementExpiresAt:
      typeof revenueCatEvent.expiration_at_ms === "number"
        ? revenueCatEvent.expiration_at_ms
        : undefined,
  });

  return Response.json({
    ok: true,
    entitlementSync: entitlementSync ? "updated" : "skipped_no_convex",
  });
}
