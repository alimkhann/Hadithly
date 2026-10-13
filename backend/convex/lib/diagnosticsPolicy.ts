import { v } from "convex/values";
import type { Infer } from "convex/values";
import { DIAGNOSTICS_RELEASE } from "./diagnosticsRelease";

export const operation = v.union(v.literal("generation"), v.literal("daily_translation"),
  v.literal("daily_push"), v.literal("evidence_processing"), v.literal("subscription_refresh"),
  v.literal("canonical_resolver"), v.literal("synthetic"));
export type DiagnosticOperation = Infer<typeof operation>;
export const surface = v.union(v.literal("backend"), v.literal("web"));
export type DiagnosticSurface = Infer<typeof surface>;
export const MONTHLY_REPORT_CAP = 1000;
export const REPORT_INTERVAL_MS = 60_000;
export const HEALTH_WINDOW_MS = 10 * 60_000;
export const HEARTBEAT_STALE_MS = 45 * 60_000;

export function diagnosticsEnvironment(): "development" | "production" {
  return process.env.CONVEX_CLOUD_URL?.includes("giddy-ox-648") ? "production" : "development";
}

export function safeEvent(input: { operation: DiagnosticOperation; surface: DiagnosticSurface;
  eventId: string; release?: string; environment?: "development" | "production" }) {
  return { event_id: input.eventId, platform: input.surface === "backend" ? "node" : "javascript",
    level: "error", release: input.release ?? DIAGNOSTICS_RELEASE,
    environment: input.environment ?? diagnosticsEnvironment(),
    exception: { values: [{ type: "HadithlyOperationalFailure", value: input.operation }] },
    tags: { surface: input.surface, operation: input.operation },
    fingerprint: ["hadithly", input.surface, input.operation] };
}

export function parseWebFailure(raw: unknown): { operation: "canonical_resolver" | "synthetic"; release: string; environment: "development" | "production" } | null {
  if (raw === null || typeof raw !== "object" || Array.isArray(raw)) return null;
  if (Object.keys(raw).sort().join(",") !== "environment,operation,release") return null;
  if (!("operation" in raw) || !("release" in raw) || !("environment" in raw)) return null;
  if (raw.operation !== "canonical_resolver" && raw.operation !== "synthetic") return null;
  if (typeof raw.release !== "string" || !/^hadithly@[a-f0-9]{12}$/.test(raw.release)) return null;
  if (raw.environment !== "development" && raw.environment !== "production") return null;
  return { operation: raw.operation, release: raw.release, environment: raw.environment };
}

export function sentryDestination(raw: string | undefined): { url: string; authorization: string } | null {
  if (!raw) return null;
  try {
    const dsn = new URL(raw);
    if (dsn.protocol !== "https:" || !/^o[0-9]+\.ingest\.(?:us\.|de\.)?sentry\.io$/.test(dsn.hostname)
      || !/^[a-f0-9]{32}$/.test(dsn.username) || dsn.password || !/^\/[0-9]+$/.test(dsn.pathname) || dsn.search || dsn.hash) return null;
    return { url: `https://${dsn.hostname}/api${dsn.pathname}/envelope/`,
      authorization: `Sentry sentry_version=7,sentry_key=${dsn.username}` };
  } catch { return null; }
}
