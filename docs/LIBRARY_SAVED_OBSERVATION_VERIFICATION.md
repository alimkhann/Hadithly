# A2 mandatory Saved observation authority

October 23, 2026, after `588e623`. All four private Saved version consumers now require a typed, owner-bound observation selected by the native store in the same account transaction/context. There is no no-argument/default-observation fallback. Receipt settlement, pending settlement, Saved cache writes, positions cache writes, retention and current projection callers were migrated together.

This completes the policy/transaction authority step of the selected Saved cutover. Production row mode remains off until effective presentation, refresh publication and both native UI locations are ready. Existing production behavior continues through the store-selected legacy mode; this is not the completed production read/UI cutover or A2.

## Authority and callers

`LibrarySavedObservation` is ephemeral and not Codable/Serializable. Its private representation is unavailable, a validated owned legacy revision, or a verified active private generation. Production construction occurs only in native store selection; pure tests use explicit validated fixtures. Every consumer checks the full owner scope, including subject and deployment, rather than only an owner key. No copied observation revision is persisted in `LibraryPartitionState`. Saved heads, public metadata and passage hydration cannot create this value.

- `projectedFrozenChanges(owner, observed)` retains a collecting folder-delete overlay until the selected observation reaches the committed Saved revision.
- `pruneConfirmed(owner, observed)` uses that same observation for Saved commands. Positions remain in their separate revision domain. Receipt settlement and both cache paths must supply the store-selected value.
- `settleCollectedOutcome(... observed ...)` retains originals and waits for owned private observation before the durable recovery/ACK transition.
- `canPruneOutcome(... observed ...)` requires that authority along with the existing exact proof, dependency and thirty-day retention rules. Previously claimed bounded cleanup retains its existing continuation policy.

The production projection constructor now requires authority as well. `libraryProjection(owner)` reads account state and selects observation in one store transaction/context; the UserLibraryModel caller no longer separately constructs it from a detached partition. This projection still uses the existing joined display cache and arrays. The subsequent indexed presentation work replaces that display implementation; this unit does not describe it as bounded.

A mode flag lives in the existing private Saved scope header. Default legacy mode validates and selects the owned existing snapshot. Row mode validates the current scope, owner epoch, active generation and completed checkpoint. With no active generation it returns unavailable; an old snapshot with any high revision cannot supply fallback authority. There is no production mode-flip setter yet. Tests manually set the actual persisted flag to exercise the target branch. Final production switching must join private activation and completed effective presentation in one atomic publication.

Android schema 6 adds `row_mode` to installed v3-v5 Saved headers; v1/v2 create the final header. Existing local import/guest/account/deletion tables are preserved for v5. The mode reader rejects noninteger, unknown or overflowing values instead of coercing them into legacy mode. SwiftData adds `rowMode` with default false. Neither migration decodes or rewrites every account just to obtain an observation.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Full iOS planner/presentation/Settings selection | 129 pass, zero failures | `/tmp/hadithly-saved-observation-ios-accepted.log`, `/tmp/hadithly-saved-observation-ios-accepted.xcresult` |
| Full Android connected store/facade selection | 118 pass, zero skipped/failed | `/tmp/hadithly-saved-observation-android-final.log`, connected JUnit XML |
| Android local unit selection | 212 pass, zero skipped/failed | Same Android final command, unit JUnit XML |
| Genuine prior SwiftData fixture | Verified, 1,005 retained facts | `capture-saved-schema-fixture.py --verify --output ios/HadithlyTests/Fixtures/SavedSchemaV3.store.gz` |
| Independent source recheck | No remaining concrete finding | [Accepted review](product-program/sync-design/scale/saved-cutover/observation-accepted-review.md) |

New actual-store cases on each platform force row mode and show:

- Old joined versions 999/1000 with no active private generation cannot clear a confirmed Saved edit through receipt/cache paths, including a positions cache update.
- A collected folder delete stays projected and settlement remains awaiting Saved. Active version 2 clears the matching confirmed edit but cannot settle a version-3 outcome or remove its collecting overlay. Activating verified version 3 permits the exact durable settlement and survives reopen.
- Previously acknowledged successful evidence remains retained while row observation is unavailable. After verified private activation it can be pruned through the existing bounded sweep.
- Same-key observations from another subject or deployment are rejected by all four pure consumers, leaving state unchanged. Tests retain existing proof, original/recovery, Undo, corruption, export and erasure checks.

The Android immediate-v5 fixture removes only the new mode column, retains Ready, accepted account state, a separate deletion intent/erasing clock, active Saved metadata and export fence, then opens through schema 6. All remain exact; mode defaults to zero and a restored invalid legacy JSON file is still ignored. Existing actual v1/v2/v3/v4 upgrade cases pass too.

The genuine captured `d1c80bc` SwiftData database lacks active/retiring and rowMode properties. The verifier explicitly rejects a fixture containing ZROWMODE. The migration test opens the old model through the new schema, checks false mode, preserves all 1,005 source facts, finishes verification/activation and reopens. This is bounded proof from that captured older model; it does not claim every intermediate installed binary, backup or OS combination.

## Remaining work and limits

Production mode stays legacy. Effective indexes, exact-target/folder reads, filtered keyset windows, staged bulk refresh/catch-up, final atomic private/view publication and both native Saved/Reader UI switches remain open. The old joined display arrays/cache still exist and are not a second row-mode observation source. Their safe migration/removal is part of that remaining work.

Practical throughput, large queue/positions/account blobs, server export scale/consistency, installed/backend-first rollout, real SDK/JWT, cross-device and physical-device proof, recoverable iOS save failure, deployment and A1 content dependencies remain open. Backend was unchanged; no deployment, provider/paid call, production change or push occurred. Incoming Xcode/catalog changes remain separate. Full PRODUCT_PROGRAM stays active.
