import type {
  Citation,
  Hadith,
  HadithProviderName,
  Translation,
} from "@hadithly/types";
import { ConvexHttpClient } from "convex/browser";
import { makeFunctionReference } from "convex/server";

type ProviderRef = {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
};

type CachedTranslation = Translation & {
  _id?: string;
};

type CachedHadithInput = Omit<Hadith, "id" | "createdAt">;

const upsertHadithPage = makeFunctionReference<
  "mutation",
  { items: CachedHadithInput[] },
  string[]
>("hadiths:upsertPage");
const getHadithByProviderRef = makeFunctionReference<
  "query",
  ProviderRef,
  (Hadith & { _id: string }) | null
>("hadiths:getByProviderRef");
const searchHadiths = makeFunctionReference<
  "query",
  { query: string; collectionSlug?: string; language?: string; limit?: number },
  Hadith[]
>("hadiths:search");
const getDefaultTranslationForProviderRef = makeFunctionReference<
  "query",
  ProviderRef & { language: string },
  CachedTranslation | null
>("translations:getDefaultForProviderRef");
const cacheGeminiTranslationForProviderRef = makeFunctionReference<
  "mutation",
  ProviderRef & {
    language: string;
    content: string;
    aiModel: string;
    confidence?: number;
    riskFlags?: string[];
    groundingUsed?: boolean;
    groundingSourceCount?: number;
    citations?: Citation[];
    sourceReferenceUrl?: string;
  },
  string
>("translations:cacheGeminiTranslationForProviderRef");
const syncRevenueCatEntitlement = makeFunctionReference<
  "mutation",
  {
    clerkId: string;
    revenueCatAppUserId: string;
    subscriptionTier: "free" | "trial" | "pro";
    entitlementProductId?: string;
    entitlementExpiresAt?: number;
  },
  string
>("users:syncRevenueCatEntitlement");
const listEnabledPushTokens = makeFunctionReference<
  "query",
  { limit?: number },
  Array<{
    token: string;
    platform: "ios" | "android" | "web";
    dailyTime?: string;
  }>
>("library:listEnabledPushTokens");
const upsertCurrentUser = makeFunctionReference<
  "mutation",
  {
    clerkId: string;
    email?: string;
    displayName?: string;
    avatarUrl?: string;
    preferredLanguage?: string;
  },
  string
>("users:upsertCurrentUser");
const incrementAiGeneration = makeFunctionReference<
  "mutation",
  { userId: string },
  void
>("quotas:incrementAiGeneration");
const canGenerateAi = makeFunctionReference<
  "query",
  { userId: string },
  boolean
>("quotas:canGenerateAi");
const resetMonthlyAiUsage = makeFunctionReference<
  "mutation",
  Record<string, never>,
  number
>("quotas:resetMonthlyAiUsage");
const savePushToken = makeFunctionReference<
  "mutation",
  {
    userId: string;
    token: string;
    platform: "ios" | "android" | "web";
    dailyTime?: string;
    enabled: boolean;
  },
  string
>("library:savePushToken");

export function shouldUseConvex() {
  return Boolean(process.env.CONVEX_URL || process.env.NEXT_PUBLIC_CONVEX_URL);
}

export function parseInternalHadithId(value: string): ProviderRef | null {
  const [provider, collectionSlug, ...rest] = value.split(":");
  const providerHadithId = rest.join(":");
  if (!provider || !collectionSlug || !providerHadithId) return null;
  if (
    provider !== "sunnah_now" &&
    provider !== "sunnah_com" &&
    provider !== "local_dump"
  )
    return null;
  return { provider, collectionSlug, providerHadithId };
}

function getConvexClient() {
  const url = process.env.CONVEX_URL || process.env.NEXT_PUBLIC_CONVEX_URL;
  if (!url) return null;
  return new ConvexHttpClient(url, { logger: false });
}

export async function cacheHadithPage(items: Hadith[]) {
  const client = getConvexClient();
  if (!client || items.length === 0) return [];
  return await client.mutation(upsertHadithPage, {
    items: items.map(({ id, createdAt, ...item }) => {
      void id;
      return item;
    }),
  });
}

export async function findCachedHadithByInternalId(internalId: string) {
  const ref = parseInternalHadithId(internalId);
  const client = getConvexClient();
  if (!client || !ref) return null;
  return await client.query(getHadithByProviderRef, ref);
}

export async function searchCachedHadiths(args: {
  query: string;
  collectionSlug?: string;
  language?: string;
  limit?: number;
}) {
  const client = getConvexClient();
  if (!client) return [];
  return await client.query(searchHadiths, args);
}

export async function getCachedTranslation(
  internalHadithId: string,
  language: string,
) {
  const ref = parseInternalHadithId(internalHadithId);
  const client = getConvexClient();
  if (!client || !ref) return null;
  return await client.query(getDefaultTranslationForProviderRef, {
    ...ref,
    language,
  });
}

export async function cacheGeminiTranslation(args: {
  hadithId: string;
  language: string;
  content: string;
  aiModel: string;
  confidence?: number;
  riskFlags?: string[];
  groundingUsed?: boolean;
  groundingSourceCount?: number;
  citations?: Citation[];
  sourceReferenceUrl?: string;
}) {
  const ref = parseInternalHadithId(args.hadithId);
  const client = getConvexClient();
  if (!client || !ref) return null;
  return await client.mutation(cacheGeminiTranslationForProviderRef, {
    ...ref,
    language: args.language,
    content: args.content,
    aiModel: args.aiModel,
    confidence: args.confidence,
    riskFlags: args.riskFlags,
    groundingUsed: args.groundingUsed,
    groundingSourceCount: args.groundingSourceCount,
    citations: args.citations,
    sourceReferenceUrl: args.sourceReferenceUrl,
  });
}

export async function updateRevenueCatEntitlement(args: {
  clerkId: string;
  revenueCatAppUserId: string;
  subscriptionTier: "free" | "trial" | "pro";
  entitlementProductId?: string;
  entitlementExpiresAt?: number;
}) {
  const client = getConvexClient();
  if (!client) return null;
  return await client.mutation(syncRevenueCatEntitlement, args);
}

export async function getEnabledPushTokens(limit = 1000) {
  const client = getConvexClient();
  if (!client) return [];
  return await client.query(listEnabledPushTokens, { limit });
}

export async function saveUserPushToken(args: {
  clerkId: string;
  email?: string;
  displayName?: string;
  preferredLanguage?: string;
  token: string;
  platform: "ios" | "android" | "web";
  dailyTime?: string;
}) {
  const client = getConvexClient();
  if (!client) return null;
  const userId = await client.mutation(upsertCurrentUser, {
    clerkId: args.clerkId,
    email: args.email,
    displayName: args.displayName,
    preferredLanguage: args.preferredLanguage,
  });
  return await client.mutation(savePushToken, {
    userId,
    token: args.token,
    platform: args.platform,
    dailyTime: args.dailyTime,
    enabled: true,
  });
}

export async function upsertApiUser(args: {
  clerkId: string;
  email?: string;
  displayName?: string;
  avatarUrl?: string;
  preferredLanguage?: string;
}) {
  const client = getConvexClient();
  if (!client) return null;
  return await client.mutation(upsertCurrentUser, args);
}

export async function incrementAiGenerationForUser(userId: string) {
  const client = getConvexClient();
  if (!client) return null;
  return await client.mutation(incrementAiGeneration, { userId });
}

export async function canGenerateAiForUser(userId: string) {
  const client = getConvexClient();
  if (!client) return null;
  return await client.query(canGenerateAi, { userId });
}

export async function resetMonthlyAiUsageForAll() {
  const client = getConvexClient();
  if (!client) return null;
  return await client.mutation(resetMonthlyAiUsage, {});
}
