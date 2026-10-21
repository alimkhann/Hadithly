/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { readSavedHead, readSavedReference, readSavedText, SAVED_REFERENCE_BYTES, SAVED_TEXT_BYTES } from "./lib/librarySavedReads";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());
async function fixture() {
  const t = convexTest(schema, modules), a = t.withIdentity({ subject: "reads-owner", tokenIdentifier: "fixture:reads-owner" }), b = t.withIdentity({ subject: "reads-other", tokenIdentifier: "fixture:reads-other" });
  const userId = await a.mutation(api.users.ensureCurrentUser, {}), otherId = await b.mutation(api.users.ensureCurrentUser, {});
  const hadithId = await t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", providerHadithId: "1", collectionSlug: "bukhari", volumeId: "1", collectionName: "Bukhari", referenceDisplay: "Bukhari 1", arabicText: "  إِنَّمَا\n", englishText: 'Actions "by intentions".\n', createdAt: 1 }));
  const binding = await a.mutation(api.librarySync.openManifestBinding, {});
  return { t, a, b, userId, otherId, hadithId, binding, request: { capability: binding.capability, hadithId } };
}
test("compact head observes Saved independently of positions and never joins library or public rows", async () => {
  const f = await fixture(), request = { capability: f.binding.capability };
  expect(await f.a.query(api.librarySync.savedHead, request)).toEqual({ ownerKey: f.userId, version: 0 });
  await f.a.mutation(api.library.toggleSavedBookmark, { hadithId: f.hadithId });
  const changed = await f.a.query(api.librarySync.savedHead, request); expect(changed).toEqual({ ownerKey: f.userId, version: 1 });
  await f.a.mutation(api.library.saveReadingProgress, { collectionSlug: "bukhari", hadithId: f.hadithId });
  expect((await f.a.query(api.librarySync.positionsSnapshot, {})).version).toBe(1);
  await f.b.mutation(api.library.toggleSavedBookmark, { hadithId: f.hadithId });
  expect(await f.a.query(api.librarySync.savedHead, request)).toEqual(changed);
  await f.a.run(async ctx => {
    const queries = vi.spyOn(ctx.db, "query"), gets = vi.spyOn(ctx.db, "get");
    try { expect(await readSavedHead(ctx, request)).toEqual(changed); expect(queries.mock.calls.map(call => call[0])).toEqual(["users", "librarySyncBindings", "librarySyncVersions"]); expect(gets).not.toHaveBeenCalled(); }
    finally { queries.mockRestore(); gets.mockRestore(); }
  });
  await f.t.run(ctx => ctx.db.delete(f.hadithId)); expect(await f.a.query(api.librarySync.savedHead, request)).toEqual(changed);
});
test.each([-1, 0.5, Number.MAX_SAFE_INTEGER + 1])("head refuses invalid private counter %s", async version => {
  const f = await fixture(); await f.t.run(ctx => ctx.db.insert("librarySyncVersions", { userId: f.userId, kind: "saved", version }));
  await expect(f.a.query(api.librarySync.savedHead, { capability: f.binding.capability })).rejects.toThrow("SYNC_SAVED_VERSION_INVARIANT");
});
test("metadata excludes passages and private notes while full text preserves the exact owned target", async () => {
  const f = await fixture(); await f.a.mutation(api.library.upsertSavedNote, { hadithId: f.hadithId, content: "Private note never belongs in public hydration" });
  const reference = await f.a.query(api.librarySync.savedReference, f.request), text = await f.a.query(api.librarySync.savedText, f.request);
  expect(reference).toEqual({ kind: "available", ownerKey: f.userId, hadithId: f.hadithId, reference: { _id: f.hadithId, providerHadithId: "1", collectionSlug: "bukhari", volumeId: "1", collectionName: "Bukhari", referenceDisplay: "Bukhari 1" } });
  if (text.kind !== "available") throw new Error("Expected full cached text");
  expect(text.hadith).toMatchObject({ _id: f.hadithId, arabicText: "  إِنَّمَا\n", englishText: 'Actions "by intentions".\n' });
  expect(JSON.stringify(reference)).not.toMatch(/arabicText|englishText|Private note|version|capability/); expect(JSON.stringify(text)).not.toMatch(/Private note|version|capability/);
  await f.a.run(async ctx => {
    const queries = vi.spyOn(ctx.db, "query"), gets = vi.spyOn(ctx.db, "get");
    try { expect(await readSavedReference(ctx, f.request)).toEqual(reference); expect(queries.mock.calls.map(call => call[0])).toEqual(["users", "librarySyncBindings", "savedItems"]); expect(gets.mock.calls).toEqual([[f.hadithId]]); }
    finally { queries.mockRestore(); gets.mockRestore(); }
  });
  const directory = process.env.HADITHLY_LIBRARY_SYNC_CONTRACT_DIR;
  if (directory) { const { writeFileSync } = await import("node:fs"), { resolve } = await import("node:path"); writeFileSync(resolve(directory, "saved-reads-parity.json"), JSON.stringify({ head: await f.a.query(api.librarySync.savedHead, { capability: f.binding.capability }), reference, text })); }
});
test.each(["bookmarks", "favorites", "notes"])("legacy %s hydrates through bounded owner and target lookups", async source => {
  const f = await fixture();
  await f.t.run(async ctx => { if (source === "bookmarks") await ctx.db.insert("bookmarks", { userId: f.userId, hadithId: f.hadithId, createdAt: 1 }); else if (source === "favorites") await ctx.db.insert("favorites", { userId: f.userId, hadithId: f.hadithId, createdAt: 1 }); else await ctx.db.insert("notes", { userId: f.userId, hadithId: f.hadithId, content: "Private", createdAt: 1, updatedAt: 2 }); });
  expect(await f.a.query(api.librarySync.savedReference, f.request)).toMatchObject({ kind: "available", ownerKey: f.userId, hadithId: f.hadithId }); expect(await f.a.query(api.librarySync.savedText, f.request)).toMatchObject({ kind: "available", ownerKey: f.userId, hadithId: f.hadithId });
});
test("unsaved and foreign-only targets return missing without a public get", async () => {
  const f = await fixture(), missing = { kind: "missing", ownerKey: f.userId, hadithId: f.hadithId };
  expect(await f.a.query(api.librarySync.savedReference, f.request)).toEqual(missing);
  await f.b.mutation(api.library.upsertSavedNote, { hadithId: f.hadithId, content: "Foreign private" });
  await f.a.run(async ctx => {
    const queries = vi.spyOn(ctx.db, "query"), gets = vi.spyOn(ctx.db, "get");
    try { expect(await readSavedText(ctx, f.request)).toEqual(missing); expect(queries.mock.calls.map(call => call[0])).toEqual(["users", "librarySyncBindings", "savedItems", "bookmarks", "favorites", "notes"]); expect(gets).not.toHaveBeenCalled(); }
    finally { queries.mockRestore(); gets.mockRestore(); }
  });
});
test("public changes or disappearance never mutate private facts or revision", async () => {
  const f = await fixture(); await f.a.mutation(api.library.upsertSavedNote, { hadithId: f.hadithId, content: "Retain exact private note" });
  const before = await f.t.run(ctx => ctx.db.query("savedItems").withIndex("by_user_hadith", q => q.eq("userId", f.userId).eq("hadithId", f.hadithId)).unique()); if (!before) throw new Error("Missing private fixture");
  const head = await f.a.query(api.librarySync.savedHead, { capability: f.binding.capability });
  await f.t.run(ctx => ctx.db.patch(f.hadithId, { collectionName: "Updated public label", arabicText: "Updated public passage" }));
  expect(await f.a.query(api.librarySync.savedReference, f.request)).toMatchObject({ kind: "available", reference: { collectionName: "Updated public label" } }); expect(await f.a.query(api.librarySync.savedText, f.request)).toMatchObject({ kind: "available", hadith: { arabicText: "Updated public passage" } });
  await f.t.run(ctx => ctx.db.delete(f.hadithId));
  expect(await f.a.query(api.librarySync.savedReference, f.request)).toEqual({ kind: "missing", ownerKey: f.userId, hadithId: f.hadithId }); expect(await f.a.query(api.librarySync.savedText, f.request)).toEqual({ kind: "missing", ownerKey: f.userId, hadithId: f.hadithId });
  expect(await f.a.query(api.librarySync.savedHead, { capability: f.binding.capability })).toEqual(head); expect(await f.t.run(ctx => ctx.db.get(before._id))).toEqual(before);
});
test("full passage larger than the fact envelope preserves all text including JSON escapes", async () => {
  const f = await fixture(), arabicText = "ع\n".repeat(100_000), englishText = '"\\\u0000'.repeat(30_000);
  await f.a.mutation(api.library.toggleSavedBookmark, { hadithId: f.hadithId }); await f.t.run(ctx => ctx.db.patch(f.hadithId, { arabicText, englishText }));
  const reference = await f.a.query(api.librarySync.savedReference, f.request), text = await f.a.query(api.librarySync.savedText, f.request);
  expect(Buffer.byteLength(JSON.stringify(reference))).toBeLessThan(SAVED_REFERENCE_BYTES); if (text.kind !== "available") throw new Error("Valid full passage unavailable");
  expect(text.hadith.arabicText).toBe(arabicText); expect(text.hadith.englishText).toBe(englishText); expect(Buffer.byteLength(JSON.stringify(text))).toBeGreaterThan(64 * 1024); expect(Buffer.byteLength(JSON.stringify(text))).toBeLessThan(SAVED_TEXT_BYTES);
});
test("explicit metadata and fulltext bounds return unavailable without partial text", async () => {
  const f = await fixture(); await f.a.mutation(api.library.toggleSavedBookmark, { hadithId: f.hadithId }); await f.t.run(ctx => ctx.db.patch(f.hadithId, { collectionName: "ع".repeat(SAVED_REFERENCE_BYTES) }));
  expect(await f.a.query(api.librarySync.savedReference, f.request)).toEqual({ kind: "unavailable", ownerKey: f.userId, hadithId: f.hadithId, reason: "reference_too_large" });
  // Adapter robustness beyond the hosted document limit, not accepted hosted data.
  await f.a.run(async ctx => {
    const original = await ctx.db.get(f.hadithId); if (!original) throw new Error("Missing fixture"); const gets = vi.spyOn(ctx.db, "get").mockResolvedValue({ ...original, arabicText: "\u0000".repeat(Math.ceil(SAVED_TEXT_BYTES / 6)) });
    try { expect(await readSavedText(ctx, f.request)).toEqual({ kind: "unavailable", ownerKey: f.userId, hadithId: f.hadithId, reason: "text_too_large" }); } finally { gets.mockRestore(); }
  });
});
test("head metadata and fulltext enforce JWT binding owner protocol key and expiry", async () => {
  const f = await fixture(), old = await f.a.mutation(api.librarySync.openBinding, {});
  for (const endpoint of [api.librarySync.savedReference, api.librarySync.savedText]) { await expect(f.t.query(endpoint, f.request)).rejects.toThrow("Unauthenticated"); await expect(f.b.query(endpoint, f.request)).rejects.toThrow("SYNC_OWNER_MISMATCH"); await expect(f.a.query(endpoint, { ...f.request, capability: old.capability })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED"); await expect(f.a.query(endpoint, { ...f.request, capability: "ع".repeat(257) })).rejects.toThrow("SYNC_INVALID_SAVED_REQUEST"); }
  await expect(f.t.query(api.librarySync.savedHead, { capability: f.binding.capability })).rejects.toThrow("Unauthenticated"); await expect(f.b.query(api.librarySync.savedHead, { capability: f.binding.capability })).rejects.toThrow("SYNC_OWNER_MISMATCH"); await expect(f.a.query(api.librarySync.savedHead, { capability: old.capability })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  await f.t.run(async ctx => { const binding = await ctx.db.query("librarySyncBindings").withIndex("by_user", q => q.eq("userId", f.userId)).filter(q => q.eq(q.field("protocol"), "manifest_v2")).first(); if (!binding) throw new Error("Missing binding"); await ctx.db.patch(binding._id, { savedCursorKey: undefined }); });
  await expect(f.a.query(api.librarySync.savedHead, { capability: f.binding.capability })).rejects.toThrow("SYNC_BINDING_REOPEN_REQUIRED"); const next = await f.a.mutation(api.librarySync.openManifestBinding, {}); vi.useFakeTimers(); vi.setSystemTime(next.validUntil + 1);
  await expect(f.a.query(api.librarySync.savedReference, { ...f.request, capability: next.capability })).rejects.toThrow("SYNC_BINDING_EXPIRED"); await expect(f.a.query(api.librarySync.savedText, { ...f.request, capability: next.capability })).rejects.toThrow("SYNC_BINDING_EXPIRED"); await expect(f.a.query(api.librarySync.savedHead, { capability: next.capability })).rejects.toThrow("SYNC_BINDING_EXPIRED");
});
