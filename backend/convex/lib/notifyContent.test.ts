import { describe, expect, test } from "vitest";
import {
  allDeliveryBuckets,
  buildNotificationPayload,
  classifyPushError,
  localDateInIanaZone,
  localMinutesInIanaZone,
  normalizeDeliveryBucket,
  retryDelayMs,
  selectDueTokens,
  type PushTokenLike,
} from "./notifyContent";

function token(overrides: Partial<PushTokenLike> = {}): PushTokenLike {
  return {
    _id: "token",
    enabled: true,
    dailyTime: "08:00",
    timezone: "Asia/Almaty",
    ...overrides,
  };
}

// 2026-09-18T03:05:00Z == 08:05 in Asia/Almaty (UTC+5 since March 2024,
// Kazakhstan stays on standard time year-round).
const ALMATY_0805 = Date.parse("2026-09-18T03:05:00Z");

describe("normalizeDeliveryBucket", () => {
  test("floors to the 15-minute slot", () => {
    expect(normalizeDeliveryBucket("08:00")).toBe("08:00");
    expect(normalizeDeliveryBucket("08:07")).toBe("08:00");
    expect(normalizeDeliveryBucket("08:15")).toBe("08:15");
    expect(normalizeDeliveryBucket("23:59")).toBe("23:45");
  });
  test("rejects malformed times", () => {
    expect(normalizeDeliveryBucket("8:00")).toBeNull();
    expect(normalizeDeliveryBucket("24:00")).toBeNull();
    expect(normalizeDeliveryBucket("08:60")).toBeNull();
    expect(normalizeDeliveryBucket("morning")).toBeNull();
  });
  test("covers all 96 slots", () => {
    expect(allDeliveryBuckets()).toHaveLength(96);
    expect(allDeliveryBuckets()[0]).toBe("00:00");
    expect(allDeliveryBuckets()[95]).toBe("23:45");
  });
});

describe("IANA local clock", () => {
  test("resolves Almaty local date and minutes", () => {
    expect(localDateInIanaZone(ALMATY_0805, "Asia/Almaty")).toBe("2026-09-18");
    expect(localMinutesInIanaZone(ALMATY_0805, "Asia/Almaty")).toEqual({
      date: "2026-09-18",
      minutes: 8 * 60 + 5,
    });
  });
  test("follows DST through the zone database", () => {
    // America/Los_Angeles: PDT (UTC-7) in July, PST (UTC-8) in January.
    // 15:00 UTC is 08:00 PDT but 07:00 PST — a fixed offset would be wrong
    // for one of the two.
    const july = Date.parse("2026-07-01T15:00:00Z");
    const january = Date.parse("2026-01-01T15:00:00Z");
    expect(localMinutesInIanaZone(july, "America/Los_Angeles").minutes).toBe(
      8 * 60,
    );
    expect(localMinutesInIanaZone(january, "America/Los_Angeles").minutes).toBe(
      7 * 60,
    );
  });
  test("throws on an invalid zone", () => {
    expect(() => localDateInIanaZone(ALMATY_0805, "Mars/Olympus")).toThrow();
  });
});

describe("selectDueTokens", () => {
  test("marks a token due inside its window", () => {
    const { due, skipped } = selectDueTokens([token()], ALMATY_0805);
    expect(due).toHaveLength(1);
    expect(due[0].localDate).toBe("2026-09-18");
    expect(due[0].isRetry).toBe(false);
    expect(skipped).toHaveLength(0);
  });
  test("skips outside the window and after it passes", () => {
    const before = selectDueTokens(
      [token()],
      Date.parse("2026-09-18T02:50:00Z"),
    );
    expect(before.due).toHaveLength(0);
    expect(before.skipped[0].reason).toBe("outside-window");
    const after = selectDueTokens([token()], Date.parse("2026-09-18T03:20:00Z"));
    expect(after.due).toHaveLength(0);
    expect(after.skipped[0].reason).toBe("outside-window");
  });
  test("prevents duplicate local-date delivery", () => {
    const { due, skipped } = selectDueTokens(
      [token({ lastSentDate: "2026-09-18" })],
      ALMATY_0805,
    );
    expect(due).toHaveLength(0);
    expect(skipped[0].reason).toBe("duplicate-local-date");
  });
  test("skips tokens without an IANA zone instead of guessing", () => {
    const { due, skipped } = selectDueTokens(
      [token({ timezone: undefined })],
      ALMATY_0805,
    );
    expect(due).toHaveLength(0);
    expect(skipped[0].reason).toBe("missing-timezone");
  });
  test("flags invalid zones and times observably", () => {
    const badZone = selectDueTokens(
      [token({ timezone: "Not/AZone" })],
      ALMATY_0805,
    );
    expect(badZone.skipped[0].reason).toBe("invalid-timezone");
    const badTime = selectDueTokens([token({ dailyTime: "25:00" })], ALMATY_0805);
    expect(badTime.skipped[0].reason).toBe("invalid-daily-time");
  });
  test("retries matured failures even outside the window, bounded", () => {
    const retry = selectDueTokens(
      [
        token({
          consecutiveFailures: 1,
          nextRetryAt: ALMATY_0805 - 60_000,
          dailyTime: "08:00",
        }),
      ],
      // 10:00 local: outside the 08:00 window, but the retry is mature.
      Date.parse("2026-09-18T05:00:00Z"),
    );
    expect(retry.due).toHaveLength(1);
    expect(retry.due[0].isRetry).toBe(true);
    const exhausted = selectDueTokens(
      [token({ consecutiveFailures: 3, nextRetryAt: 0 })],
      ALMATY_0805,
    );
    expect(exhausted.due).toHaveLength(0);
    expect(exhausted.skipped[0].reason).toBe("retry-exhausted");
    const waiting = selectDueTokens(
      [token({ consecutiveFailures: 1, nextRetryAt: ALMATY_0805 + 60_000 })],
      ALMATY_0805,
    );
    expect(waiting.due).toHaveLength(0);
    expect(waiting.skipped[0].reason).toBe("outside-window");
  });
  test("is idempotent: stamping lastSentDate removes the token", () => {
    const first = selectDueTokens([token()], ALMATY_0805);
    expect(first.due).toHaveLength(1);
    const second = selectDueTokens(
      [token({ lastSentDate: first.due[0].localDate })],
      ALMATY_0805,
    );
    expect(second.due).toHaveLength(0);
  });
});

describe("retryDelayMs", () => {
  test("backs off exponentially with a cap", () => {
    expect(retryDelayMs(1)).toBe(2 * 60 * 1000);
    expect(retryDelayMs(2)).toBe(4 * 60 * 1000);
    expect(retryDelayMs(3)).toBe(8 * 60 * 1000);
    expect(retryDelayMs(100)).toBe(4 * 60 * 60 * 1000);
  });
});

describe("classifyPushError", () => {
  test("treats dead tokens as permanent", () => {
    expect(classifyPushError(new Error("APNs rejected push (410): Gone"))).toBe(
      "permanent",
    );
    expect(
      classifyPushError(new Error("APNs rejected push (400): BadDeviceToken")),
    ).toBe("permanent");
    expect(
      classifyPushError(
        new Error("FCM rejected push (404): UNREGISTERED"),
      ),
    ).toBe("permanent");
    expect(
      classifyPushError(
        new Error("FCM rejected push (400): INVALID_ARGUMENT"),
      ),
    ).toBe("permanent");
  });
  test("treats rate limits as backpressure", () => {
    expect(classifyPushError(new Error("APNs rejected push (429): slow"))).toBe(
      "backpressure",
    );
  });
  test("treats the rest as transient", () => {
    expect(classifyPushError(new Error("socket hang up"))).toBe("transient");
    expect(classifyPushError(new Error("FCM rejected push (500): boom"))).toBe(
      "transient",
    );
  });
});

describe("buildNotificationPayload", () => {
  test("labels AI text and carries the exact target", () => {
    const payload = buildNotificationPayload({
      collectionName: "Sahih al-Bukhari",
      referenceDisplay: "Hadith 57",
      translation: { text: "Actions are by intentions.", language: "en", isAI: false },
      hadithId: "hadith1",
      collectionSlug: "bukhari",
      providerHadithId: "57",
      volumeId: "2",
    });
    expect(payload.title).toBe("Sahih al-Bukhari · Hadith 57");
    expect(payload.body).toBe("Actions are by intentions.");
    const alreadyQualified = buildNotificationPayload({
      collectionName: "Sahih al-Bukhari",
      referenceDisplay: "Sahih al-Bukhari · Hadith 231",
      translation: { text: "Body.", language: "en", isAI: false },
      hadithId: "hadith1",
      collectionSlug: "bukhari",
      providerHadithId: "231",
    });
    expect(alreadyQualified.title).toBe("Sahih al-Bukhari · Hadith 231");
    expect(payload.data).toMatchObject({
      collectionSlug: "bukhari",
      providerHadithId: "57",
      volumeId: "2",
      locale: "en",
      ai: "0",
    });
    const ai = buildNotificationPayload({
      collectionName: "Sahih al-Bukhari",
      referenceDisplay: "Hadith 57",
      translation: { text: "Әрекеттер ниетке байланысты.", language: "kk", isAI: true },
      hadithId: "hadith1",
      collectionSlug: "bukhari",
      providerHadithId: "57",
    });
    expect(ai.body).toContain("AI translation");
    expect(ai.data.ai).toBe("1");
    expect(ai.data.volumeId).toBeUndefined();
  });
  test("truncates very long bodies", () => {
    const payload = buildNotificationPayload({
      collectionName: "C",
      referenceDisplay: "R",
      translation: { text: "x".repeat(2000), language: "en", isAI: false },
      hadithId: "h",
      collectionSlug: "bukhari",
      providerHadithId: "1",
    });
    expect(payload.body.length).toBeLessThanOrEqual(1001);
    expect(payload.body.endsWith("…")).toBe(true);
  });
});
