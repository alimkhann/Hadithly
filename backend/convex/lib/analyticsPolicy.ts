import { METRICS, ANALYTICS_VERSION, type AnalyticsMetric } from "./analyticsCatalog";

export const HOUR = 3_600_000;
export const DAY = 24 * HOUR;
export const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
export type Counter = { metric: AnalyticsMetric; count: number };
export type MeasurementHealth = { month: string; admittedMonthly: number; exportedMonthly: number; exportFailures: number; rejectedMonthly?: number; suppressedBuckets?: number; observedHour: number };
export type Summary = { version: 1; platform: "ios" | "android"; batchId: string; hour: number; counters: Counter[] };
export function isMetric(value: unknown): value is AnalyticsMetric {
  return typeof value === "string" && METRICS.some(metric => metric === value);
}
function object(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === "object" && !Array.isArray(value);
}
export function parseSummary(raw: unknown, now: number): Summary | null {
  if (!object(raw) || Object.keys(raw).sort().join() !== "batchId,counters,hour,platform,version"
    || raw.version !== ANALYTICS_VERSION || (raw.platform !== "ios" && raw.platform !== "android")
    || typeof raw.batchId !== "string" || !UUID.test(raw.batchId)
    || typeof raw.hour !== "number" || !Number.isSafeInteger(raw.hour)
    || raw.hour > Math.floor(now / HOUR) || raw.hour * HOUR + DAY <= now
    || !Array.isArray(raw.counters) || !raw.counters.length || raw.counters.length > 32) return null;
  const counters: Counter[] = [], seen = new Set<AnalyticsMetric>();
  for (const item of raw.counters) {
    if (!object(item) || Object.keys(item).sort().join() !== "count,metric" || !isMetric(item.metric)
      || typeof item.count !== "number" || !Number.isSafeInteger(item.count) || item.count < 1 || item.count > 40
      || seen.has(item.metric)) return null;
    seen.add(item.metric); counters.push({ metric: item.metric, count: item.count });
  }
  if (counters.reduce((sum, counter) => sum + counter.count, 0) > 40) return null;
  return { version: 1, platform: raw.platform, batchId: raw.batchId, hour: raw.hour, counters };
}
export function mergeCounters(current: Counter[], incoming: Counter[]): Counter[] {
  const counts = new Map(current.map(item => [item.metric, item.count]));
  for (const item of incoming) counts.set(item.metric, (counts.get(item.metric) ?? 0) + item.count);
  return [...counts].map(([metric, count]) => ({ metric, count }));
}
export function aggregateEvent(input: { metric: AnalyticsMetric; count: number; day: string; platform: "ios" | "android";
  environment: "development" | "production"; uuid: string; health?: MeasurementHealth }) {
  const [family, variant] = input.metric.split(".");
  return { event: family, distinctId: `aggregate:${input.day}:${input.platform}:${input.environment}`,
    uuid: input.uuid, timestamp: new Date(`${input.day}T00:00:00Z`),
    properties: { variant, count: input.count, day: input.day, platform: input.platform,
      environment: input.environment, schema_version: 1, $process_person_profile: false, $geoip_disable: true,
      measurement_month: input.health?.month ?? input.day.slice(0, 7),
      admitted_monthly: input.health?.admittedMonthly ?? 0, exported_monthly: input.health?.exportedMonthly ?? 0,
      export_failures: input.health?.exportFailures ?? 0, rejected_monthly: input.health?.rejectedMonthly ?? 0,
      suppressed_buckets: input.health?.suppressedBuckets ?? 0, observed_hour: input.health?.observedHour ?? 0 } };
}
