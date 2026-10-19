# Account deletion integration work still required

October 19. Parent-identified lifecycle gap during actual A2 integration. This is
an implementation contract, not evidence the lifecycle is repaired.

Current native deletion invalidates the sync owner, deletes the bound backend
account, erases its local partition, then deletes the captured Clerk user. If the
backend deletion succeeds and Clerk deletion fails or the process stops, later
automatic activation can bootstrap that same Clerk subject again. The old account
must not be recreated or pending private data replayed after an erasure request.
The missing-account case also needs retry without an expired/deleted binding.

Implement a durable deletion record keyed by deployment namespace plus verified
Clerk subject, with server-pending and identity-pending phases. Persist intent
before deleting anything; LibrarySync checks it before bootstrap/open. A storage
failure therefore cannot authorize new cloud writes while deletion state is unknown.

Use a JWT-derived existing-account binding/missing result that never bootstraps a
user. Its response includes the verified subject, checked against the captured
native session before effects. If the row exists, return a fresh opaque binding;
if already absent, return that verified absence. No client user ID argument.

After confirmed backend erasure, atomically mark identity-pending and remove all
local partitions for that subject/namespace. Never touch the current account B
when a delayed response belongs to A. Delete only the captured Clerk user and
check the active session again before that SDK call. Retry a pending deletion
through the existing Delete action; do not silently delete identities on sign-in.
Clear the deletion marker after verified identity deletion/local cleanup succeeds.
Account creation remains blocked while either pending phase exists.

Prove response loss, restart in both phases, account switch before each await,
local save failure, backend-already-missing and Clerk deletion failure. Inspect
installed Clerk User.delete endpoints and retain actual SDK/device proof separately.
Local pending/recovery export is now implemented and locally verified in
`../../LIBRARY_SYNC_EXPORT_VERIFICATION.md`. Actual SDK/file-picker/device checks
remain open. It captures the original owner before the dialog/device check and
validates the binding before reading server data and before file creation.

Other integration follow-ups: native invalid pending admission, >500-member folder
continuations, vanished anchors, installed-schema and suspended-commit cancellation,
plus final independent/native UI review. None is a reason to claim A2 complete.


## Root cause beyond one installation

A local deletion marker alone is insufficient. Another still-authenticated device
can call `ensureCurrentUser` after backend erasure while Clerk deletion is pending.
A server-owned deletion marker keyed by a digest of the verified Clerk subject
must block every user bootstrap. Current source has one production `users` insert,
in `ensureCurrentUser`; there is no Clerk webhook user-upsert in this checkout.
Future creation paths must share this guard. A response-loss retry must not recreate
a user just to obtain a binding.

Use a read-only-in-effect preparation step that derives the subject from JWT and
returns a fresh short-lived opaque deletion authorization, including when no user
row remains. Verify its returned subject against the captured native session before
requesting erasure. The subsequent erasure mutation verifies both the authorization
and its JWT subject before writing a marker or touching private data. The native
client never supplies a user identity argument. Keeping preparation separate from
erasure prevents an A request delivered under B's token from starting B's deletion
before the native subject comparison.

The server marker must survive a `user.deleted` event long enough to reject old
JWT replay; do not delete it immediately upon a webhook. Its minimum retained digest,
retention/revocation policy, and production privacy treatment need explicit evidence.
Do not add a Clerk backend secret or server-side identity-delete integration under
the earlier A1 approval.

## Installed SDK evidence and caller constraints

The installed iOS `User.delete()` delegates to `UserService.delete()`, which constructs
`DELETE /v1/me` and `_clerk_session_id` from `Clerk.shared.session?.id` before its
first network await. Android 1.1.4 `UserKt.delete` dispatches `UserApi.deleteUser`;
bytecode for its default argument reads `Clerk.session.id` synchronously before the
suspending call. The captured User object's ID does not select the request account.
The source/bytecode inspection used local package caches, not real deletion calls.

Serialize the immediate session guard and SDK request construction on the native
main executor with no await between them. Verify actual request and late SDK auth
events in the real SDK gate. Capture the deletion confirmation's account when the
dialog opens, including on restart when LibrarySync intentionally cannot activate
a pending-deletion account. A dialog opened for A must never delete B after switching.

The read-only consultant for this question failed at the usage limit without a
report. These constraints are the parent's source findings, not an independent
review. Two implementation alternatives remain: native identity deletion with a
persistent local phase plus server erasure authorization/deny marker, or a durable
server deletion job using Clerk management credentials. Prefer the former within
the existing authorized product/credential scope; the latter introduces unapproved
cloud credentials and service effects.
