# Public folder transition contract

October 21, 2026. Parent read both complete candidates and agrees with the judge:
reject A and B unchanged, synthesize smaller C from B's stored capability protocol
and A's explicit new-client entry. A scores15/25, B18/25 before correction. No human
checkpoint is requested; parent implements. No cloud deployment is authorized.

Keep openBinding{} unchanged for old clients. Add openManifestBinding{} with the
same SyncBinding DTO and a defaulted optional manifest-v2 field on the private
binding row. Current native open adapters migrate to that method; shared apply,
poll, ACK and retire dispatch/guard from verified stored metadata. Legacy calls
must fail SYNC_CLIENT_UPGRADE_REQUIRED before consuming or returning a pending,
manifest or split proof from upgraded shared history. A new client may replay an
old inline committed slot exactly. Endpoint/content/clientKey alone is insufficient
capability proof. No silent fallback to the legacy binding endpoint.

Existing stream proof is resolved before fresh business dispatch. Fresh mixed
folder frames get exact all-operation batch_requires_split receipts with NO business
or version effects. Direct/exact polled native settlement requeues unchanged frozen
operations/sources ahead of later work and persists ACK before sending isolated
frames. Historical cursor adoption never requeues unknown original work.

New isolated delete prepares and holds atomically; preparation auto-schedules held
visibility commit. Prepared held recovery is bounded and automatic. Busy is retryable
without losing frozen intent; missing/stale/expired results are terminal and explicit.
Restore reserves and holds authoritative retained membership/name. Publish the actual
destination alias with visibility and receipt, reject preexisting conflicting alias
before reservation, and reserve restore: namespace from fresh ordinary key creation.
No pending-alias table or separate producer backend is needed.

Legacy owner folder_deletion marks remain a <=500 compatibility source even for
empty compact client lists. No injected client IDs create membership authority.
Legacy transaction/read scale and unknown deletion-commit age remain explicit gates;
do not manufacture row identity or reset a trusted retention clock. Existing old
stream history is not rewritten merely to provide new protocol semantics.

Both account Undo callers capture only ID/name/deadline/context and submit an empty
hadithIds array. Guest local Undo keeps its own identities. Projection tags each
membership removed by an earlier local delete, restores only unchanged matching
authority, and clears it on later membership/last-facet removal. It stores no second
persistent member array. A newer owned base without that local delete supplies no
guessed original members. Accepted manifest restore still waits for actual Saved.

All current native callers migrate. The v1 path remains only for installed binaries,
not an internal fallback. Batch digest/owner/JWT, journals, Saved barriers, ACK,
retention and erasure protections remain. Backend-first rollout, full Saved/export
bounds, legacy installed/mixed migration, physical/cross-device and full A2 remain
open until their actual evidence exists. A green local producer is not deployment.
