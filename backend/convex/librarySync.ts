import { writeSavedMembership, removeEmptySavedMembership, touchSavedFolderMemberships, savedFolderScanGuard } from "./lib/savedMembership";
import { advanceFolderManifest as advanceManifest, purgeFolderManifestMembers as purgeManifest,
  FOLDER_MANIFEST_LEASE_MS, type FolderManifestStep } from "./lib/savedFolderManifests";
import { internal } from "./_generated/api";
import { existingFrameExchange, librarySyncCursor } from "./lib/librarySyncFrames";
import { requireLibraryUser as owner, requireLibraryBinding as boundOwner } from "./lib/librarySyncIdentity";
import { libraryVersion, advanceLibraryVersion } from "./lib/librarySyncVersions";
import { librarySyncMark as mark, stampLibrarySyncMark as stamp } from "./lib/librarySyncMarks";
import { v } from "convex/values";
import { internalMutation, mutation, query, type MutationCtx, type QueryCtx } from "./_generated/server";
import type { Doc, Id } from "./_generated/dataModel";
import { materializeLegacySavedItem, applyReadingPosition, readSavedSnapshot, readReadingProgressDetailed } from "./library";
import { normalizedFolderName } from "./lib/savedFolderPolicy";
import { legacyReadingPosition } from "./lib/readingPositions";
import { textDigest } from "./lib/evidenceReviewPolicy";
import {
  syncBatchDigest, syncWriteDecision, validateSyncBatch,
  SYNC_BINDING_LIMIT, SYNC_BINDING_LIFETIME,
  syncFrame, syncPending, syncAcknowledgement, validateSyncStream, syncSavedSnapshot, syncPositionsSnapshot,
  type SyncHadithSummary, type SyncSavedSnapshot, type SyncPositionsSnapshot,
  type SyncBinding, type SyncOperation, type SyncOutcome, type SyncReceipt, type SyncFolderReference, type SyncExchange, type SyncAckReply,
} from "./lib/librarySyncPolicy";

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
function superseded(reason: Extract<SyncOutcome, { kind: "superseded" }>["reason"]): SyncOutcome { return { kind: "superseded", reason }; }
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
    const members = await ctx.db.query("savedItems").withIndex("by_user_folder_updated", q => q.eq("userId", userId).eq("folderId", current._id)).take(501);
    if (members.length > 500) return { outcome: unresolved("folder_too_large") };
    const guard = await savedFolderScanGuard(ctx, current);
    if (current.updatedAt > operation.at || (guard.latestAt ?? 0) > operation.at) {
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
    await stamp(ctx, userId, `folder:${current._id}`, operation, operation.at, { kind: "folder_deletion", hadithIds: ids });
    return { outcome: { kind: "folder_deleted", hadithIds: ids, deletedAt: operation.at } };
  }
  if (command.kind === "folder_restore") {
    const deletionMarks = await ctx.db.query("librarySyncMarks").withIndex("by_user_operation", q => q.eq("userId", userId).eq("operationId", command.deletionId)).take(501);
    const deletion = deletionMarks.find(value => value.key.startsWith("folder:") && value.commandKind === "folder_delete");
    if (!deletion || deletion.detail.kind !== "folder_deletion") return { outcome: unresolved("missing_folder") };
    if (operation.at < deletion.at) return { outcome: superseded("newer_cloud") };
    const name = normalizedFolderName(command.name);
    const alias = await ctx.db.query("librarySyncFolderKeys").withIndex("by_user_key", q => q.eq("userId", userId).eq("key", `restore:${command.deletionId}`)).unique();
    const previous = alias ? await ctx.db.get(alias.folderId) : null;
    if (alias && previous?.userId !== userId) return { outcome: superseded("changed_since_delete") };
    const existing = previous ?? await ctx.db.query("savedFolders").withIndex("by_user_normalized_name", q => q.eq("userId", userId).eq("normalizedName", name.normalizedName)).unique();
    const folderId = existing?._id ?? await ctx.db.insert("savedFolders", { userId, ...name, createdAt: operation.at, updatedAt: operation.at });
    await folderAlias(ctx, userId, `restore:${command.deletionId}`, folderId);

    const restored: string[] = [], supersededIds: string[] = [], missing: string[] = [];
    const removed = new Set(deletion.detail.hadithIds);
    for (const raw of new Set([...deletion.detail.hadithIds, ...command.hadithIds])) {
      const hadithId = ctx.db.normalizeId("hadiths", raw);
      if (!hadithId || !removed.has(hadithId)) { missing.push(raw); continue; }
      const item = await ctx.db.query("savedItems").withIndex("by_user_hadith", q => q.eq("userId", userId).eq("hadithId", hadithId)).unique();
      const version = await mark(ctx, userId, `membership:${hadithId}`);
      if (!item) { missing.push(raw); continue; }
      if (item.folderId !== undefined || version?.operationId !== command.deletionId || version.commandKind !== "folder_delete" || (item.folderUpdatedAt ?? 0) > version.at || operation.at < version.at) { supersededIds.push(raw); continue; }
      await ctx.db.patch(item._id, { folderId, folderUpdatedAt: operation.at, updatedAt: Math.max(item.updatedAt, operation.at) });
      await stamp(ctx, userId, `membership:${hadithId}`, operation);
      await touchSavedFolderMemberships(ctx, userId, [folderId]);
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
    if (item.bookmarkCreatedAt === undefined && item.favoriteCreatedAt === undefined && item.noteContent === undefined) {
      await removeEmptySavedMembership(ctx, item);
      return { outcome: unresolved("missing_saved_item") };
    }
    const destination = command.folder.kind === "none" ? null : await folder(ctx, userId, command.folder);
    if (command.folder.kind !== "none" && !destination) return { outcome: unresolved("missing_folder") };
    const decision = command.mode === "claim_if_unset" && destination
      ? await writeSavedMembership(ctx, item, { kind: "claim_if_unset", folder: destination })
      : await writeSavedMembership(ctx, item, { kind: "dated", folder: destination, at: operation.at, operation: { id: operation.id, kind: "membership_put" } });
    if (decision.kind === "newer_cloud" || decision.kind === "tie_cloud" || decision.kind === "unversioned_cloud") return { outcome: superseded(decision.kind) };
    if (decision.kind === "missing_folder") return { outcome: unresolved("missing_folder") };
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
    if (previous?.operationId !== command.deletionId || previous.commandKind !== `${command.value.kind}_remove`) {
      await removeEmptySavedMembership(ctx, item);
      return { outcome: superseded("changed_since_delete") };
    }
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
  if (decision === "newer_cloud" || decision === "tie_cloud") {
    await removeEmptySavedMembership(ctx, item);
    return { outcome: superseded(decision) };
  }
  if (!present && same) {
    await removeEmptySavedMembership(ctx, item);
    return { outcome: { kind: "preserved" } };
  }
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
  await removeEmptySavedMembership(ctx, next);
  return { outcome: { kind: "preserved" } };
}

export const applyBatch = mutation({
  args: { capability: v.string(), frame: syncFrame },
  handler: async (ctx, { capability, frame }): Promise<SyncExchange> => {
    const user = await boundOwner(ctx, capability);
    validateSyncStream(frame.clientKey, frame.sequence);
    validateSyncBatch(frame.batch, Date.now());
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", frame.clientKey)).unique();
    const digest = await syncBatchDigest(frame.batch);
    const existing = existingFrameExchange(user._id, frame, digest, stream);
    if (existing) return existing;
    const receipts: SyncReceipt[] = [];
    for (const operation of frame.batch.operations) {
      const result = await applyOperation(ctx, user._id, operation);
      receipts.push({ id: operation.id, revision: operation.revision, outcome: result.outcome });
    }
    const saved = frame.batch.operations.some(value => value.command.kind !== "position_put" && value.command.kind !== "legacy_position_put");
    const revision = { saved: saved ? await advanceLibraryVersion(ctx, user._id, "saved") : await libraryVersion(ctx, user._id, "saved"), position: await libraryVersion(ctx, user._id, "position") };
    const committed = { clientKey: frame.clientKey, sequence: frame.sequence, digest, revision,
      reply: { ownerKey: user._id, batchId: frame.batch.id, receipts } };
    if (stream) await ctx.db.patch(stream._id, { slot: { kind: "committed", committed } });
    else await ctx.db.insert("librarySyncStreams", { userId: user._id, clientKey: frame.clientKey, closedThrough: 0, slot: { kind: "committed", committed } });
    return { kind: "accepted", committed };
  },
});

export const pollPending = query({
  args: { capability: v.string(), pending: syncPending },
  handler: async (ctx, { capability, pending }): Promise<SyncExchange> => {
    const user = await boundOwner(ctx, capability);
    validateSyncStream(pending.clientKey, pending.sequence);
    if (!/^[A-Za-z0-9][A-Za-z0-9_.:-]{0,127}$/.test(pending.batchId) || !pending.digest || pending.digest.length > 128) throw new Error("SYNC_INVALID_PENDING");
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", pending.clientKey)).unique();
    const slot = stream?.slot;
    if (slot?.kind === "pending" && slot.pending.sequence === pending.sequence && slot.pending.batchId === pending.batchId && slot.pending.digest === pending.digest
      && slot.pending.intentDigest === pending.intentDigest && slot.pending.manifestId === pending.manifestId && slot.pending.generation === pending.generation) return { kind: "pending", ownerKey: user._id, pending: slot.pending };
    if (slot?.kind === "committed" && slot.committed.sequence === pending.sequence && slot.committed.reply.batchId === pending.batchId && slot.committed.digest === pending.digest) return { kind: "accepted", committed: slot.committed };
    return { kind: "reconcile", ownerKey: user._id, clientKey: pending.clientKey, requestedSequence: pending.sequence, requestedBatchId: pending.batchId, cursor: librarySyncCursor(stream) };
  },
});

const FUTURE_RETIREMENT_LIMIT = 100;

async function consumeRetirements(ctx: MutationCtx, userId: Id<"users">, clientKey: string, closedThrough: number): Promise<number> {
  for (let inspected = 0; inspected < FUTURE_RETIREMENT_LIMIT; inspected++) {
    const next = await ctx.db.query("librarySyncRetirements").withIndex("by_user_client_sequence", q => q.eq("userId", userId).eq("clientKey", clientKey).eq("sequence", closedThrough + 1)).unique();
    if (!next) break;
    await ctx.db.delete(next._id);
    closedThrough++;
  }
  return closedThrough;
}

/** Fences one unsendable sequence, without skipping valid earlier work from a restored copy. */
export const retireInvalidFrame = mutation({
  args: { capability: v.string(), clientKey: v.string(), sequence: v.number() },
  handler: async (ctx, { capability, clientKey, sequence }): Promise<SyncAckReply> => {
    const user = await boundOwner(ctx, capability);
    validateSyncStream(clientKey, sequence);
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", clientKey)).unique();
    const closedThrough = stream?.closedThrough ?? 0;
    const cursor = librarySyncCursor(stream), slot = stream?.slot;
    const outstandingSequence = slot?.kind === "pending" ? slot.pending.sequence : slot?.committed.sequence;
    if (sequence <= closedThrough || outstandingSequence === sequence) return { ownerKey: user._id, clientKey, cursor };
    if (!slot && sequence === closedThrough + 1) {
      const closed = await consumeRetirements(ctx, user._id, clientKey, sequence);
      if (stream) await ctx.db.patch(stream._id, { closedThrough: closed });
      else await ctx.db.insert("librarySyncStreams", { userId: user._id, clientKey, closedThrough: closed });
      return { ownerKey: user._id, clientKey, cursor: { closedThrough: closed } };
    }
    const existing = await ctx.db.query("librarySyncRetirements").withIndex("by_user_client_sequence", q => q.eq("userId", user._id).eq("clientKey", clientKey).eq("sequence", sequence)).unique();
    if (!existing) {
      const pending = await ctx.db.query("librarySyncRetirements").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", clientKey)).take(FUTURE_RETIREMENT_LIMIT);
      if (pending.length >= FUTURE_RETIREMENT_LIMIT) throw new Error("SYNC_RETIREMENT_CAPACITY");
      await ctx.db.insert("librarySyncRetirements", { userId: user._id, clientKey, sequence });
    }
    if (!stream) await ctx.db.insert("librarySyncStreams", { userId: user._id, clientKey, closedThrough });
    return { ownerKey: user._id, clientKey, cursor };
  },
});

export const acknowledge = mutation({
  args: { capability: v.string(), acknowledgement: syncAcknowledgement },
  handler: async (ctx, { capability, acknowledgement }): Promise<SyncAckReply> => {
    const user = await boundOwner(ctx, capability);
    validateSyncStream(acknowledgement.clientKey, acknowledgement.sequence);
    const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", user._id).eq("clientKey", acknowledgement.clientKey)).unique();
    if (!stream) return { ownerKey: user._id, clientKey: acknowledgement.clientKey, cursor: { closedThrough: 0 } };
    const active = stream.slot?.kind === "committed" ? stream.slot.committed : undefined;
    if (active && active.sequence === acknowledgement.sequence && active.reply.batchId === acknowledgement.batchId && active.digest === acknowledgement.digest) {
      const closedThrough = await consumeRetirements(ctx, user._id, acknowledgement.clientKey, active.sequence);
      await ctx.db.patch(stream._id, { closedThrough, slot: undefined });
      return { ownerKey: user._id, clientKey: acknowledgement.clientKey, cursor: { closedThrough } };
    }
    return { ownerKey: user._id, clientKey: acknowledgement.clientKey, cursor: librarySyncCursor(stream) };
  },
});

function cleanSummary(value: { _id: string; providerHadithId: string; collectionSlug: string; collectionName: string; volumeId: string | null; arabicText: string; englishText: string | null; referenceDisplay: string }): SyncHadithSummary {
  return { _id: value._id, providerHadithId: value.providerHadithId, collectionSlug: value.collectionSlug, collectionName: value.collectionName,
    ...(value.volumeId === null ? {} : { volumeId: value.volumeId }), arabicText: value.arabicText,
    ...(value.englishText === null ? {} : { englishText: value.englishText }), referenceDisplay: value.referenceDisplay };
}
export const savedSnapshot = query({
  args: {}, returns: syncSavedSnapshot,
  handler: async (ctx): Promise<SyncSavedSnapshot> => {
    const user = await owner(ctx), data = await readSavedSnapshot(ctx, user._id);
    const version = await libraryVersion(ctx, user._id, "saved");
    return { ownerKey: user._id, version, folders: data.folders, items: data.items.flatMap(item => item.hadith ? [{
      hadithId: item.hadithId, createdAt: item.createdAt, updatedAt: item.updatedAt,
      ...(item.bookmarkCreatedAt === undefined ? {} : { bookmarkCreatedAt: item.bookmarkCreatedAt }),
      ...(item.favoriteCreatedAt === undefined ? {} : { favoriteCreatedAt: item.favoriteCreatedAt }),
      ...(item.noteContent === undefined ? {} : { noteContent: item.noteContent }),
      ...(item.noteCreatedAt === undefined ? {} : { noteCreatedAt: item.noteCreatedAt }),
      ...(item.noteUpdatedAt === undefined ? {} : { noteUpdatedAt: item.noteUpdatedAt }),
      ...(item.folderId === undefined ? {} : { folderId: item.folderId }), hadith: cleanSummary(item.hadith),
    }] : []) };
  },
});
export const positionsSnapshot = query({
  args: {}, returns: syncPositionsSnapshot,
  handler: async (ctx): Promise<SyncPositionsSnapshot> => {
    const user = await owner(ctx), rows = await readReadingProgressDetailed(ctx, user._id);
    const version = await libraryVersion(ctx, user._id, "position");
    return { ownerKey: user._id, version, rows: rows.flatMap(row => row.hadith ? [{ collectionSlug: row.collectionSlug, hadithId: row.hadithId,
      updatedAt: row.updatedAt, ...(row.position === undefined ? {} : { position: row.position }), hadith: cleanSummary(row.hadith) }] : []) };
  },
});

export const advanceFolderManifest = internalMutation({
  args: { id: v.id("savedFolderManifests"), generation: v.string(), step: v.number() },
  handler: async (ctx, request): Promise<FolderManifestStep> => advanceManifest(ctx, request),
});

export const purgeFolderManifestMembers = internalMutation({
  args: { id: v.id("savedFolderManifests"), generation: v.string() },
  handler: async (ctx, request): Promise<{ deleted: number }> => purgeManifest(ctx, request),
});

export const recoverFolderManifests = internalMutation({
  args: {},
  handler: async (ctx): Promise<{ scheduled: number }> => {
    const now = Date.now();
    const rows = await ctx.db.query("savedFolderManifests").withIndex("by_state_updated", q => q.eq("state.kind", "scanning").lte("updatedAt", now - 5 * 60_000)).take(25);
    for (const header of rows) {
      if (header.state.kind !== "scanning") continue;
      await ctx.scheduler.runAfter(0, internal.librarySync.advanceFolderManifest, { id: header._id, generation: header.generation, step: header.state.step });
      // Dispatch does not renew the inactivity lease. Only committed progress can.
      await ctx.db.patch(header._id, { updatedAt: now });
    }
    if (rows.length === 25) await ctx.scheduler.runAfter(0, internal.librarySync.recoverFolderManifests, {});
    return { scheduled: rows.length };
  },
});

export const pruneFolderManifests = internalMutation({
  args: { cutoff: v.optional(v.number()) },
  handler: async (ctx, request): Promise<{ scheduled: number }> => {
    const cutoff = request.cutoff ?? Date.now();
    const rows = await ctx.db.query("savedFolderManifests").withIndex("by_expiry", q => q.lte("expiresAt", cutoff)).take(25);
    for (const header of rows) {
      const reason = header.state.kind === "abandoned" || header.state.kind === "purging" ? header.state.reason : "expired";
      await ctx.db.patch(header._id, { state: { kind: "purging", reason, count: header.state.count }, expiresAt: Date.now() + FOLDER_MANIFEST_LEASE_MS });
      await ctx.scheduler.runAfter(0, internal.librarySync.purgeFolderManifestMembers, { id: header._id, generation: header.generation });
    }
    if (rows.length === 25) await ctx.scheduler.runAfter(0, internal.librarySync.pruneFolderManifests, { cutoff });
    return { scheduled: rows.length };
  },
});

/** Erasure keeps discoverable headers until their facts are gone. Never touches a live owner. */
export const eraseFolderManifestOwner = internalMutation({
  args: { userId: v.id("users") },
  handler: async (ctx, { userId }): Promise<{ deleted: number }> => {
    if (await ctx.db.get(userId)) return { deleted: 0 };
    const facts = await ctx.db.query("savedFolderManifestMembers").withIndex("by_user", q => q.eq("userId", userId)).take(50);
    for (const fact of facts) await ctx.db.delete(fact._id);
    let deleted = facts.length;
    if (facts.length < 50) {
      const headers = await ctx.db.query("savedFolderManifests").withIndex("by_user", q => q.eq("userId", userId)).take(25);
      for (const header of headers) await ctx.db.delete(header._id);
      deleted += headers.length;
      if (headers.length < 25) return { deleted };
    }
    await ctx.scheduler.runAfter(0, internal.librarySync.eraseFolderManifestOwner, { userId });
    return { deleted };
  },
});
