# Continue from the owner-requested reader checkpoint

Read PLAN.md, SMOOTH_READER_CHECKPOINT.md, SMOOTH_READER_VERIFICATION.md and
SMOOTH_READER_DECISION.md. The complete smooth-reader goal remains active, with
below 1 ms/s in every retained warm run, full behavior checks and final owner
confirmation. Page-transition caching and priority-4 remain separate later goals.

The owner reports the current app feels much better and explicitly requests an
exact rollback point while we continue. Preserve tag reader-smooth-owner-20261102
and its signed app/dSYMs/full tracked iOS source snapshot under
/Users/alim/Developer/Artifacts/Hadithly/reader-smooth-owner-20261102-1fb14968.
Signature, binary and source digests were verified. It includes quiet-period
persistence, committed decoded reuse and bounded viewport tracking, because that
is the exact installed version the owner praised. ReaderView.swift was restored
to match its build digest before checkpointing. Do not claim strict acceptance:
the first matched large-type run is 8.94 ms/s with 14 hitches. The geometry
experiments alone did not show hitch benefit, but this complete experience must
remain available if later experiments feel worse.

Retained repairs before the checkpoint are 7774dcd and b9d8604; baseline/decision
is 8655bd8. Quiet-period saves reduced large-type results from 32.89–52.94 to
8.04 ms/s in one controlled run. Decoded reuse reduced 20 post-write reads from
177.53 to 20.21 ms; its physical run remained 9.59 ms/s. All 161 safety tests,
two reader UI checks and 13 capture checks pass at the recorded scopes. Eight
unchanged-Android parity checks remain valid preparation, not final acceptance.

Next: correlate late-frame lifetimes with simultaneous CPU/thread-state data.
The standard Animation Hitches template plus app-only Time Profiler and Points
of Interest successfully recorded the complete driver under
/tmp/hadithly-smooth-reader-20261101/animation-hitches-diagnostic. Seven parallel
exports expanded about 17 GiB scratch and failed from disk exhaustion. All are
terminal; only their PID-named scratch directories were removed, recovering
20 GiB free. The recorded trace is preserved. Retry one export at a time, ideally
multiple selected schemas in one call, and inspect the existing output/logs first.
Select the non-dynamic PointsOfInterest os-signpost table, not all signpost tables.
Do not interpret CPU-sampled captures as acceptance data.

The successful SwiftUI diagnostic and GPU/frame-phase records are portable under
docs/smooth-reader-verification. GPU phases of remaining hitches were about
1.21–1.55 ms; two associated app updates exceeded 15 ms. Bounded tracking plus
quiet saves still measured 8.94 ms/s, so no renderer rewrite has been justified.
The phone is wired, authorized for optimized development installation/profiling,
generation off. Never install unchanged production Release or reset/sign in.
Coordinate only if the phone becomes occupied or locked. Preserve the five
incoming iOS files and six prior Python cache files, all original gates, A2 row
mode off and completed Convex/A5/B/C/D work. Commit completed units without push.
