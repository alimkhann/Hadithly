# Product readiness review

October 17, 2026. This review uses the current checkout, local audits, and the
owner's reported defects. It is not a fresh production or store-console audit.
No release gate is closed by this review.

## Give the first useful reading a dependable path back

Hadithly's next milestone should be a complete reading experience: choose a
language, understand a hadith, inspect its provenance, save it, and recover it
later. This is a product hypothesis to test with readers. The current evidence
does not establish which moment makes people return.

The owner linked the same video twice:
[Tim Gabe, How Top 1% Apps Earn Your Second Visit](https://www.youtube.com/watch?v=YA3QpYIKqNI).
I read its full English caption track, inspected a contact sheet across the
video, and inspected selected reveal frames. Pi extracted 23 frames in total. The local Pi `video-extract` extension produced
the frames from a downloaded public video after its remote-stream path failed.
Captions came from the video's English caption endpoint after rate-limit errors.
No Gemini analysis, Pi model session, or paid inference was used.

The case study distinguishes onboarding completion from actual use
([0:56](https://www.youtube.com/watch?v=YA3QpYIKqNI&t=56s)), finds a voluntary
return around a valuable result
([5:36](https://www.youtube.com/watch?v=YA3QpYIKqNI&t=336s)), and makes the first
trial useful ([9:22](https://www.youtube.com/watch?v=YA3QpYIKqNI&t=562s)). Its
processing and reveal sequences make state and payoff tangible
([11:14](https://www.youtube.com/watch?v=YA3QpYIKqNI&t=674s),
[14:48](https://www.youtube.com/watch?v=YA3QpYIKqNI&t=888s)). It presents design
rationale and founder reactions, not measured post-launch retention uplift.

For Hadithly, the corresponding opportunity is a calm, trustworthy reading with
an easy return to a saved passage or reading position. Animation should explain
availability and acknowledge an action. It should not delay access to the text.

## Findings that change the next work

The localization counts below are the read-only baseline before the scoped
reader-state changes in this session. They are not release approval.

| Finding | Evidence | Consequence |
| --- | --- | --- |
| Ordinary AI generation is ungrounded for both free and Pro. | `backend/convex/actions/ai.ts:29` makes one structured generation call without retrieval tools. `backend/convex/quotas.ts` publishes `groundingUsed: false, citations: []`. Q1 explicitly removed ordinary web grounding. | This is a deliberate existing cost contract, not a paid-only retrieval feature. A canonical hadith link is separate from evidence used for a translation. Existing cached records may have different provenance. Production was not queried here. |
| Pro changes allowance, not research depth. | Both account tiers reach the same generator. `generationPolicy.ts` defines five free versus 100 Pro new translations in a rolling seven days. | Do not imply that Pro translations are more researched or verified. |
| The first reading can miss the chosen language entirely. | `actions/daily.ts:resolveDailyTranslation` returns null when the exact-locale translation is not cached. Onboarding then shows Arabic plus Retry. That read-only retry does not create the missing translation. | This is a high-priority activation risk. Prove a useful exact-locale first reading without depending on sign-in or a fresh AI request. The frequency in real use has not been measured. |
| Localization remains incomplete. | The existing audit reports 3,944 iOS draft units, 75 missing-value failures, and 1,344 Android English-copy draft units. Its Android scan covers only `strings.xml` and `la2.xml`. | Resource presence is not translated runtime coverage. These are audit counts, not counts of visible defects. |
| A broader Android check finds more coverage than that audit inspects. | All default XML files contain 292 translatable string entries. Arabic, Russian, Urdu, and Latin American Spanish each have values for all entries, but 94 values match English exactly. Some identical names or symbols may be legitimate. | Audit every XML file and the actual visible journeys before calling a locale complete. |
| The reported RTL return defect escaped label-only coverage. | A new real-root iOS onboarding test reproduces the English name moving from x=62 to x=285 after Arabic → English. Recreating only the language list on a direction change restores its geometry. Android onboarding and Settings round trips pass. | Keep the row-geometry regression and native Settings captures. Physical-device and broader locale gates remain open; see `LANGUAGE_SWITCH_VERIFICATION.md`. |
| Private sync has unresolved product evidence. | `OPEN_GATES.md` retains the September 30 report of missing cross-device Saved/progress sync. | Prove saving and recovery in both directions before relying on sync in acquisition or paid conversion claims. |
| Current analytics cannot answer cohort retention. | `LA2_DESIGN.md` explicitly describes clipped counts rather than unique readers or long-term retention. Development collection was disabled after verification. | No current D1/D7 retention or acquisition baseline has been established by this review. |

The generator still receives the provider's hadith text as input. It performs no
external retrieval. Its original-text reference does not verify the translation.

Adding source links for appearance would weaken trust. A grounding improvement
needs real retrieved evidence, exact hadith identity, supported claims, attribution,
and an honest distinction between original text, published translation, and AI
translation. One relevant primary source can be stronger than several duplicate
sites. Keep that quality standard across tiers. Evaluate costs, rights, failure
behavior, and cached provenance before proposing activation; this review does not
change provider tools, budgets, old translations, or deployments.

## Work in this order

| Order | Bounded milestone | Completion evidence |
| --- | --- | --- |
| 1 | Deliver the first useful reading in the chosen language. | A guest reaches actual exact-locale text and its provenance, including when today's translation is absent. Keep the canonical Daily contract intact. Language round trips and reader-state repairs from this session are recorded separately; they do not prove this content-availability gate. |
| 2 | Close the core trust loop. | An authenticated reader saves a passage/note and reading position on one platform, recovers them on the other, and repeats in reverse. Grounding behavior and source presentation match their claims. |
| 3 | Finish a bounded localization journey before expanding the pass. | Welcome → language choice → first reading → Saved → return → failure recovery has translated runtime text and correct direction. Then complete the fifteen-locale L1 scope with its required copy review and dependency gates. |
| 4 | Run one consolidated release proof. | Physical reader/accessibility/offline/push/widget matrix; both stores' real purchase/restore/expiry/refund/account-switch receipts; rights, disclosures, production backup/recovery, and operational readbacks. Keep each receipt linked to its original gate. |
| 5 | Test the reading promise with a small invited group. | Observe first useful reading, attempted saving, and later return without coaching. Ask why people came back or stopped. Record consent and avoid collecting reading text or notes. |

Start lightweight audience conversations and draft store positioning alongside
the first milestones. Spend substantial acquisition money only after the core
journey and purchase claims have evidence. Test one promise and one audience at
a time. Candidate promise: understand a hadith in your language and keep what
matters close. This is proposed positioning, not a validated conversion claim.

Choose the return experience from those observations: resuming an unfinished
reading, revisiting Saved, or opening the daily hadith are candidates. Existing
widgets and optional reminders can support a demonstrated habit. They do not
establish retention by themselves. No streaks, ranking, or pressure mechanics.

Measure the stages separately: chosen language → readable exact-locale text →
voluntary save or continued reading → a later return. Visibility and taps are
proxies, not proof of comprehension. Purchase conversion comes after delivered
value. Begin with observed sessions and consented follow-up; any new cohort
instrumentation needs its own privacy contract and rollout. The present LA2
totals cannot establish these outcomes.

## Keep the gates legible

`OPEN_GATES.md` remains the detailed register. Its older external readbacks need
refreshing when that track resumes. Group them operationally:

- **Core product:** reported language transition, incomplete copy, cross-device
  sync, translation/source truthfulness, physical reader and accessibility proof.
- **Money and distribution:** Apple compliance and sandbox receipts; the
  owner-deferred Play account/setup; real entitlements and quota retry. The
  monthly-equivalent-only paywall remains a prototype requiring release revision.
- **Content and operations:** rights/adaptation/redistribution, translation-pack
  provenance, production rollout/disclosures, backups/recovery and provider costs.
- **Device integrations:** exact-open push, widget restoration, offline and
  account-change behavior. Fold overlapping checks into the physical matrix.
- **Later:** LA4 web reader stays deferred. Full L1 and D4 retain the dependencies
  in `PLAN.md`; this review does not silently reopen them.

An architecture rewrite is not the next milestone. Investigate architecture
where a reproduced failure or measured constraint points to it. Keeping one
complete reading-and-return path as the acceptance target prevents another
unbounded polish pass from substituting for product proof.
