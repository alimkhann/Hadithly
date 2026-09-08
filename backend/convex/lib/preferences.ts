import { v } from "convex/values";

/**
 * Reader preference contracts (F2). Shared by both clients through the
 * `users` row. The wire shape is platform-neutral flat JSON.
 *
 * Locale rules (docs/PLAN.md): BCP 47 identifiers everywhere. UI fallback is
 * exact locale, base language, then English. A hadith translation never
 * changes language silently. Arabic, Urdu, and Persian scripts are RTL.
 */

export const READER_PREFERENCES_SCHEMA_VERSION = 1;

export const MIN_ARABIC_FONT_SIZE = 18;
export const MAX_ARABIC_FONT_SIZE = 40;

export const readingDirectionValidator = v.union(
  v.literal("auto"),
  v.literal("rtl"),
  v.literal("ltr"),
);

export const themeValidator = v.union(
  v.literal("system"),
  v.literal("light"),
  v.literal("paper"),
  v.literal("dark"),
);

/**
 * Arabic font identifiers. Known ids come from docs/FONT_LICENSES.md; the
 * server validates the shape, not the catalog, so older clients keep working
 * when newer ones add a licensed font. Clients map unknown ids to "system".
 */
export const arabicFontValidator = v.string();

export const readerPreferencesValidator = v.object({
  schemaVersion: v.literal(READER_PREFERENCES_SCHEMA_VERSION),
  uiLocale: v.string(),
  translationLocale: v.string(),
  readingDirection: readingDirectionValidator,
  theme: themeValidator,
  arabicFont: arabicFontValidator,
  arabicFontSize: v.number(),
  arabicVisible: v.boolean(),
  translationVisible: v.boolean(),
  updatedAt: v.number(),
});

export type ReaderPreferences = {
  schemaVersion: 1;
  uiLocale: string;
  translationLocale: string;
  readingDirection: "auto" | "rtl" | "ltr";
  theme: "system" | "light" | "paper" | "dark";
  arabicFont: string;
  arabicFontSize: number;
  arabicVisible: boolean;
  translationVisible: boolean;
  updatedAt: number;
};

export type PreferencesErrorCode =
  | "INVALID_LOCALE"
  | "INVALID_ARABIC_FONT"
  | "VISIBILITY_ALL_HIDDEN";

export class PreferencesError extends Error {
  readonly code: PreferencesErrorCode;

  constructor(code: PreferencesErrorCode, detail: string) {
    super(`${code}: ${detail}`);
    this.code = code;
    this.name = "PreferencesError";
  }
}

const LANGUAGE_TAG_PATTERN = /^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$/;
const ARABIC_FONT_ID_PATTERN = /^[A-Za-z0-9_-]{1,64}$/;

const RTL_BASE_LANGUAGES = new Set([
  "ar",
  "fa",
  "he",
  "ps",
  "sd",
  "ug",
  "ur",
  "yi",
  "ckb",
  "mzn",
  "sdh",
]);

/** Canonicalizes a BCP 47 tag: en → en, EN_us → en-US, pt-br → pt-BR.
 * Returns null for empty, malformed, or oversized input. */
export function canonicalizeLocaleTag(tag: string): string | null {
  const trimmed = tag.trim();
  if (!trimmed || trimmed.length > 35) return null;
  const parts = trimmed.split(/[-_]/);
  if (parts.length > 8) return null;
  const language = parts[0];
  if (!/^[A-Za-z]{2,3}$/.test(language)) return null;
  const canonical = [language.toLowerCase()];
  for (const part of parts.slice(1)) {
    if (part.length === 4 && /^[A-Za-z]{4}$/.test(part)) {
      canonical.push(part[0].toUpperCase() + part.slice(1).toLowerCase());
    } else if (part.length === 2 && /^[A-Za-z]{2}$/.test(part)) {
      canonical.push(part.toUpperCase());
    } else if (/^[A-Za-z0-9]{2,8}$/.test(part)) {
      canonical.push(part.toLowerCase());
    } else {
      return null;
    }
  }
  const joined = canonical.join("-");
  return LANGUAGE_TAG_PATTERN.test(joined) ? joined : null;
}

/** Fallback chain: exact locale, base language, then English. */
export function localeFallbackChain(tag: string): string[] {
  const canonical = canonicalizeLocaleTag(tag);
  if (canonical === null) return ["en"];
  const base = canonical.split("-")[0];
  const chain = canonical === base ? [canonical] : [canonical, base];
  if (!chain.includes("en")) chain.push("en");
  return chain;
}

/** First entry of the chain that is in `supported`, or null. */
export function resolveLocale(
  tag: string,
  supported: ReadonlySet<string>,
): string | null {
  for (const candidate of localeFallbackChain(tag)) {
    if (supported.has(candidate)) return candidate;
  }
  return null;
}

/** The base language of a canonical or non-canonical BCP 47 tag. */
export function baseLanguage(tag: string): string {
  const canonical = canonicalizeLocaleTag(tag);
  return (canonical ?? tag).split(/[-_]/)[0].toLowerCase();
}

export function isRTLLocale(tag: string): boolean {
  return RTL_BASE_LANGUAGES.has(baseLanguage(tag));
}

/**
 * Resolves the reading direction metadata. `auto` uses RTL for Arabic-only
 * reading, the translation script for translation-only reading, and the
 * translation language for mixed pages. Arabic blocks always stay RTL.
 */
export function readingDirectionMetadata(preferences: {
  readingDirection: "auto" | "rtl" | "ltr";
  translationLocale: string;
  arabicVisible: boolean;
  translationVisible: boolean;
}): { pageDirection: "rtl" | "ltr"; arabicBlocksRTL: true } {
  if (preferences.readingDirection === "rtl") {
    return { pageDirection: "rtl", arabicBlocksRTL: true };
  }
  if (preferences.readingDirection === "ltr") {
    return { pageDirection: "ltr", arabicBlocksRTL: true };
  }
  const arabicOnly = preferences.arabicVisible && !preferences.translationVisible;
  const pageDirection = !arabicOnly && isRTLLocale(preferences.translationLocale)
    ? "rtl"
    : "ltr";
  if (arabicOnly) {
    return { pageDirection: "rtl", arabicBlocksRTL: true };
  }
  return { pageDirection, arabicBlocksRTL: true };
}

/** Normalizes and validates one reader preference object at the boundary. */
export function parseReaderPreferences(raw: {
  schemaVersion: number;
  uiLocale: string;
  translationLocale: string;
  readingDirection: "auto" | "rtl" | "ltr";
  theme: "system" | "light" | "paper" | "dark";
  arabicFont: string;
  arabicFontSize: number;
  arabicVisible: boolean;
  translationVisible: boolean;
  updatedAt: number;
}): ReaderPreferences {
  const uiLocale = canonicalizeLocaleTag(raw.uiLocale);
  const translationLocale = canonicalizeLocaleTag(raw.translationLocale);
  if (uiLocale === null) {
    throw new PreferencesError("INVALID_LOCALE", `uiLocale "${raw.uiLocale}"`);
  }
  if (translationLocale === null) {
    throw new PreferencesError(
      "INVALID_LOCALE",
      `translationLocale "${raw.translationLocale}"`,
    );
  }
  if (!ARABIC_FONT_ID_PATTERN.test(raw.arabicFont)) {
    throw new PreferencesError(
      "INVALID_ARABIC_FONT",
      `arabicFont "${raw.arabicFont}"`,
    );
  }
  if (!raw.arabicVisible && !raw.translationVisible) {
    throw new PreferencesError(
      "VISIBILITY_ALL_HIDDEN",
      "Arabic and translation visibility cannot both be disabled",
    );
  }
  const fontSize = Math.min(
    MAX_ARABIC_FONT_SIZE,
    Math.max(MIN_ARABIC_FONT_SIZE, raw.arabicFontSize),
  );
  return {
    schemaVersion: READER_PREFERENCES_SCHEMA_VERSION,
    uiLocale,
    translationLocale,
    readingDirection: raw.readingDirection,
    theme: raw.theme,
    arabicFont: raw.arabicFont,
    arabicFontSize: fontSize,
    arabicVisible: raw.arabicVisible,
    translationVisible: raw.translationVisible,
    updatedAt: raw.updatedAt,
  };
}

/** Default preference object seeded from one legacy language tag. */
export function defaultReaderPreferences(
  localeTag: string,
  updatedAt: number,
): ReaderPreferences {
  const locale = canonicalizeLocaleTag(localeTag) ?? "en";
  return {
    schemaVersion: READER_PREFERENCES_SCHEMA_VERSION,
    uiLocale: locale,
    translationLocale: locale,
    readingDirection: "auto",
    theme: "system",
    arabicFont: "system",
    arabicFontSize: 26,
    arabicVisible: true,
    translationVisible: true,
    updatedAt,
  };
}
