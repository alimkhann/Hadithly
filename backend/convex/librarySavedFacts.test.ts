/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { readSavedFactsPage, SAVED_FACT_PAGE_BYTES, SAVED_FACT_CURSOR_BYTES, type SavedFact, type SavedFactsReply } from "./lib/librarySavedFacts";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

async function fixture() {
  const t = convexTest(schema, modules);
  const a = t.withIdentity({ subject: "facts-owner", tokenIdentifier: "fixture:facts-owner" });
  const b = t.withIdentity({ subject: "facts-other", tokenIdentifier: "fixture:facts-other" });
  const userId = await a.mutation(api.users.ensureCurrentUser, {});
  const otherId = await b.mutation(api.users.ensureCurrentUser, {});
  const hadithId = await t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", providerHadithId: "1", collectionSlug: "bukhari", arabicText: "نص", referenceDisplay: "Bukhari 1", collectionName: "Bukhari", createdAt: 1 }));
  const binding = await a.mutation(api.librarySync.openManifestBinding, {});
  return { t, a, b, userId, otherId, hadithId, binding, capability: binding.capability };
}
type Fixture = Awaited<ReturnType<typeof fixture>>;
function page(reply: SavedFactsReply) {
  if (reply.kind !== "page" && reply.kind !== "complete") throw new Error("Missing private page");
  return reply;
}
async function all(f: Fixture) {
  const facts: SavedFact[] = [];
  let continuation: string | undefined;
  let assemblyId: string | undefined;
  let version: number | undefined;
  for (let step = 0; step < 5_000; step++) {
    const reply = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, ...(continuation ? { continuation } : {}) }));
    expect(reply.ownerKey).toBe(f.userId);
    expect(reply.input).toBe(continuation);
    expect(reply.start).toBe(facts.length);
    expect(reply.facts.length).toBeLessThanOrEqual(1);
    expect(Buffer.byteLength(JSON.stringify(reply), "utf8")).toBeLessThanOrEqual(SAVED_FACT_PAGE_BYTES);
    if (assemblyId !== undefined) expect(reply.assemblyId).toBe(assemblyId);
    if (version !== undefined) expect(reply.version).toBe(version);
    assemblyId = reply.assemblyId; version = reply.version;
    for (const row of reply.facts) { expect(row.ordinal).toBe(facts.length); facts.push(row); }
    if (reply.kind === "complete") {
      expect(reply.total).toBe(facts.length);
      return { facts, reply };
    }
    expect(reply.next).not.toBe(continuation);
    continuation = reply.next;
  }
  throw new Error("Private traversal exceeded finite fixture limit");
}

test("empty sources finish only after every phase and signed completion rechecks the Saved revision", async () => {
  const f = await fixture();
  const first = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability }));
  expect(first).toMatchObject({ kind: "page", start: 0, facts: [] });
  expect(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability })).toEqual(first);
  const { facts, reply } = await all(f);
  expect(facts).toEqual([]);
  const replay = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: reply.completion }));
  expect(replay).toMatchObject({ kind: "complete", facts: [], total: 0, assemblyId: reply.assemblyId });
  await f.a.mutation(api.library.toggleSavedBookmark, { hadithId: f.hadithId });
  expect(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: reply.completion })).toEqual({ kind: "restart", reason: "saved_changed" });
});

test("501 items and 501 duplicate legacy facets traverse exactly once without a public hadith join", async () => {
  const f = await fixture();
  const ids = await f.t.run(async ctx => {
    const ids = [];
    for (let index = 0; index < 501; index++) {
      const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", providerHadithId: String(index + 2), collectionSlug: "bukhari", arabicText: index === 0 ? "ع".repeat(100_000) : "نص", referenceDisplay: `Bukhari ${index + 2}`, collectionName: "Bukhari", createdAt: 1 });
      ids.push(hadithId);
      await ctx.db.insert("savedItems", { userId: f.userId, hadithId, bookmarkCreatedAt: index + 10, createdAt: index + 10, updatedAt: index + 10 });
      await ctx.db.insert("bookmarks", { userId: f.userId, hadithId: f.hadithId, createdAt: 1_000 - index });
    }
    await ctx.db.insert("savedFolders", { userId: f.userId, name: "Empty folder", normalizedName: "empty folder", createdAt: 1, updatedAt: 1 });
    await ctx.db.insert("notes", { userId: f.otherId, hadithId: f.hadithId, content: "Other private note", createdAt: 1, updatedAt: 1 });
    await ctx.db.delete(ids[17]);
    return ids;
  });
  const { facts } = await all(f);
  const items = facts.flatMap(row => row.kind === "item" ? [row.value.hadithId] : []);
  expect(items).toEqual(ids);
  expect(items).toContain(ids[17]);
  expect(facts.filter(row => row.kind === "bookmark")).toHaveLength(501);
  expect(new Set(facts.map(row => row.sourceId)).size).toBe(facts.length);
  expect(facts.find(row => row.kind === "folder")).toMatchObject({ value: { name: "Empty folder" } });
  expect(JSON.stringify(facts)).not.toContain("Other private note");
  await f.a.run(async ctx => {
    const queries = vi.spyOn(ctx.db, "query"), gets = vi.spyOn(ctx.db, "get");
    try {
      const first = page(await readSavedFactsPage(ctx, { capability: f.capability }));
      if (first.kind !== "page") throw new Error("Missing first continuation");
      expect(first.facts[0]).toMatchObject({ kind: "folder" });
      queries.mockClear(); gets.mockClear();
      const second = page(await readSavedFactsPage(ctx, { capability: f.capability, continuation: first.next }));
      expect(second.facts).toEqual([]);
      const next = second.kind === "page" ? second.next : second.completion;
      queries.mockClear(); gets.mockClear();
      const third = page(await readSavedFactsPage(ctx, { capability: f.capability, continuation: next }));
      expect(third.facts[0]).toMatchObject({ kind: "item" });
      expect(queries.mock.calls.map(call => call[0])).toEqual(["users", "librarySyncBindings", "librarySyncVersions", "savedItems"]);
      expect(gets).not.toHaveBeenCalled();
    } finally { queries.mockRestore(); gets.mockRestore(); }
  });
}, 60_000);

test("source facts preserve canonical and duplicate legacy timestamp/tie semantics", async () => {
  const f = await fixture();
  await f.t.run(async ctx => {
    await ctx.db.insert("savedItems", { userId: f.userId, hadithId: f.hadithId, bookmarkCreatedAt: 30, favoriteCreatedAt: 50, noteContent: "Canonical tie wins", noteCreatedAt: 15, noteUpdatedAt: 80, createdAt: 15, updatedAt: 90 });
    for (const createdAt of [20, 5, 12]) await ctx.db.insert("bookmarks", { userId: f.userId, hadithId: f.hadithId, createdAt });
    for (const createdAt of [40, 7]) await ctx.db.insert("favorites", { userId: f.userId, hadithId: f.hadithId, createdAt });
    for (const value of [{ content: "Legacy tie loses", createdAt: 2, updatedAt: 80 }, { content: "Newer note wins", createdAt: 3, updatedAt: 100 }, { content: "Equal legacy later loses", createdAt: 1, updatedAt: 100 }]) await ctx.db.insert("notes", { userId: f.userId, hadithId: f.hadithId, ...value });
  });
  const { facts } = await all(f);
  const canonical = facts.find(row => row.kind === "item");
  if (canonical?.kind !== "item") throw new Error("Missing canonical fact");
  const merged = { ...canonical.value };
  for (const fact of facts) {
    if (fact.kind === "bookmark") { merged.bookmarkCreatedAt = Math.min(merged.bookmarkCreatedAt ?? fact.createdAt, fact.createdAt); merged.createdAt = Math.min(merged.createdAt, fact.createdAt); }
    if (fact.kind === "favorite") { merged.favoriteCreatedAt = Math.min(merged.favoriteCreatedAt ?? fact.createdAt, fact.createdAt); merged.createdAt = Math.min(merged.createdAt, fact.createdAt); }
    if (fact.kind === "note") {
      if ((merged.noteUpdatedAt ?? -Infinity) < fact.updatedAt) { merged.noteContent = fact.content; merged.noteCreatedAt = fact.createdAt; merged.noteUpdatedAt = fact.updatedAt; }
      merged.createdAt = Math.min(merged.createdAt, fact.createdAt); merged.updatedAt = Math.max(merged.updatedAt, fact.updatedAt);
    }
  }
  const expected = (await f.a.query(api.librarySync.savedSnapshot, {})).items[0];
  const { hadith: _summary, ...privateExpected } = expected;
  expect(merged).toEqual(privateExpected);
  expect(merged).toMatchObject({ bookmarkCreatedAt: 5, favoriteCreatedAt: 7, noteContent: "Newer note wins", createdAt: 1, updatedAt: 100 });
});

test("cursor tampering, owner/binding swaps and old bindings cannot select source rows", async () => {
  const f = await fixture();
  const first = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability }));
  if (first.kind !== "page") throw new Error("Missing continuation");
  const other = await f.b.mutation(api.librarySync.openManifestBinding, {});
  await expect(f.b.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: first.next })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  await expect(f.b.query(api.librarySync.savedFactsPage, { capability: other.capability, continuation: first.next })).rejects.toThrow("SYNC_INVALID_SAVED_CURSOR");
  const reopened = await f.a.mutation(api.librarySync.openManifestBinding, {});
  await expect(f.a.query(api.librarySync.savedFactsPage, { capability: reopened.capability, continuation: first.next })).rejects.toThrow("SYNC_INVALID_SAVED_CURSOR");
  const [encoded, signature] = first.next.split(".");
  const raw = JSON.parse(atob(encoded));
  for (const change of [{ source: "complete" }, { ordinal: 100 }, { ownerKey: f.otherId }, { cursor: "foreign-opaque-cursor" }]) {
    const tampered = `${btoa(JSON.stringify({ ...raw, ...change }))}.${signature}`;
    await expect(f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: tampered })).rejects.toThrow("SYNC_INVALID_SAVED_CURSOR");
  }
  await expect(f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: "x".repeat(SAVED_FACT_CURSOR_BYTES + 1) })).rejects.toThrow("SYNC_INVALID_SAVED_CURSOR");
  const legacy = await f.a.mutation(api.librarySync.openBinding, {});
  await expect(f.a.query(api.librarySync.savedFactsPage, { capability: legacy.capability })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  await f.t.run(async ctx => {
    const bindings = await ctx.db.query("librarySyncBindings").collect();
    const row = bindings.find(row => row.savedCursorKey !== undefined);
    if (!row) throw new Error("Missing binding fixture");
    await ctx.db.patch(row._id, { savedCursorKey: undefined });
  });
  await expect(f.a.query(api.librarySync.savedFactsPage, { capability: f.capability })).rejects.toThrow("SYNC_BINDING_REOPEN_REQUIRED");
});

test.each(["folder", "item", "note"] as const)("oversized %s source preserves content and cannot complete or consume the row", async kind => {
  const f = await fixture(), content = "ع".repeat(kind === "folder" ? 200_000 : 400_000);
  await f.t.run(async ctx => {
    if (kind === "folder") await ctx.db.insert("savedFolders", { userId: f.userId, name: content, normalizedName: content, createdAt: 1, updatedAt: 1 });
    if (kind === "item") await ctx.db.insert("savedItems", { userId: f.userId, hadithId: f.hadithId, noteContent: content, createdAt: 1, updatedAt: 1 });
    if (kind === "note") await ctx.db.insert("notes", { userId: f.userId, hadithId: f.hadithId, content, createdAt: 1, updatedAt: 1 });
  });
  let continuation: string | undefined;
  for (let step = 0; step < 5; step++) {
    const request = { capability: f.capability, ...(continuation ? { continuation } : {}) };
    const result = await f.a.query(api.librarySync.savedFactsPage, request);
    if (result.kind === "unavailable") {
      expect(result).toEqual({ kind: "unavailable", reason: "source_too_large" });
      expect(await f.a.query(api.librarySync.savedFactsPage, request)).toEqual(result);
      expect(JSON.stringify(await f.a.query(api.users.exportCurrentUserData, {}))).toContain(content);
      return;
    }
    if (result.kind !== "page") throw new Error("Oversized source incorrectly completed");
    continuation = result.next;
  }
  throw new Error("Oversized source was not reached");
});

test.each(["bookmarks", "favorites", "notes"] as const)("%s backfill during traversal forces restart rather than mixed completion", async source => {
  const f = await fixture();
  await f.t.run(async ctx => {
    if (source === "notes") await ctx.db.insert("notes", { userId: f.userId, hadithId: f.hadithId, content: "Old private note", createdAt: 1, updatedAt: 2 });
    else await ctx.db.insert(source, { userId: f.userId, hadithId: f.hadithId, createdAt: 1 });
  });
  const first = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability }));
  if (first.kind !== "page") throw new Error("Missing continuation");
  await f.t.mutation(internal.migrations.migrateH3SavedItems, { source, paginationOpts: { cursor: null, numItems: 10 } });
  expect(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: first.next })).toEqual({ kind: "restart", reason: "saved_changed" });
});

test("expiry and account erasure revoke traversal; private cursor keys never enter binding DTO or export", async () => {
  vi.useFakeTimers();
  const f = await fixture();
  const first = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability }));
  if (first.kind !== "page") throw new Error("Missing continuation");
  const secret = await f.t.run(async ctx => (await ctx.db.query("librarySyncBindings").filter(q => q.eq(q.field("userId"), f.userId)).first())?.savedCursorKey);
  if (!secret) throw new Error("Missing signing key");
  expect(JSON.stringify(f.binding)).not.toContain(secret);
  expect(JSON.stringify(await f.a.query(api.users.exportCurrentUserData, {}))).not.toContain(secret);
  vi.setSystemTime(f.binding.validUntil + 1);
  await expect(f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation: first.next })).rejects.toThrow("SYNC_BINDING_EXPIRED");
  const reopened = await f.a.mutation(api.librarySync.openManifestBinding, {});
  await f.a.mutation(api.users.deleteCurrentUser, { authorization: (await f.a.mutation(api.users.prepareAccountDeletion, {})).authorization });
  await expect(f.a.query(api.librarySync.savedFactsPage, { capability: reopened.capability })).rejects.toThrow("SYNC_ACCOUNT_MISSING");
  expect(await f.t.run(ctx => ctx.db.query("librarySyncBindings").collect())).toEqual([]);
});


test("effective staged membership survives physical normalization under the same private revision", async () => {
  const f = await fixture();
  const { itemId, destinationId } = await f.t.run(async ctx => {
    const oldFolder = await ctx.db.insert("savedFolders", { userId: f.userId, name: "Removed", normalizedName: "removed", createdAt: 1, updatedAt: 1 });
    const destinationId = await ctx.db.insert("savedFolders", { userId: f.userId, name: "Restored", normalizedName: "restored", createdAt: 100, updatedAt: 100 });
    const manifestId = await ctx.db.insert("savedFolderManifests", { userId: f.userId, folderId: oldFolder, operationId: "delete", requestedAt: 50, generation: "g", createdAt: 50, updatedAt: 100, expiresAt: Date.now() + 10_000,
      captured: { epoch: 0, updatedAt: 1, name: "Removed", createdAt: 1 },
      state: { kind: "restored", count: 1, operationId: "restore", at: 100, destinationId, normalization: { kind: "pending", cursor: null, step: 0 }, restored: 1, superseded: 0, missing: 0 } });
    const itemId = await ctx.db.insert("savedItems", { userId: f.userId, hadithId: f.hadithId, folderId: oldFolder, folderUpdatedAt: 1, bookmarkCreatedAt: 1, createdAt: 1, updatedAt: 1 });
    const memberId = await ctx.db.insert("savedFolderManifestMembers", { userId: f.userId, manifestId, ordinal: 0, itemId, hadithId: f.hadithId, disposition: "restored" });
    await ctx.db.patch(itemId, { folderStage: { manifestId, memberId, generation: "g", restoreId: "restore" } });
    await ctx.db.delete(oldFolder);
    return { itemId, destinationId };
  });
  let continuation: string | undefined;
  for (let step = 0; step < 10; step++) {
    const request = { capability: f.capability, ...(continuation ? { continuation } : {}) };
    const reply = page(await f.a.query(api.librarySync.savedFactsPage, request));
    if (reply.facts[0]?.kind === "item") {
      expect(reply.facts[0].value).toMatchObject({ folderId: destinationId, folderUpdatedAt: 100, updatedAt: 100 });
      await f.a.run(async ctx => {
        const gets = vi.spyOn(ctx.db, "get"), queries = vi.spyOn(ctx.db, "query");
        try {
          expect(await readSavedFactsPage(ctx, request)).toEqual(reply);
          expect(gets).toHaveBeenCalledTimes(2);
          expect(queries.mock.calls.map(call => call[0])).toEqual(["users", "librarySyncBindings", "librarySyncVersions", "savedItems"]);
        } finally { gets.mockRestore(); queries.mockRestore(); }
      });
      await f.t.run(ctx => ctx.db.patch(itemId, { folderStage: undefined, folderId: destinationId, folderUpdatedAt: 100, updatedAt: 100 }));
      expect(await f.a.query(api.librarySync.savedFactsPage, request)).toEqual(reply);
      return;
    }
    if (reply.kind !== "page") throw new Error("Missed staged item");
    continuation = reply.next;
  }
  throw new Error("Missing staged item fact");
});

test("malformed foreign folder pointers reveal no private name or membership", async () => {
  const f = await fixture();
  await f.t.run(async ctx => {
    const folderId = await ctx.db.insert("savedFolders", { userId: f.otherId, name: "Other private folder", normalizedName: "other private folder", createdAt: 1, updatedAt: 1 });
    await ctx.db.insert("savedItems", { userId: f.userId, hadithId: f.hadithId, folderId, folderUpdatedAt: 1, noteContent: "Own note", createdAt: 1, updatedAt: 1 });
  });
  const { facts } = await all(f);
  expect(facts).toHaveLength(1);
  expect(facts[0]).toMatchObject({ kind: "item", value: { noteContent: "Own note" } });
  if (facts[0].kind !== "item") throw new Error("Missing item");
  expect(facts[0].value.folderId).toBeUndefined();
  expect(JSON.stringify(facts)).not.toContain("Other private folder");
});

test.each([0, 1, 2, 3, 4])("a private write after source step %s forces restart", async sourceStep => {
  const f = await fixture();
  let continuation: string | undefined;
  for (let step = 0; step <= sourceStep; step++) {
    const result = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, ...(continuation ? { continuation } : {}) }));
    continuation = result.kind === "page" ? result.next : result.completion;
  }
  await f.a.mutation(api.library.toggleSavedFavorite, { hadithId: f.hadithId });
  expect(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability, continuation })).toEqual({ kind: "restart", reason: "saved_changed" });
});

function hasPaginator(value: unknown): value is { paginate: (...args: unknown[]) => unknown } {
  return typeof value === "object" && value !== null && "paginate" in value && typeof value.paginate === "function";
}

test.each([{ isDone: false, withRow: false }, { isDone: true, withRow: false }, { isDone: false, withRow: true }, { isDone: true, withRow: true }])("SDK SplitRequired $isDone/$withRow cannot consume partial facts or sign completion", async ({ isDone, withRow }) => {
  const f = await fixture();
  await f.a.run(async ctx => {
    const prototype: unknown = Object.getPrototypeOf(ctx.db.query("savedFolders").withIndex("by_user", q => q.eq("userId", f.userId)));
    if (!hasPaginator(prototype)) throw new Error("Actual SDK query prototype lacks paginate");
    const id = await ctx.db.insert("savedFolders", { userId: f.userId, name: "Partial value cannot be consumed", normalizedName: "partial", createdAt: 1, updatedAt: 1 });
    const row = await ctx.db.get(id);
    const paginate = vi.spyOn(prototype, "paginate").mockReturnValue(Promise.resolve({ page: withRow ? [row] : [], continueCursor: "partial-cursor", isDone, pageStatus: "SplitRequired", splitCursor: "split-point" }));
    try {
      expect(await readSavedFactsPage(ctx, { capability: f.capability })).toEqual({ kind: "unavailable", reason: "source_requires_split" });
      expect(paginate).toHaveBeenCalledWith({ cursor: null, numItems: 1, maximumRowsRead: 1, maximumBytesRead: 32 * 1024 });
    } finally { paginate.mockRestore(); }
  });
});

test("SDK nonprogress is explicit unavailability rather than an endless empty continuation", async () => {
  const f = await fixture();
  await f.a.run(async ctx => {
    const prototype: unknown = Object.getPrototypeOf(ctx.db.query("savedFolders").withIndex("by_user", q => q.eq("userId", f.userId)));
    if (!hasPaginator(prototype)) throw new Error("Actual SDK query prototype lacks paginate");
    const paginate = vi.spyOn(prototype, "paginate").mockReturnValue(Promise.resolve({ page: [], continueCursor: null, isDone: false }));
    try { expect(await readSavedFactsPage(ctx, { capability: f.capability })).toEqual({ kind: "unavailable", reason: "source_did_not_advance" }); }
    finally { paginate.mockRestore(); }
  });
});


test("deleted-folder tombstone clock has a fixed point-read bound and preserves exact visible time", async () => {
  const f = await fixture();
  const folderId = await f.t.run(async ctx => {
    const folderId = await ctx.db.insert("savedFolders", { userId: f.userId, name: "Removed", normalizedName: "removed", createdAt: 1, updatedAt: 1 });
    const manifestId = await ctx.db.insert("savedFolderManifests", { userId: f.userId, folderId, operationId: "delete", requestedAt: 100, generation: "g", createdAt: 100, updatedAt: 100, expiresAt: Date.now() + 10_000,
      captured: { epoch: 0, updatedAt: 1, name: "Removed", createdAt: 1 }, state: { kind: "deleted", count: 1 } });
    await ctx.db.insert("savedItems", { userId: f.userId, hadithId: f.hadithId, folderId, folderUpdatedAt: 1, bookmarkCreatedAt: 1, createdAt: 1, updatedAt: 1 });
    await ctx.db.insert("librarySyncMarks", { userId: f.userId, key: `folder:${folderId}`, operationId: "delete", commandKind: "folder_delete", at: 100, detail: { kind: "folder_manifest", manifestId } });
    await ctx.db.delete(folderId);
    return folderId;
  });
  const first = page(await f.a.query(api.librarySync.savedFactsPage, { capability: f.capability }));
  if (first.kind !== "page") throw new Error("Missing source continuation");
  await f.a.run(async ctx => {
    const gets = vi.spyOn(ctx.db, "get"), queries = vi.spyOn(ctx.db, "query");
    try {
      const result = page(await readSavedFactsPage(ctx, { capability: f.capability, continuation: first.next }));
      expect(result.facts[0]).toMatchObject({ kind: "item", value: { folderUpdatedAt: 100, updatedAt: 100 } });
      if (result.facts[0]?.kind !== "item") throw new Error("Missing private item");
      expect(result.facts[0].value.folderId).toBeUndefined();
      expect(gets).toHaveBeenCalledExactlyOnceWith(folderId);
      expect(queries.mock.calls.map(call => call[0])).toEqual(["users", "librarySyncBindings", "librarySyncVersions", "savedItems", "librarySyncMarks"]);
    } finally { gets.mockRestore(); queries.mockRestore(); }
  });
});
