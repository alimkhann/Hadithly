"use node";
import { randomUUID, createHash } from "node:crypto";
import { v } from "convex/values";
import { PostHog } from "posthog-node";
import { internalAction } from "../_generated/server";
import { internal } from "../_generated/api";
import { aggregateEvent, isMetric, type Counter, type MeasurementHealth } from "../lib/analyticsPolicy";

export function eventUUID(exportId: string, metric: string): string {
  const hex = createHash("sha256").update(`${exportId}:${metric}`).digest("hex");
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-4${hex.slice(13, 16)}-8${hex.slice(17, 20)}-${hex.slice(20, 32)}`;
}

export async function sendAggregate(input: { uuid: string; day: string; platform: "ios" | "android";
  environment: "development" | "production"; counters: Counter[]; health?: MeasurementHealth }, key: string): Promise<boolean> {
  const events = input.counters.map(counter => aggregateEvent({ ...input, ...counter, uuid: eventUUID(input.uuid, counter.metric) }));
  let attempted = false;
  const client = new PostHog(key, { host: "https://eu.i.posthog.com", personProfiles: "never", disableGeoip: true,
    enableExceptionAutocapture: false, enableLocalEvaluation: false, disableCompression: true,
    fetchRetryCount: 0, requestTimeout: 3000, flushAt: 100, flushInterval: 0,
    fetch: async (url, options) => {
      if (attempted) throw new Error("ANALYTICS_ATTEMPT_EXHAUSTED");
      if (new URL(url).origin !== "https://eu.i.posthog.com" || options.method !== "POST") throw new Error("ANALYTICS_TRANSPORT_REJECTED");
      attempted = true;
      return await fetch("https://eu.i.posthog.com/batch/", { method: "POST", redirect: "error",
        headers: { "Content-Type": "application/json" }, signal: AbortSignal.timeout(3000),
        body: JSON.stringify({ api_key: key, batch: events.map(event => ({ event: event.event, uuid: event.uuid,
          timestamp: event.timestamp.toISOString(), properties: { ...event.properties, distinct_id: event.distinctId } })) }) });
    },
    before_send: event => {
      const properties = event.properties;
      if (!properties) return null;
      const metric = `${event.event}.${properties.variant}`;
      if (!isMetric(metric) || !Number.isSafeInteger(properties.count) || properties.count < 1) return null;
      return { ...event, properties: { distinct_id: `aggregate:${input.day}:${input.platform}:${input.environment}`,
        variant: properties.variant, count: properties.count, day: input.day, platform: input.platform,
        environment: input.environment, schema_version: 1, $process_person_profile: false, $geoip_disable: true } };
    } });
  try {
    for (const event of events) client.capture(event);
    await client.flush();
    return true;
  } catch { return false; }
  finally { await client.shutdown(1000).catch(() => undefined); }
}

export const exportDaily = internalAction({ args: { verifyCurrentDay: v.optional(v.boolean()) }, handler: async (ctx, args): Promise<void> => {
  const key = process.env.ANALYTICS_POSTHOG_KEY;
  if (process.env.ANALYTICS_ENABLED !== "1" || !key) return;
  const job = await ctx.runMutation(internal.analytics.claim, { uuid: randomUUID(), verifyCurrentDay: args.verifyCurrentDay });
  if (!job) return;
  const counters: Counter[] = [];
  for (const item of job.counters) {
    if (!isMetric(item.metric)) return;
    counters.push({ metric: item.metric, count: item.count });
  }
  const success = await sendAggregate({ ...job, counters }, key);
  await ctx.runMutation(internal.analytics.settle, { id: job.id, attempt: job.attempt, success });
} });
