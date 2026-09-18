"use node";

/**
 * O1 offline dump generation — the only place dump bytes are built.
 * Reads cached hadiths/outlines/translations, validates fail-closed,
 * stores immutable JSON in Convex storage, and upserts manifest rows.
 *
 * Determinism: row ordering, canonical JSON, and content versions depend
 * only on table contents plus the injected `generatedAt`. Two runs over
 * unchanged data with the same `generatedAt` produce identical bytes and
 * hashes; the upsert then reuses the existing row instead of storing a
 * second blob (idempotent publish).
 */

import { createHash } from "node:crypto";
import { v } from "convex/values";
import { action } from "../_generated/server";
import { api, internal } from "../_generated/api";
import {
  OFFLINE_MIN_APP_VERSION,
  OfflineDumpError,
  assertOfflineLicense,
  buildBaseDump,
  buildManifest,
  buildTranslationPack,
  canonicalJson,
  canonicalRowsPayload,
  contentVersionForPayload,
  serializeDeterministic,
} from "../lib/offlineDumps";
import type {
  DumpRowInput,
  LicenseDescriptor,
  TranslationPackEntry,
} from "../lib/offlineDumps";
import { canonicalHadithIdentity } from "../lib/contentPolicy";
import type { Id } from "../_generated/dataModel";

export type DumpGenerationSummary = {
  base: {
    collectionSlug: string;
    contentVersion: string;
    sha256: string;
    byteSize: number;
    hadithCount: number;
    reused: boolean;
  };
  packs: Array<{
    locale: string;
    contentVersion: string;
    sha256: string;
    byteSize: number;
    entryCount: number;
    reused: boolean;
  }>;
};

function sha256Hex(input: string): string {
  return createHash("sha256").update(input, "utf8").digest("hex");
}

async function loadLicense(
  ctx: ActionCtx,
  sourceKey: string,
): Promise<{ descriptor: LicenseDescriptor; recordId: Id<"licenseRecords"> }> {
  const record = await ctx.runQuery(
    internal.offlineDumps.getLicenseBySourceKey,
    { sourceKey },
  );
  if (!record) {
    throw new OfflineDumpError(
      "missing_license",
      `no license record for ${sourceKey}`,
    );
  }
  const descriptor: LicenseDescriptor = {
    sourceKey: record.sourceKey,
    sourceName: record.sourceName,
    sourceUrl: record.sourceUrl,
    terms: record.terms,
  };
  // Fail closed before any bytes are built.
  assertOfflineLicense(descriptor);
  return { descriptor, recordId: record._id };
}

export const generateCollectionDump = action({
  args: {
    collectionSlug: v.string(),
    translationLocales: v.array(v.string()),
    // Injected (never Date.now() inside the builders) so a rebuild over
    // unchanged data reproduces byte-identical artifacts.
    generatedAt: v.optional(v.number()),
  },
  handler: async (ctx, args): Promise<DumpGenerationSummary> => {
    const generatedAt = args.generatedAt ?? Date.now();
    const { descriptor: license, recordId: licenseRecordId } =
      await loadLicense(ctx, "sunnah_now");

    const hadiths = await ctx.runQuery(internal.hadiths.listByCollection, {
      provider: "sunnah_now",
      collectionSlug: args.collectionSlug,
    });
    if (hadiths.length === 0) {
      throw new OfflineDumpError(
        "bad_reference",
        `no cached hadiths for ${args.collectionSlug}`,
      );
    }
    const outline = await ctx.runQuery(api.collections.getOutline, {
      collectionSlug: args.collectionSlug,
    });
    if (!outline) {
      throw new OfflineDumpError(
        "bad_reference",
        `no collection outline for ${args.collectionSlug}`,
      );
    }

    const rows: DumpRowInput[] = hadiths.map((hadith) => ({
      provider: hadith.provider,
      collectionSlug: hadith.collectionSlug,
      providerHadithId: hadith.providerHadithId,
      ...(hadith.volumeId !== undefined ? { volumeId: hadith.volumeId } : {}),
      ...(hadith.chapterId !== undefined ? { chapterId: hadith.chapterId } : {}),
      arabicText: hadith.arabicText,
      ...(hadith.englishText !== undefined
        ? { englishText: hadith.englishText }
        : {}),
      ...(hadith.narrator !== undefined ? { narrator: hadith.narrator } : {}),
      ...(hadith.narratorAr !== undefined
        ? { narratorAr: hadith.narratorAr }
        : {}),
      referenceDisplay: hadith.referenceDisplay,
      collectionName: hadith.collectionName,
      ...(hadith.bookName !== undefined ? { bookName: hadith.bookName } : {}),
      ...(hadith.chapterName !== undefined
        ? { chapterName: hadith.chapterName }
        : {}),
      authenticity: hadith.authenticity,
    }));

    const rowsPayload = canonicalRowsPayload(args.collectionSlug, rows, {
      volumes: outline.volumes.map((volume) => ({
        volumeId: volume.volumeId,
        chapters: volume.chapters,
      })),
    });
    const baseContentVersion = contentVersionForPayload(
      rowsPayload,
      sha256Hex(rowsPayload),
    );

    const existingBase = await ctx.runQuery(internal.offlineDumps.latestArtifact, {
      kind: "base",
      collectionSlug: args.collectionSlug,
    });
    const baseReused =
      existingBase !== null && existingBase.contentVersion === baseContentVersion;

    let baseSha256: string;
    let baseBytes: string;
    if (baseReused && existingBase !== null) {
      baseSha256 = existingBase.sha256;
      baseBytes = "";
    } else {
      const baseDoc = buildBaseDump({
        collectionSlug: args.collectionSlug,
        collectionName: hadiths[0].collectionName,
        contentVersion: baseContentVersion,
        generatedAt,
        license,
        rowsPayload,
      });
      baseBytes = serializeDeterministic(baseDoc);
      baseSha256 = sha256Hex(baseBytes);
    }

    // Translation packs bind to this base content version.
    const packSummaries: DumpGenerationSummary["packs"] = [];
    const packContentVersions: string[] = [];
    for (const locale of args.translationLocales) {
      const liveDefaults = await ctx.runQuery(
        internal.offlineDumps.listLiveDefaultsForLanguage,
        { language: locale },
      );
      const entries: TranslationPackEntry[] = [];
      for (const { translation, hadith } of liveDefaults) {
        if (hadith.collectionSlug !== args.collectionSlug) continue;
        const identity = canonicalHadithIdentity({
          provider: hadith.provider,
          collectionSlug: hadith.collectionSlug,
          providerHadithId: hadith.providerHadithId,
        });
        entries.push({
          canonicalId: identity.canonicalId,
          language: translation.language,
          content: translation.content,
          source: translation.source,
          sourceLabel: translation.sourceLabel,
        });
      }
      entries.sort((left, right) =>
        left.canonicalId < right.canonicalId ? -1 : 1,
      );
      if (entries.length === 0) {
        // No live default translations: nothing to pack, and the native
        // decoders reject empty packs. The base dump still publishes.
        continue;
      }
      const packContentVersion = contentVersionForPayload(
        canonicalJson(entries),
        sha256Hex(canonicalJson(entries)),
      );
      packContentVersions.push(packContentVersion);

      const existingPack = await ctx.runQuery(
        internal.offlineDumps.latestArtifact,
        {
          kind: "pack",
          collectionSlug: args.collectionSlug,
          locale,
        },
      );
      if (
        existingPack !== null &&
        existingPack.contentVersion === packContentVersion
      ) {
        packSummaries.push({
          locale,
          contentVersion: packContentVersion,
          sha256: existingPack.sha256,
          byteSize: existingPack.byteSize,
          entryCount: entries.length,
          reused: true,
        });
        continue;
      }
      const packDoc = buildTranslationPack({
        collectionSlug: args.collectionSlug,
        language: locale,
        baseContentVersion,
        contentVersion: packContentVersion,
        generatedAt,
        license,
        entries,
      });
      const packBytes = serializeDeterministic(packDoc);
      const packSha = sha256Hex(packBytes);
      const packStorageId = await ctx.storage.store(
        new Blob([packBytes], { type: "application/json" }),
      );
      await ctx.runMutation(internal.offlineDumps.upsertArtifact, {
        kind: "pack",
        collectionSlug: args.collectionSlug,
        locale,
        schemaVersion: packDoc.schemaVersion,
        contentVersion: packContentVersion,
        baseContentVersion,
        storageId: packStorageId,
        sha256: packSha,
        byteSize: Buffer.byteLength(packBytes, "utf8"),
        minAppVersion: OFFLINE_MIN_APP_VERSION,
        generatedAt,
        licenseRecordId,
        compatiblePacks: [baseContentVersion],
      });
      packSummaries.push({
        locale,
        contentVersion: packContentVersion,
        sha256: packSha,
        byteSize: Buffer.byteLength(packBytes, "utf8"),
        entryCount: entries.length,
        reused: false,
      });
    }

    let finalBaseSha = baseSha256;
    let finalBaseBytes = baseBytes.length;
    let baseStorageId = existingBase?.storageId;
    if (!baseReused) {
      baseStorageId = await ctx.storage.store(
        new Blob([baseBytes], { type: "application/json" }),
      );
      finalBaseBytes = Buffer.byteLength(baseBytes, "utf8");
      await ctx.runMutation(internal.offlineDumps.upsertArtifact, {
        kind: "base",
        collectionSlug: args.collectionSlug,
        schemaVersion: 1,
        contentVersion: baseContentVersion,
        storageId: baseStorageId,
        sha256: baseSha256,
        byteSize: finalBaseBytes,
        minAppVersion: OFFLINE_MIN_APP_VERSION,
        generatedAt,
        licenseRecordId,
        compatiblePacks: packContentVersions,
      });
    } else if (existingBase !== null) {
      finalBaseBytes = existingBase.byteSize;
    }

    // The manifest itself is validated at publish time so a malformed
    // descriptor can never reach clients.
    if (baseStorageId !== undefined) {
      buildManifest({
        kind: "base",
        collectionSlug: args.collectionSlug,
        contentVersion: baseContentVersion,
        byteSize: finalBaseBytes,
        sha256: finalBaseSha,
        generatedAt,
        license,
        compatiblePacks: packContentVersions,
        storageId: baseStorageId,
      });
    }

    return {
      base: {
        collectionSlug: args.collectionSlug,
        contentVersion: baseContentVersion,
        sha256: finalBaseSha,
        byteSize: finalBaseBytes,
        hadithCount: hadiths.length,
        reused: baseReused,
      },
      packs: packSummaries,
    };
  },
});

type ActionCtx = import("../_generated/server").ActionCtx;
