# Lossless outline storage, local verification

November 1, 2026. This unit reduces the database bytes read by
`collections.getOutline` while preserving its full public response. It is local
implementation and verification. Development deployment and conversion are
pending separate approval; production is outside scope.

## Decision

Both native apps use the complete chapter outline for contents and reader jumps.
Returning fewer fields after reading the same document would retain its database
I/O. Splitting chapters into separate rows would require new APIs and loading
behavior on both apps. Lossless compression of the existing row is the smaller
change with a measurable benefit.

The stored row contains lightweight volume metadata and gzip-compressed Convex
JSON for the full volumes. The public query reconstructs the original shape,
including chapter IDs, Unicode, optional fields and special Float64 values.
`fflate` is pinned at 0.8.3. The query validates decoded length, CRC32, SHA-256
and metadata agreement. Chunked decoding bounds expansion work. Complete legacy
documents must fit Convex's document limit so rollback remains possible. When
compression would grow the complete row, storage keeps the legacy format.

Refresh replaces the same row and updates counts in the same mutation. Conversion
preserves `_id`, `_creationTime` and `indexedAt`; cache lifetime and freshness
policy stay intact. Existing count fallback reads volume metadata without
decoding chapters. No native API, provider, generation, quota, identity or rights
policy changes.

Convex supports binary `ArrayBuffer` values and accounts for documents and index
entries read. See the official [value types](https://docs.convex.dev/database/types)
and [limits](https://docs.convex.dev/production/state/limits). Returning the same
full payload means this change does not reduce client response bandwidth.

## Real local measurement

The isolated anonymous Convex 1.45.0 backend used a private snapshot of seven
existing public cached development outlines. No user records or provider calls
were used. Crons were disabled and cloud credentials were excluded. Each format
received one uncached public query followed by one cached query. Completion logs
confirmed those cache states. The verifier compared full response objects before
conversion, after conversion and after rollback, including system fields.

| Collection | Legacy cold DB bytes | Packed cold DB bytes |
| --- | ---: | ---: |
| ibn-majah | 6,432 | 2,524 |
| bukhari | 889,575 | 232,323 |
| muslim | 10,202 | 3,757 |
| tirmidhi | 10,326 | 2,853 |
| sunan-nasai | 8,630 | 3,317 |
| abu-dawood | 7,166 | 2,795 |
| mishkat-al-masabih | 4,339 | 1,936 |
| Total | 936,670 | 249,505 |

The total reduction is 73.36%; Bukhari alone falls 73.88%. Every warm query used
zero database read bytes. Bukhari's cold query execution increased from 34.8 ms
to 82.9 ms. These single local samples establish an I/O tradeoff, not a latency
distribution, live-service saving, invoice estimate or free-plan user capacity.

All seven conversion retries were idempotent and all seven rollback responses
matched exactly. Numeric usage and response digests are in
[outline-storage-local.json](verification/convex-cost/outline-storage-local.json).
Raw chapter data stays outside git. The final write-size guard was added after
this capture; it does not change measured reads and all seven source rows fit.

## Checks and review

All 557 backend tests across 45 files and `npm --prefix backend run typecheck`
pass. Ten storage tests cover payload fidelity, row identity, refresh/counts,
conversion/retry/rollback, metadata-heavy fallback, corruption, forged expansion,
CRC and complete-document limits. An oversized refresh leaves the original row
and counts intact. The real offline artifact builder emits identical immutable
bytes before and after conversion. Existing count-size coverage now measures
the public decoded outline, since JSON stringification does not size binary data.

Independent standards and requirements reviews identified bounded expansion,
CRC validation and whole-document size issues. Failing regression cases reproduced
all three before the fixes; both reviews then reported no remaining defect.
The verifier stopped its owned local process and removed temporary state.
The five incoming iOS catalog/project/scheme files remain unstaged and unchanged.

## Repeatable commands

Run from the repository root. Choose a new private snapshot path. The capture is
read-only, projects only public outline fields, rejects already-packed rows and
creates an exclusive file with mode 0600 outside the repository.

```sh
python3 scripts/capture-convex-outline-snapshot.py --deployment festive-cobra-664 --output /tmp/hadithly-outline-new-baseline.json
node scripts/verify-convex-outline-cost.mjs --snapshot /tmp/hadithly-outline-new-baseline.json --output docs/verification/convex-cost/outline-storage-local.json
npm --prefix backend test -- --maxWorkers=2
npm --prefix backend run typecheck
```

The verifier boots its own anonymous local backend, seeds only the snapshot,
measures both formats, checks retry and rollback, then cleans up. It refuses an
unrelated legacy anonymous deployment and records no raw response or log payload.

## Next boundary and rollback

After approval for the exact new commit, deploy only to development
`festive-cobra-664`. Verify the deployed function/schema, capture public response
digests, then invoke `migrations:rewriteCollectionOutlineStorage` once for each
of these seven collection slugs with `format: "packed"`. Repeat each conversion
to check idempotence. Compare full public response digests and freshness/system
fields against the pre-conversion values. Inspect query completions and verify
both native contents/reader journeys against the changed development backend.
Use existing cached content with automatic generation off.

The internal mutation also accepts `format: "legacy"`. Restore rows using that
format before attempting an older schema deployment. Stop on a mismatch or
failed query; do not continue converting other collections until diagnosed.
No manual notification, paid generation or production action is included.

The owner's earlier approval covered only fe8742c and its completed notification
readback. This new deployment and data conversion are not yet authorized. All
G01-G41, A1/A3/A4 acceptance, A7/G38 deferral, E Linear and final audit stay open.
The larger cost goal remains active.
