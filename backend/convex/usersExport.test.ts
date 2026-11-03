/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api } from "./_generated/api";
import schema from "./schema";

const modules = import.meta.glob("./**/*.ts");

const TEST_TOKEN_IDENTIFIER = "https://clerk.example|user_export_test";

function identity(subject: string) {
  return { subject, tokenIdentifier: TEST_TOKEN_IDENTIFIER };
}

describe("users:exportCurrentUserData", () => {
  test("requires authentication", async () => {
    const t = convexTest(schema, modules);
    await expect(t.query(api.users.exportCurrentUserData, {})).rejects.toThrow(
      "Unauthenticated",
    );
  });

  test("returns empty portable payload when no user row exists", async () => {
    const t = convexTest(schema, modules);
    const result = await t
      .withIdentity(identity("export_norow"))
      .query(api.users.exportCurrentUserData, {});
    expect(result.account).toBeNull();
    expect(result.notificationPreferences).toBeNull();
    expect(result.savedItems).toEqual([]);
    expect(result.readingProgress).toEqual([]);
    expect(result.submissions).toEqual([]);
  });

  test("exports only the caller's portable data", async () => {
    const t = convexTest(schema, modules);
    const alice = t.withIdentity(identity("export_alice"));
    const bob = t.withIdentity(identity("export_bob"));

    await alice.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
    await bob.mutation(api.users.ensureCurrentUser, { preferredLanguage: "ar" });
    await alice.mutation(api.library.setDailyNotification, { enabled: true, dailyTime: "07:15" });
    await bob.mutation(api.library.setDailyNotification, { enabled: false, dailyTime: "18:37" });
    await alice.mutation(api.library.savePushToken, { token: "PRIVATE_TOKEN_CANARY", platform: "ios" });

    const aliceExport = await alice.query(api.users.exportCurrentUserData, {});
    expect(aliceExport.account?.subscriptionTier).toBe("free");
    expect(aliceExport.readerPreferences).toMatchObject({ translationLocale: "en" });
    expect(aliceExport.notificationPreferences).toEqual({ enabled: true, dailyTime: "07:15" });
    // No push tokens, audit rows, or other users leak into the payload.
    expect(JSON.stringify(aliceExport)).not.toContain("pushTokens");
    expect(JSON.stringify(aliceExport)).not.toContain("PRIVATE_TOKEN_CANARY");
    expect(JSON.stringify(aliceExport)).not.toContain("adminAuditLog");
    expect(JSON.stringify(aliceExport)).not.toContain("export_bob");

    const bobExport = await bob.query(api.users.exportCurrentUserData, {});
    expect(bobExport.readerPreferences).toMatchObject({ translationLocale: "ar" });
    expect(bobExport.notificationPreferences).toEqual({ enabled: false, dailyTime: "18:37" });
    expect(JSON.stringify(bobExport)).not.toContain("export_alice");
    expect(JSON.stringify(bobExport)).not.toContain("PRIVATE_TOKEN_CANARY");
  });

  test("deletion removes everything the export would carry", async () => {
    const t = convexTest(schema, modules);
    const user = t.withIdentity(identity("export_then_delete"));
    await user.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
    const unset = await user.query(api.users.exportCurrentUserData, {});
    expect(unset.notificationPreferences).toBeNull();
    await user.mutation(api.library.setDailyNotification, { enabled: true, dailyTime: "08:00" });
    const before = await user.query(api.users.exportCurrentUserData, {});
    expect(before.account).not.toBeNull();
    expect(before.notificationPreferences).toEqual({ enabled: true, dailyTime: "08:00" });
    await user.mutation(api.users.deleteCurrentUser, { authorization: (await user.mutation(api.users.prepareAccountDeletion, {})).authorization });
    const after = await user.query(api.users.exportCurrentUserData, {});
    expect(after.account).toBeNull();
    expect(after.notificationPreferences).toBeNull();
    expect(after.savedItems).toEqual([]);
    expect(after.readingProgress).toEqual([]);
  });
});
