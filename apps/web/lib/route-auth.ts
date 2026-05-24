import { jsonError } from "./hadith-provider";

export function requireCronSecret(request: Request) {
  const expected = process.env.CRON_SECRET;
  if (!expected) {
    return jsonError("CRON_SECRET is not configured", 503);
  }
  const provided = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "");
  if (provided !== expected) {
    return jsonError("Unauthorized", 401);
  }
  return null;
}
