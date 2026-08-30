import { saveUserPushToken } from "@/lib/convex-server";
import { jsonError } from "@/lib/hadith-provider";

type PushTokenRequest = {
  clerkId?: string;
  email?: string;
  displayName?: string;
  preferredLanguage?: string;
  token?: string;
  platform?: "ios" | "android" | "web";
  dailyTime?: string;
};

export async function POST(request: Request) {
  const body = (await request
    .json()
    .catch(() => null)) as PushTokenRequest | null;
  if (!body?.clerkId || !body.token || !body.platform) {
    return jsonError("clerkId, token, and platform are required", 400);
  }

  const saved = await saveUserPushToken({
    clerkId: body.clerkId,
    email: body.email,
    displayName: body.displayName,
    preferredLanguage: body.preferredLanguage,
    token: body.token,
    platform: body.platform,
    dailyTime: body.dailyTime,
  });

  return Response.json({ ok: true, saved: Boolean(saved) });
}
