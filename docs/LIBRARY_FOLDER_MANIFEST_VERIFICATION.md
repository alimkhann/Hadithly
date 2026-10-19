# A2 resumable folder manifest preparation

October 19, 2026. Continues `8b3cbe9`. The selected manifest design now has an
implemented preparation worker, storage, recovery and cleanup. This is the scan
half of the lifecycle. It does not delete a folder, change native routing or
produce a terminal sync receipt. No deployment, private account call or paid
provider call was made. Full A2 and large-folder support remain open.

The contract is in `product-program/sync-design/scale/manifest-core.md`.

## Implemented behavior

A preparation captures the verified server owner's folder identity, epoch and
metadata time. One folder may have one active preparation; an owner may have four.
These bound concurrent work and do not impose a member limit. Reusing an operation
ID for different folder/time fails. A still-valid retry returns the same ID and
generation. Abandoned, purging, expired and changed retries return a conflict;
they never masquerade as a live scan.

Each scheduled transaction checks owner existence, original folder owner/epoch/
time, generation and exact step. It reads up to 50 indexed members, writes only
item/hadith identities, raw membership times and ordinals, and commits facts,
cursor/count and the next scheduled step together. Duplicate or late steps do not
duplicate facts. There is no copied note or provider text. The final page marks
the manifest prepared. Fact reads also recheck the current owner/folder guard.

Accepted intervening moves or last-facet removals invalidate the scan through the
shared epoch. Same-name recreation has a different folder ID and cannot substitute
for the original. Failure removes temporary facts without changing the library.
Valid progress renews a 30-minute inactivity lease; preparation is not constrained
to 30 minutes of total runtime. A five-minute internal recovery dispatcher can
retry stalled scanning headers. Unused preparation expires through indexed
25-header admission and 50-fact cleanup steps. An explicit purging phase keeps
cleanup retryable while removing selected headers from the expiry range.

Account deletion fences the owner immediately and schedules bounded metadata
cleanup. Headers remain discoverable until facts are gone, and late workers cannot
recreate the owner/header or write new facts. New manifest metadata erasure is
asynchronous; this does not prove the existing whole-account erasure path is
bounded, or close its privacy/retention gate.

There is no registered mobile entry point for starting or reading preparation.
The later frame adapter must resolve its owner from JWT and validated binding.
The helper accepts only that internal owner. Current apps still use the existing
folder mutation, including its 500-member boundary.

## Observed failures and corrections

The first expiry test left 3 of 28 headers behind while deleting earlier cursor
rows under convex-test's ID-based pagination. It failed at
`/tmp/hadithly-folder-manifest-expiry-red.log`. Cleanup now uses a bounded indexed
take followed by a transactional purging transition and continuation. This avoids
depending on a deleted cursor row in both the local model and production design.
The local failure does not prove hosted Convex has the same cursor behavior.

Independent review found that an abandoned operation still returned a live
manifest handle. Three actual red cases reproduced changed-during-scan,
changed-after-preparation and expiry retries:
`/tmp/hadithly-folder-manifest-terminal-red.log`. Retry now returns the terminal
conflict and rechecks the current guard. The final source review found no new
blocker in that repair. Raw reports are in
`product-program/sync-design/scale/manifest-review-initial.md` and
`manifest-review-final.md`. They preceded completed test output and do not claim
hosted or full product acceptance.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| New actual Convex preparation/scheduler cases | 12 pass in full suite | `backend/convex/savedFolderManifests.test.ts` |
| Complete backend suite | 433 tests, 38 files pass | `/tmp/hadithly-folder-manifest-final-backend.log` |
| Strict typecheck | Pass | `/tmp/hadithly-folder-manifest-final-typecheck.log` |
| Local API reference generation | Pass | `node scripts/generate-convex-api-local.mjs --check` |
| Native wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| Existing large-folder product support probe | Red, intentionally still open | `/tmp/hadithly-folder-manifest-support-red.log` |

The 501- and 2,001-member fixtures execute real database and scheduled functions.
They cover duplicate steps/generations, complete paged identities, owner isolation,
concurrent moves, same-name replacement, post-prepare changes, lease renewal,
expiry, recovery after canceled delivery, erasure and terminal retry. They leave
visible Saved facets and placement unchanged except the explicit user mutation
made by an interleaving fixture. They are current-schema local fixtures, not
installed migration, process-kill or real cross-device proof.

The scanning query requests at most 50 rows and 2 MiB of source bytes, with at
most 50 small fact writes plus a header write and scheduled continuation. Fact
reads request 50 rows/64 KiB. Hosted byte-cap enforcement and any single-document
overshoot are not measured by convex-test. Index building, hosted quotas, worker
delivery and cron readback still need an approved development deployment.

The local API tool uses the installed SDK's pure API template and local module
eligibility rules. It never initializes CLI credentials or selects a deployment.
It refreshes only the already-bootstrapped local `api.js`/`api.d.ts`, which remain
gitignored under repository policy. Component projects fail with an instruction
to use official codegen. This is not schema deployment or a replacement for
`npx convex dev --once` when an approved deployment is eventually performed.

## Required next work

Connect preparation to a held immutable frame and a terminal proof before enabling
it. Prepared is never ACK-able success. Persist failure/commit authority in that
receipt lifecycle before expiring temporary headers; an expired preparation alone
cannot prove what a previously pending frame did. No committed deletion or frozen
offline Undo may depend on this temporary lease.

Phase-aware effective membership must cover the 50/100/75 stale-removal case before
logical deletion. Restore needs one-time handles, staged visibility, exact bounded
outcome pages and bounded materialization without alias chains. Migrate read/export
pagination, both native coordinators/projections, old mixed frames and installed
stores together. Preserve the final cross-device, SDK, account/privacy and release
gates. The fresh 501-member support probe still returns unresolved; preparation
passing does not close it.
