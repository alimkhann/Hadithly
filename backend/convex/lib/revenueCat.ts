import { v } from "convex/values";

export function authorizeRevenueCatWebhook(args: { expected: string | undefined; provided: string | null }) {
  if (!args.expected) return { kind: "misconfigured" } as const;
  if (args.provided !== args.expected && args.provided !== `Bearer ${args.expected}`) return { kind: "unauthorized" } as const;
  return { kind: "authorized" } as const;
}
export function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}
export const purchaseAccess = v.object({ productId: v.string(), store: v.union(v.literal("app_store"), v.literal("play_store")),
  paidUntil: v.number(), until: v.number(), phase: v.union(v.literal("paid"), v.literal("cancelled"), v.literal("grace")) });
export type PurchaseAccess = { productId: string; store: "app_store" | "play_store"; paidUntil: number; until: number; phase: "paid" | "cancelled" | "grace" };
export type SubscriptionFields = { subscriptionTier: "free" | "trial" | "pro"; entitlementExpiresAt?: number;
  subscriptionPurchases?: PurchaseAccess[]; subscriptionOwnershipConflict?: boolean };
export function subscriptionAccess(user: SubscriptionFields, now: number) {
  if (user.subscriptionOwnershipConflict) return null;
  if (user.subscriptionPurchases !== undefined)
    return user.subscriptionPurchases.filter(p => p.until > now).sort((a, b) => b.until - a.until)[0] ?? null;
  // Legacy finite grants survive rollout; absent expiry never creates indefinite Pro.
  if (user.subscriptionTier !== "free" && user.entitlementExpiresAt !== undefined && user.entitlementExpiresAt > now)
    return { until: user.entitlementExpiresAt, phase: "paid" as const, store: null };
  return null;
}
export function revenueCatPolicy() {
  const environment = process.env.REVENUECAT_ENVIRONMENT ?? "PRODUCTION";
  if (environment !== "PRODUCTION" && environment !== "SANDBOX") throw new Error("SUBSCRIPTIONS_NOT_CONFIGURED");
  if (environment === "SANDBOX" && !["https://festive-cobra-664.eu-west-1.convex.cloud", "https://festive-cobra-664.convex.cloud"].includes(process.env.CONVEX_CLOUD_URL ?? "")) throw new Error("SUBSCRIPTIONS_NOT_CONFIGURED");
  const appIds = (process.env.REVENUECAT_APP_IDS ?? "").split(",").map(s => s.trim()).filter(Boolean);
  const playProducts = (process.env.REVENUECAT_PLAY_PRODUCTS ?? "").split(",").map(s => s.trim()).filter(Boolean);
  const appleProducts = ["com.hadithly.app.pro.monthly", "com.hadithly.app.pro.annual"];
  if (playProducts.some(p => appleProducts.includes(p)) || playProducts.length > 2) throw new Error("SUBSCRIPTIONS_NOT_CONFIGURED");
  return { environment, appIds, appleProducts, playProducts };
}
type Policy = ReturnType<typeof revenueCatPolicy>;
type Delivery = { id: string; accountIds: string[]; deny: boolean; transferDestinations: string[] };
type ParseDelivery = { kind: "invalid" } | { kind: "ignored" } | { kind: "valid"; delivery: Delivery };
const clerkAccount = (id: unknown): id is string => typeof id === "string" && /^user_[A-Za-z0-9_-]{1,160}$/.test(id);
export function parseRevenueCatEvent(body: unknown, policy: Policy): ParseDelivery {
  if (!isRecord(body) || !isRecord(body.event)) return { kind: "invalid" };
  const event = body.event;
  if (typeof event.id !== "string" || !event.id || event.id.length > 200 || typeof event.type !== "string") return { kind: "invalid" };
  // Dashboard tests can use the project's Test Store app, never an access grant.
  if (event.type === "TEST") return { kind: "ignored" };
  if (typeof event.app_id !== "string" || !policy.appIds.includes(event.app_id)) return { kind: "invalid" };
  if (event.environment !== policy.environment) return { kind: "ignored" };
  if (event.type === "TRANSFER") {
    if (!Array.isArray(event.transferred_from) || !Array.isArray(event.transferred_to) ||
        event.transferred_from.length + event.transferred_to.length > 100) return { kind: "invalid" };
    const sources = event.transferred_from.filter(clerkAccount), destinations = event.transferred_to.filter(clerkAccount);
    return { kind: "valid", delivery: { id: event.id, accountIds: [...new Set([...sources, ...destinations])], deny: true, transferDestinations: destinations } };
  }
  if (!clerkAccount(event.app_user_id)) return { kind: "ignored" };
  const deny = event.type === "EXPIRATION" || (event.type === "CANCELLATION" && event.cancel_reason === "CUSTOMER_SUPPORT");
  return { kind: "valid", delivery: { id: event.id, accountIds: [event.app_user_id], deny, transferDestinations: [] } };
}
function dateMs(value: unknown): number | null {
  if (typeof value !== "string") return null;
  const time = Date.parse(value);
  return Number.isFinite(time) && time > 0 ? time : null;
}
function subscriptionProductId(rawId: string, wire: Record<string, unknown>): string {
  if (wire.store !== "play_store") return rawId;
  const plan = wire.product_plan_identifier;
  if (rawId.includes(":")) return typeof plan === "string" && rawId.split(":")[1] !== plan ? "" : rawId;
  return typeof plan === "string" && plan.length > 0 ? `${rawId}:${plan}` : rawId;
}

export function parseRevenueCatSnapshot(body: unknown, accountId: string, policy: Policy) {
  if (!isRecord(body) || !Number.isSafeInteger(body.request_date_ms) || typeof body.request_date_ms !== "number" ||
      !isRecord(body.subscriber) || !isRecord(body.subscriber.entitlements) || !isRecord(body.subscriber.subscriptions))
    throw new Error("INVALID_SUBSCRIPTION_SNAPSHOT");
  const subscriber = body.subscriber, original = subscriber.original_app_user_id;
  if (typeof original !== "string") throw new Error("INVALID_SUBSCRIPTION_SNAPSHOT");
  const ownershipConflict = !original.startsWith("$RCAnonymousID:") && original !== accountId;
  const purchases: PurchaseAccess[] = [];
  if (!ownershipConflict && isRecord(subscriber.entitlements) && isRecord(subscriber.entitlements.pro) && isRecord(subscriber.subscriptions)) {
    const rawEntitledProduct = subscriber.entitlements.pro.product_identifier;
    const entitledWire = typeof rawEntitledProduct === "string"
      ? subscriber.subscriptions[rawEntitledProduct] ?? subscriber.subscriptions[rawEntitledProduct.split(":")[0]] : null;
    const entitledProduct = typeof rawEntitledProduct === "string" && isRecord(entitledWire)
      ? subscriptionProductId(rawEntitledProduct, entitledWire) : null;
    const catalog = [...policy.appleProducts, ...policy.playProducts];
    // A sole exact pro entitlement plus the verified catalog binds both store products.
    if (typeof entitledProduct === "string" && catalog.includes(entitledProduct)) {
      for (const [rawProductId, wire] of Object.entries(subscriber.subscriptions)) {
        if (!isRecord(wire)) throw new Error("INVALID_SUBSCRIPTION_SNAPSHOT");
        const productId = subscriptionProductId(rawProductId, wire);
        const store = wire.store;
        const allowed = store === "app_store" ? policy.appleProducts.includes(productId)
          : store === "play_store" && policy.playProducts.includes(productId);
        if (!allowed || (store !== "app_store" && store !== "play_store") || wire.is_sandbox !== (policy.environment === "SANDBOX") ||
            wire.ownership_type !== "PURCHASED" || wire.refunded_at !== null) continue;
        const paidUntil = dateMs(wire.expires_date);
        if (paidUntil === null) continue;
        const graceUntil = dateMs(wire.grace_period_expires_date);
        const until = Math.max(paidUntil, graceUntil ?? 0);
        const phase = graceUntil !== null && graceUntil > paidUntil && wire.billing_issues_detected_at != null ? "grace"
          : wire.unsubscribe_detected_at != null ? "cancelled" : "paid";
        purchases.push({ productId, store, paidUntil, until, phase });
      }
    }
  }
  return { observedAt: body.request_date_ms, purchases, ownershipConflict };
}
