# Candidate A: bounded private fact pages, assembled behind the native Saved data layer

## Usage (written first)

Production feature callers keep a single `savedChanges()` stream of **complete** owned snapshots. The feature model never sees source phases, Convex cursors, legacy merge order, or partial rows:

```swift
reads.savedChanges().sink { complete in
    guard capturedSessionStillMatches(), complete.owner == owner else { return }
    try store.installCompleteSavedRevision(complete)
    sync.wake()
}
```

```kotlin
reads.savedChanges().collect { complete ->
    ensureCapturedSessionStillMatches()
    store.installCompleteSavedRevision(complete)
    sync.wake()
}
```

The data-layer implementation, not either feature model, consumes one opaque continuation repeatedly. It writes staged facts to an owner/session/assembly-specific row store, merges canonical and legacy facts there, and publishes only after a terminal, revision-checked completion. A cancellation or restart discards just that assembly; the last complete snapshot stays usable and no new version crosses the Saved overlay/manifest settlement barrier.

```ts
// Backend first slice: real bounded source/fact pages; existing savedSnapshot stays.
const first = await client.query(api.librarySync.savedFactsPage, { capability });
if (first.kind === "page") {
  // future native assembler owns this loop and durable staging
  const next = await client.query(api.librarySync.savedFactsPage, {
    capability, continuation: first.continuation,
  });
}
```

`complete private facts` must not be confused with a complete rendering snapshot: the current baseline also joins canonical hadith text/existence, which has no owner Saved clock. This is an explicit integration boundary below.

## Problem and grounding

`backend/convex/library.ts:794` `readSavedSnapshot` currently collects five owner tables before any merge: savedItems, savedFolders, bookmarks, favorites, notes. A `Map` keyed by hadith combines them and `hadithSummary` (`library.ts:968`) does a full canonical document get per unique hadith. `librarySync.ts:385` wraps this with owner/version and strips to `syncSavedSnapshot` (`lib/librarySyncPolicy.ts:216`). Pagination over that resulting array would retain the original whole-read defect. Calling the old per-hadith materializer is also unsuitable because it collects legacy duplicates.

The exact baseline is asymmetric and must be preserved, including asymmetries that look accidental: canonical item wins initialization; bookmarks and favorites take earliest creation across all duplicate rows, update aggregate createdAt minimum, but do not otherwise advance aggregate updatedAt; newest note by strict `>` replaces note fields, aggregate createdAt is minimum and updatedAt maximum. Canonical note wins equal timestamp against legacy; equal legacy notes keep the first encountered row in the existing index order. Folders sort ascending createdAt; items sort descending aggregate updatedAt. Canonical target absence removes the final item, not the private input fact. Legacy-only rows initialize their own createdAt/updatedAt from the first encountered source row. Ordering tie behavior must be explicitly preserved with source ordinal, not assumed from hash-map iteration.

`effectiveSavedMembership` (`lib/savedMembership.ts`) hides a bounded dependency graph: an optional staged manifest and its destination folder, then current folder or owner membership tombstone. It checks ownership before following staged/public folder visibility. Maximum work is a fixed number of direct gets/index-unique lookups per item, not member enumeration. Materialization may change physical rows without changing visible membership; emit its **effective** membership in private facts, never raw folderStage.

Native `UserLibraryModel.swift:448` and `UserLibraryModel.kt:320` currently consume complete subscriptions. `GuestDataStore.swift:538`/`GuestStore.kt:462` replace the full cached snapshot and prune confirmed overlays in the same persistent partition operation. Therefore passing any page to those methods would falsely declare completeness and retire effects early. Existing whole-partition storage itself remains a separate scale gate.

`users.ts:190` export contains many additional tables and raw details; this endpoint does not become a paginated export by virtue of sharing Saved facts.

## Shape

### One public server capability

```ts
type SavedFactsRequest = { capability: string; continuation?: string };
type SavedFactsReply =
  | { kind: "page"; ownerKey: string; savedVersion: number;
      facts: readonly SavedFact[]; continuation: string }
  | { kind: "complete"; ownerKey: string; savedVersion: number;
      facts: readonly SavedFact[]; completion: string }
  | { kind: "restart"; reason: "saved_changed" }
  | { kind: "unavailable"; reason: "source_row_too_large" | "invalid_source" };

type SavedFact =
  | { kind: "folder"; sourceId: string; ordinal: number;
      value: { id: string; name: string; createdAt: number } }
  | { kind: "item"; sourceId: string; ordinal: number;
      value: CanonicalPrivateItemWithEffectiveMembership }
  | { kind: "bookmark" | "favorite"; sourceId: string; ordinal: number;
      value: { hadithId: string; createdAt: number } }
  | { kind: "note"; sourceId: string; ordinal: number;
      value: { hadithId: string; content: string; createdAt: number; updatedAt: number } };
```

Actual validators live with the other librarySync wire validators; Infer generates TS and the existing native wire generator generates native DTOs once consumed. Domain assembler types remain behind native `savedChanges()`, not feature-layer copies of DTOs.

One private module `lib/librarySavedFacts.ts` owns phase ordering, budgets, opaque continuations and effective membership. `librarySync.ts` resolves JWT plus existing capability, invokes it, and enforces actual response bytes. No source-selection arguments or supplied owner identity. No per-account snapshot-copy tables.

Use fixed source order folders -> savedItems -> bookmarks -> favorites -> notes. Each phase uses the existing user-prefix index; notes uses by_user_hadith with the user prefix, preserving its existing encounter order. Each query performs **one paginate call**, never collect, never per-hadith legacy fanout. For the first truthful implementation, `numItems:1`, `maximumRowsRead:1`, an explicit byte cap, and zero `.filter()` predicates. Empty/split pages must advance using returned continuation and may contain no facts; an intermediate phase completion is not overall completion. Multiple source phases must not be read using independent pagination calls inside one Convex query.

A single-row limit is intentional first proof for a server capability with no production native cutover. Thousands of serial round trips would not be a usable final Saved experience; native rollout requires measured bounded multirow throughput or a revised shape, rather than declaring this first slice product-ready. Once measured source-byte bounds are proven, batches can increase without changing the contract. Do not infer `numItems` alone is a hard execution bound: installed Convex SDK pagination docs explicitly say it is an initial value and support maximumRowsRead/maximumBytesRead (`backend/node_modules/convex/src/server/pagination.ts:68-121`).

### Cursor binding and completeness

Continuation payload includes protocol version, binding ID, verified owner ID, captured Saved version, source phase, source cursor and next ordinal. Encode length limits and validate before invoking database pagination. To make owner/source/query/cursor tampering rejection deterministic, sign the payload with a **server-private random per-binding cursor key**, stored as an optional field on the existing short-lived librarySyncBinding row so old bindings remain schema-valid. Generate it locally when creating bindings; no external credential service is required. It must not be the client-visible capability or its digest (the client can derive the latter). This is a bounded field addition on existing bindings; old rows can return a clear reopen-binding requirement rather than a fake key fallback. The key must never be returned or exported.

This is genuinely stateless per assembly: no mutable read-session progress or snapshot copies, and each valid continuation may be replayed. Queries verify JWT ownership, binding expiry and signature, then check current Saved version equals captured version in the **same transaction** as page reads. Same binding/version/input returns same source fact projection provided visible semantics are unchanged. Cross-owner/source altered cursors fail before source traversal. Session swap/expiry fails without publishing. Future native assembler records previous cursor/ordinal and rejects skipped, duplicated, mismatched-owner/version facts or completion against another assembly.

The signed final completion proves traversal reached terminal source under that Saved revision, not that the client persisted it. Native durable install remains the only event that allows receipt/outcome settling. Replayed earlier pages overwrite their source-ID/ordinal stage entries idempotently; they do not append duplicate merged facts.

### Read and wire budgets, including one oversized document

There is no database projection get in the current code, so reading a small public summary from a hadith, note, or savedItem still reads the entire document. Do not claim a 64 KiB *read* ceiling merely because the response is 64 KiB. Separate:

- one primary source document per call;
- at most the fixed effective-membership dependency reads plus binding/user/version lookups;
- source pagination maximumRowsRead=1 and maximumBytesRead explicitly set;
- predeclared worst-case document-read budget that includes a whole legal single source/dependency document, measured with actual SDK/local platform behavior;
- UTF-8 serialized response <=64 KiB, including envelope and continuation;
- request and continuation byte limits fixed before parsing/lookup.

One note, folder name or canonical private item can exceed the wire budget. Return `unavailable(source_row_too_large)` with no continuation/completion advancement and no value or snippet, never truncate, silently omit, or keep trying an empty page forever. This is honest unavailability; supporting arbitrary legal near-platform-limit row content later needs chunked scalar transport, which is a separate contract. A malformed owner source row similarly fails the assembly rather than discarding it as though complete. Owner-mismatched dependency pointers remain ineffective under current membership semantics and never reveal dependency data.

If the installed backend cannot hard-bound the first oversized document below its runtime transaction ceiling, this contract must document the legal-document-size worst case, not pretend maximumBytesRead prevents a single crossing row. Tests must exercise that boundary.

## Canonical corpus is a separate clock

Private fact pages deliberately do **zero hadith gets**. Saved facts are authoritative private data, including facts whose hadith is currently missing. This avoids duplicate per-hadith reads and does not invent whole-corpus consistency.

The actual current sync wire (`syncHadithSummary`) excludes provider, canonicalId and chapterId, despite the richer intermediate library summary. Preserve the sync wire, not the intermediate shape.

A future native assembler cannot yet reproduce the old complete `SyncSavedSnapshot` atomically using only savedVersion. Canonical changes are outside that clock: actual writes are in `hadiths.ts:100,112`, migrations (`migrations.ts:42,88`), and development fixture writes/deletion (`e3Verification.ts:18,89`). Canonical IDs, text, reference and target existence can change while private Saved remains unchanged. Per-hadith `sourceUpdatedAt` is optional and insufficient to detect deletion or rows not yet scanned.

Before switching native production subscriptions, choose and prove one of these explicit contracts:

1. **Exact old atomic join parity:** add a corpus revision touched by every canonical mutation/delete, capture `{saved,corpus}` on every page and bounded canonical-summary hydration request, and final check both. Hydrate each unique hadith once from staged private IDs, bounded by both input and document reads. Missing target is a recorded result. A canonical mutation midassembly restarts all hydration. This is my recommended future integration if the old complete DTO is retained.
2. **Deliberately independent content cache:** make the private complete snapshot contain no summary, resolve hadith existence/text independently with explicit content freshness semantics and update feature data types/barriers accordingly. That is a product/data-model migration, not a quiet fallback to a mixed old DTO.

For the smallest next backend unit, implement and prove private fact traversal only; report native migration/canonical consistency as OPEN. Do not return a falsely named complete `SyncSavedSnapshot`. The private completion is still a useful stable foundation for local row staging and later canonical hydration, but cannot be fed to current cache/ACK methods.

## Tradeoffs accepted

- We accept more native data-layer merge work in exchange for no unbounded server merge/session copies, honest duplicate-legacy coverage and idempotent facts.
- We accept one-row initial throughput in exchange for a mechanically provable read and response bound; product switch waits for measured assembly performance.
- We accept explicit oversized-row unavailability in exchange for never truncating private notes or losing traversal facts.
- We accept a new binding-private key field in exchange for stateless, owner/query-bound cursor integrity without a new shared secret deployment.
- We accept keeping old subscriptions during staged development in exchange for preserving installed-client behavior until native assembly is actually proven. This is not a claim the old endpoint is scale-safe.

## Alternatives considered

A durable server preparation/session snapshot hides legacy merge from native callers and simplifies merged-row wire, but requires persisted copies or a source-indexed merge workspace, work scheduling, expiry/erasure, completion publication, idempotent resume and per-owner/session limits. It can be a deep module, but is larger than raw facts and risks repeated O(library-size) copies if every subscription refresh creates a session. Choose it only if native row assembly proves too expensive after actual measurements.

A server merged page per hadith grouping is attractive but cannot cheaply enumerate the union of canonical+legacy hadith IDs with arbitrary duplicates using current indexes without a multi-source merge cursor and bounded continuation of a single huge duplicate group. Adding per-hadith `.collect()` reintroduces the defect; returning partial facet semantics silently is incorrect.

Paginating old readSavedSnapshot output has a small interface but hides no useful new bound, so is rejected.

## Synthesis decision

Candidate submitted for the parent/judge; no repository implementation performed by this consultant.

## Risks / unresolved questions

Can every production Saved writer and migration be proven to advance the Saved version before native switching? Parent is repairing migrateH3SavedItems; static writer coverage plus interleaving tests remain necessary. Can every canonical writer be routed through a single corpus revision boundary before exact old atomic join parity is claimed? Can the native staging store install a complete row generation without rewriting the whole partition, and can export reuse the row store without conflating its broader tables? These remain implementation evidence questions, not user approval blockers for local work.

## First implementation step and executable proof

Add the bounded private fact-page endpoint plus validators/cursor module, leaving production native callers untouched. The installed convex-test paginator ignores maximumRowsRead/maximumBytesRead, so a green fake-paginator test cannot prove hosted enforcement. Use a read-counting query/get wrapper to prove the module call graph and explicit limits locally, plus preserve an actual SDK/hosted byte-limit gate; do not close it from convex-test alone. Tests must traverse multiple pages with >500 items and >500 duplicate legacy facets, compare a deterministic test assembler to existing readSavedSnapshot private merge semantics, cover materialization transitions without visible membership drift, all Saved writer/migration changes midassembly, cross-owner cursor replay/tampering/phase substitution, exact replay, missing canonical references retained as private facts, one oversized note/folder/item, UTF-8 response budgets and actual database-read instrumentation. No whole collect or canonical get may appear in this new endpoint's call graph. A final terminal result is evidence only for this private fact traversal; native full cache, canonical joins, export, hosted SDK, deployment, cross-device and physical failure gates remain OPEN.

## Review corrections from live grounding

Read `/tmp/hadithly-saved-pages/grounding.md` after the first sketch. Parent reports the H3 migration version hole now has three passing regressions and a 487-test full backend run; treat that repair as a dependency rather than implement it twice. The grounding intermediate-summary wording is broader than actual sync wire; the explicit correction above governs native parity.
