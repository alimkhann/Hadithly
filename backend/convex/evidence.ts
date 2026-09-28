import { paginationOptsValidator } from "convex/server";
import { v } from "convex/values";
import { internalMutation, internalQuery, mutation, query } from "./_generated/server";
import type { Id } from "./_generated/dataModel";
import type { MutationCtx, QueryCtx } from "./_generated/server";
import { requireIdentity } from "./lib/identity";
import { MAX_EVIDENCE_BYTES } from "./lib/evidencePolicy";

const DAY = 24 * 60 * 60 * 1000;
export const DRAFT_EXPIRY_MS = 7 * DAY;
export const PROCESSING_EXPIRY_MS = 30 * DAY;
const fileMime = v.union(v.literal("image/jpeg"), v.literal("image/png"), v.literal("image/webp"), v.literal("application/pdf"));
const descriptor = v.union(
  v.object({ kind: v.literal("url"), clientItemKey: v.string(), url: v.string() }),
  v.object({ kind: v.literal("file"), clientItemKey: v.string(), declaredMime: fileMime, declaredSize: v.number(), declaredSha256: v.string(), displayName: v.string() }),
);

function normalizedUrl(raw: string): string {
  if (raw.length > 2048) throw new Error("Evidence URL is too long");
  let url: URL;
  try { url = new URL(raw.trim()); } catch { throw new Error("Evidence must be an HTTPS URL"); }
  if (url.protocol !== "https:" || !url.hostname || url.username || url.password) {
    throw new Error("Evidence must be an HTTPS URL without credentials");
  }
  url.hash = "";
  return url.href;
}

function displayName(raw: string): string {
  const name = raw.split(/[\\/]/).at(-1)?.trim() ?? "";
  if (!name || name.length > 100 || /[\x00-\x1f\x7f]/.test(name)) throw new Error("Invalid evidence filename");
  return name;
}

function storageHashMatches(stored: string, declaredHex: string): boolean {
  if (/^[a-f0-9]{64}$/.test(stored)) return stored === declaredHex;
  try {
    const decoded = atob(stored);
    if (decoded.length !== 32) return false;
    const hex = [...decoded].map(character => character.charCodeAt(0).toString(16).padStart(2, "0")).join("");
    return hex === declaredHex;
  } catch { return false; }
}

async function currentUser(ctx: QueryCtx | MutationCtx) {
  const identity = await requireIdentity(ctx);
  const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", identity.clerkId)).unique();
  if (!user) throw new Error("Sign in is required to submit evidence");
  return user;
}

async function ownDraft(ctx: QueryCtx | MutationCtx, submissionId: Id<"communitySubmissions">) {
  const user = await currentUser(ctx);
  const submission = await ctx.db.get(submissionId);
  if (!submission || submission.submittedBy !== user._id) throw new Error("Evidence draft not found");
  return { user, submission };
}

function snapshot(submission: { _id: Id<"communitySubmissions">; status: string; proposedContent: string; expiresAt?: number }, items: Array<{ _id: Id<"evidenceItems">; clientItemKey: string; state: string; source: { kind: string; url?: string; displayName?: string; declaredMime?: string; declaredSize?: number; size?: number } }>) {
  return {
    submissionId: submission._id,
    status: submission.status,
    proposedContent: submission.proposedContent,
    expiresAt: submission.expiresAt ?? null,
    items: items.map(item => ({ itemId: item._id, clientItemKey: item.clientItemKey, kind: item.source.kind, state: item.state, url: item.source.url ?? null, displayName: item.source.displayName ?? null, declaredMime: item.source.declaredMime ?? null, declaredSize: item.source.declaredSize ?? null, size: item.source.size ?? null })),
  };
}

export const createEvidenceDraft = mutation({
  args: {
    hadithInternalId: v.string(), language: v.string(), proposedContent: v.string(),
    replacesTranslationId: v.optional(v.id("translations")),
    legacySubmissionId: v.optional(v.id("communitySubmissions")),
    draftKey: v.string(), items: v.array(descriptor),
  },
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    const now = Date.now();
    if (!/^[A-Za-z0-9_-]{8,100}$/.test(args.draftKey)) throw new Error("Invalid draft key");
    const existing = await ctx.db.query("communitySubmissions").withIndex("by_submitter_draft_key", q => q.eq("submittedBy", user._id).eq("draftKey", args.draftKey)).unique();
    if (existing) {
      const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", existing._id)).collect();
      return snapshot(existing, items);
    }
    if (!args.legacySubmissionId) {
      const recent = await ctx.db.query("communitySubmissions")
        .withIndex("by_submitter_created", q => q.eq("submittedBy", user._id).gte("createdAt", now - DAY))
        .take(5);
      if (recent.length >= 5) throw new Error("Daily evidence submission limit reached");
    }
    if (args.items.length < 1 || args.items.length > 3) throw new Error("One to three evidence items are required");
    if (new Set(args.items.map(item => item.clientItemKey)).size !== args.items.length || args.items.some(item => !/^[A-Za-z0-9_-]{8,100}$/.test(item.clientItemKey))) throw new Error("Evidence item keys must be unique");
    const content = args.proposedContent.trim();
    if (!content || [...content].length > 10_000) throw new Error("Invalid translation length");
    const directId = ctx.db.normalizeId("hadiths", args.hadithInternalId);
    const hadith = directId
      ? await ctx.db.get(directId)
      : await ctx.db.query("hadiths")
        .withIndex("by_canonical_id", q => q.eq("canonicalId", args.hadithInternalId))
        .unique();
    if (!hadith) throw new Error("Unknown hadith");
    const hadithId = hadith._id;
    const language = args.language.trim();
    if (!/^[A-Za-z]{2,3}(?:-[A-Za-z0-9]{2,8})*$/.test(language)) throw new Error("Invalid language");
    if (args.replacesTranslationId) {
      const replacement = await ctx.db.get(args.replacesTranslationId);
      if (!replacement || replacement.hadithId !== hadithId || replacement.language !== language) throw new Error("Replacement translation does not match");
    }
    const normalized = args.items.map(item => item.kind === "url"
      ? { ...item, url: normalizedUrl(item.url) }
      : { ...item, displayName: displayName(item.displayName) });
    for (const item of normalized) {
      if (item.kind === "file" && (!Number.isInteger(item.declaredSize) || item.declaredSize < 1 || item.declaredSize > MAX_EVIDENCE_BYTES)) throw new Error("Evidence file exceeds the 10 MB limit");
      if (item.kind === "file" && !/^[a-f0-9]{64}$/.test(item.declaredSha256)) throw new Error("Invalid evidence file checksum");
    }
    const urls = normalized.filter(item => item.kind === "url").map(item => item.url);
    if (new Set(urls).size !== urls.length) throw new Error("Duplicate evidence URL");
    let submissionId: Id<"communitySubmissions">;
    if (args.legacySubmissionId) {
      const { submission } = await ownDraft(ctx, args.legacySubmissionId);
      if (submission.hadithId !== hadithId || submission.language !== language || submission.status !== "legacy_evidence_missing") throw new Error("Legacy proposal cannot be upgraded");
      submissionId = submission._id;
      await ctx.db.patch(submissionId, { proposedContent: content, status: "draft", draftKey: args.draftKey, expiresAt: now + DRAFT_EXPIRY_MS });
    } else {
      submissionId = await ctx.db.insert("communitySubmissions", { hadithId, language, submittedBy: user._id, proposedContent: content, replacesTranslationId: args.replacesTranslationId, status: "draft", draftKey: args.draftKey, expiresAt: now + DRAFT_EXPIRY_MS, createdAt: now });
    }
    const items = [];
    for (const item of normalized) {
      const source = item.kind === "url"
        ? { kind: "url" as const, url: item.url }
        : { kind: "file" as const, declaredMime: item.declaredMime, declaredSize: item.declaredSize, declaredSha256: item.declaredSha256, displayName: item.displayName };
      const state = item.kind === "url" ? "pending_safe_fetch" as const : "reserved" as const;
      const itemId = await ctx.db.insert("evidenceItems", { submissionId, ownerUserId: user._id, clientItemKey: item.clientItemKey, source, state, uploadAttempts: 0, createdAt: now, updatedAt: now });
      items.push({ _id: itemId, clientItemKey: item.clientItemKey, state, source });
    }
    return snapshot({ _id: submissionId, status: "draft", proposedContent: content, expiresAt: now + DRAFT_EXPIRY_MS }, items);
  },
});

export const getOwnEvidenceDraft = query({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    const { submission } = await ownDraft(ctx, args.submissionId);
    const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
    return snapshot(submission, items);
  },
});

export const getOwnLegacyProposal = query({
  args: { hadithInternalId: v.string(), language: v.string() },
  handler: async (ctx, args) => {
    const user = await currentUser(ctx);
    const directId = ctx.db.normalizeId("hadiths", args.hadithInternalId);
    const hadith = directId
      ? await ctx.db.get(directId)
      : await ctx.db.query("hadiths")
        .withIndex("by_canonical_id", q => q.eq("canonicalId", args.hadithInternalId))
        .unique();
    if (!hadith) return null;
    const hadithId = hadith._id;
    const rows = await ctx.db.query("communitySubmissions")
      .withIndex("by_submitted_by", q => q.eq("submittedBy", user._id)).collect();
    const row = rows.filter(item => item.hadithId === hadithId && item.language === args.language && item.status === "legacy_evidence_missing")
      .sort((a, b) => b.createdAt - a.createdAt)[0];
    return row ? { submissionId: row._id, proposedContent: row.proposedContent } : null;
  },
});

export const replaceEvidenceSlot = mutation({
  args: { submissionId: v.id("communitySubmissions"), itemId: v.id("evidenceItems"), descriptor },
  handler: async (ctx, args) => {
    const { submission } = await ownDraft(ctx, args.submissionId);
    if (submission.status !== "draft" || (submission.expiresAt ?? 0) <= Date.now()) throw new Error("Evidence draft is closed");
    const item = await ctx.db.get(args.itemId);
    if (!item || item.submissionId !== submission._id) throw new Error("Evidence item not found");
    if (item.source.kind === "file" && item.source.storageId) await ctx.storage.delete(item.source.storageId);
    const source = args.descriptor.kind === "url"
      ? { kind: "url" as const, url: normalizedUrl(args.descriptor.url) }
      : { kind: "file" as const, declaredMime: args.descriptor.declaredMime, declaredSize: args.descriptor.declaredSize, declaredSha256: args.descriptor.declaredSha256, displayName: displayName(args.descriptor.displayName) };
    if (source.kind === "file" && (!Number.isInteger(source.declaredSize) || source.declaredSize < 1 || source.declaredSize > MAX_EVIDENCE_BYTES)) throw new Error("Evidence file exceeds the 10 MB limit");
    if (source.kind === "file" && !/^[a-f0-9]{64}$/.test(source.declaredSha256)) throw new Error("Invalid evidence file checksum");
    await ctx.db.patch(item._id, { source, state: source.kind === "url" ? "pending_safe_fetch" : "reserved", updatedAt: Date.now() });
    return true;
  },
});

export const finalizeEvidenceDraft = mutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    const { submission } = await ownDraft(ctx, args.submissionId);
    if (submission.status === "awaiting_processing") return { status: "awaiting_processing" as const };
    if (submission.status !== "draft" || (submission.expiresAt ?? 0) <= Date.now()) throw new Error("Evidence draft is closed");
    const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submission._id)).collect();
    if (items.length < 1 || items.length > 3 || items.some(item => item.state !== "quarantined_unscanned" && item.state !== "pending_safe_fetch")) throw new Error("All evidence must finish uploading");
    const identities = items.map(item => item.source.kind === "url" ? `url:${item.source.url}` : `file:${item.source.sha256 ?? ""}`);
    if (new Set(identities).size !== identities.length) throw new Error("Duplicate evidence");
    await ctx.db.patch(submission._id, { status: "awaiting_processing", expiresAt: Date.now() + PROCESSING_EXPIRY_MS });
    return { status: "awaiting_processing" as const };
  },
});

export async function deleteEvidenceForSubmission(ctx: MutationCtx, submissionId: Id<"communitySubmissions">) {
  const items = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", submissionId)).collect();
  for (const item of items) {
    if (item.source.kind === "file") {
      if (item.source.storageId) await ctx.storage.delete(item.source.storageId);
      else if (item.state === "reserved") {
        await ctx.db.insert("evidenceUploadTombstones", {
          declaredMime: item.source.declaredMime,
          declaredSize: item.source.declaredSize,
          declaredSha256: item.source.declaredSha256,
          slotCreatedAt: item.createdAt,
          expiresAt: Date.now() + 3 * DAY,
        });
      }
    }
    await ctx.db.delete(item._id);
  }
}

export const deleteEvidenceDraft = mutation({
  args: { submissionId: v.id("communitySubmissions") },
  handler: async (ctx, args) => {
    const { submission } = await ownDraft(ctx, args.submissionId);
    if (submission.status !== "draft" && submission.status !== "awaiting_processing" && submission.status !== "expired") throw new Error("Evidence submission cannot be deleted here");
    await deleteEvidenceForSubmission(ctx, submission._id);
    await ctx.db.delete(submission._id);
    return true;
  },
});

export const authorizeUpload = internalQuery({
  args: { clerkId: v.string(), submissionId: v.string(), itemId: v.string() },
  handler: async (ctx, args) => {
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", args.clerkId)).unique();
    const submissionId = ctx.db.normalizeId("communitySubmissions", args.submissionId);
    const itemId = ctx.db.normalizeId("evidenceItems", args.itemId);
    if (!user || !submissionId || !itemId) throw new Error("Evidence upload not found");
    const submission = await ctx.db.get(submissionId);
    const item = await ctx.db.get(itemId);
    if (!submission || !item || submission.submittedBy !== user._id || item.submissionId !== submissionId || submission.status !== "draft" || (submission.expiresAt ?? 0) <= Date.now() || item.source.kind !== "file") throw new Error("Evidence upload not found");
    if (item.state !== "quarantined_unscanned" && item.uploadAttempts >= 5) throw new Error("Evidence upload retry limit reached");
    return { declaredMime: item.source.declaredMime, declaredSize: item.source.declaredSize, declaredSha256: item.source.declaredSha256, state: item.state };
  },
});

export const bindUpload = internalMutation({
  args: { clerkId: v.string(), submissionId: v.string(), itemId: v.string(), storageId: v.id("_storage") },
  handler: async (ctx, args) => {
    const user = await ctx.db.query("users").withIndex("by_clerk_id", q => q.eq("clerkId", args.clerkId)).unique();
    const submissionId = ctx.db.normalizeId("communitySubmissions", args.submissionId);
    const itemId = ctx.db.normalizeId("evidenceItems", args.itemId);
    if (!user || !submissionId || !itemId) throw new Error("Evidence upload not found");
    const submission = await ctx.db.get(submissionId);
    const item = await ctx.db.get(itemId);
    if (!submission || !item || submission.submittedBy !== user._id || item.submissionId !== submissionId || submission.status !== "draft" || (submission.expiresAt ?? 0) <= Date.now() || item.state !== "reserved" || item.source.kind !== "file") throw new Error("Evidence upload is no longer available");
    await ctx.db.patch(itemId, { state: "validating", source: { ...item.source, storageId: args.storageId }, uploadAttempts: item.uploadAttempts + 1, updatedAt: Date.now() });
  },
});

export const completeUpload = internalMutation({
  args: { itemId: v.string(), storageId: v.id("_storage"), verifiedMime: v.string(), sha256: v.string(), size: v.number(), width: v.optional(v.number()), height: v.optional(v.number()), pageCount: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const normalizedId = ctx.db.normalizeId("evidenceItems", args.itemId);
    if (!normalizedId) throw new Error("Evidence item not found");
    const item = await ctx.db.get(normalizedId);
    if (!item || item.state !== "validating" || item.source.kind !== "file" || item.source.storageId !== args.storageId) throw new Error("Evidence upload is no longer available");
    const siblings = await ctx.db.query("evidenceItems").withIndex("by_submission", q => q.eq("submissionId", item.submissionId)).collect();
    if (siblings.some(other => other._id !== item._id && other.source.kind === "file" && other.source.sha256 === args.sha256)) throw new Error("Duplicate evidence file");
    await ctx.db.patch(item._id, { state: "quarantined_unscanned", source: { ...item.source, verifiedMime: args.verifiedMime, sha256: args.sha256, size: args.size, width: args.width, height: args.height, pageCount: args.pageCount }, updatedAt: Date.now() });
  },
});

export const failUpload = internalMutation({
  args: { itemId: v.string(), storageId: v.id("_storage") },
  handler: async (ctx, args) => {
    const normalizedId = ctx.db.normalizeId("evidenceItems", args.itemId);
    if (!normalizedId) return;
    const item = await ctx.db.get(normalizedId);
    if (!item || item.source.kind !== "file" || item.source.storageId !== args.storageId) return;
    await ctx.storage.delete(args.storageId);
    await ctx.db.patch(item._id, { state: "invalid", source: { kind: "file", declaredMime: item.source.declaredMime, declaredSize: item.source.declaredSize, declaredSha256: item.source.declaredSha256, displayName: item.source.displayName }, updatedAt: Date.now() });
  },
});

export const expireEvidence = internalMutation({
  args: {},
  handler: async ctx => {
    let expired = 0;
    for (const status of ["draft", "awaiting_processing"] as const) {
      const rows = await ctx.db.query("communitySubmissions").withIndex("by_status_expiry", q => q.eq("status", status).lt("expiresAt", Date.now())).take(25);
      for (const row of rows) {
        await deleteEvidenceForSubmission(ctx, row._id);
        await ctx.db.patch(row._id, { status: "expired", expiresAt: undefined });
        expired += 1;
      }
    }
    return expired;
  },
});

/** Covers a crash after storage.store but before the slot records its ID. */
export const sweepStorageOrphans = internalMutation({
  args: { nowMs: v.optional(v.number()) },
  handler: async (ctx, args) => {
    const now = args.nowMs ?? Date.now();
    const state = await ctx.db.query("evidenceCleanupCursor").withIndex("by_name", q => q.eq("name", "storage_orphans")).unique();
    const page = await ctx.db.system.query("_storage").paginate({ numItems: 50, cursor: state?.cursor ?? null });
    let deleted = 0;
    for (const file of page.page) {
      if (now - file._creationTime < 2 * 60 * 60 * 1000) continue;
      const [evidenceRef, offlineRef] = await Promise.all([
        ctx.db.query("evidenceItems").withIndex("by_storage_id", q => q.eq("source.storageId", file._id)).first(),
        ctx.db.query("offlineArtifacts").withIndex("by_storage_id", q => q.eq("storageId", file._id)).first(),
      ]);
      if (evidenceRef || offlineRef) continue;
      if (file.contentType && !["image/jpeg", "image/png", "image/webp", "application/pdf"].includes(file.contentType)) continue;
      const possibleSlots = await ctx.db.query("evidenceItems")
        .withIndex("by_reserved_size", q => q.eq("state", "reserved").eq("source.declaredSize", file.size))
        .take(20);
      const belongsToEvidence = possibleSlots.some(slot => slot.source.kind === "file" &&
        (!file.contentType || slot.source.declaredMime === file.contentType) && slot.createdAt <= file._creationTime &&
        file._creationTime - slot.createdAt < DRAFT_EXPIRY_MS && storageHashMatches(file.sha256, slot.source.declaredSha256));
      const tombstones = await ctx.db.query("evidenceUploadTombstones")
        .withIndex("by_size", q => q.eq("declaredSize", file.size)).take(20);
      const belongsToDeletedEvidence = tombstones.some(row => row.expiresAt > now &&
        (!file.contentType || row.declaredMime === file.contentType) &&
        row.slotCreatedAt <= file._creationTime && file._creationTime - row.slotCreatedAt < DRAFT_EXPIRY_MS && storageHashMatches(file.sha256, row.declaredSha256));
      if (!belongsToEvidence && !belongsToDeletedEvidence) continue;
      await ctx.storage.delete(file._id);
      deleted += 1;
    }
    const oldTombstones = await ctx.db.query("evidenceUploadTombstones")
      .withIndex("by_expiry", q => q.lt("expiresAt", now)).take(25);
    for (const tombstone of oldTombstones) await ctx.db.delete(tombstone._id);
    const cursor = page.isDone ? undefined : page.continueCursor;
    if (state) await ctx.db.patch(state._id, { cursor, updatedAt: now });
    else await ctx.db.insert("evidenceCleanupCursor", { name: "storage_orphans", cursor, updatedAt: now });
    return { scanned: page.page.length, deleted, isDone: page.isDone };
  },
});

export const migrateLegacySubmissions = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const result = await ctx.db.query("communitySubmissions").paginate(args.paginationOpts);
    let migrated = 0;
    for (const row of result.page) {
      if (row.draftKey || row.legacyStatus) continue;
      await ctx.db.patch(row._id, { legacyStatus: row.status, ...(row.status === "approved" ? {} : { status: "legacy_evidence_missing" as const }) });
      migrated += 1;
    }
    return { migrated, continueCursor: result.continueCursor, isDone: result.isDone };
  },
});

export const countLiveCommunityTranslations = internalQuery({
  args: {},
  handler: async ctx => {
    const rows = await ctx.db.query("translations").withIndex("by_source_status", q => q.eq("source", "community").eq("status", "live")).collect();
    return rows.length;
  },
});

/** Flags historical public community text without changing its visibility. */
export const markLegacyCommunityTranslations = internalMutation({
  args: { paginationOpts: paginationOptsValidator },
  handler: async (ctx, args) => {
    const page = await ctx.db.query("translations").withIndex("by_source_status", q => q.eq("source", "community").eq("status", "live")).paginate(args.paginationOpts);
    let flagged = 0;
    for (const row of page.page) {
      if (row.legacyEvidenceMissing === true) continue;
      await ctx.db.patch(row._id, { legacyEvidenceMissing: true });
      flagged += 1;
    }
    return { flagged, continueCursor: page.continueCursor, isDone: page.isDone };
  },
});
