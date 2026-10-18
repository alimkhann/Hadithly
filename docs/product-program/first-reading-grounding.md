# First-reading boundary, current trace

October 17 baseline, before implementation.

- iOS `OnboardingTranslationView.loadDailyHadith` calls
  `actions/daily:getDailyHadith` with timezone and selected translation locale.
- Android `TranslationDemonstration` calls the repository's `getDailyHadith(locale)`.
- `backend/convex/actions/daily.ts:getDailyHadith` persists or reuses one eligible
  hadith for local date and IANA timezone, then resolves that hadith's translation.
- English uses the provider's existing English text. Other languages read the
  exact-locale live default. Missing cache returns null. The public read never
  generates a translation, preserving guest safety and admission quotas.
- Both onboarding views currently render the hadith's Arabic and show Retry when
  translation is missing. Retry makes the same read. The continue action is not
  conditioned on actually reading a translation in the chosen language.
- Existing Daily tests cover eligibility, stable selection, signed-out reading,
  and cached-only behavior. Daily identity must not become language-dependent.

Design task: choose the smallest complete boundary that guarantees a useful
first-reading path using real authorized content, without disguising another
hadith as today's canonical selection or secretly generating on a public read.
Consider an explicit starter-reading response versus a prepared canonical Daily
content policy. Also address the truly empty locale case rather than silently
falling back to English or calling a missing translation success.

Rubric: exact-locale useful text; canonical Daily stability; licensing/provenance
and quota safety; bounded data access; both-native integration and honest missing
state; deterministic reproducible verification.
