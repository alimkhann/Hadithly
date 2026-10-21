# Native private Saved assembly: independent judgment

Read in full: frame.md, grounding.md, candidate-a.md and candidate-b.md. Read-only design comparison; no implementation, repository edit, external call or additional delegation performed. Scores assess the proposals, not evidence that either implementation works.

## Decision

Select **A's raw fact journal and bounded postterminal fold** as the base for the first native store component, with B's tighter total transaction budget and explicit single-flight facade as grafts. Both must retain the existing joined snapshot as the sole production barrier authority until the later explicit cutover.

A wins narrowly on exact replay, recovery and inspectable collection/fold separation. B does not eliminate source/page ledgers or generation lifecycle: it primarily removes raw payload storage and one fold pass while adding the invariant that every fact, digest, source identity, projected delta and continuation committed exactly once together. The temporary raw payload cost is real, especially for overridden legacy notes, but it buys a simpler first correctness proof and a reproducible fold without rebuilding a server library. Do not implement both strategies or add a generic persistence engine.

This is a choice of the first verifiable component of the target architecture. Prepared row generations alone do not constitute native read migration, production activation, acceptable throughput or A2 completion.

## Scores

Each score is 1–5 against the frame's criteria.

| Criterion | A | B | Reason |
| --- | ---: | ---: | --- |
| Exact cursor/fold/source parity | 5 | 4 | A retains exact source facts and page replies for replay plus a separate deterministic fold. B correctly handles source order and empty pages but makes exact semantic recovery depend on the transactional incremental fold and a last-reply window. |
| Durable failure/reopen/erasure ownership | 4 | 4 | Both capture durable owner incarnation, forbid callback recreation and require transactional checkpoints. Their installed migration and recoverable SwiftData failure claims remain to be proven. |
| Bounded memory/IO/migration/export | 3 | 4 | A retains more private text and adds fold/verification IO. B's compact ledgers and explicit sub-50 total budget are stronger; both still require concrete erasure/export integration and old schema fixtures. |
| Active generation/barrier/native integration truth | 5 | 5 | Both put rows plus future activation pointer/version in one row database, reject AtomicFile atomicity claims and leave every existing production barrier untouched in the first unit. |
| Deep interface/minimal lifecycle/executable proof | 4 | 3 | A's ingestion journal and reducer are easier to inspect independently. B saves a pass but retains similar table families while coupling more invariants in each page acceptance. Both expose a useful bounded advance capability. |
| Total | **21/25** | **20/25** | A base, with the concrete constraints below. |

## Required grafts and clarifications

1. **Adopt B's conservative transaction budget rather than redefining 50 to hide overhead.** Start with at most 16 data facts per local step, currently one on wire. Account for raw row scans, indexed target/source/ordinal checks, touched output rows, page receipt and checkpoint/scope/clock writes. A 50-fact loop plus metadata is not a 50-row transaction. Instrument actual maximum rows and serialized payload bytes for ingestion, fold, verify, read, cleanup, export and erase. Fixed metadata overhead must be stated and tested.
2. **Keep one facade and single-flight collector.** Feature code never sees the collect/fold/verify pipeline. Internal exact replay support is useful for reopened/lost responses; it does not justify multiple simultaneous requests or mutable assembly reuse. A new binding abandons the old candidate; callbacks can only commit to the preexisting captured scope/header/incarnation.
3. **Make prepared versus active unambiguous in types and accessors.** The first unit may return an opaque prepared handle and bounded inspection/export pages. It must have no route from a received terminal reply to `cacheSavedSnapshot`, observed Saved revision, confirmed pruning, manifest settlement/ACK or retention. The later integrated private observation reads the active pointer and version from the same row DB; the old JSON version stops being authoritative only when all four consumers and projection are migrated together.
4. **Use distinct Saved tables/models.** Reuse concrete SwiftData save/rollback and SQLite transaction foundations, not manifest counts or outcome per-hadith uniqueness. Duplicate canonical/legacy hadith facts are valid; duplicate source IDs or changed same-ordinal facts are not. Preserve exact first encounter order across canonical replacement, bookmark/favorite initialization and strict note timestamp ties.
5. **Make raw retention temporary and explicit.** One active, one candidate and at most one retiring generation per exact owner is an upper bound, not permission to accumulate another failed stage. Admission must drive bounded cleanup first. Raw facts and page receipts may be reclaimed only after they are no longer needed for preparation/replay/export and only through a persisted bounded cleanup phase. Until reclaimed, every retained original note payload is private data subject to erasure and export.
6. **Choose and implement one complete clock policy.** A shared private mutation clock is reasonable if its scope, remaining-data checks, inventory, export and erase semantics are extended to Saved in the same component. The current outcome clock is not already sufficient. Independent Saved clocks are also sound but create another fence family; do not accidentally mix the two. An erasing subject+namespace marker must block all owner-key scopes before bounded per-scope cleanup, including old owner orphans.
7. **No hidden large deletion or export.** Erase must rotate/fence first, then delete indexed rows in bounded steps with persisted progress. Avoid cascading header deletion before child cleanup. Export streams retained assemblies/raw facts/projected rows across the whole subject+namespace with mutation fence validation; no prebuilt array or active-only export while private dead stages remain. Existing artifact invalidation must cover these contents. This treatment is required before production wiring, and should be implemented/proven in the store-core unit rather than left as an undefined cleanup promise.
8. **Install migrations are acceptance evidence.** Android currently starts at v2; support both actual v1→v3 and v2→v3 without wiping old outcome/export state. On iOS open an actual old disk schema with the additive models and inspect preserved data. Merely creating a fresh new database, or using the existing `try!` initializer without an old file, proves no upgrade.

## Rejections

- Reject B as the initial base, not as an invalid architecture. It becomes preferable if measured temporary raw payload/storage or extra passes are unacceptable and the incremental invariants remain simpler than adding raw recovery later. Do not graft its compact fact ledger onto A when the raw fact row already supplies that exact identity/evidence.
- Reject unlimited exact page-response payload duplication. A's raw facts hold private payload once; page receipts should retain bounded exact envelope/token/identity evidence and verify against raw rows. Do not store the entire serialized page again just to compare a digest. Empty pages still require independent receipt identity.
- Reject a hash as a replacement for structural validation, a fold-end cursor as proof of complete durable output, and a projected-row checksum as independent semantic recomputation. Pure reducer parity and persisted structural verification prove different things. State their limits honestly.
- Reject reconstructing the complete old joined DTO from all row pages to keep current UI/barrier callers unchanged. That would preserve the memory defect and omit missing-target private facts. Production integration requires the explicit new private domain and separately eventual public summaries.
- Reject a broad new cross-platform repository/transaction framework. Existing concrete stores already own the necessary persistence primitives; keep the new domain seam deep and narrow.

## First component acceptance

Generate actual SavedFact/Reply DTOs, add installed-store migrations and implement raw collection, bounded deterministic fold, persisted verification and opaque prepared handles on both native stores. Include bounded row inspection, cleanup, erasure and streamed local export/fencing for every newly retained private payload. Keep production subscriptions, old joined caches, activation and all current barrier consumers unchanged.

Use actual reopened disk stores with >501 unique items, >500 duplicate legacy facts and >50-step fold/cleanup; compare exact private values and stable ordering with bounded backend parity fixtures. Cover empty advancing pages, source phase regression, missing target references, duplicate source IDs, changed retry facts/tokens, ordinal gaps, wrong owner/root/version, terminal totals, restart/unavailable, binding reopen and session/erasure races. Inspect stored rows and checkpoint after failure/reopen. Prove max row/byte work and no partition JSON rewrite per page. Android controlled transaction abort is useful; unsupported CoreData trigger crashes are not recoverable iOS save-failure proof. Retain that gate if a supported harness cannot prove it.

The next required integration unit must prove final server completion recheck, atomic activation, explicit private observation authority for all four barrier consumers, bounded UI access/hydration, old local cache migration and production collector scheduling. Loading/churn throughput, broader pending/cache/export scale, hosted SDK/auth, installed-client/cross-device and physical persistence behavior remain open. A prepared-generation test does not close those requirements.
