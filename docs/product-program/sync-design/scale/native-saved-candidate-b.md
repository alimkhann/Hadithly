# Candidate B: transactional incremental private Saved fold

## Usage (caller first)

The native data layer owns a bounded durable assembly. UI and the write coordinator do not coordinate raw facts or write a giant partition snapshot.

```swift
let captured = try savedStore.open(owner: owner, sessionEpoch: currentEpoch)
let progress = try await savedStore.advance(captured, isCurrent: isStillCurrent) { continuation in
    try await transport.savedFactsPage(continuation: continuation)
}
// advance performs at most one bounded page/finalization step.
// A later wake/reopen resumes using the stored checkpoint.
if case .verified(let staged) = progress {
    // First store-core slice stops here. Production activation is a later parity unit.
    scheduleCompletionRecheck(staged)
}
```

A future integrated reader uses `savedStore.activeView(owner:)` and bounded `items(after:limit:)` / `folders(after:limit:)`. It does not reconstruct `SyncSavedSnapshot`. Public hadith summaries hydrate separately; missing public targets suppress presentation but do not delete private rows or block the private Saved observation barrier.

Future activation, wholly owned by the same module:

```swift
let outcome = try await savedStore.confirmAndActivate(staged, isCurrent: isStillCurrent) {
    try await transport.savedFactsPage(continuation: staged.completionToken)
}
// A fresh, empty terminal reply validates the final private revision.
// Durable active pointer + private revision change together in the row database.
// Only after success may integrated consumers read that authority and wake sync.
```

Android supplies equivalent suspend functions behind `GuestStore`; its SQLite transaction is the sole activation authority. The AtomicFile partition cannot be atomically committed with SQLite. Existing JSON `savedSnapshot.version` remains the authority until all consumers are explicitly migrated; first store-core implementation does not call either old barrier or activation.

## Problem and actual grounding

The new backend `librarySavedFacts.ts` emits one indexed source row per page today, with 32 KiB source, 64 KiB reply and 12 KiB cursor limits. Its exact owner/version/assembly/input/start chain covers folders, items, bookmarks, favorites and notes; final replies include total and a completion token. Empty advancing pages are valid. Re-querying the terminal completion token yields an empty final reply when the private Saved revision remains unchanged, or restart otherwise. Tokens are opaque signed server data. Native code must not parse them to invent its own source cursor.

Actual iOS storage already offers SwiftData models in `GuestDataModels.swift`, registered through `GuestDataStore.schema`, fresh `outcomeContext()` instances with autosave disabled, `saveOutcomeContext` rollback, small fetched predicates, owner/erasure assertions, and outcome export clocks. Android `LibraryOutcomeJournal` is SQLiteOpenHelper **version 2**, with v1->v2 export migration, exact row transactions, generation fences and bounded member cleanup. `GuestStore` separately persists its entire partition via AtomicFile under a mutex. These are real transaction foundations to extend, not reasons to add another cross-platform storage framework.

Both `UserLibraryModel` implementations still subscribe to `librarySync:savedSnapshot`; iOS `reloadAccount` and Android projection materialize full arrays/maps. `LibraryPartitionState.savedSnapshot` controls confirmed pruning, projected folder deletion, manifest settlement and retention. Therefore a store-core result cannot be injected as an old DTO with a missing hadith field or privately omitted rows. Production read and barrier migration is a separate required unit.

## Shape

Use an incremental fold: **each accepted page atomically updates the merged private rows, compact identity/digest evidence and its exact continuation checkpoint**. No full raw fact journal and no second semantic fold after collection.

### Types and surface

```swift
struct SavedAssemblyHandle: Sendable {
    let owner: LibrarySyncOwner          // namespace + subject + owner/storage key
    let scopeGeneration: String         // erase/owner incarnation, durable
    let collectionGeneration: String    // one local staging attempt
    let sessionEpoch: String            // captured in-process session, never identity from wire
}
enum SavedAssemblyProgress {
    case collecting(nextFactOrdinal: Int)
    case verifying
    case verified(SavedStagedGeneration)
    case restart
    case unavailable(SavedAssemblyFailure)
}
struct SavedActiveView {
    let owner: LibrarySyncOwner
    let collectionGeneration: String
    let privateVersion: Int
}
// Wire enums come from actual savedFact/savedFactsReply validators through the existing generator.
// Transport wire is parsed/validated behind this domain surface.
func open(owner: LibrarySyncOwner, sessionEpoch: String) throws -> SavedAssemblyHandle
func advance(_ handle: SavedAssemblyHandle, isCurrent: () -> Bool,
             fetch: (String?) async throws -> SavedFactsReply) async throws -> SavedAssemblyProgress
func activeView(owner: LibrarySyncOwner) throws -> SavedActiveView?
func items(_ view: SavedActiveView, after: SavedItemOrderKey?, limit: Int) throws -> SavedPrivateItemPage
func folders(_ view: SavedActiveView, after: SavedFolderOrderKey?, limit: Int) throws -> SavedFolderPage
func cleanupStep(owner: LibrarySyncOwner) throws -> Bool
```

Kotlin mirrors the domain, using Long for safe integer ordinals/versions internally after validating generated wire Double values. `confirmAndActivate` is future integration surface, not an available shortcut in the first core-only unit. Repository APIs hide SQL/model objects, raw fact phases, retry digests and storage keys; per deep-module/boundary-discipline, UI never receives a ledger or a raw transport reply.

### Durable rows

Use the existing row database/container, with distinct table/model names:

1. **Saved scope**, one per exact owner namespace/subject/key: durable incarnation; erasing flag; active generation pointer + active private version; optional staging generation pointer; cleanup phase/cursor. Active pointer/version are the same row/transaction, never duplicated into AtomicFile as authoritative truth.
2. **Assembly header**, one active/staging or retiring generation: owner identity, incarnation, captured session-independent binding/root identity, private version after first reply, current input token, next fact ordinal, highest fact source phase, first encounter counter, terminal total/token, verification cursor, state, last accepted page identity/digest. All metadata has explicit byte limits. No growing array/history in header.
3. **Projected items**, unique `(collectionGeneration, hadithId)` key, exact private facet/membership values, `firstEncounterOrdinal` and stable order columns. Raw staged canonical membership has already been resolved by the server; retain `folderUpdatedAt` as independent causal data. No public text or guessed missing-target filtering.
4. **Projected folders**, unique `(generation, folderId)` and first encounter ordinal, exact name/created timestamp; retain empty folders.
5. **Compact fact ledger**, unique `(generation, ordinal)` and `(generation, sourceKind, sourceId)`, with explicit stable fact fingerprint and target key. It keeps no full note/content payload. It detects a duplicate source ID at a later ordinal and guards same-ordinal changes.
6. **Compact page chain ledger**, unique `(generation, inputTokenFingerprint)` and monotonic local page sequence, reply envelope digest plus start/count/end. This detects an old/repeated opaque continuation or cycle even when empty pages keep the same fact ordinal. It stores token hashes, not every full cursor. The current token and last retry digest remain in header.

This is O(unique private items + folders + source facts + advancing pages), not constant total space. Every transaction and read is bounded. The compact ledgers remain until the staging generation is verified and activated; after activation, bounded cleanup removes them because collection cannot resume. Export must include any private rows retained before cleanup. No unlimited abandoned generation creation: at most one active, one staging and one retiring generation per exact owner; a new restart cannot create a fourth until bounded cleanup frees the slot. Explicitly benchmark churn; the design does not claim acceptable throughput from boundedness.

### Boundary validation and exact replay

Before awaiting transport, `advance` captures the owner, session epoch, existing persisted scope incarnation, staging generation, state, exact requested continuation and checkpoint. It creates the scope only through `open` while the owner partition is active and not deleting. Page persistence never recreates a missing scope/header. After await it rechecks current session/owner, then rechecks incarnation/header/checkpoint **inside** the row transaction under the native store's existing ownership/erasure serialization.

The first accepted page must have nil input, start 0, a nonempty bounded assembly ID, exact owner key and safe nonnegative integer version. Subsequent replies must echo the exact request input, same owner/version/assembly and exact next ordinal. Fact ordinal is contiguous `start + offset`, source identity is nonempty/bounded, timestamps finite; phase kinds must be nondecreasing in the actual server order. Validate whole envelope size, facts count, all strings and merged row size before commit. An empty page must change continuation, must not revisit a recorded input token and must not be mistaken for EOF. A terminal page must have `total == start + facts.count`, no next token and a bounded nonempty completion token.

On a new accepted page, compute and validate all row deltas, insert compact fact/page ledger entries, update projected rows and checkpoint, and bump the private export mutation clock in **one transaction/save**. Any malformed fact, uniqueness conflict or failed save rolls everything back. No partial per-page cursor advance.

Keep the last exact reply envelope fingerprint in the header so the immediately previous page can be retried idempotently after response loss/reopen. It must match its original requested input/start/owner/version/root and complete reply fingerprint; a changed fact/outcome/token fails. A page older than the retained last-page retry window returns explicit stale-page failure with no state change, even if it might be an exact historical replay. The caller resumes from the persisted current checkpoint; no network client needs arbitrary old replay because it permits only one page in flight. The compact fact ledger can further diagnose historical ordinal conflicts but must never guess an old response from only merged current values.

Fingerprints must be semantic deterministic framing: tagged fields, explicit optional markers, UTF-8 byte-length strings and finite IEEE754 bit representation for number values. Existing `LibraryOutcomeBinding.hash` supplies framed hashing structure; do not rely on Swift JSON key ordering or Kotlin serialization order to define equality. Cross-platform identical digests are useful fixtures, but each local replay ledger only requires its own versioned deterministic definition. Persist a fingerprint-version tag for future installed-store changes.

### Exact fold semantics

The pure fold helper receives the previous projected row (one indexed point read) and one fact:

- Canonical item: replace private values completely, including clearing absent fields, but retain the first ever encounter ordinal for stable sort ties. Canonical duplicate rows are permitted because current reader's map uses last canonical value, unlike duplicate source IDs which are invalid.
- Bookmark/favorite: take minimum facet time and minimum createdAt. If a projected row already exists, do **not** raise its updatedAt from the bookmark/favorite timestamp. If none exists, initialize createdAt/updatedAt from that first legacy fact. Later first encounters in other phases preserve that encounter ordinal.
- Note: create a legacy-only row if absent; strictly newer noteUpdatedAt replaces content/noteCreatedAt/noteUpdatedAt. Canonical wins equal-time legacy note; first legacy note wins equal-time later legacy note. Always lower createdAt and raise updatedAt by the note fact's timestamps, matching current helper behavior.
- Folder: exact folder row, stable first encounter ordinal for equal creation timestamps; retain empty folders. A repeated identical source ID is invalid, not an upsert loophole.

A generation-local row lookup is O(1 indexed result with fetchLimit2 to detect corruption), not a dictionary load. Facts are processed in increasing ordinal and source order. The pure helper returns at most one row mutation. It never joins canonical hadith data, and private rows referencing missing public targets remain preserved.

### Verification and activation

After the first terminal reply is committed, collection becomes verifying; it cannot expose active revision. Verification is bounded: walk compact ledger ordinals and projected rows/folders with persisted cursors, validate contiguous source coverage, exact counts, ownership/generation/key/fingerprint consistency, safe sort fields, phase order and terminal total. A rolling count/hash can be persisted in the header; no all-row array. Incremental transactional fold itself is the semantic proof; this verifier checks persisted integrity, not a second rebuild falsely described as independent recomputation.

Only after verification succeeds may future `confirmAndActivate` re-query the exact terminal completion token. Require current owner/root/version, input equal to that token, start/total equal to durable total, zero facts and the same deterministic completion token. A restart or unavailable reply never activates and preserves the old active generation. On success, recheck owner/session/incarnation and verified header inside the row transaction, atomically switch active pointer plus private revision and mark old active retiring. No network/DB transaction can prevent a subsequent cloud write; this proves a coherent completed historical revision, just as current snapshot responses can become stale after return.

The future integrated barrier reads `SavedActiveView.privateVersion` from this exact database and captured owner. `LibraryPartitionState.pruneConfirmed`, projected folder-delete filtering, manifest settlement and retention must accept this explicit private observation authority; `savedSnapshot.version` cannot remain a parallel authority. Android then may persist a convenience marker in AtomicFile, but it is a replayable hint only. If that hint save fails after SQLite activation, reopen still discovers the active view; if SQLite activation fails, the partition can never invent it. This is a required migration design, not cross-file atomicity.

## Bounds and lifecycle

Today one server fact/page means a normal ingest touches one projected row, one fact ledger row, one page ledger row and header/clock. Enforce an independent local ingress maximum **below 50**, even if a future server sends more. A conservative future cap of 16 facts gives at most 16 projected +16 fact ledger +1 page ledger +header/scope/export metadata within 50 row touches. Keep constant secondary reads explicit. Oversized future replies are rejected without checkpoint changes; compatible backend batch-size negotiation is a future requirement before widening server pages.

Verification/cleanup fetch at most 48 data rows plus at most two metadata rows per step. Persist the cleanup phase and cursor; yield between steps. Do not run an unbounded while-loop on MainActor even when each SQL delete is capped. Bounded row payload sizes (suggest 128 KiB projection payload, reply <=64 KiB, token <=12 KiB plus fixed metadata) make bounded row count a real memory bound. A merged row exceeding policy fails the staging generation explicitly, preserving source and old active base. Never trim user text to make a test pass.

Erase begins by atomically rotating the Saved scope incarnation and setting erasing before any async deletion. Full subject+namespace deletion fences every owner key, including orphan generations. Bounded row/page/fact/header cleanup and private export-artifact cleanup follow. A captured response cannot recreate scope; a later legitimate sign-in creates a fresh incarnation only through authorized open after existing deletion policy permits it. Owner-only cleanup must leave another owner/incarnation untouched. Existing outcome erase/export clock code can host these additional tables, but it must not remove the shared clock while Saved rows remain; current `remaining headers/scopes` checks need extension.

Export streams bounded private projected rows plus staging metadata/compact ledgers across **all** subject+namespace generations, including old owner orphans. Export fencing changes on every staging/fold/activation/cleanup/erase mutation, and must be validated during streaming. A compact ledger is not raw-note evidence; exported projected private facts are the authoritative retained note content. Existing full partition and server export scale remain open and must not be called fixed by adding this stream.

## Module map

- iOS existing `GuestDataModels.swift`: new additive Saved scope/header/projected/ledger @Models and domain structs; generated actual wire region derives SavedFact/SavedFactsReply validators. Register models in existing GuestDataStore.schema, no new Xcode project file.
- iOS existing `GuestDataStore.swift`: Saved assembly methods with fresh contexts, exact save/rollback, export/erase/cleanup extension. Pure fold and framing types can live beside existing guest planner in an existing compiled file. Avoid scattering a one-caller pipeline across new wrappers.
- Android `LibraryOutcomeJournal.kt`: bump schema to v3 additively, preserving v1->v2->v3 chain and all existing rows; add Saved tables/transactions and extend shared clock/erase queries. Alternatively a sibling domain class on the **same** database handle is acceptable if it actually concentrates the Saved knowledge rather than forwarding every method.
- Android `GuestStore.kt`: narrow owner/session serialization facade around row transactions; no `persistLocked` per page and no whole AtomicFile rewrite.
- Native planner tests/Android instrumentation: actual on-disk reopened stores and installed-schema fixtures, not only pure helper tests.

The boundary hides exact page identity, source order, duplicate/tie fold semantics, persistence, checkpoints, verification and lifecycle. It exposes one bounded `advance` operation because callers genuinely need to yield/schedule, not separate validate/fold/save methods. This passes the red-flag screen: no transport reexports to UI, no repeated merge knowledge in presentation, no temporal pipeline of shallow adapters.

## Tradeoffs accepted

- We accept compact per-source/per-page ledgers until activation in exchange for duplicate and empty-page cycle detection without retaining every full raw note/fact twice.
- We accept exact last-page replay only, rejecting older pages, in exchange for a bounded retry envelope and a simple single-flight collector.
- We accept no independent raw replay recomputation in exchange for one atomic merge per fact; correctness rests on real transaction rollback plus pure fold parity cases and persisted integrity checks.
- We accept a store-core-only first component in exchange for isolating proof before replacing every private observation barrier. Full native production migration is still required; this is no substitute completion.

## Alternatives considered

1. **Full raw fact journal followed by bounded fold**: strongest ability to rebuild/audit independently and simple immutable ingestion; costs duplicate user text, a second whole-generation pass and additional cleanup/export privacy surface. It hides merge timing but not the need for active-view/barrier migration. Prefer it only if independent replay/recovery is a real requirement or incremental semantic proof becomes too fragile.
2. **Whole `SyncSavedSnapshot` assembled in memory then JSON cache write**: rejected. It recreates the original unbounded memory/write problem and lies about the new private base when public targets are missing.
3. **Per-page AtomicFile partition updates**: rejected. Both platforms rewrite unbounded cache/pending partitions per response and Android adds a false cross-file activation problem. Row storage owns this domain.
4. **Rolling fingerprint only, without source/page identity ledgers**: rejected. It cannot detect a duplicate source ID at a later ordinal, and nonempty ordinal progress cannot detect empty-page token cycles.

## Executable proof and first component

First implement generated wire roots, bounded incremental row-store collection/verification plus erase/cleanup/export fencing on **both** native stores, leaving production reads and ACK barriers unchanged. Prove it using actual disk stores and fake wire transport:

- More than 501 unique items and hundreds of duplicate legacy facets for a single hadith, exact current-helper timestamp/tie/empty-folder parity, stable order ties and missing public targets retained privately.
- Reopen after every accepted page and immediately before/after terminal verification; resume from exact persisted token, no double fold. Exact last retry accepted, same ordinal changed fact/token fails, old replay rejected, duplicate source ID later rejected.
- Empty advancing pages, repeated/cyclic continuation, skipped ordinal, backwards phase, wrong root/owner/version, unsafe number, oversized wire/merged row, malformed final total; no checkpoint/rows changed on failure.
- Inject failure between projected-row writes and ledger/header commit using actual store transaction failure harness, then reopen. SQLite can use a controlled abort; SwiftData must use a supported save-failure harness, not the previously fatal unsupported CoreData trigger. If unavailable, retain iOS save-failure gate honestly.
- Pause fetch, erase or switch owner, release reply, reopen: no resurrection; other owner unchanged. Pause export, mutate/erase assembly, validate fence fails and deletes partial artifact.
- Seed real installed Android v1/v2 fixture files and old SwiftData model store; additive migration retains all old outcome/partition rows and creates no active Saved view accidentally.
- Instrument maximum rows/bytes per collect/read/verify/delete step and demonstrate no partition save per accepted page; measured loading/churn throughput remains a separate acceptance gate.

The next integration unit must then implement completion recheck/atomic activation, bounded UI projection/hydration, explicit private barrier consumers, legacy local cache migration and full export. Until those pass, old whole-snapshot subscriptions and scale gates remain open. No deployment/private account/provider call is part of this consultation or first local component.

## Synthesis decision

Parent/judge to fill after comparing the raw-journal candidate. Candidate B chooses transactional incremental fold as the base if its compact ledger proof remains simpler under implementation; scrap it for raw replay if repeated recovery cases require retaining original fact payloads.

## Open questions and risks

- Can the supported SwiftData harness prove failed save rollback without a CoreData fatal, or must that physical/runtime gate stay open again?
- Will a maximum of three generations and cleanup gating stall large libraries under repeated revision churn? Measure before claiming usability.
- Can the next integration replace all `savedSnapshot.version` readers with explicit row authority in one coherent parity unit, including retention/export, without temporary double authority?
- Does independent raw fact rebuild have a product/debugging requirement worth its extra retained private text? If yes, select the competing journal design instead of bolting raw content onto this compact ledger later.
