/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { convexToJson, getConvexSize, getDocumentSize } from "convex/values";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { gzipSync, strToU8 } from "fflate";
import { packVolumes, prepareOutline, unpackVolumes } from "./lib/outlineStorage";

const modules = import.meta.glob("./**/*.ts");
const volumes = Array.from({ length: 8 }, (_, i) => ({
  volumeId: `opaque-volume-${i}`,
  title: `Volume ${i} %@ مصدر`,
  firstChapterTitle: "Original title",
  firstChapterArabicTitle: "كتاب الإيمان",
  hadithCount: 40,
  chapters: Array.from({ length: 40 }, (_, j) => ({
    chapterId: `opaque:${i}/${j}%@`,
    title: "Source chapter title ".repeat(12) + j,
    arabicTitle: "بَابُ الْإِيمَانِ ".repeat(12) + j,
    hadithCount: 1,
    firstProviderHadithId: `${i}-${j}-opaque`,
  })),
}));

describe("outline storage cost", () => {
  test("stores fewer bytes while returning every original chapter and identifier", async () => {
    const t = convexTest(schema, modules);
    const args = { collectionSlug: "bukhari", volumes };
    await t.mutation(internal.collections.upsertOutline, args);
    const response = await t.query(api.collections.getOutline, { collectionSlug: "bukhari" });
    expect(response?.volumes).toEqual(volumes);
    const stored = await t.run(ctx => ctx.db.query("collectionOutlines").unique());
    if (!stored) throw new Error("Missing outline");
    const storedWireBytes = getDocumentSize(stored);
    const legacyWireBytes = getDocumentSize({ ...args, indexedAt: 1 });
    expect(storedWireBytes).toBeLessThan(legacyWireBytes / 2);
  });
  test("legacy conversion and rollback preserve the exact public document and freshness", async () => {
    const t = convexTest(schema, modules);
    await t.run(ctx => ctx.db.insert("collectionOutlines", { collectionSlug: "bukhari", volumes, indexedAt: 123 }));
    const original = await t.query(api.collections.getOutline, { collectionSlug: "bukhari" });
    const rewrite = (format: "packed" | "legacy") => t.mutation(internal.migrations.rewriteCollectionOutlineStorage, { collectionSlug: "bukhari", format });
    expect(await rewrite("packed")).toEqual({ status: "packed" });
    expect(await rewrite("packed")).toEqual({ status: "already_packed" });
    expect(await t.query(api.collections.getOutline, { collectionSlug: "bukhari" })).toEqual(original);
    expect(await rewrite("legacy")).toEqual({ status: "legacy" });
    expect(await rewrite("legacy")).toEqual({ status: "already_legacy" });
    expect(await t.query(api.collections.getOutline, { collectionSlug: "bukhari" })).toEqual(original);
  });

  test("refresh replaces packed data and updates compact counts in the same transaction", async () => {
    const t = convexTest(schema, modules);
    const id = await t.mutation(internal.collections.upsertOutline, { collectionSlug: "bukhari", volumes });
    const changed = [{ ...volumes[0], hadithCount: 41, chapters: [] }];
    expect(await t.mutation(internal.collections.upsertOutline, { collectionSlug: "bukhari", volumes: changed })).toBe(id);
    expect((await t.query(api.collections.getOutline, { collectionSlug: "bukhari" }))?.volumes).toEqual(changed);
    expect((await t.query(api.library.listCollectionProgressSummaries, {})).find(row => row.collectionSlug === "bukhari")?.totalHadiths).toBe(41);
  });

  test("missing versus empty chapters and Convex Float64 values round trip", async () => {
    const values = [
      { volumeId: "opaque", title: "x\u0001 %1$@ 👋", hadithCount: -0 },
      { volumeId: "empty", title: "", hadithCount: Infinity, chapters: [] },
      { ...volumes[0], hadithCount: NaN, chapters: [{ title: "", firstProviderHadithId: "unchanged%/معرف", hadithCount: -Infinity }] },
    ];
    const packed = await packVolumes(values);
    expect(convexToJson(await unpackVolumes(packed))).toEqual(convexToJson(values));
    expect(await packVolumes(values)).toEqual(packed);
  });

  test("corruption, size mismatch and excess allocation fail closed", async () => {
    const packed = await packVolumes(volumes);
    await expect(unpackVolumes({ ...packed, sha256: "0".repeat(64) })).rejects.toThrow("Invalid packed");
    await expect(unpackVolumes({ ...packed, uncompressedBytes: packed.uncompressedBytes + 1 })).rejects.toThrow("Invalid packed");
    await expect(unpackVolumes({ ...packed, uncompressedBytes: 2 ** 32 })).rejects.toThrow("Invalid packed");
    await expect(unpackVolumes({ ...packed, data: new ArrayBuffer(2) })).rejects.toThrow("Invalid packed");
  });

  test("counts backfill uses the small metadata and missing records stay missing", async () => {
    const t = convexTest(schema, modules);
    expect(await t.mutation(internal.migrations.rewriteCollectionOutlineStorage, { collectionSlug: "bukhari", format: "packed" })).toEqual({ status: "missing" });
    await t.mutation(internal.collections.upsertOutline, { collectionSlug: "bukhari", volumes });
    await t.run(async ctx => { for (const row of await ctx.db.query("collectionCounts").collect()) await ctx.db.delete(row._id); });
    expect((await t.query(api.library.listCollectionProgressSummaries, {})).find(row => row.collectionSlug === "bukhari")?.totalHadiths).toBe(320);
    expect(await t.mutation(internal.migrations.materializeQ1CollectionCounts, {})).toEqual({ written: 1 });
    expect((await t.query(api.library.listCollectionProgressSummaries, {})).find(row => row.collectionSlug === "bukhari")?.totalHadiths).toBe(320);
  });

  test("a forged small footer cannot hide extra decompressed content", async () => {
    const packed = await packVolumes(volumes);
    const json = JSON.stringify(convexToJson(volumes));
    const data = Uint8Array.from(gzipSync(strToU8(json + " ".repeat(1000000)), { mtime: 0 }));
    new DataView(data.buffer).setUint32(data.byteLength - 4, packed.uncompressedBytes, true);
    await expect(unpackVolumes({ ...packed, data: data.buffer })).rejects.toThrow("Invalid packed");
  });

  test("gzip trailer corruption is rejected even when the decoded content is unchanged", async () => {
    const packed = await packVolumes(volumes);
    const data = new Uint8Array(packed.data.slice(0));
    data[data.byteLength - 8] ^= 1;
    await expect(unpackVolumes({ ...packed, data: data.buffer })).rejects.toThrow("Invalid packed");
  });

  test("metadata-heavy outlines never grow or become unwritable during packing", async () => {
    let seed = 157;
    const title = Array.from({ length: 900000 }, () => {
      seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5;
      return String.fromCharCode(33 + ((seed >>> 0) % 90));
    }).join("");
    const input = { collectionSlug: "bukhari", volumes: [{ volumeId: "opaque", title, hadithCount: 1 }] };
    const t = convexTest(schema, modules);
    await t.mutation(internal.collections.upsertOutline, input);
    const row = await t.run(ctx => ctx.db.query("collectionOutlines").unique());
    if (!row) throw new Error("Missing outline");
    expect(getDocumentSize(row)).toBeLessThan(1024 * 1024);
    expect("packedVolumes" in row).toBe(false);
    expect((await t.query(api.collections.getOutline, { collectionSlug: "bukhari" }))?.volumes).toEqual(input.volumes);
    expect(await t.mutation(internal.migrations.rewriteCollectionOutlineStorage, { collectionSlug: "bukhari", format: "packed" })).toEqual({ status: "already_small" });
  });

  test("new packed data must still fit the legacy document budget for rollback", async () => {
    const fields = { collectionSlug: "bukhari", indexedAt: 123, volumes: [{ volumeId: "1", title: "Volume", hadithCount: 1,
      chapters: [{ title: "", hadithCount: 1, firstProviderHadithId: "opaque" }] }] };
    fields.volumes[0].chapters[0].title = "x".repeat(1024 * 1024 - getDocumentSize(fields) + 1);
    expect(getConvexSize(fields.volumes)).toBeLessThan(1024 * 1024);
    expect(getDocumentSize(fields)).toBeGreaterThan(1024 * 1024);
    await expect(prepareOutline(fields)).rejects.toThrow("Invalid packed");
    const t = convexTest(schema, modules);
    await t.mutation(internal.collections.upsertOutline, { collectionSlug: "bukhari", volumes });
    const original = await t.query(api.collections.getOutline, { collectionSlug: "bukhari" });
    await expect(t.mutation(internal.collections.upsertOutline, { collectionSlug: "bukhari", volumes: fields.volumes })).rejects.toThrow("Invalid packed");
    expect(await t.query(api.collections.getOutline, { collectionSlug: "bukhari" })).toEqual(original);
    expect((await t.query(api.library.listCollectionProgressSummaries, {})).find(row => row.collectionSlug === "bukhari")?.totalHadiths).toBe(320);
  });

});
