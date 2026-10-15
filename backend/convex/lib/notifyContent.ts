/**
 * N1 notification content: pure helpers for translated exact-target pushes.
 *
 * Everything here is deterministic and network-free so the cron's decisions
 * (due filtering, resolution order, payload shape, error classification) are
 * unit-testable without devices or provider credentials.
 *
 * Resolution order (PLAN.md): approved/official text first, reusable cached
 * AI second, one globally cached labeled service generation only when policy
 * permits. Never Arabic-only or the wrong language as a silent fallback —
 * unresolved content is skipped with an observable reason.
 */

import { notificationAITranslationLabel } from "./notificationLocalization";

export const DAILY_TIME_PATTERN = /^([01][0-9]|2[0-3]):[0-5][0-9]$/;

/** Cron cadence in minutes. Delivery windows are [due, due + WINDOW). */
export const DELIVERY_WINDOW_MINUTES = 15;

/** Max transient attempts for one token within one local date. */
export const MAX_ATTEMPTS_PER_DATE = 3;

/** Max pushes attempted in a single cron run (provider backpressure). */
export const MAX_SENDS_PER_RUN = 500;

/** Base for exponential retry backoff: attempt n waits 2^n minutes. */
export const RETRY_BASE_MINUTES = 2;

/** Cap for a single retry delay. */
export const RETRY_MAX_MINUTES = 4 * 60;

/** Tokens unseen for this long are purged as probably-uninstalled. */
export const STALE_TOKEN_DAYS = 30;

/** Push body truncation budget (well under the ~4KB provider limits). */
export const MAX_BODY_CHARS = 1000;

export type SkipReason =
  | "disabled"
  | "missing-timezone"
  | "invalid-timezone"
  | "invalid-daily-time"
  | "outside-window"
  | "duplicate-local-date"
  | "retry-exhausted"
  | "missing-content"
  | "unresolved-translation"
  | "service-generation-failed"
  | "provider-unconfigured";

export type PushTokenLike = {
  _id: unknown;
  enabled: boolean;
  dailyTime?: string;
  /** IANA timezone. Tokens without one predate N1 and cannot be scheduled. */
  timezone?: string;
  lastSentDate?: string;
  consecutiveFailures?: number;
  nextRetryAt?: number;
};

export type DueToken<T extends PushTokenLike> = {
  token: T;
  localDate: string;
  isRetry: boolean;
};

export type SkippedToken<T extends PushTokenLike> = {
  token: T;
  reason: SkipReason;
};

/** Floors "HH:MM" to its 15-minute delivery bucket ("08:07" → "08:00"). */
export function normalizeDeliveryBucket(dailyTime: string): string | null {
  const trimmed = dailyTime.trim();
  const match = DAILY_TIME_PATTERN.exec(trimmed);
  if (!match) return null;
  const [hh, mm] = trimmed.split(":");
  const floored = Math.floor(Number(mm) / 15) * 15;
  return `${hh}:${String(floored).padStart(2, "0")}`;
}

/** All 96 quarter-hour bucket labels in a day. */
export function allDeliveryBuckets(): string[] {
  const buckets: string[] = [];
  for (let hour = 0; hour < 24; hour += 1) {
    for (const minute of [0, 15, 30, 45]) {
      buckets.push(
        `${String(hour).padStart(2, "0")}:${String(minute).padStart(2, "0")}`,
      );
    }
  }
  return buckets;
}

/** Throws unless `timezone` is a valid IANA zone name. */
export function assertIanaTimezone(timezone: string): void {
  try {
    new Intl.DateTimeFormat("en-CA", { timeZone: timezone });
  } catch {
    throw new Error(`Invalid IANA timezone: ${timezone}`);
  }
  if (!timezone || timezone.length > 64) {
    throw new Error(`Invalid IANA timezone: ${timezone}`);
  }
}

/** Local calendar date (YYYY-MM-DD) in an IANA zone. Throws on bad zone. */
export function localDateInIanaZone(nowMs: number, timezone: string): string {
  const parts = new Intl.DateTimeFormat("en-CA", {
    timeZone: timezone,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
  }).formatToParts(new Date(nowMs));
  const get = (type: string) => parts.find((p) => p.type === type)?.value;
  const year = get("year");
  const month = get("month");
  const day = get("day");
  if (!year || !month || !day) {
    throw new Error(`Could not resolve local date for timezone: ${timezone}`);
  }
  return `${year}-${month}-${day}`;
}

/** Local minutes-since-midnight in an IANA zone. Throws on bad zone. */
export function localMinutesInIanaZone(
  nowMs: number,
  timezone: string,
): { date: string; minutes: number } {
  const date = localDateInIanaZone(nowMs, timezone);
  const parts = new Intl.DateTimeFormat("en-GB", {
    timeZone: timezone,
    hour: "2-digit",
    minute: "2-digit",
    hourCycle: "h23",
  }).formatToParts(new Date(nowMs));
  const get = (type: string) => parts.find((p) => p.type === type)?.value;
  const hour = Number(get("hour"));
  const minute = Number(get("minute"));
  if (!Number.isFinite(hour) || !Number.isFinite(minute)) {
    throw new Error(`Could not resolve local time for timezone: ${timezone}`);
  }
  return { date, minutes: hour * 60 + minute };
}

function toDueMinutes(dailyTime: string): number | null {
  if (!DAILY_TIME_PATTERN.test(dailyTime.trim())) return null;
  const [hour, minute] = dailyTime.trim().split(":").map(Number);
  return hour * 60 + minute;
}

/**
 * Splits tokens into due and skipped for one cron tick. Pure: no clock
 * reads (nowMs injected), no IO. Re-running with the same inputs converges
 * to the same split, and stamping lastSentDate makes a token leave the due
 * set — the idempotency property the 15-minute cron depends on.
 */
export function selectDueTokens<T extends PushTokenLike>(
  tokens: T[],
  nowMs: number,
): { due: DueToken<T>[]; skipped: SkippedToken<T>[] } {
  const due: DueToken<T>[] = [];
  const skipped: SkippedToken<T>[] = [];
  for (const token of tokens) {
    if (!token.enabled) {
      skipped.push({ token, reason: "disabled" });
      continue;
    }
    if (!token.timezone) {
      skipped.push({ token, reason: "missing-timezone" });
      continue;
    }
    let local: { date: string; minutes: number };
    try {
      local = localMinutesInIanaZone(nowMs, token.timezone);
    } catch {
      skipped.push({ token, reason: "invalid-timezone" });
      continue;
    }
    if (token.lastSentDate === local.date) {
      skipped.push({ token, reason: "duplicate-local-date" });
      continue;
    }
    const failures = token.consecutiveFailures ?? 0;
    const isRetry = failures > 0;
    if (isRetry) {
      if (failures >= MAX_ATTEMPTS_PER_DATE) {
        skipped.push({ token, reason: "retry-exhausted" });
        continue;
      }
      if ((token.nextRetryAt ?? 0) > nowMs) {
        skipped.push({ token, reason: "outside-window" });
        continue;
      }
      // A maturing retry goes even outside the daily window so transient
      // failures still deliver the same local date when they clear.
      due.push({ token, localDate: local.date, isRetry: true });
      continue;
    }
    if (!token.dailyTime || toDueMinutes(token.dailyTime) === null) {
      skipped.push({ token, reason: "invalid-daily-time" });
      continue;
    }
    const dueMinutes = toDueMinutes(token.dailyTime) as number;
    if (
      local.minutes >= dueMinutes &&
      local.minutes < dueMinutes + DELIVERY_WINDOW_MINUTES
    ) {
      due.push({ token, localDate: local.date, isRetry: false });
    } else {
      skipped.push({ token, reason: "outside-window" });
    }
  }
  return { due, skipped };
}

/** Retry delay after `failures` consecutive failures (1-based). */
export function retryDelayMs(failures: number): number {
  const minutes = Math.min(
    RETRY_BASE_MINUTES * 2 ** Math.max(0, failures - 1),
    RETRY_MAX_MINUTES,
  );
  return minutes * 60 * 1000;
}

export type PushErrorClass = "permanent" | "transient" | "backpressure";

/**
 * Classifies a provider send failure from the sender's thrown error.
 * Permanent means the token will never work again (delete it); backpressure
 * means stop this run and leave the rest for the next tick; everything else
 * is a bounded transient retry.
 */
export function classifyPushError(error: unknown): PushErrorClass {
  const message = error instanceof Error ? error.message : String(error);
  if (/\(429\)|too many requests|rate.?limit|retry.?after/i.test(message)) {
    return "backpressure";
  }
  if (
    /\b(410|400|404)\b/.test(message) &&
    /bad ?device ?token|unregistered|invalid.?argument|invalid.?token|gone|not.?registered|no longer valid/i.test(
      message,
    )
  ) {
    return "permanent";
  }
  if (/unregistered|invalid.?argument/i.test(message)) {
    return "permanent";
  }
  return "transient";
}

export type NotificationTranslation = {
  text: string;
  language: string;
  /** True for cached or service-generated AI text: the message must label it. */
  isAI: boolean;
};

export type NotificationPayload = {
  title: string;
  body: string;
  data: Record<string, string>;
};

/**
 * Builds the exact-target push payload. The title is the reference display,
 * prefixed with the collection only when the display does not already
 * contain it (provider displays usually read "Collection · Hadith N").
 * The body is the selected translation with an AI label suffix when
 * applicable. Data carries the canonical identity the clients route
 * through their F3/R2 path.
 */
export function buildNotificationPayload(input: {
  collectionName: string;
  referenceDisplay: string;
  translation: NotificationTranslation;
  hadithId: string;
  collectionSlug: string;
  providerHadithId: string;
  volumeId?: string | null;
}): NotificationPayload {
  const body = input.translation.isAI
    ? `${truncateBody(input.translation.text)}\n— ${notificationAITranslationLabel(input.translation.language)}`
    : truncateBody(input.translation.text);
  const title = input.referenceDisplay.includes(input.collectionName)
    ? input.referenceDisplay
    : `${input.collectionName} · ${input.referenceDisplay}`;
  return {
    title,
    body,
    data: {
      collectionSlug: input.collectionSlug,
      providerHadithId: input.providerHadithId,
      ...(input.volumeId ? { volumeId: input.volumeId } : {}),
      hadithId: input.hadithId,
      locale: input.translation.language,
      ai: input.translation.isAI ? "1" : "0",
    },
  };
}

function truncateBody(text: string): string {
  const trimmed = text.trim();
  if (trimmed.length <= MAX_BODY_CHARS) return trimmed;
  return `${trimmed.slice(0, MAX_BODY_CHARS).trimEnd()}…`;
}
