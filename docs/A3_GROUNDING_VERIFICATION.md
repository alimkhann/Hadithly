# A3 translation trust repair

October 25, 2026. First bounded A3 repair after the A2 normal-use wrap-up.
A2 live development delivery and the full A3 grounding gate remain open.

## What the code actually does

`backend/convex/actions/ai.ts` sends provider Arabic, optional English, narrator and
reference text to one structured-output generation path. It configures no search
or external retrieval tool. Free and Pro use this same path; their allowance and
budget pools differ. `quotas.finish` records `groundingUsed: false` and empty
citations. The derived original-reference URL does not prove the model visited it.
Older cached translations may retain citations from earlier generation paths.

The earlier Q1 prompt explicitly removed ordinary web grounding to bound cost.
The owner's A3 request asks for stronger grounding, but no new paid retrieval,
provider call or reuse permission is authorized by this local repair. Filling a
source list with unrelated links would not satisfy that request.

## Repairs

Android previously claimed every AI translation was grounded in cited sources,
even for an empty citation list. It now uses the existing iOS disclosure, shows
when no external sources were cited, and provides tappable HTTPS reference and
citation rows. Invalid/non-HTTPS links are disabled. The combined hadith-header
source sheet remains the entry point; a redundant English-only inner heading is
removed. iOS already has the disclosure and working
source buttons; its rendered source-sheet and publication-invalidation checks are
no-change parity verification.

The two reused copy entries are resource-backed across English, Arabic, Russian,
Kazakh, Kyrgyz, Uzbek, Turkish, Indonesian, Urdu, French, Spanish Latin America,
Brazilian Portuguese, Swahili, Hindi and Bengali. Their existing `needs_review`
status remains. They are drafts, not native-copy approval. Regenerate/check Android
without modifying the incoming iOS catalog with:

```sh
python3 scripts/generate-ui-polish-copy.py --android-only --check
```

The known Kazakh Bukhari 18 meaning reversal was excluded from first reading but
still returned by ordinary public reads. The shared availability check now rejects
an exact recorded `meaning_reversal` by canonical hadith, locale and content hash.
This covers reader defaults, cached-generation lookups, notification candidates
and publication invalidation on both apps. It preserves the underlying row and
allows a changed text version. `unsuitable_standalone` exclusions still apply only
to first reading.

A new generation could otherwise return that exact bad text again. Completion now
checks the same incident before changing defaults, inserting a translation or
creating a success/allowance charge. It records provider cost as a failed attempt
and releases the allowance reservation. This rejects known exact text only; it
cannot establish that an unseen paraphrase is semantically sound.

## Verification

- The ordinary-reader regression failed before the shared read check, returning
  the blocked text. Evidence: `/tmp/hadithly-a3-incident-red.log`.
- Both free and Pro completion regressions failed before the output check because
  the same blocked text was published. Evidence: `/tmp/hadithly-a3-output-red.log`.
- Android native regressions failed on missing no-citation disclosure and inert
  citation rows. Evidence: `/tmp/hadithly-a3-source-ui-red.log`.
- The focused final backend group passes 54 tests, including both paid/free
  allowance preservation cases. Evidence: `/tmp/hadithly-a3-output-focused.log`.
- Final backend strict typecheck and 528 tests in 43 files pass. Evidence:
  `/tmp/hadithly-a3-final-typecheck.log`, `/tmp/hadithly-a3-final-backend.log`.
- Android's two native source cases pass, including the actual URI-handler action.
  Evidence: `/tmp/hadithly-a3-source-ui-final.log`.
  The rendered component capture is `/tmp/hadithly-a3-reader-sources.png`.
  A separate direct instrumentation run uses the same verification runner because
  Gradle's completed run removes the installed test app and its cached screenshot.
- iOS's combined source-sheet UI and publication-invalidation cases both pass.
  Evidence: `/tmp/hadithly-a3-source-ios.log` and `.xcresult`. The exported actual
  Paper source-sheet capture is
  `/tmp/hadithly-a3-ios-captures/2FC8176D-7653-4F9C-AFD3-FB83FACA805C.png`.
- Android copy generation check and scoped whitespace checks pass.

The first Android follow-up used an English literal while the native host selected
localized resources. The final assertion resolves the selected resource and still
requires the no-citation state and absence of the old grounding claim. The test
also taps the reference through the actual native URI handler boundary using a
controlled handler, without opening a browser or making network requests.

## Still open

Ordinary generation still performs no external retrieval. Next, select a small set
of exact-hadith comparison references whose recorded permissions allow model
processing and display. Bind actual retrieved references to canonical identity,
source revision and exact translation language; keep paid and free quality equal
and retain single-flight/cache reuse and bounded cost. Verify relevance and failed
retrieval rather than requiring an arbitrary number of citations. Current model
confidence is self-reported and is not independent semantic review.

Known source-link derivation is best-effort and still needs an identity audit.
The live bad-text record is not modified or suppressed until this code is deployed.
No deployment, private account write, source-policy change, paid generation or
production operation was performed. A2's pending deployment approval is separate;
these A3 changes have no live rollout evidence. Native copy, physical-device,
content rights and release gates stay open.
Previously downloaded translation text and old installed-client invalidation still
need their own readback. No offline artifact was rebuilt or claimed repaired.
