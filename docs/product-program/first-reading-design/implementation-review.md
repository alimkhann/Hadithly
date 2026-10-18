# A1 final bounded source and trail review

Requested reviewer model: gpt-6-sol (parent invocation metadata). Read-only review of the current A1 diff and decision records; this is not approval of the full product objective.

## Finding

**P1 — The known bad Kazakh text can still become the first reading through Daily.** `docs/product-program/first-reading-exclusions.json:5` records that `sunnah_now:bukhari:18` reverses prohibitions. The exclusion is applied only while choosing prepared slots (`scripts/prepare-first-reading.py:20,40-41`). `firstReading:get` first reads the persisted Daily selection and tries every exact-locale live default through `automaticSource` (`backend/convex/firstReading.ts:93-109`); it never consults this exclusion. If Bukhari 18 is selected for a future local day/timezone, its current live Kazakh row can be returned with `origin: daily` before the safer Muslim 258 slot is tried. Rights and generation identity do not establish semantic correctness. Keep the ordinary-reader repair in A3, but make A1's known-content exclusion effective for its Daily branch or suppress that unsafe translation at its authoritative publication boundary, and test this exact case. Do not call Kazakh first-reading quality safe until that path is closed.

## Evidence and limits

- The earlier provider-target and origin-label findings are addressed: the resolver rejects unsupported provider/collection/number/identity (`backend/convex/firstReading.ts:21-24`), and both clients display Daily versus starter labels (`ios/Hadithly/Features/Onboarding/OnboardingFlowView.swift:324-330`; `android/app/src/main/kotlin/com/hadithly/app/features/onboarding/OnboardingScreens.kt:249-255`). Revoked publication, expiry, budget overflow, and controlled native stream cases now have focused tests (`backend/convex/firstReading.test.ts:201-229`; `docs/FIRST_READING_VERIFICATION.md:73-86`).
- The approved development-only operation stays scoped: `scripts/prepare-first-reading.py:12-18,23-28,45-56` pins the development deployment and writes at most three existing references per locale through `prepareSlot`; the public query contains no provider/model call or quota mutation. The review found no new source, credential, or paid-cost operation in this path.
- The trail does **not** mark A1 complete. `docs/PRODUCT_PROGRAM.md:78-90`, `docs/FIRST_READING_VERIFICATION.md:98-113`, and `docs/product-program/decisions.tsv:7-9` retain eleven absent locales, automatic slot maintenance, ordinary-reader quality repair, production/device and later program work. The readiness JSON supports four exact-locale public outcomes, not native-speaker approval or fifteen-locale readiness. Final reading-first native reruns are stated as underway (`docs/FIRST_READING_VERIFICATION.md:91-96`); their result must be recorded before claiming that final visual gate.

**Attention:** A1 content quality remains open because of the Daily bypass above and the eleven unavailable locales. A3 still owns repair of the underlying live Kazakh translation and generation quality. Deployment approval covered development and existing references only; no broader content, permission, provider, paid, or production action follows from it.

## Addendum after the exact-text block

The P1 Daily bypass above is **resolved in the revised local source**. `resolve` checks `firstReadingBlockedTexts` by exact locale, canonical ID and SHA-256 before returning any translation (`backend/convex/firstReading.ts:38-45`), and both Daily and prepared slots call that resolver (`:104-121`). `blockTranslation` verifies the caller's expected hash against the current row and inserts idempotently without editing translations or permission records (`:141-153`). The preparation script hashes existing text, records all four reviewed Kazakh incidents, then fills at most three slots (`scripts/prepare-first-reading.py:39-67`). The regression makes bad text both Daily and slot 0, proves safe slot 1 and `daily.hasExactText=false`, checks the row is untouched, and rejects an old hash after the text changes (`backend/convex/firstReading.test.ts:232-251`). I found no remaining blocking code defect in this bounded fix.

**Remaining evidence boundary:** the 364-test backend/typecheck result and approved development redeploy are recorded, but the refreshed live public readback after the four block writes was still underway at this review; local tests alone cannot prove those development records were installed. The final native reading-first tests are reported as iOS 3 decoder plus 8 distinct UI cases and Android 3 decoder plus 12 UI cases, each covering four live locales (`docs/FIRST_READING_VERIFICATION.md:69-109`); capture export was still underway and is not a visual acceptance claim yet. Eleven locales, automatic slot maintenance, native-speaker quality approval, and the ordinary-reader Kazakh incident stay open (`:111-123`). The current docs and decision trail preserve those limits; the original P1 finding should be read with this resolution, not as an open blocker.

## Parent execution readback after review

The final operation completed after the review addendum. Public HTTPS readback
still returns exact text for en/ar/ru/kk and unavailable for the other eleven
locales. A separate read-only development query verified all four exact hashes
in `firstReadingBlockedTexts` against the committed incident manifest. Eight real
Android screenshots were exported and the Russian reading-first capture was
visually inspected alongside iOS. These readbacks do not broaden the reviewer's
source review into native-speaker or all-locale acceptance.
