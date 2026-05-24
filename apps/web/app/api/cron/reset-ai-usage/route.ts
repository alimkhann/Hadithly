import { jsonError } from "@/lib/hadith-provider";
import { requireCronSecret } from "@/lib/route-auth";

export async function POST(request: Request) {
  const authError = requireCronSecret(request);
  if (authError) return authError;
  return Response.json({ ok: true, reset: "queued" });
}
