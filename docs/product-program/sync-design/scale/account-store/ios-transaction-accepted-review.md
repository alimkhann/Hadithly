# iOS account transaction and native export retry final recheck

2026-10-23. Read-only source recheck of current GuestDataStore.swift, both native preparePortableExport retry wrappers and their real-artifact fixtures. Parent is sole implementer. No code/docs/schema/cloud/delegation changes by this consultation.

## Source result

**No remaining concrete correctness finding in this reviewed local unit.** The previous export-test contract mismatch is corrected on both platforms. The fresh-context account/journal/clock boundary remains coherent for synchronous MainActor writers in this process, and the retry contract now has explicit transient and persistent invalidation coverage.

Final account boundary guards reject empty/overlong key, subject and namespace values and delimiter ambiguity before row admission. bumpOutcomeClock checks the exact deletion intent in its supplied context before a non-erasing bump, so an absent/stale clock cannot bypass the durable deletion fence. Legacy account export gets a present clock. The new legacy-account test confirms empty freeze/repeated empty claim leaves semantic state and fence unchanged. The invalid-key/deletion test preserves serverPending and rejects late enqueue and premature intent clearing.

No-op decisions use LibraryPartitionState equality, not JSON byte ordering. withAccount uses one fresh autosave-disabled context and one save for changed account plus journal/clock state; its callback has no suspension. ACK/retention helpers no longer save independently. Scoped bounded account cleanup precedes journal cleanup, and account presence preserves the clock until all scope data is gone. Identity-pending and clear continue to validate scope emptiness. Historical partitionless evidence remains a retained export source, rather than supplying current-owner admission or creating a partition.

## Retry fixtures now express the actual contract

On both platforms the one-shot mutation case inspects the completed returned JSON, requires two outcome authorities and the newly inserted `insert-during-export` authority, explicitly discards the successful artifact, then checks that no export directories remain. This proves success comes from a fresh complete attempt rather than merely permitting the old stale artifact.

Persistent mutation mode waits for three **distinct actual partial artifact directories**, invalidates each by an account queue mutation, and requires terminal failure/cleanup. Thus the max-three loop is exercised against real export artifacts, not inferred from source or incidental background sync activity. Cancellation, session switch and erasure remain rejection/cleanup cases.

Each attempt still captures a new fence and reads current local state. Retry does not disable writes or weaken any fence. StoreUnavailable is bounded to three attempts; session/owner/cancellation failures are not retried as successful work. Attempt cleanup runs before the next attempt. File cleanup failures remain a retained-artifact operational concern; no forensic-erasure or impossible transaction with external file effects is claimed.

## Evidence interpretation

The original red test demonstrated missing account-only export-clock invalidation. The reopened account writer test was a passing old-code control; **no iOS lost-update reproduction is claimed**. The clock-exhaustion ACK probe demonstrates rollback of in-context unsaved journal/account changes after a logical throw, then exact successful retry. It does not demonstrate recovery from ModelContext.save failure.

The earlier Core Data SQLite-trigger experiment fatally failed optimistic-lock recovery. Its artifact `/tmp/hadithly-ios-account-transactions-second.log` remains failure evidence. Removing that framework-fatal test from the default suite does not close the recoverable iOS save-failure gate.

## Scope retained

This recheck concerns the local transaction prerequisite and bounded native export retries. It does not switch the four Saved private-revision consumers or the production Saved UI to row authority. Pending/positions/server-export throughput, large account blob latency/memory, practical export behavior under continuous large-library mutation, installed/backend-first rollout, real SDK/JWT, cross-device, physical-device and actual recoverable iOS save-failure evidence remain open. MainActor serialization is an in-process guarantee, not a demonstrated multi-process Core Data writer protocol.

The retry reuses a supplied server export value; it establishes a coherent local attempt, not an atomic server-plus-local export snapshot. Full server consistency/scale remains its separate gate. Preexisting Xcode project/catalog modifications remain unrelated.

## Terminal artifacts

Inspected completed artifacts directly; no test job was independently relaunched by this reviewer:

- `/tmp/hadithly-ios-account-transactions-accepted.log`: **126 selected iOS tests, zero failures**, TEST SUCCEEDED. Result bundle `/tmp/hadithly-ios-account-transactions-accepted.xcresult`. The log explicitly shows passing clock-exhaustion rollback, invalid-key/deletion, legacy no-clock/no-op and real-artifact transient/persistent export retry tests. The earlier `/tmp/hadithly-ios-account-transactions-final.log` had124 passes before the final two boundary regressions;126 is the current result.
- `/tmp/hadithly-ios-account-transactions-android-final.log`: BUILD SUCCESSFUL, **114 connected tests, zero failures/errors/skips**, confirmed from the connected XML. This reruns the matching retry fixtures, including the persistent three-artifact invalidation case.
- `/tmp/hadithly-ios-account-transactions-android-unit.log`: BUILD SUCCESSFUL. Aggregated actual `android/app/build/test-results/testDebugUnitTest/TEST-*.xml`: **212 tests, zero failures/errors/skips**.
- `git diff --check`: clean on the final recheck.

No remaining concrete correctness finding is identified in the reviewed local implementation and these tested paths. Parent can document/commit this unit while retaining all limits above. This consultation approves no deployment, release, broad A2 gate, or goal completion.
