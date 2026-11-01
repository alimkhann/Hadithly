# Convex usage reduction acceptance

November 1, 2026. The requested continuation reduces measured Convex usage while
preserving the native reading contract. It does not close the original app
program, release gates or free-plan capacity question.

| Requirement | Authoritative evidence | Result |
| --- | --- | --- |
| Diagnose current usage instead of attributing a monthly screenshot to one reader | `CONVEX_COST_VERIFICATION.md`, development CLI captures and seven current materialized collection counts | Historical progress totals span the earlier Q1 fix; no redundant count migration |
| Separate background work from reading | Completed scheduled-run observer plus paired native reader and equal-duration idle artifacts in `CONVEX_READER_COST_VERIFICATION.md` | Both native reading baselines and idle controls pass; ambient overlap and shared-cache limits remain explicit |
| Reduce repeated notification work while retaining delivery rules | `push-local-before-after.json`, regression coverage and two scheduled development runs | Empty/small tick uses one query instead of 96; real local scenarios retain delivery outputs |
| Reduce unnecessary native fetches | db216a6, Android controlled before/after journeys and thirty focused tests | Outline actions fall from nine to one; all eleven positions and 21 reader-page actions match; iOS policy already matched |
| Reduce large outline database reads with the same content | ed93a19, `outline-storage-local.json`, seven live converted rows and `outline-live-query-completions.json` | Controlled local cold reads fall from 936,670 to 249,505 bytes; live packed cold reads match; all full public responses, IDs and freshness timestamps match |
| Preserve refresh, count fallback, optional fields, identity and offline output | Ten storage tests, real offline artifact builder test, 557 passing backend tests and type checking | No native API, authorization, provider, quota, TTL or provenance policy changes; legacy fallback and rollback verified locally |
| Make the storage/CPU tradeoff visible | Local and live completion timings | Largest local cold query increases from 35 to 83 ms; live packed cold query takes 178 ms; cached repeats read zero bytes |
| Verify both native apps against the converted development data | `outline-android-native.json`, `outline-ios-native.json`, guarded instrumentation and terminal XCTest results | Both ten-page journeys and live contents jumps pass; Android positions match its prior baseline; initial iOS direct-tap failure and settled-tap correction remain recorded |
| Respect exact external authorization | Separate approvals for fe8742c and ed93a19; internal deployed mutation metadata and rollout evidence | Development only; no paid generation, manual notification, production, push or external message |
| Preserve repository and original-program gates | Final scoped diff, incoming-file SHA-256 checks and PLAN checkpoint | Incoming iOS files stay byte-identical and unstaged; G01-G41, A1/A3/A4, A7/G38 deferral, E Linear and final audit remain open |

The source of truth for the new rollout and native readback is
[CONVEX_OUTLINE_STORAGE_VERIFICATION.md](CONVEX_OUTLINE_STORAGE_VERIFICATION.md).
Resource artifacts distinguish calls, database bytes/documents, writes, action
memory time and network egress. Stored outline size is measured directly.
Provider request counters, billed totals and reader-population assumptions remain
unavailable. The procedures invoke no generation, and native captures expose no
generation completion in their measured windows. Those facts are not a direct
provider billing audit.

The changes retain one indexed outline lookup and the public full-outline API.
They remove eager requests and redundant notification enumeration. Compression
is confined to storage and only selected when the complete stored row shrinks.
No second backend, weaker cache freshness, additional entitlement or production
quota bypass was introduced. Broader normalized storage and scheduling rewrites
remain unnecessary without new measurements that justify them.
