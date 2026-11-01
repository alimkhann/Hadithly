import { convexToJson, getConvexSize, getDocumentSize, jsonToConvex, v } from "convex/values";
import type { Infer, JSONValue } from "convex/values";
import { gzipSync, Gunzip, strFromU8, strToU8 } from "fflate";

const volumeFields = {
  volumeId: v.string(), title: v.string(),
  firstChapterTitle: v.optional(v.string()), firstChapterArabicTitle: v.optional(v.string()),
  hadithCount: v.number(),
};
export const outlineVolumeMetadata = v.object(volumeFields);
export const outlineVolume = v.object({ ...volumeFields, chapters: v.optional(v.array(v.object({
  chapterId: v.optional(v.string()), title: v.string(), arabicTitle: v.optional(v.string()),
  hadithCount: v.number(), firstProviderHadithId: v.string(),
}))) });
export const packedOutline = v.object({
  format: v.literal("gzip-convex-json-v1"), data: v.bytes(),
  uncompressedBytes: v.number(), sha256: v.string(),
});
export const collectionOutlineStorage = v.union(
  v.object({ collectionSlug: v.string(), volumes: v.array(outlineVolume), indexedAt: v.number() }),
  v.object({ collectionSlug: v.string(), volumes: v.array(outlineVolumeMetadata),
    packedVolumes: packedOutline, indexedAt: v.number() }),
);
export type OutlineVolume = Infer<typeof outlineVolume>;
type PackedOutline = Infer<typeof packedOutline>;
const MAX_EXPANDED_BYTES = 8 * 1024 * 1024;
const MAX_CONVEX_VALUE_BYTES = 1024 * 1024;

function invalid(): never { throw new Error("Invalid packed collection outline"); }
function isRecord(value: unknown): value is Record<string, unknown> {
  return value !== null && typeof value === "object" && !Array.isArray(value);
}
function isJson(value: unknown): value is JSONValue {
  if (value === null || typeof value === "string" || typeof value === "boolean") return true;
  if (typeof value === "number") return Number.isFinite(value);
  if (Array.isArray(value)) return value.every(isJson);
  return isRecord(value) && Object.values(value).every(isJson);
}
function record(value: unknown, keys: string[]): Record<string, unknown> {
  if (!isRecord(value) || Object.keys(value).some(key => !keys.includes(key))) return invalid();
  return value;
}
function text(value: unknown): string { return typeof value === "string" ? value : invalid(); }
function optionalText(value: unknown): string | undefined { return value === undefined ? undefined : text(value); }
function number(value: unknown): number { return typeof value === "number" ? value : invalid(); }
function array(value: unknown): unknown[] { return Array.isArray(value) ? value : invalid(); }
function parseVolumes(value: unknown): OutlineVolume[] {
  return array(value).map(entry => {
    const volume = record(entry, ["volumeId", "title", "firstChapterTitle", "firstChapterArabicTitle", "hadithCount", "chapters"]);
    return {
      volumeId: text(volume.volumeId), title: text(volume.title), hadithCount: number(volume.hadithCount),
      firstChapterTitle: optionalText(volume.firstChapterTitle), firstChapterArabicTitle: optionalText(volume.firstChapterArabicTitle),
      chapters: volume.chapters === undefined ? undefined : array(volume.chapters).map(entry => {
        const chapter = record(entry, ["chapterId", "title", "arabicTitle", "hadithCount", "firstProviderHadithId"]);
        return { chapterId: optionalText(chapter.chapterId), title: text(chapter.title),
          arabicTitle: optionalText(chapter.arabicTitle), hadithCount: number(chapter.hadithCount),
          firstProviderHadithId: text(chapter.firstProviderHadithId) };
      }),
    };
  });
}

const crcTable = Uint32Array.from({ length: 256 }, (_, index) => {
  let crc = index;
  for (let bit = 0; bit < 8; bit++) crc = crc & 1 ? (crc >>> 1) ^ 0xedb88320 : crc >>> 1;
  return crc >>> 0;
});
function crc32(bytes: Uint8Array): number {
  let crc = 0xffffffff;
  for (const byte of bytes) crc = (crc >>> 8) ^ crcTable[(crc ^ byte) & 255];
  return (crc ^ 0xffffffff) >>> 0;
}

async function sha256(bytes: Uint8Array): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", Uint8Array.from(bytes));
  return Array.from(new Uint8Array(digest), byte => byte.toString(16).padStart(2, "0")).join("");
}

export function volumeMetadata(volumes: OutlineVolume[]): Infer<typeof outlineVolumeMetadata>[] {
  return volumes.map(({ chapters: _chapters, ...metadata }) => metadata);
}

export async function packVolumes(volumes: OutlineVolume[]): Promise<PackedOutline> {
  // Convex's wire encoding preserves special Float64 values and absent optional fields.
  if (getConvexSize(volumes) > MAX_CONVEX_VALUE_BYTES) return invalid();
  const bytes = strToU8(JSON.stringify(convexToJson(volumes)));
  if (bytes.byteLength > MAX_EXPANDED_BYTES) return invalid();
  const data = gzipSync(bytes, { level: 6, mtime: 0 });
  return { format: "gzip-convex-json-v1", data: Uint8Array.from(data).buffer,
    uncompressedBytes: bytes.byteLength, sha256: await sha256(bytes) };
}

export async function prepareOutline(fields: {
  collectionSlug: string; volumes: OutlineVolume[]; indexedAt: number;
}): Promise<Infer<typeof collectionOutlineStorage>> {
  if (getDocumentSize(fields) > MAX_CONVEX_VALUE_BYTES) return invalid();
  const packed = { ...fields, volumes: volumeMetadata(fields.volumes), packedVolumes: await packVolumes(fields.volumes) };
  return getDocumentSize(packed) < getDocumentSize(fields) ? packed : fields;
}

export async function unpackVolumes(packed: PackedOutline): Promise<OutlineVolume[]> {
  if (!Number.isSafeInteger(packed.uncompressedBytes) || packed.uncompressedBytes < 1 ||
      packed.uncompressedBytes > MAX_EXPANDED_BYTES || packed.data.byteLength < 18) return invalid();
  const footerSize = new DataView(packed.data).getUint32(packed.data.byteLength - 4, true);
  if (footerSize !== packed.uncompressedBytes) return invalid();
  try {
    const bytes = new Uint8Array(packed.uncompressedBytes);
    let written = 0;
    const decoder = new Gunzip(chunk => {
      if (chunk.byteLength > bytes.byteLength - written) return invalid();
      bytes.set(chunk, written);
      written += chunk.byteLength;
    });
    const input = new Uint8Array(packed.data);
    // Small input chunks bound work before an oversized stream can be rejected.
    for (let offset = 0; offset < input.byteLength; offset += 256) {
      decoder.push(input.subarray(offset, offset + 256), offset + 256 >= input.byteLength);
    }
    if (written !== bytes.byteLength || crc32(bytes) !== new DataView(packed.data).getUint32(packed.data.byteLength - 8, true)) return invalid();
    if (await sha256(bytes) !== packed.sha256) return invalid();
    const json: unknown = JSON.parse(strFromU8(bytes));
    if (!isJson(json)) return invalid();
    const volumes = parseVolumes(jsonToConvex(json));
    if (getConvexSize(volumes) > MAX_CONVEX_VALUE_BYTES) return invalid();
    return volumes;
  } catch { return invalid(); }
}
