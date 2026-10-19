# A2 production caller integration, local verification

October 19, 2026. Continues `0609bf2`. This checkpoint connects the native product
callers to the durable sync core. A2 remains open. No development deployment,
private account writes, paid generation or production changes were performed.

## Result

Both native sign-in paths now activate the coordinator using the current active
Clerk session. The coordinator verifies the server subject before atomically
claiming guest data. The old snapshot/send/unconditional-clear path is removed.
Account bookmarks, favorites, notes, folders, membership, conditional undo and
semantic reading positions persist in the captured account's queue before send.
A failed local note write keeps the editor open with its text and a retry message.

Saved and position subscriptions remain separate. Their generated DTOs carry a
server-derived owner and a per-domain revision. Each collector checks owner,
captured session and generation before caching or rendering. Account partitions
persist these owned bases, pending and frozen intent, exact folder mappings and
accepted effects. Accepted effects remain visible until the corresponding owned
snapshot revision catches up, including after reopening the real native store.
A position update cannot discard a Saved overlay through an unrelated counter.
Legacy Saved and position writers advance the same relevant counters.

Confirmation dialogs, folder actions and undo capture their original account
scope. Switching accounts clears private presentation and invalidates old actions.
An explicit Remove cannot toggle an absent facet into an add. An already absent
server removal cannot gain authority to undo a different device's actual deletion.
Invalid unsent notes retain their original content in recovery and do not block
later valid work; new invalid account intent returns a failed local save.

Folder undo derives its authorized members from the server's actual deletion
manifest. A stale native member list cannot omit a member that the server removed,
or authorize restoration of an unrelated member. Newer placements remain intact.
Refused facet undo and losing writes remove empty materialized Saved rows.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Backend strict typecheck | Pass | `/tmp/hadithly-sync-integration-final-typecheck.log` |
| Complete backend suite | 388 tests, 34 files pass | `/tmp/hadithly-sync-integration-final-backend.log` |
| Generated native DTO consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| iOS actual stores/core/facade and presentation policy | 32 pass | `/tmp/hadithly-sync-admission-ios.log`, `.xcresult` |
| Android actual stores/core/facade and wire adapter | 18 pass | `/tmp/hadithly-sync-admission-android-fixed.log` |
| Whitespace | Pass | `git diff --check` |

The real-facade fixtures exercise all private library intent types, offline
persistence and store reopening, accepted-note projection under delayed query
revisions, wrong-owner and late read callbacks, A-to-B switching, sign-out, stale
undo, oversized note rejection and explicit absent removal. Their read streams
and RPCs are controlled transports. They do not execute Clerk or network delivery.
The Android wire test proves Double numeric values, omission of optional values
and Unicode/quotes/newlines through the production plain-value adapter required by
the installed Convex SDK. Backend tests execute actual local Convex mutations and
queries, including JWT/binding rejection for preference, export and deletion calls,
independent snapshot counters, payload overhead and stale folder-member undo.

The accepted-note iOS fixture originally asserted settlement immediately after
coalescing an already-running offline attempt. It now waits for the real durable
acknowledgement state with the existing bounded three-second predicate, so it
proves automatic retry after the transport returns rather than scheduler timing.
An added no-op-removal test first failed on a phantom empty Saved row and passed
after cleanup of refused materializations. Initial fixture-name/type typos were
compile repairs, not product regression evidence.

The verification runner disables automatic account sync in native test hosts.
Explicit live tests can still call the normal sign-in completion themselves.
The iOS test host uses the existing automation context. Android sets its test-only
property before Application creation through `HadithlyVerificationRunner` and uses
the already installed AndroidX runner version. This prevents incidental cloud
writes while controlled tests run. No test-user login was performed here.

## Review and limits

The prior receipt protocol at `0609bf2` passed independent gpt-6-sol source review
in `product-program/sync-design/receipt-lifecycle/implementation-review.md`.
A partial independent integration review found the stale folder-member undo P1.
Its report and the parent resolution are in
`product-program/sync-design/integration-review.md`. The final integration has not
received an independent re-review. A later read-only deletion consultation failed
at the account usage limit; no report was produced.

Still required before A2 acceptance:

- Durable account-deletion restart/retry and server-side prevention of recreation
  after backend deletion but before Clerk deletion. Installed iOS `User.delete()`
  builds `/v1/me` using the current session, and Android's extension dispatches a
  default session argument. Capturing a User object alone is not proof that the
  request remains bound to it. No real deletion SDK call was tested.
- Current-owner export of local pending/recovery data, with provider text and
  capabilities excluded, plus account-switch proof across device authentication.
- More than 500 folder members, vanished anchors, account-scale query/export/
  erasure, installed schema/old frozen invalid batches, bounded quarantine work
  and Android storage-commit cancellation. Reopening is not process-kill evidence.
- Actual note-editor failure and confirmation/undo UI checks beyond model/source
  checks, final independent review and device accessibility parity.
- A2 deployment and private test-write approval, then actual SDK/auth and two-device
  iOS-to-Android and Android-to-iOS readback. The new native endpoint/schema contract
  is not deployed; this local build is not a release or installed-cloud proof.

The production caller migration is implemented. These remaining gates must not be
reported as closed by a build or by controlled transport tests. The existing
original Xcode project/scheme/catalog changes remain excluded from this commit.
