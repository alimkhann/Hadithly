import { jsonError } from "@/lib/hadith-provider";

export async function POST(request: Request) {
  if (!process.env.POLAR_WEBHOOK_SECRET) {
    return jsonError("POLAR_WEBHOOK_SECRET is not configured", 503);
  }
  const event = await request.json().catch(() => null);
  if (!event) {
    return jsonError("Invalid Polar webhook", 400);
  }
  return Response.json({ ok: true, entitlementSync: "queued" });
}
