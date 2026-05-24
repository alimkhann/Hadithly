import { readServerEnv } from "@hadithly/config";
import { SunnahNowProvider } from "@hadithly/hadith-provider";

export function getHadithProvider() {
  const env = readServerEnv();
  return new SunnahNowProvider({ apiKey: env.SUNNAH_NOW_API_KEY });
}

export function jsonError(message: string, status = 500) {
  return Response.json({ error: message }, { status });
}

export function parsePositiveInt(value: string | null, fallback: number) {
  const parsed = Number(value);
  return Number.isInteger(parsed) && parsed > 0 ? parsed : fallback;
}
