import { v } from "convex/values";
import type { Infer } from "convex/values";
import {
  authenticityClaimValidator,
  licenseRecordDescriptorValidator,
  normalizedGradeValidator,
  providerValidator,
} from "./contentPolicy";

/**
 * O1 offline dumps — pure, deterministic builders and validators for
 * versioned collection base dumps and separate translation packs.
 *
 * No Node APIs here: this module is imported by both queries (edge runtime)
 * and the Node generation action. Hashing (SHA-256) lives with the caller
 * (`actions/offlineDumps.ts`, `node:crypto`); everything else — canonical
 * serialization, row validation, manifest assembly — is pure so it can be
 * unit-tested without Convex and mirrored 1:1 in Swift and Kotlin.
 *
 * Wire formats are part of the O1 contract. Do not rename fields or change
 * key order without bumping OFFLINE_DUMP_SCHEMA_VERSION and updating both
 * native decoders.
 */

export const OFFLINE_DUMP_SCHEMA_VERSION = 1;
export const OFFLINE_DUMP_CONTENT_MODEL = "od1";
export const OFFLINE_MIN_APP_VERSION = "0.1.0";

export const BASE_DUMP_FORMAT = "hadithly-base-dump";
export const TRANSLATION_PACK_FORMAT = "hadithly-translation-pack";
export const OFFLINE_MANIFEST_FORMAT = "hadithly-offline-manifest";

const COLLECTION_SLUG_PATTERN = /^[a-z][a-z0-9-]{1,31}$/;
// Deliberately wider than the F3 canonical-link pattern: Sunnah.now serves
// real collection content under id "0" (e.g. Muslim's Muqaddimah), and the
// offline dump must carry exactly what the reader shows online. R1
// positions already accept the same shape, so Saved and Continue Reading
// keep working for those hadiths. Links to such ids still fall back safely
// under the stricter F3 pattern.
const PROVIDER_HADITH_ID_PATTERN = /^[0-9]{1,12}(\.[0-9]{1,12})*$/;
const SHA256_HEX_PATTERN = /^[0-9a-f]{64}$/;
const SEMVER_PATTERN = /^\d+\.\d+\.\d+$/;

const VALID_GRADES = new Set([
  "sahih",
  "hasan",
  "daif",
  "mawdu",
  "mixed",
  "unknown",
]);

export type OfflineDumpErrorCode =
  | "missing_license"
  | "unlicensed_source"
  | "duplicate_provider_id"
  | "invalid_grade"
  | "bad_reference"
  | "nondeterministic_output"
  | "checksum_mismatch"
  | "unsupported_schema"
  | "incompatible_pack";

export class OfflineDumpError extends Error {
  readonly code: OfflineDumpErrorCode;

  constructor(code: OfflineDumpErrorCode, detail: string) {
    super(`Offline dump ${code}: ${detail}`);
    this.name = "OfflineDumpError";
    this.code = code;
  }
}

export const offlineDumpHadithValidator = v.object({
  canonicalId: v.string(),
  provider: providerValidator,
  collectionSlug: v.string(),
  providerHadithId: v.string(),
  volumeId: v.optional(v.string()),
  chapterId: v.optional(v.string()),
  arabicText: v.string(),
  englishText: v.optional(v.string()),
  narrator: v.optional(v.string()),
  narratorAr: v.optional(v.string()),
  referenceDisplay: v.string(),
  collectionName: v.string(),
  bookName: v.optional(v.string()),
  chapterName: v.optional(v.string()),
  authenticity: authenticityClaimValidator,
});

export type OfflineDumpHadith = Infer<typeof offlineDumpHadithValidator>;

export const baseDumpValidator = v.object({
  format: v.literal(BASE_DUMP_FORMAT),
  schemaVersion: v.literal(OFFLINE_DUMP_SCHEMA_VERSION),
  collectionSlug: v.string(),
  collectionName: v.string(),
  contentVersion: v.string(),
  generatedAt: v.number(),
  license: licenseRecordDescriptorValidator,
  hadiths: v.array(offlineDumpHadithValidator),
});

export type BaseDump = Infer<typeof baseDumpValidator>;

export const translationPackEntryValidator = v.object({
  canonicalId: v.string(),
  language: v.string(),
  content: v.string(),
  source: v.union(
    v.literal("official"),
    v.literal("community"),
    v.literal("gemini_ai"),
  ),
  sourceLabel: v.string(),
});

export type TranslationPackEntry = Infer<typeof translationPackEntryValidator>;

export const translationPackValidator = v.object({
  format: v.literal(TRANSLATION_PACK_FORMAT),
  schemaVersion: v.literal(OFFLINE_DUMP_SCHEMA_VERSION),
  collectionSlug: v.string(),
  language: v.string(),
  baseContentVersion: v.string(),
  contentVersion: v.string(),
  generatedAt: v.number(),
  license: licenseRecordDescriptorValidator,
  entries: v.array(translationPackEntryValidator),
});

export type TranslationPack = Infer<typeof translationPackValidator>;

export const offlineManifestValidator = v.object({
  format: v.literal(OFFLINE_MANIFEST_FORMAT),
  schemaVersion: v.literal(OFFLINE_DUMP_SCHEMA_VERSION),
  kind: v.union(v.literal("base"), v.literal("pack")),
  collectionSlug: v.string(),
  locale: v.optional(v.string()),
  contentVersion: v.string(),
  baseContentVersion: v.optional(v.string()),
  byteSize: v.number(),
  sha256: v.string(),
  minAppVersion: v.string(),
  generatedAt: v.number(),
  license: licenseRecordDescriptorValidator,
  compatiblePacks: v.array(v.string()),
  storageId: v.id("_storage"),
});

export type OfflineManifest = Infer<typeof offlineManifestValidator>;

/** Manifest shape returned to clients (storage id stays server-side). */
export const offlineManifestViewValidator = v.object({
  format: v.literal(OFFLINE_MANIFEST_FORMAT),
  schemaVersion: v.literal(OFFLINE_DUMP_SCHEMA_VERSION),
  kind: v.union(v.literal("base"), v.literal("pack")),
  collectionSlug: v.string(),
  locale: v.optional(v.string()),
  contentVersion: v.string(),
  baseContentVersion: v.optional(v.string()),
  byteSize: v.number(),
  sha256: v.string(),
  minAppVersion: v.string(),
  generatedAt: v.number(),
  license: licenseRecordDescriptorValidator,
  compatiblePacks: v.array(v.string()),
  downloadUrl: v.string(),
});

export type OfflineManifestView = Infer<typeof offlineManifestViewValidator>;

/**
 * Deterministic JSON serialization: object keys sorted recursively, arrays
 * keep their order, no whitespace. Two builds over equal input produce
 * byte-identical output, which is what makes content versions reproducible.
 * Throws on values JSON cannot represent (undefined, functions, bigint,
 * non-finite numbers) instead of silently dropping them.
 */
export function canonicalJson(value: unknown): string {
  if (value === null) return "null";
  if (typeof value === "boolean") return value ? "true" : "false";
  if (typeof value === "string") return JSON.stringify(value);
  if (typeof value === "number") {
    if (!Number.isFinite(value)) {
      throw new OfflineDumpError(
        "nondeterministic_output",
        "non-finite number cannot be serialized deterministically",
      );
    }
    return JSON.stringify(value);
  }
  if (Array.isArray(value)) {
    return `[${value.map((entry) => canonicalJson(entry)).join(",")}]`;
  }
  if (typeof value === "object") {
    const entries = Object.entries(value as Record<string, unknown>)
      .filter(([, entryValue]) => entryValue !== undefined)
      .sort(([left], [right]) => (left < right ? -1 : left > right ? 1 : 0));
    return `{${entries.map(([key, entryValue]) => `${JSON.stringify(key)}:${canonicalJson(entryValue)}`).join(",")}}`;
  }
  throw new OfflineDumpError(
    "nondeterministic_output",
    `unsupported value of type ${typeof value}`,
  );
}

/** Dotted-decimal provider-id order ("2" < "4.5" < "10"), not lexicographic. */
export function compareProviderHadithIds(left: string, right: string): number {
  const leftParts = left.split(".").map(Number);
  const rightParts = right.split(".").map(Number);
  const length = Math.max(leftParts.length, rightParts.length);
  for (let index = 0; index < length; index += 1) {
    const leftPart = leftParts[index] ?? 0;
    const rightPart = rightParts[index] ?? 0;
    if (leftPart !== rightPart) return leftPart - rightPart;
  }
  return 0;
}

export type DumpRowInput = Omit<OfflineDumpHadith, "canonicalId"> & {
  // canonicalId is derived, never caller-supplied, so identity cannot drift.
  providerHadithId: string;
};

export type DumpOutline = {
  volumes: Array<{
    volumeId: string;
    chapters?: Array<{ chapterId?: string }>;
  }>;
};

/**
 * Fail-closed row validation. Throws on collection mismatch, malformed
 * slugs/ids, canonical-id drift, duplicate provider ids, empty Arabic text,
 * unknown grades, or volume/chapter references missing from the outline.
 */
export function validateDumpRows(
  collectionSlug: string,
  rows: DumpRowInput[],
  outline: DumpOutline,
): void {
  if (!COLLECTION_SLUG_PATTERN.test(collectionSlug)) {
    throw new OfflineDumpError("bad_reference", `invalid slug ${collectionSlug}`);
  }
  const volumes = new Map<string, Set<string | undefined>>();
  for (const volume of outline.volumes) {
    const chapters = new Set<string | undefined>(
      (volume.chapters ?? []).map((chapter) => chapter.chapterId),
    );
    volumes.set(volume.volumeId, chapters);
  }
  const seen = new Set<string>();
  for (const row of rows) {
    if (row.collectionSlug !== collectionSlug) {
      throw new OfflineDumpError(
        "bad_reference",
        `row ${row.providerHadithId} belongs to ${row.collectionSlug}, not ${collectionSlug}`,
      );
    }
    if (!PROVIDER_HADITH_ID_PATTERN.test(row.providerHadithId)) {
      throw new OfflineDumpError(
        "bad_reference",
        `invalid provider hadith id ${row.providerHadithId}`,
      );
    }
    if (seen.has(row.providerHadithId)) {
      throw new OfflineDumpError(
        "duplicate_provider_id",
        `duplicate provider hadith id ${row.providerHadithId}`,
      );
    }
    seen.add(row.providerHadithId);
    if (row.arabicText.length === 0) {
      throw new OfflineDumpError(
        "bad_reference",
        `empty Arabic text for ${row.providerHadithId}`,
      );
    }
    const grade =
      row.authenticity.kind === "unverified"
        ? "unknown"
        : row.authenticity.normalizedGrade;
    if (!VALID_GRADES.has(grade)) {
      throw new OfflineDumpError(
        "invalid_grade",
        `unknown grade for ${row.providerHadithId}`,
      );
    }
    if (row.volumeId !== undefined) {
      const chapters = volumes.get(row.volumeId);
      if (!chapters) {
        throw new OfflineDumpError(
          "bad_reference",
          `unknown volume ${row.volumeId} for ${row.providerHadithId}`,
        );
      }
      if (
        row.chapterId !== undefined &&
        ![...chapters].some((chapterId) => chapterId === row.chapterId)
      ) {
        throw new OfflineDumpError(
          "bad_reference",
          `unknown chapter ${row.chapterId} in volume ${row.volumeId}`,
        );
      }
    }
  }
}

/** Canonical rows payload: sorted, identity-complete, ready to hash/version. */
export function canonicalRowsPayload(
  collectionSlug: string,
  rows: DumpRowInput[],
  outline: DumpOutline,
): string {
  validateDumpRows(collectionSlug, rows, outline);
  const ordered = [...rows].sort((left, right) =>
    compareProviderHadithIds(left.providerHadithId, right.providerHadithId),
  );
  const withIdentity: OfflineDumpHadith[] = ordered.map((row) => ({
    ...row,
    canonicalId: `${row.provider}:${row.collectionSlug}:${row.providerHadithId}`,
  }));
  return canonicalJson(withIdentity);
}

export function contentVersionForPayload(payload: string, hashHex: string): string {
  if (payload.length === 0) {
    throw new OfflineDumpError("bad_reference", "cannot version an empty dump");
  }
  if (!SHA256_HEX_PATTERN.test(hashHex)) {
    throw new OfflineDumpError("bad_reference", "content hash must be SHA-256 hex");
  }
  return `${OFFLINE_DUMP_CONTENT_MODEL}:${hashHex}`;
}

export type LicenseDescriptor = Infer<typeof licenseRecordDescriptorValidator>;

export function assertOfflineLicense(descriptor: LicenseDescriptor): void {
  if (descriptor.terms.kind !== "verified") {
    throw new OfflineDumpError(
      "missing_license",
      `${descriptor.sourceKey} has no verified license record`,
    );
  }
  if (
    descriptor.terms.permitsDisplay !== true ||
    descriptor.terms.permitsOfflineDistribution !== true
  ) {
    throw new OfflineDumpError(
      "unlicensed_source",
      `${descriptor.sourceKey} does not permit offline distribution`,
    );
  }
  if (descriptor.sourceName.length === 0 || descriptor.sourceUrl.length === 0) {
    throw new OfflineDumpError("missing_license", "license record lacks source identity");
  }
}

export function buildBaseDump(args: {
  collectionSlug: string;
  collectionName: string;
  contentVersion: string;
  generatedAt: number;
  license: LicenseDescriptor;
  rowsPayload: string;
}): BaseDump {
  assertOfflineLicense(args.license);
  if (!Number.isFinite(args.generatedAt) || args.generatedAt <= 0) {
    throw new OfflineDumpError("bad_reference", "generatedAt must be a positive timestamp");
  }
  const hadiths = JSON.parse(args.rowsPayload) as OfflineDumpHadith[];
  return {
    format: BASE_DUMP_FORMAT,
    schemaVersion: OFFLINE_DUMP_SCHEMA_VERSION,
    collectionSlug: args.collectionSlug,
    collectionName: args.collectionName,
    contentVersion: args.contentVersion,
    generatedAt: args.generatedAt,
    license: args.license,
    hadiths,
  };
}

/**
 * Serialize + determinism tripwire: parse the bytes back and require
 * byte-identical re-serialization. Any key-ordering or encoding bug fails
 * the build instead of shipping drifting content versions.
 */
export function serializeDeterministic(document: unknown): string {
  const first = canonicalJson(document);
  const second = canonicalJson(JSON.parse(first));
  if (first !== second) {
    throw new OfflineDumpError(
      "nondeterministic_output",
      "re-serialization produced different bytes",
    );
  }
  return first;
}

export function validatePackEntries(
  collectionSlug: string,
  entries: TranslationPackEntry[],
): void {
  const seen = new Set<string>();
  for (const entry of entries) {
    const parts = entry.canonicalId.split(":");
    if (
      parts.length !== 3 ||
      parts[0].length === 0 ||
      parts[1] !== collectionSlug ||
      !PROVIDER_HADITH_ID_PATTERN.test(parts[2])
    ) {
      throw new OfflineDumpError(
        "bad_reference",
        `pack entry ${entry.canonicalId} does not belong to ${collectionSlug}`,
      );
    }
    if (entry.language.length === 0 || entry.language.length > 35) {
      throw new OfflineDumpError(
        "bad_reference",
        `invalid language for ${entry.canonicalId}`,
      );
    }
    if (entry.content.length === 0) {
      throw new OfflineDumpError(
        "bad_reference",
        `empty content for ${entry.canonicalId}`,
      );
    }
    if (seen.has(entry.canonicalId)) {
      throw new OfflineDumpError(
        "duplicate_provider_id",
        `duplicate pack entry ${entry.canonicalId}`,
      );
    }
    seen.add(entry.canonicalId);
  }
}

export function buildTranslationPack(args: {
  collectionSlug: string;
  language: string;
  baseContentVersion: string;
  contentVersion: string;
  generatedAt: number;
  license: LicenseDescriptor;
  entries: TranslationPackEntry[];
}): TranslationPack {
  assertOfflineLicense(args.license);
  if (!Number.isFinite(args.generatedAt) || args.generatedAt <= 0) {
    throw new OfflineDumpError("bad_reference", "generatedAt must be a positive timestamp");
  }
  const ordered = [...args.entries].sort((left, right) =>
    left.canonicalId < right.canonicalId
      ? -1
      : left.canonicalId > right.canonicalId
        ? 1
        : 0,
  );
  validatePackEntries(args.collectionSlug, ordered);
  return {
    format: TRANSLATION_PACK_FORMAT,
    schemaVersion: OFFLINE_DUMP_SCHEMA_VERSION,
    collectionSlug: args.collectionSlug,
    language: args.language,
    baseContentVersion: args.baseContentVersion,
    contentVersion: args.contentVersion,
    generatedAt: args.generatedAt,
    license: args.license,
    entries: ordered,
  };
}

export function buildManifest(args: {
  kind: "base" | "pack";
  collectionSlug: string;
  locale?: string;
  contentVersion: string;
  baseContentVersion?: string;
  byteSize: number;
  sha256: string;
  generatedAt: number;
  license: LicenseDescriptor;
  compatiblePacks: string[];
  storageId: string;
}): OfflineManifest {
  assertOfflineLicense(args.license);
  if (!Number.isInteger(args.byteSize) || args.byteSize <= 0) {
    throw new OfflineDumpError("bad_reference", "byteSize must be a positive integer");
  }
  if (!SHA256_HEX_PATTERN.test(args.sha256)) {
    throw new OfflineDumpError("bad_reference", "sha256 must be 64 lowercase hex chars");
  }
  if (!SEMVER_PATTERN.test(OFFLINE_MIN_APP_VERSION)) {
    throw new OfflineDumpError("bad_reference", "min app version is malformed");
  }
  if (args.kind === "pack" && args.baseContentVersion === undefined) {
    throw new OfflineDumpError(
      "incompatible_pack",
      "translation pack manifest requires a base content version",
    );
  }
  return {
    format: OFFLINE_MANIFEST_FORMAT,
    schemaVersion: OFFLINE_DUMP_SCHEMA_VERSION,
    kind: args.kind,
    collectionSlug: args.collectionSlug,
    ...(args.locale !== undefined ? { locale: args.locale } : {}),
    contentVersion: args.contentVersion,
    ...(args.baseContentVersion !== undefined
      ? { baseContentVersion: args.baseContentVersion }
      : {}),
    byteSize: args.byteSize,
    sha256: args.sha256,
    minAppVersion: OFFLINE_MIN_APP_VERSION,
    generatedAt: args.generatedAt,
    license: args.license,
    compatiblePacks: args.compatiblePacks,
    storageId: args.storageId as OfflineManifest["storageId"],
  };
}

/**
 * Wire shape for an untrusted manifest document, exactly what the native
 * decoders parse before validation. Deliberately wider than
 * OfflineManifest so corrupt payloads stay representable at the boundary.
 */
export type OfflineManifestWire = {
  format: string;
  schemaVersion: number;
  kind: string;
  collectionSlug: string;
  locale?: string;
  contentVersion: string;
  baseContentVersion?: string;
  byteSize: number;
  sha256: string;
  minAppVersion: string;
  generatedAt: number;
  license: LicenseDescriptor;
  compatiblePacks: string[];
};

/**
 * Client-side activation gate, mirrored in Swift and Kotlin: reject
 * unsupported schemas, unlicensed manifests, and byte/hash mismatches
 * before anything touches disk. Throws instead of returning false so
 * callers cannot ignore the reason.
 */
export function assertManifestForBytes(args: {
  manifest: OfflineManifestWire;
  actualByteSize: number;
  actualSha256: string;
  expectedBaseContentVersion?: string;
}): void {
  if (args.manifest.format !== OFFLINE_MANIFEST_FORMAT) {
    throw new OfflineDumpError(
      "bad_reference",
      `unexpected manifest format ${args.manifest.format}`,
    );
  }
  if (args.manifest.kind !== "base" && args.manifest.kind !== "pack") {
    throw new OfflineDumpError(
      "bad_reference",
      `unexpected manifest kind ${args.manifest.kind}`,
    );
  }
  if (args.manifest.schemaVersion !== OFFLINE_DUMP_SCHEMA_VERSION) {
    throw new OfflineDumpError(
      "unsupported_schema",
      `schema ${args.manifest.schemaVersion}, client supports ${OFFLINE_DUMP_SCHEMA_VERSION}`,
    );
  }
  assertOfflineLicense(args.manifest.license);
  if (args.actualByteSize !== args.manifest.byteSize) {
    throw new OfflineDumpError(
      "checksum_mismatch",
      `byte size ${args.actualByteSize} != manifest ${args.manifest.byteSize}`,
    );
  }
  if (args.actualSha256 !== args.manifest.sha256) {
    throw new OfflineDumpError("checksum_mismatch", "SHA-256 does not match manifest");
  }
  if (
    args.manifest.kind === "pack" &&
    args.expectedBaseContentVersion !== undefined &&
    args.manifest.baseContentVersion !== args.expectedBaseContentVersion
  ) {
    throw new OfflineDumpError(
      "incompatible_pack",
      `pack targets ${args.manifest.baseContentVersion}, base is ${args.expectedBaseContentVersion}`,
    );
  }
}
