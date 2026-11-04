/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { expect, test, vi, afterEach } from "vitest";
import schema from "./schema";
import { api } from "./_generated/api";
import type { SyncBatch, SyncBinding, SyncReply, SyncExchange, SyncFrame, SyncAckReply, SyncAcknowledgement, SyncSavedSnapshot, SyncPositionsSnapshot } from "./lib/librarySyncPolicy";
const modules = import.meta.glob("./**/*.ts");
const open = makeFunctionReference<"mutation", Record<string, never>, SyncBinding>("librarySync:openBinding");
const apply = makeFunctionReference<"mutation", { capability: string; frame: SyncFrame }, SyncExchange>("librarySync:applyBatch");
const ack = makeFunctionReference<"mutation", { capability: string; acknowledgement: SyncAcknowledgement }, SyncAckReply>("librarySync:acknowledge");
const ownedSaved = makeFunctionReference<"query", Record<string, never>, SyncSavedSnapshot>("librarySync:savedSnapshot");
const ownedPositions = makeFunctionReference<"query", Record<string, never>, SyncPositionsSnapshot>("librarySync:positionsSnapshot");
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

test("onboarding initializes once and preserves a later explicit notification choice", async () => {
  const f = await fixture();
  const binding = await f.a.mutation(open, {});
  const init = makeFunctionReference<"mutation", { capability: string }, { enabled: boolean; dailyTime: string; initialized: boolean }>("library:initializeDailyNotification");
  const tokenId = await f.a.mutation(api.library.savePushToken, { token: "auto-registered", platform: "android" });
  expect(await f.t.run(ctx => ctx.db.get(tokenId))).toMatchObject({ enabled: false, preferenceOrigin: "default" });
  await expect(f.b.mutation(init, { capability: binding.capability })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  expect((await f.b.query(api.users.getCurrentUser, {}))?.dailyNotificationEnabled).toBeUndefined();
  expect(await f.a.mutation(init, { capability: binding.capability })).toEqual({ enabled: true, dailyTime: "08:00", initialized: true });
  expect(await f.t.run(ctx => ctx.db.get(tokenId))).toMatchObject({ enabled: true, dailyTime: "08:00", preferenceOrigin: "chosen" });
  await f.a.mutation(api.library.setDailyNotification, { enabled: false, dailyTime: "18:37" });
  expect(await f.a.mutation(init, { capability: binding.capability })).toEqual({ enabled: false, dailyTime: "18:37", initialized: false });
  expect(await f.t.run(ctx => ctx.db.get(tokenId))).toMatchObject({ enabled: false, dailyTime: "18:37", preferenceOrigin: "chosen" });
});

test("onboarding preserves the latest legacy token choice", async () => {
  const f = await fixture();
  const binding = await f.a.mutation(open, {});
  const init = makeFunctionReference<"mutation", { capability: string }, { enabled: boolean; dailyTime: string; initialized: boolean }>("library:initializeDailyNotification");
  await f.t.run(async ctx => {
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", "sync_fixture_a")).unique();
    if (!user) throw new Error("missing fixture");
    await ctx.db.insert("pushTokens", { userId: user._id, token: "legacy", platform: "ios", enabled: false, dailyTime: "19:30", updatedAt: 1 });
  });
  expect(await f.a.mutation(init, { capability: binding.capability })).toEqual({ enabled: false, dailyTime: "19:30", initialized: false });
});

test("notification preference capability fences stale and wrong owners before any writes", async () => {
  vi.useFakeTimers();
  const f = await fixture();
  const binding = await f.a.mutation(open, {});
  const notify = makeFunctionReference<"mutation", { enabled: boolean; dailyTime: string; capability?: string }, number>("library:setDailyNotification");
  const tokenId = await f.b.mutation(api.library.savePushToken, { token: "binding-test", platform: "ios" });
  const before = await f.t.run(ctx => ctx.db.get(tokenId));
  await expect(f.b.mutation(notify, { enabled: true, dailyTime: "07:00", capability: binding.capability })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  expect(await f.t.run(ctx => ctx.db.get(tokenId))).toEqual(before);
  expect((await f.b.query(api.users.getCurrentUser, {}))?.dailyNotificationEnabled).toBeUndefined();
  await expect(f.t.mutation(notify, { enabled: true, dailyTime: "07:00", capability: binding.capability })).rejects.toThrow("Unauthenticated");
  await expect(f.t.withIdentity({ subject: "no_account", tokenIdentifier: "https://clerk.example|no_account" }).mutation(notify,
    { enabled: true, dailyTime: "07:00", capability: binding.capability })).rejects.toThrow("SYNC_ACCOUNT_MISSING");
  expect(await f.a.mutation(notify, { enabled: true, dailyTime: "07:00", capability: binding.capability })).toBe(0);
  vi.setSystemTime(binding.validUntil + 1);
  await expect(f.a.mutation(notify, { enabled: false, dailyTime: "08:00", capability: binding.capability })).rejects.toThrow("SYNC_BINDING_EXPIRED");
  expect((await f.a.query(api.users.getCurrentUser, {}))?.dailyNotificationEnabled).toBe(true);
  await f.a.mutation(notify, { enabled: false, dailyTime: "09:00" });
  expect((await f.a.query(api.users.getCurrentUser, {}))?.dailyNotificationEnabled).toBe(false);
});

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
  await f.a.mutation(api.users.deleteCurrentUser, { authorization: (await f.a.mutation(api.users.prepareAccountDeletion, {})).authorization });
  await expect(f.send(current.capability, batch)).rejects.toThrow("SYNC_ACCOUNT_MISSING");
  await f.t.run(async ctx => {
    for (const table of ["librarySyncBindings", "librarySyncStreams", "librarySyncRetirements", "librarySyncMarks", "librarySyncFolderKeys", "librarySyncVersions"] as const) {
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
    { id: "restore-folder-action", revision: "r3", at: 3_000, command: { kind: "folder_restore", deletionId: "restore-folder-deletion", name: "Folder fixture", hadithIds: [f.hadithId] } },
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
    expect(streams[0].slot).toBeUndefined();
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
  expect(await f.a.mutation(apply, { capability: binding.capability, frame: other })).toMatchObject({ kind: "reconcile", cursor: { closedThrough: 0, outstanding: { kind: "committed", committed: first.committed } } });
  const acknowledgement = { clientKey: frame.clientKey, sequence: 1, batchId: frame.batch.id, digest: "wrong-digest" };
  expect(await f.a.mutation(ack, { capability: binding.capability, acknowledgement })).toMatchObject({ cursor: { closedThrough: 0, outstanding: { kind: "committed", committed: first.committed } } });
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

test("folder undo restores actual deleted members even when the native snapshot omitted one", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const secondId = await f.t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "2", arabicText: "نص", collectionName: "Bukhari", referenceDisplay: "Bukhari 2", createdAt: 1 }));
  const operations: SyncBatch["operations"] = [{ id: "actual-folder", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "actual-key", name: "Actual members", purpose: "create" } }];
  for (const [index, hadithId] of [f.hadithId, secondId].entries()) operations.push(
    { id: `actual-add-${index}`, revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId, createdAt: 1_000 } },
    { id: `actual-place-${index}`, revision: "r1", at: 1_000, command: { kind: "membership_put", hadithId, folder: { kind: "local", key: "actual-key" } } },
  );
  await f.send(binding.capability, { id: "actual-seed", operations });
  const deleted = await f.send(binding.capability, { id: "actual-delete", operations: [{ id: "actual-deletion", revision: "r1", at: 2_000, command: { kind: "folder_delete", folder: { kind: "local", key: "actual-key" } } }] });
  expect(deleted.receipts[0].outcome).toMatchObject({ kind: "folder_deleted", hadithIds: expect.arrayContaining([f.hadithId, secondId]) });
  const restored = await f.send(binding.capability, { id: "actual-undo", operations: [{ id: "actual-restoration", revision: "r1", at: 3_000,
    command: { kind: "folder_restore", deletionId: "actual-deletion", name: "Actual members", hadithIds: [f.hadithId] } }] });
  const outcome = restored.receipts[0].outcome;
  expect(outcome).toMatchObject({ kind: "folder_restored", restored: expect.arrayContaining([f.hadithId, secondId]), superseded: [], missing: [] });
  if (outcome.kind !== "folder_restored") throw new Error("Missing restored fixture");
  const saved = await f.a.query(api.library.listSavedSnapshot, {});
  expect(saved.items.map(item => item.folderId)).toEqual([outcome.folderId, outcome.folderId]);
});

test("owned library snapshots keep exact targets and independent domain revisions", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const empty = await f.a.query(ownedSaved, {});
  const other = await f.b.query(ownedSaved, {});
  expect(empty.ownerKey).not.toBe(other.ownerKey);
  expect(empty).toMatchObject({ version: 0, folders: [], items: [] });
  await f.send(binding.capability, { id: "owned-note", operations: [{ id: "owned-note-intent", revision: "r1", at: 1_000,
    command: { kind: "note_put", hadithId: f.hadithId, content: "Owned private fixture", createdAt: 1_000, updatedAt: 1_000 } }] });
  const saved = await f.a.query(ownedSaved, {});
  expect(saved).toMatchObject({ ownerKey: empty.ownerKey, version: 1, items: [{ hadithId: f.hadithId, noteContent: "Owned private fixture", hadith: { _id: f.hadithId, providerHadithId: "1" } }] });
  expect((await f.b.query(ownedSaved, {})).items).toEqual([]);
  expect(await f.a.query(ownedPositions, {})).toMatchObject({ ownerKey: empty.ownerKey, version: 0, rows: [] });
  await f.send(binding.capability, { id: "owned-position", operations: [{ id: "owned-position-intent", revision: "r1", at: 2_000,
    command: { kind: "legacy_position_put", hadithId: f.hadithId, updatedAt: 2_000 } }] });
  expect(await f.a.query(ownedSaved, {})).toEqual(saved);
  expect(await f.a.query(ownedPositions, {})).toMatchObject({ ownerKey: empty.ownerKey, version: 1, rows: [{ hadithId: f.hadithId, position: { anchor: { providerHadithId: "1" } } }] });
  await f.a.mutation(api.library.upsertSavedNote, { hadithId: f.hadithId, content: "Later legacy fixture" });
  expect(await f.a.query(ownedSaved, {})).toMatchObject({ version: 2, items: [{ noteContent: "Later legacy fixture" }] });
});

test("bound existing account operations reject another JWT before private effects", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await expect(f.b.mutation(api.users.ensureCurrentUser, { capability: binding.capability, preferredLanguage: "ru" })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  await expect(f.b.query(api.users.getCurrentUserPreferences, { capability: binding.capability })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  await expect(f.b.query(api.users.exportCurrentUserData, { capability: binding.capability })).rejects.toThrow("SYNC_OWNER_MISMATCH");
  const deletion = await f.a.mutation(api.users.prepareAccountDeletion, {});
  await expect(f.b.mutation(api.users.deleteCurrentUser, { authorization: deletion.authorization })).rejects.toThrow("ACCOUNT_DELETION_OWNER_MISMATCH");
  expect((await f.b.query(api.users.getCurrentUserPreferences, {}))?.readerPreferences?.translationLocale).toBe("en");
  expect(await f.b.query(api.users.getCurrentUser, {})).not.toBeNull();
});

test("owned Saved adds only bounded metadata while keeping the separate progress payload", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "payload-fixture", operations: [{ id: "payload-note", revision: "r1", at: 1_000,
    command: { kind: "note_put", hadithId: f.hadithId, content: "Payload fixture", createdAt: 1_000, updatedAt: 1_000 } }] });
  const legacy = await f.a.query(api.library.listSavedSnapshot, {});
  const owned = await f.a.query(ownedSaved, {});
  expect(owned.items.map(item => item.hadithId)).toEqual(legacy.items.map(item => item.hadithId));
  const bytes = (value: unknown) => new TextEncoder().encode(JSON.stringify(value)).byteLength;
  expect(bytes(owned)).toBeLessThanOrEqual(bytes(legacy) + 200);
  expect(Object.hasOwn(owned, "rows")).toBe(false);
  expect((await f.a.query(ownedPositions, {})).rows).toEqual([]);
});


test("removing an already absent facet cannot acquire another deletion's undo authority", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "original-removal", operations: [
    { id: "original-bookmark", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "actual-deletion", revision: "r1", at: 2_000, command: { kind: "bookmark_remove", hadithId: f.hadithId } },
  ] });
  await f.send(binding.capability, { id: "stale-removal", operations: [
    { id: "absent-deletion", revision: "r1", at: 3_000, command: { kind: "bookmark_remove", hadithId: f.hadithId } },
  ] });
  const denied = await f.send(binding.capability, { id: "stale-undo", operations: [
    { id: "absent-undo", revision: "r1", at: 4_000, command: { kind: "facet_restore", hadithId: f.hadithId, deletionId: "absent-deletion", value: { kind: "bookmark", createdAt: 1_000 } } },
  ] });
  expect(denied.receipts[0].outcome).toEqual({ kind: "superseded", reason: "changed_since_delete" });
  expect((await f.a.query(ownedSaved, {})).items).toEqual([]);
  const allowed = await f.send(binding.capability, { id: "actual-undo", operations: [
    { id: "real-undo", revision: "r1", at: 5_000, command: { kind: "facet_restore", hadithId: f.hadithId, deletionId: "actual-deletion", value: { kind: "bookmark", createdAt: 1_000 } } },
  ] });
  expect(allowed.receipts[0].outcome).toEqual({ kind: "preserved" });
});

test("retiring an unsendable frozen sequence fences late application without receiving private content", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const retire = makeFunctionReference<"mutation", { capability: string; clientKey: string; sequence: number }, SyncAckReply>("librarySync:retireInvalidFrame");
  const request = { capability: binding.capability, clientKey: "retired-device", sequence: 1 };
  await expect(f.b.mutation(retire, request)).rejects.toThrow("SYNC_OWNER_MISMATCH");
  const closed = await f.a.mutation(retire, request);
  expect(closed).toMatchObject({ ownerKey: binding.ownerKey, cursor: { closedThrough: 1 } });
  expect(await f.a.mutation(retire, request)).toEqual(closed);
  const late: SyncFrame = { clientKey: request.clientKey, sequence: 1, batch: { id: "late-retired", operations: [
    { id: "late-private-note", revision: "r1", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Must not resurrect", createdAt: 1_000, updatedAt: 1_000 } },
  ] } };
  expect(await f.a.mutation(apply, { capability: binding.capability, frame: late })).toMatchObject({ kind: "reconcile", cursor: { closedThrough: 1 } });
  expect((await f.a.query(ownedSaved, {})).items).toEqual([]);
  const next = { ...late, sequence: 2, batch: { ...late.batch, id: "new-valid-intent" } };
  expect(await f.a.mutation(apply, { capability: binding.capability, frame: next })).toMatchObject({ kind: "accepted" });
});

test("retirement keeps an already committed receipt exact until ACK then fences a future invalid sequence", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const retire = makeFunctionReference<"mutation", { capability: string; clientKey: string; sequence: number }, SyncAckReply>("librarySync:retireInvalidFrame");
  const frame: SyncFrame = { clientKey: "occupied-retirement", sequence: 1, batch: { id: "accepted-before-retire", operations: [
    { id: "committed-note", revision: "r1", at: 1_000, command: { kind: "note_put", hadithId: f.hadithId, content: "Committed original", createdAt: 1_000, updatedAt: 1_000 } },
  ] } };
  const first = await f.a.mutation(apply, { capability: binding.capability, frame });
  if (first.kind !== "accepted") throw new Error("Missing accepted fixture");
  const request = { capability: binding.capability, clientKey: frame.clientKey, sequence: 7 };
  const retired = await f.a.mutation(retire, request);
  expect(retired.cursor).toEqual({ closedThrough: 0, outstanding: { kind: "committed", committed: first.committed } });
  expect(await f.a.mutation(retire, request)).toEqual(retired);
  expect(await f.a.mutation(apply, { capability: binding.capability, frame })).toEqual(first);
  const proof = { clientKey: frame.clientKey, sequence: 1, batchId: frame.batch.id, digest: first.committed.digest };
  expect(await f.a.mutation(ack, { capability: binding.capability, acknowledgement: { ...proof, digest: "wrong-proof" } })).toMatchObject({ cursor: { closedThrough: 0, outstanding: { kind: "committed", committed: first.committed } } });
  expect(await f.a.mutation(ack, { capability: binding.capability, acknowledgement: proof })).toMatchObject({ cursor: { closedThrough: 1 } });
  for (let sequence = 2; sequence <= 6; sequence++) {
    const healthy = await f.a.mutation(apply, { capability: binding.capability, frame: { ...frame, sequence, batch: { id: `healthy-${sequence}`, operations: [{ id: `healthy-note-${sequence}`, revision: "r1", at: 1_000 + sequence, command: { kind: "note_put", hadithId: f.hadithId, content: "Committed original", createdAt: 1_000, updatedAt: 1_000 + sequence } }] } } });
    expect(healthy.kind).toBe("accepted");
    if (healthy.kind !== "accepted") throw new Error("Healthy restored fork was blocked");
    const closed = await f.a.mutation(ack, { capability: binding.capability, acknowledgement: { clientKey: frame.clientKey, sequence, batchId: healthy.committed.reply.batchId, digest: healthy.committed.digest } });
    expect(closed.cursor.closedThrough).toBe(sequence === 6 ? 7 : sequence);
  }
  expect(await f.t.run(ctx => ctx.db.query("librarySyncRetirements").collect())).toHaveLength(0);
  expect(await f.a.mutation(apply, { capability: binding.capability, frame: { ...frame, sequence: 7, batch: { id: "late-invalid-now-valid", operations: [
    { id: "late-remove", revision: "r2", at: 2_000, command: { kind: "note_remove", hadithId: f.hadithId } },
  ] } } })).toMatchObject({ kind: "reconcile", cursor: { closedThrough: 7 } });
  expect((await f.a.query(ownedSaved, {})).items[0].noteContent).toBe("Committed original");
  const streams = await f.t.run(ctx => ctx.db.query("librarySyncStreams").collect());
  expect(streams).toHaveLength(1);
  expect(streams[0].closedThrough).toBe(7);
  expect(streams[0].slot).toBeUndefined();
  expect(await f.t.run(ctx => ctx.db.query("librarySyncRetirements").collect())).toHaveLength(0);
});

test("retirement fences only the requested future sequence and rejects invalid stream bounds without effects", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const retire = makeFunctionReference<"mutation", { capability: string; clientKey: string; sequence: number }, SyncAckReply>("librarySync:retireInvalidFrame");
  for (const sequence of [0, 1.5, Number.MAX_SAFE_INTEGER]) await expect(f.a.mutation(retire, { capability: binding.capability, clientKey: "bounded-retirement", sequence })).rejects.toThrow("SYNC_INVALID_STREAM");
  expect(await f.t.run(ctx => ctx.db.query("librarySyncStreams").collect())).toHaveLength(0);
  expect(await f.a.mutation(retire, { capability: binding.capability, clientKey: "bounded-retirement", sequence: 7 })).toMatchObject({ cursor: { closedThrough: 0 } });
  expect(await f.t.run(ctx => ctx.db.query("librarySyncRetirements").collect())).toMatchObject([{ clientKey: "bounded-retirement", sequence: 7 }]);
  expect((await f.a.query(ownedSaved, {})).items).toEqual([]);
});

test("future retirement capacity is bounded, ordinary next retirement still works, and erasure removes fences", async () => {
  vi.useFakeTimers();
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const retire = makeFunctionReference<"mutation", { capability: string; clientKey: string; sequence: number }, SyncAckReply>("librarySync:retireInvalidFrame");
  for (let sequence = 1_000; sequence < 1_100; sequence++) await f.a.mutation(retire, { capability: binding.capability, clientKey: "capacity-device", sequence });
  await expect(f.a.mutation(retire, { capability: binding.capability, clientKey: "capacity-device", sequence: 1_100 })).rejects.toThrow("SYNC_RETIREMENT_CAPACITY");
  expect(await f.a.mutation(retire, { capability: binding.capability, clientKey: "capacity-device", sequence: 1_000 })).toMatchObject({ cursor: { closedThrough: 0 } });
  expect(await f.a.mutation(retire, { capability: binding.capability, clientKey: "capacity-device", sequence: 1 })).toMatchObject({ cursor: { closedThrough: 1 } });
  expect(await f.t.run(ctx => ctx.db.query("librarySyncRetirements").collect())).toHaveLength(100);
  const exported = await f.a.query(api.users.exportCurrentUserData, { capability: binding.capability });
  expect(exported.sync.retirements).toHaveLength(100);
  const authorization = await f.a.mutation(api.users.prepareAccountDeletion, {});
  await f.a.mutation(api.users.deleteCurrentUser, { authorization: authorization.authorization });
  await f.t.finishAllScheduledFunctions(vi.runAllTimers);
  expect(await f.t.run(ctx => ctx.db.query("librarySyncRetirements").collect())).toHaveLength(0);
});

test.each([{ at: 1_500, restorable: true }, { at: 2_000, restorable: true }, { at: 2_500, restorable: false }])("no-folder observation at $at preserves the correct Undo authority", async ({ at, restorable }) => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "membership-tie-seed", operations: [
    { id: "membership-tie-create", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "tie-folder", name: "Tie fixture", purpose: "create" } },
    { id: "membership-tie-bookmark", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "membership-tie-place", revision: "r1", at: 1_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "tie-folder" } } },
    { id: "membership-tie-delete", revision: "r1", at: 2_000, command: { kind: "folder_delete", folder: { kind: "local", key: "tie-folder" } } },
  ] });
  const observation = await f.send(binding.capability, { id: "membership-tie-observation", operations: [
    { id: "membership-tie-none", revision: "r1", at, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "none" } } },
  ] });
  expect(observation.receipts[0].outcome).toEqual({ kind: "preserved" });
  const restored = await f.send(binding.capability, { id: "membership-tie-undo", operations: [
    { id: "membership-tie-restore", revision: "r1", at: 3_000, command: { kind: "folder_restore", deletionId: "membership-tie-delete", name: "Tie fixture", hadithIds: [f.hadithId] } },
  ] });
  expect(restored.receipts[0].outcome).toMatchObject({ kind: "folder_restored", restored: restorable ? [f.hadithId] : [], superseded: restorable ? [] : [f.hadithId], missing: [] });
});

test.each([false, true])("an older guest merge preserves a newer cloud membership and its clock, same-folder=%s", async sameFolder => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const initial = await f.send(binding.capability, { id: "guest-clock-seed", operations: [
    { id: "guest-clock-create", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "cloud-folder", name: "Cloud folder", purpose: "create" } },
    { id: "guest-clock-bookmark", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "guest-clock-place", revision: "r1", at: 3_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "cloud-folder" } } },
  ] });
  const folder = initial.receipts[0].outcome;
  if (folder.kind !== "folder") throw new Error("Missing cloud folder fixture");
  await f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "guest-local-folder", name: sameFolder ? "Cloud folder" : "Older guest folder", createdAt: 1_000 }],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 500, folderLocalId: "guest-local-folder", createdAt: 500, updatedAt: 1_500 }],
  });
  const saved = await f.a.query(ownedSaved, {});
  expect(saved.items[0].folderId).toBe(folder.folderId);
  expect(saved.items[0].bookmarkCreatedAt).toBe(500);
  const olderDeletion = await f.send(binding.capability, { id: "guest-clock-old-delete", operations: [
    { id: "guest-clock-delete", revision: "r1", at: 2_000, command: { kind: "folder_delete", folder: { kind: "server", id: folder.folderId } } },
  ] });
  expect(olderDeletion.receipts[0].outcome).toEqual({ kind: "superseded", reason: "newer_cloud" });
  expect((await f.a.query(ownedSaved, {})).items[0].folderId).toBe(folder.folderId);
});


test("a newer guest placement still applies through the shared membership boundary", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "newer-guest-seed", operations: [
    { id: "newer-guest-add", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
  ] });
  await f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "guest-folder", name: "New guest folder", createdAt: 1_000 }],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 1_000, folderLocalId: "guest-folder", folderUpdatedAt: 3_000, createdAt: 1_000, updatedAt: 3_000 }],
  });
  const saved = await f.a.query(ownedSaved, {});
  expect(saved.folders).toHaveLength(1);
  expect(saved.items[0].folderId).toBe(saved.folders[0]._id);
  const old = await f.send(binding.capability, { id: "newer-guest-old", operations: [
    { id: "newer-guest-none", revision: "r1", at: 2_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "none" } } },
  ] });
  expect(old.receipts[0].outcome).toEqual({ kind: "superseded", reason: "newer_cloud" });
});

test("legacy same-clock no-folder selection preserves Undo but a newer explicit selection supersedes it", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_000);
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "legacy-tie-seed", operations: [
    { id: "legacy-tie-create", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "legacy-tie-folder", name: "Legacy tie", purpose: "create" } },
    { id: "legacy-tie-add", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "legacy-tie-place", revision: "r1", at: 1_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "legacy-tie-folder" } } },
    { id: "legacy-tie-delete", revision: "r1", at: 2_000, command: { kind: "folder_delete", folder: { kind: "local", key: "legacy-tie-folder" } } },
  ] });
  vi.setSystemTime(2_000);
  await f.a.mutation(api.library.assignSavedFolder, { hadithId: f.hadithId });
  const restored = await f.send(binding.capability, { id: "legacy-tie-undo", operations: [
    { id: "legacy-tie-restore", revision: "r1", at: 3_000, command: { kind: "folder_restore", deletionId: "legacy-tie-delete", name: "Legacy tie", hadithIds: [f.hadithId] } },
  ] });
  expect(restored.receipts[0].outcome).toMatchObject({ kind: "folder_restored", restored: [f.hadithId] });
  vi.setSystemTime(4_000);
  await f.a.mutation(api.library.assignSavedFolder, { hadithId: f.hadithId });
  expect((await f.a.query(ownedSaved, {})).items[0].folderId).toBeUndefined();
  const staleUndo = await f.send(binding.capability, { id: "legacy-tie-stale-undo", operations: [
    { id: "legacy-tie-repeat-restore", revision: "r1", at: 5_000, command: { kind: "folder_restore", deletionId: "legacy-tie-delete", name: "Legacy tie", hadithIds: [f.hadithId] } },
  ] });
  expect(staleUndo.receipts[0].outcome).toMatchObject({ kind: "folder_restored", restored: [], superseded: [f.hadithId] });
  expect((await f.a.query(ownedSaved, {})).items[0].folderId).toBeUndefined();

});


test.each([Number.NaN, Number.POSITIVE_INFINITY, -1])("an invalid guest membership clock rolls back the entire merge: %s", async updatedAt => {
  const f = await fixture();
  await expect(f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "invalid-clock-folder", name: "Invalid clock fixture", createdAt: 1_000 }],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 1_000, folderLocalId: "invalid-clock-folder", folderUpdatedAt: updatedAt, createdAt: 1_000, updatedAt: 1_000 }],
  })).rejects.toThrow("INVALID_GUEST_MERGE_CLOCK");
  expect(await f.a.query(ownedSaved, {})).toMatchObject({ version: 0, folders: [], items: [] });
});

test.each([true, false])("note edit time never masquerades as a folder move, explicit-clock=%s", async explicitClock => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const initial = await f.send(binding.capability, { id: "independent-clock-seed", operations: [
    { id: "independent-clock-folder", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "independent-cloud", name: "Independent cloud", purpose: "create" } },
    { id: "independent-clock-add", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "independent-clock-place", revision: "r1", at: 3_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "independent-cloud" } } },
  ] });
  const original = initial.receipts[0].outcome;
  if (original.kind !== "folder") throw new Error("Missing independent cloud folder");
  await f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "old-guest-folder", name: "Old guest placement", createdAt: 1_000 }],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 1_000, noteContent: "A newer independent note", noteCreatedAt: 1_000, noteUpdatedAt: 5_000,
      folderLocalId: "old-guest-folder", ...(explicitClock ? { folderUpdatedAt: 1_500 } : {}), createdAt: 1_000, updatedAt: 5_000 }],
  });
  expect((await f.a.query(ownedSaved, {})).items[0]).toMatchObject({ folderId: original.folderId, noteContent: "A newer independent note", noteUpdatedAt: 5_000 });
});

test("an unversioned guest claim seeds only unset membership without inventing ordering authority", async () => {
  const f = await fixture(), binding = await f.a.mutation(open, {});
  const seeded = await f.send(binding.capability, { id: "unversioned-seed", operations: [
    { id: "unversioned-create", revision: "r1", at: 1_000, command: { kind: "folder_create", key: "unversioned-folder", name: "Unversioned fixture", purpose: "guest_claim" } },
    { id: "unversioned-bookmark", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
    { id: "unversioned-placement", revision: "r1", at: 9_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "unversioned-folder" }, mode: "claim_if_unset" } },
  ] });
  expect(seeded.receipts[2].outcome).toEqual({ kind: "preserved" });
  expect((await f.a.query(ownedSaved, {})).items[0].folderId).toBeDefined();
  const explicit = await f.send(binding.capability, { id: "unversioned-explicit", operations: [
    { id: "explicit-placement-none", revision: "r1", at: 2_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "none" } } },
  ] });
  expect(explicit.receipts[0].outcome).toEqual({ kind: "preserved" });
  const staleClaim = await f.send(binding.capability, { id: "unversioned-repeat", operations: [
    { id: "unversioned-old-placement", revision: "r1", at: 10_000, command: { kind: "membership_put", hadithId: f.hadithId, folder: { kind: "local", key: "unversioned-folder" }, mode: "claim_if_unset" } },
  ] });
  expect(staleClaim.receipts[0].outcome).toEqual({ kind: "superseded", reason: "unversioned_cloud" });
  expect((await f.a.query(ownedSaved, {})).items[0].folderId).toBeUndefined();
});


test("unversioned guest metadata still validates its own clocks before any merge effects", async () => {
  const f = await fixture();
  await expect(f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "bad-metadata-folder", name: "Bad metadata fixture", createdAt: 1_000 }],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 1_000, folderLocalId: "bad-metadata-folder", createdAt: 1_000, updatedAt: Number.NaN }],
  })).rejects.toThrow("INVALID_GUEST_MERGE_CLOCK");
  expect(await f.a.query(ownedSaved, {})).toMatchObject({ version: 0, folders: [], items: [] });
});

test("an independent membership time keeps the Saved item update time monotonic", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_000);
  const f = await fixture(), binding = await f.a.mutation(open, {});
  await f.send(binding.capability, { id: "aggregate-monotonic-seed", operations: [
    { id: "aggregate-monotonic-bookmark", revision: "r1", at: 1_000, command: { kind: "bookmark_add", hadithId: f.hadithId, createdAt: 1_000 } },
  ] });
  await f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "aggregate-monotonic-folder", name: "Monotonic fixture", createdAt: 1_000 }],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 1_000, folderLocalId: "aggregate-monotonic-folder", folderUpdatedAt: 3_000, createdAt: 1_000, updatedAt: 1_000 }],
  });
  const saved = await f.a.query(ownedSaved, {});
  expect(saved.items[0].folderId).toBe(saved.folders[0]._id);
  expect(saved.items[0].updatedAt).toBe(3_000);
});

test("invalid membership clocks reject even when the referenced folder is absent", async () => {
  const f = await fixture();
  await expect(f.a.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedItems: [{ hadithId: f.hadithId, bookmarkCreatedAt: 1_000, folderLocalId: "absent-folder", folderUpdatedAt: Number.NaN, createdAt: 1_000, updatedAt: 1_000 }],
  })).rejects.toThrow("INVALID_GUEST_MERGE_CLOCK");
  expect(await f.a.query(ownedSaved, {})).toMatchObject({ version: 0, folders: [], items: [] });
});
