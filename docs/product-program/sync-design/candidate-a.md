# A2 candidate A: versioned snapshot and exact receipts

## Problem

Both native sign-in paths snapshot SwiftData/JSON guest drafts, await `guestMerge:mergeGuestData`, then `clearAll`; an edit during the await is deleted without being sent (`AppEnvironment.swift:232-318`, `SessionManager.kt:124-148`). Aggregate skipped counts cannot distinguish duplicate preservation, cloud conflicts, missing targets, or unresolved folder membership (`/tmp/hadithly-sync-server-trace.md`). Boolean Clerk/Convex authentication and unscoped Saved subscriptions also cannot prove which account owns a queued result. The shape must preserve each exact local version through retries while keeping Convex as the only mobile API and deriving the owner exclusively from verified JWT.

## Usage (caller's view)

Native call sites invoke a single deep coordinator. They no longer build wire dictionaries or call `clearAll`.

```swift
// AppEnvironment.completeSignIn, after Convex auth and ensureCurrentUser:
await guestSync.activate(clerkSession: Clerk.shared.session?.id, transport: convex)
library.activate(scope: guestSync.currentAccountScope)
// Guest save paths keep writing GuestDataStore; it notifies guestSync of a revision.
guestData.saveNote(/* existing arguments */)
// RootView/Settings sign-out or switch:
guestSync.deactivate(); library.deactivate()
```

```kotlin
// SessionManager.completeSignIn, after ensureCurrentUser:
guestSync.activate(Clerk.sessionsFlow.value.singleOrNull()?.id, repository)
library.activate(guestSync.currentAccountScope)
// Existing GuestDataStore writes remain the data source; coordinator observes revision changes.
guestData.saveProgress(draft)
// On empty/different Clerk session:
guestSync.deactivate(); library.deactivate()
```

`activate` starts a bounded drain, returns once the initial attempt reaches a stable result, and keeps a retry worker for unsent versions. Failure leaves recoverable drafts. The view sees sync status, never a transport receipt or token. `library.activate` is a domain scope switch; it may render only values tagged with that scope.

## Shape

```ts
type LocalRevision = string;          // persisted monotonic per-device revision, never wall clock
type OperationId = string;            // persisted, stable across retry and process restart
type GuestOperation =
  | { kind: "folder"; opId: OperationId; revision: LocalRevision; localFolderId: string; name: string }
  | { kind: "bookmark" | "favorite"; opId: OperationId; revision: LocalRevision;
      hadithId: Id<"hadiths">; present: boolean; createdAt?: number }
  | { kind: "note"; opId: OperationId; revision: LocalRevision;
      hadithId: Id<"hadiths">; content: string | null; updatedAt: number }
  | { kind: "membership"; opId: OperationId; revision: LocalRevision;
      hadithId: Id<"hadiths">; localFolderId: string | null; dependsOn?: OperationId }
  | { kind: "position"; opId: OperationId; revision: LocalRevision;
      collectionSlug: string; position: ReadingPosition | null };
type Batch = { batchId: string; operations: GuestOperation[] }; // no account/user ID
type Receipt = { opId: OperationId; revision: LocalRevision;
  outcome: "preserved" | "conflict" | "rejected" | "resolved";
  reason?: "newer_cloud" | "missing_target" | "missing_folder" | "changed_anchor";
  serverFolderId?: string; resolvedPosition?: ReadingPosition };
type MergeReply = { receipts: Receipt[] }; // exactly one per submitted op, keyed by opId

// Server: JWT owner only; `binding` is opaque, short-lived and never a user ID.
beginGuestSync(): Promise<{ binding: string; validUntil: number }>;
mergeGuestBatch(args: { binding: string; batch: Batch }): Promise<MergeReply>;
// Client-owned deep module; wire parsing and batching are private.
GuestSync.activate(sessionHandle: string, transport: MergeTransport): Promise<SyncStatus>;
GuestSync.deactivate(): void;
GuestSync.onGuestRevision(): void;
GuestStore.captureBatch(limit: { operations: 25; bytes: 65536 }): PersistedBatch | null;
GuestStore.applyReceiptsIfCurrent(batch: PersistedBatch, reply: MergeReply, scope: AccountScope): void;
```

The local store holds current guest records with a revision for each facet, folder membership, and semantic position, plus **one persisted immutable in-flight snapshot**. This is not an append-only operation queue. `captureBatch` groups up to 25 operations / 64 KiB, orders folder creation before membership, and stores stable operation IDs before network send. Every mutation of a local record allocates a later revision; removals during an in-flight add become revisioned tombstones so the later delete is not lost. `applyReceiptsIfCurrent` verifies that each receipt matches a sent op and revision. It removes only an exact current revision with `preserved`; newer revisions remain for the next batch. `conflict`, `rejected`, and transformed `resolved` versions remain in a recoverable, account-scoped pending section for explicit reconciliation. An empty/sanitized-out draft is never acknowledged. This is the one local authority for cleanup on both platforms.

The server parses and caps the batch at admission, resolves the account with `requireIdentity`, validates a server-minted binding against that JWT owner, and processes the batch atomically. It stores a compact owner+opId receipt ledger in the same transaction; a lost response is retried with the same IDs and returns the stored receipts without replaying writes. Exact semantic equality or a successfully applied value is `preserved`; a newer/equal-but-different cloud note/position/membership is `conflict`; missing hadith/folder is `rejected`. Folder receipt returns the server folder ID for dependent membership. A nearest-anchor position is `resolved` with the actual position, never called an exact preservation. Owner+hadith indexes replace full-owner facet scans. Idempotency ledger has a documented retention floor longer than all client retry windows; expired pending snapshots require a fresh reconciliation read, not unsafe replay.

The binding is essential because the actual Swift `ClerkConvexAuthProvider` exposes `AuthState.authenticated(String JWT)`, binds the global current Clerk session, and may refresh from that session. A true auth boolean is insufficient, and we do **not** assume the SDK pins an in-flight request to the earlier session. `beginGuestSync` returns an opaque binding stored server-side with the JWT-derived owner; `mergeGuestBatch` compares the binding to the *JWT owner of that mutation* before any write. The client does not send an account ID. On activate, the coordinator associates the snapshot with a private local account scope obtained from an authenticated server principal/binding response, and checks that same scope plus a local generation before cleanup. On sign-out/account change it cancels its worker, invalidates the generation, clears rendered private data, and keeps A's pending snapshot isolated; A can resume only after the same server-owned scope is confirmed. If a request already committed under A, B cannot claim its receipt or its drafts. The server binding prevents a globally refreshed token for B from applying A's payload to B.

Saved snapshot and position subscriptions carry a captured account scope and local generation through their collector closures. `refresh` closes old collectors on any scope transition, even signed-in A→B; each emission checks the captured generation before rendering. The guest view uses only guest records. This is a client display fence, not a substitute for JWT ownership. Account scope and binding are never written to logs; no note text, position, token or private identifier enters diagnostics.

The drain uses one active worker per scope, finite exponential backoff for transport errors, and immediate resnapshot after a preserved receipt if newer revisions exist. Conflicts/rejections stop automatic retries of those exact revisions and surface bounded recovery status; the worker keeps draining independent accepted work. On process restart, the persisted batch is retried under a freshly verified same-account binding with the same opIds. Batch payloads and reply are bounded; note bytes and folder count are rejected at admission. Network send, receipt decision and local compare-remove are covered by one testable coordinator using injected transport and store clock/scheduler.

## Synthesis decision

Candidate A only; arena synthesis pending.

## Tradeoffs accepted

- We accept an extra authenticated binding round trip and small server receipt ledger in exchange for proving a refreshed global auth provider cannot attribute an older payload to a new account.
- We accept recoverable account-scoped conflicts rather than silently dropping or endlessly retrying them.
- We accept one persisted snapshot and per-record revisions instead of a general durable operation log; the current guest store remains the source of truth.

## Alternatives considered

- A one-shot `clearIfUnchanged` after the old aggregate response protects newer local writes but still discards skipped/missing items and cannot prevent a request from landing under another account. It exposes server conflict rules to callers and has a shallow interface.
- Client-only Clerk-session checks before/after mutation cannot prove the JWT used by a queued or refreshed request. They hide no server ownership policy and fail the cross-account invariant.
- A full durable outbox records every edit before sync; it is a structurally different ownership model with more event lifecycle and compaction machinery than the existing guest snapshot needs. Compare it independently in arena.

## Open questions and risks

- What exact SDK callback or server principal query gives a stable authenticated account scope without treating the raw JWT string or boolean auth state as identity proof? Inspect the installed SDK before coding the adapter.
- What retention period and reconciliation path cover a snapshot restored after the server receipt ledger expires?
- Which membership conflict rule should win when an offline guest move and a newer cloud move collide? The chosen rule must be encoded in per-operation receipts.

## Next implementation step

First write the red coordinator test through both real stores: save note and semantic position, pause transport after persisted snapshot, make newer edits, return mixed receipts, then assert exact-version cleanup, retained conflicts, and a second bounded send under the same verified scope.
