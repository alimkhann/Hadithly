# Unit 4 motion verification

November 3, 2026. All four paging units are verified in their recorded native
scopes. Original program gates remain unchanged. Numeric results and artifact
identities are in verification/page-transitions/unit4.json.

Both clients now prepare immutable previous/current/next rendered contexts from
existing public content. A cached volume edge carries its actual volume, payload,
header and recent landing through the drag. Only the committed page captures,
acknowledges, generates translations or exposes interaction. This adds no fetch,
cache capacity or wider lookahead. The existing native vertical landing writer
remains the only scroll authority.

iOS retains page identity while a neighbor moves to the center. Header/range
metadata stays fixed for that visit. Android uses three keyed native pager slots
and requests recentering before measure. Native frames, rather than the API name,
must establish whether this handoff is acceptable.

## Reproduced candidate regressions and repairs

- The first iOS edge succeeded, but its retained context carried the outgoing
  generation and blocked the return. The context now retains the displayed data
  while rebasing its generation after commit. A consecutive-edge model regression
  and the actual rendered edge matrix pass.
- Recreating the active iOS page lost its recent position because initialization
  used only the frozen context landing. Active initialization again uses the latest
  recent position, with explicit model landing taking precedence. The actual
  recreation, out-and-back and reflow regressions pass.
- Android accepted an evicted cache-only preview. It now requires an extant matching
  cached payload, or an exact resident same-volume payload. Both eviction cases pass.
- Android's pointer-consuming unavailable-edge interceptor made a subsequent short
  swipe advance. The failure reproduced in an isolated native pager after the
  rejected edge, while the same short swipe from rest passed. Position, offset,
  target and scroll state were already centered; explicit recentering did not fix
  it. A nested-scroll candidate preserves the pager's pointer lifecycle and consumes
  movement into missing slots. The original failure passes after that repair.
  Reverse-direction and explicit-navigation fences pass the later ordinary-animation
  run and final regression checks.

Independent source review confirmed the cache and iOS generation/recreation fixes.
It also identified the later Android missing-drag reversal and origin risks before
acceptance. Source review does not replace their native checks.

## Current native evidence

Artifacts remain outside the checkout at
`/Users/alim/Developer/Artifacts/Hadithly/paging-implementation-20261102`.

| Run | Result and scope |
| --- | --- |
| `unit4-ios-prototype-native2` | 26 pass, 3 fail. Retained red evidence for the two edge failures and active recreation regression. |
| `unit4-ios-prototype-native3` | 30 pass, zero failures/skips. 22 model/store/offline cases and 8 actual ReaderView cases: explicit midgesture selection, recent recreation/return, partial header/reflow, both edges/boundaries, RTL/large/fixture Reduced Motion, pending success/cancel and verified local offline turns. |
| `unit4-android-nested-native` | 47 pass. Native pager, pending, cache, recent-position and rendered matrix cases. The emulator's existing animator scale was 0; this is Reduced Motion scope. It predates the final reverse/origin safeguards. |
| `unit4-android-reduced-motion` | Explicit Reduced Motion accessibility case passes; original animator scale 0 restored and read back. |

The Android 68-turn rendered retention replay in the 47-case run makes 44 fixture
requests for 36 unique pages, holds at most four populated model slots and reports
PSS 277104 → 284121 KB, peak 284197 KB. This is one emulator run with model-directed
turns, not a causal memory saving, physical Android result or leak proof.

The later ordinary-animation Android run passes 29 cases, and the retained
continuation run passes 39 reader/cache/position cases. Final targeted runs cover
private translation reads, Continue, revocation, Contents and Saved. iOS labeled
footer controls, Saved/Contents, control geometry, RTL and paging during translation
preparation pass their surrounding checks. Full VoiceOver/TalkBack acceptance
remains at its original gate.

## Physical iPhone candidate

The optimized candidate is archived in `unit4-native-candidate/Hadithly.app`, binary
SHA-256 `da510ef7f41d9f078663a463aa2f0630035c41073cbbc375001a21159cebf9bd`.
Its production source hashes and patch are retained beside it. Subsequent test-only
additions do not change that installed production source.

`unit4-after-edges.mov` records Bukhari 7 → 8 → 7 → 8 → 7, with slow next, fast
previous, fast next and slow previous gestures. The actual destination tracks
through the cached edge. Direct inspection covers all 87 original frames in
15.00–15.42, 18.25–18.68, 21.18–21.62 and 26.28–26.72 seconds. The selected windows
show the expected destination identity and no full-page loader or previous-page
replacement. Body row-projection alignment finds zero integer vertical shift in
those windows, with minimum correlation above .995. This is a local decoded-frame
displacement check, not an app frame-rate or universal no-flash claim.

The file has 1860 source frames, observed mean capture cadence 57.012 frames/s and
maximum interval 66.716 ms. Recording cadence is not native app FPS. Keep the raw
video, every-frame contacts and tracking contacts together.

The earlier Unit 3 suspicious frames were inspected directly. Their reference,
volume and body identities remain Bukhari 8 and 7184 respectively. Local glyph
deformation remains visible; H.264 capture does not establish whether it originated
in rendering or encoding. Do not label those frames a confirmed previous-page flash.

## Performance evidence

The early 40-second Activity Monitor/Hitches trace is diagnostic only. It does not
prove complete coverage of all four gestures after driver startup. Its clipped
known-app hitch total is 116.686458 ms, with two unattributed rows and one app row
outside the window. The cumulative sampled CPU delta is 2.769927833 seconds over
39.829707166 seconds. Neither number is a full-workload before/after result.

The final matched pair uses the same warmed four-turn Bukhari 7184 journey and
75-second Activity Monitor/Hitches captures. The trace-ready notification precedes
driver launch; capture is still recording after all four gestures finish. Both
traces export successfully. The control's wrapper timed out during final save;
the saved trace's duration and data were validated before use. The final capture
stops and saves normally. The isolated control uses `8ef463a` and preserved
incoming project/catalog bytes; no root source was reset.

| Native fixed-window measure | Unit 3 control | Final Unit 4 |
| --- | ---: | ---: |
| Sampled app CPU delta, seconds | 5.779183 | 4.880316 |
| Known app hitch count | 11 | 6 |
| Known app hitch interval union, ms | 200.034081 | 250.042500 |
| Maximum known app hitch, ms | 33.339 | 83.3475 |
| Unattributed hitch rows | 1 | 4 |

This is one mixed pair including quiet time and driver startup. It establishes
measurement coverage, not uniformly improved animation, native FPS, statistical
significance or billed savings. Destination readiness, finger tracking, settling,
recording cadence and whole-window resource totals remain distinct.

The final optimized build's three-iteration short vertical recheck reports zero
app hitches in every iteration and mean app CPU time 5.441295 seconds. This uses
the same short Unit 1 slow driver; it does not reopen the owner's accepted
scrolling decision or prove the older strict below-1 target. Frame-count fields
were zero, so no new FPS acceptance claim is made. Android retained its existing
debounced saving and IO-backed storage; native vertical/diagonal and position
regressions pass without porting the iOS writer.

The final signed development app is installed on the iPhone, binary SHA-256
`f2f4c2dd335f5cf4d6aaaff146d446c3459c9f69f5be4a23d5145339267a3484`.
The ordinary launch is restored at Bukhari 7 after profiling. Device pairing first
blocked installation and automation; those failed attempts are retained and are
not counted as verification. The checked install, launch and physical Continue
run succeed after owner authorization.

Preserve owner-accepted scrolling, public cache limits and Convex reductions.
No backend, cloud, account, deployment, migration, paid-model, translation-pack or
publication change occurred. The completed paired unit is committed without
pushing; all original release, language, physical and accessibility gates retain
their original scopes.

## Final repairs and matrix coverage

The final iOS Continue fixture reopens a file-backed guest store and uses a fresh
model's actual resolver and entry loading. It reproduced a dropped nonzero offset
on a row shorter than the viewport. The existing semantic writer now applies the
requested position through its existing UIScrollView using actual reading-area
geometry and legal inset bounds. Header/chapter landing and compatible snapshots
retain their existing branches. Short and tall rows now restore the exact Arabic
text position, and the real physical Today Continue replay passes its 3-point check.

The fixture's store URL and content stores now share SwiftUI state lifetime with
its model. Its private translation seed uses the actual internal ID. These setup
repairs do not change production storage or translation behavior. The live Contents
fixtures on both clients now have actual public page identity rather than falsely
using the verified offline namespace.

The Android frame capture found an outgoing-page frame during recenter, despite
passing settled-state assertions. The settle effect had requested center against
the outgoing slot mapping. Successful commit now keeps the displayed destination
until the new committed identity selects fresh slots and requests center before
measure. Rejected commits still return to the outgoing center. The identical
recorded replay removes the observed A/B/A/B flash, and RTL plus explicit-navigation
regressions pass after the repair. Sparse emulator capture is not native FPS or
proof that every possible transient frame is absent.

| Matrix group | iOS evidence | Android evidence |
| --- | --- | --- |
| Input | Actual ReaderView slow/fast next/previous, short cancel, opposite/repeated turns, diagonal arbitration and pending reversal | Native pager gesture suite, three-volume rendered matrix, same-gesture reverse/missing-slot safeguards, ordinary and Reduced Motion runs |
| Identity | Both prepared edges, absolute boundaries, actual iPhone 7→8→7→8→7, explicit midgesture selection and stale-completion tests | Both edges/boundaries, captured recenter replay, cached/missing midgesture selection, epoch/cache eviction fences |
| Readiness | Delayed success/cancel UI, failure/retry models, cache reuse and rendered checksummed offline 1→11→1 | Delayed/canceled rendered requests, failure/retry models, warm reuse and rendered checksummed offline 1→11→1 |
| Position | Current recreation, recent return, partial header, actual Saved/Contents, persisted Continue short/tall and physical Today replay | Captured recent/recreated return, explicit Contents/Saved, actual rendered Continue anchor/fraction |
| Layout | Header/footer targets, shown/hidden controls without movement, RTL/large/Reduced Motion, font reflow and actual inactive private-text growth | Native control actions, RTL/large and source reflow; delayed private growth preserves visible Arabic, then restores the new layout |
| Access/privacy/cost | Labeled native footer controls; model/account/generation fences; cache/request/memory evidence from Unit 2 | Native custom actions and labels; private revocation/default-read fixtures; bounded 68-turn retention and public request assertions |

Private translations remain outside the public cache. Android's injectable
translation-read bundle defaults to the same repository calls. Controlled fixtures
supply empty or gated defaults and a publication flow instead of contacting the
service. No generation, allowance, revocation or production transport behavior was
replaced. The growth test requires a fresh native viewport capture containing the
expanded text. It distinguishes content added below visible Arabic from restoration
on a later return; it does not force a surprise scroll to preserve a whole-row
fraction while that row grows.

The independent final source review found no additional consequential issue in the
Android mapping/recenter, iOS single landing writer or default repository delegation.
The retained Android 39-case continuation and iOS Continue diagnostics were read
and preserved. The supplied session-ses_f4ec.md copy contains older UI/widget work;
none of that work was changed by this unit.
