# A2 folder scan guards

October 19, 2026. Local prerequisite for the selected bounded manifest design.
No folder worker, pending receipt, logical deletion or native job integration is
enabled. The 501-member support gate and full A2 remain open.

## Implementation

Folders have an optional membership epoch, with absent values interpreted as zero.
Accepted ordinary placements invalidate the source and destination, including a
newer same-folder clock. Unknown-time guest seeds invalidate only their target.
Rejected/tied observations and independent note edits leave the epoch unchanged.
Removing an item's last facet invalidates its current folder before deleting the
row. Both legacy and queued restore paths invalidate their destination.

The shared domain module owns these updates. Old per-caller empty-row deletion
helpers are removed. Physical folder deletion removes the folder itself, so any
later scan must reject its missing original row. Account erasure also removes the
owner and folders; future worker owner-existence checks remain part of the job
contract. Legacy facet-only writes and the current H3 backfill do not change a raw
folder placement; the backfill only adds facets or creates unplaced rows.

An owner/folder/membership-time index returns the current maximum with one `first`
query. It does not cache a high-water mark, so moving/removing the maximum member
immediately exposes the next current member. An undefined installed membership
clock remains zero. Owner is part of the index prefix, so a foreign row with a bad
pointer cannot enter this guard. Current small-folder deletion uses the indexed
maximum for its existing stale-delete check. It still performs the existing
501-row size check and does not support large deletion yet.

The independent review found that the old size check counted foreign malformed
pointers before filtering. A 500-owned-plus-one-foreign fixture reproduced that
false failure. A legacy fixture also showed its deletion receipt included a
foreign member. Both delete queries now use the owner/folder index prefix before
reading or writing members. The foreign row's placement, clock and note stay
unchanged. Red evidence: `/tmp/hadithly-folder-scan-owner-red.log`.

These guards are necessary for the next job's compare-and-commit check. They do
not themselves freeze a set, retain a manifest, provide phase-aware logical
membership or make paged preparation atomic. No scan may commit based only on an
old in-memory folder record; it must load and compare the current owner/folder,
epoch, metadata time and job generation in its final mutation.

## Executed verification

| Boundary | Result | Evidence |
| --- | --- | --- |
| Actual Convex scan/placement/facet/guest/restore/foreign-pointer paths | 8 pass in full suite | `convex/savedFolderScan.test.ts` |
| Complete backend suite | 421 tests, 37 files pass | `/tmp/hadithly-folder-scan-final-backend.log` |
| Strict typecheck | Pass | `/tmp/hadithly-folder-scan-final-typecheck.log` |
| Native wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |

The 2,001-member fixture checks maximum removal/movement, owner isolation and
optional installed epoch zero. Other cases exercise actual sync, guest and legacy
mutations, separate note clocks, same-folder observations, last-facet removal and
both restore paths. Native payloads and interfaces are unchanged in this unit;
the preceding native 51 iOS/30 Android checks are recorded separately in
`LIBRARY_SYNC_MEMBERSHIP_VERIFICATION.md`. They were not rerun for this server-only
metadata change.

The database helper's one indexed result and fixed number of folder reads bound
that helper's document count, not the full current delete mutation. Local fixtures
do not measure hosted index-build readiness, Convex quotas, response/read byte
budgets, whole-file native storage or real account/device delivery. Malformed
installed timestamps and prior schemas remain migration checks. The new optional
field and index need an explicitly approved development deployment before live
readback. No deployment or migration was run.

The independent report and query-correction addendum are preserved in
`product-program/sync-design/scale/scan-review.md`. They found no blocker in this
bounded prerequisite or final ownership correction. They preceded final completed
test output and do not claim hosted or full A2 acceptance.
