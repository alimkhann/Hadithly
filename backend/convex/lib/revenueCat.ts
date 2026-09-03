export type RevenueCatAuthorization =
  | { kind: "misconfigured" }
  | { kind: "unauthorized" }
  | { kind: "authorized" };

export type ParsedRevenueCatEvent = {
  appUserId: string;
  subscriptionTier: "free" | "trial" | "pro";
  entitlementProductId?: string;
  entitlementExpiresAt?: number;
};

export type RevenueCatEventParseResult =
  | { kind: "invalid"; message: string }
  | { kind: "valid"; event: ParsedRevenueCatEvent };

export function authorizeRevenueCatWebhook(args: {
  expected: string | undefined;
  provided: string | null;
}): RevenueCatAuthorization {
  if (!args.expected) return { kind: "misconfigured" };
  if (
    args.provided !== args.expected &&
    args.provided !== `Bearer ${args.expected}`
  ) {
    return { kind: "unauthorized" };
  }
  return { kind: "authorized" };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export function parseRevenueCatEvent(args: {
  body: unknown;
  now: number;
}): RevenueCatEventParseResult {
  if (!isRecord(args.body)) {
    return { kind: "invalid", message: "Invalid RevenueCat webhook" };
  }

  const event = isRecord(args.body.event) ? args.body.event : args.body;
  const appUserId = event.app_user_id;
  if (typeof appUserId !== "string" || appUserId.length === 0) {
    return {
      kind: "invalid",
      message: "RevenueCat event missing app_user_id",
    };
  }

  const entitlementIds = event.entitlement_ids;
  const hasProEntitlement =
    (Array.isArray(entitlementIds) &&
      entitlementIds.some((entitlementId) => entitlementId === "pro")) ||
    event.entitlement_id === "pro" ||
    (typeof event.product_id === "string" &&
      event.product_id.toLowerCase().includes("pro"));
  const eventType = typeof event.type === "string" ? event.type : "";
  const expirationAt =
    typeof event.expiration_at_ms === "number"
      ? event.expiration_at_ms
      : undefined;
  const isRevocation =
    eventType === "EXPIRATION" ||
    ((eventType === "CANCELLATION" || eventType === "BILLING_ISSUE") &&
      expirationAt !== undefined &&
      expirationAt <= args.now);
  const isTrial = event.period_type === "TRIAL";

  return {
    kind: "valid",
    event: {
      appUserId,
      subscriptionTier:
        hasProEntitlement && !isRevocation
          ? isTrial
            ? "trial"
            : "pro"
          : "free",
      entitlementProductId:
        typeof event.product_id === "string" ? event.product_id : undefined,
      entitlementExpiresAt: expirationAt,
    },
  };
}
