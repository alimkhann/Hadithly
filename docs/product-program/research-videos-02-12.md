# B research: videos 02, 03 and 05 through 12

Reviewed October 27, 2026. This batch covers ten manifest videos. Every available
English automatic transcript was read completely, including sponsorship segments
and the full 48-minute founder interview. Twenty-four selected video frames were
extracted and inspected. Video 04 belongs to a separate review batch.

The videos are first-person product diaries or interviews. Their revenue,
retention, costs, user comments and claimed improvements are self-reported. No raw
cohorts, controlled experiments, source code or independent financial records were
available in this review. Static frames establish the pictured UI, not animation
quality, accessible behavior or causal conversion effects. All decisions below
are Hadithly judgments, not findings that these changes increase its retention.

Raw captions and frames remain outside git in `/Users/alim/Documents/Codex/2026-10-27/hadithly-product-research/`.
Each section records the exact transcript SHA-256 and inspected frame names;
resolve a frame under `/Users/alim/Documents/Codex/2026-10-27/hadithly-product-research/<video ID>/`. The directory is
a local evidence archive, not public media hosting. Re-extract frames with
`scripts/collect-product-research.py --output /Users/alim/Documents/Codex/2026-10-27/hadithly-product-research --ids ID
--frames SECONDS ...`. No Pi session, inference call, contact or tracking change
was made for this review.

## 02. How My App Is Doing (Kind of Stuck)

[Source video](https://www.youtube.com/watch?v=kLEM58wpbmo). Full available
transcript reaches 17:39.9 of the listed 17:40 duration.

- [00:32](https://www.youtube.com/watch?v=kLEM58wpbmo&t=32): The creator reports roughly $3.2K to $3.5K MRR with substantial churn. Revenue stability does not establish a stable return journey.
- [02:41](https://www.youtube.com/watch?v=kLEM58wpbmo&t=161): Real use changed the watch design from calories consumed to calories remaining. At 06:32, dictation failed through the phone connection; the creator changed the architecture for timely requests. His own use and reliability claims are anecdotes, not fleet measurements.
- [12:55](https://www.youtube.com/watch?v=kLEM58wpbmo&t=775): The share extension reuses the existing processing path. At 15:29, automatic summarization gets a first-use explanation and an opt-out. The creator explicitly says its retention effect is unknown.

Apply the narrow lesson to C2: explain an automatic translation change where it
happens, preserve a manual action and make the resulting text understandable.
Keep entry points bound to the same content identity. Defer a watch app and an
inbound image-processing extension. They do not address the current reading
refinements. Reject automatic summarization of hadith text.

Frames: `frame-00095.jpg` at 01:35 shows the watch's remaining-calorie view;
`frame-00932.jpg` at 15:32 shows a compact text log during the summarization
segment. They do not establish transition timing or retention.

Transcript SHA-256: `0cd660563938fd66b0951eee733756ef01b0524ea4ff6ba0c66b0a311fdf2b36`.

## 03. How I Make Apps FEEL Premium (5 examples)

[Source video](https://www.youtube.com/watch?v=MXLF8b15GhQ). Full available
transcript reaches 14:08.9 of 14:11.

- [00:49](https://www.youtube.com/watch?v=MXLF8b15GhQ&t=49): Instant text replacement works technically but gives poor feedback. A toast and then an in-place animation make the change visible; 01:47 introduces the final gradient treatment.
- [03:30](https://www.youtube.com/watch?v=MXLF8b15GhQ&t=210): The creator contrasts custom onboarding illustration with generic art. Praise from viewers is self-reported and does not measure comprehension or completion.
- [10:17](https://www.youtube.com/watch?v=MXLF8b15GhQ&t=617): An inline camera keeps the action close to its context. At 11:36, restaurant context improves a difficult dictation case; the creator says location use is opt-in.

Apply in-place translation feedback and context-preserving reader sheets to C2,
with native motion, cancellation and reduced-motion behavior. Judge the state
change by whether a reader can follow it. Keep website imagery coherent in D.
Reject adopting the purple gradient, location collection or lengthy prompting
as requirements. None is evidence of Hadithly value or an accessibility result.

Frames: `frame-00107.jpg` at 01:47 is presenter-only; `frame-00115.jpg` at
01:55 shows the text log in the final-animation demonstration; `frame-00628.jpg`
at 10:28 shows ChatGPT's inline camera reference. The still at 01:55 cannot
establish the quality of the animation.

Transcript SHA-256: `e9be828deaa4076dd52cd19a7da53e24e0f6cc8385610180b6c2cadc1e4290a1`.

## 05. I asked SF founders: should I keep bootstrapping?

[Source video](https://www.youtube.com/watch?v=xlOyK8Pt3WQ). Full available
transcript reaches 48:31.6 of 48:32, including the interviews and closing material.

- [20:29](https://www.youtube.com/watch?v=xlOyK8Pt3WQ&t=1229): Wispr Flow's CTO distinguishes testing one's product from choosing it during ordinary work. He reports that Chrome-only availability interrupted use outside the browser. The abandonment estimate is a founder account without cohort definitions.
- [23:04](https://www.youtube.com/watch?v=xlOyK8Pt3WQ&t=1384): The discussion treats early retention as a predictor of longer-term retention and recommends finding meaningful engagement thresholds. Words dictated fits that product; opens per day is not a universal value measure.
- [24:52](https://www.youtube.com/watch?v=xlOyK8Pt3WQ&t=1492): Watching a few people onboard exposed confusion faster than waiting for analytics. Later, the Greptile interview similarly describes correcting obviously poor behavior before building elaborate evaluations. These are practitioner judgments, not grounds to omit security or semantic checks.

Apply an ordinary first-reading, save and return walkthrough with comprehension
checks to C and A7. Keep existing platform parity because an unavailable action
can interrupt an otherwise useful journey. Defer new analytics machinery until a
specific question requires it. Reject maximizing reading frequency or copying
dictation thresholds. No funding recommendation or account action follows from
these interviews.

Frames: `frame-01230.jpg` at 20:30 and `frame-01505.jpg` at 25:05 show the
CTO interview with matching product-use/onboarding subtitles. No retention graph
or underlying dataset is visible in either frame.

Transcript SHA-256: `3dc8c95a94912d1eb5368ef210e008aa7d451661ea6e3a52f0aa4f7838239439`.

## 06. How My App Is Doing (4 Month Update)

[Source video](https://www.youtube.com/watch?v=yj33J3f2Zgk). Full available
transcript reaches 13:07.4 of 13:10.

- [00:09](https://www.youtube.com/watch?v=yj33J3f2Zgk&t=9): The creator reports week-one retention rising to 22%. He calls the prior value 12% near the opening and 13% at 01:37. Several changes occurred together, so neither a precise baseline nor a causal effect is established.
- [03:17](https://www.youtube.com/watch?v=yj33J3f2Zgk&t=197): Churned readers of the calorie app reported that they could not trust its outputs. The creator separates vague input from genuine data/model failures rather than relying solely on a successful internal benchmark.
- [07:20](https://www.youtube.com/watch?v=yj33J3f2Zgk&t=440): Accuracy education added late in onboarding was skimmed. At 08:17, observed sessions prompted concrete visual examples, and the creator reports better understanding. At 11:42, real model accuracy work remains unfinished.

Apply a short, concrete explanation of AI provenance and uncertainty at the
reader action in C2/C8. Check whether someone can explain what they received.
In D, link exact evidence where available and keep unsupported accuracy claims
out of marketing. Reject treating polished education as a fix for wrong meaning,
and reject claiming that the new onboarding caused the reported 22% retention.

Frames: `frame-00450.jpg` at 07:30 shows an accuracy comparison screen;
`frame-00530.jpg` at 08:50 shows side-by-side vague/specific food examples.
The visible benchmark is the creator's own report, not independent validation.

Transcript SHA-256: `13474636a28a3cbd3ae81cc815d392426797495b8b593547c5f6079612fd0912`.

## 07. How My App Is Doing (Not Good)

[Source video](https://www.youtube.com/watch?v=l763SzomQN0). Full available
transcript reaches 13:35.5 of 13:39.

- [02:13](https://www.youtube.com/watch?v=l763SzomQN0&t=133): An authentication failure during a backend outage left a blank screen despite an existing offline mode. Support inside Settings was unreachable.
- [03:33](https://www.youtube.com/watch?v=l763SzomQN0&t=213): The replacement keeps local use available, shows pending changes and service status, and explains automatic rechecking. At 05:04, the creator catches the mistake of hosting the outage message on the failed service itself.
- [09:10](https://www.youtube.com/watch?v=l763SzomQN0&t=550): User-editable profile rows also contained subscription and rate-limit fields. The creator reports fixing that trust-boundary defect. Later recommendations about provider caps are not verification that any specific provider currently enforces a hard cap.

Apply clear retry/unavailable states in C2 while keeping existing readable text
and pending work intact. Keep public support reachable outside sign-in for D.
Preserve server authority for allowance and entitlement decisions. Do not infer a
new infrastructure or storage project, and do not copy the video's model fallback
or treat this story as proof that Hadithly has the same vulnerability.

Frames: `frame-00211.jpg` at 03:31 is presenter-only;
`frame-00235.jpg` at 03:55 shows the status sheet with local-data, sync and
pending-change explanations; `frame-00569.jpg` at 09:29 shows the illustrated
subscription/rate-limit columns. The outage, fix and financial exposure are
self-reported, not an independent security audit.

Transcript SHA-256: `c4f26105573e8f5e9ab7a62c34378949c44f194f1b77af091778c540df99403b`.

## 08. How My App Is Doing (2 Month Update)

[Source video](https://www.youtube.com/watch?v=4Ayyp8ewEzI). Full available
transcript reaches 11:02.9 of 11:04.

- [02:00](https://www.youtube.com/watch?v=4Ayyp8ewEzI&t=120): Separate handling for portion edits and repeated food caching reduced reported model costs. At 03:37, the creator reports 60% to 70% cache hits. The savings are app-specific, without raw usage or cost evidence.
- [07:09](https://www.youtube.com/watch?v=4Ayyp8ewEzI&t=429): Users did not recognize an editable description as editable. An explicit correction action addresses discoverability without adding a new capability.
- [08:51](https://www.youtube.com/watch?v=4Ayyp8ewEzI&t=531): Export is presented as trust-building. At 09:16, reminders become aware of already completed actions. The creator reports overall retention rising from 8% to 10.2%, after multiple simultaneous changes.

Apply visible actions for translation, retry and manual selection in C2 rather
than relying on gestures alone. Preserve export and quiet, voluntary reminders.
Keep canonical/exact-locale cache validity; do not copy approximate food caching
for authoritative text. Reject history lock-in as a retention goal, and do not
expand notification tracking or restart A2 from this example.

Frames: `frame-00455.jpg` at 07:35 shows the explicit correction action below a
photo description; `frame-00560.jpg` at 09:20 shows opt-in daily-reminder settings.
The frame does not prove suppression after a completed action.

Transcript SHA-256: `ce2fb5e6da523376569f8cc578141452da0920c03bb2ebaa139f314119da6074`.

## 09. My App Hit $1000/mo (But We Have A Problem)

[Source video](https://www.youtube.com/watch?v=x-XIo_RyMek). Full available
transcript reaches 11:55.3; metadata lists 11:54. This small duration discrepancy
is retained rather than treating metadata as exact media coverage.

- [01:10](https://www.youtube.com/watch?v=x-XIo_RyMek&t=70): The creator reports 100 paying users but only 8% week-one retention. In this video's wording, the denominator is trial starters; other updates say signups or downloads. The numbers are not directly comparable without definitions.
- [04:24](https://www.youtube.com/watch?v=x-XIo_RyMek&t=264): Photo output permits correction before calculation. At 05:45, expected micronutrient support matters to users even though it was not the product's original differentiator.
- [08:24](https://www.youtube.com/watch?v=x-XIo_RyMek&t=504): Re-running research for a simple portion edit produced unexpected totals and lost trust. The revised routing preserves the intended operation instead of recalculating unrelated facts.

Apply the expectation lesson to C2/C6/C7: translation choice, Contents jumps and
page switching should perform the named action while preserving reader context.
Keep the shared generation authority and existing GPT-only boundary. Reject
copying the multi-model stack, public feature voting or category retention targets.
No new model call is justified by this diary.

Frames: `frame-00275.jpg` at 04:35 shows the editable recognized description;
`frame-00287.jpg` at 04:47 is presenter-only; `frame-00560.jpg` at 09:20 shows
the creator's request-routing diagram. The diagram explains the claim but does
not verify its implementation or accuracy.

Transcript SHA-256: `8251383320456a172e1b699b72c5394b60f6f8e6c10c29c12ff7e5a11498bdaa`.

## 10. My app's first week (what actually happened)

[Source video](https://www.youtube.com/watch?v=6YFT7CwHvLk). Full available
transcript reaches 09:47.4 of 09:50.

- [01:47](https://www.youtube.com/watch?v=6YFT7CwHvLk&t=107): The creator initially reports 40% download-to-signup and later claims all 400 subsequent downloads signed up after Apple/Google login. The closing recap calls the original rate 60%, contradicting the earlier figure. Instrumentation, cohort comparability and attribution are unverified.
- [07:06](https://www.youtube.com/watch?v=6YFT7CwHvLk&t=426): Onboarding moves before account creation, with saving and cross-device use as the explanation for signing in. This was newly changed, not a demonstrated conversion result.
- [08:09](https://www.youtube.com/watch?v=6YFT7CwHvLk&t=489): Dismissing the paywall offers 24 hours without a payment card. It is a monetization experiment motivated by reported 60% dismissal, not evidence that the experiment succeeds.

Apply familiar official provider buttons and a clear account benefit in C8.
Preserve Hadithly's existing first-reading and quota boundaries. Reject copying
automatic account merging, free provider access or a new trial entitlement. Keep
paywall dismissal understandable and never reinterpret a dismissal as purchase
consent. No claimed signup lift should appear in Hadithly's website copy.

Frames: `frame-00115.jpg` at 01:55 is presenter-only;
`frame-00138.jpg` at 02:18 shows Apple/Google sign-in buttons;
`frame-00501.jpg` at 08:21 shows the 24-hour offer with no-card copy.
They establish the presented UI, not authentication or subscription behavior.

Transcript SHA-256: `f186b6889b6aa6b85e93a810363422ce192f2b01c9c39a9321df123d88876dd0`.

## 11. My New App Is FINALLY Live

[Source video](https://www.youtube.com/watch?v=tg6Vmi2LFb4). Full available
transcript reaches 08:15 of 08:18.

- [01:06](https://www.youtube.com/watch?v=tg6Vmi2LFb4&t=66): Beta-model spend accelerated launch. The creator reports some power users cost more than the eventual subscription. A launch story is not a cost model for Hadithly.
- [02:42](https://www.youtube.com/watch?v=tg6Vmi2LFb4&t=162): A trial timeline explains access, reminder and billing. The creator explicitly has no conversion comparison. At 04:34, the marketing site shifts from waitlist collection to explaining the available app.
- [05:59](https://www.youtube.com/watch?v=tg6Vmi2LFb4&t=359): The creator reports App Review rejection when annual billing was less prominent than its monthly equivalent, followed by another rejection over legal links. This is historical experience, not current official policy verification.

Apply concrete product screens, visible support/legal navigation and honest
availability in D. Keep C1's owner-selected monthly-equivalent-only design labeled
as a prototype; the actual annual-total release requirement stays open. Do not
promise trial reminders unless the corresponding behavior is verified. Reject
copying streaks, urgency to launch from cost pressure, or the hypothetical email
claim about 70% of users. That number was an example, not observed evidence.

Frames: `frame-00177.jpg` at 02:57 shows the trial timeline;
`frame-00379.jpg` at 06:19 shows the annual option emphasizing $8.33/month with
a smaller annual total during the rejection account. These frames do not establish
the app's current store compliance or Hadithly's purchase behavior.

Transcript SHA-256: `62e616d98b8100403ce9083042996b6661f23fdaf3379a15252dc80516fc3f24`.

## 12. We Built An App And Got 100 Users!

[Source video](https://www.youtube.com/watch?v=ghxgQaxZ9Kw). Full available
transcript reaches 08:50 of 08:52.

- [01:57](https://www.youtube.com/watch?v=ghxgQaxZ9Kw&t=117): Widgets reduce the steps to a useful action and keep current information visible. The creator calls them a retention shortcut but provides no controlled effect estimate for this app.
- [03:41](https://www.youtube.com/watch?v=ghxgQaxZ9Kw&t=221): Streaks and animated badges aim to encourage repeated use. Their fit for a calorie diary does not justify pressure mechanics in Hadithly.
- [06:06](https://www.youtube.com/watch?v=ghxgQaxZ9Kw&t=366): Lost accepted edits and stale totals undermined trust. At 07:44, missing metric/imperial options exposed assumptions about international users. These are concrete failures rather than a need for more cosmetic features.

Apply a save, leave, reopen check while refining C, and preserve the actual
reading target when a widget opens the app. Keep explicit translation/language
choices and verify real runtime copy. Existing W1/W2 device gates remain open.
Reject streaks, badges, attention-maximizing widget claims and category retention
benchmarks. This research does not authorize a new A2 storage sweep.

Frames: `frame-00185.jpg` at 03:05 shows the home-screen widget;
`frame-00397.jpg` at 06:37 shows a proposed edit with Discard/Edit/Accept actions.
The second frame shows an approval UI, not persistence after closing the app.

Transcript SHA-256: `02d8bc3b8154f0e9030fda07e0dd67072bb743c7d15020cdcc91a11222351816`.
