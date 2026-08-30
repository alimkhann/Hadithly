import { jsonError } from "@/lib/hadith-provider";
import { getEnabledPushTokens } from "@/lib/convex-server";
import { requireCronSecret } from "@/lib/route-auth";

export async function POST(request: Request) {
  const authError = requireCronSecret(request);
  if (authError) return authError;

  const tokens = await getEnabledPushTokens();
  if (tokens.length === 0) {
    return Response.json({
      ok: true,
      sent: 0,
      fallback: "No enabled Expo push tokens found or Convex is not configured",
    });
  }

  const messages = tokens.map((token) => ({
    to: token.token,
    sound: "default",
    title: "Today's hadith",
    body: "A short hadith is ready for your daily reading.",
    data: { href: "/reader/bukhari", source: "daily-hadith" },
  }));

  const expoResponse = await fetch("https://exp.host/--/api/v2/push/send", {
    method: "POST",
    headers: {
      accept: "application/json",
      "accept-encoding": "gzip, deflate",
      "content-type": "application/json",
    },
    body: JSON.stringify(messages),
  });
  if (!expoResponse.ok) {
    return jsonError(`Expo push failed with HTTP ${expoResponse.status}`, 502);
  }

  return Response.json({
    ok: true,
    sent: tokens.length,
    fallback:
      "Use cached translation or English if preferred-language translation is unavailable",
  });
}

export function GET() {
  return jsonError("Use POST", 405);
}
