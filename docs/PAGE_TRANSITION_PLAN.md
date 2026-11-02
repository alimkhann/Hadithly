# Page and volume transition plan

November 2, 2026. Planning is complete for the decisions below. Product repairs
have not started. The owner's request to plan controls this session. The first
implementation unit is Unit 1; do not batch the whole plan into one change.

## Agreed experience

Follow Sajda closely for page motion, top and bottom layout, control behavior
during turns, cancellation and settling. Retain Hadithly typography, source and
authenticity actions, accessibility, privacy and native platform meaning.

- A recently visited page returns to its earlier reading position during the
  current reading session. An unseen page starts at its header. Explicit
  Continue, Saved and Contents targets take priority over a recent-page position.
- The page shown during a drag and the page after commit have the same identity,
  content and vertical position. A canceled turn leaves the current page intact.
- Keep the existing configurable direction and translation-language Automatic
  setting. Compare logical previous/next outcomes across LTR and RTL.
- When a destination is unavailable, keep the current text visible with a quiet
  loading cue. Complete the pending turn only when its destination is ready.
  Cancellation, another navigation and errors must not cause a delayed surprise
  turn. Keep this presentation decision in one place so it can later change to a
  destination loading page without rewriting fetching, identity or landing.
- Reuse available content efficiently. Wider preloading is an experiment, not
  the initial solution. Do not increase Convex work merely to hide a loader.

Recent-page positions are temporary for the open reader. The implementation must
bound them and clear them when the reader is closed or its account context ends.
Reader sheets and temporary backgrounding do not end a retained reader session.
After a process restart, Continue Reading remains the durable last reading
position. Preference changes use semantic anchors rather than replaying
incompatible raw offsets.

The [baseline](PAGE_TRANSITION_BASELINE.md) distinguishes reproduced behavior
from hypotheses. It directly shows a vertical reset after a returning iOS page
has landed, an unloaded previous page, and a warm revisit with rendered content.

## Ordered implementation units

Each unit pairs iOS and Android work, targets a 30–45 minute useful slice, and
ends with its own verification and commit. Split a unit at a green boundary if
its actual scope grows. Preserve the whole destination and remaining matrix.

### Unit 1. Make recent-page return and landing consistent

Use the existing semantic reading-position shape and one native landing writer.
Represent the recent-page position explicitly, keyed by the actual page and
content identity. Replace the unconditional manual-header decision only for a
valid recent-page return. Match the neighbor preview to that same decision before
it is revealed. Never add a second scroll-offset effect to fix the handoff.

Primary files are iOS `ReaderModel.swift`, `ReaderView.swift` and their focused
landing tests, plus Android `ReaderViewModel.kt`, `ReaderScreen.kt` and matching
tests. Keep platform writers in separate directories; serialize native device runs.

Prove the existing returning-page reset red, then green. Repeat scroll A → B → A
on the installed native app after the repair. Also check unseen-page headers,
explicit Continue/Saved restoration, cancellation and semantic re-anchoring after
large bilingual text changes. Recheck the accepted scrolling workload without
reopening marginal below-1-ms/s tuning. Stop before changing fetch policy.

### Unit 2. Retain useful neighbor content and deduplicate requests

Measure the same turn workload first, including a resumed entry, warm out-and-back
and a volume edge. Record destination-ready time separately from animation, reader
request counts/duplicates, cache hits, unused prefetches and retained memory.

Use a bounded session content cache and shared in-flight requests. Retain useful
payloads from existing warming before issuing additional speculative requests.
Keep page identity, content/pagination version and source identity explicit.
Invalidate on relevant source/version changes. Keep account data, generation and
allowances outside the shared content cache. Preserve cancellation and generation
fences when requests finish out of order.

Start with the nearest useful neighbor in each direction. Compare one-page and
two-page lookahead on the same forward, reversal and edge journeys only after
reuse works. Adopt two-page lookahead only when measured waiting improves and
extra unused work, memory and Convex cost are justified. No new provider calls,
generation, backend deployment or schema change is part of this unit.

Warm revisits must reuse content without another page request. Idle must not
start reader polling. Preserve the recent notification, outline and reader I/O
reductions. A lower request count is not proof of a lower bill; use real bounded
readbacks for any live cost claim and obtain its action-time approval.

### Unit 3. Keep the current page stable until the target is ready

Represent the pending turn separately from the committed page. Loading, errors
and retries preserve the outgoing readable content. Commit destination identity,
payload and vertical landing together. Gate completion by the current intent so
a canceled or superseded request cannot navigate later.

The loading presentation has one native decision point. The default keeps the
current page with a quiet accessible cue. The fetching/landing model must also
support a later destination-loader renderer without an architectural rewrite;
this does not add a user-facing setting now.

Check delayed, failed, canceled, superseded and successful targets on both native
apps, including both volume edges. Reproduce the first backward loader workload
and compare its repaired video. Keep first-readable-content timing distinct from
turn duration. Stop before general collection-opening optimization.

### Unit 4. Match the surrounding layout and motion, then close the matrix

Compare the recorded Sajda states with the same Hadithly journey. Adjust only
differences that affect this turn experience: top clearance, bottom clearance,
compact/expanded indicators, control fading and tracking/settling. Keep page
content and its vertical position stable when controls appear or disappear.
Preserve source-provided chapter/volume meaning and accessible controls.

Use native SwiftUI/UIKit and Compose mechanisms. A browser mockup cannot prove
native motion. If an interaction has competing implementations, make a bounded
native probe before choosing; do not assume Sajda's internal renderer.

Close the matrix below with timestamped before/after evidence and a focused
independent review of stale-request and landing ownership risks. Preserve capture
cadence limitations and report each case's actual evidence scope.

## Verification matrix

| Group | Required cases on each app |
| --- | --- |
| Input | Slow/fast previous and next, short cancel, reverse, repeated input, diagonal/vertical arbitration |
| Identity | Same-volume pages, both volume edges, first/last collection boundary, stale or canceled target completion |
| Readiness | Fresh/unloaded target, warm revisit, failed/retried request, verified offline base content |
| Position | Recent-page return, unseen-page header, Continue, Saved, explicit Contents target, preference/content changes |
| Layout | Controls shown/hidden, top/bottom clearance, LTR/RTL, large bilingual text, translation growth, Reduced Motion |
| Access and cost | Native accessibility actions, preserved privacy/fences, matched request/memory evidence, idle reader traffic |

Run Android instrumentation only through the guarded `run-android-ui-tests.py`
runner with explicit `emulator-5554` and one repeated `--class` argument per case.
Reuse the existing iPhone 18 Pro simulator/runtime. Physical phone work uses the
explicit selected device when available. Fixtures, simulator/emulator results,
physical evidence, language approval and live-service proof remain distinct.
Build with the repository commands and run focused unit tests for changed state
transitions. A build or fixture does not close the native motion or external gates.

## Following fetch and offline translation work

The later collection/page opening session shares the efficient content path;
measure opening latency there. Existing verified offline base dumps may be reused
only with their real source identity and canonical anchors. They are not live
server pages with interchangeable ordinals or content versions.

The owner also wants durable offline translations for only the chosen language.
Keep this requirement explicit. Version 1 translation packs are currently blocked
because they lack entry-level rights and revocation identity. Design a separate
rights/publication-aware artifact and manifest contract, exact-locale selection,
invalidation and native verification before enabling them. Do not revive v1 packs
or treat a cached translation as permission to redistribute it. Backend/cloud,
migration, account, paid-model and publication actions keep their action gates.

Screenshot-aware sharing, functional pill navigation, simulator consolidation,
bounded crash-safe saving and the prior Free–Pro/translation-reliability program
remain separate recorded work. Original G01–G41 and all acceptance/deferral gates
remain unchanged.

## Execution and next task

Use this chat's planning decisions and bounded Terra coding tasks. Apply `how`
to unfamiliar paths, `architect` before changing the state boundary, the native
review procedure for rendered changes and focused regression tests for the
reproduced reset. Use one independent review for the consequential ownership or
request-cancellation risk. A full model panel and Cursor-specific pipeline are
not prerequisites. Review scoped diffs, preserve incoming files and commit each
verified logical unit without pushing.

Experience First includes the surrounding reader controls in the destination.
Sequence Work into Verifiable Units keeps the first repair at landing/return.
Model the Domain separates recent positions, reusable content and pending turns.
Laziness Protocol keeps loading presentation at one boundary. Build the Lever
produced the reusable native gesture probe. Prove It Works requires the actual
native before/after replay, rather than a passing build.

Next task: implement Unit 1 on both native apps. Start with the recorded A → B → A
case and the existing single-owner landing contract. Preserve all earlier scrolling
and cost repairs. Stop after verified recent-page restoration, updated evidence
and a scoped commit; then select Unit 2.
