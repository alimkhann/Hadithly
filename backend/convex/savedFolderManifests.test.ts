/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { FOLDER_MANIFEST_LEASE_MS, prepareFolderManifest, readPreparedFolderManifest } from "./lib/savedFolderManifests";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

async function fixture(count = 501) {
  vi.useFakeTimers(); vi.setSystemTime(1_000_000);
  const t = convexTest(schema, modules);
  const owner = t.withIdentity({ subject: "manifest-owner", tokenIdentifier: "fixture:manifest-owner" });
  const other = t.withIdentity({ subject: "manifest-other", tokenIdentifier: "fixture:manifest-other" });
  const userId = await owner.mutation(api.users.ensureCurrentUser, {});
  const otherId = await other.mutation(api.users.ensureCurrentUser, {});
  const folderId = await owner.mutation(api.library.createSavedFolder, { name: "Manifest fixture" });
  // Use older imported metadata, with no membership epoch on installed-style rows.
  await t.run(ctx => ctx.db.patch(folderId, { updatedAt: 1_000 }));
  const ids: Id<"hadiths">[] = [];
  for (let start = 0; start < count; start += 100) await t.run(async ctx => {
    for (let index = start; index < Math.min(start + 100, count); index++) {
      const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: String(index + 1), volumeId: "1", collectionName: "Bukhari", referenceDisplay: `Bukhari ${index + 1}`, arabicText: "Provider fixture stays outside the manifest", createdAt: 1 });
      ids.push(hadithId);
      await ctx.db.insert("savedItems", { userId, hadithId, folderId, folderUpdatedAt: 1_000, bookmarkCreatedAt: 1_000,
        ...(index === 0 ? { noteContent: "Private original stays in Saved", noteCreatedAt: 1_000, noteUpdatedAt: 1_000 } : {}), createdAt: 1_000, updatedAt: 1_000 });
    }
  });
  async function start(id = "prepare-delete", folder = folderId, account = userId) {
    const result = await t.run(ctx => prepareFolderManifest(ctx, account, { id, at: 10_000, folderId: folder }));
    if (result.kind !== "manifest") throw new Error(`Unexpected fixture preparation ${result.reason}`);
    return { id: result.id, generation: result.generation };
  }
  return { t, owner, other, userId, otherId, folderId, ids, start };
}

test.each([501, 2_001])("preparation resumes bounded pages, freezes every identity and has no visible effect: %s", async count => {
  const f = await fixture(count), manifest = await f.start();
  expect(await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 })).toEqual({ kind: "scanning", count: 50, read: 50 });
  expect(await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 })).toEqual({ kind: "ignored" });
  expect(await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, generation: "old-generation", step: 1 })).toEqual({ kind: "ignored" });
  await expect(f.t.run(ctx => readPreparedFolderManifest(ctx, f.userId, { ...manifest, cursor: null }))).rejects.toThrow("FOLDER_MANIFEST_UNAVAILABLE");
  expect(await f.t.mutation(internal.librarySync.purgeFolderManifestMembers, manifest)).toEqual({ deleted: 0 });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.start()).toEqual(manifest);
  expect((await f.t.run(ctx => ctx.db.get(manifest.id)))?.state).toEqual({ kind: "prepared", count });
  const seen: string[] = [];
  let cursor: string | null = null;
  do {
    const page = await f.t.run(ctx => readPreparedFolderManifest(ctx, f.userId, { ...manifest, cursor }));
    expect(page.page.length).toBeLessThanOrEqual(50);
    for (const member of page.page) { expect(member.ordinal).toBe(seen.length); seen.push(member.hadithId); }
    expect(JSON.stringify(page.page)).not.toContain("Private original");
    expect(JSON.stringify(page.page)).not.toContain("Provider fixture");
    cursor = page.isDone ? null : page.continueCursor;
  } while (cursor !== null);
  expect(new Set(seen)).toEqual(new Set(f.ids));
  const saved = await f.owner.query(api.library.listSavedSnapshot, {});
  expect(saved.items).toHaveLength(count);
  expect(saved.items.every(item => item.folderId === f.folderId)).toBe(true);
  expect(saved.items.find(item => item.hadithId === f.ids[0])?.noteContent).toBe("Private original stays in Saved");
  await expect(f.t.run(ctx => readPreparedFolderManifest(ctx, f.otherId, { ...manifest, cursor: null }))).rejects.toThrow("FOLDER_MANIFEST_UNAVAILABLE");
});

test("a real accepted move during scanning abandons all prepared facts without partially deleting Saved", async () => {
  const f = await fixture(), manifest = await f.start();
  await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 });
  const binding = await f.owner.mutation(api.librarySync.openBinding, {});
  await f.owner.mutation(api.librarySync.applyBatch, { capability: binding.capability, frame: { clientKey: "move-during-scan", sequence: 1,
    batch: { id: "move-during-scan", operations: [{ id: "remove-last-member", revision: "r1", at: 20_000, command: { kind: "membership_put", hadithId: f.ids[500], folder: { kind: "none" } } }] } } });
  expect(await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 1 })).toEqual({ kind: "abandoned", reason: "changed" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifestMembers").collect())).toEqual([]);
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "prepare-delete", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "changed" });
  const saved = await f.owner.query(api.library.listSavedSnapshot, {});
  expect(saved.folders[0]._id).toBe(f.folderId);
  expect(saved.items.filter(item => item.folderId === f.folderId)).toHaveLength(500);
  expect(saved.items).toHaveLength(501);
});

test("a same-name replacement never substitutes for the captured original folder", async () => {
  const f = await fixture(2), manifest = await f.start();
  await f.owner.mutation(api.library.deleteSavedFolder, { folderId: f.folderId });
  const replacement = await f.owner.mutation(api.library.createSavedFolder, { name: "Manifest fixture" });
  expect(await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 })).toEqual({ kind: "abandoned", reason: "missing_folder" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.owner.query(api.library.listSavedSnapshot, {})).folders[0]._id).toBe(replacement);
});

test("prepared fact enumeration rechecks the epoch after the last scan page", async () => {
  const f = await fixture(1), manifest = await f.start();
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  vi.setSystemTime(1_001_000);
  await f.owner.mutation(api.library.assignSavedFolder, { hadithId: f.ids[0] });
  await expect(f.t.run(ctx => readPreparedFolderManifest(ctx, f.userId, { ...manifest, cursor: null }))).rejects.toThrow("FOLDER_MANIFEST_UNAVAILABLE");
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "prepare-delete", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "changed" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
});

test("retry of expired or purging preparation reports a terminal conflict instead of a live handle", async () => {
  const f = await fixture(1);
  await f.start(); await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  vi.setSystemTime(Date.now() + FOLDER_MANIFEST_LEASE_MS);
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "prepare-delete", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "expired" });
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {});
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "prepare-delete", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "expired" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
});

test("operation replay is exact, foreign folders are unavailable, and work bounds do not cap membership", async () => {
  const f = await fixture(0), first = await f.start();
  expect(await f.start()).toEqual(first);
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.otherId, { id: "foreign-folder", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "missing_folder" });
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "another-delete", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "folder_busy" });
  const folders: Id<"savedFolders">[] = [];
  for (let index = 0; index < 4; index++) {
    const id = await f.owner.mutation(api.library.createSavedFolder, { name: `Concurrent ${index}` });
    await f.t.run(ctx => ctx.db.patch(id, { updatedAt: 1_000 })); folders.push(id);
  }
  await expect(f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "prepare-delete", at: 10_000, folderId: folders[0] }))).rejects.toThrow("FOLDER_MANIFEST_OPERATION_CONFLICT");
  for (let index = 0; index < 3; index++) await f.start(`concurrent-${index}`, folders[index]);
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "fifth", at: 10_000, folderId: folders[3] }))).toEqual({ kind: "conflict", reason: "owner_busy" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
});

test("progress renews inactivity rather than imposing a total runtime/member cap", async () => {
  const f = await fixture(101), manifest = await f.start();
  vi.setSystemTime(Date.now() + 25 * 60_000);
  expect((await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 })).kind).toBe("scanning");
  vi.setSystemTime(Date.now() + 25 * 60_000);
  expect((await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 1 })).kind).toBe("scanning");
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.t.run(ctx => ctx.db.get(manifest.id)))?.state).toEqual({ kind: "prepared", count: 101 });
});

test("an expired scan cleans every partial fact in bounded steps without a deletion", async () => {
  const f = await fixture(101), manifest = await f.start();
  await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 });
  vi.setSystemTime(Date.now() + FOLDER_MANIFEST_LEASE_MS);
  expect(await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 1 })).toEqual({ kind: "abandoned", reason: "expired" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.get(manifest.id))).toBeNull();
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifestMembers").collect())).toEqual([]);
  expect((await f.owner.query(api.library.listSavedSnapshot, {})).items.filter(item => item.folderId === f.folderId)).toHaveLength(101);
});

test("automatic recovery completes a preparation after its scheduled delivery is interrupted", async () => {
  const f = await fixture(501), manifest = await f.start();
  await f.t.run(async ctx => { for (const scheduled of await ctx.db.system.query("_scheduled_functions").collect()) await ctx.scheduler.cancel(scheduled._id); });
  vi.setSystemTime(Date.now() + 6 * 60_000);
  expect(await f.t.mutation(internal.librarySync.recoverFolderManifests, {})).toEqual({ scheduled: 1 });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.t.run(ctx => ctx.db.get(manifest.id)))?.state).toEqual({ kind: "prepared", count: 501 });
});

test("prepared expiry pages headers and facts without removing unexpired preparation", async () => {
  const f = await fixture(101), manifest = await f.start();
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  const header = await f.t.run(ctx => ctx.db.get(manifest.id));
  if (!header) throw new Error("Missing prepared fixture");
  await f.t.run(async ctx => {
    for (let index = 0; index < 28; index++) await ctx.db.insert("savedFolderManifests", { userId: f.otherId, folderId: f.folderId, operationId: `expired-${index}`, requestedAt: 10_000,
      generation: `expired-${index}`, createdAt: 1, updatedAt: 1, expiresAt: Date.now(), captured: header.captured, state: { kind: "prepared", count: 0 } });
  });
  expect(await f.t.mutation(internal.librarySync.pruneFolderManifests, {})).toEqual({ scheduled: 25 });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifests").collect())).toMatchObject([{ _id: manifest.id }]);
  expect(await f.t.mutation(internal.librarySync.purgeFolderManifestMembers, { ...manifest, generation: "foreign-generation" })).toEqual({ deleted: 0 });
  vi.setSystemTime(Date.now() + FOLDER_MANIFEST_LEASE_MS);
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {});
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifestMembers").collect())).toEqual([]);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifests").collect())).toEqual([]);
});

test("account erasure fences late pages and cleans facts without touching another owner", async () => {
  const f = await fixture(101), manifest = await f.start();
  await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 0 });
  const otherFolder = await f.other.mutation(api.library.createSavedFolder, { name: "Other manifest" });
  await f.t.run(async ctx => {
    await ctx.db.patch(otherFolder, { updatedAt: 1_000 });
    await ctx.db.insert("savedItems", { userId: f.otherId, hadithId: f.ids[0], folderId: otherFolder, noteContent: "Other private original", createdAt: 1_000, updatedAt: 1_000 });
  });
  const otherManifest = await f.start("prepare-delete", otherFolder, f.otherId);
  expect(await f.t.mutation(internal.librarySync.eraseFolderManifestOwner, { userId: f.otherId })).toEqual({ deleted: 0 });
  await f.owner.mutation(api.users.deleteCurrentUser, { authorization: (await f.owner.mutation(api.users.prepareAccountDeletion, {})).authorization });
  await f.t.mutation(internal.librarySync.advanceFolderManifest, { ...manifest, step: 1 });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifests").collect())).toMatchObject([{ _id: otherManifest.id, userId: f.otherId, state: { kind: "prepared", count: 1 } }]);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifestMembers").collect())).toMatchObject([{ userId: f.otherId, manifestId: otherManifest.id }]);
  expect(await f.t.run(ctx => prepareFolderManifest(ctx, f.userId, { id: "after-erasure", at: 10_000, folderId: f.folderId }))).toEqual({ kind: "conflict", reason: "missing_owner" });
  expect((await f.other.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("Other private original");
});
