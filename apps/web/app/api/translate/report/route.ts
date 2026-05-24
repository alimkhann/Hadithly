import { jsonError } from "@/lib/hadith-provider";

export async function POST(request: Request) {
  const body = await request.json().catch(() => null);
  if (!body?.translationId || !body?.reason) {
    return jsonError("Invalid report request", 400);
  }
  return Response.json({ ok: true, status: "queued_for_moderation" });
}
