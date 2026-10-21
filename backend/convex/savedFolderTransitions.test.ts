/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import { SYNC_OUTCOME_BYTES, SYNC_OUTCOME_PAGE, type SyncBinding, type SyncCommand, type SyncFrame, type SyncOutcomePageRequest } from "./lib/librarySyncPolicy";
import { prepareFolderManifest, advanceFolderManifest } from "./lib/savedFolderManifests";
import { holdFolderFrame } from "./lib/librarySyncFrames";
import { beginFolderRestoration, commitPreparedFolderDeletion } from "./lib/savedFolderTransitions";
import { FOLDER_HANDLE_RETENTION_MS, FOLDER_WORK_LEASE_MS } from "./lib/savedFolderPolicy";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

async function fixture(count = 9) {
  vi.useFakeTimers(); vi.setSystemTime(1_000_000);
  const t = convexTest(schema, modules);
  const a = t.withIdentity({ subject: "logical-owner", tokenIdentifier: "fixture:logical-owner" });
  const b = t.withIdentity({ subject: "logical-other", tokenIdentifier: "fixture:logical-other" });
  const userId = await a.mutation(api.users.ensureCurrentUser, {}), otherId = await b.mutation(api.users.ensureCurrentUser, {});
  const folderId = await t.run(ctx => ctx.db.insert("savedFolders", { userId, name: "Logical folder", normalizedName: "logical folder", createdAt: 50_000, updatedAt: 50_000 }));
  const otherFolder = await b.mutation(api.library.createSavedFolder, { name: "Other private folder" });
  const ids: Id<"hadiths">[] = [];
  for (let start = 0; start < count; start += 100) await t.run(async ctx => {
    for (let index = start; index < Math.min(start + 100, count); index++) {
      const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: String(index + 1), volumeId: "1", collectionName: "Bukhari", referenceDisplay: `Bukhari ${index + 1}`, arabicText: "نص", createdAt: 1 });
      ids.push(hadithId);
      await ctx.db.insert("savedItems", { userId, hadithId, folderId, folderUpdatedAt: 50_000, bookmarkCreatedAt: 50_000, createdAt: 50_000, updatedAt: 50_000,
        ...(index === 0 ? { noteContent: "Private original", noteCreatedAt: 50_000, noteUpdatedAt: 50_000 } : {}) });
      if (index === 0) await ctx.db.insert("savedItems", { userId: otherId, hadithId, folderId: otherFolder, noteContent: "Other original", createdAt: 50_000, updatedAt: 50_000 });
    }
  });
  const frame: SyncFrame = { clientKey: "logical-delete-device", sequence: 1, batch: { id: "logical-delete-batch", operations: [{ id: "logical-delete", revision: "r1", at: 100_000, command: { kind: "folder_delete", folder: { kind: "server", id: folderId } } }] } };
  const work = await t.run(async ctx => {
    const prepared = await prepareFolderManifest(ctx, userId, { id: "logical-delete", at: 100_000, folderId });
    if (prepared.kind !== "manifest") throw new Error("Preparation refused");
    const held = await holdFolderFrame(ctx, userId, frame, { id: prepared.id, generation: prepared.generation });
    if (held.kind !== "pending") throw new Error("Missing held delete");
    return { id: prepared.id, generation: prepared.generation, pending: held.pending };
  });
  // Domain fixtures intentionally stop prepared; public automatic delivery has
  // separate actual-endpoint tests. Stale scheduled scan steps are CAS no-ops.
  for (let step = 0; step <= Math.ceil(count / 50); step++) {
    const result = await t.run(ctx => advanceFolderManifest(ctx, { id: work.id, generation: work.generation, step }));
    if (result.kind === "prepared") break;
  }
  async function commit() { return t.run(ctx => commitPreparedFolderDeletion(ctx, userId, work)); }
  async function begin(id = "logical-restore", at = 200_000) {
    const result = await t.run(ctx => beginFolderRestoration(ctx, userId, { id, at, deletionId: "logical-delete" }));
    if (result.kind !== "restoring") throw new Error("Restore refused");
    const restoreFrame: SyncFrame = { clientKey: "logical-restore-device", sequence: 1, batch: { id: "logical-restore-batch", operations: [{ id, revision: "r1", at,
      command: { kind: "folder_restore", deletionId: "logical-delete", name: "Logical folder", hadithIds: [] } }] } };
    const held = await t.run(ctx => holdFolderFrame(ctx, userId, restoreFrame, result));
    if (held.kind !== "pending") throw new Error("Missing held restore");
    return { id: result.id, generation: result.generation, operationId: result.operationId, pending: held.pending, frame: restoreFrame };
  }
  let request = 0;
  async function send(command: SyncCommand, at: number) {
    const index = request++, capability = (await a.mutation(api.librarySync.openBinding, {})).capability;
    const reply = await a.mutation(api.librarySync.applyBatch, { capability, frame: { clientKey: `interleave-${index}`, sequence: 1,
      batch: { id: `interleave-${index}`, operations: [{ id: `operation-${index}`, revision: "r1", at, command }] } } });
    if (reply.kind !== "accepted") throw new Error("Interleaving refused");
    return reply.committed.reply.receipts[0].outcome;
  }
  async function header() { const value = await t.run(ctx => ctx.db.get(work.id)); if (!value) throw new Error("Missing header"); return value; }
  async function finishRestoration() {
    // The published convex-test type exposes no maxIterations override; a full
    // 2,001-member restore correctly needs more than its default 100 steps.
    for (let step = 0; step < Math.ceil(count / 4) * 2 + 20; step++) {
      vi.runOnlyPendingTimers();
      await t.finishInProgressScheduledFunctions();
      const state = (await header()).state;
      if (state.kind === "restored" && state.normalization.kind === "done") {
        await t.finishAllScheduledFunctions(vi.runAllTimers);
        return;
      }
    }
    throw new Error("Restoration did not finish within its bounded fixture work");
  }
  let outcomeBinding: SyncBinding | undefined;
  async function outcomeCapability() {
    if (!outcomeBinding || outcomeBinding.validUntil <= Date.now()) outcomeBinding = await a.mutation(api.librarySync.openManifestBinding, {});
    return outcomeBinding.capability;
  }
  return { t, a, b, userId, folderId, ids, work, frame, commit, begin, send, header, finishRestoration, outcomeCapability };
}

test.each([501, 2_001])("logical deletion and staged restore cover the full %s-member set with bounded receipts", async count => {
  const f = await fixture(count);
  expect(await f.commit()).toMatchObject({ kind: "folder_deleted_manifest", count });
  const deleted = await f.a.query(api.library.listSavedSnapshot, {});
  expect(deleted.folders).toEqual([]); expect(deleted.items).toHaveLength(count);
  expect(deleted.items.every(item => item.folderId === undefined && item.updatedAt === 100_000)).toBe(true);
  const capability = await f.outcomeCapability();
  const deletionProof = await f.a.query(api.librarySync.pollPending, { capability, pending: f.work.pending });
  expect(deletionProof).toMatchObject({ kind: "accepted", committed: { reply: { receipts: [{ outcome: { kind: "folder_deleted_manifest", count } }] } } });
  expect(JSON.stringify(deletionProof).length).toBeLessThan(2_000);
  const restore = await f.begin();
  expect(await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 })).toEqual({ kind: "staged", read: 4 });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toEqual([]);
  await f.finishRestoration();
  const state = (await f.header()).state;
  expect(state).toMatchObject({ kind: "restored", restored: count, superseded: 0, missing: 0, normalization: { kind: "done" } });
  const saved = await f.a.query(api.library.listSavedSnapshot, {});
  expect(saved.folders).toHaveLength(1); expect(saved.items.filter(item => item.folderId === saved.folders[0]._id)).toHaveLength(count);
  expect(saved.items.find(item => item.hadithId === f.ids[0])?.noteContent).toBe("Private original");
  const result = await f.a.query(api.librarySync.pollPending, { capability, pending: restore.pending });
  expect(result).toMatchObject({ kind: "accepted", committed: { reply: { receipts: [{ outcome: { kind: "folder_restored_manifest", restored: count } }] } } });
  expect(JSON.stringify(result).length).toBeLessThan(2_000);
  expect((await f.b.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("Other original");
}, 240_000);

test("deletion50/100/75 and during/after restore ordering preserve exact visibility and frozen totals", async () => {
  const f = await fixture(); await f.commit();
  expect(await f.send({ kind: "membership_put", hadithId: f.ids[0], folder: { kind: "none" } }, 75_000)).toEqual({ kind: "preserved" });
  const restore = await f.begin();
  const base = { id: restore.id, generation: restore.generation, operationId: restore.operationId };
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { ...base, step: 0 });
  await f.send({ kind: "bookmark_remove", hadithId: f.ids[1] }, 150_000);
  await f.send({ kind: "membership_put", hadithId: f.ids[2], folder: { kind: "none" } }, 150_000);
  await f.send({ kind: "membership_put", hadithId: f.ids[3], folder: { kind: "none" } }, 75_000);
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items.every(item => item.folderId === undefined)).toBe(true);
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { ...base, step: 1 });
  expect(await f.t.mutation(internal.librarySync.advanceFolderRestoration, { ...base, step: 2 })).toEqual({ kind: "restored", read: 1 });
  const state = (await f.header()).state;
  if (state.kind !== "restored") throw new Error("Missing visibility flip");
  expect(state).toMatchObject({ restored: 7, superseded: 1, missing: 1, normalization: { kind: "pending" } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items.filter(item => item.folderId === state.destinationId)).toHaveLength(7);
  expect(await f.send({ kind: "membership_put", hadithId: f.ids[3], folder: { kind: "none" } }, 150_000)).toEqual({ kind: "superseded", reason: "newer_cloud" });
  await f.send({ kind: "membership_put", hadithId: f.ids[4], folder: { kind: "none" } }, 250_000);
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.header()).state).toMatchObject({ restored: 7, superseded: 1, missing: 1, normalization: { kind: "done" } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items.filter(item => item.folderId === state.destinationId)).toHaveLength(6);
});

test("one restore operation reserves the handle and an existing destination stays structurally locked", async () => {
  const f = await fixture(); await f.commit();
  const destination = await f.a.mutation(api.library.createSavedFolder, { name: "Logical folder" });
  const restore = await f.begin();
  expect(await f.t.run(ctx => beginFolderRestoration(ctx, f.userId, { id: "competing-undo", at: 200_000, deletionId: "logical-delete" }))).toMatchObject({ kind: "outcome", outcome: { kind: "superseded" } });
  await expect(f.a.mutation(api.library.deleteSavedFolder, { folderId: destination })).rejects.toThrow("SAVED_FOLDER_BUSY");
  const binding = await f.a.mutation(api.librarySync.openManifestBinding, {});
  await expect(f.a.mutation(api.librarySync.applyBatch, { capability: binding.capability, frame: { clientKey: "delete-locked", sequence: 1,
    batch: { id: "delete-locked", operations: [{ id: "delete-locked", revision: "r1", at: 1_000_000, command: { kind: "folder_delete", folder: { kind: "server", id: destination } } }] } } })).rejects.toThrow("SAVED_FOLDER_BUSY");
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.header()).state).toMatchObject({ kind: "restored", destinationId: destination });
  await f.a.mutation(api.library.deleteSavedFolder, { folderId: destination });
  expect(await f.t.run(ctx => beginFolderRestoration(ctx, f.userId, { id: "late-old-handle", at: 1_000_000, deletionId: "logical-delete" }))).toMatchObject({ kind: "outcome", outcome: { kind: "superseded" } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toEqual([]);
  expect(await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 })).toEqual({ kind: "ignored", read: 0 });
});

test("a destination created during staging is reused only at the atomic flip", async () => {
  const f = await fixture(); await f.commit(); const restore = await f.begin();
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toEqual([]);
  const created = await f.a.mutation(api.library.createSavedFolder, { name: "Logical folder" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.header()).state).toMatchObject({ kind: "restored", destinationId: created, restored: 9 });
});

test("Undo begun near retention expiry keeps its facts while making progress", async () => {
  const f = await fixture(); await f.commit();
  vi.setSystemTime((await f.header()).expiresAt - 10_000);
  const restore = await f.begin();
  const request = { id: restore.id, generation: restore.generation, operationId: restore.operationId };
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { ...request, step: 0 });
  vi.setSystemTime(Date.now() + 20 * 60_000);
  expect(await f.t.mutation(internal.librarySync.pruneFolderManifests, {})).toEqual({ scheduled: 0 });
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { ...request, step: 1 });
  vi.setSystemTime(Date.now() + 20 * 60_000);
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { ...request, step: 2 });
  expect((await f.header()).expiresAt).toBe(Date.now() + FOLDER_HANDLE_RETENTION_MS);
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.header()).state).toMatchObject({ kind: "restored", restored: 9 });
});

test("unconsumed expiry first materializes every deletion clock, then removes facts and tombstone", async () => {
  const f = await fixture(); await f.commit();
  vi.setSystemTime(Date.now() + FOLDER_HANDLE_RETENTION_MS);
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {});
  expect((await f.header()).state.kind).toBe("expiring");
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.get(f.work.id))).toBeNull();
  const rows = await f.t.run(ctx => ctx.db.query("savedItems").withIndex("by_user", q => q.eq("userId", f.userId)).collect());
  expect(rows.every(row => row.folderId === undefined && row.folderUpdatedAt === 100_000)).toBe(true);
  expect(await f.send({ kind: "membership_put", hadithId: f.ids[0], folder: { kind: "none" } }, 75_000)).toEqual({ kind: "preserved" });
  expect(await f.t.run(ctx => beginFolderRestoration(ctx, f.userId, { id: "expired-undo", at: 200_000, deletionId: "logical-delete" }))).toMatchObject({ kind: "outcome", outcome: { kind: "unresolved", reason: "folder_restore_unavailable" } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toEqual([]);
});

test("expired restored detail finishes visible materialization before cleanup", async () => {
  const f = await fixture(1); await f.commit(); const restore = await f.begin();
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 });
  const before = await f.a.query(api.library.listSavedSnapshot, {});
  vi.setSystemTime(Date.now() + FOLDER_HANDLE_RETENTION_MS);
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {});
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items).toEqual(before.items);
  vi.setSystemTime(Date.now() + FOLDER_WORK_LEASE_MS);
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {}); await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.get(f.work.id))).toBeNull();
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items).toEqual(before.items);
});

test("erasure during staging cannot create a destination from a late worker", async () => {
  const f = await fixture(); await f.commit(); const restore = await f.begin();
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 });
  await f.a.mutation(api.users.deleteCurrentUser, { authorization: (await f.a.mutation(api.users.prepareAccountDeletion, {})).authorization });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifests").collect())).toEqual([]);
  expect(await f.t.run(ctx => ctx.db.query("savedFolders").withIndex("by_user", q => q.eq("userId", f.userId)).collect())).toEqual([]);
  expect((await f.b.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("Other original");
});

test("an empty folder restores without exposing a pending destination", async () => {
  const f = await fixture(0); expect(await f.commit()).toMatchObject({ kind: "folder_deleted_manifest", count: 0 });
  await f.begin(); expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toEqual([]);
  await f.finishRestoration();
  expect((await f.header()).state).toMatchObject({ kind: "restored", restored: 0, superseded: 0, missing: 0 });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toHaveLength(1);
});

test("a newer folder mark rejects deletion before its tombstone could lose the clock", async () => {
  const f = await fixture(1);
  await f.t.run(ctx => ctx.db.insert("librarySyncMarks", { userId: f.userId, key: `folder:${f.folderId}`, operationId: "newer-folder-observation", commandKind: "folder_create", at: 150_000, detail: { kind: "write" } }));
  expect(await f.commit()).toEqual({ kind: "superseded", reason: "changed_since_delete" });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].folderId).toBe(f.folderId);
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
});

test("stalled restoration resumes automatically without a second reservation or partial visibility", async () => {
  const f = await fixture(); await f.commit(); const restore = await f.begin();
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 });
  await f.t.run(async ctx => { for (const scheduled of await ctx.db.system.query("_scheduled_functions").collect()) if (scheduled.state.kind === "pending") await ctx.scheduler.cancel(scheduled._id); });
  vi.setSystemTime(Date.now() + 6 * 60_000);
  expect(await f.t.mutation(internal.librarySync.recoverFolderManifests, {})).toEqual({ scheduled: 1 });
  await f.finishRestoration();
  expect((await f.header()).state).toMatchObject({ kind: "restored", restored: 9, normalization: { kind: "done" } });
});

test("older facet endpoints remove canonical staged members instead of leaving ghost membership", async () => {
  const f = await fixture(); await f.commit(); const restore = await f.begin();
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 });
  await f.a.mutation(api.library.toggleBookmark, { hadithId: f.ids[0] });
  await f.a.mutation(api.library.deleteNote, { hadithId: f.ids[0] });
  await f.a.mutation(api.library.toggleFavorite, { hadithId: f.ids[1] });
  await f.a.mutation(api.library.toggleBookmark, { hadithId: f.ids[1] });
  await f.a.mutation(api.library.toggleFavorite, { hadithId: f.ids[1] });
  await f.a.mutation(api.library.upsertNote, { hadithId: f.ids[2], content: "Updated through older endpoint" });
  await f.finishRestoration();
  expect((await f.header()).state).toMatchObject({ kind: "restored", restored: 7, missing: 2, superseded: 0 });
  const saved = await f.a.query(api.library.listSavedSnapshot, {});
  expect(saved.items.some(item => item.hadithId === f.ids[0] || item.hadithId === f.ids[1])).toBe(false);
  expect(saved.items.find(item => item.hadithId === f.ids[2])?.noteContent).toBe("Updated through older endpoint");
});

test("older note updates retain the existing note ID and original creation time", async () => {
  const f = await fixture(1);
  const original = await f.t.run(async ctx => {
    const item = await ctx.db.query("savedItems").withIndex("by_user_hadith", q => q.eq("userId", f.userId).eq("hadithId", f.ids[0])).unique();
    if (!item) throw new Error("Missing note fixture");
    await ctx.db.patch(item._id, { noteContent: undefined, noteCreatedAt: undefined, noteUpdatedAt: undefined });
    return ctx.db.insert("notes", { userId: f.userId, hadithId: f.ids[0], content: "Legacy note", createdAt: 10_000, updatedAt: 20_000 });
  });
  expect(await f.a.mutation(api.library.upsertNote, { hadithId: f.ids[0], content: "Updated old note" })).toBe(original);
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0]).toMatchObject({ noteContent: "Updated old note", noteCreatedAt: 10_000 });
});

async function outcomeRequest(f: Awaited<ReturnType<typeof fixture>>, pending = f.work.pending): Promise<SyncOutcomePageRequest> {
  const capability = (await f.a.mutation(api.librarySync.openManifestBinding, {})).capability;
  const exchange = await f.a.query(api.librarySync.pollPending, { capability, pending });
  if (exchange.kind !== "accepted") throw new Error("Missing terminal proof");
  const receipt = exchange.committed.reply.receipts[0], outcome = receipt.outcome;
  if (outcome.kind !== "folder_deleted_manifest" && outcome.kind !== "folder_restored_manifest") throw new Error("Missing manifest receipt");
  return { proof: { clientKey: exchange.committed.clientKey, sequence: exchange.committed.sequence, batchId: exchange.committed.reply.batchId, digest: exchange.committed.digest },
    receiptId: receipt.id, manifestId: outcome.manifestId, generation: outcome.generation, phase: outcome.kind === "folder_deleted_manifest" ? "delete" : "restore", start: 0 };
}
async function outcomePage(f: Awaited<ReturnType<typeof fixture>>, request: SyncOutcomePageRequest) {
  const capability = await f.outcomeCapability();
  return f.a.query(api.librarySync.outcomePage, { capability, request });
}

test.each([1, 50, 51, 501])("%s-member outcome pages are bounded, exact, private identity facts and replay identically", async count => {
  const f = await fixture(count); await f.commit();
  const original = await outcomeRequest(f), hadithIds: Id<"hadiths">[] = [], memberIds = new Set<string>();
  let request = original, pages = 0;
  while (pages++ < 12) {
    const page = await outcomePage(f, request);
    if (page.kind !== "page") throw new Error("Missing detail");
    expect(page).toEqual(await outcomePage(f, request));
    expect(page.ownerKey).toBe(f.userId); expect(page.request).toEqual(request);
    expect(page.rows.length).toBeLessThanOrEqual(SYNC_OUTCOME_PAGE);
    expect(new TextEncoder().encode(JSON.stringify(page)).byteLength).toBeLessThan(SYNC_OUTCOME_BYTES);
    expect(page.rows.map(row => row.ordinal)).toEqual(Array.from({ length: page.rows.length }, (_, i) => request.start + i));
    for (const row of page.rows) {
      expect(Object.keys(row).sort()).toEqual(["disposition", "hadithId", "memberId", "ordinal"]);
      expect(row.disposition).toBe("deleted"); expect(memberIds.has(row.memberId)).toBe(false);
      memberIds.add(row.memberId); hadithIds.push(row.hadithId);
    }
    expect(page.next).toBe(request.start + page.rows.length);
    if (page.done) break;
    expect(page.rows).toHaveLength(SYNC_OUTCOME_PAGE);
    request = { ...request, start: page.next };
  }
  expect(pages).toBe(Math.ceil(count / SYNC_OUTCOME_PAGE)); expect(hadithIds).toHaveLength(count);
  expect(new Set(hadithIds)).toEqual(new Set(f.ids));
  expect(await outcomePage(f, { ...original, start: count })).toMatchObject({ kind: "page", rows: [], next: count, done: true });
});

test("delete outcome pages stay historical while Undo changes the same manifest dispositions", async () => {
  const f = await fixture(); await f.commit();
  const request = await outcomeRequest(f), deleted = await outcomePage(f, request);
  const restore = await f.begin();
  await f.t.mutation(internal.librarySync.advanceFolderRestoration, { id: restore.id, generation: restore.generation, operationId: restore.operationId, step: 0 });
  expect(await outcomePage(f, request)).toEqual(deleted);
  await f.send({ kind: "bookmark_remove", hadithId: f.ids[1] }, 150_000);
  await f.send({ kind: "membership_put", hadithId: f.ids[2], folder: { kind: "none" } }, 150_000);
  await f.finishRestoration();
  expect(await outcomePage(f, request)).toEqual(deleted);
  const restoredRequest = await outcomeRequest(f, restore.pending), result = await outcomePage(f, restoredRequest);
  if (result.kind !== "page") throw new Error("Missing restored details");
  expect(result.done).toBe(true); expect(result.rows).toHaveLength(9);
  expect(result.rows.filter(row => row.disposition === "restored")).toHaveLength(7);
  expect(result.rows.filter(row => row.disposition === "missing").map(row => row.hadithId)).toEqual([f.ids[1]]);
  expect(result.rows.filter(row => row.disposition === "superseded").map(row => row.hadithId)).toEqual([f.ids[2]]);
  await f.send({ kind: "membership_put", hadithId: f.ids[4], folder: { kind: "none" } }, 250_000);
  expect(await outcomePage(f, restoredRequest)).toEqual(result);
});

test("outcome details require the JWT owner and its exact committed receipt proof", async () => {
  const f = await fixture(1); await f.commit();
  const request = await outcomeRequest(f), aBinding = await f.a.mutation(api.librarySync.openManifestBinding, {}), bBinding = await f.b.mutation(api.librarySync.openManifestBinding, {});
  await expect(f.b.query(api.librarySync.outcomePage, { capability: aBinding.capability, request })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  expect(await f.b.query(api.librarySync.outcomePage, { capability: bBinding.capability, request })).toEqual({ kind: "unavailable", ownerKey: bBinding.ownerKey, request, reason: "proof_unavailable" });
  const changed: SyncOutcomePageRequest[] = [
    { ...request, proof: { ...request.proof, clientKey: "wrong-device" } },
    { ...request, proof: { ...request.proof, sequence: 2 } },
    { ...request, proof: { ...request.proof, batchId: "wrong-batch" } },
    { ...request, proof: { ...request.proof, digest: "wrong-digest" } },
    { ...request, receiptId: "wrong-operation" }, { ...request, generation: "wrong-generation" }, { ...request, phase: "restore" },
  ];
  const { _id, _creationTime, ...otherHeader } = await f.header();
  const otherId = await f.t.run(ctx => ctx.db.insert("savedFolderManifests", otherHeader));
  changed.push({ ...request, manifestId: otherId });
  for (const bad of changed) expect(await outcomePage(f, bad)).toEqual({ kind: "unavailable", ownerKey: f.userId, request: bad, reason: "proof_unavailable" });
});

test.each([-1, 0.5, Number.MAX_SAFE_INTEGER, NaN, Infinity])("outcome continuation rejects invalid ordinal %s", async start => {
  const f = await fixture(1); await f.commit();
  await expect(outcomePage(f, { ...await outcomeRequest(f), start })).rejects.toThrow("SYNC_INVALID_OUTCOME_PAGE");
});

test("pending work and acknowledged proof cannot expose manifest details", async () => {
  const f = await fixture(1);
  const pending = f.work.pending;
  const request: SyncOutcomePageRequest = { proof: { clientKey: pending.clientKey, sequence: pending.sequence, batchId: pending.batchId, digest: pending.digest },
    receiptId: "logical-delete", manifestId: pending.manifestId, generation: pending.generation, phase: "delete", start: 0 };
  expect(await outcomePage(f, request)).toMatchObject({ kind: "unavailable", reason: "proof_unavailable" });
  await f.commit(); expect(await outcomePage(f, request)).toMatchObject({ kind: "page" });
  const capability = (await f.a.mutation(api.librarySync.openManifestBinding, {})).capability;
  await f.a.mutation(api.librarySync.acknowledge, { capability, acknowledgement: request.proof });
  expect(await outcomePage(f, request)).toMatchObject({ kind: "unavailable", reason: "proof_unavailable" });
});

test("expired or purging detail is explicitly unavailable without claiming a complete empty result", async () => {
  const f = await fixture(1); await f.commit(); const request = await outcomeRequest(f);
  vi.setSystemTime((await f.header()).expiresAt);
  expect(await outcomePage(f, request)).toMatchObject({ kind: "unavailable", reason: "detail_unavailable" });
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {});
  expect(await outcomePage(f, request)).toMatchObject({ kind: "unavailable", reason: "detail_unavailable" });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await outcomePage(f, request)).toMatchObject({ kind: "unavailable", reason: "detail_unavailable" });
});

test("missing ordinal cannot be reported as a short complete page", async () => {
  const f = await fixture(3); await f.commit(); const request = await outcomeRequest(f);
  await f.t.run(async ctx => {
    const member = await ctx.db.query("savedFolderManifestMembers").withIndex("by_user_manifest_ordinal", q => q.eq("userId", f.userId).eq("manifestId", f.work.id).eq("ordinal", 1)).unique();
    if (!member) throw new Error("Missing fixture fact"); await ctx.db.delete(member._id);
  });
  await expect(outcomePage(f, request)).rejects.toThrow("SYNC_OUTCOME_MANIFEST_INVARIANT");
});

test("corrupt negative restore counters cannot cancel into an apparently valid page count", async () => {
  const f = await fixture(1); await f.commit(); const restore = await f.begin(); await f.finishRestoration();
  const request = await outcomeRequest(f, restore.pending);
  await f.t.run(async ctx => {
    const header = await ctx.db.get(f.work.id);
    if (header?.state.kind !== "restored") throw new Error("Missing restored fixture");
    await ctx.db.patch(header._id, { state: { ...header.state, restored: 2, missing: -1 } });
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", f.userId).eq("clientKey", request.proof.clientKey)).unique();
    if (stream?.slot?.kind !== "committed") throw new Error("Missing committed fixture");
    const committed = stream.slot.committed;
    await ctx.db.patch(stream._id, { slot: { kind: "committed", committed: { ...committed, reply: { ...committed.reply,
      receipts: committed.reply.receipts.map(receipt => receipt.outcome.kind === "folder_restored_manifest" ? { ...receipt, outcome: { ...receipt.outcome, restored: 2, missing: -1 } } : receipt) } } } });
  });
  await expect(outcomePage(f, request)).rejects.toThrow("SYNC_OUTCOME_MANIFEST_INVARIANT");
});

test("zero-member outcomes require and return explicit terminal proof for both phases", async () => {
  const f = await fixture(0); await f.commit();
  expect(await outcomePage(f, await outcomeRequest(f))).toMatchObject({ kind: "page", rows: [], next: 0, done: true });
  const restore = await f.begin(); await f.finishRestoration();
  expect(await outcomePage(f, await outcomeRequest(f, restore.pending))).toMatchObject({ kind: "page", rows: [], next: 0, done: true });
});
