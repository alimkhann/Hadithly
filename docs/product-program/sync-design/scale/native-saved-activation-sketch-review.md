# Selected A activation/lifecycle sketch review

2026-10-21. Read-only consultation against `/tmp/hadithly-native-saved/activation-sketch.md` and the current accepted raw/prepared stores. No repo/code edits, cloud calls or delegates.

## Decision

No structural authority or lifecycle mistake found in the selected A sketch. Proceed with the stated local store component. The final exact server completion recheck, captured prepared checkpoint CAS, same-row-database pointer/retirement/clock mutation and current-active handle validation are the necessary authority boundary; none of the current joined production Saved barriers is migrated by this component.

The active+candidate+one retiring generation bound is coherent. Retired/abandoned generation cleanup can resume independently in bounded transactions, cannot target the current or active lease, and cannot be overwritten by another retirement. Final network failure/invalid response does not consume Prepared. Restart/unavailable records the candidate stop while retaining the last active generation. Lost-return replay of an already activated exact lease should return the same handle without another pointer or clock change.

## Concrete implementation constraints from the current stores

These are required details of the selected design, not alternative architectures or new scope:

1. Current `savedHeader(lease)` requires header.lease == lease. Therefore active page inspection while a newer candidate exists must validate the scope's erasure/incarnation/ownership plus `activeData.lease` and active checkpoint directly; reusing the candidate-only helper would incorrectly hide the still-current old active generation. Raw/projection row decoders already accept an explicit generation lease and can be reused after that authority validation.
2. Likewise, cleanup requires validating the stored retiring record against the owner scope, then querying exactly its collection. It must not call candidate-only checkpoint lookup or derive cleanup bounds from the new candidate lease. Do not clear retiring metadata before the final empty raw/page/projection check in that same transaction. This protects crash-resume and stale cleanup calls.
3. Distinguish retirement-slot occupancy from server Unavailable/Restart: a full retiring slot must preserve the prepared candidate and active pointer unchanged so cleanup+retry can proceed. It must not permanently stop a valid candidate as if the server denied it. Exact already-active replay may succeed despite an occupied slot because it adds no retirement.
4. Owner-scope epoch stays stable while ordinary candidate generations rotate. Owner erase/reset creates a new epoch only after old rows/metadata are fenced and cleaned; all incoming records/handles must compare the existing scope epoch. Subject+namespace alone is insufficient for an old lease after reset.
5. Header export must explicitly emit active/retiring generation metadata as well as candidate state; current default metadata has `active:false`. When current candidate and active are the same lease, represent that identity consistently rather than suggesting two independent authoritative libraries. Continue redacting opaque root/input/completion tokens from every added metadata record.
6. Additive Android v4 upgrade must accept v3 and ALTER both optional columns without recreating outcome/Saved tables; v1/v2 direct upgrade must create the final schema including new columns. Old SwiftData disk proof must use the previously accepted Saved schema, not only the earlier pre-Saved schema.

## Proof scope

The proposed on-disk activation/refresh/cleanup/reopen, terminal mismatch/race, pointer rollback, migration and export tests address these constraints. Tests should assert old active contents remain readable during an incomplete or stopped newer candidate, old handles reject after a successful newer activation, and at least three successful generations with cleanup between retirements converge without orphaning previous rows.

No code behavior was claimed verified by this sketch review. Existing production subscriptions/read paths, private Saved revision/barrier consumers, receipt settlement/pruning, legacy full-cache/export scale, real hosted/installed SDK/cross-device/physical-device evidence and recoverable iOS save-failure gates remain open.
