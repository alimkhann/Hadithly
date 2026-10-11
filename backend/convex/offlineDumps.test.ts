/// <reference types="vite/client" />

import { createHash } from "node:crypto";
import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import {
  OFFLINE_DUMP_SCHEMA_VERSION,
  OfflineDumpError,
  assertManifestForBytes,
  assertOfflineLicense,
  buildBaseDump,
  buildManifest,
  buildTranslationPack,
  canonicalJson,
  canonicalRowsPayload,
  compareProviderHadithIds,
  contentVersionForPayload,
  serializeDeterministic,
  validatePackEntries,
} from "./lib/offlineDumps";
import type {
  DumpRowInput,
  LicenseDescriptor,
  OfflineManifestWire,
  TranslationPackEntry,
} from "./lib/offlineDumps";

const modules = import.meta.glob("./**/*.ts");

function sha256Hex(input: string): string {
  return createHash("sha256").update(input, "utf8").digest("hex");
}

const verifiedLicense: LicenseDescriptor = {
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
    verifiedAt: 1_700_000_000_000,
  },
};

const unverifiedLicense: LicenseDescriptor = {
  sourceKey: "sunnah_now",
  sourceName: "Sunnah.now",
  sourceUrl: "https://sunnah.now",
  terms: { kind: "unverified" },
};

const collectionScope = {
  kind: "collection_scope",
  normalizedGrade: "sahih",
  claimScope: "collection",
  sourceLabel: "Documented Sahih collection",
  sourceName: "Sunnah.now",
  sourceUrl: "https://sunnah.now",
  verificationMethod: "manual_collection_mapping",
} as const;

function makeRow(overrides: Partial<DumpRowInput> = {}): DumpRowInput {
  return {
    provider: "sunnah_now",
    collectionSlug: "bukhari",
    providerHadithId: "7",
    volumeId: "2",
    chapterId: "42",
    arabicText: "نص الحديث",
    englishText: "Hadith text",
    narrator: "Narrated Aisha",
    referenceDisplay: "Sahih al-Bukhari · Hadith 7",
    collectionName: "Sahih al-Bukhari",
    chapterName: "Chapter of faith",
    authenticity: { ...collectionScope },
    ...overrides,
  };
}

const outline = {
  volumes: [{ volumeId: "2", chapters: [{ chapterId: "42" }] }],
};

function buildGolden(): { bytes: string; contentVersion: string } {
  const rows = [
    makeRow({ providerHadithId: "10", arabicText: "عاشر" }),
    makeRow({ providerHadithId: "2", arabicText: "ثان" }),
    makeRow(),
  ];
  const payload = canonicalRowsPayload("bukhari", rows, outline);
  const contentVersion = contentVersionForPayload(payload, sha256Hex(payload));
  const doc = buildBaseDump({
    collectionSlug: "bukhari",
    collectionName: "Sahih al-Bukhari",
    contentVersion,
    generatedAt: 1_700_000_000_000,
    license: verifiedLicense,
    rowsPayload: payload,
  });
  return { bytes: serializeDeterministic(doc), contentVersion };
}

function expectDumpError(fn: () => void, code: string): void {
  try {
    fn();
  } catch (error) {
    expect(error).toBeInstanceOf(OfflineDumpError);
    expect((error as OfflineDumpError).code).toBe(code);
    return;
  }
  throw new Error(`expected OfflineDumpError ${code}`);
}

describe("offline dump determinism", () => {
  test("canonical JSON sorts keys and is stable", () => {
    expect(canonicalJson({ b: 1, a: [3, 2], n: { z: 1, a: 2 } })).toBe(
      '{"a":[3,2],"b":1,"n":{"a":2,"z":1}}',
    );
  });

  test("two repeated builds produce identical bytes and hashes", () => {
    const first = buildGolden();
    const second = buildGolden();
    expect(second.bytes).toBe(first.bytes);
    expect(second.contentVersion).toBe(first.contentVersion);
    expect(sha256Hex(first.bytes)).toBe(sha256Hex(second.bytes));
    expect(first.contentVersion).toMatch(/^od1:[0-9a-f]{64}$/);
  });

  test("provider ids order numerically, not lexicographically", () => {
    expect(compareProviderHadithIds("10", "2")).toBeGreaterThan(0);
    expect(compareProviderHadithIds("4.5", "4")).toBeGreaterThan(0);
    expect(compareProviderHadithIds("4.5", "5")).toBeLessThan(0);
    const rows = [
      makeRow({ providerHadithId: "10" }),
      makeRow({ providerHadithId: "4.5" }),
      makeRow({ providerHadithId: "2" }),
    ];
    const payload = canonicalRowsPayload("bukhari", rows, outline);
    const ids = (JSON.parse(payload) as Array<{ providerHadithId: string }>).map(
      (row) => row.providerHadithId,
    );
    expect(ids).toEqual(["2", "4.5", "10"]);
  });

  test("derived canonical ids match the F1 identity contract", () => {
    const payload = canonicalRowsPayload("bukhari", [makeRow()], outline);
    const rows = JSON.parse(payload) as Array<{ canonicalId: string }>;
    expect(rows[0].canonicalId).toBe("sunnah_now:bukhari:7");
  });
});

describe("offline dump fail-closed validation", () => {
  test("rejects duplicate provider ids", () => {
    expectDumpError(
      () => canonicalRowsPayload("bukhari", [makeRow(), makeRow()], outline),
      "duplicate_provider_id",
    );
  });

  test("accepts provider id 0 and orders it before 1", () => {
    // Sunnah.now serves real collection content (e.g. Muslim's Muqaddimah)
    // under id "0"; the dump must carry exactly what the reader shows.
    const payload = canonicalRowsPayload(
      "bukhari",
      [makeRow({ providerHadithId: "2" }), makeRow({ providerHadithId: "0" })],
      outline,
    );
    const ids = (JSON.parse(payload) as Array<{ providerHadithId: string }>).map(
      (row) => row.providerHadithId,
    );
    expect(ids).toEqual(["0", "2"]);
  });

  test.each(["abc", ".5", "7.", ""])(
    "rejects malformed provider id %s",
    (id) => {
      expectDumpError(
        () =>
          canonicalRowsPayload(
            "bukhari",
            [makeRow({ providerHadithId: id })],
            outline,
          ),
        "bad_reference",
      );
    },
  );

  test("rejects rows from another collection", () => {
    expectDumpError(
      () =>
        canonicalRowsPayload(
          "bukhari",
          [makeRow({ collectionSlug: "muslim" })],
          outline,
        ),
      "bad_reference",
    );
  });

  test("rejects empty Arabic text and unknown outline references", () => {
    expectDumpError(
      () =>
        canonicalRowsPayload("bukhari", [makeRow({ arabicText: "" })], outline),
      "bad_reference",
    );
    expectDumpError(
      () =>
        canonicalRowsPayload("bukhari", [makeRow({ volumeId: "9" })], outline),
      "bad_reference",
    );
    expectDumpError(
      () =>
        canonicalRowsPayload("bukhari", [makeRow({ chapterId: "99" })], outline),
      "bad_reference",
    );
  });

  test("rejects invalid grades", () => {
    expectDumpError(
      () =>
        canonicalRowsPayload(
          "bukhari",
          [
            makeRow({
              authenticity: {
                kind: "hadith_grade",
                normalizedGrade: "bogus",
                claimScope: "hadith",
                sourceLabel: "x",
                sourceName: "y",
                sourceUrl: "https://example.test",
                verificationMethod: "source_provided",
              } as never,
            }),
          ],
          outline,
        ),
      "invalid_grade",
    );
  });

  test("refuses to build dumps or manifests without a verified license", () => {
    const payload = canonicalRowsPayload("bukhari", [makeRow()], outline);
    expectDumpError(
      () =>
        buildBaseDump({
          collectionSlug: "bukhari",
          collectionName: "Sahih al-Bukhari",
          contentVersion: "od1:" + "0".repeat(64),
          generatedAt: 1,
          license: unverifiedLicense,
          rowsPayload: payload,
        }),
      "missing_license",
    );
    const offlineOnly = {
      ...verifiedLicense,
      terms: { ...verifiedLicense.terms, permitsOfflineDistribution: false },
    } as LicenseDescriptor;
    expect(() => assertOfflineLicense(offlineOnly)).toThrowError(
      expect.objectContaining({ code: "unlicensed_source" }),
    );
  });

  test("pack entries must be unique and belong to the collection", () => {
    const entry: TranslationPackEntry = {
      canonicalId: "sunnah_now:bukhari:7",
      language: "ur",
      content: "ترجمہ",
      source: "official",
      sourceLabel: "Official",
    };
    expect(() => validatePackEntries("bukhari", [entry])).not.toThrow();
    expectDumpError(
      () => validatePackEntries("bukhari", [entry, entry]),
      "duplicate_provider_id",
    );
    expectDumpError(
      () =>
        validatePackEntries("bukhari", [
          { ...entry, canonicalId: "sunnah_now:muslim:7" },
        ]),
      "bad_reference",
    );
  });

  test("pack manifest requires a base content version", () => {
    expectDumpError(
      () =>
        buildManifest({
          kind: "pack",
          collectionSlug: "bukhari",
          locale: "ur",
          contentVersion: "od1:" + "1".repeat(64),
          byteSize: 10,
          sha256: "2".repeat(64),
          generatedAt: 1,
          license: verifiedLicense,
          compatiblePacks: [],
          storageId: "x",
        }),
      "incompatible_pack",
    );
  });
});

describe("manifest activation gate", () => {
  function goldenManifest(): {
    manifest: OfflineManifestWire;
    bytes: string;
  } {
    const { bytes, contentVersion } = buildGolden();
    return {
      bytes,
      manifest: {
        format: "hadithly-offline-manifest",
        schemaVersion: OFFLINE_DUMP_SCHEMA_VERSION,
        kind: "base",
        collectionSlug: "bukhari",
        contentVersion,
        byteSize: Buffer.byteLength(bytes, "utf8"),
        sha256: sha256Hex(bytes),
        minAppVersion: "0.1.0",
        generatedAt: 1_700_000_000_000,
        license: verifiedLicense,
        compatiblePacks: [],
      },
    };
  }

  test("accepts matching bytes and hash", () => {
    const { manifest, bytes } = goldenManifest();
    expect(() =>
      assertManifestForBytes({
        manifest,
        actualByteSize: Buffer.byteLength(bytes, "utf8"),
        actualSha256: sha256Hex(bytes),
      }),
    ).not.toThrow();
  });

  test("corrupt bytes fail the checksum gate", () => {
    const { manifest, bytes } = goldenManifest();
    expectDumpError(
      () =>
        assertManifestForBytes({
          manifest,
          actualByteSize: Buffer.byteLength(bytes, "utf8") + 1,
          actualSha256: sha256Hex(bytes),
        }),
      "checksum_mismatch",
    );
    expectDumpError(
      () =>
        assertManifestForBytes({
          manifest,
          actualByteSize: Buffer.byteLength(bytes, "utf8"),
          actualSha256: "0".repeat(64),
        }),
      "checksum_mismatch",
    );
  });

  test("unsupported schema and unlicensed manifests fail", () => {
    const { manifest, bytes } = goldenManifest();
    expectDumpError(
      () =>
        assertManifestForBytes({
          manifest: { ...manifest, schemaVersion: 2 },
          actualByteSize: Buffer.byteLength(bytes, "utf8"),
          actualSha256: sha256Hex(bytes),
        }),
      "unsupported_schema",
    );
    expectDumpError(
      () =>
        assertManifestForBytes({
          manifest: { ...manifest, license: unverifiedLicense },
          actualByteSize: Buffer.byteLength(bytes, "utf8"),
          actualSha256: sha256Hex(bytes),
        }),
      "missing_license",
    );
  });

  test("incompatible pack fails against the active base", () => {
    const { contentVersion } = buildGolden();
    const packBytes = serializeDeterministic(
      buildTranslationPack({
        collectionSlug: "bukhari",
        language: "ur",
        baseContentVersion: contentVersion,
        contentVersion: `od1:${"3".repeat(64)}`,
        generatedAt: 1,
        license: verifiedLicense,
        entries: [
          {
            canonicalId: "sunnah_now:bukhari:7",
            language: "ur",
            content: "ترجمہ",
            source: "official",
            sourceLabel: "Official",
          },
        ],
      }),
    );
    const manifest: OfflineManifestWire = {
      format: "hadithly-offline-manifest",
      schemaVersion: OFFLINE_DUMP_SCHEMA_VERSION,
      kind: "pack",
      collectionSlug: "bukhari",
      locale: "ur",
      contentVersion: `od1:${"3".repeat(64)}`,
      baseContentVersion: contentVersion,
      byteSize: Buffer.byteLength(packBytes, "utf8"),
      sha256: sha256Hex(packBytes),
      minAppVersion: "0.1.0",
      generatedAt: 1,
      license: verifiedLicense,
      compatiblePacks: [contentVersion],
    };
    expect(() =>
      assertManifestForBytes({
        manifest,
        actualByteSize: Buffer.byteLength(packBytes, "utf8"),
        actualSha256: sha256Hex(packBytes),
        expectedBaseContentVersion: contentVersion,
      }),
    ).not.toThrow();
    expectDumpError(
      () =>
        assertManifestForBytes({
          manifest,
          actualByteSize: Buffer.byteLength(packBytes, "utf8"),
          actualSha256: sha256Hex(packBytes),
          expectedBaseContentVersion: `od1:${"9".repeat(64)}`,
        }),
      "incompatible_pack",
    );
  });
});

describe("offline artifact storage", () => {
  test("records the verified license once and never overwrites a verified row", async () => {
    const t = convexTest(schema, modules);
    const first = await t.mutation(
      internal.offlineDumps.recordSunnahNowLicense,
      {},
    );
    const stored = await t.run(async (ctx) => await ctx.db.get(first));
    expect(stored?.terms).toMatchObject({
      kind: "verified",
      permitsDisplay: true,
      permitsRedistribution: false,
      permitsOfflineDistribution: true,
    });

    // A later E3-grade record must survive a repeat run.
    const upgradedAt = 1_800_000_000_000;
    await t.run(async (ctx) => {
      if (!stored) throw new Error("missing license row");
      await ctx.db.patch(stored._id, {
        terms: {
          kind: "verified",
          licenseName: "Direct publisher agreement",
          licenseUrl: "https://example.test/agreement",
          permitsDisplay: true,
          permitsRedistribution: true,
          permitsOfflineDistribution: true,
          verifiedAt: upgradedAt,
        },
      });
    });
    const second = await t.mutation(
      internal.offlineDumps.recordSunnahNowLicense,
      {},
    );
    expect(second).toEqual(first);
    const kept = await t.run(async (ctx) => await ctx.db.get(first));
    expect(kept?.terms).toMatchObject({
      licenseName: "Direct publisher agreement",
      verifiedAt: upgradedAt,
    });
  });

  test("artifact upsert is idempotent on content version", async () => {
    const t = convexTest(schema, modules);
    const licenseId = await t.mutation(
      internal.offlineDumps.recordSunnahNowLicense,
      {},
    );
    const probe = await t.run(async (ctx) => {
      const blobId = await ctx.storage.store(
        new Blob(["{}"], { type: "application/json" }),
      );
      return blobId;
    });
    const args = {
      kind: "base" as const,
      collectionSlug: "bukhari",
      schemaVersion: 1,
      contentVersion: "od1:" + "a".repeat(64),
      storageId: probe,
      sha256: "b".repeat(64),
      byteSize: 2,
      minAppVersion: "0.1.0",
      generatedAt: 5,
      licenseRecordId: licenseId,
      compatiblePacks: [],
    };
    const first = await t.mutation(internal.offlineDumps.upsertArtifact, args);
    const second = await t.mutation(internal.offlineDumps.upsertArtifact, args);
    expect(second).toEqual(first);
  });

  test("pre-existing version 1 translation packs are not advertised or distributed", async () => {
    const t = convexTest(schema, modules);
    const licenseId = await t.mutation(internal.offlineDumps.recordSunnahNowLicense, {});
    const storageId = await t.run(ctx => ctx.storage.store(new Blob(["{}"], { type: "application/json" })));
    const shared = { collectionSlug: "bukhari", schemaVersion: 1, storageId, sha256: "b".repeat(64), byteSize: 2, minAppVersion: "0.1.0", generatedAt: 5, licenseRecordId: licenseId, compatiblePacks: ["od1:" + "c".repeat(64)] };
    await t.mutation(internal.offlineDumps.upsertArtifact, { ...shared, kind: "base", contentVersion: "od1:" + "a".repeat(64) });
    await t.mutation(internal.offlineDumps.upsertArtifact, { ...shared, kind: "pack", locale: "ur", baseContentVersion: "od1:" + "a".repeat(64), contentVersion: "od1:" + "c".repeat(64) });
    expect(await t.query(api.offlineDumps.getPackManifest, { collectionSlug: "bukhari", locale: "ur" })).toBeNull();
    const manifests = await t.query(api.offlineDumps.getOfflineManifests, { translationLocale: "ur" });
    expect(manifests.bases).toHaveLength(1);
    expect(manifests.bases[0]?.compatiblePacks).toEqual([]);
    expect(manifests.packs).toEqual([]);
  });

  test("public manifests are empty before the first publish", async () => {
    const t = convexTest(schema, modules);
    expect(
      await t.query(api.offlineDumps.getBaseManifest, {
        collectionSlug: "bukhari",
      }),
    ).toBeNull();
    expect(
      await t.query(api.offlineDumps.getOfflineManifests, {}),
    ).toEqual({ bases: [], packs: [] });
  });

  test("version 1 packs cannot export unbound translation rights", async () => {
    const t = convexTest(schema, modules);
    const rows = await t.run(async (ctx) => {
      const hadithId = await ctx.db.insert("hadiths", {
        provider: "sunnah_now",
        canonicalId: "sunnah_now:bukhari:7",
        providerHadithId: "7",
        collectionSlug: "bukhari",
        arabicText: "نص",
        referenceDisplay: "Sahih al-Bukhari · Hadith 7",
        collectionName: "Sahih al-Bukhari",
        createdAt: 1,
      });
      const live = await ctx.db.insert("translations", {
        hadithId,
        language: "ur",
        content: "زندہ",
        source: "official",
        sourceLabel: "Official",
        status: "live",
        isDefault: true,
        groundingUsed: false,
        createdAt: 1,
        updatedAt: 1,
      });
      await ctx.db.insert("translations", {
        hadithId,
        language: "ur",
        content: "زیر التواء",
        source: "community",
        sourceLabel: "Community",
        status: "pending",
        isDefault: false,
        groundingUsed: false,
        createdAt: 2,
        updatedAt: 2,
      });
      await ctx.db.insert("translations", {
        hadithId,
        language: "ur",
        content: "پرانا",
        source: "official",
        sourceLabel: "Official",
        status: "archived",
        isDefault: false,
        groundingUsed: false,
        createdAt: 3,
        updatedAt: 3,
      });
      return { live };
    });
    const found = await t.query(
      internal.offlineDumps.listLiveDefaultsForLanguage,
      { language: "ur" },
    );
    expect(found).toHaveLength(0);
  });
});
