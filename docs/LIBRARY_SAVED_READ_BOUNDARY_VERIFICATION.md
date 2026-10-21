# A2 compact Saved reads and native delivery boundary

October 22, 2026, after `19ace8e`. A2 remains active. This implements the common
read prerequisite for the selected production cutover design. It adds compact
invalidation, independent reference metadata and full cached text, generated native
wire values, real SDK adapters and captured native read contexts. Production Saved
subscriptions, display arrays and all four private observation consumers still use
the existing joined snapshot. This unit does not switch their authority.

## Implemented behavior

`librarySync:savedHead` returns only the authenticated owner's Saved revision. It
performs indexed user, binding and version reads, without enumerating Saved or
joining public hadiths. This is a change trigger. It cannot prove native collection
or activation and cannot authorize pruning, settlement, ACK or retention.

`librarySync:savedReference` returns exact-ID route/reference metadata without Arabic
or English passages. `librarySync:savedText` returns the complete existing cached
Arabic/English summary on demand. Both require the verified Clerk user and a current
manifest binding with its Saved cursor key. Callers never supply an owner identity.
Admission checks at most four exact owner+target source indexes, including canonical
and legacy Saved. Only a matching own source permits the one public hadith get.
Unsaved, foreign-only and vanished public targets return the same missing shape.
Replies echo the caller's owner and requested target, without private content or
an observed Saved version. No provider or generation call occurs.

Reference and fulltext responses have explicit 8 KiB and 8 MiB serialized UTF-8 wire
bounds. Oversize returns unavailable; no substring or partial passage masquerades
as complete text. The reference response bound is not a database-read bound: each
matching source lookup reads its document, and hydration reads at most one public
document. Convex currently documents a 1 MiB document limit and 16 MiB return limit;
the application text bound allows JSON escaping expansion. This does not prove SDK
or device performance at the ceiling. See [Convex limits](https://docs.convex.dev/production/state/limits).

The new binding helper centralizes the Saved manifest/key checks while preserving
the existing fact cursor boundary. Public changes and hydration failures never
mutate private source facts or the Saved revision. Rights scope matches the old
authenticated native Saved summary path; no new web/offline redistribution
permission or release approval follows.

Both native value sets derive the actual new validators and response bounds. The
generator executes the real Convex metadata/text fixture and emits its response
vectors. Native policy validates owner and target echoes, nested identity, route
fields, integer head revision, byte bounds and unavailable reasons. It separates
invalidation, reference metadata and complete text domain values. Large Arabic,
English, whitespace, quotes and controls remain byte-for-byte content.

Captured native read contexts bind the actual write/session generation, owner,
capability identity and absolute expiry. Metadata/text/fact requests validate before
suspension and again before delivery; renewal or account switch rejects old callbacks.
Head streams validate each emission, expire even when quiet and reject unexpected
upstream completion so the future refresh driver can renew/retry. Swift creates the
source and expiry timer inside Deferred on the main queue, so delayed subscriptions
revalidate scope and retain only the remaining lifetime. Android does the same at
flow collection. These contexts are ephemeral and do not enter storage/export.
SDK adapters call the actual new Convex paths; the production observer has not yet
been switched to invoke them.

## Executed evidence

| Check | Result | Evidence |
| --- | --- | --- |
| Complete local Convex suite | 524 tests, 43 files pass | `/tmp/hadithly-saved-reads-backend-first.log` |
| Strict backend typecheck | Pass | `/tmp/hadithly-saved-reads-typecheck-final.log` |
| New actual Convex read cases | 13 pass | `/tmp/hadithly-saved-reads-focused-first.log` |
| iOS selected planner/presentation/Settings suites | 120 pass, zero failures | `/tmp/hadithly-saved-reads-ios-accepted2.log`, `/tmp/hadithly-saved-reads-ios-accepted2.xcresult` |
| Android selected connected planner/facade suite | 102 pass, zero skipped/failed | `/tmp/hadithly-saved-reads-android-accepted.log` |
| Native generated wire/parity and local API checks | Pass | Both generator `--check` commands |

Backend cases cover Saved versus positions and foreign-owner revisions, invalid
counters, canonical/all three legacy admission, missing public data, zero public get
for foreign-only targets, unchanged private facts/revision, full text beyond the
private fact envelope, explicit oversize and JWT/binding/protocol/key/expiry failures.
Query/get traces establish fixed fanout. The mocked oversized fulltext adapter case
is explicitly outside hosted document limits; it is not a hosted capacity claim.

Native cases decode actual backend vectors, preserve passages larger than 64 KiB,
reject wrong identities/reasons/sizes, keep high invalidation values from changing
the private partition or active pointer, and reject suspended hydration after
binding renewal or account switch. Quiet expiry, unexpected source completion,
delayed subscription/collection and stale admission before transport are covered.
No native UI, real authenticated hosted SDK or physical-device path is claimed here.

## Reproduced lifecycle defects

The first extra EOF probes failed on both platforms. Swift's merged deadline kept
an ended source open; Android silently completed. Swift now prefixes the source
until the deadline and appends a renewal failure, while Android rejects normal EOF.
The complete follow-up suites passed 119 iOS and 101 Android checks.

Independent review then found Swift calculated its relative deadline at publisher
creation. A delayed subscriber could start stale transport and extend quiet expiry.
The focused actual-native regression reproduced all three failures. Deferred
subscription-time admission/deadline calculation fixes that boundary. Android's
flow already deferred admission; it gained the matching parity case.

The first full iOS run after that change had one fixture delivery failure: a bounded
Task.yield loop observed publisher construction rather than actual demand. The
fixture now awaits an explicit receiveRequest expectation before sending its head.
This removes a test scheduling race without changing production behavior.

Red evidence is `/tmp/hadithly-saved-head-closed-ios-red.log`,
`/tmp/hadithly-saved-head-closed-android-red.log` and
`/tmp/hadithly-saved-head-delayed-ios-red.log`. Full review and final recheck live
beside the selected design under `product-program/sync-design/scale/saved-cutover/`.

## Selected continuation and remaining gates

The two complete integration candidates and independent judgment select indexed
materialized presentation rows, with direct point edits and serial-bound tickets.
Bulk work stages a separate complete generation. The parent and judge rejected
the base/overlay anti-join because bounded continuation could still exhaust a whole
scope to establish empty. They also rejected a custom range/exclusion tree absent
measured need. See `product-program/sync-design/scale/saved-cutover/decision.md` for the complete contract.

Next specify Android account-partition migration and crash-safe guest transfer into
the same row database. Moving the account blob alone would split the existing atomic
guest claim and is insufficient. Then migrate the mandatory private observation
through all four consumers, effective indexes/windows and exact Reader status,
bounded folder controls, independent metadata/fulltext UI and old-cache retirement
together. Missing routes must not hide private items or produce false collection
empty states. No production read mode may switch before that complete path is ready.

Practical throughput, large bulk latency, pending/positions and server-export scale,
legacy delete age/transactions, recoverable SwiftData save failure, actual hosted
SDK/auth/deletion, installed/backend-first compatibility, cross-device, physical
device and A2 deployment gates remain open. No schema change, cloud deployment,
paid call, production change or push occurred in this unit. It adds no visible UI
copy; accessibility/localization gates and the full PRODUCT_PROGRAM scope remain open.
