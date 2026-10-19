/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import { holdFolderFrame, failHeldFolderFrame } from "./lib/librarySyncFrames";
import { prepareFolderManifest, FOLDER_MANIFEST_LEASE_MS } from "./lib/savedFolderManifests";
import { validateSyncBatch, validateSyncStream, type SyncFrame } from "./lib/librarySyncPolicy";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

async function fixture() {
  vi.useFakeTimers(); vi.setSystemTime(1_000_000);
  const t = convexTest(schema, modules);
  const a = t.withIdentity({ subject: "held-owner", tokenIdentifier: "fixture:held-owner" });
  const b = t.withIdentity({ subject: "held-other", tokenIdentifier: "fixture:held-other" });
  const userId = await a.mutation(api.users.ensureCurrentUser, {}), otherId = await b.mutation(api.users.ensureCurrentUser, {});
  const folderId = await a.mutation(api.library.createSavedFolder, { name: "Held folder" });
  const hadithId = await t.run(async ctx => {
    const id = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "1", volumeId: "1", collectionName: "Bukhari", referenceDisplay: "Bukhari 1", arabicText: "نص", createdAt: 1 });
    await ctx.db.insert("savedItems", { userId, hadithId: id, folderId, folderUpdatedAt: 1_000_000, noteContent: "Original stays in Saved", noteCreatedAt: 1_000_000, noteUpdatedAt: 1_000_000, createdAt: 1_000_000, updatedAt: 1_000_000 });
    return id;
  });
  const frame: SyncFrame = { clientKey: "held-device", sequence: 1, batch: { id: "held-batch", operations: [{ id: "held-delete", revision: "r1", at: 1_000_100, command: { kind: "folder_delete", folder: { kind: "server", id: folderId } } }] } };
  const work = await t.run(async ctx => {
    validateSyncStream(frame.clientKey, frame.sequence); validateSyncBatch(frame.batch, Date.now());
    const value = await prepareFolderManifest(ctx, userId, { id: "held-delete", at: 1_000_100, folderId });
    if (value.kind !== "manifest") throw new Error("Fixture preparation refused");
    return { id: value.id, generation: value.generation };
  });
  const held = await t.run(ctx => holdFolderFrame(ctx, userId, frame, work));
  if (held.kind !== "pending") throw new Error("Missing held proof");
  const capability = (await a.mutation(api.librarySync.openBinding, {})).capability;
  return { t, a, b, userId, otherId, folderId, hadithId, frame, work, held, capability };
}

test("a held frame cannot be applied, ACKed or retired as terminal while its work is pending", async () => {
  const f = await fixture(), { pending } = f.held;
  expect(await f.a.mutation(api.librarySync.applyBatch, { capability: f.capability, frame: f.frame })).toEqual(f.held);
  expect(await f.t.run(ctx => holdFolderFrame(ctx, f.userId, f.frame, f.work))).toEqual(f.held);
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect((await f.t.run(ctx => ctx.db.get(f.work.id)))?.state).toEqual({ kind: "prepared", count: 1 });
  expect(await f.a.query(api.librarySync.pollPending, { capability: f.capability, pending })).toEqual(f.held);
  const acknowledgement = { clientKey: pending.clientKey, sequence: pending.sequence, batchId: pending.batchId, digest: pending.digest };
  const expected = { ownerKey: f.userId, clientKey: pending.clientKey, cursor: { closedThrough: 0, outstanding: { kind: "pending", pending } } };
  expect(await f.a.mutation(api.librarySync.acknowledge, { capability: f.capability, acknowledgement })).toEqual(expected);
  expect(await f.a.mutation(api.librarySync.retireInvalidFrame, { capability: f.capability, clientKey: pending.clientKey, sequence: 1 })).toEqual(expected);
  const exported = await f.a.query(api.users.exportCurrentUserData, {});
  if (!exported.sync) throw new Error("Missing owner export");
  expect(exported.sync.streams[0]).toMatchObject({ slot: { kind: "pending", batch: f.frame.batch } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0]).toMatchObject({ folderId: f.folderId, noteContent: "Original stays in Saved" });
});

test("expiry retains an exact failure after work cleanup; only its exact ACK crosses a future retirement fence", async () => {
  const f = await fixture(), { pending } = f.held;
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  await f.a.mutation(api.librarySync.retireInvalidFrame, { capability: f.capability, clientKey: pending.clientKey, sequence: 2 });
  vi.setSystemTime(Date.now() + FOLDER_MANIFEST_LEASE_MS);
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {});
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.get(f.work.id))).toBeNull();
  const capability = (await f.a.mutation(api.librarySync.openBinding, {})).capability;
  const terminal = await f.a.query(api.librarySync.pollPending, { capability, pending });
  if (terminal.kind !== "accepted") throw new Error("Missing terminal failure proof");
  expect(terminal.committed.reply.receipts).toEqual([{ id: "held-delete", revision: "r1", outcome: { kind: "unresolved", reason: "preparation_expired" } }]);
  expect(await f.a.mutation(api.librarySync.applyBatch, { capability, frame: f.frame })).toEqual(terminal);
  const proof = { clientKey: pending.clientKey, sequence: 1, batchId: pending.batchId, digest: pending.digest };
  expect((await f.a.mutation(api.librarySync.acknowledge, { capability, acknowledgement: { ...proof, digest: "wrong" } })).cursor.outstanding?.kind).toBe("committed");
  expect((await f.a.mutation(api.librarySync.acknowledge, { capability, acknowledgement: proof })).cursor).toEqual({ closedThrough: 2 });
  expect((await f.a.mutation(api.librarySync.applyBatch, { capability, frame: f.frame })).kind).toBe("reconcile");
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].folderId).toBe(f.folderId);
});

test("a changed scan commits its no-effect conflict before purging temporary facts", async () => {
  const f = await fixture();
  vi.setSystemTime(Date.now() + 1_000);
  await f.a.mutation(api.library.assignSavedFolder, { hadithId: f.hadithId });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  const terminal = await f.a.query(api.librarySync.pollPending, { capability: f.capability, pending: f.held.pending });
  expect(terminal).toMatchObject({ kind: "accepted", committed: { reply: { receipts: [{ outcome: { kind: "superseded", reason: "changed_since_delete" } }] } } });
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifestMembers").collect())).toEqual([]);
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("Original stays in Saved");
});

test("foreign owners, another stream and changed payloads cannot steal held authority", async () => {
  const f = await fixture();
  await expect(f.b.query(api.librarySync.pollPending, { capability: f.capability, pending: f.held.pending })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  const otherCapability = (await f.b.mutation(api.librarySync.openBinding, {})).capability;
  expect(await f.b.query(api.librarySync.pollPending, { capability: otherCapability, pending: f.held.pending })).toMatchObject({ kind: "reconcile", ownerKey: f.otherId, cursor: { closedThrough: 0 } });
  await expect(f.t.run(ctx => holdFolderFrame(ctx, f.otherId, f.frame, f.work))).rejects.toThrow("SYNC_WORK_MISMATCH");
  await expect(f.t.run(ctx => holdFolderFrame(ctx, f.userId, { ...f.frame, clientKey: "another-device" }, f.work))).rejects.toThrow("SYNC_WORK_ALREADY_BOUND");
  const changed: SyncFrame = { ...f.frame, batch: { ...f.frame.batch, operations: [{ ...f.frame.batch.operations[0], revision: "changed-revision" }] } };
  expect(await f.a.mutation(api.librarySync.applyBatch, { capability: f.capability, frame: changed })).toMatchObject({ kind: "reconcile", cursor: { outstanding: { kind: "pending" } } });
  const header = await f.t.run(ctx => ctx.db.get(f.work.id));
  if (!header) throw new Error("Missing held fixture header");
  await f.t.run(ctx => failHeldFolderFrame(ctx, { ...header, generation: "stale-generation" }, "changed"));
  expect(await f.a.query(api.librarySync.pollPending, { capability: f.capability, pending: f.held.pending })).toEqual(f.held);
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
});

test("account erasure removes the held stream and late callbacks cannot recreate it", async () => {
  const f = await fixture();
  await f.a.mutation(api.users.deleteCurrentUser, { authorization: (await f.a.mutation(api.users.prepareAccountDeletion, {})).authorization });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("librarySyncStreams").collect())).toEqual([]);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifests").collect())).toEqual([]);
  await expect(f.a.query(api.librarySync.pollPending, { capability: f.capability, pending: f.held.pending })).rejects.toThrow("SYNC_ACCOUNT_MISSING");
});
