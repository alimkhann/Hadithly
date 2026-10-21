# A2 public folder transition verification

October 21, 2026. Continues `47a7f29`. Current native account sync now uses the
manifest protocol, with compact folder Undo and exact migration of old mixed frozen
frames. This completes the local public-producer component. Full A2, deployment,
installed-client, full-library scale and physical cross-device gates remain open.
No cloud, private account, paid generation, production change or push occurred.

## Implemented boundary

`openBinding({})` retains its old arguments and response. New
`openManifestBinding({})` returns the same DTO and stores optional private
`manifest_v2` binding metadata. Absent metadata means inline-v1. Both current native
adapters use the new entry without fallback. Shared apply, poll, ACK, retirement and
outcome detail enforce the stored verified capability. An old capability cannot
return or consume pending, manifest or split proof, even when a restored binary
shares the same client key. It receives `SYNC_CLIENT_UPGRADE_REQUIRED` before any
change. V2 can replay an already committed old inline frame exactly.

Fresh v2 mixed folder frames commit exact `batch_requires_split` receipts for every
operation, with no business or Saved-version effects. Native direct or exact polled
settlement requires the still-frozen batch, unique operation IDs, matching revisions,
exactly one folder command and all-split outcomes. It requeues original commands and
sources ahead of later work and persists ACK intent. No isolated send occurs before
ACK. Historical cursor adoption preserves originals in recovery and never assumes
that old work was unapplied. The batch digest remains unchanged.

An isolated delete resolves an owned folder, prepares its manifest and holds its
frame in one transaction. Fifty-row preparation steps automatically schedule held
visibility commit. Recovery resumes stranded prepared work. The final transaction
publishes logical deletion, Saved revision and exact terminal proof atomically.
Busy work remains retryable without committing a second stream. Missing, stale and
expired authority return explicit outcomes.

Manifest Undo uses the retained server membership and captured folder name. Client
IDs grant no membership. Final visibility also binds `restore:<deletionId>` to the
actual destination. Begin and final commit both check aliases. A late conflicting
alias publishes exact superseded proof and starts bounded unwind before exposing a
new destination. Existing destination locks are released. Fresh ordinary folder
creation cannot claim the reserved namespace. Owned legacy deletion marks remain a
bounded <=500 compatibility source, including when a compact client list is empty.
That compatibility path still needs transaction-size and old-age rollout evidence.

Account Undo now captures deletion identity, name, deadline and context only. It
submits an empty identity array. Guest Undo retains its separate local identities.
Immediate local projection tags membership removed by the matching local delete.
Only that unchanged causal membership can return. Later explicit unassignment,
newer deletion or last-facet removal clears the authority. An authoritative base
without the earlier local delete supplies no guessed members. Existing outcome
journals, Saved barriers, ACK, retention and erasure rules remain in force.

## Design and review

The complete sketches and cross-judge are in
`product-program/sync-design/scale/public-folder*.md`. Parent selected corrected C,
combining an explicit new binding endpoint with stored capability metadata. Keeping
only a versioned apply endpoint would leave old ACK/poll paths able to consume
upgraded shared history. Changing the public binding DTO was unnecessary.

Initial review found a late alias race and missing protocol enforcement on outcome
detail. Both were fixed and tested. The intermediate recheck retained red backend
and iOS evidence. The final review found no remaining concrete defect in this slice
and checked the terminal passing logs. Earlier reports remain historical, not
current passing evidence.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Complete backend suite | 484 tests, 41 files pass | `/tmp/hadithly-public-folder-backend-final.log` |
| Backend strict typecheck | Pass | `/tmp/hadithly-public-folder-typecheck-final.log` |
| iOS real-store/coordinator, presentation and Settings suites | 89 pass, zero failures | `/tmp/hadithly-public-folder-ios-verified.log`, `/tmp/hadithly-public-folder-verified.xcresult` |
| Android real-store/coordinator instrumentation | 72 pass | `/tmp/hadithly-public-folder-android-verified.log` |
| Required current-binding 501-member public probe | Pass | `/tmp/hadithly-public-folder-support-final.log` |
| Default old-binding safety probe | Pass in complete suite, no partial deletion | `libraryFolderScale.test.ts` |
| Wire and local API generators | Pass | `python3 scripts/generate-library-sync-wire.py --check`, `node scripts/generate-convex-api-local.mjs --check` |
| Whitespace | Pass | `git diff --check` |

The fifteen new public tests run actual local Convex functions and scheduled workers.
They cover full 501-member delete/restore, bounded outcome pages, authoritative name,
identity injection, ownership, old inline replay, compact legacy Undo, all-split
migration, the v1 apply/poll/ACK/retire/detail matrix, prepared recovery, duplicate
commit, alias conflicts, busy and expiry. Another owner's Saved state and notes
survive. Restored aliases work in subsequent membership commands.

Both native suites use real SwiftData or AtomicFile/SQLite stores with controlled
transports. A 501-member offline account Undo persists below 1,024 operation bytes,
contains no IDs and reopens with all expected projected memberships. Split tests
inject ACK failure, reopen the store, preserve source/order/later work, prove ACK
blocks sends and then send the isolated folder command. Malformed and historical
proof never requeues originals. Causal projection tests cover newer unassignment,
last-facet removal/readdition, newer deletion and advanced authoritative bases.

The maximum 50-operation split reply is below 64 KiB and stores no input batch in
the committed slot. Manifest pending and terminal replies for 501 members stay below
2 KiB; outcome pages have at most 50 rows and 64 KiB. A valid old-shaped restore with
500 multibyte claimed IDs stays below the 128 KiB input limit. Its held stream stays
below input plus 4,096 bytes and terminal proof below 2 KiB. These are measured local
wire bounds, not hosted platform performance claims.

## Red runs and corrections

- The original required 501 support probe was red at
  `/tmp/hadithly-public-folder-current-red.log` before producer wiring.
- Both native compact-Undo tests were red with the old >500 captured identity array.
  Logs are `/tmp/hadithly-compact-undo-ios-red.log` and
  `/tmp/hadithly-compact-undo-android-red.log`. Their final full suites pass.
- The initial full backend run had 22 failures from intentionally changed protocol
  and worker-phase contracts. Fixtures now choose the intended binding and raw
  domain scan control while retaining their data assertions. Automatic producer
  behavior is independently exercised by the public tests.
- The expanded backend run then exceeded Vitest's default five-second timeout in
  the heavy 501 test. Its unfinished local transaction caused eleven follow-on
  failures. That test now has a scoped 30-second timeout; bounded drain limits are
  unchanged. The final full suite passes. This is not hosted latency evidence.
- The expanded iOS run failed compilation because a new projection test lacked
  `@MainActor`. The annotation is corrected; all 89 tests then ran and passed.

## Remaining gates

- No A2 deployment is approved. New schema, validators, scheduled entry points and
  generated SDK compatibility require backend-first rollout and deployed readback.
- Actual installed v1 binaries/restored backups, SDK authentication/deletion, both
  cross-device directions and physical/older-OS matrices remain open.
- Full Saved/folder snapshots, server export and native whole-file cache/partition/
  dependency scale remain open. This producer pass is not whole-app scale proof.
- Legacy <=500 transaction/read size and unknown historical deletion-commit age
  remain explicit compatibility constraints. No trusted old timestamp was invented.
- Recoverable iOS save failure, process death at every seam, retention disclosure,
  A1 content dependencies and all release gates remain open.
- The complete product program, including research, native design, website and
  Linear, remains active in the owner's requested order.
