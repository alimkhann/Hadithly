import { v } from "convex/values";
import { providerValidator } from "./contentPolicy";
import type { HadithProviderName } from "./contentPolicy";

export const READING_POSITION_SCHEMA_VERSION = 1;
export const READER_PAGINATION_VERSION = 1;

export const readingPositionAnchorValidator = v.object({
  provider: providerValidator,
  collectionSlug: v.string(),
  providerHadithId: v.string(),
});

export const readingPositionValidator = v.object({
  schemaVersion: v.literal(READING_POSITION_SCHEMA_VERSION),
  anchor: readingPositionAnchorValidator,
  contentVersion: v.string(),
  volumeId: v.string(),
  chapterId: v.optional(v.string()),
  pageKey: v.string(),
  displayPageIndex: v.number(),
  rawPageOffset: v.number(),
  normalizedOffset: v.number(),
  layoutSignature: v.string(),
  updatedAt: v.number(),
});

export type ReadingPositionAnchor = {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
};

export type ReadingPosition = {
  schemaVersion: 1;
  anchor: ReadingPositionAnchor;
  contentVersion: string;
  volumeId: string;
  chapterId?: string;
  pageKey: string;
  displayPageIndex: number;
  rawPageOffset: number;
  normalizedOffset: number;
  layoutSignature: string;
  updatedAt: number;
};

export type ReadingPositionAnchorLocation = {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
  volumeId: string;
  chapterId?: string;
};

export type ReadingPositionPage = {
  pageKey: string;
  displayPageIndex: number;
  anchors: ReadingPositionAnchorLocation[];
};

export type ReadingPositionTopology = {
  contentVersion: string;
  layoutSignature: string;
  pages: ReadingPositionPage[];
};

export type ReadingPositionResolution = {
  kind: "raw" | "semantic" | "nearest" | "unavailable";
  anchor: ReadingPositionAnchor | null;
  volumeId: string | null;
  chapterId?: string;
  pageKey: string | null;
  displayPageIndex: number;
  rawPageOffset: number;
  normalizedOffset: number;
};

export class ReadingPositionError extends Error {
  constructor(detail: string) {
    super(`INVALID_READING_POSITION: ${detail}`);
    this.name = "ReadingPositionError";
  }
}

const COLLECTION_SLUG_PATTERN = /^[a-z][a-z0-9-]{1,31}$/;
// Provider data contains reference 0 even though canonical public URLs start
// at 1. Positions follow provider identity, not the stricter URL grammar.
const PROVIDER_HADITH_ID_PATTERN = /^[0-9]{1,12}(\.[0-9]{1,12})*$/;
const VERSION_PATTERN = /^(?:cv1:[A-Za-z0-9._:-]{1,128}|legacy)$/;
const PAGE_KEY_PATTERN = /^(?:pg1:[A-Za-z0-9._:-]{1,160}|legacy)$/;
const LAYOUT_SIGNATURE_PATTERN = /^(?:ls1:[A-Za-z0-9._:-]{1,160}|legacy)$/;
const CONTEXT_ID_PATTERN = /^[A-Za-z0-9._:-]{1,128}$/;

/** Convex validates the field types. This function validates domain ranges and grammars. */
export function parseReadingPosition(raw: ReadingPosition): ReadingPosition {
  if (raw.schemaVersion !== READING_POSITION_SCHEMA_VERSION) {
    throw new ReadingPositionError("unsupported schemaVersion");
  }
  if (!COLLECTION_SLUG_PATTERN.test(raw.anchor.collectionSlug)) {
    throw new ReadingPositionError("invalid collectionSlug");
  }
  if (!PROVIDER_HADITH_ID_PATTERN.test(raw.anchor.providerHadithId)) {
    throw new ReadingPositionError("invalid providerHadithId");
  }
  if (!VERSION_PATTERN.test(raw.contentVersion)) {
    throw new ReadingPositionError("invalid contentVersion");
  }
  if (!CONTEXT_ID_PATTERN.test(raw.volumeId)) {
    throw new ReadingPositionError("invalid volumeId");
  }
  if (raw.chapterId !== undefined && !CONTEXT_ID_PATTERN.test(raw.chapterId)) {
    throw new ReadingPositionError("invalid chapterId");
  }
  if (!PAGE_KEY_PATTERN.test(raw.pageKey)) {
    throw new ReadingPositionError("invalid pageKey");
  }
  if (!LAYOUT_SIGNATURE_PATTERN.test(raw.layoutSignature)) {
    throw new ReadingPositionError("invalid layoutSignature");
  }
  if (!isIntegerAtLeast(raw.displayPageIndex, 1)) {
    throw new ReadingPositionError("displayPageIndex must be a positive integer");
  }
  if (!isFiniteAtLeast(raw.rawPageOffset, 0)) {
    throw new ReadingPositionError("rawPageOffset must be non-negative");
  }
  if (!Number.isFinite(raw.normalizedOffset) || raw.normalizedOffset < 0 || raw.normalizedOffset > 1) {
    throw new ReadingPositionError("normalizedOffset must be between zero and one");
  }
  if (!isFiniteAtLeast(raw.updatedAt, 0)) {
    throw new ReadingPositionError("updatedAt must be non-negative");
  }
  return raw;
}

function isFiniteAtLeast(value: number, minimum: number): boolean {
  return Number.isFinite(value) && value >= minimum;
}

function isIntegerAtLeast(value: number, minimum: number): boolean {
  return Number.isInteger(value) && value >= minimum;
}

export function legacyReadingPosition(args: {
  provider: HadithProviderName;
  collectionSlug: string;
  providerHadithId: string;
  volumeId: string;
  chapterId?: string;
  updatedAt: number;
}): ReadingPosition {
  return parseReadingPosition({
    schemaVersion: READING_POSITION_SCHEMA_VERSION,
    anchor: {
      provider: args.provider,
      collectionSlug: args.collectionSlug,
      providerHadithId: args.providerHadithId,
    },
    contentVersion: "legacy",
    volumeId: args.volumeId,
    ...(args.chapterId === undefined ? {} : { chapterId: args.chapterId }),
    pageKey: "legacy",
    displayPageIndex: 1,
    rawPageOffset: 0,
    normalizedOffset: 0,
    layoutSignature: "legacy",
    updatedAt: args.updatedAt,
  });
}

type LocatedAnchor = ReadingPositionAnchorLocation & {
  pageKey: string;
  displayPageIndex: number;
  itemIndex: number;
};

/** Pure, mirrored resolver used by R2 on both clients. */
export function resolveReadingPosition(
  position: ReadingPosition,
  topology: ReadingPositionTopology,
): ReadingPositionResolution {
  const all = topology.pages.flatMap((page) =>
    page.anchors.map((anchor, itemIndex) => ({
      ...anchor,
      pageKey: page.pageKey,
      displayPageIndex: page.displayPageIndex,
      itemIndex,
    })),
  );
  const candidates = all.filter((candidate) =>
    candidate.provider === position.anchor.provider &&
    candidate.collectionSlug === position.anchor.collectionSlug
  );
  const exact = candidates.find((candidate) => anchorsEqual(candidate, position.anchor));

  if (exact) {
    const rawPageMatches =
      exact.pageKey === position.pageKey &&
      exact.displayPageIndex === position.displayPageIndex;
    if (
      topology.contentVersion === position.contentVersion &&
      topology.layoutSignature === position.layoutSignature &&
      rawPageMatches
    ) {
      return resolved("raw", exact, position.rawPageOffset, position.normalizedOffset);
    }
    return resolved("semantic", exact, 0, position.normalizedOffset);
  }

  if (candidates.length === 0) {
    return {
      kind: "unavailable",
      anchor: null,
      volumeId: null,
      pageKey: null,
      displayPageIndex: 1,
      rawPageOffset: 0,
      normalizedOffset: 0,
    };
  }

  let preferred = candidates;
  const sameVolume = preferred.filter((candidate) => candidate.volumeId === position.volumeId);
  if (sameVolume.length > 0) preferred = sameVolume;
  if (position.chapterId !== undefined) {
    const sameChapter = preferred.filter((candidate) => candidate.chapterId === position.chapterId);
    if (sameChapter.length > 0) preferred = sameChapter;
  }
  const nearest = [...preferred].sort((left, right) =>
    compareDistance(position.anchor.providerHadithId, left, right)
  )[0];
  return resolved("nearest", nearest, 0, 0);
}

function resolved(
  kind: "raw" | "semantic" | "nearest",
  location: LocatedAnchor,
  rawPageOffset: number,
  normalizedOffset: number,
): ReadingPositionResolution {
  return {
    kind,
    anchor: {
      provider: location.provider,
      collectionSlug: location.collectionSlug,
      providerHadithId: location.providerHadithId,
    },
    volumeId: location.volumeId,
    ...(location.chapterId === undefined ? {} : { chapterId: location.chapterId }),
    pageKey: location.pageKey,
    displayPageIndex: location.displayPageIndex,
    rawPageOffset,
    normalizedOffset,
  };
}

function anchorsEqual(
  left: ReadingPositionAnchorLocation,
  right: ReadingPositionAnchor,
): boolean {
  return left.provider === right.provider &&
    left.collectionSlug === right.collectionSlug &&
    left.providerHadithId === right.providerHadithId;
}

function compareDistance(
  targetId: string,
  left: LocatedAnchor,
  right: LocatedAnchor,
): number {
  const target = providerIdSegments(targetId);
  const leftSegments = providerIdSegments(left.providerHadithId);
  const rightSegments = providerIdSegments(right.providerHadithId);
  if (target === null) return compareLocated(left, right);
  if (leftSegments === null || rightSegments === null) {
    if (leftSegments !== null) return -1;
    if (rightSegments !== null) return 1;
    return compareLocated(left, right);
  }
  const width = Math.max(target.length, leftSegments.length, rightSegments.length);
  for (let index = 0; index < width; index += 1) {
    const targetPart = target[index] ?? 0;
    const leftDistance = Math.abs((leftSegments[index] ?? 0) - targetPart);
    const rightDistance = Math.abs((rightSegments[index] ?? 0) - targetPart);
    if (leftDistance !== rightDistance) return leftDistance - rightDistance;
  }
  const providerOrder = compareProviderIds(leftSegments, rightSegments);
  if (providerOrder !== 0) return providerOrder;
  return compareLocated(left, right);
}

function compareLocated(left: LocatedAnchor, right: LocatedAnchor): number {
  if (left.providerHadithId !== right.providerHadithId) {
    return left.providerHadithId < right.providerHadithId ? -1 : 1;
  }
  if (left.displayPageIndex !== right.displayPageIndex) {
    return left.displayPageIndex - right.displayPageIndex;
  }
  return left.itemIndex - right.itemIndex;
}

function providerIdSegments(value: string): number[] | null {
  if (!PROVIDER_HADITH_ID_PATTERN.test(value)) return null;
  return value.split(".").map((part) => Number(part));
}

function compareProviderIds(left: number[], right: number[]): number {
  const width = Math.max(left.length, right.length);
  for (let index = 0; index < width; index += 1) {
    const difference = (left[index] ?? 0) - (right[index] ?? 0);
    if (difference !== 0) return difference;
  }
  return left.length - right.length;
}
