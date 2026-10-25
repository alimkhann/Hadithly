# First reading, development verification

October 18, 2026. A1 engineering unit. The full A1 content and maintenance gate
remains open, as does the wider program in `PRODUCT_PROGRAM.md`.

## Behavior and authorization

Onboarding subscribes to `firstReading:get`. It reads the existing canonical Daily
selection without changing it, then tries up to three prepared references for the
exact supported locale. It never calls a provider/model, reserves quota, or uses
authentication to unlock reading. An Arabic original is explicitly original text.
A starter is visibly distinguished from Today's hadith. The selected-language text
comes first; a translated reading keeps the Arabic original in a disclosure.
The reference opens the same supported Sunnah.now collection and hadith number
in the native reader. Unknown providers, unsupported collections, malformed numbers,
and inconsistent canonical identities are rejected.

The public query rechecks verified display permission, current generation identity,
default/publication state, exact official-translation permission bindings, evidence
dependencies and expiry. A prepared reference grants no rights. Original display
permission does not require an invented offline-redistribution grant. Published
evidence keeps its existing stronger publication permission requirements.
Read work is bounded by four Daily defaults, three slots, and a shared 128-read
publication budget. Changed text or attribution invalidates the prepared digest.

Both clients clear withdrawn or expired readings, cancel the previous language's
subscription, and reject a mismatched-language result. Missing content offers
language choice and guest continuation. Retry is for transport failure only.
The reading-rendered analytics event fires after text rendering, not on an empty
or failed response. Android now uses the saved translation locale independently
of the interface locale, matching iOS.

The owner explicitly approved deployment to development and preparation of up to
three references per available locale from existing authorized text. The backend
was deployed using `npx convex dev --once` to `festive-cobra-664`; the deployment
completed at 13:36 local time. The exact-text exclusion fix was redeployed at
14:50, then four hash-bound exclusion records were read back from development. No production, license-permission, paid generation,
or provider-content change was made. Local codegen alone was separately verified
not to have deployed the function before that approval.

## Development content readback

`scripts/prepare-first-reading.py --apply` writes references only through the
internal authorized resolver, then reads the public HTTPS query without an
Authorization header for all fifteen supported locales. It is restricted to the
named development deployment. Default mode is read-only. The sanitized result is
`product-program/first-reading-dev-readiness.json`.

| Locale | Current public outcome | Prepared references |
| --- | --- | --- |
| English | Daily, existing provider English | 3 |
| Arabic | Daily, Arabic original | 3 |
| Russian | Daily, existing labeled AI text | 3 |
| Kazakh | Distinct starter, existing labeled AI text | 3 |
| Kyrgyz, Uzbek, Turkish, Indonesian, Urdu, French, Spanish Latin America, Brazilian Portuguese, Swahili, Hindi, Bengali | Unavailable | 0 |

These are authorization and runtime outcomes, not translation-quality approval.
Older Uzbek and Turkish rows do not have a current generation identity and were
not silently promoted. The bounded English/Arabic candidate scan was truncated;
this is not an exhaustive content inventory.

Actual readback exposed a meaning reversal in existing Kazakh Bukhari 18 and other
unsuitable starter text. `product-program/first-reading-exclusions.json` keeps
these out of first reading, including its Daily branch. Its replacement starter is
Muslim 258. **The older translations remain live in the ordinary reader.** The
exact-text block is checked inside the shared resolver for Daily and prepared
references. It does not suppress ordinary-reader rows or establish semantic
quality for new text versions. A3 must address those records and the generation/review path.
The original source URL is not evidence that the AI performed retrieval.

October 25 local A3 repair: the shared public availability check now rejects exact
`meaning_reversal` incidents outside first reading too. Generation completion
rejects that same known text without publishing it or consuming reader allowance.
`unsuitable_standalone` remains a first-reading-only exclusion. This code is not
deployed; the earlier live-state statement above remains true until rollout.
See `A3_GROUNDING_VERIFICATION.md`.

## Verification evidence

- Backend typecheck passes. Full backend suite: 364 tests in 32 files pass in
  `/tmp/hadithly-first-reading-block-backend.log`.
- Sixteen focused tests exercise the actual public resolver and the shared
  publication validator, including source identity, official text-bound grants,
  changed text, revoked grants/publications, permission deadline, unsupported
  native targets, oversized dependency denial, and an exact-text incident block covering both
  Daily and prepared references without changing the original translation row. Fixtures are synthetic test
  data and never deployed as app content.
- `scripts/sync-first-reading-fixtures.py` regenerates and compares five actual
  local-query outcomes against both clients' decoder fixtures.
- Nine scoped UI strings across all fifteen locales are synchronized by
  `scripts/generate-ui-polish-copy.py --source docs/first-reading-copy.json --check`.
  Non-English values remain review-pending drafts. This does not start or pass L1.
- Native fixture tests exercise full unclipped translation, distinct Daily/starter
  labels, Arabic original handling/disclosure, transport recovery, missing state,
  subscription withdrawal, local deadline expiry without another server emission,
  and old-language subscription cancellation.
- Live native tests query the real development content in English, Arabic, Russian
  and Kazakh, compare the displayed text, and open the displayed collection/number
  in the actual reader. Automatic generation is disabled for those runs.

Final reading-first verification:

- iOS: three decoder tests and eight distinct UI tests pass across the reading-first
  bundle and the focused Arabic-disclosure rerun. One live UI test covers all four
  available locales and opens each actual target. The first broad run caught an
  inherited accessibility identifier in expanded Arabic; adding a containment
  boundary fixes it. Logs/results:
  `/tmp/hadithly-first-reading-reading-first-ios.xcresult`,
  `/tmp/hadithly-first-reading-arabic-disclosure-ios.xcresult`.
- Android: three decoder tests and thirteen distinct instrumented tests pass. Four are live
  locale-to-reader journeys. Final layout log:
  `/tmp/hadithly-first-reading-android-reading-first.log`. A separate live
  cached-subscription return test passes in
  `/tmp/hadithly-first-reading-android-cache-return.log`; returning through the
  language step reopens the exact cached reading.
- Live tests deliberately use English UI with the selected reading language to
  prove interface-language independence. They compare actual development text,
  not a screenshot fixture. Arabic has no duplicate translation layer.
- Rendered capture inspection caught Arabic pushing the translation below the
  first viewport. The selected-language text now appears first; original Arabic
  remains available in a native disclosure. No three-line truncation is used.

## Open gates and next work

- Eleven locales still need real authorized current text. A model call, rights
  change, or inferred license is not authorized by the reference-preparation approval.
- Automatic replenishment/repair of prepared references is not implemented yet.
  Invalid references fail closed, but a manual preparation batch is not autonomous
  content maintenance.
- Existing ordinary AI generation is ungrounded for both account tiers. Actual
  retrieval/provenance, semantic review, quality incidents and bounded-cost proof
  remain A3 work. No citation-count padding is accepted.
- Native-speaker review, physical devices, accessibility/large-type breadth,
  offline behavior, production, stores, receipts and all existing release gates
  remain open. Native lifecycle tests use controlled streams; development permission
  records were not revoked or expired to manufacture a live test.
- Saved/cross-device sync, full localization audit, research, later native design,
  website and Linear work remain in the full program. None is closed by this unit.

## Commit and independent review

Implementation: `beea614`. No push was requested or performed. Incoming Xcode
project/scheme changes and unrelated catalog extraction changes remain outside
this unit; only the nine scoped catalog entries were staged.

Requested independent reviewer: `gpt-6-sol`. The review and fix-specific addendum
are in `product-program/first-reading-design/implementation-review.md`. The
provider mismatch, missing origin label, lifecycle test gap and known-text Daily
bypass are addressed. The reviewer found no remaining blocking code defect in
the bounded incident fix. The content, maintenance, broader quality/grounding and
release gates above remain open. This is not review or completion of the full goal.
