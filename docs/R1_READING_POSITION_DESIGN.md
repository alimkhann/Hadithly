# R1 reading-position design

## Problem

The existing progress row points at a Convex hadith row and cannot prove that its page or offset still describes the current content and layout. R1 must keep those rows readable while making provider identity the durable location.

## Usage

The reader captures one `ReadingPosition` from page metadata, the visible hadith, the current layout inputs, and a timestamp. `UserLibraryModel` saves that value to Convex or guest storage. R2 will pass a stored position and current page topology to `resolveReadingPosition`, then apply the returned raw or semantic target.

## Shape

```text
ReadingPosition V1
  schemaVersion: 1
  anchor: provider + collectionSlug + providerHadithId
  contentVersion: opaque content digest
  volumeId, optional chapterId
  pageKey, displayPageIndex, rawPageOffset
  normalizedOffset
  layoutSignature
  updatedAt
```

All numeric wire values are doubles. Display pages are one-based. Raw offsets use logical points or dp and are only hints. The normalized offset is clamped to the closed interval from zero to one.

The existing `readingProgress` row gains an optional `position`. Its `hadithId`, `bookId`, `scrollOffset`, and `updatedAt` remain during the compatibility window and are derived from every accepted V1 write. Reads prefer V1 and otherwise synthesize a legacy position. A bounded migration materializes the same conversion without deleting legacy fields.

`actions/hadithData:getReaderPage` returns a content digest, pagination version, and page key. The content digest covers ordered provider identity, chapter identity, and source text. The page key covers content version, pagination version, volume, and ordered anchors.

The resolver uses the raw hint only when content version, layout signature, display page, page key, and exact anchor all match. Otherwise it finds the exact semantic anchor and keeps its normalized offset. If the anchor disappeared, it selects the nearest dotted-decimal provider ID within the same provider and collection, preferring the stored volume and chapter when possible, and resets the offset to zero.

Newer `updatedAt` wins per collection. Equal timestamps never overwrite an existing row, which makes exact retries no-ops. Guest stores apply the same rule before merge.

## Synthesis decision

The embedded-row candidate is the base because `readingProgress` already owns one latest position per user and collection. A separate table would create two authoritative stores and a permanent reconciliation path. The chosen design takes the separate-table candidate's stricter raw-hint check, nearest-anchor rule, deferred legacy handling, and cross-platform golden vectors. It rejects a second table, UUID write identifiers, a new subscription, and translation-size inputs that the current preference contract does not own.

## Tradeoffs accepted

- We keep a temporary legacy projection in exchange for compatibility with deployed clients.
- We mirror the pure resolver in Swift and Kotlin in exchange for guest and offline restoration.
- We use client timestamps for offline merge, so a badly skewed device clock can delay later writes.
- Migrated legacy rows use semantic restoration at offset zero because their old pixel offsets have no trustworthy layout signature.

## Alternatives considered

A separate `readingPositions` table isolates the new schema but forces every read, write, deletion, and migration to reconcile two stores. An append-only event stream records conflicts but adds compaction for a domain that only needs the latest private position. Storing only an anchor removes the required fast landing, while storing only page and offset cannot recover after layout changes.

## Open risks

O1 may replace the current content digest with a manifest version. The contract treats it as opaque so that change does not alter clients. Any future provider whose IDs are not dotted decimal needs an explicit ordering adapter before it can participate in nearest-anchor fallback.

## Next implementation step

Add failing backend, Swift, and Kotlin tests for V1 round trips, legacy conversion, version changes, missing anchors, latest-wins writes, and guest merge.
