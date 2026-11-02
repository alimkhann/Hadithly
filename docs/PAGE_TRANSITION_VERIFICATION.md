# Native paging implementation evidence

November 2, 2026. The owner expanded this chat to all four paging units and an
Android scrolling parity audit. Unit 1 is verified in the scopes below.
Units 2-4 remain active. No original
release, device, authenticated, language or accessibility gate is closed here.

## Unit 1 evidence

The desired recent-page return failed before repair on both platforms. The real
iOS model regression returned Header instead of Semantic(57, 0.4). The guarded
Android instrumentation returned Header instead of Semantic(1, 0.4).

The initial repaired iOS simulator run passed 49 focused tests. A later run
passed 181 model/safety tests and two production-reader UI cases. These runs
precede the final review refinements and do not verify the latest source by
themselves. A fresh refined iOS run passes 19 focused cases. The final pinned fixture run
passes two model and four native UI cases, including an actual increase in
measured bilingual item height and unchanged normalized reading position.
The refined Android guarded suite passes six cases with the same normalized
position tolerance. Contents intent and Saved-return iOS regressions also pass.

The implementation retains at most 32 recent semantic positions per reader.
Compatible native viewport snapshots preserve partial headers and whitespace.
Layout, viewport, source text and translation presentation changes force semantic
restoration through the existing landing writer. Explicit entry commands take
priority. Account changes invalidate pending recent commands and close clears
the temporary registry. Reader sheets and backgrounding retain the session.

## The two observed physical jumps

After the owner approved XCTest on the phone, the observe probe passed. A fresh
pre-repair native capture then replayed vertical-up, fast-left and fast-right on
the installed optimized app without reinstalling or resetting data. The owner
observed two jumps. Original-frame inspection confirms both.

| Native video interval | Observation |
| --- | --- |
| 20.24-20.37 seconds | After the forward turn reveals B, its header/body shifts upward. |
| 23.26-23.39 seconds | Returning A first displays its scrolled reading position, then resets to the header. |

The source contains 1,650 decoded frames across 28.87 seconds, about 57.12
recorded frames per second. Its median interval is 16.667 ms and maximum is
66.6 ms. These numbers describe capture cadence, not app frame rate. Missing
intervals limit claims about movement between sampled frames. Both intervals
were checked against the fresh installed repair. In the repaired capture, the
forward transition is inspected at 17.95-19.25 seconds and the return at
20.98-22.30 seconds. B stays at the preview's header placement and A stays at its
scrolled preview position after landing. Selected settled frame pairs have a
best vertical alignment of zero source pixels. Compression still changes small
pixel values, so this is an alignment check, not pixel identity or app-FPS proof.
The owner watched the physical replay and reported, "no jerk, it was good."

The owner-reviewed signed app is retained at `owner-accepted-unit1/Hadithly.app`
inside the artifact directory. Its binary SHA-256 is
`44f4fb5d1c0e1f9c32e5e968c72f09684e3fc6e79cf35e7dee0cced855d74059`.
Signature validation and the reconstructed tracked iOS source archive hashes pass.
The committed source adds a stale-frame membership guard and smaller pinned DEBUG
fixture sizes after that physical build. Those changes are covered by local tests;
the physical replay proves the matching landing implementation, not those later
fixture inputs. Keep this build available for comparison in later units.

Raw native video, screenshots, logs, xcresults, frame manifests and source hashes
remain local under
`/Users/alim/Developer/Artifacts/Hadithly/paging-implementation-20261102`.
The baseline video is `physical-before-approved.mov`; the detailed original-frame
sheets are `physical-before-close/window-2.png` and `window-3.png`.

## iPhone scrolling recheck

The installed owner-reviewed build repeats the existing slow vertical-drag
workload with runtime checkers and injected profiling disabled. All three named
scroll-signpost samples have positive active durations. The slow hitch ratios
are 0, 0 and 12.56 ms/s, with mean 4.19 ms/s against the retained 5 ms/s bounded
budget. Mean app CPU time is 6.19 seconds against 6.35 seconds. Both checks pass.
App-wide zero fields are excluded. This is the short existing replay, not the
later strict long-form below-1 matrix; that unachieved target remains unchanged.
The faster replay records 0, 0 and 0 ms/s in the named scroll signpost, with
positive active durations. It passes the retained mean hitch budget. Mean app CPU
is 6.85 seconds. As in the prior faster-flick check, its different active duration
uses the scroll budget only; CPU is retained rather than relabeled a slow-workload
CPU pass. No app-wide zero field is used as proof.
The installed build provenance and later source differences are recorded above.

## Android scrolling audit

Android already debounces durable progress capture and performs its local store
work on Dispatchers.IO. Its storage differs from the iOS Core Data path. The iOS
decoded-partition cache is not a justified direct port. The new recent-position
capture requires a fresh scrolling non-regression check on Android.

The first instrumented scroll run passes movement, page-retention and request
checks, but overlaps a heavy optimized iOS compilation and differs from the prior
control in measured movement. Its frame timings are inconclusive.

A new quiet pair rebuilds the same workload once against pre-change reader source
and once against the repair. The current source bytes are restored and checked.
Both runs keep page zero and make one page request, with Arabic 26, translation
16 and English. The baseline records 63 frames with median 79.79 ms and p95
124.62 ms. The repair records 88 frames with median 72.96 ms and p95 96.46 ms.
Captured progress moves 3,188 versus 3,443 pixels, so this pair does not isolate
a hitch-ratio improvement. It shows no timing deterioration in this scoped
emulator workload. Neither run establishes physical Android frame rates or an
Android release-performance gate. Raw summaries, screenshots and XML are in
`android-scroll-quiet-baseline` and `android-scroll-quiet-current`.

## Remaining units and gates

Unit 2 content reuse and request deduplication, Unit 3 stable pending targets,
Unit 4 surrounding motion/layout and the full plan matrix remain pending. Keep
one-page versus two-page lookahead measured rather than enabling extra work by
default. Chosen-language offline translation packs retain the separate rights
and revocation contract gate. Sharing, interactive pills, general opening latency,
simulator cleanup and the original app program retain their recorded scopes.

No backend, schema, cloud, deployment, migration, paid-model, publication or push
action is part of the work recorded above. Incoming project, scheme, catalog and
Python cache bytes are checked against the captured SHA-256 inventory.
