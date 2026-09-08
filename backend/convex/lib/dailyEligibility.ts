import type { AuthenticityClaim } from "./contentPolicy";

export function isDailyEligible(claim: AuthenticityClaim | undefined): boolean {
  if (!claim) return false;
  switch (claim.kind) {
    case "hadith_grade":
      return (
        claim.verificationMethod === "source_provided" &&
        (claim.normalizedGrade === "sahih" || claim.normalizedGrade === "hasan")
      );
    case "collection_scope":
      return (
        claim.verificationMethod === "manual_collection_mapping" &&
        claim.normalizedGrade === "sahih"
      );
    case "unverified":
      return false;
    default: {
      const exhaustive: never = claim;
      return exhaustive;
    }
  }
}

export function chooseDailyCandidate<
  T extends { canonicalId: string; authenticity?: AuthenticityClaim },
>(items: T[], localDate: string): T | null {
  const eligible = items
    .filter((item) => isDailyEligible(item.authenticity))
    .sort((left, right) => left.canonicalId.localeCompare(right.canonicalId));
  if (eligible.length === 0) return null;
  return eligible[dateHash(localDate) % eligible.length] ?? null;
}

export function dailyCollectionOrder<T>(
  collections: readonly T[],
  localDate: string,
): T[] {
  if (collections.length === 0) return [];
  const offset = dateHash(localDate) % collections.length;
  return [
    ...collections.slice(offset),
    ...collections.slice(0, offset),
  ];
}

export function localDateInTimezone(nowMs: number, timezone: string): string {
  if (!Number.isFinite(nowMs)) throw new Error("Invalid instant");
  let formatter: Intl.DateTimeFormat;
  try {
    formatter = new Intl.DateTimeFormat("en-CA", {
      timeZone: timezone,
      year: "numeric",
      month: "2-digit",
      day: "2-digit",
    });
  } catch {
    throw new Error(`Invalid IANA timezone: ${timezone}`);
  }

  const parts: Record<string, string> = {};
  for (const part of formatter.formatToParts(new Date(nowMs))) {
    if (part.type === "year" || part.type === "month" || part.type === "day") {
      parts[part.type] = part.value;
    }
  }
  if (!parts.year || !parts.month || !parts.day) {
    throw new Error(`Could not resolve local date for timezone: ${timezone}`);
  }
  return `${parts.year}-${parts.month}-${parts.day}`;
}

function dateHash(date: string): number {
  let hash = 0;
  for (let index = 0; index < date.length; index += 1) {
    hash = (hash * 31 + date.charCodeAt(index)) >>> 0;
  }
  return hash;
}
