# A2 bounded quarantine and frozen-frame recovery

October 19, 2026. Continues `e1e75d5`. Implemented on both native apps and locally
verified against real stores and actual Convex functions. No deployment, private
account call or real cross-device test was performed. A2 remains open.

## Reproduced problem

Both native freeze loops limited selected valid operations but could inspect and
quarantine an entire invalid pending queue in one call. A 101-invalid-entry fixture
failed on both apps: one freeze quarantined 101 instead of at most 50 and reached
the later valid operation immediately. Red evidence is
`/tmp/hadithly-sync-quarantine-red-ios.log`, `.xcresult` and
`/tmp/hadithly-sync-quarantine-red-android.log`.

Already frozen frames also bypassed current domain admission. A known older frame
with a note exceeding today's UTF-8 limit could retry unchanged indefinitely and
hold up valid later intent. Erasing or rewrapping it would be unsafe if an older
copy had already committed or a late request could still arrive.

## Implemented behavior

A freeze now inspects at most 50 entries. Invalid originals remain in recovery.
If a pass produces no frame while pending work remains, the coordinator continues
and reschedules after its existing eight-pass budget. A 401-invalid-entry fixture
proves the later valid bookmark still sends once and all 401 original operations
remain recoverable. This bounds admission work per pass, not the whole-file load,
array copying or serialization costs of the current native stores.

Before sending, the coordinator rechecks the frozen batch's identifiers, operation
count, duplicate IDs, UTF-8 size, command fields, clocks and folder fanout. A known
but currently invalid frame uses a captured-owner retirement RPC with only its
installation and sequence. It sends no private operation payload. The server fences
that one sequence and preserves any already committed exact receipt until ACK.

A future sequence gets one indexed sparse fence. It cannot skip a healthy restored
copy's valid earlier work. Exact ACK consumes contiguous following fences and
compacts them. At most 100 future fences can be outstanding per installation;
duplicate retirement is safe and ordinary expected-next retirement allocates none.
This is an outstanding-work bound, not a lifetime cap. Capacity failure keeps the
original frozen frame for retry. Sparse fences are exported and erased with the
account; they cannot safely expire merely by wall clock.

Native settlement verifies owner, installation, requested sequence and the same
still-frozen batch. The available old original is retained as historical recovery,
including uncertainty about older acceptance; it is never falsely called exactly
preserved. An occupied receipt proof is persisted for ACK before fresh work. A lost
retirement response leaves the original frozen frame intact. A stale response
cannot clear a newer frame or recreate an erased partition.

## Executed checks

| Boundary | Result | Evidence |
| --- | --- | --- |
| Complete backend suite | 395 tests, 34 files pass | `/tmp/hadithly-sync-sparse-final-backend.log` |
| Backend strict typecheck | Pass | `/tmp/hadithly-sync-sparse-final-typecheck.log` |
| iOS stores/core/facade and Settings policy | 47 pass | `/tmp/hadithly-sync-recovery-verified-ios.log`, `.xcresult` |
| Android stores/core/facade and wire adapter | 26 pass | `/tmp/hadithly-sync-recovery-verified-android.log` |
| Generated wire consistency | Pass | `python3 scripts/generate-library-sync-wire.py --check` |
| Whitespace | Pass | `git diff --check` |

Actual Convex tests cover owner mismatch, duplicate retirement, late application,
active receipt preservation, incorrect ACK, healthy frames1–6 while7 is fenced,
contiguous compaction, invalid stream bounds, capacity, expected-next retirement
at capacity, export and account erasure. Native tests seed a known old invalid
payload into the real SwiftData/JSON store, lose a retirement response, retry and
reopen the store. Only the later valid operation sends, at sequence2; the original
oversized Unicode note remains in historical recovery. Other tests protect the
occupied proof, a newer frozen frame and coordinator continuation after quarantine.

The SwiftData fixture uses current model schema with an older-style payload. It
is not a previous installed-schema migration or process-kill test. Native RPCs are
controlled; SDK/auth/network delivery remains unverified. The first new backend
assertion expected explicitly present undefined fields; it was corrected to assert
absence after Convex omitted those fields. It was a fixture repair, not a product
regression. The quarantine diagnostic is the observed red product case.

## Independent review and remaining work

The initial source review found a P1: a retirement high-water mark could skip a
healthy restored copy's valid intervening frames. That design was replaced with
sparse fences, and the actual test now executes the healthy frames before crossing
only the retired sequence. The final independent source review found no remaining
blocker in this bounded revision. Reports are in
`product-program/sync-design/recovery-review-initial.md` and
`product-program/sync-design/recovery-review-final.md`. The final review preceded
completed test output and does not claim those results or A2 completion.

Unknown wire variants, corrupt stream headers, prior installed models, whole-file
storage scale, suspended commits and real interruption/account delivery retain
separate gates. Same-sequence cloned copies still have the existing protocol's
unknown-history reconciliation; available originals are retained, not invented or
automatically replayed. Large folders still have the 500-member boundary. Their
bounded-job/read migration is separate architecture work. Marker retention, account
scale, SDK deletion propagation, final broad integration review and A2 deployment
approval also remain open in the program.
