/**
 * Every user-facing query/mutation authenticates through the Clerk ↔ Convex
 * JWT integration. The identity `subject` is the Clerk user id (clerkId).
 * Callers never pass their own userId — that would be an impersonation hole.
 *
 * `getUserIdentity()` is synchronous in queries/mutations and a Promise in
 * actions; awaiting normalizes both.
 */
export type HadithlyIdentity = {
  clerkId: string;
  tokenIdentifier: string;
  name?: string;
  email?: string;
  pictureUrl?: string;
};

type IdentityCtx = {
  auth: { getUserIdentity: () => unknown };
};

export async function requireIdentity(
  ctx: IdentityCtx,
): Promise<HadithlyIdentity> {
  const raw = await ctx.auth.getUserIdentity();
  const identity = raw as {
    subject?: string;
    tokenIdentifier?: string;
    name?: string;
    email?: string;
    pictureUrl?: string;
  } | null;

  if (!identity?.subject || !identity.tokenIdentifier) {
    throw new Error(
      "Unauthenticated: this function requires a signed-in user",
    );
  }
  return {
    clerkId: identity.subject,
    tokenIdentifier: identity.tokenIdentifier,
    name: identity.name,
    email: identity.email,
    pictureUrl: identity.pictureUrl,
  };
}

export async function optionalIdentity(
  ctx: IdentityCtx,
): Promise<HadithlyIdentity | null> {
  try {
    return await requireIdentity(ctx);
  } catch {
    return null;
  }
}
