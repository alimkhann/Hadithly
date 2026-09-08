import { Platform } from "react-native";
import Purchases, {
  type CustomerInfo,
  type PurchasesOffering,
  type PurchasesPackage,
} from "react-native-purchases";

export const PRO_ENTITLEMENT_ID = "pro";

let configured = false;

export function configurePurchases(userId?: string) {
  const apiKey =
    Platform.OS === "ios"
      ? process.env.EXPO_PUBLIC_REVENUECAT_IOS_KEY
      : process.env.EXPO_PUBLIC_REVENUECAT_ANDROID_KEY;
  if (!apiKey) return false;
  Purchases.configure({ apiKey, appUserID: userId });
  configured = true;
  return true;
}

export function isPurchasesConfigured() {
  return configured;
}

/** Current offering's packages (monthly/annual/etc.), or null if unavailable. */
export async function getCurrentOffering(): Promise<PurchasesOffering | null> {
  if (!configured) return null;
  try {
    const offerings = await Purchases.getOfferings();
    return offerings.current ?? null;
  } catch {
    return null;
  }
}

export function hasProEntitlement(info: CustomerInfo | null | undefined) {
  if (!info) return false;
  return Boolean(info.entitlements.active[PRO_ENTITLEMENT_ID]);
}

export type PurchaseResult =
  | { status: "purchased"; isPro: boolean }
  | { status: "cancelled" }
  | { status: "error"; message: string };

export async function purchasePackage(
  pkg: PurchasesPackage,
): Promise<PurchaseResult> {
  try {
    const { customerInfo } = await Purchases.purchasePackage(pkg);
    return { status: "purchased", isPro: hasProEntitlement(customerInfo) };
  } catch (error) {
    if (
      error &&
      typeof error === "object" &&
      "userCancelled" in error &&
      (error as { userCancelled?: boolean }).userCancelled
    ) {
      return { status: "cancelled" };
    }
    return { status: "error", message: purchaseErrorMessage(error) };
  }
}

export async function restorePurchases(): Promise<PurchaseResult> {
  try {
    const customerInfo = await Purchases.restorePurchases();
    return { status: "purchased", isPro: hasProEntitlement(customerInfo) };
  } catch (error) {
    return { status: "error", message: purchaseErrorMessage(error) };
  }
}

function purchaseErrorMessage(error: unknown) {
  if (error && typeof error === "object" && "message" in error) {
    return String(
      (error as { message?: unknown }).message ?? "Purchase failed.",
    );
  }
  return "Purchase failed.";
}
