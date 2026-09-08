import { z } from "zod";

const optionalSecret = z.preprocess(
  (value) => (value === "" ? undefined : value),
  z.string().min(1).optional(),
);

export const serverEnvSchema = z.object({
  SUNNAH_NOW_API_KEY: z.string().min(1),
  GEMINI_API_KEY: optionalSecret,
  CLERK_SECRET_KEY: optionalSecret,
  REVENUECAT_WEBHOOK_SECRET: optionalSecret,
  POLAR_WEBHOOK_SECRET: optionalSecret,
  CRON_SECRET: optionalSecret,
});

export function readServerEnv(env: NodeJS.ProcessEnv = process.env) {
  return serverEnvSchema.parse(env);
}
