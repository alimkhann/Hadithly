/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import type { Id } from "./_generated/dataModel";
import type { SyncCommand, SyncCommitted, SyncExchange, SyncFrame, SyncPending, SyncOutcomePageRequest } from "./lib/librarySyncPolicy";
import { FOLDER_MANIFEST_LEASE_MS, advanceFolderManifest } from "./lib/savedFolderManifests";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());

function committed(exchange: SyncExchange): SyncCommitted {
  if (exchange.kind !== "accepted") throw new Error("Missing terminal receipt");
  return exchange.committed;
}
function held(exchange: SyncExchange): SyncPending {
  if (exchange.kind !== "pending") throw new Error("Missing exact pending proof");
  return exchange.pending;
}
function ack(value: SyncCommitted) { return { clientKey: value.clientKey, sequence: value.sequence, batchId: value.reply.batchId, digest: value.digest }; }
async function fixture(count = 3) {
  vi.useFakeTimers(); vi.setSystemTime(1_000_000);
  const t = convexTest(schema, modules), a = t.withIdentity({ subject: "public-owner", tokenIdentifier: "fixture:public-owner" }), b = t.withIdentity({ subject: "public-other", tokenIdentifier: "fixture:public-other" });
  const userId = await a.mutation(api.users.ensureCurrentUser, {}), otherId = await b.mutation(api.users.ensureCurrentUser, {});
  const folderId = await t.run(ctx => ctx.db.insert("savedFolders", { userId, name: "Original folder", normalizedName: "original folder", createdAt: 1_000, updatedAt: 1_000 }));
  const otherFolder = await b.mutation(api.library.createSavedFolder, { name: "Other folder" });
  const ids: Id<"hadiths">[] = [];
  for (let start = 0; start < count; start += 100) await t.run(async ctx => {
    for (let index = start; index < Math.min(start + 100, count); index++) {
      const id = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: String(index + 1), volumeId: "1", collectionName: "Bukhari", referenceDisplay: `Bukhari ${index + 1}`, arabicText: "نص", createdAt: 1 });
      ids.push(id);
      await ctx.db.insert("savedItems", { userId, hadithId: id, folderId, folderUpdatedAt: 1_000, bookmarkCreatedAt: 1_000, createdAt: 1_000, updatedAt: 1_000,
        ...(index === 0 ? { noteContent: "Private original", noteCreatedAt: 1_000, noteUpdatedAt: 1_000 } : {}) });
      if (index === 0) await ctx.db.insert("savedItems", { userId: otherId, hadithId: id, folderId: otherFolder, noteContent: "Other private original", createdAt: 1_000, updatedAt: 1_000 });
    }
  });
  const v1 = (await a.mutation(api.librarySync.openBinding, {})).capability, v2 = (await a.mutation(api.librarySync.openManifestBinding, {})).capability;
  const frame: SyncFrame = { clientKey: "public-device", sequence: 1, batch: { id: "public-delete", operations: [{ id: "public-delete-op", revision: "r1", at: 1_000_100, command: { kind: "folder_delete", folder: { kind: "server", id: folderId } } }] } };
  async function drain(id: Id<"savedFolderManifests">, restore = false) {
    for (let step = 0; step < Math.ceil(count / 4) * 2 + Math.ceil(count / 50) + 30; step++) {
      vi.runOnlyPendingTimers(); await t.finishInProgressScheduledFunctions();
      const header = await t.run(ctx => ctx.db.get(id));
      if (!header) throw new Error("Work vanished before expected success");
      if (!restore && header.state.kind === "deleted" || restore && header.state.kind === "restored" && header.state.normalization.kind === "done") return;
    }
    throw new Error("Public work did not converge within bounded fixture steps");
  }
  async function deleted() {
    const pending = held(await a.mutation(api.librarySync.applyBatch, { capability: v2, frame }));
    await drain(pending.manifestId);
    return { pending, result: committed(await a.query(api.librarySync.pollPending, { capability: v2, pending })) };
  }
  function restoreFrame(sequence = 2, hadithIds: string[] = []): SyncFrame {
    return { clientKey: frame.clientKey, sequence, batch: { id: "public-undo", operations: [{ id: "public-undo-op", revision: "r1", at: 1_000_200, command: { kind: "folder_restore", deletionId: "public-delete-op", name: "Client cannot rename canonical folder", hadithIds } }] } };
  }
  return { t, a, b, userId, otherId, folderId, ids, frame, v1, v2, drain, deleted, restoreFrame };
}

test("public manifest delete and compact Undo cover 501 members, page exact facts and publish the real alias", async () => {
  const f = await fixture(501);
  const legacy = committed(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v1, frame: { ...f.frame, clientKey: "old-device" } }));
  expect(legacy.reply.receipts[0].outcome).toEqual({ kind: "unresolved", reason: "folder_too_large" });
  const { pending, result } = await f.deleted();
  expect(new TextEncoder().encode(JSON.stringify(pending)).byteLength).toBeLessThan(2_048);
  expect(result.reply.receipts[0].outcome).toMatchObject({ kind: "folder_deleted_manifest", count: 501 });
  expect(new TextEncoder().encode(JSON.stringify(result)).byteLength).toBeLessThan(2_048);
  const receipt = result.reply.receipts[0];
  const request: SyncOutcomePageRequest = { proof: ack(result), receiptId: receipt.id, manifestId: pending.manifestId, generation: pending.generation, phase: "delete", start: 0 };
  const seen = new Set<string>();
  for (let start = 0; start < 501; start += 50) {
    const page = await f.a.query(api.librarySync.outcomePage, { capability: f.v2, request: { ...request, start } });
    if (page.kind !== "page") throw new Error("Missing public outcome detail");
    expect(page.rows.length).toBeLessThanOrEqual(50); expect(new TextEncoder().encode(JSON.stringify(page)).byteLength).toBeLessThanOrEqual(64 * 1024); page.rows.forEach(row => seen.add(row.hadithId));
  }
  expect(seen).toEqual(new Set(f.ids));
  const removed = await f.a.query(api.librarySync.savedSnapshot, {});
  expect(removed.folders).toEqual([]); expect(removed.items.every(item => item.folderId === undefined)).toBe(true);
  expect(removed.items[0].noteContent).toBe("Private original");
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(result) });
  const restore = f.restoreFrame(), restoring = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: restore }));
  expect(await f.t.run(ctx => ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", f.userId).eq("key", "restore:public-delete-op")).unique())).toBeNull();
  await f.drain(restoring.manifestId, true);
  const restored = committed(await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending: restoring })), outcome = restored.reply.receipts[0].outcome;
  if (outcome.kind !== "folder_restored_manifest") throw new Error("Missing bounded restore receipt");
  expect(outcome).toMatchObject({ restored: 501, superseded: 0, missing: 0 });
  expect(new TextEncoder().encode(JSON.stringify(restored)).byteLength).toBeLessThan(2_048);
  const saved = await f.a.query(api.librarySync.savedSnapshot, {});
  expect(saved.folders).toMatchObject([{ _id: outcome.folderId, name: "Original folder" }]);
  expect(saved.items.filter(item => item.folderId === outcome.folderId)).toHaveLength(501);
  expect((await f.b.query(api.library.listSavedSnapshot, {})).items[0]).toMatchObject({ noteContent: "Other private original" });
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(restored) });
  const assigned = committed(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: { clientKey: restore.clientKey, sequence: 3, batch: { id: "after-undo", operations: [{ id: "after-undo", revision: "r1", at: 1_000_300, command: { kind: "membership_put", hadithId: f.ids[0], folder: { kind: "local", key: "restore:public-delete-op" } } }] } } }));
  expect(assigned.reply.receipts[0].outcome).toEqual({ kind: "preserved" });
}, 30_000);

test("manifest Undo ignores injected member claims and preserves unrelated membership", async () => {
  const f = await fixture(1), { result } = await f.deleted();
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(result) });
  const other = await f.a.mutation(api.library.createSavedFolder, { name: "Unrelated destination" });
  const injected = await f.t.run(async ctx => {
    const id = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "999", collectionName: "Bukhari", referenceDisplay: "Bukhari 999", arabicText: "نص", createdAt: 1 });
    await ctx.db.insert("savedItems", { userId: f.userId, hadithId: id, folderId: other, folderUpdatedAt: 1_000_150, bookmarkCreatedAt: 1_000, createdAt: 1_000, updatedAt: 1_000_150 });
    return id;
  });
  const restore = f.restoreFrame(2, [injected]), pending = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: restore }));
  await f.drain(pending.manifestId, true);
  const terminal = committed(await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending }));
  expect(terminal.reply.receipts[0].outcome).toMatchObject({ kind: "folder_restored_manifest", restored: 1, missing: 0, superseded: 0 });
  expect((await f.a.query(api.librarySync.savedSnapshot, {})).items.find(item => item.hadithId === injected)?.folderId).toBe(other);
});

test("v2 replays old inline mixed history exactly and compact Undo uses only the owned legacy deletion set", async () => {
  const f = await fixture(2);
  const frame: SyncFrame = { ...f.frame, batch: { id: "old-mixed", operations: [f.frame.batch.operations[0], { id: "old-note", revision: "r1", at: 1_000_100, command: { kind: "note_put", hadithId: f.ids[0], content: "Old accepted original", createdAt: 1_000, updatedAt: 1_000_100 } }] } };
  const old = await f.a.mutation(api.librarySync.applyBatch, { capability: f.v1, frame });
  expect(committed(old).reply.receipts[0].outcome.kind).toBe("folder_deleted");
  expect(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame })).toEqual(old);
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(committed(old)) });
  const restored = committed(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: f.restoreFrame() }));
  expect(restored.reply.receipts[0].outcome).toMatchObject({ kind: "folder_restored", restored: f.ids });
  expect((await f.a.query(api.librarySync.savedSnapshot, {})).items[0].noteContent).toBe("Old accepted original");
});

test("fresh v2 mixed frames receive exact stable no-effect split proof without a Saved revision change", async () => {
  const f = await fixture(1), before = await f.a.query(api.librarySync.savedSnapshot, {});
  const frame: SyncFrame = { ...f.frame, batch: { id: "split-mixed", operations: [{ id: "unsent-note", revision: "r1", at: 1_000_100, command: { kind: "note_put", hadithId: f.ids[0], content: "Must remain unsent", createdAt: 1_000, updatedAt: 1_000_100 } }, f.frame.batch.operations[0]] } };
  const reply = await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame });
  expect(committed(reply).reply.receipts).toEqual(frame.batch.operations.map(op => ({ id: op.id, revision: op.revision, outcome: { kind: "batch_requires_split" } })));
  expect(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame })).toEqual(reply);
  expect(await f.a.query(api.librarySync.savedSnapshot, {})).toEqual(before);
  expect(await f.t.run(ctx => ctx.db.query("savedFolderManifests").collect())).toEqual([]);
});

test("maximum-operation split proof is bounded and stores no original business payload", async () => {
  const f = await fixture(1);
  const frame: SyncFrame = { clientKey: "c".repeat(128), sequence: 1, batch: { id: "b".repeat(128), operations: [f.frame.batch.operations[0], ...Array.from({ length: 49 }, (_, index) => ({ id: `operation-${index}`.padEnd(128, "x"), revision: "r".repeat(128), at: 1_000_100, command: { kind: "bookmark_remove", hadithId: "h".repeat(128) } satisfies SyncCommand }))] } };
  const reply = committed(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame }));
  expect(reply.reply.receipts).toHaveLength(50);
  expect(reply.reply.receipts.every(receipt => receipt.outcome.kind === "batch_requires_split")).toBe(true);
  expect(new TextEncoder().encode(JSON.stringify(reply)).byteLength).toBeLessThan(64 * 1024);
  const stream = await f.t.run(ctx => ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", f.userId).eq("clientKey", frame.clientKey)).unique());
  expect(stream?.slot?.kind).toBe("committed");
  expect(stream?.slot && "batch" in stream.slot).toBe(false);
});

test("large valid legacy-shaped manifest request stays bounded without granting claimed membership", async () => {
  const f = await fixture(1), { result } = await f.deleted();
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(result) });
  const claims = Array.from({ length: 500 }, (_, index) => "α".repeat(120) + index);
  const frame = f.restoreFrame(2, claims);
  expect(new TextEncoder().encode(JSON.stringify(frame.batch)).byteLength).toBeLessThan(128 * 1024);
  const pending = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame }));
  expect(new TextEncoder().encode(JSON.stringify(pending)).byteLength).toBeLessThan(2_048);
  const stream = await f.t.run(ctx => ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", f.userId).eq("clientKey", frame.clientKey)).unique());
  if (stream?.slot?.kind !== "pending") throw new Error("Missing bounded held request");
  expect(stream.slot.batch).toEqual(frame.batch);
  expect(new TextEncoder().encode(JSON.stringify(stream)).byteLength).toBeLessThan(128 * 1024 + 4_096);
  await f.drain(pending.manifestId, true);
  const restored = committed(await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending }));
  expect(restored.reply.receipts[0].outcome).toMatchObject({ kind: "folder_restored_manifest", restored: 1, missing: 0, superseded: 0 });
  expect(new TextEncoder().encode(JSON.stringify(restored)).byteLength).toBeLessThan(2_048);
});

test.each(["pending", "deleted", "restored", "split"])("legacy capabilities cannot expose or consume %s v2 stream proof", async mode => {
  const f = await fixture(1);
  const fallback = await f.t.run(ctx => ctx.db.insert("savedFolderManifests", { userId: f.userId, folderId: f.folderId, operationId: "dummy", requestedAt: 1, generation: "dummy", createdAt: 1, updatedAt: 1, expiresAt: 1, captured: { epoch: 0, updatedAt: 1, name: "Dummy", createdAt: 1 }, state: { kind: "abandoned", count: 0, reason: "expired" } }));
  let frame = f.frame, exchange: SyncExchange;
  if (mode === "split") {
    frame = { ...frame, batch: { ...frame.batch, operations: [...frame.batch.operations, { id: "split-note", revision: "r1", at: 1_000_100, command: { kind: "note_remove", hadithId: f.ids[0] } }] } };
    exchange = await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame });
  } else {
    exchange = await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame });
    if (mode !== "pending") {
      const pending = held(exchange); await f.drain(pending.manifestId);
      exchange = await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending });
      if (mode === "restored") {
        await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(committed(exchange)) });
        frame = f.restoreFrame(); const restoring = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame }));
        await f.drain(restoring.manifestId, true); exchange = await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending: restoring });
      }
    }
  }
  const proof = exchange.kind === "pending" ? { clientKey: exchange.pending.clientKey, sequence: exchange.pending.sequence, batchId: exchange.pending.batchId, digest: exchange.pending.digest } : ack(committed(exchange));
  const pending: SyncPending = exchange.kind === "pending" ? exchange.pending : { ...proof, intentDigest: "a".repeat(64), manifestId: fallback, generation: "dummy", retryAfterMs: 1_000 };
  const stream = () => f.t.run(ctx => ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", f.userId).eq("clientKey", frame.clientKey)).unique());
  const before = await stream();
  await expect(f.a.mutation(api.librarySync.applyBatch, { capability: f.v1, frame })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  await expect(f.a.mutation(api.librarySync.applyBatch, { capability: f.v1, frame: { ...frame, batch: { ...frame.batch, id: "other-restored-copy" } } })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  await expect(f.a.query(api.librarySync.pollPending, { capability: f.v1, pending })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  for (const digest of [proof.digest, "wrong-proof"]) await expect(f.a.mutation(api.librarySync.acknowledge, { capability: f.v1, acknowledgement: { ...proof, digest } })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  for (const sequence of [proof.sequence, proof.sequence + 2]) await expect(f.a.mutation(api.librarySync.retireInvalidFrame, { capability: f.v1, clientKey: proof.clientKey, sequence })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  expect(await stream()).toEqual(before);
  expect(await f.t.run(ctx => ctx.db.query("librarySyncRetirements").collect())).toEqual([]);
  if (exchange.kind === "accepted") {
    const value = exchange.committed.reply.receipts[0].outcome;
    if (value.kind === "folder_deleted_manifest" || value.kind === "folder_restored_manifest") {
      const request: SyncOutcomePageRequest = { proof, receiptId: exchange.committed.reply.receipts[0].id, manifestId: value.manifestId, generation: value.generation, phase: value.kind === "folder_deleted_manifest" ? "delete" : "restore", start: 0 };
      await expect(f.a.query(api.librarySync.outcomePage, { capability: f.v1, request })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
      expect((await f.a.query(api.librarySync.outcomePage, { capability: f.v2, request })).kind).toBe("page");
    }
  }
});

test("prepared held delivery is recovered and duplicate commit does not advance Saved twice", async () => {
  const f = await fixture(1), pending = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: f.frame }));
  const work = { id: pending.manifestId, generation: pending.generation };
  await f.t.run(ctx => advanceFolderManifest(ctx, { ...work, step: 0 }));
  await f.t.run(ctx => ctx.db.patch(work.id, { updatedAt: Date.now() - 5 * 60_000 }));
  expect((await f.t.mutation(internal.librarySync.recoverFolderManifests, {})).scheduled).toBe(1);
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  const before = await f.a.query(api.librarySync.savedSnapshot, {});
  await f.t.mutation(internal.librarySync.commitFolderDeletion, work);
  expect(await f.a.query(api.librarySync.savedSnapshot, {})).toEqual(before);
  expect(committed(await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending })).reply.receipts[0].outcome.kind).toBe("folder_deleted_manifest");
});

test.each([false, true])("late alias conflict produces a terminal receipt and unwinds staged state, existing destination=%s", async existing => {
  const f = await fixture(3), { result } = await f.deleted();
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(result) });
  const original = existing ? await f.a.mutation(api.library.createSavedFolder, { name: "Original folder" }) : null;
  const restore = f.restoreFrame(), pending = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: restore }));
  await expect(f.a.mutation(api.librarySync.applyBatch, { capability: f.v1, frame: { ...restore, clientKey: "legacy-undo", sequence: 1 } })).rejects.toThrow("SYNC_CLIENT_UPGRADE_REQUIRED");
  const winner = await f.a.mutation(api.library.createSavedFolder, { name: "Other winning folder" });
  // Model an older in-flight writer or repaired legacy alias without weakening current admission.
  await f.t.run(ctx => ctx.db.insert("librarySyncFolderKeys", { userId: f.userId, key: "restore:public-delete-op", folderId: winner }));
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  const terminal = await f.a.query(api.librarySync.pollPending, { capability: f.v2, pending });
  expect(committed(terminal).reply.receipts[0].outcome).toEqual({ kind: "superseded", reason: "changed_since_delete" });
  expect(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: restore })).toEqual(terminal);
  const saved = await f.a.query(api.librarySync.savedSnapshot, {});
  expect(saved.items.every(item => item.folderId === undefined)).toBe(true);
  expect(saved.folders.map(row => row._id).sort()).toEqual((original ? [original, winner] : [winner]).sort());
  expect(await f.t.run(ctx => ctx.db.query("savedItems").withIndex("by_user", q => q.eq("userId", f.userId)).collect())).not.toContainEqual(expect.objectContaining({ folderStage: expect.anything() }));
  if (original) expect((await f.t.run(ctx => ctx.db.get(original)))?.transition).toBeUndefined();
});

test("reserved aliases cannot be created by ordinary clients and preexisting conflicts fail before restore reservation", async () => {
  const f = await fixture(1), { result } = await f.deleted();
  await f.a.mutation(api.librarySync.acknowledge, { capability: f.v2, acknowledgement: ack(result) });
  for (const [index, capability] of [f.v1, f.v2].entries()) await expect(f.a.mutation(api.librarySync.applyBatch, { capability, frame: { clientKey: `reserved-${index}`, sequence: 1, batch: { id: "reserved", operations: [{ id: "reserved", revision: "r1", at: 1_000_200, command: { kind: "folder_create", key: "restore:public-delete-op", name: "Must not appear", purpose: "create" } }] } } })).rejects.toThrow("SYNC_RESERVED_FOLDER_KEY");
  const destination = await f.a.mutation(api.library.createSavedFolder, { name: "Conflicting alias target" });
  await f.t.run(ctx => ctx.db.insert("librarySyncFolderKeys", { userId: f.userId, key: "restore:public-delete-op", folderId: destination }));
  expect(committed(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: f.restoreFrame() })).reply.receipts[0].outcome).toEqual({ kind: "superseded", reason: "changed_since_delete" });
  expect((await f.a.query(api.librarySync.savedSnapshot, {})).folders).toMatchObject([{ _id: destination }]);
});

test("busy preparation is retryable without a stream effect; expired public work retains exact failure and no deletion", async () => {
  const f = await fixture(1), pending = held(await f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: f.frame }));
  const competing: SyncFrame = { ...f.frame, clientKey: "busy-other", batch: { ...f.frame.batch, id: "busy-other", operations: [{ ...f.frame.batch.operations[0], id: "busy-other" }] } };
  await expect(f.a.mutation(api.librarySync.applyBatch, { capability: f.v2, frame: competing })).rejects.toThrow("SYNC_FOLDER_BUSY");
  expect(await f.t.run(ctx => ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", f.userId).eq("clientKey", competing.clientKey)).unique())).toBeNull();
  vi.setSystemTime(Date.now() + FOLDER_MANIFEST_LEASE_MS);
  await f.t.mutation(internal.librarySync.pruneFolderManifests, {}); await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  const capability = (await f.a.mutation(api.librarySync.openManifestBinding, {})).capability;
  expect(committed(await f.a.query(api.librarySync.pollPending, { capability, pending })).reply.receipts[0].outcome).toEqual({ kind: "unresolved", reason: "preparation_expired" });
  expect((await f.a.query(api.librarySync.savedSnapshot, {})).folders).toMatchObject([{ _id: f.folderId }]);
});
