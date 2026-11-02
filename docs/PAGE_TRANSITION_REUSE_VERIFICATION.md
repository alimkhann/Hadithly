# Page content reuse verification

November 3, 2026. Unit 2 follows the accepted Unit 1 landing repair, `8c544b7`.
The paging program remains active. Pending-target presentation and surrounding
motion/layout belong to Units 3 and 4.

## Behavior and boundaries

Both native apps share public page payloads between resume-only entry warming,
adjacent-volume warming and foreground reading. A requested target maps to the
actual returned ordinal only after its provider hadith is found. A target request
cannot alias the ordinal it originally requested. Offline base pages keep their
separate identity and fallback path. Personal translations, allowances and
translation-generation requests stay outside this store.

The session LRU holds 28 payloads. Current page, immediate neighbors and the last
loaded tail retain at most four additional payloads in renderer slots. Other
slots become empty sentinels, preserving ordinal and total-page behavior. Small
source-range metadata survives payload eviction so previously known volume ranges
do not disappear. At most four requests run concurrently; additional callers wait
for capacity. Shared requests survive one caller's cancellation. Failed work can
retry, and closing or changing account context fences late completions. Account
changes replay the original page/target or volume-edge operation when loading.
Explicit reader exits release Android renderer payloads even when the activity's
ViewModelStore still retains the closed model. Sheets/backgrounding retain the
reader session. Unopened entry warmth expires after 120 seconds.

Page key, content version, pagination version and provider/item identity remain
explicit. A newer observed response for the same actual page wins over an older
response arriving through a different target locator. Observed pagination changes
invalidate incompatible collection entries. Content versions are not assumed to
be volume-wide: the backend's provider-fallback response hashes the returned page,
while its cached-volume response hashes the volume. No backend code changed.

## Reproduction and focused checks

The iOS red warmed-edge fixture fetched volume 2 twice, with ledger
`[2:0, 2:0, 1:0]`. The repaired ledger is `[2:0, 1:0]`. The Android red fixture
could not observe adjacent warming through its injected loader because that path
bypassed it. The repaired model routes warming and foreground loading through one
store and proves one request while the warmed destination remains gated.

The final iOS `TranslationQ1Tests` run passes 12 cases. These cover entry/target
reuse, shared cancellation, eviction, context fencing, out-of-order aliases,
pagination invalidation, failed retry, offline identity exclusion, source-range
retention, no timer-triggered requests during the bounded idle sample, account
restart at the last volume page and the lookahead experiment. Two rendered Unit 1
regressions also pass with reuse enabled: partial-header/reflow and recreated-page
A-to-B-to-A return. An intermediate account test counted a separate neighboring
volume's warm call; its counter was corrected to the requested volume before the
passing final run.

Eight Android reuse cases pass after review repairs, alongside the earlier six
Unit 1 recent-position cases. The account-edge test now gates the requested last
page explicitly; its first timing-based version could finish before the account
change. A rendered long-journey case makes 34 forward and 34 backward model-directed
turns with actual native page rendering. It issues 44 requests for 36 distinct
pages as the bounded cache evicts and reloads older content. At most four renderer
slots stay populated. Native process PSS is 275,822 KB initially, 277,501 KB at
return and 310,252 KB at its sampled peak. This is within-run emulator evidence,
including test/runtime/rendering memory, not implementation before/after or
physical Android evidence. Thirty unchanged entry-policy unit checks also pass.

Independent Terra review found foreground-flight eviction and loss of the pending
last-edge operation during an account change. Both were repaired. Follow-up review
confirmed operation replay and reported no remaining must-fix issue in that change.
A mistakenly overlapping Android launch was interrupted during compilation before
its device tests; subsequent native runs were serialized.

The final tail regressions seed/retain a volume's last page while its first page
is absent. Both models return without a new request for that volume. This covers
the owner's repeated cross-volume-loading observation at the request boundary;
Unit 3 still owns visible pending-target behavior.

## Lookahead decision

The native iOS store experiment uses the same 25 ms synthetic fetch and paced
forward, reversal and edge/backward journeys for distances one and two. Forward
uses five calls and no unused pages for either distance. Reversal uses four calls
and one unused page at distance one, versus five calls and two unused pages at
distance two. The edge/backward journey uses three calls in either case; the
unwarmed backward demand takes about 27 ms in both. Warm demand totals are below
0.1 ms in these fixtures. Animation is excluded from these store timings.

These are fixture results, not network latency or native frame-rate measurements.
Payload counts are not process-memory measurements. Two-page lookahead has no
measured useful benefit here and adds reversal waste. It remains disabled. The
existing nearest-forward and adjacent-volume policy is preserved. No polling,
provider/generation expansion, cloud/deployment/schema/migration or paid-model
action was introduced. Fewer fixture requests do not establish invoice savings.

## Physical process memory

The Activity Monitor replays use the physical iPhone 16 Pro on iOS 27.0.1, English,
dark appearance and Arabic 40/translation 22. Each opens Bukhari 7184 by canonical
link, then performs five left and five right turns with the same standalone
driver. Screenshot sequences show 7184, 7188, 7193, 7196, 7202 and 7207, then the
reverse. Each trace contains 65 process samples.

The Unit 1 control ends at 161,450,040 bytes with a 213,387,368-byte peak. The
Unit 2 replay ends at 161,302,584 bytes with a 205,293,624-byte peak. Medians are
161,450,040 and 161,318,968 bytes. Entry warmth and capture start delay differ,
and the control replay ran second. These are actual process measurements, not
payload-size estimates, but they do not isolate a causal saving or prove absence
of leaks. Both finish near 161 MB in the sampled journey. The earlier exploratory
Unit 1 trace remains separate.

## Evidence and remaining scope

Raw native results, Activity Monitor traces, screenshots and build logs remain at
`/Users/alim/Developer/Artifacts/Hadithly/paging-implementation-20261102`.
[verification/page-transitions/unit2.json](verification/page-transitions/unit2.json)
records the final measurements and exact scopes. The memory-measured optimized Unit 2
binary SHA-256 is
`66c1a795614b9924d1a79b03b27e6b1dd068c8c65ff50f1ec62ab9d7462e091c`.
The accepted Unit 1 app/source archive remains separate and unchanged. The measured
Unit 2 archive predates only the later cached-tail lookup and its regressions;
final build/install provenance is in the portable record.

The original iPhone scrolling acceptance, strict below-1 target limitation,
Convex reductions, incoming project/scheme/catalog/Python bytes and every original
G01-G41, A1/A3/A4, A7/G38, E and release/physical/language gate remain unchanged.
No universal performance, physical Android, live cost, native-speaker or release
claim follows from this unit. Continue with Unit 3 separately, then Unit 4's full
native matrix. General opening latency, offline translation packs, sharing and
pills retain their separate contracts.
