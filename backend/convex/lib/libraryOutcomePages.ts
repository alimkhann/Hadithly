import type { QueryCtx } from "../_generated/server";
import type { Id } from "../_generated/dataModel";
import { SYNC_OUTCOME_BYTES, SYNC_OUTCOME_PAGE, type SyncOutcomePage, type SyncOutcomePageRequest } from "./librarySyncPolicy";

/** A terminal receipt is the authority for this page, never a caller's member list. */
export async function readLibraryOutcomePage(ctx: QueryCtx, userId: Id<"users">, request: SyncOutcomePageRequest): Promise<SyncOutcomePage> {
  if (!Number.isSafeInteger(request.start) || request.start < 0) throw new Error("SYNC_INVALID_OUTCOME_PAGE");
  const unavailable = (reason: "proof_unavailable" | "detail_unavailable"): SyncOutcomePage => ({ kind: "unavailable", ownerKey: userId, request, reason });
  const stream = await ctx.db.query("librarySyncStreams").withIndex("by_user_client", q => q.eq("userId", userId).eq("clientKey", request.proof.clientKey)).unique();
  if (stream?.slot?.kind !== "committed") return unavailable("proof_unavailable");
  const committed = stream.slot.committed, proof = request.proof;
  if (committed.clientKey !== proof.clientKey || committed.reply.ownerKey !== userId || committed.sequence !== proof.sequence || committed.reply.batchId !== proof.batchId || committed.digest !== proof.digest) return unavailable("proof_unavailable");
  const receipt = committed.reply.receipts.find(value => value.id === request.receiptId);
  if (!receipt || request.phase === "delete" && receipt.outcome.kind !== "folder_deleted_manifest" || request.phase === "restore" && receipt.outcome.kind !== "folder_restored_manifest") return unavailable("proof_unavailable");
  const outcome = receipt.outcome;
  if (outcome.kind !== "folder_deleted_manifest" && outcome.kind !== "folder_restored_manifest") return unavailable("proof_unavailable");
  if (outcome.manifestId !== request.manifestId || outcome.generation !== request.generation) return unavailable("proof_unavailable");
  const counts = outcome.kind === "folder_deleted_manifest" ? [outcome.count] : [outcome.restored, outcome.superseded, outcome.missing];
  if (counts.some(count => !Number.isSafeInteger(count) || count < 0)) throw new Error("SYNC_OUTCOME_MANIFEST_INVARIANT");
  const total = outcome.kind === "folder_deleted_manifest" ? outcome.count : outcome.restored + outcome.superseded + outcome.missing;
  if (!Number.isSafeInteger(total)) throw new Error("SYNC_OUTCOME_MANIFEST_INVARIANT");
  if (request.start > total) throw new Error("SYNC_INVALID_OUTCOME_PAGE");
  const header = await ctx.db.get(request.manifestId);
  if (header?.userId !== userId || header.generation !== request.generation || header.expiresAt <= Date.now()) return unavailable("detail_unavailable");
  if (header.state.kind !== "deleted" && header.state.kind !== "restoring" && header.state.kind !== "restored") return unavailable("detail_unavailable");
  if (header.state.count !== total) throw new Error("SYNC_OUTCOME_MANIFEST_INVARIANT");
  if (outcome.kind === "folder_deleted_manifest") {
    if (receipt.id !== header.operationId || outcome.deletedAt !== header.requestedAt) return unavailable("proof_unavailable");
  } else {
    const state = header.state;
    if (state.kind !== "restored" || receipt.id !== state.operationId || outcome.folderId !== state.destinationId || outcome.restored !== state.restored || outcome.superseded !== state.superseded || outcome.missing !== state.missing) return unavailable("proof_unavailable");
  }
  const members = await ctx.db.query("savedFolderManifestMembers").withIndex("by_user_manifest_ordinal", q => q.eq("userId", userId).eq("manifestId", header._id).gte("ordinal", request.start)).take(SYNC_OUTCOME_PAGE);
  if (members.length !== Math.min(SYNC_OUTCOME_PAGE, total - request.start) || members.some((row, index) => row.ordinal !== request.start + index)) throw new Error("SYNC_OUTCOME_MANIFEST_INVARIANT");
  const rows = members.map(row => {
    if (request.phase === "delete") return { ordinal: row.ordinal, memberId: row._id, hadithId: row.hadithId, disposition: "deleted" } satisfies SyncOutcomePageMember;
    if (row.disposition === undefined) throw new Error("SYNC_OUTCOME_MANIFEST_INVARIANT");
    return { ordinal: row.ordinal, memberId: row._id, hadithId: row.hadithId, disposition: row.disposition };
  });
  const next = request.start + rows.length;
  const page = { kind: "page", ownerKey: userId, request, rows, next, done: next === total } satisfies SyncOutcomePage;
  if (new TextEncoder().encode(JSON.stringify(page)).byteLength > SYNC_OUTCOME_BYTES) throw new Error("SYNC_OUTCOME_PAGE_TOO_LARGE");
  return page;
}

type SyncOutcomePageMember = Extract<SyncOutcomePage, { kind: "page" }>["rows"][number];
