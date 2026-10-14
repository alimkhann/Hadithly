import { purchaseAccess } from "./lib/revenueCat";
import { defineSchema, defineTable } from "convex/server";
import { v } from "convex/values";
import {
  authenticityClaimValidator,
  licenseTermsValidator,
  providerValidator,
} from "./lib/contentPolicy";
import { legacyReaderPreferencesValidator, readerPreferencesValidator } from "./lib/preferences";
import { readingPositionValidator } from "./lib/readingPositions";
import { permissionGrant, publicCitation, reviewPass, sourcePolicy } from "./lib/evidenceReviewPolicy";
import { caseReason, caseState } from "./lib/evidenceCasePolicy";
import { supportFields, noticeKind } from "./lib/supportPolicy";

const authenticityGrade = v.union(
  v.literal("sahih"),
  v.literal("hasan"),
  v.literal("daif"),
  v.literal("mawdu"),
  v.literal("mixed"),
  v.literal("unknown"),
);

export default defineSchema({
  supportRequests: defineTable({ ...supportFields, expiresAt: v.number() })
    .index("by_reference", ["requestId"]).index("by_expiry", ["expiresAt"]),
  supportRates: defineTable({ emailHash: v.string(), count: v.number(), expiresAt: v.number() })
    .index("by_hash", ["emailHash"]).index("by_expiry", ["expiresAt"]),
  operationsState: defineTable({ day: v.string(), month: v.string(), minute: v.number(), ingressMinute: v.number(), ingressDaily: v.number(),
    supportDaily: v.number(), supportMonthly: v.number(), mailDaily: v.number(), mailMonthly: v.number(), suppressed: v.boolean() }),
  operationsMail: defineTable({ kind: noticeKind, reference: v.string(), expiresAt: v.number(), providerId: v.optional(v.string()),
    state: v.union(v.literal("queued"), v.literal("attempted"), v.literal("sent"), v.literal("delivered"), v.literal("bounced"), v.literal("complained")) })
    .index("by_kind_reference", ["kind", "reference"]).index("by_provider", ["providerId"]).index("by_state", ["state"]).index("by_expiry", ["expiresAt"]),
  reviewMonthlyBudgets: defineTable({ month: v.string(), attempts: v.number() }).index("by_month", ["month"]),
  analyticsReceipts: defineTable({ batchId: v.string(), expiresAt: v.number() })
    .index("by_batch", ["batchId"]).index("by_expiry", ["expiresAt"]),
  analyticsBuckets: defineTable({ day: v.string(), platform: v.union(v.literal("ios"), v.literal("android")),
    summaries: v.number(), counters: v.array(v.object({ metric: v.string(), count: v.number() })),
    exported: v.boolean(), exportId: v.optional(v.string()), attempts: v.optional(v.number()),
    nextAttemptAt: v.optional(v.number()), expiresAt: v.number() })
    .index("by_day_platform", ["day", "platform"]).index("by_pending", ["exported", "day"]).index("by_expiry", ["expiresAt"]),
  analyticsState: defineTable({ day: v.string(), month: v.string(), admittedDaily: v.number(),
    admittedMonthly: v.number(), exportedMonthly: v.number(), lastExportAt: v.number(), exportFailures: v.number(),
    rejectedMonthly: v.optional(v.number()) }),
  diagnosticsState: defineTable({
    month: v.string(), reports: v.number(), webReports: v.number(), failures: v.number(), windowStart: v.number(),
    lastFailureAt: v.number(), lastReportAt: v.number(), lastWebReportAt: v.number(), heartbeatAt: v.number(), alertTestUntil: v.number(),
  }),
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
    readerPreferences: v.optional(v.union(readerPreferencesValidator, legacyReaderPreferencesValidator)),
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
    subscriptionPurchases: v.optional(v.array(purchaseAccess)),
    subscriptionRefreshRevision: v.optional(v.number()),
    subscriptionSnapshotAt: v.optional(v.number()),
    subscriptionOwnershipConflict: v.optional(v.boolean()),
    // Read-only legacy fields until the bounded Q1 migration erases them.
    aiGenerationsThisMonth: v.optional(v.number()),
    aiGenerationLimit: v.optional(v.number()),
    // Assigned only through the Convex dashboard/internal admin bootstrap.
    // Admin access is never inferred from client-supplied data.
    isAdmin: v.optional(v.boolean()),
    createdAt: v.number(),
    updatedAt: v.number(),
  }).index("by_clerk_id", ["clerkId"]),

  subscriptionWebhookReceipts: defineTable({ eventId: v.string(), createdAt: v.number(), queuedAt: v.optional(v.number()), state: v.union(v.literal("queued"), v.literal("completed"), v.literal("failed")) }).index("by_event", ["eventId"]).index("by_time", ["createdAt"]).index("by_state", ["state", "createdAt"]).index("by_queue", ["state", "queuedAt"]),

  subscriptionWebhookTargets: defineTable({ receiptId: v.id("subscriptionWebhookReceipts"), userId: v.id("users"), deny: v.boolean(), ownershipConflict: v.boolean() })
    .index("by_receipt", ["receiptId"]).index("by_user", ["userId"]),

  aiGenerationJobs: defineTable({
    generationKey: v.string(), sourceDigest: v.string(), hadithId: v.id("hadiths"), language: v.string(),
    userId: v.optional(v.id("users")), origin: v.union(v.literal("user"), v.literal("service")),
    status: v.union(v.literal("pending"), v.literal("completed"), v.literal("failed")),
    attempt: v.number(), expiresAt: v.number(), createdAt: v.number(),
    translationId: v.optional(v.id("translations")),
  }).index("by_key", ["generationKey"]).index("by_user_status", ["userId", "status"])
    .index("by_user_status_expiry", ["userId", "status", "expiresAt"])
    .index("by_status_expiry", ["status", "expiresAt"]),
  // Global immutable success fact. No account, device, prompt, or user text.
  aiUsageEvents: defineTable({ generationKey: v.string(), translationId: v.id("translations"), createdAt: v.number() })
    .index("by_key", ["generationKey"]),
  aiUsageCharges: defineTable({ userId: v.id("users"), eventId: v.id("aiUsageEvents"), createdAt: v.number() })
    .index("by_user_time", ["userId", "createdAt"]),
  aiCostEvents: defineTable({ jobId: v.id("aiGenerationJobs"), attempt: v.number(), model: v.string(),
    pricingVersion: v.string(), inputTokens: v.number(), outputTokens: v.number(), thinkingTokens: v.number(),
    estimatedMicroUsd: v.number(), tokenUsageKnown: v.boolean(), durationMs: v.number(),
    outcome: v.union(v.literal("published"), v.literal("cached"), v.literal("failed"), v.literal("stale")),
    groundingUsed: v.literal(false), createdAt: v.number(),
  }).index("by_job_attempt", ["jobId", "attempt"]).index("by_time", ["createdAt"]),
  aiRateLimits: defineTable({ key: v.string(), userId: v.optional(v.id("users")), startedAt: v.number(), count: v.number() })
    .index("by_key", ["key"]).index("by_user", ["userId"]),
  aiSpendBudgets: defineTable({ monthKey: v.string(), committedMicroUsd: v.number(), freeCommittedMicroUsd: v.optional(v.number()) }).index("by_month", ["monthKey"]),
  aiSpendReservations: defineTable({ jobId: v.id("aiGenerationJobs"), attempt: v.number(), monthKey: v.string(),
    reservedMicroUsd: v.number(), freePool: v.optional(v.boolean()), settled: v.boolean() }).index("by_job_attempt", ["jobId", "attempt"]),
  generationChallenges: defineTable({ userId: v.id("users"), hadithId: v.id("hadiths"), language: v.string(),
    generationKey: v.string(), nonce: v.string(), createdAt: v.number(), expiresAt: v.number(),
  }).index("by_user_time", ["userId", "createdAt"]),
  generationCredentials: defineTable({ userId: v.id("users"), keyId: v.string(), publicKey: v.string(), signCount: v.number() })
    .index("by_key", ["keyId"]).index("by_user", ["userId"]),
  collectionCounts: defineTable({ collectionSlug: v.string(), totalHadiths: v.number(), indexedAt: v.number() })
    .index("by_collection", ["collectionSlug"]),

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
    generationKey: v.optional(v.string()),
    sourceDigest: v.optional(v.string()),
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
    legacyEvidenceMissing: v.optional(v.boolean()),
    evidencePublicationId: v.optional(v.id("evidencePublicationRevisions")),
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
    .index("by_source_status", ["source", "status"])
    .index("by_publication", ["evidencePublicationId"])
    .searchIndex("search_content", {
      searchField: "content",
      filterFields: ["language", "status"],
    }),

  // Community publication belongs to the deterministic evidence gate.
  communitySubmissions: defineTable({
    hadithId: v.id("hadiths"),
    language: v.string(),
    submittedBy: v.id("users"),
    proposedContent: v.string(),
    replacesTranslationId: v.optional(v.id("translations")),
    aiReview: v.optional(v.object({
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
    })),
    status: v.union(
      v.literal("pending"),
      v.literal("approved"),
      v.literal("rejected"),
      v.literal("needs_admin"),
      v.literal("draft"),
      v.literal("awaiting_processing"),
      v.literal("evidence_ready"),
      v.literal("under_review"),
      v.literal("review_unavailable"),
      v.literal("held"),
      v.literal("processing_failed"),
      v.literal("infected"),
      v.literal("legacy_evidence_missing"),
      v.literal("expired"),
      v.literal("revoked"),
    ),
    draftKey: v.optional(v.string()),
    expiresAt: v.optional(v.number()),
    legacyStatus: v.optional(v.string()),
    createdAt: v.number(),
    reviewedAt: v.optional(v.number()),
    contributionConsentVersion: v.optional(v.string()),
    firstRejectedAt: v.optional(v.number()),
    auditReceipt: v.optional(v.string()),
    recheckAttempts: v.optional(v.number()),
  })
    .index("by_status", ["status"])
    .index("by_submitted_by", ["submittedBy"])
    .index("by_submitter_draft_key", ["submittedBy", "draftKey"])
    .index("by_submitter_created", ["submittedBy", "createdAt"])
    .index("by_owner_target", ["submittedBy", "hadithId", "language", "createdAt"])
    .index("by_status_expiry", ["status", "expiresAt"]),

  evidenceItems: defineTable({
    submissionId: v.id("communitySubmissions"),
    ownerUserId: v.id("users"),
    clientItemKey: v.string(),
    source: v.union(
      v.object({ kind: v.literal("url"), url: v.string() }),
      v.object({
        kind: v.literal("file"),
        declaredMime: v.string(),
        declaredSize: v.number(),
        declaredSha256: v.string(),
        displayName: v.string(),
        storageId: v.optional(v.id("_storage")),
        verifiedMime: v.optional(v.string()),
        sha256: v.optional(v.string()),
        size: v.optional(v.number()),
        width: v.optional(v.number()),
        height: v.optional(v.number()),
        pageCount: v.optional(v.number()),
      }),
    ),
    state: v.union(
      v.literal("reserved"),
      v.literal("validating"),
      v.literal("quarantined_unscanned"),
      v.literal("pending_safe_fetch"),
      v.literal("processing"),
      v.literal("ready"),
      v.literal("failed"),
      v.literal("infected"),
      v.literal("invalid"),
      v.literal("expired"),
    ),
    uploadAttempts: v.number(),
    processingAttempts: v.optional(v.number()),
    processingQueued: v.optional(v.boolean()),
    processingLease: v.optional(v.object({ token: v.string(), deadline: v.number() })),
    retryable: v.optional(v.boolean()),
    createdAt: v.number(),
    updatedAt: v.number(),
  })
    .index("by_submission", ["submissionId"])
    .index("by_owner", ["ownerUserId"])
    .index("by_storage_id", ["source.storageId"])
    .index("by_processing_deadline", ["state", "processingLease.deadline"])
    .index("by_processing_queue", ["processingQueued", "createdAt"])
    .index("by_retryable", ["state", "retryable"])
    .index("by_reserved_size", ["state", "source.declaredSize"]),

  evidenceExtractions: defineTable({
    submissionId: v.id("communitySubmissions"),
    evidenceItemId: v.id("evidenceItems"),
    trust: v.literal("untrusted"),
    mime: v.string(),
    sha256: v.string(),
    finalUrl: v.optional(v.string()),
    sourceStorageId: v.optional(v.id("_storage")),
    accessChain: v.optional(v.array(v.string())),
    text: v.string(),
    spans: v.array(v.object({
      start: v.number(), end: v.number(),
      source: v.union(
        v.object({ kind: v.literal("html_chars"), start: v.number(), end: v.number() }),
        v.object({ kind: v.literal("page_box"), page: v.number(), x: v.number(), y: v.number(), width: v.number(), height: v.number() }),
      ),
    })),
    createdAt: v.number(),
  }).index("by_item", ["evidenceItemId"]).index("by_submission", ["submissionId"]).index("by_source_storage", ["sourceStorageId"]),

  evidenceWorkerLease: defineTable({
    name: v.union(v.literal("processor"), v.literal("reviewer")),
    token: v.string(),
    deadline: v.number(),
  }).index("by_name", ["name"]),

  evidenceCleanupCursor: defineTable({
    name: v.literal("storage_orphans"),
    cursor: v.optional(v.string()),
    updatedAt: v.number(),
  }).index("by_name", ["name"]),

  evidenceUploadTombstones: defineTable({
    declaredMime: v.string(),
    declaredSize: v.number(),
    declaredSha256: v.string(),
    slotCreatedAt: v.number(),
    expiresAt: v.number(),
  })
    .index("by_size", ["declaredSize"])
    .index("by_expiry", ["expiresAt"]),

  evidencePermissionGrants: defineTable({ grant: permissionGrant, submissionId: v.optional(v.id("communitySubmissions")), createdAt: v.number() })
    .index("by_artifact", ["grant.artifactSha256"]).index("by_submission", ["submissionId"])
    .index("by_scope", ["grant.artifactSha256", "grant.textSha256", "grant.canonicalId", "grant.sourceKind", "grant.sourceUrl", "submissionId", "grant.language"]),
  evidenceSourcePolicies: defineTable({ policy: sourcePolicy }).index("by_origin_kind", ["policy.origin", "policy.sourceKind"]).index("by_assessment", ["policy.assessment.kind"]).index("by_kind", ["policy.sourceKind"]),
  evidenceSourceDependencies: defineTable({ submissionId: v.id("communitySubmissions"), origin: v.string() })
    .index("by_origin", ["origin"]).index("by_submission", ["submissionId"]),
  evidenceReviewJobs: defineTable({
    submissionId: v.id("communitySubmissions"), token: v.string(), deadline: v.number(), snapshotSha256: v.string(),
    status: v.union(v.literal("running"), v.literal("complete"), v.literal("failed")),
    policyVersion: v.string(), reasons: v.array(v.string()), createdAt: v.number(),
    caseId: v.optional(v.id("evidenceCases")),
  }).index("by_submission", ["submissionId"]).index("by_status_deadline", ["status", "deadline"]),
  evidenceProvenance: defineTable({ submissionId: v.id("communitySubmissions"), evidenceItemId: v.id("evidenceItems"),
    status: v.union(v.literal("unassessed"), v.literal("verified"), v.literal("unresolved")),
    artifactSha256: v.optional(v.string()), textSha256: v.optional(v.string()), canonicalId: v.optional(v.string()), language: v.optional(v.string()),
    citation: v.optional(publicCitation), grantId: v.optional(v.id("evidencePermissionGrants")), createdAt: v.number(),
  }).index("by_submission", ["submissionId"]),
  evidenceLicenseAssessments: defineTable({ submissionId: v.id("communitySubmissions"), evidenceItemId: v.id("evidenceItems"),
    status: v.union(v.literal("unassessed"), v.literal("affirmative"), v.literal("ambiguous"), v.literal("denied")),
    grantId: v.optional(v.id("evidencePermissionGrants")), createdAt: v.number(),
  }).index("by_submission", ["submissionId"]),
  evidenceReviewPasses: defineTable({ submissionId: v.id("communitySubmissions"), status: v.union(v.literal("not_started"), v.literal("complete")),
    snapshotSha256: v.optional(v.string()), policyVersion: v.optional(v.string()), result: v.optional(reviewPass), createdAt: v.number(),
  }).index("by_submission", ["submissionId"]),
  evidencePublicationRevisions: defineTable({ submissionId: v.id("communitySubmissions"), status: v.union(v.literal("not_published"), v.literal("published"), v.literal("revoked")),
    translationId: v.optional(v.id("translations")), snapshotSha256: v.optional(v.string()), policyVersion: v.optional(v.string()),
    citations: v.optional(v.array(publicCitation)),
    permissions: v.optional(v.array(v.object({ licenseName: v.string(), permissionUrl: v.string(), attribution: v.string(), offline: v.boolean() }))),
    outputSha256: v.optional(v.string()),
    previousDefaultIds: v.optional(v.array(v.id("translations"))),
    comparisonPublicationIds: v.optional(v.array(v.id("evidencePublicationRevisions"))),
    scanBindings: v.optional(v.array(v.object({ itemId: v.id("evidenceItems"), storageId: v.id("_storage"), sha256: v.string() }))),
    accessDependencies: v.optional(v.array(v.object({ origin: v.string(), path: v.string(), sourceKind: v.union(v.literal("sunnah_com"), v.literal("evidence")) }))),
    permissionDependencies: v.optional(v.array(v.union(
      v.object({ kind: v.literal("grant"), id: v.id("evidencePermissionGrants"), snapshot: permissionGrant, use: v.optional(v.literal("comparison")) }),
      v.object({ kind: v.literal("policy"), id: v.id("evidenceSourcePolicies"), snapshot: sourcePolicy, use: v.optional(v.literal("comparison")) }),
    ))),
    createdAt: v.number(),
  }).index("by_submission", ["submissionId"]).index("by_status", ["status"]),
  evidenceAppeals: defineTable({ submissionId: v.id("communitySubmissions"), ownerUserId: v.id("users"), status: v.union(v.literal("not_requested"), v.literal("processing"), v.literal("published"), v.literal("private")), reason: v.optional(v.string()), expiresAt: v.optional(v.number()), createdAt: v.number() }).index("by_owner", ["ownerUserId"]).index("by_submission", ["submissionId"]),
  evidenceCases: defineTable({
    kind: v.union(v.literal("exception"), v.literal("report"), v.literal("appeal"), v.literal("audit"), v.literal("recheck"), v.literal("incident")),
    target: v.union(v.object({ kind: v.literal("submission"), submissionId: v.id("communitySubmissions") }), v.object({ kind: v.literal("translation"), translationId: v.id("translations") })),
    state: caseState, attempts: v.number(), receipt: v.string(), reason: caseReason,
    context: v.optional(v.string()), expiresAt: v.number(), createdAt: v.number(),
  }).index("by_submission", ["target.submissionId"]).index("by_translation", ["target.translationId"])
    .index("by_due", ["state.kind", "state.dueAt"]).index("by_kind", ["kind"]).index("by_expiry", ["expiresAt"]),
  evidenceRequestEvents: defineTable({ userId: v.id("users"), kind: v.union(v.literal("submission"), v.literal("report"), v.literal("appeal")), createdAt: v.number() })
    .index("by_user_kind_time", ["userId", "kind", "createdAt"]).index("by_time", ["createdAt"]),
  evidenceAuditActors: defineTable({ userId: v.id("users"), key: v.string() }).index("by_user", ["userId"]),
  evidenceReviewSpendEvents: defineTable({ submissionId: v.id("communitySubmissions"), createdAt: v.number() })
    .index("by_submission_time", ["submissionId", "createdAt"]).index("by_time", ["createdAt"]),
  evidenceReviewGlobalSpendEvents: defineTable({ createdAt: v.number() }).index("by_time", ["createdAt"]),
  evidenceAuditFacts: defineTable({
    receipt: v.string(), actor: v.union(v.object({ kind: v.literal("automated") }), v.object({ kind: v.literal("operator"), verified: v.literal(true), key: v.string() })),
    reason: caseReason, before: v.string(), after: v.string(), policyVersion: v.string(), publicationPolicyVersion: v.string(),
    models: v.array(v.object({ model: v.string(), revision: v.string() })), createdAt: v.number(),
  }).index("by_receipt", ["receipt"]).index("by_time", ["createdAt"]),
  evidenceAbuseEvents: defineTable({ submissionId: v.id("communitySubmissions"), ownerUserId: v.id("users"), status: v.union(v.literal("none"), v.literal("blocked")), createdAt: v.number() }).index("by_owner", ["ownerUserId"]).index("by_submission", ["submissionId"]),
  evidenceDeletionStates: defineTable({ submissionId: v.id("communitySubmissions"), status: v.union(v.literal("active"), v.literal("deleted")), createdAt: v.number() }).index("by_submission", ["submissionId"]),

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
    expiresAt: v.optional(v.number()),
    caseId: v.optional(v.id("evidenceCases")),
  })
    .index("by_status", ["status"])
    .index("by_reporter", ["reporterUserId"])
    .index("by_reporter_target", ["reporterUserId", "translationId"])
    .index("by_translation", ["translationId"])
    .index("by_case", ["caseId"])
    .index("by_expiry", ["expiresAt"]),

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
  }).index("by_kind_collection", ["kind", "collectionSlug"])
    .index("by_storage_id", ["storageId"]),
});
