# Candidate B: claimed guest partition and durable account outbox

## Problem and grounded constraints

`guestMerge:mergeGuestData` derives the owner through `requireIdentity` (`backend/convex/guestMerge.ts:81-92`), resolves folders before facets (`:95`), merges canonical Saved rows (`:199-265`) and positions (`:277-308`), then returns aggregate counters (`:311-322`). Counters conflate rejected targets and retained cloud winners. Both clients clear their entire guest store after success. A newer local note or position is deleted although it was never sent. Native subscriptions use boolean authentication and apply responses without account epochs (native trace). Swift's ClerkConvexAuthProvider fetches from the current global session: an authenticated boolean or post-await epoch check cannot prevent a queued write being authenticated as another user. The server must reject wrong-owner dispatch before private writes.

## Usage (caller's view)

```swift
// AppEnvironment: invoked for restored sessions and explicit sign-in alike.
await librarySync.activate(session: currentSessionHandle)
// Guest and account writes go through existing library methods; these now persist
// in the active partition before network dispatch. Caller never clears stores.
await library.saveNote(target, text: text)
await librarySync.deactivate() // invalidates render epoch immediately; cancels workers.
```
```kotlin
// SessionManager: one coordinator owns auth transitions, retries and subscriptions.
sync.activate(sessionHandle) // idempotent for the same session; replaces older epoch.
library.saveReadingPosition(position) // durable optimistic write, then worker wake-up.
sync.deactivate()
```
```ts
// Native transport adapter, internal to LibrarySync; not a consumer-facing API.
const binding = await convex.mutation(api.librarySync.openBinding, {});
// Compare returned verified subject with captured Clerk account BEFORE claiming guests.
const batch = localStore.claimAndFreeze(binding.account, MAX_OPERATIONS);
const receipt = await convex.mutation(api.librarySync.applyBatch, {
  binding: binding.capability, batchId: batch.id, operations: batch.operations,
}); // No user identity request field. Capability is opaque and never logged.
```

## Shape

```ts
type Partition = {kind: "guest"; generation: string}
  | {kind: "account"; localOwnerKey: string}; // local-only, never sent as identity.
type LocalRevision = string; // generated persistently, never wall-clock equality.
type FrozenBatch = {id: string; ownerPartition: Partition; operations: readonly Operation[]};
type Operation = {id: string; revision: LocalRevision; payload:
  | FolderCreate | BookmarkSet | FavoriteSet | NoteSet | MembershipSet | PositionSet};
// Facet set supports present/absent. Membership supports explicit null. Position
// retains full semantic anchor and raw hints; notes retain original timestamps.
type Receipt = {batchId: string; results: readonly OperationResult[]};
type OperationResult = {id: string; revision: LocalRevision; outcome:
  | {kind: "preserved"}
  | {kind: "superseded"; winner: CanonicalFacetValue; reason: "newer_cloud" | "tie_cloud"}
  | {kind: "unresolved"; reason: "missing_target" | "missing_folder" | "invalid_position"}
  | {kind: "resolved_position"; position: ReadingPosition}};
// Wire validation/types private to adapter; native consumer sees LibraryState.
interface LibrarySync {
  activate(session: SessionHandle): Promise<void>;
  deactivate(): void;
}
// Store capabilities internal to coordinator, atomically persisted:
// claimGuests(owner); recordWrite(partition, facetKey, value); freezeBatch(owner, limit);
// settle(batchId, receipt); loadProjection(owner); loadRecoverable(owner).
// Every method implemented against SwiftData transaction / Android mutex+atomic file.
```

One native `LibrarySync` module owns durable partitions, scheduling and render ownership; existing `UserLibraryModel` delegates persistence/network policy rather than adding another independent worker. `GuestMergePlanner` becomes internal migration/normalization logic, not the owner of cleanup semantics. Backend `librarySync.ts` owns binding and operation receipts and calls existing library domain helpers; migrate the two guest merge callers and retire their clearAll/count path together. Keep current read queries but wrap application in epoch fencing. This is a deep interface: consumers state session and intent; do not coordinate snapshot/ack/retry stages (per minimize-reader-load and boundary-discipline).

## Separation before sharing

On first verified account binding, one local transaction moves current guest generation into that account partition, records the claim and opens a fresh guest generation. It does not copy then clear. Pending account data is invisible to signed-out state and other accounts. Guest writes racing the claim land entirely before it in the claimed partition or after it in the new guest generation; neither is deleted. While the captured session is active, subsequent user writes use its account partition; stale queued UI writes retain their captured partition or fail for stale ownership, never consult mutable current account at execution time.

Claimed drafts immediately project into that account's optimistic library. Freezing a batch makes its bytes and operation IDs immutable; later edits append new revisions outside that batch. Same-facet pending unsent revisions may coalesce, but in-flight revisions remain immutable. Receipts settle only exact operation ID+revision. Server-winner conflict retires the attempted operation automatically and stores the losing local value in private account-scoped recovery storage; it does not block unrelated sync or require a queue the operator/user must process. Unresolved content is parked with reason and retried only on relevant content change or explicit retry. Do not silently evict recovery data with a small ring buffer; integrate account deletion/explicit recovery erasure and document storage limits.

## Ownership handshake and subscriptions

Add authenticated `openBinding({})`: server derives user via requireIdentity, returns verified subject plus random opaque capability, and stores capability hash→owner. Client compares the returned subject with the captured local Clerk user/session epoch before claiming or dispatching data. Return identity is private runtime control data, never analytics/evidence logs. `applyBatch` requires capability and checks its stored owner equals the request JWT owner BEFORE operation application. A queued A batch dispatched under B therefore fails with no private writes. Binding is an authorization guard, not a user ID argument or a replacement for JWT. Capabilities are short-lived, app-private and refreshed with the same handshake; expiry never causes reclaim/reassignment of account drafts. Exclude capabilities from crash reports.

A queued openBinding may authenticate B; its response comparison rejects it. A stale applyBatch may finish under A after sign-out; that's safe attribution to A and its receipt settles only A's durable partition. It never paints B's projection. Keep local epoch+account fences before/after every await and subscription emission; deactivate cancels workers, clears rendered private arrays, and invalidates old handlers synchronously. Reactivate restarts both Saved and position subscriptions even when previous state was authenticated. Subscription errors/retries retain captured ownership. Prefer binding-aware query wrappers returning private verified owner tag with the payload, checked before applying; otherwise a queued subscription could start under B while labeled A. No auth UI/config changes.

## Server reconciliation and idempotence

Use `syncBatches` indexed by JWT owner+batchId storing request digest and receipt. Same digest returns same receipt; mismatched reuse rejects. Transaction commits effects and receipt atomically. Retain ledger until client settlement acknowledgement plus bounded recovery window; clients must not resend expired ledger batches without reconciliation. Simpler initial policy: retain account-private receipts until account deletion, with hard per-account storage admission cap and explicit actionable failure rather than unsafe expiry.

Reuse earliest add and strict newest-note/position policies; equal differing values report superseded, not preserved. Membership compares its own version/timestamp so a replay cannot overwrite a newer cloud move. Server-winner facet payload is private reconciliation data. Resolved nearest positions are explicit transformations; settle them automatically into canonical projection while keeping original recoverable. Unknown targets are not preserved. Tombstones for set-absent facets prevent delayed add replay resurrecting deletions; guest adds carry their original timestamps and are reconciled against those tombstones. Existing set/remove mutations must share this comparison helper, or the outbox can race normal direct writes. Route all native account writes through the outbox; do not maintain competing direct-write ownership.

Folder operations precede dependent membership in bounded batches; explicit local operation IDs map to owner-scoped server folder IDs in persisted mapping/receipts. Name reuse remains the current normalized-name policy. A missing dependency parks only its membership. Incoming malformed batch rejects atomically; domain failures return explicit operation outcomes.

## Bounds, restart and eventual delivery

Admission bounds: e.g. 50 operations / 128 KiB per batch and existing domain note/folder limits; one worker per account partition, one active account network worker. Stop on auth mismatch, permission error or binding expiry; reconnect/rebind only after fresh captured-session check. Transport retry uses capped exponential backoff+jitter and connectivity wakeups; pending work persists across process death. Frozen batch resends identically after ambiguous commit. On restart restore the current Clerk account, handshake, then resume only its partition. Never auto-send another account's backlog or re-claim already claimed guests.

Replace per-item full-user bookmark/favorite scans with owner+hadith indexes. Bound vanished-position fallback query or return unresolved requiring existing reader resolution path; a limited scan must never claim nearest globally. Read snapshots remain potentially unbounded existing behavior; scope new operation/write path limits explicitly and retain snapshot scaling as separate work unless needed for correctness.

## Tradeoffs accepted

- Accept local schema/outbox migration and facet tombstones for durable writes during sign-in, restart and transient failure; this is larger than compare-and-delete but resolves eventual sync at one owner.
- Accept server binding state because current-session token fetch makes client-only account fencing insufficient to prove attribution.
- Accept private recoverable losing values while selecting cloud winners automatically; ordinary sync has no mandatory conflict queue.
- Accept a bounded receipt ledger/storage gate until a complete compaction protocol exists; silently expiring idempotency is unsafe.

## Alternatives considered

- Snapshot plus revision acknowledgements: smaller migration and fixes cleanup; loses eventual-delivery ownership unless another queue/scheduler is added, and still needs the same transport guard. That scattered responsibility is the principal rejection.
- Per-session isolated Convex client with immutable captured JWT: could avoid capability state, but SDK refresh/reconnect token ownership and account changes are not proven. Requires source-backed adapter and integration tests before replacing the binding guard.
- Local receipt inferred from subscription equality: shallow implementation but exposes timing and conflict policy to every caller; absent targets and changed values cannot be acknowledged reliably.

## Synthesis decision

Candidate B only; parent selects and grafts after comparison. Screened against runner red flags: domain state is hidden inside one coordinator; local/wire types do not become UI API; stages are internal implementation rather than separate public modules.

## Implementation sequence and proof seam

1. Define typed operations/receipts and implement pure reconciliation against existing facet rules; tests establish missing/equal/newer/mixed facet outcomes and membership replay protection.
2. Implement authenticated binding + ledger + applyBatch and query-owner wrapper; deterministic fake-JWT tests queue A request and execute under B, asserting zero writes. Inspect actual SDK queued dispatch/refresh with fake transport rather than assuming cancellation.
3. Migrate native guest storage atomically into partitions/outbox with crash-before/after claim/freeze/receipt checkpoints; route both production sign-in callers through LibrarySync and turn parent's real-storage red tests green through this boundary.
4. Route account writes through durable operations, fence projections/subscriptions and prove stale responses, newer local edits/deletes, invalid targets, duplicate callbacks, restart and offline replay with injected clock/network/receipt loss. Native tests use real persistence and production coordinator, not duplicated cleanup helpers.
5. Verify full facets/folders/semantic positions iOS→Android and Android→iOS under real approved sign-in, including account switch/sign-out, separately from local green tests. Keep external gate open until that evidence exists.
