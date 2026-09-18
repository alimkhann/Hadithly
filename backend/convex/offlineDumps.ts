import { internalMutation, internalQuery, query } from "./_generated/server";
import { v } from "convex/values";
import type { Doc } from "./_generated/dataModel";
import {
  OFFLINE_DUMP_SCHEMA_VERSION,
  OFFLINE_MANIFEST_FORMAT,
} from "./lib/offlineDumps";
import type { OfflineManifestView } from "./lib/offlineDumps";

/**
 * O1 offline manifests. All reads are public and identity-free (cached
 * collection content works signed out, matching the reader contract).
 * Generation lives in `actions/offlineDumps.ts`; this file owns the
 * manifest rows and their public views.
 */

export const getLicenseBySourceKey = internalQuery({
  args: { sourceKey: v.string() },
  handler: async (ctx, args) =>
    await ctx.db
      .query("licenseRecords")
      .withIndex("by_source_key", (q) => q.eq("sourceKey", args.sourceKey))
      .unique(),
});

/**
 * Records the verified Sunnah.now offline assessment. Evidence (checked
 * 2026-09-18): the provider's invite email and https://docs.sunnah.now
 * license section state the project is MIT-licensed and "free to use
 * locally"; the database README
 * (https://github.com/sunnah-now/database) states its files "can also be
 * used for offline use cases" and ships versioned release dumps.
 * Caveat: the data repo carries no SPDX LICENSE file
 * (GitHub `license: null`), so general redistribution is NOT granted —
 * permitsRedistribution stays false. E3 owns the production-grade license
 * confirmation; a later verified record is never overwritten here.
 */
export const recordSunnahNowLicense = internalMutation({
  args: {},
  handler: async (ctx) => {
    const now = Date.now();
    const existing = await ctx.db
      .query("licenseRecords")
      .withIndex("by_source_key", (q) => q.eq("sourceKey", "sunnah_now"))
      .unique();
    if (existing) {
      if (existing.terms.kind === "verified") return existing._id;
      await ctx.db.patch(existing._id, {
        terms: {
          kind: "verified",
          licenseName: "Sunnah.now early-access data grant",
          licenseUrl: "https://github.com/sunnah-now/database",
          permitsDisplay: true,
          permitsRedistribution: false,
          permitsOfflineDistribution: true,
          verifiedAt: now,
        },
        updatedAt: now,
      });
      return existing._id;
    }
    return await ctx.db.insert("licenseRecords", {
      sourceKey: "sunnah_now",
      sourceName: "Sunnah.now",
      sourceUrl: "https://sunnah.now",
      terms: {
        kind: "verified",
        licenseName: "Sunnah.now early-access data grant",
        licenseUrl: "https://github.com/sunnah-now/database",
        permitsDisplay: true,
        permitsRedistribution: false,
        permitsOfflineDistribution: true,
        verifiedAt: now,
      },
      createdAt: now,
      updatedAt: now,
    });
  },
});

/** Internal: live default translations for one language, joined to hadiths. */
export const listLiveDefaultsForLanguage = internalQuery({
  args: { language: v.string() },
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("translations")
      .withIndex("by_language_status_default", (q) =>
        q
          .eq("language", args.language)
          .eq("status", "live")
          .eq("isDefault", true),
      )
      .collect();
    const withHadiths = [];
    for (const row of rows) {
      const hadith = await ctx.db.get(row.hadithId);
      if (hadith) withHadiths.push({ translation: row, hadith });
    }
    return withHadiths;
  },
});

/**
 * Internal: idempotent artifact upsert. The generation action computes the
 * content version BEFORE storing bytes and calls this first; a matching
 * row means the bytes already exist and no new blob is stored.
 */
export const upsertArtifact = internalMutation({
  args: {
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
  },
  handler: async (ctx, args) => {
    const now = Date.now();
    const candidates = await ctx.db
      .query("offlineArtifacts")
      .withIndex("by_kind_collection", (q) =>
        q.eq("kind", args.kind).eq("collectionSlug", args.collectionSlug),
      )
      .collect();
    const existing = candidates.find(
      (row) =>
        (row.locale ?? undefined) === (args.locale ?? undefined) &&
        row.contentVersion === args.contentVersion,
    );
    if (existing) return existing._id;
    return await ctx.db.insert("offlineArtifacts", {
      ...args,
      createdAt: now,
      updatedAt: now,
    });
  },
});

export const latestArtifact = internalQuery({
  args: {
    kind: v.union(v.literal("base"), v.literal("pack")),
    collectionSlug: v.string(),
    locale: v.optional(v.string()),
  },
  handler: async (ctx, args) => {
    const rows = await ctx.db
      .query("offlineArtifacts")
      .withIndex("by_kind_collection", (q) =>
        q.eq("kind", args.kind).eq("collectionSlug", args.collectionSlug),
      )
      .collect();
    const scoped = rows.filter(
      (row) => (row.locale ?? undefined) === (args.locale ?? undefined),
    );
    scoped.sort((left, right) => right.generatedAt - left.generatedAt);
    return scoped[0] ?? null;
  },
});

async function manifestView(
  ctx: QueryCtx,
  artifact: Doc<"offlineArtifacts">,
): Promise<OfflineManifestView | null> {
  const license = await ctx.db.get(artifact.licenseRecordId);
  if (!license) return null;
  const downloadUrl = await ctx.storage.getUrl(artifact.storageId);
  if (!downloadUrl) return null;
  const view: OfflineManifestView = {
    format: OFFLINE_MANIFEST_FORMAT,
    schemaVersion: OFFLINE_DUMP_SCHEMA_VERSION,
    kind: artifact.kind,
    collectionSlug: artifact.collectionSlug,
    ...(artifact.locale !== undefined ? { locale: artifact.locale } : {}),
    contentVersion: artifact.contentVersion,
    ...(artifact.baseContentVersion !== undefined
      ? { baseContentVersion: artifact.baseContentVersion }
      : {}),
    byteSize: artifact.byteSize,
    sha256: artifact.sha256,
    minAppVersion: artifact.minAppVersion,
    generatedAt: artifact.generatedAt,
    license: {
      sourceKey: license.sourceKey,
      sourceName: license.sourceName,
      sourceUrl: license.sourceUrl,
      terms: license.terms,
    },
    compatiblePacks: artifact.compatiblePacks,
    downloadUrl,
  };
  return view;
}

/** Public: latest base-dump manifest for one collection, or null. */
export const getBaseManifest = query({
  args: { collectionSlug: v.string() },
  handler: async (ctx, args): Promise<OfflineManifestView | null> => {
    const rows = await ctx.db
      .query("offlineArtifacts")
      .withIndex("by_kind_collection", (q) =>
        q.eq("kind", "base").eq("collectionSlug", args.collectionSlug),
      )
      .collect();
    rows.sort((left, right) => right.generatedAt - left.generatedAt);
    const latest = rows[0];
    if (!latest) return null;
    return await manifestView(ctx, latest);
  },
});

/** Public: latest translation-pack manifest, or null. */
export const getPackManifest = query({
  args: { collectionSlug: v.string(), locale: v.string() },
  handler: async (ctx, args): Promise<OfflineManifestView | null> => {
    const rows = await ctx.db
      .query("offlineArtifacts")
      .withIndex("by_kind_collection", (q) =>
        q.eq("kind", "pack").eq("collectionSlug", args.collectionSlug),
      )
      .collect();
    const scoped = rows.filter((row) => row.locale === args.locale);
    scoped.sort((left, right) => right.generatedAt - left.generatedAt);
    const latest = scoped[0];
    if (!latest) return null;
    return await manifestView(ctx, latest);
  },
});

/**
 * Public: latest base manifests for every collection plus, when a
 * translation locale is given, the matching packs. One call drives the O2
 * storage screen without N+1 queries.
 */
export const getOfflineManifests = query({
  args: { translationLocale: v.optional(v.string()) },
  handler: async (ctx, args) => {
    const bases = await ctx.db
      .query("offlineArtifacts")
      .withIndex("by_kind_collection", (q) => q.eq("kind", "base"))
      .collect();
    const latestByCollection = new Map<string, Doc<"offlineArtifacts">>();
    for (const row of bases) {
      const current = latestByCollection.get(row.collectionSlug);
      if (!current || row.generatedAt > current.generatedAt) {
        latestByCollection.set(row.collectionSlug, row);
      }
    }
    const baseViews: OfflineManifestView[] = [];
    for (const artifact of latestByCollection.values()) {
      const view = await manifestView(ctx, artifact);
      if (view) baseViews.push(view);
    }
    baseViews.sort((left, right) =>
      left.collectionSlug < right.collectionSlug ? -1 : 1,
    );

    const packViews: OfflineManifestView[] = [];
    if (args.translationLocale) {
      const packs = await ctx.db
        .query("offlineArtifacts")
        .withIndex("by_kind_collection", (q) => q.eq("kind", "pack"))
        .collect();
      const latestPack = new Map<string, Doc<"offlineArtifacts">>();
      for (const row of packs) {
        if (row.locale !== args.translationLocale) continue;
        const key = row.collectionSlug;
        const current = latestPack.get(key);
        if (!current || row.generatedAt > current.generatedAt) {
          latestPack.set(key, row);
        }
      }
      for (const artifact of latestPack.values()) {
        const view = await manifestView(ctx, artifact);
        if (view) packViews.push(view);
      }
      packViews.sort((left, right) =>
        left.collectionSlug < right.collectionSlug ? -1 : 1,
      );
    }
    return { bases: baseViews, packs: packViews };
  },
});

type QueryCtx = import("./_generated/server").QueryCtx;
