# Candidate A — raw Saved fact journal, durable bounded fold, immutable private generations

## Usage (caller first)

Feature callers observe a handle to a complete owned Saved generation through one data-layer interface, with bounded indexed view reads rather than an array of every Saved row. They do not manage pages, raw facts, fold phases or activation:

```swift
for try await change in library.savedChanges(owner: capturedOwner) {
    // A complete private base plus separately eventual public references.
    renderGeneration(change.handle) // view reads indexed pages from this handle
}
```

```kotlin
library.savedChanges(capturedOwner).collect { change -> renderGeneration(change.handle) }
```

The existing sync coordinator eventually drives a single bounded method until idle, yielding between steps; it must not loop inside one database transaction:

```swift
let progress = try await guestData.advanceSavedRead(
    owner: owner, session: session, isCurrent: capturedSessionStillMatches,
    fetch: transport.savedFactsPage
)
if progress.didActivate { sync.wake() }
```

Tests of the first storage component use the same transaction kernel without production transport wiring: `beginSavedRead(owner, rootRequest)`, `acceptSavedPage(lease, requestedInput, reply)`, `advanceSavedAssembly(lease)`, `preparedSavedGeneration(lease)`. These are **internal storage operations**, not a public feature API. The first unit stops at prepared immutable generation: the current joined native subscription remains until projection, revision barriers, public hydration, migration, erasure and export are integrated. `prepared` alone cannot wake an ACK barrier.

## Grounding and actual edges

The wire is `backend/convex/lib/librarySavedFacts.ts`, not the old joined snapshot: five ordered indexed sources, at most one fact per current page, root `assemblyId`, owner, Saved version, exact input echo/start, opaque next or signed terminal completion/total. Missing public targets remain private facts. No client capability or server private signing key belongs in persisted rows. Root/continuations are opaque bounded proof tokens; they do not authorize requests without the captured authenticated binding.

`ios/Hadithly/Core/GuestData/GuestDataStore.swift:22` lists actual SwiftData models; add new models in existing GuestDataModels.swift and schema, avoiding pbxproj. `outcomeContext()` at 774 creates an autosave-disabled fresh context; `saveOutcomeContext` rolls back failed saves. `collectOutcomeStep` 848 saves header before await, captures scope generation, then rechecks owner and generation in `persistOutcomePage`. Reuse these primitives and ownership conventions, not outcome receipt semantics or its per-hadith uniqueness (Saved permits duplicate hadith facts).

Android `LibraryOutcomeJournal.kt` is currently SQLiteOpenHelper **version 2**, not 3. `transaction` surrounds row/checkpoint updates; scope generations, export clocks and explicit LIMIT50 erasure exist. `GuestStore.kt` owns a separate AtomicFile and mutex. Outcome collection captures journal generation under mutex, releases it over fetch, rechecks captured session and owner, then persists under mutex. Reuse that shape, add Saved tables to this same SQLite database with a real v2->v3 migration, and preserve existing v1->v2->v3 upgrades. Do not rely on AtomicFile to make SQLite changes atomic.

Current `cacheSavedSnapshot` on both platforms replaces the whole JSON snapshot and prunes confirmed overlays. Current feature reload reads full snapshot arrays. Those methods are unsuitable per-page persistence or activation boundaries. Existing settlement/retention read `savedSnapshot.version`; new private base activation must become the sole source of observed private version before cutover. Public summary absence cannot hold a private receipt forever.

## Shape and ownership

A single **native Saved journal** owns collection integrity, merge semantics, state progression and generation visibility. Its public facade offers `advanceSavedRead`, `savedChanges`, bounded row reads and export/erase integration. Swift implementation stays in existing GuestDataStore/Models files; Android implementation can be a private Saved section/helper inside the existing journal file or a helper sharing its exact SQLite connection/transaction owner. A second database engine, file of page JSON or crossplatform generic persistence framework adds no useful capability.

```text
SavedScope(owner namespace/subject/storageKey, epoch, erasing, activeGeneration?, candidateGeneration?)
SavedAssembly(id, scopeEpoch, owner, root?, version?, state, exactNextInput?, nextOrdinal,
              pageCount, phaseRank, total?, terminalCompletion?, collectDigest,
              foldOrdinal, foldedDigest, verificationCursor, outputCount)
SavedPageReceipt(assembly, inputKey, exactInput?, start, rowCount, responseDigest, outputToken, terminal)
SavedRawFact(assembly+ordinal unique, assembly+kind+sourceId unique,
             ordinal, sourceId, kind, hadithId?, factData, factDigest)
SavedPrivateRow(generation+hadithId unique, firstEncounterOrdinal,
                privateFields, canonicalLastOrdinal?, rowDigest)
SavedFolderRow(generation+folderId unique, firstEncounterOrdinal, fields, rowDigest)
```

IDs/keys are length-prefixed UTF-8 hashes, not concatenations with ambiguous separators. Store owner fields explicitly and revalidate against the parent header when decoding. Facts and immutable output rows carry only private values. `SavedPrivateRow` does not require a hadith summary. Preserve independent `folderUpdatedAt` even though old joined sync DTO omitted it.

Typed boundary sketch (names may follow native conventions):

```text
advanceSavedRead(owner, capturedSession, isCurrent, fetch) async -> SavedReadProgress
savedChanges(owner) -> Stream<SavedGenerationChange(handle, version)>
readSavedRows(handle, filter, after: SavedRowCursor?, limit<=50) -> SavedRowsPage
readSavedFolders(handle, after: SavedFolderCursor?, limit<=50) -> SavedFoldersPage
advanceSavedCleanup(owner) -> bounded progress
readSavedExportPage(exportFence, cursor) -> bounded private export page
```

`SavedGenerationHandle`, row cursors and export fence are opaque domain values created by the store. No feature caller constructs a revision, chooses raw source phases or passes a transport token. A handle's complete semantics do not imply a giant array. Canonical integrity encoding must have cross-native deterministic vectors (UTF-8 length delimiters or canonical sorted-key JSON); hashing unspecified JSON object order is insufficient.

The phase state is a tagged enum, not independently mutable booleans:

```text
collecting -> folding(nextOrdinal,digest) -> verifying(rowCursor,counts,digest)
           -> prepared(terminalProof,total,privateVersion)
           -> active
restart/unavailable -> abandoned -> cleaning -> removed
active superseded -> retiring -> cleaning -> removed
```

A `PreparedSavedGeneration` is an opaque handle obtained only from stored `prepared`, scoped to current owner epoch. No constructor from an integer version or a received terminal reply. An active read handle is scoped to owner epoch and generation ID; every bounded row read checks the pointer or a deliberate export fence. Features cannot call “cache version R” with an arbitrary page.

### Collection, replay and cursor integrity

Capture owner namespace/subject/key, local scope epoch, session identity, binding identity, candidate generation, exact requested opaque input and local header state before await. After await, recheck session first, then re-read durable epoch/header under store lock/transaction before any write. A stale callback cannot create a missing header or scope. Creating an assembly requires an explicitly active partition/owner and an initialized non-erasing scope; accepting a callback never creates these authorities.

Validate generated wire values at this boundary: numbers safe integral/nonnegative; UTF-8 request/reply limits from actual backend constants; current <=1 fact limit explicit, and an absolute future step <=50. For a page/complete, owner/root/version remain exact after first accepted reply; input echo equals exact requested token (first absent); start equals expected ordinal; fact ordinals contiguous, source phase rank monotonic, IDs nonempty/bounded; no duplicate `(kind,sourceId)` anywhere in assembly. Current empty advancing source pages are valid and **require a page receipt**, because identical start ordinals may have different opaque input and output tokens. Reject nonterminal next identical to input and malformed terminal total; do not deduce phase from signed token internals or require empty phases to appear as facts.

Insert raw facts, a page receipt and next header checkpoint in **one** SwiftData save/SQLite transaction. Compare structural decoded facts plus exact token identity on replay; canonical response digest is an accelerator, not permission to accept changed facts at the same ordinal. A repeated old input uses its receipt to verify exact reply and returns current progress without advancing/folding twice. A wholly new stale input fails. A different reply for an existing input/ordinal fails without replacing evidence. SourceID uniqueness is per kind/source table, not per hadith: duplicate legacy hadith rows are valid inputs.

If save fails, rollback the fresh SwiftData context / SQLite transaction. Neither rows nor checkpoint advance. Lost responses resume from committed next input after reopen. A candidate with a known root is immutable in root/version identity. If binding expires/reopens, abandon and clean the old candidate; never adapt its continuation to a new binding. `restart` or `unavailable` records nonactivatable status, leaves old active base intact, and schedules bounded cleanup/retry policy without an immediate unbounded retry loop.

### Fold after terminal

A received `complete` makes collection terminal, not data active. Its `total` must equal durable contiguous raw count. Postterminal folding reads the next <=50 raw rows by ordinal with SQL LIMIT / SwiftData fetchLimit; validates their IDs, ordinals, decoded owner and hashes; reads the one current projected target row per fact with an indexed exact-key fetch (limit2/UNIQUE); applies a pure deterministic reducer; writes touched rows and fold checkpoint in one transaction. No whole account map, `.all()`, fetchCount over every item, full snapshot array or JSON partition write.

Canonical items are first phase; each canonical fact replaces fields for its hadith, including clearing formerly present optionals, preserving only the first encounter ordinal. Last duplicate canonical row wins values exactly like current Map.set. New bookmark/favorite-only rows initialize aggregate updatedAt from the first encountered legacy row; later bookmark/favorite facts take earliest facet createdAt and aggregate createdAt minimum **without raising existing updatedAt**. Note facts use strict greater-than replacement for content/created/updated, aggregate min created/max updated; canonical equal-note timestamp wins and equal legacy notes preserve first encounter. Canonical effective membership/clock is already server-resolved. Empty folders persist independently; retain missing public hadith references. Item final sort is updatedAt descending then firstEncounterOrdinal ascending; folder sort createdAt ascending then firstEncounterOrdinal ascending. Index sortable fields rather than fetching and sorting everything in memory.

A transaction may touch up to50 raw facts but many target rows; batch them by reducing sequentially using bounded exact gets. It must count actual inserted/updated target rows against the <=50 write policy: processing50 facts plus header can otherwise be51 writes. Define budget as <=50 **data rows**, with O(1) header/checkpoint writes explicitly accounted; if the instruction means50 total writes, use49 data rows. This convention must be identical in tests/docs. Cap bytes too: 50 legal 32KiB source facts is bounded ~1.6MiB, but an actual native allocation benchmark remains needed. Prefer default16 facts until measured, upper50.

### Verification and immutability

Do not treat `foldOrdinal == total` alone as proof. Persist a rolling canonical digest/count during collection, replay it over contiguous raw facts during fold, compare exact terminal totals/digest at fold end, and refuse a gap, reordered phase, changed raw payload or unrecognized fact. Each projected row has an independently stored canonical row digest; a bounded verification pass scans output rows/folders by primary key, checks structural identity/field validity/digest, safe ordering metadata and final output counts against counts maintained by fold transactions. Only then mark `prepared`. There is no second full-memory recompute. Pure reducer parity tests prove semantics; store verification proves durable row/checkpoint integrity. This is not a claim of resistance to an attacker who can rewrite both database values and their integrity hashes.

After prepared, no collected fact or projected row can be edited. Restart creates another candidate only after previous candidate cleanup, not by resetting its cursors in place. A schema/reducer revision is embedded in header; an unknown version is unavailable/cleanable, never resumed under changed fold semantics.

## Activation and exact barrier truth

Before eventual activation, query the server once using the stored terminal completion as continuation. Current endpoint accepts source `complete` and returns an empty terminal reply; require same owner/root/private version/total/completion. A Saved mutation returns restart. Recheck local owner/session/epoch after await and inside activation transaction. This proves the private generation at the server check's linearization point; it cannot guarantee the server stayed unchanged between remote check and local save. Subsequent changes trigger a new read, while ordinary R snapshot semantics remain valid.

Activation flips the active-generation pointer, candidate state and previous generation retirement **in one database transaction** on both platforms. Pointer and private rows share the same SwiftData/SQLite database. Android AtomicFile is deliberately absent from activation. Do not write a second authoritative `observedSavedVersion` into its JSON.

Full integration needs a `SavedObservation` read from the journal under GuestStore/store serialization and supplied into existing pure overlay/settlement/retention decisions. The same facade reads complete private rows. In migrated mode old `partition.savedSnapshot.version` is ignored for all these decisions; in legacy mode the existing complete snapshot remains authority. The database scope's active-generation mode is the single migration switch. The old DTO can remain archival during transition but cannot remain another authority. If SQLite activation succeeds and a later AtomicFile settlement write fails, the active generation remains valid and the next settlement retry observes it again; no false cross-file rollback claim. If AtomicFile write succeeds, it used a validated immutable complete generation, not a partial assembly.

Public hydration is separately eventual and may show a missing/loading public reference without deleting the private item. It cannot advance or block the private observation barrier. This requires product/projection types distinct from old `SyncSavedSnapshot`, not silently stuffing absent summaries into an old complete DTO.

## Erasure, cleanup, export and installed stores

One active, at most one candidate and at most one retiring generation per owner. Before admitting another candidate when a dead candidate/retiring generation exists, complete bounded cleanup steps. This prevents repeated failures accumulating arbitrary historical copies. Limit work per call and yield; an unlimited loop of LIMIT50 deletes is still an unbounded call.

Erasure first persists a scope tombstone/rotated epoch plus erasing state, clears active/candidate visibility and invalidates export clock in one transaction. Subsequent <=50-row deletes walk raw facts, page receipts, projected folders/items and headers using explicit indexed cursors. No ON DELETE CASCADE that can delete thousands of children in one step. Resume erasure after reopen before allowing assembly creation. A different owner epoch cannot revive old rows. Existing account deletion/removal methods must drive both old outcome tables and new Saved tables before cutover is enabled; account-only erase and namespace-wide erase need separate test coverage.

Extend existing private export mutation clock/inventory conventions so every Saved transaction invalidates a captured export fence. Export iterates retained headers, raw facts and projected rows in <=50-row pages (including abandoned/orphaned stages until cleaned), and rolls back artifacts on owner/session/fence change. Do not build an array before writing or silently export only active rows while retaining private stages. Active server-derived raw facts can be reclaimed after activation/verification using bounded cleanup once no current read/export requires them; merged active values remain. Export must include new private values before production assembly is enabled. Existing cloud export and pending/whole-partition JSON are still separate scale work.

SwiftData additive models require a real installed-schema disk fixture opened with the new schema; the current try! container initialization must not be used as evidence migration works. Android onUpgrade must support existing version2 and a version1 fixture through both upgrades without deleting any outcome evidence. Unknown/newer versions fail closed and preserve files. Tests need actual reopen and durable disk files, not in-memory stores alone.

## Alternatives and tradeoffs

Incremental projected-row fold during page acceptance saves a postterminal pass and raw storage, but exact stale/replayed empty-page receipts, original-fact recovery/export, and verification of a failed partially merged row need a larger ledger/checkpoint policy. It also mixes collection/projection bugs into the same transaction. We accept temporary raw storage plus bounded additional passes for a simple exact input journal and independently inspectable failure state. The final facade remains one complete Saved capability, so feature callers do not inherit that lifecycle.

A generic streaming database abstraction would add forwarding layers while SwiftData and SQLite still differ in transactions/migration. Reuse current concrete stores and a small shared-in-meaning reducer/fixtures. Do not expose storage/checkpoint types as UI options.

Full-array native merge is rejected: it merely moves unbounded whole-library work from Convex into memory and whole-partition encoding. Writing each raw page into partition JSON is equally rejected.

## First concrete verifiable unit

Generate actual Saved fact DTOs from validators, add real installed-schema migrations, and implement the **durable raw collection -> bounded fold/verify -> prepared immutable private generation** kernel plus bounded private row inspection, erasure and local export coverage on both native stores. Production subscriptions/activation stay off for this unit; no new private version may influence existing ACK/settlement/retention yet. This is the first component of the selected target, not completion of native Saved migration.

Tests: >500 duplicate-hadith facts and folders, canonical-last/legacy-first/equal-note timestamp parity, >50 multistep fold, empty advancing and empty terminal pages, lost/replayed replies, changed sameordinal/input/sourceID, phase regression, restart/unavailable, save/transaction failure before checkpoint, reopen every phase, owner swap and deletion during suspended fetch, namespace erase/resume, old installed DB migration, bounded cleanup with large deadstage, streamed export fencing and measured maximum perstep row/byte counts. Actual iOS recoverable save-failure injection remains a known difficult gate and cannot be replaced by the prior crashing unsupported SQLite trigger experiment. Integration unit then proves atomic activation/final check, all private-version consumers, UI projection and separate public hydration before enabling production coordinator wiring. Hosted/client/device/cross-device gates remain open.
