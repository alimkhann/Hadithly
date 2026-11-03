# Gemini grounding economics and product recommendation

Checked November 3, 2026. Research only. No model, billing, entitlement, cache,
source permission or publication policy changed.

## Current behavior and the reproduced failure

Hadithly pins `gemini-2.5-flash-lite`. The request in `actions/ai.ts` supplies the
Arabic original, available English source text and authorized database comparison
texts. It does not enable Google's Search tool. An empty comparison list is
permitted. Existing local tests publish ungrounded output with no citations when
no authorized comparison is available or used. The original text is still the
translation source; missing comparison citations do not mean there is no source.

The physical Bukhari 7 retry failed before model generation with
`AI_SOURCE_UNAVAILABLE`. Its cached source license is unverified. This is distinct
from a model returning invalid output or claiming an unavailable comparison ID.
No-grounding fallback alone does not fix that request. See
[SENTRY_REPAIR_VERIFICATION.md](SENTRY_REPAIR_VERIFICATION.md).

## What Google's documentation supports

[Google Search grounding](https://ai.google.dev/gemini-api/docs/google-search)
lists Gemini 2.5 Flash-Lite as supported. The JavaScript Generate Content SDK
enables it with `config.tools: [{ googleSearch: {} }]`; returned
`candidates[0].groundingMetadata` provides search queries, source chunks and
support metadata. Citations must reflect actual returned support, not links
invented in the response. Enabling Search alone does not prove that a relevant
source was found or that a religious translation is accurate.

[Structured output with tools](https://ai.google.dev/gemini-api/docs/structured-output#tools)
is documented for Gemini 3 series models, not 2.5. Hadithly currently requires a
JSON response schema. Therefore adding Search to the current request is not a
verified compatible change. A search/retrieval step followed by the existing
structured translation step is one candidate; a newer model is another. Both
need separate compatibility, cost and source-permission verification.

## Cost of the pinned model

[Official standard pricing](https://ai.google.dev/gemini-api/docs/pricing#gemini-2.5-flash-lite)
lists $0.10 per million text input tokens and $0.40 per million output tokens.
The paid API tier includes 1,500 grounded prompts per day, shared with Flash,
then $35 per 1,000 grounded prompts. The free API tier lists 500 per day shared
with Flash, subject to its limits. These are provider plan tiers, not Hadithly's
Free and Pro subscriptions. The actual project plan and allowance consumption
were not audited in this research.

Example estimate for 1,000 input and 500 output tokens per new translation:

| Scenario | Per translation | Per 1,000 translations |
| --- | ---: | ---: |
| Translation tokens only | $0.00030 | $0.30 |
| Search beyond the included allowance, plus the same tokens | $0.03530 | $35.30 |

This is roughly 118 times the token-only cost once Search becomes billable.
Within the included allowance the Search fee is zero. Retrieval tokens, a second
generation call and operational overhead are excluded from this example. Cache
hits need no model or Search call. Hadithly's existing spend reservation counts
model tokens, not a new Search charge, so it must include that charge before
Search is enabled.

## Recommendation

Fix source availability and accurate failure feedback before changing tiers.
Allow translation from authorized original text when no extra comparison is
available. Show the existing AI label and claim supporting sources only when
relevant sources were actually used.

Prefer one shared cache for each exact hadith, locale and source version. Making
Free drafts private would repeat model work for the same text, add private-data
lifecycle work and complicate replacement. A Pro-triggered, budgeted search or
verification upgrade can later improve the shared result for everyone. Payment
does not establish correctness: promotion must still satisfy provenance,
permissions, exact-narration and quality checks. Never replace an accepted result
merely because a paying account requested the replacement.

If Free drafts later remain private, an upgrade must replace only the app's
provisional generated result, preserve user notes and saved-target identity, and
keep provenance/version history. That is a separate cache and publication
contract, not a small switch. Defer it until current reliability is repaired and
measured cache-miss volume justifies Search costs. Prefer trusted reusable
references over a web search on every reader request.
