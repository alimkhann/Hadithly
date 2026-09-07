/**
 * Canonical hadith link contracts (F3).
 *
 * The canonical URL is `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}`
 * with optional `?locale=<BCP 47>&pos=v<contentVersion>` query parameters.
 * Parsing and validation live here as pure functions; every surface that
 * touches an inbound link (web fallback, iOS Universal Links, Android App
 * Links) validates at its own boundary before any backend data is touched.
 */

import { canonicalizeLocaleTag } from "./preferences";

export const CANONICAL_LINK_HOST = "hadithly.app";
export const CANONICAL_LINK_PATH_PREFIX = "/hadith/";

/**
 * Collection slugs are lowercase kebab-case, at least two characters. The
 * seven supported collections (bukhari, muslim, …) all satisfy this.
 */
export const COLLECTION_SLUG_PATTERN = /^[a-z][a-z0-9-]{1,31}$/;

/**
 * Provider hadith ids are provider-assigned numbers ("57") or dotted
 * sub-references ("4.5"). Dots never lead, trail, or stack, and zero is
 * not a provider id.
 */
export const PROVIDER_HADITH_ID_PATTERN = /^[1-9][0-9]{0,11}(\.[0-9]{1,12})*$/;

/**
 * The optional versioned-position parameter. F3 accepts a content-version
 * tag (`pos=v3`); a missing, malformed, or unknown version degrades to the
 * hadith start, never an error. R2 extends this with semantic anchors.
 */
export const POSITION_VERSION_PATTERN = /^v[0-9]{1,12}$/;

/** A resolved canonical path, or null when the link is malformed. */
export type ParsedCanonicalHadithPath = {
  collectionSlug: string;
  providerHadithId: string;
} | null;

/**
 * Parses the canonical path `/hadith/{collectionSlug}/{providerHadithId}`.
 * Rejects extra segments, a bare collection, empty ids, and unknown shapes.
 * A trailing slash is tolerated; everything else is malformed.
 */
export function parseCanonicalHadithPath(
  path: string,
): ParsedCanonicalHadithPath {
  const trimmed = path.endsWith("/") ? path.slice(0, -1) : path;
  if (!trimmed.startsWith(CANONICAL_LINK_PATH_PREFIX)) return null;
  const segments = trimmed
    .slice(CANONICAL_LINK_PATH_PREFIX.length)
    .split("/");
  if (segments.length !== 2) return null;
  const [collectionSlug, providerHadithId] = segments;
  if (!COLLECTION_SLUG_PATTERN.test(collectionSlug)) return null;
  if (!PROVIDER_HADITH_ID_PATTERN.test(providerHadithId)) return null;
  return { collectionSlug, providerHadithId };
}

/**
 * Parses a full canonical URL and validates the host. Used by the native
 * link routers, which must never act on a link from another host.
 */
export function parseCanonicalLink(
  url: string,
): ParsedCanonicalHadithPath {
  let parsed: URL;
  try {
    parsed = new URL(url);
  } catch {
    return null;
  }
  if (parsed.protocol !== "https:") return null;
  if (parsed.hostname !== CANONICAL_LINK_HOST) return null;
  if (parsed.pathname.includes("%")) return null;
  return parseCanonicalHadithPath(parsed.pathname);
}

/**
 * Normalizes the optional translation-locale parameter. Returns the
 * canonical BCP 47 tag, or null when absent/malformed — a hadith
 * translation never changes language silently, so an unsupported locale
 * degrades to the provider English text with a fallback label. Delegates
 * to the shared F2 tag canonicalizer so the contract has one owner.
 */
export function canonicalLocaleParam(raw: string | undefined | null): {
  requested: boolean;
  locale: string | null;
} {
  if (raw === undefined || raw === null || raw.length === 0) {
    return { requested: false, locale: null };
  }
  return { requested: true, locale: canonicalizeLocaleTag(raw) };
}

/**
 * Normalizes the optional versioned-position parameter. Returns the
 * content-version number when the tag is well-formed, null otherwise.
 * F3 always resolves the link to the hadith start; the validated version
 * tag exists so stale or future-positioned links degrade predictably.
 */
export function canonicalPositionParam(
  raw: string | undefined | null,
): number | null {
  if (raw === undefined || raw === null) return null;
  if (!POSITION_VERSION_PATTERN.test(raw)) return null;
  const version = Number(raw.slice(1));
  return Number.isSafeInteger(version) ? version : null;
}
