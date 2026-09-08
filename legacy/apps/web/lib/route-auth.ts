import { verifyToken } from "@clerk/backend";

import { jsonError } from "./hadith-provider";

export function requireCronSecret(request: Request) {
  const expected = process.env.CRON_SECRET;
  if (!expected) {
    return jsonError("CRON_SECRET is not configured", 503);
  }
  const provided = request.headers
    .get("authorization")
    ?.replace(/^Bearer\s+/i, "");
  if (provided !== expected) {
    return jsonError("Unauthorized", 401);
  }
  return null;
}

export type ClerkAuthResult =
  | { ok: true; clerkId: string }
  | { ok: false; response: Response };

export async function requireClerkAuth(
  request: Request,
): Promise<ClerkAuthResult> {
  const secretKey = process.env.CLERK_SECRET_KEY;
  if (!secretKey) {
    return {
      ok: false,
      response: jsonError("CLERK_SECRET_KEY is not configured", 503),
    };
  }

  const token = request.headers
    .get("authorization")
    ?.replace(/^Bearer\s+/i, "")
    .trim();
  if (!token) {
    return {
      ok: false,
      response: jsonError("Authentication required", 401),
    };
  }

  try {
    const payload = await verifyToken(token, { secretKey });
    if (!payload.sub) {
      return {
        ok: false,
        response: jsonError("Authentication required", 401),
      };
    }
    return { ok: true, clerkId: String(payload.sub) };
  } catch {
    return {
      ok: false,
      response: jsonError("Authentication required", 401),
    };
  }
}
