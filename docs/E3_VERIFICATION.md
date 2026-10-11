# E3 verification

Updated 2026-10-11. E3 passed in development. Stop before E4.
E2's development gate was confirmed from `E2_VERIFICATION.md` and rerun against
the updated Linux worker. E1's outstanding device matrix remains open.

## Gate evidence

| Check | Actual result |
| --- | --- |
| Backend contracts | Typecheck and 232 tests across 21 files passed. |
| Publication predicate | Licensed, consistent fixtures publish. Unknown/denied licenses, changed permission scope, injection corpus, unsupported claims, contradictory comparisons, abuse, missing provenance/support, same-model/pass identities, stale snapshots, and threshold boundaries stay private. Both raw confidence values must be strictly greater than 0.95; exactly 0.95 does not publish. |
| Permission convergence | Exact private-file grants and cached source-policy updates requeue rights-only holds automatically. Indexed pagination, source-language separation, production/legacy collection aliases, and revoked comparison permissions have regression coverage. |
| Publication atomicity/privacy | Snapshot rebuilt at commit, checksummed exact evidence and model quotes, idempotent revision/default writes, late result rejection, contributor/account deletion, and default ancestry restoration passed. Public community rows omit confidence and private identities. |
| Model isolation | Two fresh distinct model calls with separate fixed instructions. Evidence, labels, citations, and proposal remain inside `untrustedData`; no tools, user identity metadata, credentials, model network access, or shared conversation. Strict bounded output parsing fails closed. |
| Paid Gemini | Owner confirmed billing; AI Studio showed Hadithly Tier 1 Prepay. Existing valid key was installed in development only after authorization. Production was unchanged; no key was created or revoked. |
| Real review pair | `gemini-3.8-flash` and `gemini-3.5-flash-lite` returned four independent complete passes for two self-authored synthetic passages. Both passages auto-published. Confidence values were 1; these are private model reports, not a calibrated quality guarantee or product score. |
| Signed-in iOS | Real PNG upload, private OCR, automatic rights recheck, independent reviews, approved owner status/citations, and public default readback passed without skips in `/tmp/hadithly-e3-native-live7.xcresult`. |
| Signed-in Android | Same complete path passed, `OK (1 test)` in `/tmp/hadithly-e3-android-native-live6.log`, AVD `hadithly`, `emulator-5554`. |
| Native reader/status UI | iOS production stored-translation view/source control and private statuses passed, two UI tests in `/tmp/hadithly-e3-reader-final-ui.xcresult`. Android's actual English `TranslationSection`, community source navigation, private states, and 48 dp control assertion passed, four tests in `/tmp/hadithly-e3-reader-final-android-ui.log`. These UI checks use deterministic synthetic fixtures. |
| Native builds | iOS test builds and Android unit/build/instrumentation compilation passed. Final iOS unit regression is recorded below. |
| Linux worker | All 14 actual scanner/OCR/SSRF/sandbox/access-policy tests passed at 1 CPU and 1 GiB. |
| Private cloud | Unauthenticated 403, authenticated health/version, real image/PDF OCR, EICAR, malformed PDF, metadata/loopback rejection, default-denied Sunnah.com, cached avoid-policy rejection, exact HTTPS snapshot and redirect chain passed in `/tmp/hadithly-e3-private-cloud-final.log`. |
| Offline licensing boundary | Version 1 translation packs lack per-entry rights/attribution/citations. New export and existing pack manifests are blocked; base manifests remain available and advertise no compatible packs. A seeded existing-artifact regression passed. |
| Adversarial review | GPT-5.6 Sol max and GPT-6.1 Sol high independently reviewed the implementation. All accepted findings were repaired and both final reviews reported no findings. See `E3_REVIEW.md`. |
| Cleanup | Controller `/tmp/hadithly-e3-native-controller8.log` proves existing user/evidence/translation IDs preserved after both synthetic fixtures were removed. Final development readback has no fixture submissions, passes, or live rows. Temporary Clerk key/ticket/account metadata and worker invocation copies were deleted. |

## Cloud readback

- Project/service: `hadithlyapp` / `hadithly-evidence-processor-dev`, `europe-west1`.
- Canonical origin: `https://hadithly-evidence-processor-dev-d5r7bxbvdq-ew.a.run.app`.
- Ready revision: `hadithly-evidence-processor-dev-00002-7r5`, serving 100%.
- Image: `sha256:2b748ae11e9460ba5890127cff698ddb82056a2c5ec5ce789116a3a275bea08e`.
- Successful build: `ee1262fb-fa6f-4bc3-8617-ef729c8b4d63`.
- Gen2, 1 CPU, 1 GiB, concurrency 1, maximum one instance, minimum zero,
  110-second timeout. Dedicated worker identity retained.
- Service IAM permits only the existing dedicated invoker. No public binding,
  new identity, role expansion, billing change, or production deployment occurred.

The old revision failed a cold scanner startup with an out-of-memory event.
The freshly built revision passed its real startup controls, resource-limited
Linux suite, private requests, and both native pipelines. Future startup or stale
signature failures remain fail-closed; do not infer health from image build alone.

## Provider policy observations

These are recorded observations, not invented reuse grants.

- [Sunnah.now documentation](https://docs.sunnah.now/) identifies an MIT project
  and local use. The owner's access permission is acknowledged separately.
  E3 does not infer broad translation adaptation/redistribution rights for every
  dataset or third-party translation from project licensing alone.
- [Sunnah.com policy](https://sunnah.com/about) restricts scraping and mass
  reproduction; individual teaching examples have a narrower allowance.
  [API access](https://sunnah.com/developers) is not a blanket content-reuse grant.
  E3 accesses its sources only under explicit scoped permission.
- [Gemini terms](https://ai.google.dev/gemini-api/terms) distinguish paid-service
  data treatment from unpaid use. E3 requires the paid-confirmation setting and
  submits only permitted private evidence to the isolated review requests.
- [CC BY-SA legal code](https://creativecommons.org/licenses/by-sa/4.0/legalcode.en)
  treats translations as adaptations and has conditions beyond attribution.
  Conditional/share-alike grants remain blocked until their conditions can be met.

Source policy is cached by origin/kind on first encounter. Unknown rights stay
private; later affirmative policy changes trigger automatic rechecks. Source
permission and exact content provenance remain separate checks. Synonym changes
or a citation alone do not establish a reuse grant.

## Scope and remaining gates

E3 is a development gate, not a production launch claim. Production source-rights
coverage remains with O1/D4. A versioned translation-pack format remains with O2.
E4 reports/appeals, revocation, retention refinements, and optional operator tools
were not implemented. The app-wide plan now prioritizes automation rather than a
required human review queue. `OPEN_GATES.md` lists earlier unresolved device,
sync, store, sandbox, push, widget, and release gates.

## Final iOS unit regression

219 tests passed with zero failures in `/tmp/hadithly-e3-final-unit.xcresult`.
The two opt-in live suites were excluded from this regression run and proved
separately above without skipped tests.
