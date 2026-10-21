/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { makeFunctionReference } from "convex/server";
import { afterEach, expect, test, vi } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";
import type { SyncBinding, SyncExchange, SyncFrame } from "./lib/librarySyncPolicy";
const modules = import.meta.glob("./**/*.ts");
afterEach(() => vi.useRealTimers());
const open = makeFunctionReference<"mutation", Record<string, never>, SyncBinding>("librarySync:openBinding");
const apply = makeFunctionReference<"mutation", { capability: string; frame: SyncFrame }, SyncExchange>("librarySync:applyBatch");

// Default preserves the installed v1 safety contract. The required-support mode
// exercises the binding used by current native clients and its bounded receipt.
test("a 501-member folder is never partially removed or silently truncated", async () => {
  vi.useFakeTimers(); vi.setSystemTime(1_000_000);
  const requireManifest = process.env.HADITHLY_REQUIRE_LARGE_FOLDER_SUPPORT === "1";
  const t = convexTest(schema, modules);
  const owner = t.withIdentity({ subject: "folder-scale-owner", tokenIdentifier: "fixture:folder-scale-owner" });
  const other = t.withIdentity({ subject: "folder-scale-other", tokenIdentifier: "fixture:folder-scale-other" });
  const userId = await owner.mutation(api.users.ensureCurrentUser, {});
  const otherId = await other.mutation(api.users.ensureCurrentUser, {});
  const folderId = await t.run(ctx => ctx.db.insert("savedFolders", { userId, name: "Scale fixture", normalizedName: "scale fixture", createdAt: 1_000, updatedAt: 1_000 }));
  const otherFolder = await t.run(ctx => ctx.db.insert("savedFolders", { userId: otherId, name: "Other private folder", normalizedName: "other private folder", createdAt: 1_000, updatedAt: 1_000 }));
  for (let start = 0; start < 501; start += 100) await t.run(async ctx => {
    for (let index = start; index < Math.min(start + 100, 501); index++) {
      const hadithId = await ctx.db.insert("hadiths", { provider: "sunnah_now", collectionSlug: "bukhari", providerHadithId: String(index + 1), volumeId: "1", collectionName: "Bukhari", referenceDisplay: `Bukhari ${index + 1}`, arabicText: "نص", createdAt: 1 });
      await ctx.db.insert("savedItems", { userId, hadithId, folderId, folderUpdatedAt: 1_000, bookmarkCreatedAt: 1_000, createdAt: 1_000, updatedAt: 1_000 });
      if (index === 0) await ctx.db.insert("savedItems", { userId: otherId, hadithId, folderId: otherFolder, folderUpdatedAt: 1_000, noteContent: "Other private fixture", noteCreatedAt: 1_000, noteUpdatedAt: 1_000, createdAt: 1_000, updatedAt: 1_000 });
    }
  });
  const binding = await owner.mutation(requireManifest ? api.librarySync.openManifestBinding : open, {});
  let exchange = await owner.mutation(apply, { capability: binding.capability, frame: { clientKey: "folder-scale-device", sequence: 1, batch: { id: "folder-scale-delete", operations: [{ id: "delete-large-folder", revision: "r1", at: 2_000, command: { kind: "folder_delete", folder: { kind: "server", id: folderId } } }] } } });
  if (exchange.kind === "pending" && requireManifest) {
    const pending = exchange.pending;
    await t.finishAllScheduledFunctions(vi.runAllTimers);
    exchange = await owner.query(api.librarySync.pollPending, { capability: binding.capability, pending });
  }
  if (exchange.kind !== "accepted") throw new Error("Missing exact scale receipt");
  const outcome = exchange.committed.reply.receipts[0].outcome;
  const saved = await owner.query(api.library.listSavedSnapshot, {});
  const otherSaved = await other.query(api.library.listSavedSnapshot, {});
  expect(saved.items).toHaveLength(501);
  expect(otherSaved.items).toMatchObject([{ folderId: otherFolder, noteContent: "Other private fixture" }]);
  if (outcome.kind === "folder_deleted_manifest") {
    expect(outcome.count).toBe(501);
    expect(saved.folders).toHaveLength(0);
    expect(saved.items.every(item => item.folderId === undefined)).toBe(true);
  } else {
    expect(outcome).toEqual({ kind: "unresolved", reason: "folder_too_large" });
    expect(saved.folders).toMatchObject([{ _id: folderId }]);
    expect(saved.items.every(item => item.folderId === folderId)).toBe(true);
  }
  if (requireManifest) expect(outcome.kind).toBe("folder_deleted_manifest");
});
