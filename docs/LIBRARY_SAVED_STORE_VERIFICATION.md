# A2 durable native Saved store verification

October 21, 2026, after `2b8ad8c`. A2 remains active. Both native apps now retain
private Saved source facts, exact page receipts and a resumable verified projection
in their row databases. The result is prepared only. Production reads, receipt
observation, manifest settlement and pruning still use the existing complete joined
snapshot. No active-generation or private-revision authority changes in this unit.

## Implementation and ownership

The selected raw-facts design is in
`product-program/sync-design/scale/native-saved.md`. Each owner has one candidate
header with a durable epoch and generation. Raw facts have unique ordinal and
source identities. Page receipts retain exact input, prior position, result and
fingerprint without duplicating full fact payloads. Projection rows preserve the
existing canonical and legacy facet merge semantics, empty folders and private
references whose public target is missing.

Appending raw facts, the receipt, checkpoint and shared export mutation clock is
one SwiftData save or SQLite transaction. Exact historical replay reconstructs the
stored reply and changes no clock. Changed replies, duplicate sources, token cycles,
ordinal gaps and invalid terminal totals reject. Single-flight collection checks
the captured session around suspension and durable owner/incarnation/erasure fences
at commit. Beginning collection requires the current owner partition. Later steps
use bounded row metadata instead of decoding that entire partition again.

After terminal transport, local steps fold at most eight facts, reconstruct at most
eight page receipts and their facts, then verify at most eight projection rows.
The current generated server page capacity is one fact. Folding can read eight raw
facts and eight prior projections, write eight projections and fixed metadata, below
fifty row operations. The earlier sketch's sixteen-total-operation wording was too
tight and is corrected. No larger future transport capacity is covered by this bound.
Prepared pages return at most eight rows. Preparation grants no production barrier.

The existing shared mutation clock now includes Saved data. Streamed portable
export emits bounded flat `localSavedEvidence` records for retained assembly, raw,
page and projection rows, including same-subject old-owner rows without a partition.
It labels coverage `retained_local_rows` and active false. Private note text remains
exact; continuation/root proofs appear only as fingerprints. Foreign subject and
deployment data reject. Changes invalidate the existing export fence.

Erasure marks the owner or full subject/deployment scope before removing up to eight
rows per step. It can reopen and resume, preserves sibling owners and does not drop
the shared clock while retained data remains. Account deletion drives these steps
with yielding and renewed intent checks. Existing legacy partition export and old
outcome-deletion loops have their prior limits; this does not prove total account
cleanup or whole-file storage has bounded cost.

Android adds the four Saved tables to the existing journal database at version 3.
Actual v1 and v2 files upgrade additively with old rows and clocks intact. iOS adds
four models to the existing schema; an actual old sixteen-model disk store reopens
with its partition, outcome, clock, artifact and deletion intent preserved.

## Bugs reproduced and fixed

The first 1,005-fact iOS disk test failed at its first fold. Foundation's default
natural String sorting disagreed with fixed hexadecimal cursor ranges. Explicit
lexical sorting fixes technical keys throughout Saved and the existing outcome
inventory/export/retention windows. Separate real-disk regressions reproduced the
hexadecimal ordering defect and skipped/repeated identities in a 101-header outcome
export. User-facing string/date sorting is unchanged.

Independent review found Android's projection LIMIT did not prevent scanning other
collections. A compound collection/key index and closed key bounds now constrain
the scan. The reviewer's isolated SQLite probe used 10,000 foreign rows. The old
one-target scan took 40,030 VM steps; the fixed first eight, final one and empty
windows took 122, 28 and 18. Both native tests also inspect indexed SEARCH plans on
their actual migrated disk files. Final owner-only erasure lookup uses its exact
hashed scope key on both platforms.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| iOS selected planner/presentation/Settings suites | 107 pass, zero failures | `/tmp/hadithly-saved-store-ios-accepted.log`, `/tmp/hadithly-saved-store-ios-accepted.xcresult` |
| Android connected planner/facade suite | 88 pass, zero skipped or failed | `/tmp/hadithly-saved-store-android-accepted.log` |
| iOS real-disk sorting regressions before fix | Two failures reproduced | `/tmp/hadithly-saved-store-order-red.log` |
| iOS focused ordering and large-store recheck | Four pass | `/tmp/hadithly-saved-store-ios-sort-green.log` |
| Native wire/parity and local API generators | Both `--check` pass | Existing repository scripts |
| Whitespace and staged credential scans | Pass before commit | `git diff --check`, cached diff scans |

The new tests exercise actual local databases with authenticated transport fixtures.
The 1,005-fact case yields 503 private projections and reopens during collection,
folding, page verification and projection verification. It checks eight-row windows,
duplicate legacy facets, exact note text and unchanged production snapshot/version.
Other cases cover backend-derived parity, historical replay without clock changes,
changed retry, raw-row loss, unavailable nonactivation, a fresh incarnation after
cleanup, suspended responses after erasure, partial cleanup/reopen and owner reset.

Android injects an actual SQLite trigger abort before checkpoint update and proves
raw/receipt rollback across reopen. iOS proves rollback after logical validation
failure with inserted context rows; an actual recoverable SwiftData save failure is
still unproved. Export tests retain partitionless old-owner evidence, exclude foreign
scopes, preserve private content and remove proof tokens. Android also rejects a
stale local document copy. These do not prove external document-provider or physical
device behavior. Backend code did not change and its suite was not rerun for this
unit; the prior 511-pass baseline belongs to `2b8ad8c`.

Independent source review, correction and final rechecks are retained beside the
selected design as `native-saved-store-review.md`, `native-saved-store-final-review.md`,
`native-saved-store-hardening.md` and `native-saved-store-accepted-review.md`.

## Remaining gates

Next prove final server completion recheck and atomic activation in the row database,
then migrate all four private observation/barrier consumers and production reads
together. Bounded UI projection, separate public-summary hydration, cache migration,
restart/replacement lifecycle and practical transport throughput remain work.
Whole-partition pending/cache storage and server/export scale remain open, as do
legacy transaction and old-delete age limits. Actual hosted SDK/auth/delete,
installed-client/backend-first migration, cross-device, physical-device and iOS
recoverable save-failure gates remain open. This unit adds no visible copy or UI;
localization/accessibility gates are unchanged. No cloud deployment, paid call,
production change or push occurred. A1 content and the later program stages remain
open in their recorded order.
