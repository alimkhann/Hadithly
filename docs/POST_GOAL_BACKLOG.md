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
priority-3 scrolling and approved physical profiling and installation. The active
repair addresses iOS progress writes and full-bleed controls on both apps; see
`SCROLLING_VERIFICATION.md`. Paired physical repair acceptance is open. Page
transitions and priority 4 remain subsequent goals.

These exceptions change only the named units' order. Preserve the original
objective in `PRODUCT_PROGRAM.md`, its final audit and every open gate. Other
backlog work remains later. Saved/A5 repairs already completed are not new work.

The table retains the original reports with their current first-unit status.
Priority-2 defects were reproduced and repaired in A5, then freshly checked here.
Other reports are not established findings. Existing cloud/account/model,
device, rights and release gates still apply. If a symptom also blocks an original
A5 requirement, fix only the original requirement's necessary scope and record
the overlap. Avoid duplicate work or using overlap to authorize a broad redesign.
An external gate that cannot yet pass remains open; it does not make the original
objective complete or authorize skipping ahead to this backlog.

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
| 3 | Reader scrolling is laggy on iOS; Android performance is unknown. | Active: approved physical baseline identifies synchronous progress/account work; local iOS batching and both native full-bleed repairs are being verified. Paired physical timing/owner readback remains open; see SCROLLING_VERIFICATION.md. |
| 3 | Page swipes have loading jerks and insufficient caching. | Measure transition latency, cache behavior and visible position under the same workload. |
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
