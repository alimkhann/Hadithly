import type { MutationCtx, QueryCtx } from "../_generated/server";
import { requireIdentity } from "./identity";
import { textDigest } from "./evidenceReviewPolicy";
import type { SyncDeletionAuthorization } from "./librarySyncPolicy";

const AUTHORIZATION_MS = 15 * 60_000;
const AUTHORIZATION_LIMIT = 20;

export async function requireAccountNotDeleting(ctx: MutationCtx | QueryCtx, subject: string) {
  const subjectDigest = await textDigest(subject);
  const marker = await ctx.db.query("accountDeletionMarkers").withIndex("by_subject", q => q.eq("subjectDigest", subjectDigest)).unique();
  if (marker) throw new Error("ACCOUNT_DELETION_PENDING");
}

/** Creates no account and starts no erasure, even if the client token changed. */
export async function prepareAccountDeletion(ctx: MutationCtx): Promise<SyncDeletionAuthorization> {
  const identity = await requireIdentity(ctx), now = Date.now();
  const subjectDigest = await textDigest(identity.clerkId);
  const grants = await ctx.db.query("accountDeletionAuthorizations").withIndex("by_subject", q => q.eq("subjectDigest", subjectDigest)).take(AUTHORIZATION_LIMIT + 1);
  let live = 0;
  for (const grant of grants) {
    if (grant.validUntil <= now) await ctx.db.delete(grant._id);
    else live++;
  }
  if (live >= AUTHORIZATION_LIMIT) throw new Error("ACCOUNT_DELETION_AUTHORIZATION_LIMIT");
  const authorization = `${crypto.randomUUID()}.${crypto.randomUUID()}`, validUntil = now + AUTHORIZATION_MS;
  await ctx.db.insert("accountDeletionAuthorizations", { subjectDigest, digest: await textDigest(authorization), validUntil });
  return { subject: identity.clerkId, authorization, validUntil };
}

/** JWT plus the captured subject's opaque authorization precede every effect. */
export async function authorizeAccountDeletion(ctx: MutationCtx, authorization: string) {
  const identity = await requireIdentity(ctx);
  const subjectDigest = await textDigest(identity.clerkId);
  const digest = await textDigest(authorization);
  const grant = await ctx.db.query("accountDeletionAuthorizations").withIndex("by_digest", q => q.eq("digest", digest)).unique();
  if (!grant || grant.subjectDigest !== subjectDigest) throw new Error("ACCOUNT_DELETION_OWNER_MISMATCH");
  if (grant.validUntil <= Date.now()) throw new Error("ACCOUNT_DELETION_AUTHORIZATION_EXPIRED");
  const marker = await ctx.db.query("accountDeletionMarkers").withIndex("by_subject", q => q.eq("subjectDigest", subjectDigest)).unique();
  if (!marker) await ctx.db.insert("accountDeletionMarkers", { subjectDigest, requestedAt: Date.now() });
  for (const row of await ctx.db.query("accountDeletionAuthorizations").withIndex("by_subject", q => q.eq("subjectDigest", subjectDigest)).collect()) await ctx.db.delete(row._id);
  return identity;
}
