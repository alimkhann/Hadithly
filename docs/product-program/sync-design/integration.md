# A2 production integration contract

October 19. Continue from 0609bf2; no deployment is authorized. The previous turn
made progress by implementing and locally verifying receipt compaction. The
remaining contract is the actual native account lifecycle and library facade.

## Caller first

AppEnvironment/SessionManager owns LibrarySync and the verified current Clerk
session {id,subject}. It activates on the active session, not the sessions list,
and deactivates/clears rendering immediately on account transition. Open-binding
bootstrap sends no private guest data. A returned different subject cannot claim
anything. Sign-in calls LibrarySync.activate instead of snapshot/send/clearAll.

UserLibraryModel accepts each Saved/position intent synchronously with a captured
LibraryWriteContext before asynchronous work. Every signed-in facet, folder,
membership, undo and position uses the durable queue. Guest operations keep their
existing native store semantics. Conditional undo captures the deletion operation
ID and original account context at removal, not the current account at undo.

Keep the Saved and position subscriptions separate. Their typed responses contain
the server-derived owner key. Each subscription captures owner/session/generation;
both its payload and callback epoch must match before persistence or rendering.
Never infer ownership from a boolean authenticated state or from raw JWT text.

## Local projection and freshness

Each account partition keeps its last owned Saved and position snapshots, folder
ID mappings and accepted-but-not-yet-observed changes. Pending/frozen changes
project over that private base so offline actions remain visible across restart.
Only exact accepted receipts enter the accepted projection; losing and unknown
changes go to recovery. A folder-create mapping comes from its exact receipt.

An accepted effect must not disappear while a delayed older query result is still
in flight. Two per-owner counters, Saved and position, advance in the same server
transaction as a newly applied batch affecting that domain. A committed receipt
carries those revisions. Owned snapshots carry their corresponding revision.
Accepted projection is discarded only after that domain's persisted snapshot has
caught up. Separate counter rows avoid invalidating Saved on every position write.
Do not substitute wall clocks or current-value equality for causal freshness.

New shared validators generate the owned DTOs and revision values for both apps.
Extract existing dual-read Saved and position query bodies as shared readers;
legacy queries remain available for existing verification/other callers. New
owned queries reuse those readers and preserve exact hadith targets. Measure
payload overhead and keep the two subscription boundaries.

## Proof seams and remaining work

Inject typed read streams and the existing sync transport into the actual library
facade; production adapters use only Convex. Tests drive the production facade,
real native stores and controlled delayed streams/RPCs. Cover all intent types,
offline restart, delayed reads, wrong-owner and late callbacks, A-to-B account
switch, undo after a switch, failed writes and actual sign-in completion ownership.
Actual SDK/auth cross-device tests remain separate and require A2 deployment and
private test-write approval after the local implementation is concrete.

Delete the old unconditional completion cleanup and migrate old direct writes in
the same integration wave. Local pending/recovery export and account erasure,
large folders/vanished anchors, storage cancellation and installed-schema matrices
remain part of A2. Preference/push/purchase account lifecycle must retain current
behavior and use captured session guards; do not turn this into an auth UI rewrite.
