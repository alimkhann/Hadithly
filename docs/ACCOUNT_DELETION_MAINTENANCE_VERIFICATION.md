# Expired deletion authorization maintenance, local verification

October 19, 2026. Follows `720a689`. Backend-only internal maintenance; native
contracts and behavior are unchanged. No deployment or live scheduled run occurred.

Unused deletion preparation authorizations previously expired for admission but
remained stored until another preparation for that subject. An indexed internal
maintenance mutation now removes at most 100 expired records per invocation and
schedules a continuation when the page is full. The hourly cron is registered in
source. It does not delete the erasure guard marker or revive a deleted account.
Preparation still prunes its own expired grants, and successful erasure still
consumes the subject's grants. Sparse sync fences retain their separate replay-
safety lifecycle; this job does not expire them.

The real local Convex fixture inserts 205 already expired records, one exactly at
the expiry boundary, one unrelated live record, and a real live retry authorization
for an already erased subject. The first invocation removes exactly 100, leaving
106 expired records. Scheduled continuations remove those and retain both live
grants. The deleted subject remains blocked from bootstrap, its live retry grant
still finishes erasure idempotently, and another maintenance call returns zero.
The separate account-erasure marker stays present throughout.

Checks: strict backend typecheck and all 396 tests in 35 files pass, with no
unhandled errors. Evidence: `/tmp/hadithly-deletion-maintenance-typecheck.log` and
`/tmp/hadithly-deletion-maintenance-backend.log`. `git diff --check` passes. The
existing native parity evidence remains 47 iOS and 26 Android passes from the
recovery checkpoint; it was not rerun for this internal-only change.

These are actual local internal mutations and scheduler continuations under a
controlled clock. They do not prove the hourly job is installed or running on a
cloud deployment. Actual deployment readback, backlog/cost monitoring and the
published retention treatment of retained subject digests remain open. The erased
subject marker intentionally survives: expiring a preparation authorization is
not proof that every old identity JWT is revoked. A2's account-scale erase/export,
large folders, schema/device/SDK, final broad review and private sync gates remain
in `PRODUCT_PROGRAM.md`.
