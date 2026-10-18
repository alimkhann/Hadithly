/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { expect, test, vi, afterEach } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import type { SyncBatch, SyncBinding, SyncReply, SyncExchange, SyncFrame, SyncAckReply, SyncAcknowledgement } from "./lib/librarySyncPolicy";
const modules = import.meta.glob("./**/*.ts");
const open = makeFunctionReference<"mutation", Record<string, never>, SyncBinding>("librarySync:openBinding");
const apply = makeFunctionReference<"mutation", { capability: string; frame: SyncFrame }, SyncExchange>("librarySync:applyBatch");
const ack = makeFunctionReference<"mutation", { capability: string; acknowledgement: SyncAcknowledgement }, SyncAckReply>("librarySync:acknowledge");
afterEach(() => vi.useRealTimers());
async function fixture() {
  const t = convexTest(schema, modules);
  const a = t.withIdentity({ subject: "sync_fixture_a", tokenIdentifier: "https://clerk.example|sync_fixture_a" });
  const b = t.withIdentity({ subject: "sync_fixture_b", tokenIdentifier: "https://clerk.example|sync_fixture_b" });
  await a.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  await b.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
  const hadithId = await t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", canonicalId: "sunnah_now:bukhari:1", collectionSlug: "bukhari", providerHadithId: "1", arabicText: "نص", collectionName: "Bukhari", referenceDisplay: "Bukhari 1", volumeId: "1", createdAt: 1 }));
  let sequence = 1;
  async function send(capability: string, batch: SyncBatch): Promise<SyncReply> {
    const exchange = await a.mutation(apply, { capability, frame: { clientKey: "fixture-device", sequence, batch } });
    if (exchange.kind !== "accepted") throw new Error("Unexpected fixture cursor");
    const committed = exchange.committed;
    await a.mutation(ack, { capability, acknowledgement: { clientKey: committed.clientKey, sequence: committed.sequence, batchId: committed.reply.batchId, digest: committed.digest } });
    sequence++;
    return committed.reply;
  }
  return { t, a, b, hadithId, send };
}

test("a binding is server-owned and a queued frame under another JWT writes nothing", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const batch: SyncBatch = { id: "owner-batch", operations: [{ id: "owner-add", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } }] };
  const frame = { clientKey: "device-a", sequence: 1, batch };
  await expect(f.b.mutation(apply, { capability: binding.capability, frame })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items).toEqual([]);
  expect((await f.b.query(api.library.listSavedSnapshot, {})).items).toEqual([]);
  expect(await f.a.mutation(apply, { capability: binding.capability, frame })).toMatchObject({ kind: "accepted", committed: { reply: { receipts: [{ outcome: { kind: "preserved" } }] } } });
});

test("lost-response retry stays exact before ack and cannot replay after compaction and a later remove", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const batch: SyncBatch = { id: "add-batch", operations: [{ id: "add-once", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } }] };
  const frame = { clientKey: "device-a", sequence: 1, batch };
  const first = await f.a.mutation(apply, { capability: binding.capability, frame });
  expect(await f.a.mutation(apply, { capability: binding.capability, frame })).toEqual(first);
  if (first.kind !== "accepted") throw new Error("Missing committed fixture");
  const acknowledgement = { clientKey: "device-a", sequence: 1, batchId: batch.id, digest: first.committed.digest };
  const closed = await f.a.mutation(ack, { capability: binding.capability, acknowledgement });
  expect(await f.a.mutation(ack, { capability: binding.capability, acknowledgement })).toEqual(closed);
  await f.send(binding.capability, { id: "remove-batch", operations: [{ id: "remove-after", revision: "r2", at: 2_000, command: { kind: "bookmark_remove", hadithId: f.hadithId } }] });
  expect(await f.a.mutation(apply, { capability: binding.capability, frame })).toMatchObject({ kind: "reconcile", cursor: { closedThrough: 1 } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items).toEqual([]);
});

test("a mixed batch acknowledges a bookmark independently of a losing note and a missing target", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.a.mutation(api.library.upsertSavedNote, { hadithId: f.hadithId, content: "Newer cloud fixture" });
  const reply = await f.send(binding.capability, { id: "batch-mixed", operations: [
    { id: "bookmark", revision: "revision-1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "note", revision: "revision-2", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Older local fixture", createdAt: 1_000, updatedAt: 1_000 } },
    { id: "missing", revision: "revision-3", at: 1_000, command: { kind: "favorite_add", hadithId: "missing-target", createdAt: 1_000 } },
  ] } );
  expect(reply.receipts).toEqual([
    { id: "bookmark", revision: "revision-1", outcome: { kind: "preserved" } },
    { id: "note", revision: "revision-2", outcome: { kind: "superseded", reason: "newer_cloud" } },
    { id: "missing", revision: "revision-3", outcome: { kind: "unresolved", reason: "missing_target" } },
  ]);
  const snapshot = await f.a.query(api.library.listSavedSnapshot, {});
  expect(snapshot.items).toHaveLength(1);
  expect(snapshot.items[0]).toMatchObject({ noteContent: "Newer cloud fixture", bookmarkCreatedAt: 1_000 });
});

test("expiry and account erasure revoke batch admission without recreating private data", async () => {
  vi.useFakeTimers();
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const batch: SyncBatch = { id: "batch-erasure", operations: [{ id: "note-erasure", revision: "revision-1", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Private fixture", createdAt: 1_000, updatedAt: 1_000 } }] };
  vi.setSystemTime(binding.validUntil + 1);
  await expect(f.send(binding.capability, batch)).rejects.toThrow("SYNC_BINDING_EXPIRED");
  const current = await f.a.mutation(open, {});
  await f.send(current.capability, batch);
  await f.a.mutation(api.users.deleteCurrentUser, {});
  await expect(f.send(current.capability, batch)).rejects.toThrow("SYNC_ACCOUNT_MISSING");
  await f.t.run(async ctx => {
    for (const table of ["librarySyncBindings", "librarySyncStreams", "librarySyncMarks", "librarySyncFolderKeys"] as const) {
      expect(await ctx.db.query(table).collect()).toHaveLength(0);
    }
  });
});

test("a stale placement cannot overwrite a newer cloud folder move", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const batch: SyncBatch = { id: "batch-folder", operations: [
    { id: "create-folder", revision: "revision-1", at: 1_000, command: { kind: "folder_create", key: "guest-folder", name: "First folder", purpose: "guest_claim" } },
    { id: "bookmark-folder", revision: "revision-2", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "place-folder", revision: "revision-3", at: 1_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "guest-folder" } } },
  ] };
  await f.send(binding.capability, batch);
  const destination = await f.a.mutation(api.library.createSavedFolder, { name: "New cloud folder" });
  await f.a.mutation(api.library.assignSavedFolder, { hadithId: f.hadithId, folderId: destination });
  const stale = await f.send(binding.capability, { id: "batch-stale-placement", operations: [
    { id: "stale-placement", revision: "revision-4", at: 1_500, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "guest-folder" } } },
  ] } );
  expect(stale.receipts[0].outcome).toEqual({ kind: "superseded", reason: "newer_cloud" });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].folderId).toBe(destination);
});

test("legacy positions resolve through their actual public target and report the transformation", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const result = await f.send(binding.capability, { id: "batch-legacy-position", operations: [
    { id: "legacy-position", revision: "revision-1", at: 1_000, command: { kind: "legacy_position_put", hadithId: f.hadithId, updatedAt: 1_000 } },
  ] } );
  expect(result.receipts[0].outcome).toMatchObject({ kind: "resolved_position", position: { anchor: { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "1" } } });
  expect(await f.a.query(api.library.listReadingProgressDetailed, {})).toMatchObject([{ position: { anchor: { providerHadithId: "1" } } }]);
});

test("undo does not overwrite a note recreated by another device through an existing mutation", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_000);
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "batch-note-original", operations: [
    { id: "put-original", revision: "revision-1", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Original fixture", createdAt: 1_000, updatedAt: 1_000 } },
    { id: "remove-original", revision: "revision-2", at: 2_000, command: { kind: "note_remove", hadithId: f.hadithId } },
  ] } );
  vi.setSystemTime(2_500);
  await f.a.mutation(api.library.upsertSavedNote, { hadithId: f.hadithId, content: "New device fixture" });
  const undone = await f.send(binding.capability, { id: "batch-note-undo", operations: [
    { id: "undo-original", revision: "revision-3", at: 3_000, command: { kind: "facet_restore", hadithId: f.hadithId, deletionId: "remove-original", value: { kind: "note", content: "Original fixture", createdAt: 1_000, updatedAt: 1_000 } } },
  ] } );
  expect(undone.receipts[0].outcome).toEqual({ kind: "superseded", reason: "changed_since_delete" });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("New device fixture");
});

test("an older folder deletion cannot remove a newer cloud placement", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_000);
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const created = await f.send(binding.capability, { id: "delete-order-create", operations: [
    { id: "delete-order-folder", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "folder-key", name: "Folder fixture", purpose: "guest_claim" } },
    { id: "delete-order-add", revision: "r2", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "delete-order-place", revision: "r3", at: 1_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "folder-key" } } },
  ] } );
  const first = created.receipts[0].outcome;
  if (first.kind !== "folder") throw new Error("Missing fixture folder");
  vi.setSystemTime(2_500);
  await f.a.mutation(api.library.assignSavedFolder, { hadithId: f.hadithId, folderId: first.folderId });
  const result = await f.send(binding.capability, { id: "delete-order-old", operations: [
    { id: "delete-order-delete", revision: "r4", at: 2_000, command: { kind: "folder_delete", folder: { kind: "server", id: first.folderId } } },
  ] } );
  expect(result.receipts[0].outcome).toEqual({ kind: "superseded", reason: "newer_cloud" });
  const snapshot = await f.a.query(api.library.listSavedSnapshot, {});
  expect(snapshot.folders).toHaveLength(1);
  expect(snapshot.items[0].folderId).toBe(first.folderId);
});

test("folder restore reports unchanged and changed memberships separately", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_000);
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const secondId = await f.t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "2", arabicText: "نص", collectionName: "Bukhari", referenceDisplay: "Bukhari 2", createdAt: 1 }));
  const commands: SyncBatch["operations"] = [{ id: "restore-folder-create", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "folder-key", name: "Folder fixture", purpose: "guest_claim" } }];
  for (const [index, id] of [f.hadithId, secondId].entries()) commands.push(
    { id: `restore-add-${index}`, revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: id, createdAt: 1_000 } },
    { id: `restore-place-${index}`, revision: "r1", at: 1_000, command: { kind: "membership_put", hadithId: id, folder: { kind: "local", key: "folder-key" } } },
  );
  await f.send(binding.capability, { id: "restore-folder-initial", operations: commands } );
  await f.send(binding.capability, { id: "restore-folder-delete", operations: [
    { id: "restore-folder-deletion", revision: "r2", at: 2_000, command: { kind: "folder_delete", folder: { kind: "local", key: "folder-key" } } },
  ] } );
  const staleUndo = await f.send(binding.capability, { id: "restore-before-deletion", operations: [
    { id: "restore-too-old", revision: "r1", at: 1_500, command: { kind: "folder_restore", deletionId: "restore-folder-deletion", name: "Folder fixture", hadithIds: [f.hadithId] } },
  ] });
  expect(staleUndo.receipts[0].outcome).toEqual({ kind: "superseded", reason: "newer_cloud" });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).folders).toEqual([]);
  vi.setSystemTime(2_500);
  const destination = await f.a.mutation(api.library.createSavedFolder, { name: "New device folder" });
  await f.a.mutation(api.library.assignSavedFolder, { hadithId: secondId, folderId: destination });
  const result = await f.send(binding.capability, { id: "restore-folder-undo", operations: [
    { id: "restore-folder-action", revision: "r3", at: 3_000, command: { kind: "folder_restore", deletionId: "restore-folder-deletion", name: "Folder fixture", hadithIds: [f.hadithId, secondId] } },
  ] } );
  expect(result.receipts[0].outcome).toMatchObject({ kind: "folder_restored", restored: [f.hadithId], superseded: [secondId], missing: [] });
  const snapshot = await f.a.query(api.library.listSavedSnapshot, {});
  expect(snapshot.items.find(item => item.hadithId === secondId)?.folderId).toBe(destination);
});


test("routine position sync continues beyond old lifetime limits with one compact stream row", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.t.run(async ctx => {
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", "sync_fixture_a")).unique();
    if (!user) throw new Error("Missing fixture owner");
    await ctx.db.insert("librarySyncStreams", { userId: user._id, clientKey: "many-readings", closedThrough: 10_000 });
  });
  for (let index = 1; index <= 100; index++) {
    const frame: SyncFrame = { clientKey: "many-readings", sequence: 10_000 + index, batch: { id: `reading-${index}`, operations: [
      { id: `position-${index}`, revision: "r1", at: 1_000 + index, command: { kind: "legacy_position_put", hadithId: f.hadithId, updatedAt: 1_000 + index } },
    ] } };
    const result = await f.a.mutation(apply, { capability: binding.capability, frame });
    if (result.kind !== "accepted") throw new Error("Routine sync stalled");
    await f.a.mutation(ack, { capability: binding.capability, acknowledgement: { clientKey: frame.clientKey, sequence: frame.sequence, batchId: frame.batch.id, digest: result.committed.digest } });
  }
  await f.t.run(async ctx => {
    const streams = await ctx.db.query("librarySyncStreams").collect();
    expect(streams).toHaveLength(1);
    expect(streams[0]).toMatchObject({ closedThrough: 10_100 });
    expect(streams[0].active).toBeUndefined();
    expect(await ctx.db.query("readingProgress").collect()).toHaveLength(1);
    expect(await ctx.db.query("librarySyncMarks").collect()).toHaveLength(1);
  });
});

test("a different backup batch at an occupied sequence returns receipt proof without applying its intent", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const frame: SyncFrame = { clientKey: "forked-device", sequence: 1, batch: { id: "first-fork", operations: [
    { id: "first-note", revision: "r1", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Committed fixture", createdAt: 1_000, updatedAt: 1_000 } },
  ] } };
  const first = await f.a.mutation(apply, { capability: binding.capability, frame });
  if (first.kind !== "accepted") throw new Error("Missing fixture receipt");
  const other = { ...frame, batch: { id: "other-fork", operations: [{ ...frame.batch.operations[0], id: "different-intent", command: { kind: "note_remove", hadithId: f.hadithId } }] } } satisfies SyncFrame;
  expect(await f.a.mutation(apply, { capability: binding.capability, frame: other })).toMatchObject({ kind: "reconcile", cursor: { closedThrough: 0, active: first.committed } });
  const acknowledgement = { clientKey: frame.clientKey, sequence: 1, batchId: frame.batch.id, digest: "wrong-digest" };
  expect(await f.a.mutation(ack, { capability: binding.capability, acknowledgement })).toMatchObject({ cursor: { closedThrough: 0, active: first.committed } });
  await expect(f.b.mutation(ack, { capability: binding.capability, acknowledgement })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  await f.a.mutation(ack, { capability: binding.capability, acknowledgement: { ...acknowledgement, digest: first.committed.digest } });
  expect(await f.a.mutation(apply, { capability: binding.capability, frame: other })).toMatchObject({ kind: "reconcile", cursor: { closedThrough: 1 } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("Committed fixture");
});

test("a sequence gap has no effects and reports the actual cursor", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const result = await f.a.mutation(apply, { capability: binding.capability, frame: { clientKey: "old-backup", sequence: 7, batch: { id: "unsent-backup", operations: [
    { id: "must-not-apply", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
  ] } } });
  expect(result).toMatchObject({ kind: "reconcile", requestedSequence: 7, cursor: { closedThrough: 0 } });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items).toEqual([]);
});

test("compacted remove receipts still allow only a matching current facet undo", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "before-undo", operations: [
    { id: "note-before", revision: "r1", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Restored fixture", createdAt: 1_000, updatedAt: 1_000 } },
    { id: "note-deletion", revision: "r1", at: 2_000, command: { kind: "note_remove", hadithId: f.hadithId } },
  ] });
  const restored = await f.send(binding.capability, { id: "after-compaction-undo", operations: [
    { id: "note-undo", revision: "r1", at: 3_000, command: { kind: "facet_restore", hadithId: f.hadithId, deletionId: "note-deletion", value: { kind: "note", content: "Restored fixture", createdAt: 1_000, updatedAt: 1_000 } } },
  ] });
  expect(restored.receipts[0].outcome).toEqual({ kind: "preserved" });
  expect((await f.a.query(api.library.listSavedSnapshot, {})).items[0].noteContent).toBe("Restored fixture");
});
