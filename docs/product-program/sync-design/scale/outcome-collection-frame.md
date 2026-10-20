# Outcome collection frame

Read-only architecture consultations inside A2, not delegated implementation.
Do not modify repository/cloud/account state. Write only the requested candidate
under `/tmp/hadithly-outcome-collection/`. Parent implements the chosen design.

The server has exact bounded manifest receipts and stable member facts. Delete
facts expose the original identity set even if restore later changes dispositions;
restore facts are immutable only after the restoration visibility flip. Current
native settlement deliberately rejects both new receipt kinds. Current Saved cache,
pending/frozen/recovery and ACK live in a SwiftData JSON partition blob on iOS and
an AtomicFile JSON store on Android. Whole-file native scale remains open. Read
PLAN, PRODUCT_PROGRAM, librarySyncFrames, savedFolderTransitions, both native
LibrarySync/GuestDataStore/LibraryProjection, export and erasure paths.

Design caller-first types/storage/module APIs and rationale, following the
architect runner prompt and rationale template. At least two structurally distinct
shapes will be compared. Cover an owner/installation/sequence/digest/receipt-bound
page query with ordinal continuation, max50 small identity rows/64KiB, unavailable
proof/details, no guessed completion, exact counts and immutable category totals.
No full member arrays in a server transaction or growing partition blob. Native
page persistence must survive lost response, checkpoint failure/reopen, duplicate
or conflicting pages, owner changes and erasure. No ACK before needed result details
are durably preserved. A same-ID different-command fork remains historical.

Prefer native storage conventions, keep app views unaware of paging. A per-page
journal can preserve details without unbounded JSON rewrites. Consider SwiftData
rows and Android SQLite or atomic page-file storage, versus another viable shape.
Explain transaction boundaries with the current Android JSON checkpoint. Do not
invent unlimited retention: success details may be pruned after ACK plus authoritative
Saved revision observation; partial/unavailable evidence and locally available
originals must remain recovery/export data. Never label a collected subset complete.

Use the existing Saved revision barrier to prevent guessed partial optimistic
restoration from overriding a newer authoritative snapshot. Current native export
must include any retained journal evidence; erasure must cover journal orphans by
captured subject+namespace even when the partition record is gone. Existing native
whole-file cache, old installed schema, public producer and read/export cutovers stay
gated unless actually implemented and proved.

Rubric1-5: (1) exact page/receipt/owner identity and replay safety; (2) bounded page
persistence and journal/checkpoint crash consistency; (3) partial/unavailable recovery,
export and erasure completeness; (4) small deep coordinator/store interface and
honest projection/revision behavior; (5) concrete real-store/backend red/green proof
and migration limits. Recommend a base plus grafts, not implementation code.

Workflow: [x] ground/frame; [x] distinct candidates; [x] cross-judge/synthesis;
[x] parent server page implementation; [x] actual backend proof;
[x] native durable journal core/proof; [x] native coordinator collection/proof;
[ ] settlement/export cutover/proof; [x] retain open gates.

The chosen contract is `outcome-collection.md`. Candidate A's row journal is the
base, with candidate B's persistent erasure fence, unavailable-proof distinction
and Undo-aware pruning. Source candidates and independent judgment are saved here.
The current implementation proves the server query, native journal core and native
coordinator collection. The persisted collection phase preserves originals while
settlement and export cutover remain open. The journal does not itself ACK or settle
a frozen operation.
