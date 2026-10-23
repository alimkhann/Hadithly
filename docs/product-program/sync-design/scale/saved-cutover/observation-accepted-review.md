# Saved observation final recheck

2026-10-23. Read-only follow-up to `/tmp/hadithly-saved-observation-review.md`. Reviewed current observation factories, mandatory four-consumer/caller paths, strict Android mode parsing, new actual v5 predecessor fixture, iOS captured predecessor verification/readback and pure owner-mismatch fixtures. Parent is sole implementer; no code/docs/cloud/delegation changes by this consultation.

## Source result

**No remaining concrete correctness finding in the reviewed authority-preparation unit.** The migration evidence gaps from the initial review now have focused real-disk fixtures with the limits described below. Production mode still defaults OFF and there is no runtime setter. This remains a prerequisite for the coordinated effective-view/UI cutover, not the completed production Saved migration.

The existing caller inventory still holds: all four policy consumers and receipt/positions-cache indirect paths require an owner-bound ephemeral observation. Production observation factories remain store-confined and mint inside the account operation transaction/context. No serialized observed revision or arbitrary head-event authority was added. Joined snapshot version access remains limited to legacy source selection and cache monotonicity, rather than hidden private observation in the consumers.

## Android migration and mode validation

The new v5 fixture reconstructs the real immediate predecessor Saved header without row_mode while preserving the v5 local tables and their irreversible Ready marker. It retains accepted per-owner state, active Saved generation, export fence, an independent deletion intent plus erasing clock, then reopens through helper v6. Assertions require exact retained state, active handle/fence, deletion phase and erasing flag, schema6 and default row_mode0. A restored invalid legacy JSON file is ignored for authority. This fills the specific gap that a v4 fixture dropping local tables did not cover.

Mode parsing now requires Cursor FIELD_TYPE_INTEGER and reads Long before accepting only0L/1L. A nonnumeric SQLite value cannot coerce into legacy0, and a large integer cannot truncate through getInt into0/1. This is checked source logic; no new malformed-mode runtime fixture is claimed unless the parent adds one separately. Existing v1-v4 upgrade fixtures still exercise their respective additive branches.

## iOS predecessor fixture

The existing captured d1c80bc Saved fixture predates active/retiring and rowMode. The capture verifier now explicitly rejects ZROWMODE alongside ZACTIVEDATA/ZRETIRINGDATA. I ran its read-only verification against the actual gzip fixture:

`python3 scripts/capture-saved-schema-fixture.py --verify --output ios/HadithlyTests/Fixtures/SavedSchemaV3.store.gz`

It confirmed the prior schema and1005 synthetic facts; raw DB SHA256 `89c6329480fd7c93ec757057ace3e168bd8b61410b007a6f2d7faedd4e5a400a`.

The runtime migration fixture opens that real old disk under the new ModelContainer, explicitly requires migratedHeader.rowMode=false, retains raw next1005, completes the fold/verification and activation, checks expected502 items plus1 folder and bounded active page, and reopens the same active handle. This proves that captured older Saved model migrates with the new default on the tested runtime. It does **not** prove every immediately previous installed binary/model combination, all OS versions, production data, backup restoration or release rollout.

## Foreign observation guards

Both native pure tests construct an observation for the same server owner key but another subject, then another deployment namespace. They exercise projectedFrozenChanges, pruneConfirmed, settleCollectedOutcome and canPruneOutcome with otherwise eligible state/checkpoint. Each must reject; mutation-capable methods also leave exact state unchanged. The Swift test initially used a non-existent memberwise initializer; the compile error was reported and the parent corrected it before the accepted run. The failed compile log is not runtime evidence.

These checks complement the real-store unavailable/active2/active3 versus joined999/1000 tests. They prove the observation guard binds the full owner scope, rather than only the server key.

## Scope retained

The selected temporary legacy presentation remains intentional while production row mode is OFF. Existing joined UI arrays, full cache subscription and hasSavedBase are not claimed as bounded new views. A future coherent mode/private/view/queue publication must preserve its header mode for the owner lifetime and remove old production authority paths only when all exact target/folder/filter/public hydration callers are ready.

No broad A2/release gate is approved here. Effective-view construction/query work, atomic mode/view/private activation, independent public header/text loading and missing routes, old cache retirement, pending/positions/server-export throughput, installed/backend-first deployment, real SDK/JWT, cross-device/physical device and actual recoverable iOS save-failure evidence remain open.

## Inspected terminal artifacts

- `/tmp/hadithly-saved-observation-ios-accepted.log`: **129 selected tests, zero failures**, TEST SUCCEEDED. Result bundle `/tmp/hadithly-saved-observation-ios-accepted.xcresult`. The accepted log explicitly shows passing foreign-owner four-consumer and captured prior-schema migration tests. The earlier `ios-final.log` failed to compile the added pure test; it is superseded, not counted as a pass.
- `/tmp/hadithly-saved-observation-android-final.log`: **118 connected tests**, BUILD SUCCESSFUL. The current connected XML independently reports118 tests, zero failures/errors/skips, covering the v5 upgrade and foreign-observation additions.
- `git diff --check`: clean in the final recheck.

Reviewer inspected the parent's completed native artifacts and ran only the read-only captured-schema verifier; no native suite was independently relaunched. The two specific migration evidence gaps from the initial review are addressed within the tested predecessor/runtime limits. No remaining concrete source finding is identified in this prerequisite; parent can document/commit it while keeping production mode OFF and retaining the broader gates above.
