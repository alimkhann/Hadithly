import { v } from "convex/values";
import type { Infer } from "convex/values";

export const providerValidator = v.union(
  v.literal("sunnah_now"),
  v.literal("sunnah_com"),
  v.literal("local_dump"),
);

export type HadithProviderName = Infer<typeof providerValidator>;

export const normalizedGradeValidator = v.union(
  v.literal("sahih"),
  v.literal("hasan"),
  v.literal("daif"),
  v.literal("mawdu"),
  v.literal("mixed"),
  v.literal("unknown"),
);

export type NormalizedGrade = Infer<typeof normalizedGradeValidator>;

export const authenticityClaimValidator = v.union(
  v.object({
    kind: v.literal("hadith_grade"),
    normalizedGrade: normalizedGradeValidator,
    claimScope: v.literal("hadith"),
    sourceLabel: v.string(),
    sourceName: v.string(),
    sourceUrl: v.string(),
    verificationMethod: v.literal("source_provided"),
  }),
  v.object({
    kind: v.literal("collection_scope"),
    normalizedGrade: v.literal("sahih"),
    claimScope: v.literal("collection"),
    sourceLabel: v.string(),
    sourceName: v.string(),
    sourceUrl: v.string(),
    verificationMethod: v.literal("manual_collection_mapping"),
  }),
  v.object({
    kind: v.literal("unverified"),
    claimScope: v.literal("none"),
    sourceLabel: v.string(),
    sourceName: v.string(),
    sourceUrl: v.string(),
    verificationMethod: v.literal("unavailable"),
  }),
);

export type AuthenticityClaim = Infer<typeof authenticityClaimValidator>;

export const licenseTermsValidator = v.union(
  v.object({ kind: v.literal("unverified") }),
  v.object({
    kind: v.literal("verified"),
    licenseName: v.string(),
    licenseUrl: v.string(),
    permitsDisplay: v.boolean(),
    permitsRedistribution: v.boolean(),
    permitsOfflineDistribution: v.boolean(),
    verifiedAt: v.number(),
  }),
);

export const licenseRecordDescriptorValidator = v.object({
  sourceKey: v.string(),
  sourceName: v.string(),
  sourceUrl: v.string(),
  terms: licenseTermsValidator,
});

export type LicenseRecordDescriptor = Infer<
  typeof licenseRecordDescriptorValidator
>;

export const SUNNAH_NOW_LICENSE_RECORD = {
  sourceKey: "sunnah_now",
  sourceName: "Sunnah.now",
  sourceUrl: "https://sunnah.now",
  terms: { kind: "unverified" },
} satisfies LicenseRecordDescriptor;

const UNVERIFIED_AUTHENTICITY = {
  kind: "unverified",
  claimScope: "none",
  sourceLabel: "Authenticity not verified",
  sourceName: "Sunnah.now",
  sourceUrl: "https://sunnah.now",
  verificationMethod: "unavailable",
} satisfies AuthenticityClaim;

export type CanonicalHadithIdentity = {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
  canonicalId: string;
};

export function canonicalHadithIdentity(input: {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
}): CanonicalHadithIdentity {
  for (const [name, value] of Object.entries(input)) {
    if (value.length === 0 || value.includes(":")) {
      throw new Error(`Invalid canonical hadith ${name}`);
    }
  }
  return {
    ...input,
    canonicalId: `${input.provider}:${input.collectionSlug}:${input.providerHadithId}`,
  };
}

/**
 * Sunnah.now does not currently provide a structured per-hadith grade.
 * These two explicit mappings are editorial collection claims with a cited
 * source. Provider prose never enters this decision.
 */
export function authenticityForProviderHadith(
  collectionSlug: string,
): AuthenticityClaim {
  if (collectionSlug === "bukhari") {
    return {
      kind: "collection_scope",
      normalizedGrade: "sahih",
      claimScope: "collection",
      sourceLabel: "Documented Sahih collection",
      sourceName: "Sunnah.com",
      sourceUrl: "https://sunnah.com/bukhari/about",
      verificationMethod: "manual_collection_mapping",
    };
  }
  if (collectionSlug === "muslim") {
    return {
      kind: "collection_scope",
      normalizedGrade: "sahih",
      claimScope: "collection",
      sourceLabel: "Documented Sahih collection",
      sourceName: "Sunnah.com",
      sourceUrl: "https://sunnah.com/muslim/about",
      verificationMethod: "manual_collection_mapping",
    };
  }
  return { ...UNVERIFIED_AUTHENTICITY };
}

export type LegacyAuthenticity = {
  collectionSlug: string;
  authenticityGrade?: NormalizedGrade;
  authenticityAppliesTo: "hadith" | "collection" | "none";
  authenticitySource?: string;
  authenticityConfidence:
    | "source_provided"
    | "manual_mapping"
    | "unavailable";
};

/**
 * Migrates only the two manual mappings whose provenance is known. The old
 * source-provided shape lacks a source URL, so it cannot become a verified
 * hadith-grade claim without new evidence.
 */
export function migrateLegacyAuthenticity(
  legacy: LegacyAuthenticity,
): AuthenticityClaim {
  const isKnownManualCollectionClaim =
    legacy.authenticityGrade === "sahih" &&
    legacy.authenticityAppliesTo === "collection" &&
    legacy.authenticitySource === "Collection-level mapping" &&
    legacy.authenticityConfidence === "manual_mapping" &&
    (legacy.collectionSlug === "bukhari" || legacy.collectionSlug === "muslim");

  return isKnownManualCollectionClaim
    ? authenticityForProviderHadith(legacy.collectionSlug)
    : { ...UNVERIFIED_AUTHENTICITY };
}
