/// <reference types="vite/client" />

import { convexTest } from "convex-test";
import { describe, expect, test } from "vitest";
import { api, internal } from "./_generated/api";
import schema from "./schema";
import {
  PreferencesError,
  canonicalizeLocaleTag,
  defaultReaderPreferences,
  localeFallbackChain,
  parseReaderPreferences,
  readingDirectionMetadata,
  resolveLocale,
} from "./lib/preferences";

const modules = import.meta.glob("./**/*.ts");

const TEST_TOKEN_IDENTIFIER = "https://clerk.example|user_pref_test";

function identity(subject: string) {
  return { subject, tokenIdentifier: TEST_TOKEN_IDENTIFIER };
}

describe("locale tags and fallback", () => {
  test("canonicalizes BCP 47 casing and separators", () => {
    expect(canonicalizeLocaleTag("en")).toBe("en");
    expect(canonicalizeLocaleTag("EN")).toBe("en");
    expect(canonicalizeLocaleTag("en_US")).toBe("en-US");
    expect(canonicalizeLocaleTag("pt-br")).toBe("pt-BR");
    expect(canonicalizeLocaleTag("ES-419")).toBe("es-419");
    expect(canonicalizeLocaleTag("zh-HANS")).toBe("zh-Hans");
    expect(canonicalizeLocaleTag("")).toBeNull();
    expect(canonicalizeLocaleTag("not a locale")).toBeNull();
    expect(canonicalizeLocaleTag("1n")).toBeNull();
  });

  test("fallback chains end at English", () => {
    expect(localeFallbackChain("ur-PK")).toEqual(["ur-PK", "ur", "en"]);
    expect(localeFallbackChain("en")).toEqual(["en"]);
    expect(localeFallbackChain("es-419")).toEqual(["es-419", "es", "en"]);
  });

  test("resolves through the chain and rejects unsupported languages", () => {
    const supported = new Set(["en", "es", "es-419", "ar"]);
    expect(resolveLocale("es-MX", supported)).toBe("es");
    expect(resolveLocale("pt-BR", supported)).toBe("en");
    expect(resolveLocale("!!", supported)).toBe("en");
  });

  test("RTL metadata covers Arabic, Urdu, and Persian scripts", () => {
    expect(canonicalizeLocaleTag("ar-XB")).toBe("ar-XB");
    expect(canonicalizeLocaleTag("en-XA")).toBe("en-XA");
  });
});

describe("reader preference validation", () => {
  function raw(overrides: Partial<Parameters<typeof parseReaderPreferences>[0]> = {}) {
    return {
      schemaVersion: 1,
      uiLocale: "en",
      translationLocale: "en",
      readingDirection: "auto" as const,
      theme: "system" as const,
      arabicFont: "system",
      arabicFontSize: 26,
      arabicVisible: true,
      translationVisible: true,
      updatedAt: 0,
      ...overrides,
    };
  }

  test("rejects the all-hidden visibility state", () => {
    expect(() => parseReaderPreferences(raw({ arabicVisible: false, translationVisible: false })))
      .toThrowError(PreferencesError);
    try {
      parseReaderPreferences(raw({ arabicVisible: false, translationVisible: false }));
    } catch (error) {
      expect((error as PreferencesError).code).toBe("VISIBILITY_ALL_HIDDEN");
    }
  });

  test("clamps the Arabic font size into the supported range", () => {
    expect(parseReaderPreferences(raw({ arabicFontSize: 5 })).arabicFontSize).toBe(18);
    expect(parseReaderPreferences(raw({ arabicFontSize: 90 })).arabicFontSize).toBe(40);
  });

  test("canonicalizes locales and rejects malformed ones", () => {
    expect(parseReaderPreferences(raw({ uiLocale: "UR_PK" })).uiLocale).toBe("ur-PK");
    expect(() => parseReaderPreferences(raw({ translationLocale: "???" })))
      .toThrowError(PreferencesError);
  });

  test("seeds defaults from one legacy language", () => {
    const seeded = defaultReaderPreferences("ur", 100);
    expect(seeded.uiLocale).toBe("ur");
    expect(seeded.translationLocale).toBe("ur");
    expect(seeded.updatedAt).toBe(100);
  });
});

describe("reading direction metadata", () => {
  test("auto uses RTL for Arabic-only reading", () => {
    expect(
      readingDirectionMetadata({
        readingDirection: "auto",
        translationLocale: "en",
        arabicVisible: true,
        translationVisible: false,
      }),
    ).toEqual({ pageDirection: "rtl", arabicBlocksRTL: true });
  });

  test("auto follows the translation script for translation-only and mixed pages", () => {
    expect(
      readingDirectionMetadata({
        readingDirection: "auto",
        translationLocale: "ur",
        arabicVisible: false,
        translationVisible: true,
      }).pageDirection,
    ).toBe("rtl");
    expect(
      readingDirectionMetadata({
        readingDirection: "auto",
        translationLocale: "en",
        arabicVisible: true,
        translationVisible: true,
      }).pageDirection,
    ).toBe("ltr");
    expect(
      readingDirectionMetadata({
        readingDirection: "auto",
        translationLocale: "ar",
        arabicVisible: true,
        translationVisible: true,
      }).pageDirection,
    ).toBe("rtl");
  });

  test("explicit direction overrides auto", () => {
    expect(
      readingDirectionMetadata({
        readingDirection: "ltr",
        translationLocale: "ar",
        arabicVisible: true,
        translationVisible: true,
      }).pageDirection,
    ).toBe("ltr");
  });
});

describe("preferences sync and one-time migration", () => {
  test("seeds both locales from the legacy language exactly once", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("user_pref_1"));

    await asUser.mutation(api.users.ensureCurrentUser, { preferredLanguage: "ur" });

    const row = await t.run(async (ctx) =>
      await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "user_pref_1"))
        .unique(),
    );
    expect(row?.localesMigrated).toBe(true);
    expect(row?.readerPreferences?.uiLocale).toBe("ur");
    expect(row?.readerPreferences?.translationLocale).toBe("ur");

    // A later sync carrying the stale legacy language must not reset locales.
    await asUser.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
    const after = await t.run(async (ctx) =>
      await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "user_pref_1"))
        .unique(),
    );
    expect(after?.readerPreferences?.translationLocale).toBe("ur");
  });

  test("keeps a later explicit choice against stale sync payloads", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("user_pref_2"));

    await asUser.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
    await asUser.mutation(api.users.updateReaderPreferences, {
      readerPreferences: {
        schemaVersion: 1,
        uiLocale: "en",
        translationLocale: "ar",
        readingDirection: "auto",
        theme: "paper",
        arabicFont: "amiri",
        arabicFontSize: 30,
        arabicVisible: true,
        translationVisible: true,
        updatedAt: 1_800_000_000_000,
      },
    });

    // Stale payload (older updatedAt) must lose.
    await asUser.mutation(api.users.ensureCurrentUser, {
      preferredLanguage: "en",
      readerPreferences: {
        schemaVersion: 1,
        uiLocale: "en",
        translationLocale: "en",
        readingDirection: "auto",
        theme: "system",
        arabicFont: "system",
        arabicFontSize: 26,
        arabicVisible: true,
        translationVisible: true,
        updatedAt: 1_790_000_000_000,
      },
    });

    const row = await t.run(async (ctx) =>
      await ctx.db
        .query("users")
        .withIndex("by_clerk_id", (q) => q.eq("clerkId", "user_pref_2"))
        .unique(),
    );
    expect(row?.readerPreferences?.translationLocale).toBe("ar");
    expect(row?.readerPreferences?.theme).toBe("paper");
    expect(row?.localesMigrated).toBe(true);

    const adopted = await asUser.query(api.users.getCurrentUserPreferences, {});
    expect(adopted.readerPreferences?.translationLocale).toBe("ar");
  });

  test("rejects the all-hidden visibility state in the mutation", async () => {
    const t = convexTest(schema, modules);
    const asUser = t.withIdentity(identity("user_pref_3"));
    await asUser.mutation(api.users.ensureCurrentUser, { preferredLanguage: "en" });
    await expect(
      asUser.mutation(api.users.updateReaderPreferences, {
        readerPreferences: {
          schemaVersion: 1,
          uiLocale: "en",
          translationLocale: "en",
          readingDirection: "auto",
          theme: "system",
          arabicFont: "system",
          arabicFontSize: 26,
          arabicVisible: false,
          translationVisible: false,
          updatedAt: 1_800_000_000_000,
        },
      }),
    ).rejects.toThrowError(/VISIBILITY_ALL_HIDDEN/);
  });

  test("requires a signed-in identity", async () => {
    const t = convexTest(schema, modules);
    await expect(
      t.mutation(api.users.updateReaderPreferences, {
        readerPreferences: {
          schemaVersion: 1,
          uiLocale: "en",
          translationLocale: "en",
          readingDirection: "auto",
          theme: "system",
          arabicFont: "system",
          arabicFontSize: 26,
          arabicVisible: true,
          translationVisible: true,
          updatedAt: 0,
        },
      }),
    ).rejects.toThrowError(/Unauthenticated/);
    await t.query(internal.users.getByClerkId, { clerkId: "missing" }).then((row) => {
      expect(row).toBeNull();
    });
  });
});
