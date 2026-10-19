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
Export must include the current owner's pending/recovery library state without
binding capabilities and must capture its owner before device authentication.

Other integration follow-ups: native invalid pending admission, >500-member folder
continuations, vanished anchors, installed-schema and suspended-commit cancellation,
plus final independent/native UI review. None is a reason to claim A2 complete.
