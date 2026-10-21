import { v, type Infer } from "convex/values";
import type { Doc } from "../_generated/dataModel";
import type { QueryCtx } from "../_generated/server";
import { requireLibraryBinding } from "./librarySyncIdentity";
import { libraryVersion } from "./librarySyncVersions";
import { effectiveSavedMembership } from "./savedMembership";
import { syncSavedItem, syncFolderRow } from "./librarySyncPolicy";

export const SAVED_FACT_PAGE_ROWS = 1;
export const SAVED_FACT_SOURCE_BYTES = 32 * 1024;
export const SAVED_FACT_PAGE_BYTES = 64 * 1024;
export const SAVED_FACT_CURSOR_BYTES = 12 * 1024;
const sourceKind = v.union(v.literal("folders"), v.literal("items"), v.literal("bookmarks"), v.literal("favorites"), v.literal("notes"), v.literal("complete"));
type Source = Infer<typeof sourceKind>;
const { hadith: _hadith, ...privateFields } = syncSavedItem.fields;
export const savedPrivateItem = v.object({ ...privateFields, folderUpdatedAt: v.optional(v.number()) });
const identity = { sourceId: v.string(), ordinal: v.number() };
export const savedFact = v.union(
  v.object({ kind: v.literal("folder"), ...identity, value: syncFolderRow }),
  v.object({ kind: v.literal("item"), ...identity, value: savedPrivateItem }),
  v.object({ kind: v.literal("bookmark"), ...identity, hadithId: v.string(), createdAt: v.number() }),
  v.object({ kind: v.literal("favorite"), ...identity, hadithId: v.string(), createdAt: v.number() }),
  v.object({ kind: v.literal("note"), ...identity, hadithId: v.string(), content: v.string(), createdAt: v.number(), updatedAt: v.number() }),
);
export type SavedFact = Infer<typeof savedFact>;
const pageFields = { ownerKey: v.string(), version: v.number(), assemblyId: v.string(), input: v.optional(v.string()), start: v.number(), facts: v.array(savedFact) };
export const savedFactsReply = v.union(
  v.object({ kind: v.literal("page"), ...pageFields, next: v.string() }),
  v.object({ kind: v.literal("complete"), ...pageFields, total: v.number(), completion: v.string() }),
  v.object({ kind: v.literal("restart"), reason: v.literal("saved_changed") }),
  v.object({ kind: v.literal("unavailable"), reason: v.union(v.literal("source_too_large"), v.literal("page_too_large"), v.literal("source_did_not_advance"), v.literal("source_requires_split")) }),
);
export type SavedFactsReply = Infer<typeof savedFactsReply>;
type Cursor = { v: 1; bindingId: string; ownerKey: string; version: number; source: Source; cursor: string | null; ordinal: number };
const bytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).byteLength;
const invalid = () => new Error("SYNC_INVALID_SAVED_CURSOR");
function isSource(value: unknown): value is Source {
  return value === "folders" || value === "items" || value === "bookmarks" || value === "favorites" || value === "notes" || value === "complete";
}
function parseCursor(value: unknown): Cursor {
  if (typeof value !== "object" || value === null || !("v" in value && "bindingId" in value && "ownerKey" in value && "version" in value && "source" in value && "cursor" in value && "ordinal" in value)) throw invalid();
  const { v: versionTag, bindingId, ownerKey, version, source, cursor, ordinal } = value;
  if (Object.keys(value).length !== 7 || versionTag !== 1 || typeof bindingId !== "string" || typeof ownerKey !== "string" || typeof version !== "number" || !Number.isSafeInteger(version) || version < 0 || !isSource(source) || cursor !== null && (typeof cursor !== "string" || bytes(cursor) > 4_096) || typeof ordinal !== "number" || !Number.isSafeInteger(ordinal) || ordinal < 0 || source === "complete" && cursor !== null) throw invalid();
  return { v: 1, bindingId, ownerKey, version, source, cursor, ordinal };
}
function encode(value: string): string { return btoa(Array.from(new TextEncoder().encode(value), byte => String.fromCharCode(byte)).join("")); }
function decode(value: string): string { return new TextDecoder("utf-8", { fatal: true }).decode(Uint8Array.from(atob(value), char => char.charCodeAt(0))); }
async function signingKey(secret: string) {
  return crypto.subtle.importKey("raw", new TextEncoder().encode(secret), { name: "HMAC", hash: "SHA-256" }, false, ["sign", "verify"]);
}
async function seal(cursor: Cursor, key: CryptoKey): Promise<string> {
  const payload = encode(JSON.stringify(cursor));
  const signature = new Uint8Array(await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(payload)));
  const token = `${payload}.${Array.from(signature, byte => byte.toString(16).padStart(2, "0")).join("")}`;
  if (bytes(token) > SAVED_FACT_CURSOR_BYTES) throw invalid();
  return token;
}
async function open(token: string, key: CryptoKey): Promise<Cursor> {
  if (bytes(token) > SAVED_FACT_CURSOR_BYTES) throw invalid();
  const [payload, signature, extra] = token.split(".");
  if (!payload || !signature || extra !== undefined || !/^[a-f0-9]{64}$/.test(signature)) throw invalid();
  const digest = Uint8Array.from(signature.match(/../g) ?? [], value => Number.parseInt(value, 16));
  if (!await crypto.subtle.verify("HMAC", key, digest, new TextEncoder().encode(payload))) throw invalid();
  try { return parseCursor(JSON.parse(decode(payload))); } catch { throw invalid(); }
}
function nextSource(source: Exclude<Source, "complete">): Source {
  switch (source) {
    case "folders": return "items";
    case "items": return "bookmarks";
    case "bookmarks": return "favorites";
    case "favorites": return "notes";
    case "notes": return "complete";
  }
}

/** Private traversal only. Public hadith hydration and durable native activation are separate. */
export async function readSavedFactsPage(ctx: QueryCtx, request: { capability: string; continuation?: string }): Promise<SavedFactsReply> {
  if (bytes(request.capability) > 512 || request.continuation !== undefined && bytes(request.continuation) > SAVED_FACT_CURSOR_BYTES) throw invalid();
  const { user, protocol, binding } = await requireLibraryBinding(ctx, request.capability);
  if (protocol !== "manifest_v2") throw new Error("SYNC_CLIENT_UPGRADE_REQUIRED");
  if (!binding.savedCursorKey) throw new Error("SYNC_BINDING_REOPEN_REQUIRED");
  const key = await signingKey(binding.savedCursorKey);
  const prior = request.continuation === undefined ? undefined : await open(request.continuation, key);
  if (prior && (prior.ownerKey !== user._id || prior.bindingId !== binding._id)) throw invalid();
  const version = await libraryVersion(ctx, user._id, "saved");
  if (!Number.isSafeInteger(version) || version < 0) throw new Error("SYNC_SAVED_VERSION_INVARIANT");
  if (prior && prior.version !== version) return { kind: "restart", reason: "saved_changed" };
  const position: Cursor = prior ?? { v: 1, bindingId: binding._id, ownerKey: user._id, version, source: "folders", cursor: null, ordinal: 0 };
  const envelope = { ownerKey: user._id, version, assemblyId: await seal({ ...position, source: "folders", cursor: null, ordinal: 0 }, key), ...(request.continuation === undefined ? {} : { input: request.continuation }), start: position.ordinal };
  const options = { cursor: position.cursor, numItems: SAVED_FACT_PAGE_ROWS, maximumRowsRead: SAVED_FACT_PAGE_ROWS, maximumBytesRead: SAVED_FACT_SOURCE_BYTES };
  const facts: SavedFact[] = [];
  let next = position;
  if (position.source !== "complete") {
    const source = position.source;
    const sourcePage = source === "folders" ? await ctx.db.query("savedFolders").withIndex("by_user", q => q.eq("userId", user._id)).paginate(options)
      : source === "items" ? await ctx.db.query("savedItems").withIndex("by_user", q => q.eq("userId", user._id)).paginate(options)
      : source === "bookmarks" ? await ctx.db.query("bookmarks").withIndex("by_user", q => q.eq("userId", user._id)).paginate(options)
      : source === "favorites" ? await ctx.db.query("favorites").withIndex("by_user", q => q.eq("userId", user._id)).paginate(options)
      : await ctx.db.query("notes").withIndex("by_user_hadith", q => q.eq("userId", user._id)).paginate(options);
    if (sourcePage.pageStatus === "SplitRequired") return { kind: "unavailable", reason: "source_requires_split" };
    if (sourcePage.page.length > SAVED_FACT_PAGE_ROWS) throw new Error("SYNC_SAVED_PAGE_BOUND");
    for (const row of sourcePage.page) {
      if (row.userId !== user._id) throw new Error("SYNC_SAVED_OWNER_INVARIANT");
      if (bytes(row) > SAVED_FACT_SOURCE_BYTES) return { kind: "unavailable", reason: "source_too_large" };
      const id = { sourceId: row._id, ordinal: position.ordinal };
      if ("normalizedName" in row) facts.push({ kind: "folder", ...id, value: { _id: row._id, name: row.name, createdAt: row.createdAt } });
      else if ("content" in row) facts.push({ kind: "note", ...id, hadithId: row.hadithId, content: row.content, createdAt: row.createdAt, updatedAt: row.updatedAt });
      else if ("updatedAt" in row) facts.push({ kind: "item", ...id, value: await privateItem(ctx, row) });
      else if (source === "bookmarks") facts.push({ kind: "bookmark", ...id, hadithId: row.hadithId, createdAt: row.createdAt });
      else if (source === "favorites") facts.push({ kind: "favorite", ...id, hadithId: row.hadithId, createdAt: row.createdAt });
      else throw new Error("SYNC_SAVED_SOURCE_INVARIANT");
    }
    if (!sourcePage.isDone && sourcePage.continueCursor === position.cursor) return { kind: "unavailable", reason: "source_did_not_advance" };
    next = { ...position, source: sourcePage.isDone ? nextSource(source) : source, cursor: sourcePage.isDone ? null : sourcePage.continueCursor, ordinal: position.ordinal + facts.length };
    if (!Number.isSafeInteger(next.ordinal)) throw new Error("SYNC_SAVED_ORDINAL_INVARIANT");
  }
  const token = await seal(next, key);
  const result: SavedFactsReply = next.source === "complete"
    ? { kind: "complete", ...envelope, facts, total: next.ordinal, completion: token }
    : { kind: "page", ...envelope, facts, next: token };
  return bytes(result) <= SAVED_FACT_PAGE_BYTES ? result : { kind: "unavailable", reason: "page_too_large" };
}

async function privateItem(ctx: QueryCtx, row: Doc<"savedItems">): Promise<Infer<typeof savedPrivateItem>> {
  const membership = await effectiveSavedMembership(ctx, row);
  return { hadithId: row.hadithId, createdAt: row.createdAt, updatedAt: Math.max(row.updatedAt, membership.at ?? 0),
    ...(row.bookmarkCreatedAt === undefined ? {} : { bookmarkCreatedAt: row.bookmarkCreatedAt }),
    ...(row.favoriteCreatedAt === undefined ? {} : { favoriteCreatedAt: row.favoriteCreatedAt }),
    ...(row.noteContent === undefined ? {} : { noteContent: row.noteContent }),
    ...(row.noteCreatedAt === undefined ? {} : { noteCreatedAt: row.noteCreatedAt }),
    ...(row.noteUpdatedAt === undefined ? {} : { noteUpdatedAt: row.noteUpdatedAt }),
    ...(membership.folderId === undefined ? {} : { folderId: membership.folderId }),
    ...(membership.at === null ? {} : { folderUpdatedAt: membership.at }),
  };
}
