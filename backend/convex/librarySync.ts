import { librarySyncMark as mark, stampLibrarySyncMark as stamp } from "./lib/librarySyncMarks";
import { v } from "convex/values";
import { mutation, type MutationCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { requireIdentity } from "./lib/identity";
import { materializeLegacySavedItem, applyReadingPosition } from "./library";
import { normalizedFolderName } from "./lib/savedFolderPolicy";
import { legacyReadingPosition } from "./lib/readingPositions";
import { textDigest } from "./lib/evidenceReviewPolicy";
import {
  syncBatchDigest, syncReceiptSetMatches, syncWriteDecision, validateSyncBatch,
  SYNC_BINDING_LIMIT, SYNC_BINDING_LIFETIME,
  syncFrame, syncAcknowledgement, validateSyncStream,
  type SyncBinding, type SyncOperation, type SyncOutcome, type SyncReceipt, type SyncFolderReference, type SyncExchange, type SyncAckReply,
} from "./lib/librarySyncPolicy";

async function owner(ctx: MutationCtx): Promise<Doc<"users">> {
  const identity = await requireIdentity(ctx);
  const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
  if (!user) throw new Error("SYNC_ACCOUNT_MISSING");
  return user;
}

export const openBinding = mutation({
  args: {},
  handler: async (ctx): Promise<SyncBinding> => {
    const user = await owner(ctx), now = Date.now();
    const bindings = await ctx.db.query("librarySyncBindings").withIndex("by_user", q => q.eq("userId", user._id)).take(SYNC_BINDING_LIMIT + 1);
    let live = 0;
    for (const binding of bindings) {
      if (binding.expiresAt <= now) await ctx.db.delete(binding._id);
      else live++;
    }
    if (live >= SYNC_BINDING_LIMIT) throw new Error("SYNC_BINDING_LIMIT");
    const capability = `${crypto.randomUUID()}.${crypto.randomUUID()}`;
    const validUntil = now + SYNC_BINDING_LIFETIME;
    await ctx.db.insert("librarySyncBindings", { userId: user._id, digest: await textDigest(capability), expiresAt: validUntil, createdAt: now });
    return { ownerKey: user._id, subject: user.clerkId, capability, validUntil };
  },
});

async function folder(ctx: MutationCtx, userId: Id<"users">, reference: SyncFolderReference) {
  if (reference.kind === "none") return null;
  const id = reference.kind === "server" ? ctx.db.normalizeId("savedFolders", reference.id)
    : (await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", reference.key)).unique())?.folderId;
  const row = id ? await ctx.db.get(id) : null;
  return row?.userId === userId ? row : null;
}
async function folderAlias(ctx: MutationCtx, userId: Id<"users">, key: string, folderId: Id<"savedFolders">) {
  const existing = await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", key)).unique();
  if (!existing) await ctx.db.insert("librarySyncFolderKeys", { userId, key, folderId });
  else if (existing.folderId !== folderId) throw new Error("SYNC_FOLDER_KEY_REUSED");
}
async function removeEmpty(ctx: MutationCtx, item: Doc<"savedItems">) {
  if (item.bookmarkCreatedAt === undefined && item.favoriteCreatedAt === undefined && item.noteContent === undefined) await ctx.db.delete(item._id);
}
function superseded(reason: "newer_cloud" | "tie_cloud" | "changed_since_delete"): SyncOutcome { return { kind: "superseded", reason }; }
function unresolved(reason: "missing_target" | "missing_folder" | "missing_saved_item" | "folder_name_taken" | "position_unavailable" | "folder_too_large"): SyncOutcome { return { kind: "unresolved", reason }; }
type Applied = { outcome: SyncOutcome };

async function applyOperation(ctx: MutationCtx, userId: Id<"users">, operation: SyncOperation): Promise<Applied> {
  const command = operation.command;
  if (command.kind === "folder_create") {
    const previous = await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", command.key)).unique();
    if (previous) {
      const row = await ctx.db.get(previous.folderId);
      return { outcome: row?.userId === userId ? { kind: "folder", folderId: row._id } : superseded("changed_since_delete") };
    }
    const name = normalizedFolderName(command.name);
    const existing = await ctx.db.query("savedFolders").withIndex("by_user_normalized_name", q => q.eq("userId", userId).eq("normalizedName", name.normalizedName)).unique();
    if (existing && command.purpose === "create") return { outcome: unresolved("folder_name_taken") };
    const folderId = existing?._id ?? await ctx.db.insert("savedFolders", { userId, ...name, createdAt: operation.at, updatedAt: operation.at });
    await folderAlias(ctx, userId, command.key, folderId);
    await stamp(ctx, userId, `folder:${folderId}`, operation);
    return { outcome: { kind: "folder", folderId } };
  }
  if (command.kind === "folder_delete") {
    const current = await folder(ctx, userId, command.folder);
    if (!current) return { outcome: unresolved("missing_folder") };
    const members = await ctx.db.query("savedItems").withIndex("by_folder", q => q.eq("folderId", current._id)).take(501);
    if (members.length > 500) return { outcome: unresolved("folder_too_large") };
    if (current.updatedAt > operation.at || members.some(member => member.userId === userId && (member.folderUpdatedAt ?? 0) > operation.at)) {
      return { outcome: superseded("newer_cloud") };
    }
    const ids: Id<"hadiths">[] = [];
    for (const member of members) {
      if (member.userId !== userId) continue;
      const at = Math.max(operation.at, member.folderUpdatedAt ?? 0);
      await ctx.db.patch(member._id, { folderId: undefined, folderUpdatedAt: at, updatedAt: Math.max(member.updatedAt, at) });
      await stamp(ctx, userId, `membership:${member.hadithId}`, operation, at);
      ids.push(member.hadithId);
    }
    await ctx.db.delete(current._id);
    await stamp(ctx, userId, `folder:${current._id}`, operation);
    return { outcome: { kind: "folder_deleted", hadithIds: ids, deletedAt: operation.at } };
  }
  if (command.kind === "folder_restore") {
    const deletionMarks = await ctx.db.query("librarySyncMarks").withIndex("by_user_operation", q => q.eq("userId", userId).eq("operationId", command.deletionId)).take(501);
    const deletion = deletionMarks.find(value => value.key.startsWith("folder:") && value.commandKind === "folder_delete");
    if (!deletion) return { outcome: unresolved("missing_folder") };
    if (operation.at < deletion.at) return { outcome: superseded("newer_cloud") };
    const name = normalizedFolderName(command.name);
    const existing = await ctx.db.query("savedFolders").withIndex("by_user_normalized_name", q => q.eq("userId", userId).eq("normalizedName", name.normalizedName)).unique();
    const folderId = existing?._id ?? await ctx.db.insert("savedFolders", { userId, ...name, createdAt: operation.at, updatedAt: operation.at });

    const restored: string[] = [], supersededIds: string[] = [], missing: string[] = [];
    for (const raw of command.hadithIds) {
      const hadithId = ctx.db.normalizeId("hadiths", raw);
      if (!hadithId) { missing.push(raw); continue; }
      const item = await ctx.db.query("savedItems").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).unique();
      const version = await mark(ctx, userId, `membership:${hadithId}`);
      if (!item) { missing.push(raw); continue; }
      if (item.folderId !== undefined || version?.operationId !== command.deletionId || version.commandKind !== "folder_delete" || (item.folderUpdatedAt ?? 0) > version.at || operation.at < version.at) { supersededIds.push(raw); continue; }
      await ctx.db.patch(item._id, { folderId, folderUpdatedAt: operation.at, updatedAt: Math.max(item.updatedAt, operation.at) });
      await stamp(ctx, userId, `membership:${hadithId}`, operation);
      restored.push(raw);
    }
    return { outcome: { kind: "folder_restored", folderId, restored, superseded: supersededIds, missing } };
  }
  if (command.kind === "legacy_position_put") {
    const id = ctx.db.normalizeId("hadiths", command.hadithId);
    const hadith = id ? await ctx.db.get(id) : null;
    if (!hadith) return { outcome: unresolved("position_unavailable") };
    const position = legacyReadingPosition({ provider: hadith.provider, collectionSlug: hadith.collectionSlug,
      providerHadithId: hadith.providerHadithId, volumeId: hadith.volumeId ?? hadith.bookId ?? "unknown", updatedAt: command.updatedAt });
    const applied = await applyOperation(ctx, userId, { ...operation, command: { kind: "position_put", position } });
    return { ...applied, outcome: applied.outcome.kind === "preserved" ? { kind: "resolved_position", position } : applied.outcome };
  }
  if (command.kind === "position_put") {
    const position = command.position;
    const exact = await ctx.db.query("hadiths").withIndex("by_provider_ref", q => q.eq("provider", position.anchor.provider).eq("collectionSlug", position.anchor.collectionSlug).eq("providerHadithId", position.anchor.providerHadithId)).unique();
    if (!exact) return { outcome: unresolved("position_unavailable") };
    const current = await ctx.db.query("readingProgress").withIndex("by_user_collection", q => q.eq("userId", userId).eq("collectionSlug", position.anchor.collectionSlug)).unique();
    const currentPosition = current?.position;
    const same = currentPosition !== undefined && currentPosition.anchor.provider === position.anchor.provider && currentPosition.anchor.collectionSlug === position.anchor.collectionSlug && currentPosition.anchor.providerHadithId === position.anchor.providerHadithId && currentPosition.normalizedOffset === position.normalizedOffset;
    const key = `position:${position.anchor.collectionSlug}`;
    const previous = await mark(ctx, userId, key);
    const cloudAt = Math.max(current?.updatedAt ?? -Infinity, previous?.at ?? -Infinity);
    const decision = syncWriteDecision({ at: position.updatedAt, cloudAt: Number.isFinite(cloudAt) ? cloudAt : null, same });
    if (decision === "newer_cloud" || decision === "tie_cloud") return { outcome: superseded(decision) };
    await applyReadingPosition(ctx, userId, position, exact._id);
    await stamp(ctx, userId, key, operation, position.updatedAt);
    return { outcome: { kind: "preserved" } };
  }
  const hadithId = ctx.db.normalizeId("hadiths", command.hadithId);
  const hadith = hadithId ? await ctx.db.get(hadithId) : null;
  if (!hadith || !hadithId) return { outcome: unresolved("missing_target") };
  const item = await materializeLegacySavedItem(ctx, userId, hadithId);
  if (command.kind === "membership_put") {
    const key = `membership:${hadithId}`;
    if (item.bookmarkCreatedAt === undefined && item.favoriteCreatedAt === undefined && item.noteContent === undefined) {
      await removeEmpty(ctx, item);
      return { outcome: unresolved("missing_saved_item") };
    }
    const destination = command.folder.kind === "none" ? null : await folder(ctx, userId, command.folder);
    if (command.folder.kind !== "none" && !destination) return { outcome: unresolved("missing_folder") };
    const previous = await mark(ctx, userId, key);
    const cloudAt = Math.max(item.folderUpdatedAt ?? -Infinity, previous?.at ?? -Infinity);
    const decision = syncWriteDecision({ at: operation.at, cloudAt: Number.isFinite(cloudAt) ? cloudAt : null, same: item.folderId === destination?._id });
    if (decision === "newer_cloud" || decision === "tie_cloud") return { outcome: superseded(decision) };
    await ctx.db.patch(item._id, { folderId: destination?._id, folderUpdatedAt: Math.max(operation.at, cloudAt), updatedAt: Math.max(item.updatedAt, operation.at) });
    await stamp(ctx, userId, key, operation);
    return { outcome: { kind: "preserved" } };
  }
  if (command.kind === "facet_restore") {
    const key = `${command.value.kind}:${hadithId}`;
    const currentPresent = command.value.kind === "note" ? item.noteContent !== undefined
      : command.value.kind === "bookmark" ? item.bookmarkCreatedAt !== undefined : item.favoriteCreatedAt !== undefined;
    if (currentPresent) {
      const same = command.value.kind !== "note" || item.noteContent === command.value.content;
      return { outcome: same ? { kind: "preserved" } : superseded("changed_since_delete") };
    }
    const previous = await mark(ctx, userId, key);
    if (previous?.operationId !== command.deletionId || previous.commandKind !== `${command.value.kind}_remove`) return { outcome: superseded("changed_since_delete") };
    const restored: SyncOperation = { ...operation, command: command.value.kind === "note"
      ? { kind: "note_put", hadithId, content: command.value.content, createdAt: command.value.createdAt, updatedAt: operation.at }
      : command.value.kind === "bookmark" ? { kind: "bookmark_add", hadithId, createdAt: command.value.createdAt }
        : { kind: "favorite_add", hadithId, createdAt: command.value.createdAt } };
    return applyOperation(ctx, userId, restored);
  }
  const facet = command.kind.startsWith("bookmark") ? "bookmark" : command.kind.startsWith("favorite") ? "favorite" : "note";
  const key = `${facet}:${hadithId}`;
  const previous = await mark(ctx, userId, key);
  const currentAt = facet === "note" ? item.noteUpdatedAt : facet === "bookmark" ? item.bookmarkCreatedAt : item.favoriteCreatedAt;
  const cloudAt = Math.max(currentAt ?? -Infinity, previous?.at ?? -Infinity);
  const present = command.kind === "bookmark_add" || command.kind === "favorite_add" || command.kind === "note_put";
  const same = facet === "note" ? command.kind === "note_put" ? item.noteContent === command.content : item.noteContent === undefined
    : (facet === "bookmark" ? item.bookmarkCreatedAt !== undefined : item.favoriteCreatedAt !== undefined) === present;
  const at = command.kind === "note_put" ? command.updatedAt : operation.at;
  const decision = syncWriteDecision({ at, cloudAt: Number.isFinite(cloudAt) ? cloudAt : null, same });
  if (decision === "newer_cloud" || decision === "tie_cloud") return { outcome: superseded(decision) };
  let next = item;
  const updatedAt = Math.max(item.updatedAt, at);
  if (command.kind === "bookmark_add" || command.kind === "bookmark_remove") {
    const createdAt = command.kind === "bookmark_add" ? Math.min(item.bookmarkCreatedAt ?? command.createdAt, command.createdAt) : undefined;
    await ctx.db.patch(item._id, { bookmarkCreatedAt: createdAt, updatedAt });
    const legacy = await ctx.db.query("bookmarks").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).collect();
    if (command.kind === "bookmark_remove") for (const row of legacy) await ctx.db.delete(row._id);
    else if (legacy.length === 0) await ctx.db.insert("bookmarks", { userId, hadithId, createdAt: command.createdAt });
    next = { ...item, bookmarkCreatedAt: createdAt, updatedAt };
  } else if (command.kind === "favorite_add" || command.kind === "favorite_remove") {
    const createdAt = command.kind === "favorite_add" ? Math.min(item.favoriteCreatedAt ?? command.createdAt, command.createdAt) : undefined;
    await ctx.db.patch(item._id, { favoriteCreatedAt: createdAt, updatedAt });
    const legacy = await ctx.db.query("favorites").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).collect();
    if (command.kind === "favorite_remove") for (const row of legacy) await ctx.db.delete(row._id);
    else if (legacy.length === 0) await ctx.db.insert("favorites", { userId, hadithId, createdAt: command.createdAt });
    next = { ...item, favoriteCreatedAt: createdAt, updatedAt };
  } else if (command.kind === "note_put" || command.kind === "note_remove") {
    const legacy = await ctx.db.query("notes").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).unique();
    if (command.kind === "note_remove") {
      await ctx.db.patch(item._id, { noteContent: undefined, noteCreatedAt: undefined, noteUpdatedAt: undefined, updatedAt });
      if (legacy) await ctx.db.delete(legacy._id);
      next = { ...item, noteContent: undefined, noteCreatedAt: undefined, noteUpdatedAt: undefined, updatedAt };
    } else if (!same || at > (item.noteUpdatedAt ?? -Infinity)) {
      const createdAt = item.noteCreatedAt ?? command.createdAt;
      await ctx.db.patch(item._id, { noteContent: command.content, noteCreatedAt: createdAt, noteUpdatedAt: at, updatedAt });
      if (legacy) await ctx.db.patch(legacy._id, { content: command.content, updatedAt: at });
      else await ctx.db.insert("notes", { userId, hadithId, content: command.content, createdAt, updatedAt: at });
      next = { ...item, noteContent: command.content, noteCreatedAt: createdAt, noteUpdatedAt: at, updatedAt };
    }
  } else { const exhaustive: never = command; return exhaustive; }
  await stamp(ctx, userId, key, operation, at);
  await removeEmpty(ctx, next);
  return { outcome: { kind: "preserved" } };
}

async function boundOwner(ctx: MutationCtx, capability: string) {
  const user = await owner(ctx);
  const digest = await textDigest(capability);
  const binding = await ctx.db.query("librarySyncBindings").withIndex("by_digest", q => q.eq("digest", digest)).unique();
  if (!binding || binding.userId !== user._id) throw new Error("SYNC_OWNER_MISMATCH");
  if (binding.expiresAt <= Date.now()) throw new Error("SYNC_BINDING_EXPIRED");
  return user;
}

export const applyBatch = mutation({
  args: { capability: v.string(), frame: syncFrame },
  handler: async (ctx, { capability, frame }): Promise<SyncExchange> => {
    const user = await boundOwner(ctx, capability);
    validateSyncStream(frame.clientKey, frame.sequence);
    validateSyncBatch(frame.batch, Date.now());
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", frame.clientKey)).unique();
    const closedThrough = stream?.closedThrough ?? 0;
    const digest = await syncBatchDigest(frame.batch);
    const active = stream?.active;
    if (frame.sequence !== closedThrough + 1 || active && (active.sequence !== frame.sequence || active.reply.batchId !== frame.batch.id || active.digest !== digest)) {
      return { kind: "reconcile", ownerKey: user._id, clientKey: frame.clientKey, requestedSequence: frame.sequence, requestedBatchId: frame.batch.id,
        cursor: { closedThrough, ...(active ? { active } : {}) } };
    }
    if (active) {
      if (!syncReceiptSetMatches(frame.batch, active.reply.receipts)) throw new Error("SYNC_INVALID_RECEIPT");
      return { kind: "accepted", committed: active };
    }
    const receipts: SyncReceipt[] = [];
    for (const operation of frame.batch.operations) {
      const result = await applyOperation(ctx, user._id, operation);
      receipts.push({ id: operation.id, revision: operation.revision, outcome: result.outcome });
    }
    const committed = { clientKey: frame.clientKey, sequence: frame.sequence, digest,
      reply: { ownerKey: user._id, batchId: frame.batch.id, receipts } };
    if (stream) await ctx.db.patch(stream._id, { active: committed });
    else await ctx.db.insert("librarySyncStreams", { userId: user._id, clientKey: frame.clientKey, closedThrough: 0, active: committed });
    return { kind: "accepted", committed };
  },
});

export const acknowledge = mutation({
  args: { capability: v.string(), acknowledgement: syncAcknowledgement },
  handler: async (ctx, { capability, acknowledgement }): Promise<SyncAckReply> => {
    const user = await boundOwner(ctx, capability);
    validateSyncStream(acknowledgement.clientKey, acknowledgement.sequence);
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", acknowledgement.clientKey)).unique();
    if (!stream) return { ownerKey: user._id, clientKey: acknowledgement.clientKey, cursor: { closedThrough: 0 } };
    const active = stream.active;
    if (active && active.sequence === acknowledgement.sequence && active.reply.batchId === acknowledgement.batchId && active.digest === acknowledgement.digest) {
      await ctx.db.patch(stream._id, { closedThrough: active.sequence, active: undefined });
      return { ownerKey: user._id, clientKey: acknowledgement.clientKey, cursor: { closedThrough: active.sequence } };
    }
    return { ownerKey: user._id, clientKey: acknowledgement.clientKey, cursor: { closedThrough: stream.closedThrough, ...(active ? { active } : {}) } };
  },
});
