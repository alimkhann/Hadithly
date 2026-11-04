/// <reference types="vite/client" />
import { convexTest } from "convex-test";
import { afterEach, expect, test, vi } from "vitest";
import { internal } from "./_generated/api";
import schema from "./schema";
import { normalizeHadith } from "./lib/sunnahNow";

const send = vi.hoisted(() => vi.fn());
const configured = vi.hoisted(() => vi.fn(() => true));
vi.mock("./lib/apns", () => ({ apnsConfigured: configured, sendApnsPush: send }));
afterEach(() => { vi.unstubAllEnvs(); send.mockReset(); configured.mockReset().mockReturnValue(true); });

async function fixture() {
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  const t = convexTest(schema, import.meta.glob("./**/*.ts"));
  const [hadithId] = await t.mutation(internal.hadiths.upsertPage, { items: [normalizeHadith("bukhari", { id: "7" })] });
  await t.mutation(internal.migrations.confirmSunnahNowDevelopmentLicense, {});
  const { tokenId, translationId } = await t.run(async ctx => {
    const userId = await ctx.db.insert("users", { clerkId: "test", preferredLanguage: "en", subscriptionTier: "free", createdAt: 1, updatedAt: 1 });
    const tokenId = await ctx.db.insert("pushTokens", { userId, token: "SECRET_TOKEN_CANARY", platform: "ios", enabled: true, updatedAt: 1 });
    const translationId = await ctx.db.insert("translations", { hadithId, language: "ru", content: "Русский перевод", source: "gemini_ai", sourceLabel: "AI", status: "live", isDefault: true, groundingUsed: false, createdAt: 1, updatedAt: 1 });
    return { tokenId, translationId };
  });
  return { t, tokenId, translationId, hadithId };
}

test("sends one cached labeled exact-target payload and exposes only status", async () => {
  const { t, tokenId } = await fixture();
  const before = await t.run(ctx => ctx.db.get(tokenId));
  send.mockResolvedValue(200);
  expect(await t.action(internal.actions.notificationVerification.sendCachedBukhariSeven, { tokenId })).toBe("accepted");
  expect(send).toHaveBeenCalledTimes(1);
  expect(send.mock.calls[0][1]).toMatchObject({ alert: { body: expect.stringContaining("Русский перевод") }, custom: { collectionSlug: "bukhari", providerHadithId: "7", locale: "ru", ai: "1" } });
  expect(send.mock.calls[0][1].alert.body).toContain("Перевод ИИ");
  expect(await t.run(ctx => ctx.db.get(tokenId))).toEqual(before);
});

test("rejects unavailable deployment, disabled or wrong platform, absent cache and missing permission", async () => {
  const { t, tokenId, translationId, hadithId } = await fixture();
  const run = () => t.action(internal.actions.notificationVerification.sendCachedBukhariSeven, { tokenId });
  vi.stubEnv("CONVEX_CLOUD_URL", "https://production.convex.cloud");
  expect(await run()).toBe("unavailable");
  vi.stubEnv("CONVEX_CLOUD_URL", "https://festive-cobra-664.eu-west-1.convex.cloud");
  configured.mockReturnValue(false);
  expect(await run()).toBe("unavailable");
  configured.mockReturnValue(true);
  await t.run(ctx => ctx.db.patch(tokenId, { enabled: false }));
  expect(await run()).toBe("unavailable");
  await t.run(ctx => ctx.db.patch(tokenId, { enabled: true, platform: "android" }));
  expect(await run()).toBe("unavailable");
  await t.run(async ctx => { await ctx.db.patch(tokenId, { platform: "ios" }); await ctx.db.patch(translationId, { isDefault: false }); });
  expect(await run()).toBe("unavailable");
  await t.run(async ctx => { await ctx.db.patch(translationId, { isDefault: true }); await ctx.db.patch(hadithId, { licenseRecordId: undefined }); });
  expect(await run()).toBe("unavailable");
  expect(send).not.toHaveBeenCalled();
});

test("returns a fixed rejection status without exposing provider details", async () => {
  const { t, tokenId } = await fixture();
  send.mockRejectedValue(new Error("SECRET_PROVIDER_DETAIL"));
  expect(await t.action(internal.actions.notificationVerification.sendCachedBukhariSeven, { tokenId })).toBe("rejected");
});
