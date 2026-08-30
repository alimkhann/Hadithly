import { resetMonthlyAiUsageForAll } from "@/lib/convex-server";
import { jsonError } from "@/lib/hadith-provider";
import { requireCronSecret } from "@/lib/route-auth";

export async function POST(request: Request) {
  const authError = requireCronSecret(request);
  if (authError) return authError;
  try {
    const reset = await resetMonthlyAiUsageForAll();
    if (reset === null) {
      return jsonError("Convex is not configured", 503);
    }
    return Response.json({ ok: true, reset });
  } catch (error) {
    return jsonError(
      error instanceof Error ? error.message : "Failed to reset AI usage",
      500,
    );
  }
}
