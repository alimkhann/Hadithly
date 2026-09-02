import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";

const provider = v.union(
  v.literal("sunnah_now"),
  v.literal("sunnah_com"),
  v.literal("local_dump"),
);

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
    subscriptionTier: v.union(
      v.literal("free"),
      v.literal("trial"),
      v.literal("pro"),
    ),
    revenueCatAppUserId: v.optional(v.string()),
    entitlementProductId: v.optional(v.string()),
    entitlementExpiresAt: v.optional(v.number()),
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
      }),
    ),
    indexedAt: v.number(),
  }).index("by_collection_slug", ["collectionSlug"]),

  hadiths: defineTable({
    provider,
    providerHadithId: v.string(),
    collectionSlug: v.string(),
    bookId: v.optional(v.string()),
    chapterId: v.optional(v.string()),
    volumeId: v.optional(v.string()),
    arabicText: v.string(),
    englishText: v.optional(v.string()),
    narrator: v.optional(v.string()),
    referenceDisplay: v.string(),
    collectionName: v.string(),
    bookName: v.optional(v.string()),
    chapterName: v.optional(v.string()),
    authenticityGrade: v.optional(authenticityGrade),
    authenticityAppliesTo: v.union(
      v.literal("hadith"),
      v.literal("collection"),
      v.literal("none"),
    ),
    authenticitySource: v.optional(v.string()),
    authenticityConfidence: v.union(
      v.literal("source_provided"),
      v.literal("manual_mapping"),
      v.literal("unavailable"),
    ),
    createdAt: v.number(),
    sourceUpdatedAt: v.optional(v.number()),
  })
    .index("by_provider_ref", ["provider", "collectionSlug", "providerHadithId"])
    .index("by_collection", ["provider", "collectionSlug"])
    .index("by_collection_volume", ["provider", "collectionSlug", "volumeId"])
    .searchIndex("search_english", {
      searchField: "englishText",
      filterFields: ["collectionSlug"],
    }),

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

  readingProgress: defineTable({
    userId: v.id("users"),
    collectionSlug: v.string(),
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
    // UTC - local minutes at registration time (the Date.getTimezoneOffset
    // convention), so the cron can derive the device's local clock.
    tzOffsetMinutes: v.optional(v.number()),
    enabled: v.boolean(),
    // Local date (YYYY-MM-DD in the token's tz) of the last daily push
    // actually sent, guarding the 15-minute cron against double sends.
    lastSentDate: v.optional(v.string()),
    updatedAt: v.number(),
  })
    .index("by_user", ["userId"])
    .index("by_token", ["token"]),

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
});
