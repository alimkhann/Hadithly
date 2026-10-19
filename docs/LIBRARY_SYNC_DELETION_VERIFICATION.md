# A2 deletion retry and recreation guard, local verification

October 19, 2026. Follows `65276cb` and `b5c7ead`. Local implementation and tests
pass. Actual Clerk deletion, private account/device calls, deployment, final
independent review and full A2 acceptance remain open.

## Reproduced defect

The actual local Convex functions accepted `deleteCurrentUser`, then
`ensureCurrentUser` recreated the same Clerk subject. The red test resolved a new
user ID instead of rejecting with `ACCOUNT_DELETION_PENDING`:
`/tmp/hadithly-account-deletion-bootstrap-red.log`. Its first diagnostic also had a
scheduled-function cleanup error. The final tests explicitly drain that work under
fake timers; the successful recreation is the product defect, not the timer error.

Native callers also required a live library owner/binding to retry, despite the
first successful backend deletion having removed both. A lost response or failed
Clerk deletion could therefore leave an account unable to finish deletion.

## Implemented boundary

Preparation derives the subject from JWT and returns a fifteen-minute opaque
authorization, including if the user row is already absent. It creates no user and
starts no erasure. The native state machine compares the returned subject with the
session captured when the confirmation dialog opened. Erasure checks both the
JWT subject and authorization before any private effect. No client identity
argument is accepted. Authorizations are stored as digests, bounded to twenty live
records per subject, pruned on preparation and consumed on successful erasure.
A lost-response retry obtains a fresh authorization without recreating a user.

One atomic mutation records a subject digest against recreation and performs the
existing account erasure. Every current production user insert goes through
`ensureCurrentUser`, which checks that marker. A deleted subject cannot bootstrap
from another still-valid session while Clerk deletion is pending. A genuinely new
Clerk subject can still create an account. The quota deletion fixture now verifies
that new subject's access to global in-flight/cache state, with no charge retained
for the deleted account. It no longer relies on recreating the erased subject.

Both apps persist a deployment-and-subject scoped deletion intent before erasure.
`serverPending` retries preparation/erasure. Confirmed erasure atomically removes
all matching local library partitions and advances to `identityPending`. That
phase retries only identity deletion. Library activation and guest claiming reject
pending-deletion subjects before bootstrap, preserving unclaimed guest data.
Neither retry depends on an active library owner. Other accounts and deployments
remain intact. Only successful identity deletion clears the local marker.

A delayed verified A erasure response may finish A's local erasure after switching
to B. It cannot delete B's identity, partitions or local evidence. Confirmation,
preparation, erasure result and immediate identity-call session checks all retain
A. The immediate guard and installed SDK call run on the native main executor.
SDK source/bytecode construction of `/me` uses the current session; a captured User
object alone does not bind that request. Actual request capture and late SDK auth
events are still required. Controlled callbacks do not prove those SDK effects.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Backend strict typecheck | Pass | `/tmp/hadithly-account-deletion-verified-typecheck.log` |
| Complete backend suite | 391 tests, 34 files pass, no unhandled errors | `/tmp/hadithly-account-deletion-verified-backend.log` |
| iOS stores/core/facade, presentation and Settings helpers | 43 pass | `/tmp/hadithly-account-deletion-ios.log`, `.xcresult` |
| Android stores/core/facade and wire adapter | 22 pass | `/tmp/hadithly-account-deletion-final-android.log` |
| Generated native wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| Updated disposable E2 verifier syntax | Pass, not executed against cloud | `node --check backend/evidence_processor/verify_convex.mjs` |
| Whitespace | Pass | `git diff --check` |

New actual Convex cases cover post-erasure bootstrap, wrong-JWT authorization with
no B marker or deletion, preparation without effects, expired authorization,
retry after the user is gone, a never-bootstrapped account, private-row removal and
minimal marker contents. Existing evidence, subscription, quota and export erasure
fixtures use the new authorization contract and still pass.

Both real native stores are reopened after a simulated lost erasure response and
a later identity failure. The phase survives each reopening; core activation makes
zero bootstrap calls in both phases. Identity-only retry makes no second server
erasure call. The fixtures also cover wrong preparation subject, switching during
erasure, an old confirmation after switching, preservation of B and another
deployment, and A-only cleanup. Android additionally preserves a damaged original
file and makes zero cloud or identity calls when deletion intent cannot be read.
These are real storage plus controlled transports, not process-kill or SDK proof.

## Remaining gates

- Real authenticated SDK request/account binding, identity failures/re-login,
  interruption, late auth events and cross-device erasure propagation. A second
  device's server bootstrap is denied, but automatic local erasure on that device
  has not been implemented or proved. Its failed bootstrap currently uses the
  generic retry path.
- Physical deletion confirmation/undo-free privacy UI, iOS storage-save failure,
  cancellation during Android commits, actual process death and installed-schema
  migration. The new SwiftData model's additive creation/reopen tests are not an
  old installed-store migration matrix.
- Account-scale erasure remains one transaction. Large accounts, >500-member
  folders, vanished anchors, old frozen invalid intent and bounded quarantine
  still need their A2 work.
- Server marker retention, unused/expired preparation authorization maintenance,
  revocation and published privacy treatment. Subject digests remain linkable
  security data, not anonymous data. Markers intentionally do not disappear with
  the deleted user or a future Clerk webhook, because old JWTs may remain valid.
- Coordinated native/server schema and endpoint cutover, final independent review
  and A2 deployment/private test-write approval. Older clients do not have the new
  required authorization argument. No legacy fallback bypass was added.

The earlier A1 development approval does not authorize this deployment. The E2
verifier source now obtains and verifies deletion authorization for future approved
runs and reports the retained minimal marker honestly; no such run occurred here.
All broader A1/A3-A7, research, native refinement, website, Linear and release gates
remain in `PRODUCT_PROGRAM.md` and the existing session records.


Follow-up: indexed expired preparation-grant maintenance is now implemented and
locally verified in `ACCOUNT_DELETION_MAINTENANCE_VERIFICATION.md`. Its actual cloud
cron and retention-policy gates stay open; the checkpoint above is historical.
