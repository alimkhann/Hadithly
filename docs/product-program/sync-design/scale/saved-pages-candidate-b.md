# Candidate B: one durable merged private Saved projection per owner

**Selected shape after parent clarification:** materialize only exact private Saved facts at the private Saved revision. Resolve public summaries through a separate one-hadith bounded hydration boundary. Do not add a global corpus epoch in the first unit. A full-text joined atomic snapshot would require that clock, but the ACK/overlay barrier does not. This distinction makes candidate B implementable while still being structurally different from stateless raw-fact pages.

The existing public wire is `librarySyncPolicy.syncHadithSummary`: `_id`, `providerHadithId`, `collectionSlug`, `collectionName`, optional `volumeId`, `arabicText`, optional `englishText`, `referenceDisplay`. It **excludes provider/canonical/chapter**, although raw `library.readSavedSnapshot` uses the richer helper. Future hydration must match the actual consumed wire, not the richer raw helper.

Suggested additional actual validator shape:

```ts
const summaryResult = v.union(
  v.object({kind:v.literal("found"), hadith:syncHadithSummary}),
  v.object({kind:v.literal("missing"), hadithId:v.id("hadiths")}),
  v.object({kind:v.literal("unavailable"), reason:v.literal("summary_too_large")}),
);
// getSummary({hadithId}) performs one bounded full document get, checks serialized result bytes.
// The input is a public hadith reference, never a supplied private user identity.
```

This summary response is not revision R of the corpus. Native refreshes may change visible summary text/missingness with the private revision unchanged. All private facts, including temporarily missing canonical targets, stay in the completed private generation. Presentation preserves current omission of unresolved/missing public targets. Exact private assembly completion, not successful hydration, opens the private Saved receipt barrier; otherwise a public-content lookup failure could deadlock a legitimate private write. Whole native row-generation activation and that new barrier ownership remain future gated work; never synthesize a giant old DTO with absent rows and call it complete.


## Usage (written first)

A future native data-layer reader owns assembly; presentation and sync code never see individual legacy rows:

```swift
for try await observation in savedReader.observe(owner: capturedOwner, session: capturedSession) {
    switch observation {
    case .building: keepPreviousCompleteCache()
    case .complete(let generation):
        try store.activateVerifiedSavedGeneration(generation, owner: capturedOwner)
        sync.wake()
    case .unavailable(let reason): showRetainedCacheWithReadFailure(reason)
    }
}
```

Android exposes the same behavior as `Flow<SavedReadObservation>`. The future row-store activation transaction changes the active generation pointer and Saved revision together. It never constructs a giant `SyncSavedSnapshot` just to pass through the current whole-partition JSON writer. A complete new generation can replace the old one only after all folders/items were durably stored and the server's final validation succeeded. Until then existing cache and confirmed overlays remain intact.

Backend transport, hidden in that data layer:

```ts
const head = await savedReads.open({ capability }); // JWT resolves owner
if (head.kind === "building") await observeStatus(head.readId);
let cursor: SavedReadCursor | null = null;
for (;;) {
  const page = await savedReads.page({ capability, readId, cursor });
  // Persist exact generation + ordinal range, refuse gaps/duplicates/different owners.
  // A terminal item page is still provisional until finish validates the private Saved clock.
  if (page.kind !== "page") return restartOrReport(page);
  await staging.persist(page);
  if (page.next === null) break;
  cursor = page.next;
}
const finished = await savedReads.finish({ capability, readId });
// Only complete(owner, revision, generation, folderCount, itemCount) allows activation.
```

A reconnect repeats the same ready-generation page. A private Saved change produces explicit `restart`; public summary changes are observed separately and do not invalidate private assembly; a supplied cursor from a different account never selects that account's rows. The old `librarySync:savedSnapshot` remains installed-client compatibility until native migration and rollout are proven. It remains unbounded and does not silently start returning a subset.

## Problem and traced constraints

`library.ts:readSavedSnapshot` currently collects five entire owner tables, merges canonical `savedItems` plus legacy bookmarks/favorites/notes, resolves effective membership for every canonical item, reads every canonical hadith document, filters missing hadiths, and sorts the complete arrays. `librarySync.ts:savedSnapshot` returns this with the private Saved version. Both production native models subscribe to this endpoint; `GuestDataStore.cacheSavedSnapshot` and `GuestStore.cacheSavedSnapshot` persist the entire snapshot in the partition and prune overlays using that version. Therefore paging a response alone cannot fix either database reads or native storage.

Important exact merge behavior: canonical items are inserted first; if malformed duplicate canonical rows exist, the last index traversal row currently wins. Bookmark/favorite legacy rows use the earliest creation timestamp. Notes use strictly greater `updatedAt`; equal-time notes keep the first traversal result, while a canonical note wins an equal-time legacy note. Legacy rows lower item `createdAt`; notes alone raise merged `updatedAt` (bookmarks/favorites do not raise an already existing item's updatedAt in this reader). Canonical `updatedAt` includes effective membership's timestamp. Membership resolves at most a stage/header/destination or owner folder/tombstone, with owner checks. Missing canonical hadiths suppress the merged item. Folders are still included when empty. Preserve these semantics, or explicitly specify/test a separate product change.

The private Saved clock is insufficient for a frozen detailed projection: `hadiths` can change or disappear independently. Schema text fields and legacy note/folder fields are not application-bounded. A single valid database document can be much larger than the desired page. An index page followed by a per-hadith `.collect()` does not solve legacy duplicate scale. `users:exportCurrentUserData` has many additional tables and meanings; these pages are not account export.

## Shape

### Domain and wire types

Actual exported validators define wire types and later native generation; no manual parallel DTO contract.

```ts
type SavedReadRevision = { saved: number };
type SavedReadCursor = { generation: string; section: "folders" | "items"; nextOrdinal: number };
type SavedReadFailure = "source_too_large" | "row_too_large" | "invalid_source" | "missing_owner";
type SavedReadHead =
  | { kind: "building"; readId: Id<"savedReadHeads">; generation: string; revision: SavedReadRevision }
  | { kind: "ready"; readId: Id<"savedReadHeads">; generation: string; revision: SavedReadRevision; folders: number; items: number }
  | { kind: "unavailable"; reason: SavedReadFailure };
type SavedReadPage =
  | { kind: "page"; ownerKey: string; generation: string; revision: SavedReadRevision;
      section: "folders" | "items"; firstOrdinal: number; rows: FolderRow[] | SavedRow[];
      next: SavedReadCursor | null; folderCount: number; itemCount: number }
  | { kind: "restart" }
  | { kind: "unavailable"; reason: SavedReadFailure };
```

In implementation, section/rows must be a discriminated union (`folders` with FolderRow[], `items` with SavedRow[]), not the loose explanatory sketch above. Validated ordinals must be safe nonnegative integers. `finish` returns a separate completion variant; page EOF alone never activates native storage or opens the Saved revision ACK barrier.

### Persisted structure

- `savedReadHeads`, unique indexed `by_user`: owner, opaque generation, captured private Saved clock, expiry, finite-state worker checkpoint. States: `folding(source,cursor,step)` -> `finalizing(cursor,step)` -> `ready(counts)`; any state -> `failed(reason)` / `cleaning(cursor,step)`.
- `savedReadRows`: owner + generation + hadith key, bounded merged facts while folding; a private merged payload and monotonically assigned item ordinal, with no embedded public hadith document. Indexes by owner/generation/hadith and owner/generation/itemOrdinal.
- `savedReadFolders`: owner + generation + ordinal, bounded copied visible folder row.
- No corpus singleton in the selected shape. A separate bounded public summary hydration query resolves one hadith ID at a time and explicitly returns found/missing/oversized. It never calls itself an atomic corpus snapshot. Audited private Saved writers must all advance the private clock; parent's identified `migrateH3SavedItems` omission is one concrete counterexample being repaired. That repair is now verified by parent with three regressions and full 487 tests, per parent message.

There is **at most one materialized generation per owner**, shared read-only by devices. `open` reuses building/ready for the same private Saved clock. A changed clock invalidates the old generation immediately, and bounded cleanup completes before a new generation begins. A client cannot create unlimited retained copies by calling open. No per-reader locks or independent permanent session copies. Optional TTL cleanup is bounded, idempotent and owner-deletion-aware; this table family must join account erasure before any deployment. New generations do not erase private source facts.

### Worker and paging signatures

```ts
open(ctx, { capability }): Promise<SavedReadHead>;
step(ctx, { readId, generation, expectedStep }): Promise<void>; // internal scheduler only
page(ctx, { capability, readId, cursor }): Promise<SavedReadPage>;
finish(ctx, { capability, readId }): Promise<Completion | Restart | Unavailable>;
collectExpired(ctx, { boundedCursor }): Promise<Continuation>;
```

Each worker step reads/merges **one source row**, rather than rereading all facts for the hadith. Source phases are canonical items, bookmarks, favorites, notes, folders. Existing owner indexes support all phases (`notes.by_user_hadith` owner prefix). Each page has `numItems:1`, `maximumRowsRead:1` and an explicit maximum bytes setting; no post-index filters, `.collect()`, or per-hadith collect. Installed SDK `server/pagination.ts` explicitly supports maximumRowsRead/maximumBytesRead but says a byte limit may return incomplete/split pages: handle split and nonprogress explicitly, and never invent EOF from an empty page.

One source row is merged into one indexed accumulator row, preserving the semantics above. Finalization phase visits each unique accumulator once, resolves effective membership within the known constant lookup bound, produces the merged private facts, and assigns one ordinal per merged private item. Public summary hydration happens independently after private assembly; a missing public target still consumes the hydration response and suppresses that item in presentation, while its private facts remain preserved. This changes the new domain cache contract explicitly; it is not a partial old SyncSavedSnapshot. Effective membership should be resolved when ingesting canonical rows as today, or at finalization time with the same Saved-clock stability guard; no normalization-only materialization may change visible output without a clock increment.

Every worker transaction checks the private Saved clock and its exact generation/step **before** writing. A stale duplicate scheduled step is a no-op. On clock change it moves to cleaning, never produces ready. The ready transition rechecks the private clock in the same transaction. Every page and finish recheck owner, capability/session, current private Saved clock, generation, readiness and expiry. Repeated pages are immutable while valid. A clock change after finish is an ordinary new revision; the activated cache remains a truthful completed historical base and the subscription triggers refresh, just as the existing snapshot can become old after receipt.

Per boundary-discipline, caller supplied cursors do not select raw database indexes or another owner's generation: validate generation, section and ordinal against the owned header; recompute the indexed query from that header. A caller can request arbitrary valid ranges but cannot thereby cause the native assembler to consider gaps complete. Native completeness requires contiguous persisted ranges plus final counts.

### Explicit bounds, including one oversized source

Suggested first executable budgets: source/projection payload cap 32 KiB; returned page 64 KiB including its envelope; at most one source row per worker step; page at most one projected row initially. A row limit alone does not bound source bytes. A normal database `get` cannot project selected columns: even extracting a small summary reads the whole hadith document. Use the platform's actual maximum stored-document size as the worst-case single-read allowance (verify installed/hosted limit before documenting a number), and enumerate a conservative constant total bound for source + accumulator + stage/header/folder/mark + owner/binding/head/clock reads; summary hydration separately allows at most one full hadith get. This is still a bounded step even when the source exceeds the application cap. Parent confirms the platform document ceiling is 1 MiB; fifty full hadith gets are therefore rejected, and hydration allows only one. Local convex-test ignores paginator maximumRowsRead/maximumBytesRead, so those options must also be inspected/observed against the actual SDK/runtime before treating them as hosted execution proof. Immediately return persisted `source_too_large` / `row_too_large`; never truncate text or skip a private note silently. Serialize UTF-8 payloads to measure actual envelope bytes before writes/responses; reject any metadata/ID/response that exceeds its envelope. A document too large to fit the bounded application projection makes that generation explicitly unavailable, preserving the old complete cache and all private source content. Large-content chunking is a separate follow-up, not a false completion claim.

Read/runtime budgets must include secondary lookups and indexes, not just the primary paginator. The precise configured byte cap and actual read instrumentation are implementation acceptance evidence. Avoid claiming a hosted budget from `convex-test` alone; installed SDK tests can prove chosen bounds and behavior, while hosted limits remain a deployment gate.

## Module map and interface depth

- `lib/savedReadProjection.ts`: the deep module, all fold semantics, worker state machine, owned generation lookup, bounded read/write/page budgets, cleanup and exact completion.
- `savedReads.ts`: validated public wrappers plus the internal scheduled step; no business merge logic.
- `lib/savedReadPolicy.ts`: actual wire validators and pure merge/byte-budget helpers only when needed by independent native generation/test callers; keep in projection module otherwise.
- `schema.ts`: bounded header/row/folder schemas and indexes.
- Future native `SavedReadRepository` behind existing data layer: owned generation staging/contiguity/final validation; existing UserLibraryModel presentation API stays stable.

Public surface hides duplicate handling, effective membership, cursor rules and source traversal. It exposes only build/read/restart/completion because those are real asynchronous states callers must model. This is deeper than asking both native apps to reproduce the five-table merge, though it costs persistent backend rows.

## Tradeoffs accepted

- We accept one additional O(unique Saved items + folders) private server projection per owner in exchange for one merged private native wire and stable replayable pages. Its lifecycle is mandatory, not an optional cleanup note.
- We accept one-row initial steps and slower background preparation in exchange for honest per-step bounds; batching may grow only after measured complete read bounds prove safe.
- We accept rebuild/cleanup on private Saved clock change in exchange for a coherent completed private generation without inventing a global public corpus clock.
- We accept explicit unavailability for existing unusually large text in exchange for preserving exact content. The UI keeps old complete cache and reports a read failure; it never declares that account complete from a partial page set.
- We accept extra schema, scheduling and private revision audit in exchange for native simplicity. This is substantially more implementation than a raw fact page boundary and may lose on smallest first slice.

## Alternatives considered

1. Stateless source/fact pages and native merge: much smaller server lifecycle and avoids projection copies; both native stores must implement ordered durable duplicate folds, canonical lookups, missing-target filtering and clock guards. It exposes source table evolution to platform data layers but can be a good first bounded transport slice. It is structurally distinct, not a different cursor flavor.
2. Per-hadith merged query behind ordinary pagination: rejected. Duplicate bookmarks/favorites/notes can be arbitrarily numerous for one hadith, so `.collect()` behind an item row preserves the original unbounded read.
3. Fully incremental canonical Saved projection updated by every writer: would be the deepest long-term read interface but requires rebuilding legacy duplicate semantics and maintaining every old writer, corpus write and membership visibility transition atomically. The current compatibility window makes a read-generation builder easier to prove and back out.
4. Durable per-device snapshots: rejected. It makes replay simple but permits storage amplification from arbitrarily many opens and creates a cleanup/owner-bound session family per consumer. Shared one-generation-per-owner is enough.

## Executable acceptance cases and gates

- Hundreds of duplicates for one hadith spanning source pages; exact earliest facets/newest note/tie timestamps versus a bounded fixture's existing `readSavedSnapshot`; canonical duplicate ordering if tolerated; missing target suppressed but later records still reached; empty folders retained.
- More than 501 unique Saved items; instrumentation asserts every source paginator <=1 row, no collect calls in new path, each step's declared maximum secondary reads, every wire response <=64 KiB, and complete contiguous counts.
- One oversized private note/folder/merged facts row makes private assembly explicitly unavailable, with unchanged source and no ready/partial activation. An oversized canonical document/summary fails public hydration only and preserves the completed private base/barrier. An oversized ignored legacy note still has an explicit source-budget policy, not accidental silent skipping.
- Saved mutation, folder commit/stage normalization and legacy migration interleaved at every build/page/finalization boundary. Visible private changes restart; normalization that truly preserves visible projection does not fabricate a new visible revision. Public canonical text/deletion interleaving instead changes hydration found/missing content, never private revision, completeness or ACK settlement.
- Exact duplicate worker, crash/retry, stale generation, account switch, wrong-owner read ID/cursor/stage/folder/header, deleted account, expired generation and cleanup interruption. No cross-owner facts and no retained-generation growth on repeated opens.
- Future native staging persists/reopens midway, refuses ordinal gaps/reordered sections/mixed clocks, never prunes confirmed overlay before final complete-generation activation, and atomically switches without whole-snapshot encoding. Both platforms required.

Whole-account export, reading positions, existing whole-file cache/pending partition scaling, old installed clients, actual SDK subscriptions/auth/cross-device behavior, hosted limits and physical save-failure/device evidence all remain separate open gates. Backend-only pages do not close them.

## Synthesis decision

For the parent/judge to fill. This candidate recommends durable merged **private** generation as the cleaner final server boundary if its lifecycle/storage cost is accepted. Public summary hydration is explicitly eventual and separate. The stricter corpus-epoch design was considered and rejected as unnecessary for the private ACK barrier; it would require a new all-corpus-writers audit without giving the current product a materially better private Saved guarantee.

## Open questions and risks

- Can the native domain store keep exact private Saved rows independently from public hydration, including private facts whose public target is currently missing? This is necessary to avoid reintroducing a private version dependency on changing corpus content.
- Is a single additional private projection per owner worth its write/storage cost compared with a native raw-fact fold during the compatibility period? No production data or cost evidence is available here.
- Will cleanup-before-rebuild starve heavily edited large libraries? Keep the old complete native cache; measure locally and later hosted before tuning. Do not solve by unlimited parallel retained generations.
- Does current account deletion need independent bounded migration before adding rows, given its existing collect-heavy implementation? New tables must be erased and not scheduled back into existence after deletion.

## Smallest first implementation slice

Implement and prove the **bounded server fold engine and its actual validators** against old-reader parity and interleavings, including explicit private revision guards, limits and cleanup; keep native production on the old endpoint and document this as server scaffolding until durable native row-generation activation and installed-client rollout are independently implemented and verified.
