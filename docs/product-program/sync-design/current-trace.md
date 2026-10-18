# A2 sync boundary, current trace

October 18. This is a source trace and a local diagnostic, not cross-device proof.
The complete program remains in `docs/PRODUCT_PROGRAM.md`.

## Reproduced defect

Both `AppEnvironment.completeSignIn` and `SessionManager.completeSignIn` read guest
data, build a sanitized payload, await `guestMerge:mergeGuestData`, and call the
store's unconditional `clearAll` on success. Local edits made after that snapshot
are therefore not in the request and are nevertheless deleted on completion.

The diagnostic uses each platform's real persistence store, not a mocked list.
It captures a valid note/position payload, makes a newer local edit and position,
then performs the existing sign-in cleanup step. Android reports expected new
note but null; iOS reports both the missing new note and missing newer position.
The Android positive control confirms the edit and position exist before cleanup.
No cloud or authentication was used, and this is not a test of actual sign-in.

Reproduce with the focused test commands represented in:
- `/tmp/hadithly-guest-merge-race-red-android.log`
- `/tmp/hadithly-guest-merge-race-control-android.log`
- `/tmp/hadithly-guest-merge-race-red-ios.log`
- `/tmp/hadithly-guest-merge-race-red-ios.xcresult`

At reproduction time the temporary diagnostic called the same store operations as
the sign-in call sites. The current tests exercise the new coordinator and actual
stores; they do not call either production sign-in lifecycle yet. The chosen implementation must turn them into tests through
the production merge-completion boundary and migrate both callers. A store test
alone must not claim to verify Clerk, Convex, cancellation or account switching.

## Current ownership

- SwiftData owns iOS guest facets, folders/membership and reading positions.
  Android owns equivalent JSON under a Mutex. Planner values are detached from
  the store. Sanitization deduplicates and filters invalid IDs before sending.
- Both sign-in lifecycles wait for Convex authentication, ensure the user row,
  adopt stored preferences and merge. Swift builds the wire dictionary in
  `AppEnvironment`; Android uses `ConvexRepository.mergeGuestData`.
- Convex `guestMerge:mergeGuestData` derives the owner from the verified JWT.
  Clients must never supply their own user identity. The mutation creates private
  folders and facets, uses newest-note/position conflict rules, and returns counts.
  Several skipped counts conflate an already-present/newer cloud value with a
  missing hadith. Counts alone do not identify which local entries are safe to
  discard. That response must be examined before treating success as all-acked.
- The private Saved snapshot and independent reading-position subscriptions feed
  each native UserLibraryModel. Both refresh implementations use a boolean
  signed-in predicate and subscriptionsActive guard. Account-change and stale
  emission behavior needs proof, not inference from a green store test.
- Android SessionManager has one global syncInFlight flag and one launch-session
  flag. iOS has no equivalent in-flight guard in completeSignIn. Exact session
  ownership, cancellation, restart, residual drafts and error paths require trace
  and tests before changing that lifecycle.

## Design requirements

Preserve all Saved facets, private folder membership, semantic positions and
idempotent merge/conflict behavior. Cleanup may acknowledge only the sent and
accepted version. Unsent changes, rejected/missing targets and transport failures
must retain recoverable local data. Newer local edits must eventually sync without
requiring another manual sign-in. Account transitions must prevent stale results
or queued work from appearing in or being attributed to another account. Reading
stays guest-safe. Convex remains the only mobile API. No user-ID arguments,
credentials, note text or private account identifiers may enter evidence logs.

Compare complete designs rather than patching clearAll in isolation. Include the
minimum actual types, caller usage, module ownership, receipt semantics, bounded
batch/retry behavior, account lifecycle and deterministic verification seams.
Keep live cross-device sign-in/write proof distinct from local test evidence.
