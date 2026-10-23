# Mandatory Saved observation implementation review

2026-10-23. Read-only review of the current native diff: observation types, four pure consumers and all production caller paths, store projection construction, row-mode header field, additive Android migration and new real-store tests. Parent is sole implementer. No source/docs edits, cloud action, delegation or gate approval.

## Result

**No concrete correctness defect found in the reviewed authority-preparation code.** All four consumer call graphs now require an explicit ephemeral owner-bound observation. Production factories are confined to the stores and observations are minted/consumed in the account operation's same SQLite transaction or fresh synchronous SwiftData context.

This is an authority prerequisite, not the full production Saved cutover. Row mode remains OFF in all production creation/migration paths and has no production setter. Existing whole joined presentation/subscription remains in use until the selected effective-view/UI migration can flip coherently. Manually enabling stored row mode in tests proves the new behavior but is not proof that the production read/UI path is ready.

Two migration evidence gaps remain before claiming all predecessor migrations verified: the immediate Android v5→v6 installed schema, and an actual prior iOS Saved model without rowMode. The source migration shape looks additive; the current new behavioral fixtures do not themselves prove those exact upgrades. Details below.

## Consumer and caller inventory

| Consumer | Current policy | Production supply |
|---|---|---|
| projectedFrozenChanges | Calls observed.version(owner), preserves collecting folder-delete only while selected private revision is absent/below committed revision. | LibraryProjection now requires owner+observation; global/reader facade account reload goes through store.libraryProjection. |
| pruneConfirmed | Saved commands use observed private revision. Position commands retain their independent positions snapshot revision. | Both Saved and positions cache wrappers mint inside the account operation; direct receipt settle and settlePending pass mandatory owner/observation through their internal call graph. |
| settleCollectedOutcome | Exact outcome/original checks remain; settlement waits on the owned selected observation reaching committed Saved revision. | Store supplies observation with current account/checkpoint in the same transaction/context. No public hydration/head event participates. |
| canPruneOutcome | Existing complete counts, ACK age and dependency checks remain, with selected observation replacing joined snapshot revision. | Retention wrapper resolves each existing dependency owner and mints its observation in the same account transaction/context. Missing owner partition continues to retain evidence. |

A production search finds direct savedSnapshot.version access only in the old cache setters' monotonic cache update checks. These are legacy payload/cache policy, not implicit private observation in the four consumers. No no-argument legacy overload remains. Production construction of LibraryProjection is now store-routed; pure tests retain explicit legacy fixture helpers.

Retention's already-claimed partial removal still resumes under its existing irreversible retention checkpoint policy; it is not a new claim based on a high old joined version. This prior behavior remains distinct from initial canPrune eligibility. The new tests cover initial absent observation preserving acknowledged evidence, then active observation permitting pruning.

## Observation ownership and source selection

The native values are non-Codable/non-Serializable. Constructors hide their source enum; unavailable, legacy and active factories are internal module helpers, not serialized account state or external wire input. Production uses only the store factories. Pure tests can fabricate validated domain fixtures explicitly.

versionFor/version(for:) rejects a different full LibrarySyncOwner, including subject and deployment namespace, rather than comparing server owner key alone. Legacy creation verifies snapshot owner and safe integer revision. Active creation validates the complete prepared generation record and carries its handle; the store first validates header ownership, lease/checkpoint, current scope epoch and active/retiring consistency through existing savedGenerations. No arbitrary head notification or copied scalar is accepted as active proof.

Mode is stored in the existing owner Saved header. Mode0/default false chooses the existing owned legacy snapshot. Mode1/true chooses only the validated active record; an existing row-mode header with no active record returns unavailable even when the old joined cache is999 or1000. A candidate/prepared/newer source does not count as active, and an old active2 cannot satisfy committed3. Generation replacement/activation update existing header fields rather than replacing the header with default mode, so the future mode survives those operations.

The absent-header branch intentionally selects legacy because production has not flipped and some installed owners have never created a private Saved header. The selected future runtime flip must retain that mode/header for the owner lifetime and must not introduce an ordinary cleanup path that removes it while leaving an admitted account. No such production removal/flip path is introduced here.

## Projection and temporary presentation

Both facade reloads now obtain a store-produced projection rather than decoding account state and constructing its own implicit authority. The entire current projection still materializes state.savedSnapshot and overlays it; hasSavedBase still describes that legacy display cache. This is acceptable only because production row mode remains OFF and the selected migration explicitly permits temporary legacy presentation until one coherent effective-view/UI flip.

The new tests use this legacy display base as an oracle for the frozen folder-delete overlay: a row-mode unavailable/active2 observation must keep hiding the collecting delete despite a joined1000 cache. At active3 terminal settlement advances. Those tests do not prove bounded row UI, independent missing public rows, exact offscreen targets or new load-state semantics; those remain the upcoming target architecture, not this unit.

## Migration inspection

Android helper version6 logic is additive:

- v1 adds old export schema, then current Saved schema including row_mode, then local-state schema.
- v2 creates current Saved schema including row_mode and local-state schema.
- v3 adds active/retiring and row_mode, then local-state schema.
- v4 adds row_mode and local-state schema.
- v5 adds only row_mode to the existing Saved table, preserving existing local-state import/guest/account/deletion authority.

Fresh Saved schema defines row_mode INTEGER NOT NULL DEFAULT0. Updates to existing rows do not reset it. Unknown integer modes fail instead of falling back. Existing v4 fixture now explicitly reconstructs the predecessor table without row_mode; older v1/v2/v3 fixtures also run, preserving relevant data.

**Evidence gap:** I do not see a real immediate v5 database fixture in this diff. Add one before labeling v5→v6 verified: reconstruct the predecessor Saved table without row_mode while retaining v5 Ready/local_guest/local_accounts/local_deletions, active/retiring metadata and clock/artifact state, then open v6 and assert default0 plus exact state retention. A v4 fixture that drops all local-state tables is not the same upgrade.

iOS adds a nonoptional Bool with defaultfalse to GuestSavedAssembly and no explicit versioned schema. **Evidence gap:** fresh stores and manual rowMode=true tests do not prove reopening the actual predecessor SwiftData schema lacking that attribute. Either provide that real migration fixture/readback or keep this exact lightweight migration gate unverified; source default alone is not runtime proof.

## Actual new behavioral proof

Each platform adds matching real-store scenarios:

1. Manually enable row mode on a persisted header. Accept a note receipt at Saved2, cache joined999 and positions999, and prove the Saved confirmation remains. Open collecting folder delete at Saved3, cache joined1000 with an old folder/member, and prove no-active returns awaitingSaved while the delete remains projected. Activate private2, prove confirmation can prune but manifest3 still waits and delete stays projected. Activate private3 and prove settlement/ACK linkage survives reopen.
2. Begin from acknowledged aged success, switch its stored header to row mode without active data, and prove retention preserves evidence. Activate a sufficient private generation and prove bounded retention eventually removes it.

These cover all four source consumers and the positions-cache indirect pruning path. Owner mismatch behavior is clear in the required domain version method; the current two new tests primarily prove source selection, not an exhaustive foreign subject/namespace/erasure/corrupt active-record matrix. Existing store guard/generation tests continue to supply their prior coverage; do not describe them as a newly run full runtime cutover matrix.

## Inspected run artifacts

- `/tmp/hadithly-saved-observation-ios-third.log`: **128 selected tests, zero failures** in its terminal test summary. The result includes the new observation tests plus existing selected suites.
- `/tmp/hadithly-saved-observation-android-second.log`: **116 connected tests, zero failures/skips**, BUILD SUCCESSFUL in its terminal summary.
- `git diff --check`: clean during this review.

These are inspected parent-run artifacts; reviewer did not independently relaunch suites. Preexisting Xcode project/catalog dirty files remain unrelated.

## Remaining scope

Do not close A2 or enable production mode from this review. The full indexed effective-view compiler/query windows, atomic mode/private/view/queue publication, exact target/folder lookups, independent public route/text hydration and all production UI callers still need their coordinated cutover. Legacy cache/whole projection removal, pending/positions/server-export throughput, real SDK/JWT, installed/backend-first deployment, cross-device/physical-device and recoverable actual iOS save failure remain open. Complete the immediate migration evidence or record those exact unverified boundaries honestly before committing this prerequisite.
