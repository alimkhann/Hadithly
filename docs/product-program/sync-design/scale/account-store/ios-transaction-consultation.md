# iOS account transaction prerequisite

2026-10-22. Read-only source consultation before the four-consumer Saved cutover. Inspected GuestDataStore account/claim/ACK/retention/settlement/cache/deletion, outcome export/clock/inventory/erase and Saved admission paths, plus the existing SwiftData model shape. No code/repository edits, delegation or cloud actions. Parent remains sole implementer. This is a design constraint record, not an implementation or test acceptance.

## Recommendation

Proceed with the proposed **fresh synchronous MainActor context per account operation**, with one save for the account payload plus every associated clock/journal mutation. No new schema is needed. The current long-lived context caches account/deletion rows while outcome/Saved operations use fresh contexts; sharing a ModelContainer does not make their independent saves atomic.

The public red probes proposed by the parent target real gaps: reopened/cached writers must preserve all eight accepted commands, and an account-only clone edit must invalidate an export fence while a guest-only edit does not. Keep those as public API regressions; do not replace them with an assertion that a fresh ModelContext was allocated.

## Concrete current findings

1. `partitionRow/syncPartition/saveSyncPartition` around313-335 use the long-lived `context`. A previously read account may therefore be decoded from a stale identity-map instance and overwrite commands saved by a reopened writer. `saveSyncPartition` also recreates a missing row, so a generic old-context save helper is the wrong owner admission boundary.
2. `settleSyncAcknowledgement` calls `acknowledgeOutcomeEvidence`, which creates a fresh journal context and saves retention/clock, then separately saves the account partition. A partition save failure can leave a separately durable ACK marker. The target architecture should commit both or neither, matching Android's corrected boundary.
3. `pruneOutcomeSuccessStep` saves member/header/scope/inventory changes and clock, then separately writes the account retention cursor. It also loads dependency partitions through the old context. Both the pruning decision and cursor persistence must use the operation's fresh context.
4. `settleCollectedOutcome` reads outcome checkpoint in one fresh journal context, but account state through the old context, then saves account separately. It needs one fresh context now so future observed-private/view publication can join it without another authority adapter.
5. Ordinary account changes and claim do not bump the shared outcome/export clock. Export currently fences journal/Saved changes but can remain valid across a cloned pending/note/receipt/positions change. The per-owner mutation plus shared scope clock must save together.
6. `eraseOutcomeEvidence` around1007 deletes a scope's clock when headers/scopes/Saved are gone, without checking surviving account partitions. That becomes incorrect once the clock also fences account state. Keep the clock while any account or artifact in the subject/deployment scope remains.
7. `deletionRow` fetches every deletion intent then filters in memory using the long-lived context. Use its existing unique scope identity in the supplied fresh context. Final deletion currently uses an all-partition fetch then scope postfilter; scoped bounded cleanup is the proper shape, preserving guest and sibling scopes.

## Central operation boundary

An internal helper should create one fresh ModelContext with autosave disabled, resolve the exact owner partition and exact deletion scope in that context, decode a fresh value, run a **nonasync** typed policy callback, encode only a changed state, bump the shared scope clock when export-visible account state changes, and save once. Catch every escaping mutation error to rollback the context; save failures become storeUnavailable while valid domain errors retain their existing meaning.

Do not invoke today's `syncPartition`, `deletionPhase`, `assertOutcomeOwnerActive`, `saveSyncPartition`, `acknowledgeOutcomeEvidence` or `prepareOutcomeInventoryStep` from an in-context callback while they still choose their own context/save. Add supplied-context helpers or move their actual logic into the operation. Avoid a chain of wrappers that hides an independent save. The central callback is internal storage machinery, not a public transaction API for UI/coordinator callers.

Decode after admission in the new context, never before it in a cached facade. No await, yield, network fetch or callback awaiting another actor may occur between read and save. MainActor serializes these synchronous local operations across reopened store instances in this process. This does not prove interprocess/Core Data background writer locking; do not label it a cross-process lost-update guarantee without a separate CAS/conflict strategy and tests.

Use domain equality before/after to decide whether account state changed, rather than JSON byte equality: dictionary key ordering can differ without semantic mutation. A no-op read/duplicate receipt should not bump a fence merely because re-encoding produced another byte order. A journal-only mutation inside the operation must still bump the clock. Multiple legitimate bumps within one save are not a correctness defect, but a no-op replay must preserve established clocks/ACK age.

## Claim and guest context lifetime

Claim needs a creation-capable operation variant; ordinary enqueue/settlement must require an existing exact owner. Fetch all claimed guest rows in that same fresh context, preserve current original-source conversion/order and invalid recovery, append to the exact owner's state, then delete those fetched rows and save account+clock+guest removal once. Rollback preserves both account and originals. A repeated empty claim leaves the already-existing account unchanged.

The old `context` remains used for guest UI CRUD unless parent deliberately migrates it too. Add a regression that primes guest reads on one store, claims through a reopened store, then reads and edits through the original store: it must neither show already-claimed drafts as current nor resurrect a deleted managed row. A late guest note accepted after claim must survive and remain unclaimed. Refresh observable itemCount only after a successful save; report failed writes honestly. Do not silently discard accepted pending guest changes merely to refresh an identity map.

Guest-only changes do not bump an authenticated account clock. Claim does, because the guest sources become export-visible account originals. Original timestamps, note bytes, semantic positions, pending identities, frozen client/sequence/digests and recovery fields remain exact. A fresh context must not mean regenerating already persisted command/client identities.

## ACK, retention and settlement composition

- ACK: load current account/link and owned outcome scope/header in the same context. Validate exact requested proof and committed cursor, mutate retention once, mutate account ACK/link/sequence, bump scope clock and save once. Retry preserves the first successful acknowledgedAt. A failed combined save leaves both unchanged.
- Retention: prepare at most the existing bounded inventory work, then evaluate dependency states with supplied-context exact owner reads. Missing historical owner never supplies authority or grants deletion. Remove one bounded member chunk/header/scope/inventory transition and update the active account sweep cursor in that same save. Do not persist the journal before cursor encoding can fail.
- Terminal settlement: current checkpoint and current account dependency state use the same context. All exact outcome proof and original-preservation checks remain in pure policy. Only a changed durable account transition authorizes success/ACK linkage.
- Snapshot caches: legacy Saved/positions cache setters use the same operation and clock. They continue their current policy until the coordinated four-consumer cutover; this prerequisite must not quietly claim row Saved revision authority.

A prepare-inventory helper may remain a separately verifiable bounded unit when called outside combined account work. Inside a combined operation use its in-context body without its own save. Inventory backfill must check deletion through the supplied context so a stale intent read cannot regenerate clock/index data for an erasing scope.

## Clock/export/erase constraints

The clock is scoped by subject+namespace, shared across current and historical owner keys. Every export-visible account mutation bumps it in the same save. A clone changing pending/confirmed/recovery/positions or queue receipts therefore invalidates an earlier fence even without Saved/outcome page changes. Existing old accounts may have no clock: export capture must establish a present clock for such an owned account, or explicitly reject until one is established. It must never issue `.empty` while any account partition exists in scope. Empty-fence validation must include account presence alongside Saved/journal evidence.

Do not delete/reset the clock when pruning or erasing one owner's journal while another current/historical account row survives. Full deletion must retain the erasing fence while the scoped account cleanup is pending. Prefer bounded scoped account removal; when all account/Saved/outcome/inventory/artifact data is gone, transition identityPending consistently. Clear deletion intent last after verified identity success and empty-scope checks; only then remove an otherwise unnecessary clock. A retry must not manufacture a new clock incarnation that makes older artifacts appear valid.

Export owner/deletion validation must use the same fresh supplied context as the clock/artifact checks. Historical partitionless evidence remains separately readable/exportable for the correct subject/deployment; do not require recreating its erased account row. Current-owner admission and historical evidence retention are different rules. Artifact file creation/remove/rename remain external effects with durable retry metadata; a single SwiftData save cannot make filesystem operations transactional.

## Saved/outcome producers and deletion

Existing Saved admission (`savedOwnerActive`, `savedHeader`) already accepts a supplied fresh context for deletion/clock checks. Reuse exact owner checks where production authority needs an active account, while retaining explicit historical evidence read APIs. `collectOutcomeStep` and post-await persist must each admit the captured owner in the context that saves its scope/header/page. No ModelContext fetched before network await should be reused for a late save. MainActor prevents interleaving during the synchronous save operation, but every await creates a new admission boundary.

Begin deletion saves exact intent+erasing clock once. Final backend-complete cleanup must re-read current intent after each yield, preserve scope, and never use a cached deleted account object to recreate state. Imported/legacy identityPending intents should not be reported as ready for external identity cleanup while matching account/journal/artifact rows remain; fail closed with recoverable local cleanup rather than silently clearing evidence.

## Minimum useful verification

1. Public cached/reopened command-writer and account-only export-fence regressions proposed by the parent, with all exact operation IDs retained and guest edit control.
2. Prime the original guest context, claim from reopened store, then original guest read/edit; late new guest original survives and claimed originals stay claimed. Repeat account claim/reopen with frozen/client/sequence/invalid recovery invariants.
3. Combined ACK/journal/partition failure path retains exact originals/cursor/ACK age and retries once; retention resumes with bounded rows and a consistent cursor. Distinguish logical thrown callback rollback from a real ModelContext.save failure; the actual recoverable iOS save-failure gate remains open unless deliberately injected and proven.
4. Current-owner erasure with same-subject sibling owner/deployment and old-owner orphan evidence. Account rows prevent early clock removal; phase clear never authorizes a late captured write. Export retains correct orphans but excludes foreign data.
5. Old on-disk account without clock gets safe export admission, then cloned queue change invalidates. No-op replay/read and guest-only mutation preserve the fence. Run existing native parity suites and inspect actual results before reporting success.

These are local implementation constraints, not a reason to request cloud approval. The proposed prerequisite moves toward the selected full Saved cutover but does not itself switch the four consumers or production UI. Full A2, throughput, installed/SDK/cross-device/device and actual iOS save-failure gates remain open.
