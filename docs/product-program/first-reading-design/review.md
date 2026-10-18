# First-reading architecture cross-judge

Requested reviewer model: gpt-5.6-sol (invocation metadata supplied by parent)
Mode: read-only architecture and decision-trail audit

## Verdict

Pick Candidate B as the base. Its cache-only public query is the only candidate that already makes the onboarding boundary provider-free, write-free, identity-free, and bounded. Graft Candidate A's `DailySummary` into B so the client can state precisely whether today's canonical item lacks the selected translation, without presenting the starter as Daily.

Neither design completes A1 by itself. A1 passes only after real, currently authorized Arabic plus exact-locale text is provisioned and read back on both native apps for all 15 locales. An `unavailable` screen is correct failure behavior, but it is not first-reading success.

## Scores

| Criterion | A | B | Judgment |
| --- | ---: | ---: | --- |
| Exact-locale first value and empty-locale honesty | 4 | 5 | Both fail closed and reject silent English fallback. B states the all-15-locale provisioning gate and full-text requirement more directly. |
| Canonical Daily stability | 4 | 5 | Both preserve existing Daily identity. B only reads an already persisted selection; A calls `pickDailyHadith`, which may create a selection and fetch Sunnah.now. |
| Current rights/provenance and quota/guest safety | 4 | 4 | Both avoid guest generation. B spots that `publicTranslationAvailable` accepts some live non-community rows without publication evidence, but its extra translation-rights requirement is not present in the current schema and must not be invented inside A1. |
| Bounded data access and complexity | 3 | 5 | A proposes a 16-row candidate window plus sync lifecycle and still needs a separate cache-only Daily refactor. B fixes access at one Daily target plus three slots and calls out the unbounded `.collect()` and recursive validator paths. |
| Native caller simplicity and reproducible tests | 4 | 5 | Both expose a tagged result. B separates content absence from transport failure, covers locale races, and ties success metrics to rendered exact-locale text. |

Totals: A 19/25. B 24/25.

## Source challenges

- `actions/daily.ts` proves A cannot safely reuse `pickDailyHadith`: on an empty cache it calls `fetchVolumeHadiths`, writes hadiths, and persists a Daily selection. A recognizes this but leaves the critical separation as an implementation option. B resolves it in the public contract.
- `dailySelections.ts` indexes by local date and timezone and keeps the first eligible choice. B's lookup-only behavior cannot change canonical identity. It may return a starter before any Daily selection exists, which is acceptable if the response and UI do not imply that a Daily item was selected.
- `translations.ts:availableDefault` uses `.collect()` over defaults. `publicTranslationAvailable` recursively reads permission, scan, source-policy, ancestry, abuse, and deletion rows. B is right that an indexed slot alone does not make authorization work bounded.
- `publicTranslationAvailable` returns true for a live non-community row without `evidencePublicationId`. This means those legacy rows cannot be called rights-approved from current data alone. It does not authorize A1 to invent a new translation-rights schema; the gap needs an explicit inventory and legal/content decision.
- The current Daily English path returns provider English without checking the hadith license. Both designs must require verified display rights for Arabic and provider English before returning text.
- Current iOS and Android onboarding truncate translation to three lines, merge network failure with absence, and Retry the same read. B explicitly removes all three defects.

## Grafts into B

1. Add A's `DailySummary` to both `ready` and `unavailable`: canonical identity plus exact-locale availability only. Do not include unlicensed Arabic text in the summary.
2. Keep A's explicit `today | starter` naming and the rule that Today, widgets, push, and deep links remain on `getDailyHadith`.
3. Keep A's read-time revalidation rule and idempotent lifecycle cleanup. Slot rows accelerate lookup; they never authorize text.
4. Keep A's test that the displayed starter target opens that exact canonical hadith on both apps.

## False assumptions and excess state

- B says publication expiry clears rendered text, but its sample uses a one-shot repository query. `validUntil` needs a client timer/requery, or the repository must expose a reactive subscription. Test the actual mechanism.
- B's `sourceDigest` in each slot duplicates authoritative hadith/translation state. Store it only if it is part of a deliberate compare-and-reject contract; otherwise remove it and validate the current referenced rows.
- B's `timezone` is needed only to find today's persisted selection. Keep it out of starter selection and ranking.
- `providerEnglish?: true` plus optional `translationId` permits ambiguous slot states. Use a tagged slot source, `provider_english | translation`, with the required identifier for each case.
- A's `firstReadingCandidates` with a 16-row window, publication hooks, and maintenance queue is more state and machinery than A1 needs. Three explicit ranked slots per locale are easier to audit and provision.
- Neither candidate proves that existing source labels and public provenance are safe to expose. Return a narrow public attribution object and test that private evidence and storage URLs cannot escape.

## Acceptance gaps before implementation can pass

- Enumerate and verify exact tags for `en`, `ar`, `ru`, `kk`, `ky`, `uz`, `tr`, `id`, `ur`, `fr`, `es-419`, `pt-BR`, `sw`, `hi`, and `bn` from one shared backend contract. Current lists are duplicated across clients.
- Inventory real qualifying content. Require the established verified `permitsDisplay` rule for the Arabic/provider source and current `publicTranslationAvailable` policy for the translation. Do not import offline/export redistribution into first-reading UI. Fixtures, generated drafts, and a legacy live row do not by themselves prove translation rights approval.
- Decide how `ar` works. Exact-locale first value may be the authorized Arabic original, but the response must model it intentionally rather than pretending Arabic is a translation row.
- Bound every query used by the resolver, including defaults, permission dependencies, ancestry, source policies, abuse rows, and deletion rows. Fail closed on overflow.
- Prove no provider, generation, quota, usage, or Daily write occurs from signed-out onboarding. Assert unchanged tables and mock-call counts.
- Verify all result states on both platforms: Daily exact text, starter exact text, empty locale, revoked content, expiry, malformed locale/timezone, transport failure, superseded locale response, RTL, font scaling, and exact target navigation.
- Run real signed-out native journeys for all 15 locales. Count success only after useful exact-locale text and public provenance render. Keep each missing locale gate open.

## Decision-trail audit

The actual `docs/product-program/decisions.tsv` has only the frame and baseline rows. It does not yet record the arena candidates, scores, base selection, grafts, source challenges, implementation decision, or verification outcome.

Attention flags for the actual trail:

- `ATTENTION_CONTENT`: no evidence yet identifies rights-cleared first-reading text for all 15 locales.
- `ATTENTION_RIGHTS`: current live/default status does not prove translation rights approval. The first-reading UI uses the existing display contract; offline/export redistribution remains a separate gate.
- `ATTENTION_BOUND`: existing translation/publication helpers contain unbounded collections and recursive fanout.
- `ATTENTION_RUNTIME`: no native implementation or real signed-out readback exists yet.
- `ATTENTION_TRAIL`: record the requested reviewer model and Attention markers inside the canonical TSV's existing decision, evidence, or result fields and in this companion review. Keep the six-column schema unchanged. Do not retrofit imagined actions or claim this temporary judge report as implementation evidence.

Recommended trail decision: base B, graft A's Daily summary and exact-target checks, then implement only after the red contract tests expose the current provider fetch, rights hole, empty-locale result, and unbounded reads.

## Source-grounded addendum after development inventory

Fresh read-only inventory supplied by the parent found 46 translations, with live defaults only in `kk`, `ru`, `tr`, and `uz`. It found one base license record with verified `permitsDisplay: true` and `permitsRedistribution: false`. The hadith inventory stopped at 10,000, so joins and locale coverage remain incomplete. These counts show that some display-authorized base content and some live translations exist; they do not prove a qualifying exact-locale first reading for every supported locale or prove rights approval for legacy live rows.

The established native/web text boundary checks the hadith license's `permitsDisplay`. Offline artifact generation separately checks redistribution and offline-distribution terms. My earlier blanket Arabic-plus-translation redistribution requirement overreached and is corrected above. Evidence-published community rows may still carry stronger permission dependencies through `currentPublicationPermissions`, but that policy must not be generalized to every first-reading source.

B should reuse the current hadith display check and `publicTranslationAvailable` instead of adding an A1-only authorization system. If the inventory cannot establish what permits use of legacy official or Gemini rows, keep those rows out of readiness evidence and record the unresolved content/legal gap. Resolve that gap through the product's content policy rather than a speculative schema in this implementation.

B's explicit global authorization budgets also exceed the evidence available for A1. Keep the fixed three-slot lookup and bound new resolver queries. Reuse the current publication helper as-is unless measurements or tests show its existing recursive and collection reads violate the required operational bound; any shared helper redesign should be separately scoped and must preserve E3/E4 behavior.
