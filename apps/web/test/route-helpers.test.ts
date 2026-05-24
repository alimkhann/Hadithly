import { afterEach, describe, expect, it } from "vitest";

import { parsePositiveInt } from "../lib/hadith-provider";
import { requireCronSecret } from "../lib/route-auth";
import { parseInternalHadithId, shouldUseConvex } from "../lib/convex-server";

describe("parsePositiveInt", () => {
  it("returns the fallback for missing, invalid, or non-positive values", () => {
    expect(parsePositiveInt(null, 20)).toBe(20);
    expect(parsePositiveInt("abc", 20)).toBe(20);
    expect(parsePositiveInt("0", 20)).toBe(20);
    expect(parsePositiveInt("-1", 20)).toBe(20);
  });

  it("returns a positive integer query value", () => {
    expect(parsePositiveInt("12", 20)).toBe(12);
  });
});

describe("requireCronSecret", () => {
  const originalSecret = process.env.CRON_SECRET;

  afterEach(() => {
    process.env.CRON_SECRET = originalSecret;
  });

  it("rejects cron calls when the server secret is missing", async () => {
    delete process.env.CRON_SECRET;

    const response = requireCronSecret(
      new Request("https://hadithly.test/api/cron/daily-hadith"),
    );

    expect(response?.status).toBe(503);
    await expect(response?.json()).resolves.toEqual({
      error: "CRON_SECRET is not configured",
    });
  });

  it("accepts matching bearer credentials", () => {
    process.env.CRON_SECRET = "secret";

    const response = requireCronSecret(
      new Request("https://hadithly.test/api/cron/daily-hadith", {
        headers: { authorization: "Bearer secret" },
      }),
    );

    expect(response).toBeNull();
  });
});

describe("parseInternalHadithId", () => {
  it("parses stable Sunnah.now provider ids", () => {
    expect(parseInternalHadithId("sunnah_now:bukhari:1")).toEqual({
      provider: "sunnah_now",
      collectionSlug: "bukhari",
      providerHadithId: "1",
    });
  });

  it("rejects malformed provider ids", () => {
    expect(parseInternalHadithId("bukhari:1")).toBeNull();
    expect(parseInternalHadithId("sunnah_now::1")).toBeNull();
  });
});

describe("shouldUseConvex", () => {
  const originalUrl = process.env.CONVEX_URL;
  const originalPublicUrl = process.env.NEXT_PUBLIC_CONVEX_URL;

  afterEach(() => {
    process.env.CONVEX_URL = originalUrl;
    process.env.NEXT_PUBLIC_CONVEX_URL = originalPublicUrl;
  });

  it("is disabled until a Convex URL is configured", () => {
    delete process.env.CONVEX_URL;
    delete process.env.NEXT_PUBLIC_CONVEX_URL;

    expect(shouldUseConvex()).toBe(false);
  });

  it("is enabled when a server or public Convex URL is configured", () => {
    process.env.CONVEX_URL = "https://example.convex.cloud";

    expect(shouldUseConvex()).toBe(true);
  });
});
