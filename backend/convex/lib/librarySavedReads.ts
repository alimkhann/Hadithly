import { v, type Infer } from "convex/values";
import type { Doc, Id } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { requireSavedReadBinding } from "./librarySyncIdentity";
import { libraryVersion } from "./librarySyncVersions";
import { syncHadithSummary } from "./librarySyncPolicy";

export const SAVED_REFERENCE_BYTES = 8 * 1024;
export const SAVED_TEXT_BYTES = 8 * 1024 * 1024;
export const savedReadHead = v.object({ ownerKey: v.string(), version: v.number() });
const { arabicText: _arabic, englishText: _english, ...referenceFields } = syncHadithSummary.fields;
export const savedHadithReference = v.object(referenceFields);
const identity = { ownerKey: v.string(), hadithId: v.id("hadiths") };
export const savedReferenceReply = v.union(
  v.object({ kind: v.literal("available"), ...identity, reference: savedHadithReference }),
  v.object({ kind: v.literal("missing"), ...identity }),
  v.object({ kind: v.literal("unavailable"), ...identity, reason: v.literal("reference_too_large") }),
);
export const savedTextReply = v.union(
  v.object({ kind: v.literal("available"), ...identity, hadith: syncHadithSummary }),
  v.object({ kind: v.literal("missing"), ...identity }),
  v.object({ kind: v.literal("unavailable"), ...identity, reason: v.literal("text_too_large") }),
);
type SavedReadHead = Infer<typeof savedReadHead>;
type SavedReferenceReply = Infer<typeof savedReferenceReply>;
type SavedTextReply = Infer<typeof savedTextReply>;
type TargetRequest = { capability: string; hadithId: Id<"hadiths"> };
const bytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).byteLength;

/** A live change trigger. It never proves that a native private generation is complete. */
export async function readSavedHead(ctx: QueryCtx, request: { capability: string }): Promise<SavedReadHead> {
  const { user } = await requireSavedReadBinding(ctx, request.capability);
  const version = await libraryVersion(ctx, user._id, "saved");
  if (!Number.isSafeInteger(version) || version < 0) throw new Error("SYNC_SAVED_VERSION_INVARIANT");
  return { ownerKey: user._id, version };
}

async function ownsTarget(ctx: QueryCtx, userId: Id<"users">, hadithId: Id<"hadiths">): Promise<boolean> {
  if (await ctx.db.query("savedItems").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).first()) return true;
  if (await ctx.db.query("bookmarks").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).first()) return true;
  if (await ctx.db.query("favorites").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).first()) return true;
  return await ctx.db.query("notes").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).first() !== null;
}

async function cachedTarget(ctx: QueryCtx, request: TargetRequest) {
  const { user } = await requireSavedReadBinding(ctx, request.capability);
  const hadith = await ownsTarget(ctx, user._id, request.hadithId) ? await ctx.db.get(request.hadithId) : null;
  return { ownerKey: user._id, hadithId: request.hadithId, hadith };
}

function reference(hadith: Doc<"hadiths">): Infer<typeof savedHadithReference> {
  return { _id: hadith._id, providerHadithId: hadith.providerHadithId, collectionSlug: hadith.collectionSlug,
    collectionName: hadith.collectionName, referenceDisplay: hadith.referenceDisplay,
    ...(hadith.volumeId === undefined ? {} : { volumeId: hadith.volumeId }) };
}

/** One cached public reference, independent of private collection and revision observation. */
export async function readSavedReference(ctx: QueryCtx, request: TargetRequest): Promise<SavedReferenceReply> {
  const { hadith, ...target } = await cachedTarget(ctx, request);
  if (!hadith) return { kind: "missing", ...target };
  const result: SavedReferenceReply = { kind: "available", ...target, reference: reference(hadith) };
  return bytes(result) <= SAVED_REFERENCE_BYTES ? result : { kind: "unavailable", ...target, reason: "reference_too_large" };
}

/** Full passages on demand. No provider fetch, private read barrier or silent truncation. */
export async function readSavedText(ctx: QueryCtx, request: TargetRequest): Promise<SavedTextReply> {
  const { hadith, ...target } = await cachedTarget(ctx, request);
  if (!hadith) return { kind: "missing", ...target };
  const result: SavedTextReply = { kind: "available", ...target, hadith: { ...reference(hadith), arabicText: hadith.arabicText,
    ...(hadith.englishText === undefined ? {} : { englishText: hadith.englishText }) } };
  return bytes(result) <= SAVED_TEXT_BYTES ? result : { kind: "unavailable", ...target, reason: "text_too_large" };
}
