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

function isIdentityRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

export async function requireIdentity(
  ctx: IdentityCtx,
): Promise<HadithlyIdentity> {
  const raw = await ctx.auth.getUserIdentity();
  if (
    !isIdentityRecord(raw) ||
    typeof raw.subject !== "string" ||
    typeof raw.tokenIdentifier !== "string"
  ) {
    throw new Error(
      "Unauthenticated: this function requires a signed-in user",
    );
  }
  return {
    clerkId: raw.subject,
    tokenIdentifier: raw.tokenIdentifier,
    name: typeof raw.name === "string" ? raw.name : undefined,
    email: typeof raw.email === "string" ? raw.email : undefined,
    pictureUrl: typeof raw.pictureUrl === "string" ? raw.pictureUrl : undefined,
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
