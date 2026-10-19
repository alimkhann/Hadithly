/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { afterEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import { savedFolderScanGuard } from "./lib/savedMembership";
import type { Id } from "./_generated/dataModel";
import type { SyncBinding, SyncExchange, SyncFrame, SyncOperation } from "./lib/librarySyncPolicy";
const modules = import.meta.glob("./**/*.ts");
const open = makeFunctionReference<"mutation", Record<string, never>, SyncBinding>("librarySync:openBinding");
const apply = makeFunctionReference<"mutation", { capability: string; frame: SyncFrame }, SyncExchange>("librarySync:applyBatch");
afterEach(() => vi.useRealTimers());

async function fixture(count = 1) {
  const t = convexTest(schema, modules);
  const owner = t.withIdentity({ subject: "scan-owner", tokenIdentifier: "fixture:scan-owner" });
  const other = t.withIdentity({ subject: "scan-other", tokenIdentifier: "fixture:scan-other" });
  const userId = await owner.mutation(api.users.ensureCurrentUser, {});
  const otherId = await other.mutation(api.users.ensureCurrentUser, {});
  const folderId = await t.run(ctx => ctx.db.insert("savedFolders", { userId, name: "Source", normalizedName: "source", createdAt: 1, updatedAt: 1 }));
  const destination = await t.run(ctx => ctx.db.insert("savedFolders", { userId, name: "Destination", normalizedName: "destination", createdAt: 1, updatedAt: 1 }));
  const ids: Id<"hadiths">[] = [];
  for (let start = 0; start < count; start += 100) await t.run(async ctx => {
    for (let index = start; index < Math.min(start + 100, count); index++) {
      const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: String(index + 1), volumeId: "1", collectionName: "Bukhari", referenceDisplay: `Bukhari ${index + 1}`, arabicText: "نص", createdAt: 1 });
      ids.push(hadithId);
      await ctx.db.insert("savedItems", { userId, hadithId, folderId, folderUpdatedAt: index + 1, bookmarkCreatedAt: 1, createdAt: 1, updatedAt: index + 1 });
    }
  });
  const binding = await owner.mutation(open, {});
  let sequence = 1;
  async function send(operations: SyncOperation[]) {
    // Separate streams let each exact result remain unacknowledged in this fixture.
    const n = sequence++;
    const result = await owner.mutation(apply, { capability: binding.capability, frame: { clientKey: `scan-device-${n}`, sequence: 1, batch: { id: `scan-batch-${n}`, operations } } });
    if (result.kind !== "accepted") throw new Error("Missing exact scan fixture receipt");
    return result.committed.reply;
  }
  async function guard(id = folderId) {
    return t.run(async ctx => {
      const folder = await ctx.db.get(id);
      if (!folder) throw new Error("Missing scan fixture folder");
      return savedFolderScanGuard(ctx, folder);
    });
  }
  return { t, owner, other, userId, otherId, folderId, destination, ids, send, guard };
}

test("the indexed maximum follows the current members of a 2001-item folder", async () => {
  const f = await fixture(2_001);
  expect(await f.guard()).toEqual({ epoch: 0, latestAt: 2_001 });
  // A corrupt foreign pointer must not participate in this owner's guard.
  await f.t.run(ctx => ctx.db.insert("savedItems", { userId: f.otherId, hadithId: f.ids[0], folderId: f.folderId, folderUpdatedAt: 50_000, noteContent: "Other private fixture", createdAt: 1, updatedAt: 50_000 }));
  expect(await f.guard()).toEqual({ epoch: 0, latestAt: 2_001 });
  await f.send([{ id: "move-maximum", revision: "r1", at: 3_000, command: { kind: "membership_put", hadithId: f.ids[2_000], folder: { kind: "server", id: f.destination } } }]);
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: 2_000 });
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 3_000 });
  await f.send([{ id: "remove-next-maximum", revision: "r1", at: 4_000, command: { kind: "bookmark_remove", hadithId: f.ids[1_999] } }]);
  expect(await f.guard()).toEqual({ epoch: 2, latestAt: 1_999 });
  const other = await f.other.query(api.library.listSavedSnapshot, {});
  expect(other.items[0].noteContent).toBe("Other private fixture");
});

test("accepted same-folder clocks invalidate a scan; stale observations and note edits do not", async () => {
  const f = await fixture();
  const move = { kind: "membership_put", hadithId: f.ids[0], folder: { kind: "server", id: f.folderId } } satisfies SyncOperation["command"];
  await f.send([{ id: "advance-placement-clock", revision: "r1", at: 10, command: move }]);
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: 10 });
  await f.send([{ id: "observe-tied-placement", revision: "r1", at: 10, command: move }]);
  await f.send([{ id: "observe-older-placement", revision: "r1", at: 5, command: move }]);
  await f.send([{ id: "edit-independent-note", revision: "r1", at: 20, command: { kind: "note_put", hadithId: f.ids[0], content: "Independent text", createdAt: 20, updatedAt: 20 } }]);
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: 10 });
  await f.send([{ id: "remove-bookmark-keep-note", revision: "r1", at: 25, command: { kind: "bookmark_remove", hadithId: f.ids[0] } }]);
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: 10 });
  await f.send([{ id: "remove-last-note", revision: "r1", at: 30, command: { kind: "note_remove", hadithId: f.ids[0] } }]);
  expect(await f.guard()).toEqual({ epoch: 2, latestAt: null });
});

test("legacy assignment and last-facet removal invalidate both relevant scans", async () => {
  vi.useFakeTimers(); vi.setSystemTime(10_000);
  const f = await fixture();
  await f.owner.mutation(api.library.assignSavedFolder, { hadithId: f.ids[0], folderId: f.destination });
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: null });
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 10_000 });
  await f.owner.mutation(api.library.assignSavedFolder, { hadithId: f.ids[0], folderId: f.destination });
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 10_000 });
  await f.owner.mutation(api.library.toggleSavedBookmark, { hadithId: f.ids[0] });
  expect(await f.guard(f.destination)).toEqual({ epoch: 2, latestAt: null });
});

test("guest placements invalidate the target without treating a later note as a placement", async () => {
  const f = await fixture();
  await f.owner.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "guest-destination", name: "Destination", createdAt: 1 }],
    savedItems: [{ hadithId: f.ids[0], bookmarkCreatedAt: 1, folderLocalId: "guest-destination", folderUpdatedAt: 20, createdAt: 1, updatedAt: 20 }],
  });
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: null });
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 20 });
  await f.owner.mutation(api.guestMerge.mergeGuestData, { bookmarks: [], notes: [],
    savedFolders: [{ localId: "guest-source", name: "Source", createdAt: 1 }],
    savedItems: [{ hadithId: f.ids[0], bookmarkCreatedAt: 1, folderLocalId: "guest-source", folderUpdatedAt: 10, noteContent: "Later note", noteCreatedAt: 30, noteUpdatedAt: 30, createdAt: 1, updatedAt: 30 }],
  });
  expect(await f.guard()).toEqual({ epoch: 1, latestAt: null });
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 20 });
});

test("unknown-time guest placement seeds one membership epoch but no clock", async () => {
  const f = await fixture();
  await f.send([{ id: "clear-versioned-membership", revision: "r1", at: 2, command: { kind: "membership_put", hadithId: f.ids[0], folder: { kind: "none" } } }]);
  const freshId = await f.t.run(ctx => ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: "fresh", volumeId: "1", collectionName: "Bukhari", referenceDisplay: "Fresh", arabicText: "نص", createdAt: 1 }));
  const payload = { bookmarks: [], notes: [], savedFolders: [{ localId: "unknown-destination", name: "Destination", createdAt: 1 }],
    savedItems: [{ hadithId: freshId, bookmarkCreatedAt: 1, folderLocalId: "unknown-destination", createdAt: 1, updatedAt: 1 }] };
  await f.owner.mutation(api.guestMerge.mergeGuestData, payload);
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 0 });
  await f.owner.mutation(api.guestMerge.mergeGuestData, payload);
  expect(await f.guard(f.destination)).toEqual({ epoch: 1, latestAt: 0 });
});

test("both legacy and queued folder restoration invalidate a scan of an existing destination", async () => {
  vi.useFakeTimers(); vi.setSystemTime(10_000);
  const f = await fixture();
  const deletion = await f.owner.mutation(api.library.deleteSavedFolder, { folderId: f.folderId });
  if (!deletion) throw new Error("Missing legacy deletion");
  const recreated = await f.owner.mutation(api.library.createSavedFolder, { name: "Source" });
  await f.owner.mutation(api.library.restoreSavedFolder, deletion);
  expect(await f.guard(recreated)).toEqual({ epoch: 1, latestAt: 10_000 });
  await f.send([{ id: "scan-queued-delete", revision: "r1", at: 20_000, command: { kind: "folder_delete", folder: { kind: "server", id: recreated } } }]);
  const next = await f.owner.mutation(api.library.createSavedFolder, { name: "Source" });
  await f.send([{ id: "scan-queued-restore", revision: "r1", at: 30_000, command: { kind: "folder_restore", deletionId: "scan-queued-delete", name: "Source", hadithIds: f.ids } }]);
  expect(await f.guard(next)).toEqual({ epoch: 1, latestAt: 30_000 });
});

test("a malformed foreign pointer neither fills the owner's deletion limit nor changes", async () => {
  const f = await fixture(500);
  const foreignId = await f.t.run(ctx => ctx.db.insert("savedItems", { userId: f.otherId, hadithId: f.ids[0], folderId: f.folderId,
    folderUpdatedAt: 60_000, noteContent: "Foreign pointer fixture", createdAt: 1, updatedAt: 60_000 }));
  const reply = await f.send([{ id: "owned-limit-delete", revision: "r1", at: 1_000, command: { kind: "folder_delete", folder: { kind: "server", id: f.folderId } } }]);
  expect(reply.receipts[0].outcome).toMatchObject({ kind: "folder_deleted", hadithIds: f.ids });
  expect(await f.t.run(ctx => ctx.db.get(foreignId))).toMatchObject({ folderId: f.folderId, folderUpdatedAt: 60_000, noteContent: "Foreign pointer fixture", updatedAt: 60_000 });
});

test("legacy physical deletion never patches a foreign malformed pointer", async () => {
  const f = await fixture();
  const foreignId = await f.t.run(ctx => ctx.db.insert("savedItems", { userId: f.otherId, hadithId: f.ids[0], folderId: f.folderId,
    folderUpdatedAt: 60_000, noteContent: "Foreign legacy pointer fixture", createdAt: 1, updatedAt: 60_000 }));
  const reply = await f.owner.mutation(api.library.deleteSavedFolder, { folderId: f.folderId });
  expect(reply?.hadithIds).toEqual(f.ids);
  expect(await f.t.run(ctx => ctx.db.get(foreignId))).toMatchObject({ folderId: f.folderId, folderUpdatedAt: 60_000, noteContent: "Foreign legacy pointer fixture", updatedAt: 60_000 });
});
