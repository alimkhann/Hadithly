# A2 shared native account transactions

October 23, 2026, after `56e1f96`. The iOS account store now uses a fresh synchronous MainActor context per account operation. Its account payload, associated outcome ACK/retention mutations and shared export clock commit in one save. Both native exporters retry a changed/unavailable local snapshot at most three times, with each failed attempt discarded. This is the matching transaction prerequisite for the selected Saved cutover; production Saved observations and UI still use the old joined snapshot.

## Reproduction and repair

The new iOS public-API export test first failed because a cloned account edit did not invalidate the captured local export fence. Its guest-only control left the fence unchanged as intended. The reopened-account-writer test passed on the old implementation; no iOS lost-update reproduction is claimed.

`withAccount` now selects the exact current owner and deletion intent in one fresh context, decodes current state, runs synchronous policy, updates only changed state by domain equality, advances the shared clock and saves once. It rolls back escaping errors. No network await occurs inside the operation. ACK metadata no longer saves before the account cursor. Retention member/header/inventory mutations and the sweep cursor share one save. Terminal settlement and both cache setters use this same context.

Claim reads guest rows, appends exact original sources, removes those same rows and saves the account plus clock together. Ordinary mutations require an existing owner and cannot recreate an erased account. Fresh exact deletion lookup replaces all-intent filtering through the old identity map. Scope cleanup selects at most fifty account rows per batch; phase completion and intent clearing require no retained account/Saved/outcome/artifact metadata. Account presence prevents early export-clock deletion. Namespace/key boundary validation rejects ambiguous separator keys before mutation.

Existing legacy account rows can have no clock. Export now establishes a present clock instead of calling that state empty. Guest-only edits do not advance it. An empty claim or empty freeze preserves a valid existing fence. No schema migration was added.

Correct account fencing exposed an existing export assumption: sync can update account state while a multi-page file yields. Both native exporters now retry StoreUnavailable with a fresh local fence and account snapshot, at most three complete attempts. Each attempt closes/discards its partial artifact before retry. Cancellation, account changes and deletion remain terminal. Deterministic corruption can be retried twice but still fails; a retained partial never becomes a successful export. This is local snapshot consistency and does not turn the provided server export into a cross-service transaction.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| iOS public fence regression before repair | One failure; reopened-writer control passes | `/tmp/hadithly-ios-account-transactions-red.log`, matching `.xcresult` |
| Full iOS with transaction/retry implementation | 124 pass | `/tmp/hadithly-ios-account-transactions-final.log`, matching `.xcresult` |
| Final iOS including boundary and legacy-clock cases | 126 pass, zero failures | `/tmp/hadithly-ios-account-transactions-accepted.log`, matching `.xcresult` |
| Android full connected store/facade parity and retry | 114 pass, zero skipped/failed | `/tmp/hadithly-ios-account-transactions-android-final.log`, connected JUnit XML |
| Android local unit suite | 212 pass, 34 files | `/tmp/hadithly-ios-account-transactions-android-unit.log`, unit JUnit XML |

The retry fixture on each platform waits for an actual partial artifact. A one-time mutation must return fresh JSON containing both original and newly inserted exact outcome evidence, then discard the successful artifact. The persistent case waits for three distinct artifact directories and invalidates each attempt through a new account command; final failure leaves the export directory empty. Cancellation, switch and deletion continue rejecting and cleaning up. Existing malformed/half-pruned evidence and old-owner orphan export cases remain in the complete suites.

New iOS checks retain all accepted command IDs across reopened writers, verify a primed guest context cannot resurrect claimed drafts, preserve a later guest original, validate no-op/legacy clocks, reject late writes after deletion and reject premature intent clearing. The ACK rollback probe exhausts the shared clock after staging the journal ACK bump, so the account bump throws. The fresh reopened account, retention marker and captured fence remain unchanged; a repaired fixture clock then permits one successful retry and timestamp.

## Failed save experiment and limits

An actual SQLite trigger abort on Core Data's account payload UPDATE caused `Unable to recover from optimistic locking failure` and test-host failure in `/tmp/hadithly-ios-account-transactions-second.log`. The crashing probe was removed from the default suite. It did not prove recoverable ModelContext.save behavior. The passing clock-exhaustion probe proves rollback of staged same-context changes before save, not recovery from a failed save. Actual recoverable iOS save-failure verification remains open.

The [consultation](product-program/sync-design/scale/account-store/ios-transaction-consultation.md) and [initial implementation review](product-program/sync-design/scale/account-store/ios-transaction-implementation-review.md) record the constraints and corrected retry-test contract. The [final source recheck](product-program/sync-design/scale/account-store/ios-transaction-accepted-review.md) found no remaining concrete finding and inspected the completed native artifacts.

MainActor serialization covers synchronous writers in this process. Arbitrary concurrent processes, backup/rollback, installed/backend-first compatibility, real SDK/JWT, cross-device and physical-device paths remain separate gates. Per-owner pending/positions blobs and server export throughput/consistency remain open. The mandatory private Saved observation, effective presentation and production UI cutover are next; this unit does not claim their completion. A2 and A1 dependencies remain open. No deployment, paid call, production change or push occurred; incoming Xcode/catalog changes remain separate.
