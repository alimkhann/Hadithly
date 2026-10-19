# A2 held folder frames

October 19, 2026. Continues `1bb9341`. The pending protocol, failure publisher and
both native consumers are implemented and locally verified. The public folder
producer and successful logical delete/Undo are not enabled. The 501-member support
gate and full A2 remain open. No deployment, private account call or paid provider
call was performed.

The caller/storage contract is in
`product-program/sync-design/scale/held-frame.md`.

## Server behavior

A stream has one optional outstanding slot, either pending work or a committed
receipt. Pending retains the bounded original batch server-side and returns only
proof metadata in a cursor. Internal holding verifies owner existence, manifest
owner/generation, operation ID/time, folder identity/epoch/time and expiry. It
accepts one isolated delete frame and binds the manifest once. It is not a public
entry point. Future restore holding and producer admission remain part of cutover.

Actual apply retries return the held proof. A different frame cannot steal it.
The new poll query derives owner from JWT and binding before reading a stream.
ACK cannot close pending work, and invalid-frame retirement cannot fence that
sequence. Sparse future retirement still waits for the held frame's final receipt
and exact ACK. Server export retains the owned pending original in its slot.

Manifest abandonment and expiry publish an exact no-effect conflict receipt before
temporary facts/header can be purged. After cleanup, retries still find the final
receipt in the stream. Owner erasure prevents callback resurrection. Successful
logical effect publication is not implemented here and must commit its proof in
the same mutation as that effect. Prepared status never means delete success.

## Native behavior and the reproduced review finding

Both stores persist waiting metadata in the existing owner partition. A matching
frozen original remains frozen with no sequence advance, confirmation or ACK.
Coordinators poll before new freeze/admission, preserve session fences and delay
between pending responses. Later local intent waits. New delete/restore freezes
are isolated; existing frozen representations are left intact. Full old mixed-frame
cutover and installed-schema compatibility remain gates.

Independent review found a P1: matching batch/operation IDs could retain a restored
copy whose command differed from the server's pending command, then falsely
confirm it from the other copy's final receipt. This failed on both real native
test hosts before the fix:
`/tmp/hadithly-held-frame-clone-red-ios.log`, `.xcresult`, and
`/tmp/hadithly-held-frame-clone-red-android.log`.

Pending now carries a separate content fingerprint, while the existing receipt
digest remains unchanged. Backend, Swift and Kotlin encode tagged values with
UTF-8 byte lengths, ordered schema keys and IEEE-754 number bits, then SHA-256 the
versioned representation. This avoids JSON escaping and number-format differences.
The backend emits shared Unicode, fractional/exponent-number and folder vectors;
both native suites compare their actual implementation against them.

Adoption and terminal settlement both check the exact local content fingerprint.
A different same-ID clone becomes historical recovery and waits for the server's
proof. It may ACK that proof without claiming its available original was preserved.
The failed clone test now passes on both apps. Owner and malformed-proof checks
fail before clearing durable originals. Missing owner partitions are not recreated
by late settlement.

Raw independent reports are in
`product-program/sync-design/scale/held-frame-review-initial.md` and
`held-frame-review-final.md`. The final recheck found the P1 repaired and no new
blocker in this bounded change. It preceded completed final tests and does not
claim full-folder or hosted acceptance.

## Executed verification

| Boundary | Result | Evidence |
| --- | --- | --- |
| Complete backend suite | 439 tests, 39 files pass | `/tmp/hadithly-held-frame-final-backend.log` |
| Strict backend typecheck | Pass | `/tmp/hadithly-held-frame-final-typecheck.log` |
| iOS core/real stores/coordinators and existing native policies | 55 pass | `/tmp/hadithly-held-frame-final-ios.log`, `.xcresult` |
| Android core/real stores/coordinators and wire adapter | 34 pass | `/tmp/hadithly-held-frame-verified-android.log` |
| API reference and native wire consistency | Pass | Local API and wire generator `--check` commands |
| Current 501-member product support probe | Red | `/tmp/hadithly-held-frame-support-red.log` |

Actual Convex functions cover pending apply/poll, protected ACK/retirement, future
fence consumption, expiry proof surviving work cleanup, concurrent membership
change, wrong JWT/capability, another stream, changed request, stale generation,
owned export and erasure. Native tests cover exact content vectors, same-ID forks,
store reopen, retirement while held, wrong owner, terminal recovery and delayed
coordinator polling before later intent. RPCs are controlled native fixtures, not
real SDK/network or cross-device delivery.

The first backend export assertion named a nonexistent function; that fixture
was corrected to call `exportCurrentUserData`. The first new Android coordinator
fixture omitted its required coroutine scope; its final run includes the fix.
These were fixture errors, separate from the reproduced P1 product-protocol flaw.
iOS also logged existing temporary SQLite-store teardown warnings in the quarantine
fixtures; assertion passes do not certify process-kill or teardown behavior.

## Remaining cutover gates

The active-only stream schema/wire has been replaced locally by the outstanding
union. Before any approved deployment, read back existing development stream rows
and migrate the old shape if present; do not infer its absence. Both current native
consumers are updated, but old installed clients and server schemas need their
explicit migration/release proof.

Logical membership must still preserve the 50/100/75 stale-removal case. Successful
delete and staged Undo need one-time handles, exact bounded outcome pages, bounded
materialization and retained authority beyond preparation expiry. Read/export pages
and native folder projection/recovery must migrate with the public producer. No
successful large-folder operation is claimed by these pending/failure tests. All
existing real account/device, SDK deletion, privacy/retention, production and release
gates remain open in `PRODUCT_PROGRAM.md`.
