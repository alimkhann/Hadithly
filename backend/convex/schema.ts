import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  authenticityClaimValidator,
  licenseTermsValidator,
  providerValidator,
} from "./lib/contentPolicy";
import { readerPreferencesValidator } from "./lib/preferences";
import { readingPositionValidator } from "./lib/readingPositions";

const authenticityGrade = v.union(
  v.literal("sahih"),
  v.literal("hasan"),
  v.literal("daif"),
  v.literal("mawdu"),
  v.literal("mixed"),
  v.literal("unknown"),
);

export default defineSchema({
  // Signed-in users only. Guest mode is device-local and never touches Convex.
  users: defineTable({
    clerkId: v.string(),
    email: v.optional(v.string()),
    displayName: v.optional(v.string()),
    avatarUrl: v.optional(v.string()),
    preferredLanguage: v.string(),
    // F2 reader preference contracts. Optional until every signed-in row has
    // been seeded by ensureCurrentUser; preferredLanguage stays as the legacy
    // dual-write field during the migration window.
    readerPreferences: v.optional(readerPreferencesValidator),
    // Set once when readerPreferences is first seeded from preferredLanguage.
    // After it is true, ensureCurrentUser never re-seeds the locales, so a
    // later explicit choice is never reset.
    localesMigrated: v.optional(v.boolean()),
    subscriptionTier: v.union(
      v.literal("free"),
      v.literal("trial"),
      v.literal("pro"),
    ),
    revenueCatAppUserId: v.optional(v.string()),
    entitlementProductId: v.optional(v.string()),
    entitlementExpiresAt: v.optional(v.number()),
    revenueCatEventTimestamp: v.optional(v.number()),
    entitlementUpdatedAt: v.optional(v.number()),
    aiGenerationsThisMonth: v.number(),
    aiGenerationLimit: v.number(),
    // Assigned only through the Convex dashboard/internal admin bootstrap.
    // Admin access is never inferred from client-supplied data.
    isAdmin: v.optional(v.boolean()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_clerk_id", ["clerkId"]),

  // Cached Sunnah.now books (the seven collections).
  collections: defineTable({
    slug: v.string(),
    collection: v.string(),
    name: v.string(),
    sortOrder: v.optional(v.number()),
  }).index("by_slug", ["slug"]),

  // Cached volume/chapter outline per collection so the app can navigate
  // without re-paginating the whole collection from the provider.
  collectionOutlines: defineTable({
    collectionSlug: v.string(),
    volumes: v.array(
      v.object({
        volumeId: v.string(),
        title: v.string(),
        firstChapterTitle: v.optional(v.string()),
        firstChapterArabicTitle: v.optional(v.string()),
        hadithCount: v.number(),
        // R5: source-provided chapters per volume. Optional so outlines
        // cached before R5 still validate; fresh outlines always include it.
        chapters: v.optional(
          v.array(
            v.object({
              chapterId: v.optional(v.string()),
              title: v.string(),
              arabicTitle: v.optional(v.string()),
              hadithCount: v.number(),
              firstProviderHadithId: v.string(),
            }),
          ),
        ),
      }),
    ),
    indexedAt: v.number(),
  }).index("by_collection_slug", ["collectionSlug"]),

  licenseRecords: defineTable({
    sourceKey: v.string(),
    sourceName: v.string(),
    sourceUrl: v.string(),
    terms: licenseTermsValidator,
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_source_key", ["sourceKey"]),

  hadiths: defineTable({
    provider: providerValidator,
    // Optional only while the F1 backfill crosses existing deployments.
    // Every new provider write includes both fields.
    canonicalId: v.optional(v.string()),
    providerHadithId: v.string(),
    collectionSlug: v.string(),
    bookId: v.optional(v.string()),
    chapterId: v.optional(v.string()),
    volumeId: v.optional(v.string()),
    arabicText: v.string(),
    englishText: v.optional(v.string()),
    narrator: v.optional(v.string()),
    // R6 round 3: Arabic narrator line from the provider's Arabic language
    // map. Optional so rows cached before this field existed keep working.
    narratorAr: v.optional(v.string()),
    referenceDisplay: v.string(),
    collectionName: v.string(),
    bookName: v.optional(v.string()),
    chapterName: v.optional(v.string()),
    authenticity: v.optional(authenticityClaimValidator),
    licenseRecordId: v.optional(v.id("licenseRecords")),
    // Legacy F1 migration inputs. New writes remove these fields.
    authenticityGrade: v.optional(authenticityGrade),
    authenticityAppliesTo: v.optional(
      v.union(
        v.literal("hadith"),
        v.literal("collection"),
        v.literal("none"),
      ),
    ),
    authenticitySource: v.optional(v.string()),
    authenticityConfidence: v.optional(
      v.union(
        v.literal("source_provided"),
        v.literal("manual_mapping"),
        v.literal("unavailable"),
      ),
    ),
    createdAt: v.number(),
    sourceUpdatedAt: v.optional(v.number()),
  })
    .index("by_canonical_id", ["canonicalId"])
    .index("by_provider_ref", ["provider", "collectionSlug", "providerHadithId"])
    .index("by_collection", ["provider", "collectionSlug"])
    .index("by_collection_volume", ["provider", "collectionSlug", "volumeId"])
    .searchIndex("search_english", {
      searchField: "englishText",
      filterFields: ["collectionSlug"],
    }),

  dailySelections: defineTable({
    localDate: v.string(),
    timezone: v.string(),
    hadithId: v.id("hadiths"),
    createdAt: v.number(),
  }).index("by_local_date_timezone", ["localDate", "timezone"]),

  translations: defineTable({
    hadithId: v.id("hadiths"),
    language: v.string(),
    content: v.string(),
    source: v.union(
      v.literal("official"),
      v.literal("gemini_ai"),
      v.literal("community"),
    ),
    sourceLabel: v.string(),
    aiModel: v.optional(v.string()),
    aiPromptVersion: v.optional(v.string()),
    generatedByUserId: v.optional(v.id("users")),
    status: v.union(
      v.literal("live"),
      v.literal("pending"),
      v.literal("archived"),
      v.literal("rejected"),
    ),
    isDefault: v.boolean(),
    confidence: v.optional(v.number()),
    riskFlags: v.optional(v.array(v.string())),
    groundingUsed: v.boolean(),
    groundingSourceCount: v.optional(v.number()),
    citations: v.optional(
      v.array(
        v.object({
          url: v.string(),
          title: v.optional(v.string()),
          domain: v.optional(v.string()),
        }),
      ),
    ),
    sourceReferenceUrl: v.optional(v.string()),
    contributorUserId: v.optional(v.id("users")),
    contributorDisplayName: v.optional(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
    approvedAt: v.optional(v.number()),
  })
    .index("by_hadith_language_default", ["hadithId", "language", "isDefault"])
    // O1 pack generation: all live defaults for one language, then filtered
    // to the target collection by hadith join in the generation action.
    .index("by_language_status_default", ["language", "status", "isDefault"])
    .index("by_generated_user", ["generatedByUserId"])
    .index("by_contributor_user", ["contributorUserId"])
    .searchIndex("search_content", {
      searchField: "content",
      filterFields: ["language", "status"],
    }),

  // Community translation submissions. Quality is enforced by AI review +
  // admin approval — never by public voting or rankings.
  communitySubmissions: defineTable({
    hadithId: v.id("hadiths"),
    language: v.string(),
    submittedBy: v.id("users"),
    proposedContent: v.string(),
    replacesTranslationId: v.optional(v.id("translations")),
    aiReview: v.object({
      model: v.string(),
      score: v.number(),
      riskFlags: v.array(v.string()),
      missingMeaning: v.optional(v.array(v.string())),
      addedMeaning: v.optional(v.array(v.string())),
      glossaryIssues: v.optional(v.array(v.string())),
      recommendation: v.union(
        v.literal("approve"),
        v.literal("admin_review"),
        v.literal("reject"),
      ),
    }),
    status: v.union(
      v.literal("pending"),
      v.literal("approved"),
      v.literal("rejected"),
      v.literal("needs_admin"),
    ),
    createdAt: v.number(),
    reviewedAt: v.optional(v.number()),
  })
    .index("by_status", ["status"])
    .index("by_submitted_by", ["submittedBy"]),

  bookmarks: defineTable({
    userId: v.id("users"),
    hadithId: v.id("hadiths"),
    scrollOffset: v.optional(v.number()),
    createdAt: v.number(),
  }).index("by_user", ["userId"]),

  favorites: defineTable({
    userId: v.id("users"),
    hadithId: v.id("hadiths"),
    createdAt: v.number(),
  }).index("by_user", ["userId"]),

  notes: defineTable({
    userId: v.id("users"),
    hadithId: v.id("hadiths"),
    content: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_user_hadith", ["userId", "hadithId"]),

  // H3's canonical private Saved representation. Legacy bookmark, favorite,
  // and note tables remain during the dual-read rollout for already-shipped
  // clients; this table is the single record new clients mutate and render.
  savedFolders: defineTable({
    userId: v.id("users"),
    name: v.string(),
    normalizedName: v.string(),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_user_normalized_name", ["userId", "normalizedName"]),

  savedItems: defineTable({
    userId: v.id("users"),
    hadithId: v.id("hadiths"),
    bookmarkCreatedAt: v.optional(v.number()),
    favoriteCreatedAt: v.optional(v.number()),
    noteContent: v.optional(v.string()),
    noteCreatedAt: v.optional(v.number()),
    noteUpdatedAt: v.optional(v.number()),
    folderId: v.optional(v.id("savedFolders")),
    // Changes to a placement get their own clock. It lets folder undo restore
    // only the memberships removed by that delete, without overwriting a
    // later move from another device.
    folderUpdatedAt: v.optional(v.number()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_user_hadith", ["userId", "hadithId"])
    .index("by_folder", ["folderId"]),

  readingProgress: defineTable({
    userId: v.id("users"),
    collectionSlug: v.string(),
    // R1 semantic position. Legacy fields remain as a derived projection
    // until deployed clients and the production backfill have crossed R1.
    position: v.optional(readingPositionValidator),
    bookId: v.optional(v.string()),
    hadithId: v.id("hadiths"),
    scrollOffset: v.optional(v.number()),
    updatedAt: v.number(),
  }).index("by_user_collection", ["userId", "collectionSlug"]),

  pushTokens: defineTable({
    userId: v.id("users"),
    token: v.string(),
    platform: v.union(v.literal("ios"), v.literal("android")),
    dailyTime: v.optional(v.string()),
    // N1: IANA timezone of the device (e.g. "Asia/Almaty"). Fixed offsets
    // cannot survive DST or zone changes, so scheduling uses this field.
    // tzOffsetMinutes stays as a read-only legacy fallback for one release.
    timezone: v.optional(v.string()),
    // UTC - local minutes at registration time (legacy, pre-N1). Kept so
    // old clients keep validating; the cron no longer reads it.
    tzOffsetMinutes: v.optional(v.number()),
    // Per-device locales: the notification body is materialized in the
    // translation locale; the title stays language-neutral.
    uiLocale: v.optional(v.string()),
    translationLocale: v.optional(v.string()),
    // 15-minute delivery bucket floored from dailyTime ("08:07" → "08:00").
    // The cron scans indexed buckets instead of the whole table.
    deliveryBucket: v.optional(v.string()),
    enabled: v.boolean(),
    // Local date (YYYY-MM-DD in the token's IANA zone) of the last daily
    // push actually sent, guarding the 15-minute cron against double sends.
    lastSentDate: v.optional(v.string()),
    // Bounded transient-retry state: failures since the last success and
    // the earliest time a retry may run again.
    consecutiveFailures: v.optional(v.number()),
    nextRetryAt: v.optional(v.number()),
    // Last provider error, observable forops without exposing the token.
    lastError: v.optional(v.string()),
    // Refreshed on every registration upload; tokens unseen for
    // STALE_TOKEN_DAYS are purged as probably-uninstalled.
    lastSeenAt: v.optional(v.number()),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_token", ["token"])
    .index("by_enabled_bucket", ["enabled", "deliveryBucket"]),

  translationReports: defineTable({
    translationId: v.id("translations"),
    reporterUserId: v.optional(v.id("users")),
    reason: v.string(),
    status: v.union(
      v.literal("open"),
      v.literal("reviewed"),
      v.literal("dismissed"),
    ),
    createdAt: v.number(),
  })
    .index("by_status", ["status"])
    .index("by_reporter", ["reporterUserId"]),

  languageCoverage: defineTable({
    language: v.string(),
    collectionSlug: v.optional(v.string()),
    totalHadiths: v.number(),
    officialCount: v.number(),
    aiCachedCount: v.number(),
    communityApprovedCount: v.number(),
    missingCount: v.number(),
    updatedAt: v.number(),
  }).index("by_language_collection", ["language", "collectionSlug"]),

  adminAuditLog: defineTable({
    actorUserId: v.optional(v.id("users")),
    action: v.string(),
    targetType: v.string(),
    targetId: v.string(),
    metadata: v.optional(v.any()),
    createdAt: v.number(),
  })
    .index("by_target", ["targetType", "targetId"])
    .index("by_actor", ["actorUserId"]),

  // O1 versioned offline artifacts. Each row authorizes one immutable,
  // checksummed dump or translation pack in Convex storage. Clients fetch
  // the manifest (plus a download URL) and validate bytes before
  // activating; O2 owns download, activation, and rollback.
  offlineArtifacts: defineTable({
    kind: v.union(v.literal("base"), v.literal("pack")),
    collectionSlug: v.string(),
    locale: v.optional(v.string()),
    schemaVersion: v.number(),
    contentVersion: v.string(),
    baseContentVersion: v.optional(v.string()),
    storageId: v.id("_storage"),
    sha256: v.string(),
    byteSize: v.number(),
    minAppVersion: v.string(),
    generatedAt: v.number(),
    licenseRecordId: v.id("licenseRecords"),
    compatiblePacks: v.array(v.string()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_kind_collection", ["kind", "collectionSlug"]),
});
