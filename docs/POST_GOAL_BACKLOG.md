# Goals after the original product program

Owner reports received October 31, 2026. The owner has now prioritized one bounded
Convex diagnostic and usage reduction before original acceptance. That
continuation now has verified development notification/outline reductions and
native readbacks. See `CONVEX_USAGE_REDUCTION_AUDIT.md` and
`NEXT_SESSION_PROMPT.md`. Staying free is important;
low cost is permissible but has no approved numeric spending ceiling. The current
destination is a finished app experience with release dependencies deferred.

The owner subsequently selected priority-2 font-size and Settings-direction
verification as the first goal in a proposed priority 2–4 sequence. Both existing
A5 repairs pass fresh native checks on November 1; no product change was needed.
See `PRIORITY2_VERIFICATION.md`, committed as `85adf64`. The owner then started
priority-3 scrolling and approved physical profiling and installation. The bounded repair addresses iOS progress writes, repeated partition decoding
and full-bleed controls on both apps. The installed iPhone passes agent-driven
slow/faster hitch targets in their recorded scope; see `SCROLLING_VERIFICATION.md`.
The owner then approved a stricter optimized-development continuation, below
1 ms/s in every retained warm run plus owner confirmation. Its baseline and
architecture decision are complete. The retained matched large-type result is
1.34 ms/s; the stricter target was not achieved. On November 2 the owner said
that result may already be good enough and asked us to prioritize useful work
over marginal tuning. The feature/saving audit and installed-build owner check
are complete; the owner confirmed scrolling is good enough to close this round.
Broader original acceptance remains open.

These exceptions change only the named units' order. Preserve the original
objective in `PRODUCT_PROGRAM.md`, its final audit and every open gate. Other
backlog work remains later. Saved/A5 repairs already completed are not new work.

The table retains the original reports with their current first-unit status.
Priority-2 defects were reproduced and repaired in A5, then freshly checked here.
The scrolling findings and verification are recorded below; unmeasured reports
remain unconfirmed. Existing cloud/account/model,
device, rights and release gates still apply. If a symptom also blocks an original
A5 requirement, fix only the original requirement's necessary scope and record
the overlap. Avoid duplicate work or using overlap to authorize a broad redesign.
An external gate that cannot yet pass remains open; it does not make the original
objective complete or authorize skipping ahead to this backlog.

## Owner's November 2 continuation

Only the feature/saving audit is being completed now. Do not implement the
following new requests together. The owner wants separate verifiable sessions,
with page/volume swiping next. Preserve all original product gates and the
completed Convex cost reductions.

### Current closeout: preserve features and explain adjacent work

[READER_FEATURE_PRESERVATION_AUDIT.md](READER_FEATURE_PRESERVATION_AUDIT.md)
records retained capabilities, work that caused scrolling stalls, what still
runs, cache limits and the exact local-save/cloud-sync distinction. New on-disk
tests cover guest exit and an offline account's background-style save/reopen.
The failed early-axis experiment was removed and the retained development build
restored on the iPhone. The owner-preferred exact older bundle/tag remain.
The owner has confirmed the restored installed build is good enough.

Carry these reliability findings forward rather than claiming perfection:

- Continuous scrolling can defer the newest durable checkpoint until a pause
  or lifecycle flush. Design bounded crash-safe checkpointing through one
  ordered writer outside the scrolling UI path; preserve owner/session/deletion
  fences, capture timestamps, rollback and queue replay.
- Upload completion before suspension/force-close is not guaranteed. Preserve
  local-first durable queueing and retry; verify offline/background/relaunch
  behavior on each platform without promising a final termination callback.
- Audit cancellation/deduplication of adjacent warming and translation work,
  save-failure visibility and account changes as focused follow-ups. Do not
  delete necessary publication/privacy checks to reduce work.

### Next session: page and volume swiping

The November 2 interview and matched physical-iPhone discovery are complete.
[PAGE_TRANSITION_PLAN.md](PAGE_TRANSITION_PLAN.md) is the implementation sequence;
[PAGE_TRANSITION_BASELINE.md](PAGE_TRANSITION_BASELINE.md) records the direct
reposition/loader evidence and remaining cases. Product repairs have not started.
The owner chose temporary recent-page restoration, retained direction settings
and current-text-visible waiting. Reuse/deduplication comes before wider prefetch.
The next bounded unit is recent-page restoration on both apps. The later request
for chosen-language offline translations remains explicit; v1 packs are blocked
and need a separate rights/publication-aware contract rather than reactivation.

The owner reports jitters, jumps, frequent loaders and incorrect gesture cases,
including with offline collections installed. The agent should derive the
interaction matrix rather than require the owner to enumerate every bug.

- Inspect **Sajda on the actual iPhone** and compare forward/backward swipes,
  slow tracking, fast flicks, short canceled/reversed drags, repeated gestures,
  page ends, cross-volume/juz transitions, focus controls and unloaded targets.
- Capture local native video of the small animations. Use actual video frame
  timestamps and frame-by-frame inspection, approximately 10–100 ms apart as
  supported by the capture. Report actual frame rate; slow screenshots or
  upsampled frames do not establish motion fidelity. No external upload.
- Reproduce Hadithly with cold/warm content, verified offline data, long bilingual
  and large text, RTL/LTR and translation growth. Write the motion/landing/cache
  contract before implementation and compare the same cases afterward.
- Preserve one native vertical-scroll owner. Explicit Continue/Saved/Contents
  targets take priority, valid session recent-page positions come next, and unseen
  pages land at headers. Content caching must not add a competing offset writer.
  Preserve accessible controls and platform meaning.
- Target the quality of Sajda or better, while retaining Hadithly typography,
  source actions, privacy and cost controls. Do not mask an incorrect state
  transition with animation or assume Sajda's internal renderer.

### Following session: fast collection/page opening and fetching

The owner wants opening books, fetching pages and moving through downloaded
collections to feel immediate, with a considered layout transition.

- Measure tap-to-first-readable-content and ready-to-interact latency for cold,
  warm and offline openings, separately from animation duration.
- The current iOS path normally requests Convex first when reachable; offline
  dumps are fallback rather than a universal local-first path. Adjacent-volume
  warming discards returned payloads and primarily warms server data. Investigate
  reusable bounded client content caches, in-flight request deduplication and
  verified offline-first reads instead of merely adding more prefetch calls.
- Preserve current Convex notification/outline/read reductions, Convex as the sole
  mobile API/control plane, content identities, exact locale and publication/
  rights invalidation. Do not reverse cost improvements to hide latency. Keep
  server/cloud/schema/paid-provider changes behind their existing action gate.
- Verify the actual online and downloaded journeys. A layout animation is part
  of quality, not proof that data became available sooner.

### Later feature: screenshot-aware sharing

Inspect Sajda's actual iPhone screenshot reaction before designing Hadithly's.
Provide an appropriate share/tag/follow flow for launch marketing. The owner
currently has no marketing accounts, so do not create accounts, invent handles
or ship dead social links. Keep screenshot detection distinct from collecting
or uploading screenshot contents; sharing remains an explicit user action.
Verify the corresponding Android behavior when this feature is implemented.

### Functional floating progress pills

Implemented November 4, 2026 as the reader volume/page jump sheet.

The owner chose volume-relative numbers for both the pill and the Page wheel.
Either revealed pill opens the same sheet at the current location. Scrolling
past the last page advances the Volume wheel and shows Page 1. Scrolling back
from Page 1 selects the last page of the previous volume. Choosing a volume
directly selects its first page. Go jumps to the top of a different page and
keeps the current position when the selected page is already open.

The sheet follows the owner's Sajda screenshot and the observation in
[PAGE_TRANSITION_BASELINE.md](PAGE_TRANSITION_BASELINE.md). Exact page counts
come from the current reader source and uncached volumes resolve on demand —
never by fetching every volume in the collection. See
[READER_JUMP_VERIFICATION.md](READER_JUMP_VERIFICATION.md) for the recorded
gates. Wheel states, counts and Go reuse the reader's existing loading and
retry machinery through `TurnTarget.Jump`.

### Reader content in the selected translation language

Chapter headings and the named volume header currently read the source outline.
For Sunnah.now, the named volume header usually repeats the first chapter title.
Use the source's title in the selected reading language when available. For
other languages, resolve and cache a rights-checked translation by chapter and
language. Reuse that title for the volume header when it names the first chapter.

The grey narrator line uses the source English narrator in mixed and
translation-only reading. The AI generation response carries the translated
hadith body as one string. Give the narrator its own localized field and use
the Arabic narrator source when available. Keep existing published bodies
readable while narrator translations become available. Verify both native apps
with the app interface and reading translation set to different languages.

### Separate maintenance: keep one simulator

The owner wants only the existing **iPhone 18 Pro** simulator retained. The current
inventory includes Hadithly Convex Cost, Hadithly LA2 iPhone 18 Pro and iPhone 18
Pro on the same installed iOS 27 runtime. A simulator device's data and a shared
OS runtime are different things; inventory both before deleting anything.

After active tests finish, consolidate duplicate devices while preserving the
retained iPhone 18 Pro's state and needed verification evidence. Do not delete
physical-device data or unrelated development artifacts. Reuse the retained
device/runtime for subsequent checks; the prevention rule is in AGENTS.md.
This cleanup is recorded for a later session, not performed during this audit.

The original translation-reliability/Free–Pro testing goals and all prior
backlog rows remain. Select their later ordering explicitly rather than losing
them behind these newly recorded requests.

## Suggested preparation

These are agent recommendations for the later work, not new prerequisites that
delay the original objective.

1. Establish a read-only Convex cost baseline for cold launch, first reading and
   ten page moves. Separate calls, reads, bytes, actions and paid-provider usage.
   Prioritize measured waste while preserving correctness; estimate free-plan
   capacity from real workload assumptions rather than promising unlimited use.
2. Keep a repeatable reader performance workload, recording device, build,
   collection, translation, text size and cache state. Use the same workload for
   before/after scrolling and page-transition evidence.
3. Add a small language-switch regression matrix covering Arabic → English,
   same-process back navigation, Settings and restart. Compare meaning and copy
   length across apps while allowing platform-appropriate layouts.
4. Define a safe development entitlement/test-account contract for free/pro
   testing. Preserve production quota enforcement and distinguish test overrides
   from actual store/RevenueCat lifecycle proof.

Use one bounded unit at a time. Convex usage reduction and priority-2 verification
are complete within their recorded scopes.
The later priority proposal is functional reader defects and translation
reliability, then broader native polish. No extra vendor, task database or large
architecture rewrite is needed before a measured gap justifies it.

## Owner goals and proposed first units

| Priority proposal | Owner report or goal | First bounded unit |
| --- | --- | --- |
| 1 | Convex usage is far too high for one reader. Support many readers within the free plan where practical, using sound practices. | Measure the baseline above and trace the largest repeated work to its caller before proposing an optimization. |
| 2 | Reader translation font size does not work. | A5 repair freshly verified on both apps November 1. Actual 14→22 rendered text growth and both settings entry points pass; see PRIORITY2_VERIFICATION.md. |
| 2 | Switching Arabic → English and returning to Settings leaves it RTL/upside down. | A5 repair freshly verified on both apps November 1. Same-process root Settings return and reopening checks pass; see PRIORITY2_VERIFICATION.md for exact scopes. |
| 3 | Reader scrolling is laggy on iOS; Android performance is unknown. | Retained optimized large-type run is 1.34 ms/s. Owner accepted the restored installed build; feature/saving audit completes this round. The stricter below-1 target was not achieved. See READER_FEATURE_PRESERVATION_AUDIT.md. Android physical/release performance remains open. |
| 3, next | Page swipes have loading jerks and insufficient caching. | Follow the November 2 Sajda/video comparison and transition matrix above. Treat collection/page opening latency as the following separate session. |
| 4 | Free-account AI translations have a low success rate and fail inconsistently. | Classify failures by quota, attestation/auth, provider, exact-locale content and cache, without unapproved paid probes. |
| 4 | Make switching free/pro behavior easy for testing paid features and limits. | Design the explicit development-only test contract above; never create a production quota bypass. |
| 5 | Android UI/UX looks poor, possibly because it copies iOS rather than fitting Android. | Review one reading journey against Android conventions; preserve capability, meaning and privacy while allowing different layouts. |
| 5 | Android localization is too verbose and differs from the better iOS wording. | Compare selected exact messages and wrapping with iOS; retain separate native-speaker approval. |
| 6 | The third onboarding screen's translation demo is too fast and its structure is wrong. Reuse the real reader UI inside a Daily Hadith card and slow the reveal enough to see it. | Review that contained-reader prototype, pacing and reduced motion; label demonstration behavior separately from live AI generation. |
| 6 | Simplify sign-up, sign-in and provider-auth screens, spacing and sections. Keep users in native UI where supported, retaining browser handoffs where needed. | Map current native/hosted flows and vendor requirements, then propose one simpler screen and verify cancellation/recovery as well as success. |
| Later, gated | Build a proper lightweight web reader. | Revisit LA4's existing rights, demand, privacy, accessibility and cost conditions before implementation. |
| Separate maintenance | Clean up GitHub and maintain the repository to an open-source standard. | Audit README, contribution/security guidance, CI, licenses, content rights and artifact hygiene before remote or publication changes. |

The order is a proposal. Choose each unit's observable result and acceptance
evidence before implementation. This later backlog does not close Saved, A4,
native review, content, physical-device, account, store or release gates.
