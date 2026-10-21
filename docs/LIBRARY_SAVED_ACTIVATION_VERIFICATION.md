# A2 native Saved activation and generation lifecycle

October 21, 2026, after `d1c80bc`. Both native row stores can now activate a
durably verified private Saved generation after an exact final server completion
check. This is an internal store component. Production subscriptions, UI projection
and all four private observation consumers still use the existing complete joined
snapshot. A2 remains active; no receipt or ACK authority changes in this unit.

## Behavior

Activation captures the stored prepared checkpoint before awaiting the completion
query. The reply must be empty and match owner, root, private version, input,
completion token, start and total. The transaction rereads the exact candidate lease,
checkpoint, stable owner epoch and erasure fences. It refuses an older revision.
The active pointer, prior-generation retirement and shared export mutation clock
commit in one SwiftData save or SQLite transaction. Android's AtomicFile holds no
activation pointer or second observed revision.

Invalid replies and transport failures preserve the prepared candidate. Server
Restart or Unavailable stops that candidate while preserving the previous active
library. An exact already-active retry returns the existing handle without another
network check or clock mutation. Simultaneous identical replies from two reopened
stores also produce one pointer/clock transition.

The existing owner header holds the candidate plus optional bounded active and
retiring generation records. A refresh retains the same owner epoch and creates a
new candidate generation. The previous active library stays readable throughout
collection and verification. Every active page read validates its immutable handle
against the current pointer; after a newer activation an old handle rejects.
Projection inspection remains limited to eight rows per page.

Explicit replacement preserves a failed or abandoned candidate as the single
retiring generation. Replacing or activating refuses to overwrite an occupied
retirement slot. A valid prepared candidate remains prepared until cleanup and retry.
Cleanup validates the stored retiring lease, refuses the active/current identities,
and removes at most eight rows from the first nonempty child table per transaction.
Only after raw facts, receipts and projections are empty does it clear retirement
metadata. Work resumes after reopen. At most one active, one candidate and one
retiring generation can be retained per owner.

Export metadata now marks the actual active identity. It includes separate bounded
active/retiring metadata where needed, and existing flat streams still include all
retained private child rows. Added metadata exports no opaque proof tokens. The
shared clock fences activation, refresh, replacement and cleanup. Existing scope
erasure immediately hides every generation and its bounded cleanup covers all rows.

## Migration and fixture

Android journal version 4 adds two nullable columns to the existing version 3 header.
Versions 1 and 2 create the final Saved schema through the existing additive path.
Actual disk tests preserve old outcome evidence and prepared Saved rows. The v3
fixture reconstructs the exact prior header schema while retaining real local
prepared data, then opens it through the production helper.

iOS adds optional active/retiring fields to the same SwiftData model. In addition
to the existing pre-Saved schema test, a real prior-Saved database was captured from
the already-built `d1c80bc` test binary at its 1,005-fact terminal folding boundary.
The new schema reopens it, finishes fold/verification, activates and reopens again.
The committed compressed fixture contains only synthetic test data. Provenance,
hashes and recreation instructions are in `ios/HadithlyTests/Fixtures/README.md`.
`scripts/capture-saved-schema-fixture.py --verify` checks the prior columns, state
and retained count without displaying private payloads.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| iOS selected planner/presentation/Settings suites | 114 pass, zero failures | `/tmp/hadithly-saved-activation-ios-final.log`, `/tmp/hadithly-saved-activation-ios-final.xcresult` |
| Android connected planner/facade suite | 96 pass, zero skipped/failed | `/tmp/hadithly-saved-activation-android-final.log` |
| Prior SwiftData Saved fixture | Verified, 1,005 retained facts, no local path bytes | Capture helper `--verify`, committed fixture and provenance |
| Native wire/parity and local API generators | Both `--check` pass | Existing repository scripts |
| Whitespace and staged credential scans | Pass before commit | Diff and fixture-content scans |

Seven added iOS cases and eight Android cases use real local disk stores. They
cover incomplete/changed/failed final queries; exact activation replay without
clock changes; overlapping cloned activations; lower-version refusal; three
successful generations; old active visibility; stale-handle rejection; interrupted
eight-row cleanup; stopped refresh and occupied retirement; late responses after
candidate replacement, session change and erasure; and additive prior-Saved schema
migration. Existing native suites retain the private original partition unchanged.

Android also injects an actual SQLite abort after the pointer update but before
the checkpoint update. Reopen shows no pointer, unchanged prepared data and an
unchanged export fence; removing the trigger allows retry. iOS source uses one
rollback-enabled save, but a recoverable SwiftData save failure remains unproved.

The first fixture inspection failed because a SQLite backup retained WAL mode
without its side files. It exposed a test-fixture problem, not an app migration
failure. Offline journal-mode normalization fixed it. The first Android compile
also caught a test enum spelling; both final complete runs pass. No backend code
changed and no backend suite rerun is claimed. Its prior 511-pass baseline remains
recorded in `LIBRARY_SAVED_POLICY_VERIFICATION.md`.

The selected-A sketch, read-only implementation review and accepted final recheck
are retained in `product-program/sync-design/scale/native-saved-activation-*.md`.
The final recheck includes the two additional race/revision proofs requested by
the implementation reviewer.

## Remaining gates

Next connect all four observation consumers and production private reads together:
confirmed overlay pruning, frozen folder-delete projection, terminal manifest
settlement and retention eligibility. Private active authority must then replace
old joined-cache authority consistently. Public-summary hydration, bounded UI
projection, cache retirement/migration and practical transport throughput remain
open. An internal active handle is not evidence of production cutover.

Whole-partition pending/cache and server/export scale, legacy transaction/delete-age
limits, recoverable iOS save failure, actual hosted SDK/auth/delete, installed-client
and backend-first migration, cross-device, physical-device and deployment gates
remain open. This unit adds no visible UI or copy. Existing accessibility,
localization and release gates are unchanged. No cloud deployment, paid call,
production change or push occurred.
