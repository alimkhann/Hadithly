# A2 bounded private Saved fact pages

October 21, 2026, after `c7b98f7`. This is the first server read component. Native
production still consumes the earlier complete joined snapshot. Its whole-account
reads and both native whole-partition caches remain open scale work. No A2
completion, native cutover, cloud deployment, migration or push is claimed.

## Contract

`librarySync:savedFactsPage` accepts a verified capability and optional opaque
continuation. Clerk resolves the owner. New manifest bindings contain an optional
private HMAC key; old stored bindings without it require explicit reopen. Legacy
v1 bindings receive the existing upgrade-required error. No key is returned in a
binding DTO, account export or page. Ordinary sync can still use an old keyless
manifest binding; only this new traversal requires the key.

Five sources run in fixed order: folders, canonical items, legacy bookmarks,
favorites, notes. Each response contains at most one source fact with its stable
source identity and global encounter ordinal. Canonical facts resolve effective
membership and clock through the existing bounded resolver. Duplicate legacy
facts retain their encounter order. No hadith document is read and references to
missing public targets survive. Actual validators define the TS response and can
feed native wire generation when native assembly is implemented.

HMAC continuations bind the owner, binding, Saved revision, source phase, source
cursor and ordinal. Assembly identity is stable for the binding/revision root.
Replies echo the exact input continuation and start ordinal. Final completion
contains total private facts and can be replayed to recheck the private revision.
A changed Saved revision explicitly restarts. An expired, swapped or erased binding
fails before source traversal. Tampering cannot select another owner or skip a
phase. Completion is server traversal evidence; it does not prove local persistence.

The future native assembler must persist a contiguous exact input/output chain and
activate one complete private row generation atomically. Partial facts cannot
replace the existing cache or satisfy Saved/ACK/retention barriers. Private facts
and eventual public summary hydration are separate domains. Hydration failure or
missing public text must preserve private data and cannot indefinitely block a
legitimate private receipt. The old joined DTO must not silently acquire this new
meaning. Neither native app has made that domain migration yet.

## Bounds and failure behavior

The primary query uses one indexed owner-prefix paginator, one requested row,
`maximumRowsRead:1` and `maximumBytesRead:32768`, without a filter or whole collect.
Source JSON above 32 KiB returns explicit unavailability before membership work or
cursor consumption. The serialized reply, including input/root/next tokens, must
fit 64 KiB. Capability and cursor sizes are checked before decoding or traversal;
continuations are capped at 12 KiB with a 4 KiB inner source-cursor limit.

A source that does not advance returns unavailability. SDK `SplitRequired` results
are rejected before any returned fact, continuation or completion can be consumed.
A partial page cannot become a signed assertion of complete private coverage.
Large-scalar chunking and exact split-range resumption remain future work. An
oversized note is retained intact, never truncated or silently skipped.

Read bytes and wire bytes are distinct. The application reads a source document
before rejecting it. Normal successful pages need three authority/version unique
lookups and one source paginator. Membership adds at most two point gets and an
owner/key unique mark lookup. Tests trace the no-membership, restored-stage and
missing-folder/tombstone paths. This fixes cardinality, not actual hosted byte
accounting. The platform's document ceiling is 1 MiB, so a legal crossing document
can exceed the 32 KiB application budget. Index/engine accounting and actual SDK
limit enforcement remain deployment evidence, not inferred from output size.

Official references checked for this design:
[PaginationOptions](https://docs.convex.dev/api/interfaces/server.PaginationOptions)
and [document limits](https://docs.convex.dev/production/state/limits).
The installed SDK's pagination definition also describes incomplete SplitRequired
pages. Installed convex-test ignores maximumRowsRead/maximumBytesRead and never
emits SplitRequired itself. Its passing suite cannot close that hosted gate.

## Verification and corrections

The focused suite has 24 cases. It traverses 501 private items plus 501 duplicate
legacy facets, retains a deleted public target, keeps an empty folder and excludes
another account's private note. Actual read traces show no public hadith get even
when that target's text is large. A bounded fixture fold reproduces current
canonical/legacy timestamp and equal-note precedence. This is transport parity
evidence, not production native fold proof.

Other cases cover exact replay, signed completion recheck, mutation after every
source phase, all three backfill invalidations, tampered/swapped/oversized cursors,
legacy/keyless/expired/deleted bindings, secret exclusion, foreign pointers, and
staged effective membership with physically normalized replay at the same version.
Tombstone clock and stage destination tests assert their real point-read/query graph.

Three oversized fixtures retain roughly 800 KiB of legal source content and return
unavailability without an advanced cursor. The folder uses 200,000 two-byte Arabic
characters in both name and normalized name; item/note use 400,000 in one content
field. Initial review correctly rejected a larger fake-only folder fixture that
exceeded the legal document ceiling; the final fixture is corrected.

Review found the initial source ignored SplitRequired. Four injected actual SDK
paginator cases cover empty/nonempty and isDone false/true. All four fail without
the guard in `/tmp/hadithly-saved-pages-split-red.log`; the corrected focused suite
passes. The injection also asserts the exact configured row/byte options. A separate
nonprogress result proves explicit failure. These injections test adapter behavior,
not observation of a hosted incomplete page.

The first focused run also found an unauthenticated instrumentation harness; it now
uses the real owner-scoped run context. A new fixture's union Promise inference
failed typecheck and was corrected with an explicit awaited branch. Neither red
run is represented as final passing evidence.

| Check | Result | Evidence |
| --- | --- | --- |
| Complete final backend suite | 511 tests, 42 files pass | `/tmp/hadithly-saved-pages-backend-verified.log` |
| Earlier complete backend suite | 511 tests, 42 files pass | `/tmp/hadithly-saved-pages-backend-final.log` |
| Expanded focused cases | 24 pass | `/tmp/hadithly-saved-pages-focused-final.log` |
| Strict typecheck | Pass | `/tmp/hadithly-saved-pages-typecheck-final.log` |
| Existing native wire and local API generators | Pass | generator `--check` commands |
| Whitespace | Pass | `git diff --check` |

The independent review and correction recheck are under
`product-program/sync-design/scale/saved-pages*.md`. Parent read both complete
candidates, judgment and reviews. A20/25 plus B's private-domain/public-hydration
separation won over a second server materialized library. The recheck's pending
log statements describe its inspection time; parent terminal evidence above governs.

## Remaining work

Both native row stores, deterministic folds, durable chain/reopen validation,
atomic generation activation and barrier migration remain unimplemented. One-row
paging is a mechanically bounded prerequisite, not acceptable large-library
throughput proof. Batching, source scalar chunking/split resumption, independent
public hydration, stale session and save-failure tests, native memory measurements
and installed-client rollout remain open. Full export, pending/partition scale,
legacy transaction/age, actual auth/cross-device/device, A1 content, A2 deployment
and all release gates also remain open. The full product program stays active.
