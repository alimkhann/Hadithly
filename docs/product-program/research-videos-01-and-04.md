# Video research: product clarity and reading reliability

Reviewed October 27, 2026. Full available English automatic captions were read.
Frames below were extracted and inspected directly. Captions can misrecognize
names and numbers. The videos are creator accounts, not independently audited
experiments. Raw captions and frames are local evidence outside the checkout at
`/Users/alim/Documents/Codex/2026-10-27/hadithly-product-research/<video-id>/`. No Pi session or model API was used.

## 1. I Built A New App In 1 Week

[Chris Raroque, 16:49](https://www.youtube.com/watch?v=TsYgtI-b6n8).

- At 02:21–03:44 the creator tests whether one short demo communicates the
  product without explanation. At 06:04–07:04 a viewer still misunderstands its
  central capability. Apply to D: show actual reading in a chosen language,
  provenance and saving in the opening example. Test comprehension without
  coaching. A feature inventory alone cannot establish that understanding.
- At 10:20–11:23 the creator simplifies the demonstration and reports many more
  waitlist sign-ups. At 11:25–13:42 he also changes the product's interaction
  model. This is a bundled, sequential change with audience and exposure
  differences, not a controlled estimate of a design's effect.
- At 14:11–15:17 the landing page shifts toward visible outcomes and objections.
  He explicitly says no other users have used the product yet. Apply the
  demonstration principle. Reject treating sign-ups as activation, retention,
  paid conversion or evidence for a Hadithly uplift.

Visual evidence: 05:10 shows the original chat-led editor; 10:00 shows the
more complicated working view; 10:50 shows the simplified grid of work. 13:00
shows a single edit field. 14:50 shows the outcome-focused marketing analogy.
Additional sampled frames: 00:10, 03:00, 04:20, 06:00 and 16:00. The frames support
the interface description, not the reported sign-up totals or causality.

Decision: apply to C2 and D1 by making a useful reading immediately legible.
Keep AI provenance visible. Reject a spectacle that obscures text or implies
that every translation has external research. This video supplies no evidence
that Hadithly should add chat, a waitlist, or another backend.

## 4. I Built An App (But Users KEEP dropping off)

[Chris Raroque, 15:50](https://www.youtube.com/watch?v=oNRrjbKiF04).

- At 00:24–00:44 the creator retracts the prior claim that week-one retention
  rose to 20%. He says it was nearer 14% and is now about 13%. Apply to A7:
  preserve definitions, denominator, cohort maturity and corrections. Neither
  LA2's clipped counts nor this video's figures measure Hadithly retention.
- At 03:58–05:23 a successful US product lookup fails to establish international
  serving-size accuracy. At 07:26–07:56 ordinary use exposes incomplete-label
  problems missed by isolated tests. Apply to C verification: exercise real
  reading, page changes, translation availability and return in both directions
  and scripts. A successful fixture or build cannot prove that journey.
- At 10:19–10:32 the creator rejects a decorative water-bottle design that feels
  foreign to the app. At 13:27–14:06 an optional feature disappears when disabled.
  Apply restraint to C2–C4. Preserve a quiet reading surface and interruptible
  motion. Do not copy the water animation or grow the native feature set.
- At 14:14–15:17 he prioritizes accuracy and accumulated small annoyances and
  explicitly says the retention effect is not known yet. Apply to normal-use
  regressions in C. Reject a claim that these changes have proved retention lift.

Visual evidence: 00:20 shows the creator's retention table; 06:20 shows the
portion selector; 10:20 shows the decorative water experiment; 13:10 shows its
more restrained footer. A frame at 14:45 samples the discussion of the scroll
defect but does not reproduce that defect. Frames do not verify the metrics.

Decision: preserve the existing accuracy, source and sync gates. For C, reduce
friction in the ordinary journey and check the actual UI. No new storage project,
AI provider, tracking, nutrition feature or retention promise follows from this.

## Evidence fingerprints

| Video | Caption events | SHA-256 of full local transcript |
| --- | ---: | --- |
| TsYgtI-b6n8 | 576 | 227537f7a9093050f9b3156f5448d3f3ca46580b59698d216468b52b52b73a62 |
| oNRrjbKiF04 | 516 | f81febe4ec68bb70e646b8fb4b7ee6a6e11501f5fc16f5d79e16beefb0329315 |

## Reproduce and inspect evidence

Use `scripts/collect-product-research.py --output <outside-checkout-directory>
--ids <video-id>` to retrieve public captions. Use `--frames <seconds...>` with
one ID to extract selected frames. Collection never means reviewed. The script
does not invoke Pi's saved non-GPT provider or the extension's Gemini fallback.
Signed stream URLs and full caption files must stay out of git.
