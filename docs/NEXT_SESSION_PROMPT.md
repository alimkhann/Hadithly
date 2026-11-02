# Next session: recent-page return without a landing jump

Read PLAN.md's current checkpoint and mistakes, PAGE_TRANSITION_PLAN.md Unit 1,
PAGE_TRANSITION_BASELINE.md and the Page and volume transitions prompt in
SESSION_PROMPTS.md. The owner requested planning first; discovery and the product
decisions are complete, but implementation has not started.

## One outcome

On iOS and Android, scroll page A, turn to B and return to A. A must appear at
its earlier reading position throughout the swipe and after landing. A new page
starts at its header. Explicit Continue, Saved and Contents targets keep priority.
Use one native landing writer and the existing semantic reading-position model.

The physical iOS baseline directly shows the defect. In hadithly-controlled.mov,
the returning page is already scrolled at 44.265–44.432 s, then appears at its
header by 44.624 s. The installed Sajda comparison retains its scrolled position.
Raw video, original timestamped frames, test results and the standalone gesture
driver are local under
/Users/alim/Developer/Artifacts/Hadithly/page-transitions-20261102.
The portable record is docs/verification/page-transitions/baseline.json.

## Work and verification

Keep temporary recent-page positions bounded to the open reader. Retained reader
sheets/backgrounding do not end that session. Reader closure/account change clears
it; after process restart the durable Continue position remains authoritative.
Keep content/layout identity checks and semantic re-anchoring after preference
or text changes. Do not replay incompatible raw offsets or add competing resets.

First prove the desired recent-page return fails in the existing implementation.
Repair the model decision and rendered neighbor/active handoff on each platform.
Check unseen-page headers, explicit semantic entry, canceled turns and large
bilingual text changes. Repeat the same native A → B → A case and inspect actual
frames after landing. Run focused safety tests and recheck accepted scrolling in
its recorded scope. A build or fixture is not physical motion proof.

Use bounded Terra coding tasks with separate native files; review their diffs
and serialize device runs. Use the existing iPhone 18 Pro simulator and installed
runtime. Android instrumentation uses the guarded repository runner with explicit
emulator-5554 and separate --class arguments. Coordinate physical phone availability
again if a later session cannot establish that it is free. Do not record passcode
entry; any fresh iOS automation approval is done by the owner.

Commit the verified paired-platform unit and evidence without pushing. Stop before
Unit 2 content reuse or a broad layout rewrite. Preserve the full remaining plan.

## Decisions for following units

Keep configurable direction and translation-language Automatic behavior. Follow
Sajda closely for motion and surrounding controls. An unavailable target keeps the
current text with a quiet cue until ready; keep presentation separate from pending
turn identity so a destination loading page can be chosen later without a rewrite.
Reuse fetched neighbors and deduplicate requests before wider speculative prefetch.
Compare one-page versus two-page lookahead using matched waiting, request/cost and
memory evidence. Do not silently enable more calls or generation.

Offline base pages and live pages have different identities. Chosen-language
translation packs are currently blocked because v1 lacks rights/revocation identity.
Keep the owner's durable exact-locale offline translation request as a separate
artifact/manifest/native contract unit. Cloud, backend deployment, migration,
account, paid-model and publication actions keep their action-time approval gates.

## Preserved work and gates

Scrolling is accepted at the retained 1.34 ms/s result, not a strict below-1 pass.
Keep 7774dcd, b9d8604, a6c3035 and the removed-experiment record cbd1376. Preserve
owner checkpoint 2ad8243, tag reader-smooth-owner-20261102 and its signed bundle
archive in SMOOTH_READER_CHECKPOINT.md. Do not reset app data or overwrite incoming
iOS project/scheme/catalog changes or six Python cache files.

Keep recent Convex notification/outline/reader reductions, A2 row mode off,
completed A5/B/C/D, G01–G41, A1/A3/A4 acceptance, A7/G38 deferral, E actual Linear
and final audit. Screenshot sharing, interactive pills, simulator consolidation,
general opening latency, bounded crash-safe saving and Free–Pro/translation
reliability remain recorded later work. No original release, accessibility,
language, authenticated/device or external gate passed in discovery.
