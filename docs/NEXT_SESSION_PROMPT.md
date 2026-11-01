# Smooth reader: verify quiet-period persistence

Follow `PLAN.md`, `SMOOTH_READER_VERIFICATION.md` and `SMOOTH_READER_DECISION.md`.
The full owner-approved goal remains active, including every retained warm run
below 1 ms/s and owner confirmation. Goal 1 evidence/decision is committed as
8655bd8. Preserve all original-program gates and deferred page-cache/priority-4.

The 18-run nominal controlled baseline is in
`smooth-reader-verification/controlled-baseline-matrix.json`; the initial mixed
thermal cohort is separate. Every condition fails. The two geometry experiments
measured 35.61 and 35.13 ms/s on large type and were removed. A new SwiftUI diagnostic supplies evidence to retest bounded tracking after
quiet-period persistence; do not conflate the earlier storage-heavy experiments. The SwiftUI renderer and original geometry are retained.

Current candidate: ReaderModel records latest viewport motion/semantic position,
then performs the existing ordered save after 500 ms of quiet. It preserves
pending account scope, exact final-position reconstruction, explicit stop/exit/
background saves. It does not run persistence on a background executor. A real reader/library regression failed before the change; the final build passes
161 safety and two UI cases, including exact latest offset and capture ordering.
The installed `idle-save-ordered-build` measures 8.04 ms/s and 11 hitches on its
first matched large-type slow run. Saves fall from 42 to 14; geometry peaks at
0.42 ms. This repair is retained, but the target still fails. The CPU diagnostic is complete. The post-commit cache candidate passes 161 tests
and reduces 20 reads from 177.53 to 20.21 ms, but its physical run remains 9.59
ms/s. SwiftUI attachment by process name now works. The 253,111-event diagnostic
points at preference propagation, including a 7.24 ms ReaderScrollStateKey update.
Retest bounded viewport tracking with quiet-period saves before changing the
renderer. Check active jobs before restarting anything. Raw
artifacts stay under `/tmp/hadithly-smooth-reader-20261101`. Attribute remaining
stalls before expanding the full matrix or changing the renderer.

The phone is wired, authorized for optimized development installation and
scrolling, generation off. Use existing signing and development services through
`build-reader-profile.py`; never install unchanged production Release. Install
and launch with profiling enabled, use PrepareLargeOrdinary then measure the
matched large-type slow case before expanding. Captures use one 30-second run,
readiness notification, native coverage for each gesture and real frame events.
Reject incomplete metrics; CPU diagnostics stay separate. Restore/match presets
through actual Settings and Contents. No reset/sign-in/model call is authorized.

Sajda was inspected and Hadithly returned foreground; mirroring is detached.
Five incoming iOS project/scheme/catalog files and six prior Python cache files
must remain byte-identical. Commit completed implementation/evidence units without
pushing. No renderer rewrite is supported by current measurements.
