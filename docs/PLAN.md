# Hadithly master plan

This file is the source of truth for sequencing and product decisions. Read it
before any Hadithly session. Then open the matching standalone prompt in
`docs/SESSION_PROMPTS.md`.

Last updated: 2026-09-09. Phases 0 through 5 are complete. Phase 6 code is
implemented; its production dashboard gate is open. Sessions D0, G0, M0, D1,
D2, F1, F2, F3, R1, R2, and R4 are complete. R3 passed its
simulator/emulator and unit gates; its physical-device gate is open. R4's
named Terra high review passed. D3A's operational Apple and
RevenueCat work is complete, while its legal, compliance, and iOS sandbox
handoffs remain open. D3G is
explicitly deferred by the owner until a Play Console developer account is
available. Full D3 cannot pass until both release subgates pass, but neither
D3 subgate blocks F1 or most product-work branches.
D2's social sign-in runs through Clerk hosted
auth, and the username contract is now: optional, auto-generated from the
email local part at password sign-up, editable in Settings. The Android FCM
device-push re-test deferred from D1 folds into D4's physical-device matrix.

Current next session: the still-open R3 physical-device matrix. R5 is complete;
R6 (reader chrome, density, and paging polish, owner-directed) is proposed and
waits for the owner's answers on Arabic alignment, source labeling, the menu
button, and slice order. Do not
start D4 until the D3A release handoffs and D3G pass. Keep store, sandbox, and
submission work on the release track while the feature track builds the
product.

## Read the plan in layers

- `docs/PLAN.md` holds product rules, current state, session order, contracts,
  dependencies, and gates.
- `docs/LAUNCH_DASHBOARD_CHECKLIST.md` holds external dashboard work and live
  evidence.
- `docs/REFERENCE_AUDIT.md` holds the Sajda screenshot inventory, current code
  audit, and adopt, adapt, or reject decisions.
- `docs/SESSION_PROMPTS.md` holds one standalone execution prompt per session.
- `docs/REPOSITORY_AND_DISK_PLAYBOOK.md` holds the current branch, checkpoint,
  toolchain, and low-space recovery procedure.
- `docs/LAUNCH_STACK_RESEARCH.md` holds cost and launch-service evidence.
- `docs/app-store/` holds store metadata and the privacy worksheet.

## Product contract

Hadithly is a quiet native reader for the seven major hadith collections. The
reading experience comes first. AI, accounts, subscriptions, and contribution
tools stay out of the way until the reader asks for them.

These rules are immutable unless the user changes them:

1. Reading works signed out. Accounts add private sync.
2. The product has no votes, leaderboards, public statistics, streaks, ratings,
   reputation, badges, or public collections.
3. AI text is labeled and sourced. Hadithly never presents AI text as
   authoritative.
4. The subscription paywall appears only when the user reaches an AI quota.
5. Convex is the only mobile API and control plane. It calls providers and owns
   secrets. The one allowed data-plane exception is an immutable, checksummed,
   licensed offline artifact fetched from a CDN URL and manifest authorized by
   Convex; clients never query a second application backend.
6. User-scoped backend functions derive identity from the verified Clerk JWT.
7. iOS and Android ship the same behavior through native platform conventions.
8. Relay is not used for this repository.

## Product direction

Use the Sajda screenshots as behavioral references, not a template. Hadithly
keeps the calm reader, hidden controls, strong Arabic typography, compact
progress, and native sheets. It drops Quran-specific structures and anything
that adds noise without helping a hadith reader.

The design uses System, Light, Paper, and Dark themes. The chrome accent is
neutral white; hierarchy comes from luminance, not hue. Emerald survives
only as a semantic color for the brand mark, authenticity grade dots, and
success states. Bookmark and favorite colors appear only where their
meaning is needed. Arabic uses a licensed naskh-compatible font. UI text uses
the platform system font. Dynamic Type and Android font scaling must work.

Remove or consolidate these current behaviors:

- Replace the permanent action row below every hadith with a native context
  menu that appears on hold of the hadith and a quiet overflow action.
  Thus it makes the reader feel less interrupted in between hadiths on the page.
- Replace the Saved landing cards with one private list, filters, and optional
  folders.
- Remove the duplicate global Continue Reading card from Library. Show progress
  on each collection row instead.
- Move the admin queue out of consumer Settings into a secured exception tool.
- Remove the weekly subscription product.
- Do not add reciters, transcription, mushaf or juz modes, Siri actions, social
  mechanics, a generic AI chat, or a rotating Saved widget.
- Defer search until multilingual and offline indexing can return reliable
  results.

## Completed history and current launch state

| Phase | Result | Verification state |
| --- | --- | --- |
| 0 | Archived the legacy app, chose Convex as the only backend, created the SwiftUI app, and built guest onboarding. | Complete |
| 1 | Added Apple, Google, and email-code Clerk flows, guest storage, user sync, and idempotent guest merge. | Complete in development. D2 extended the contract: password sign-in with email or username, username optional (auto-generated from the email, editable in Settings), social sign-in via hosted auth; production auth verified in D2. |
| 2 | Added collection loading, content-sized pages, hidden reader controls, cache-first provider reads, and labeled AI translation with citations. | Complete on iOS simulator with unit and live tests. |
| 3 | Added Today, Library, Saved, Settings, private progress, bookmarks, favorites, notes, APNs registration, and the daily cron. | Complete in development. Production push remains in D1 and D4. |
| 4 | Added translation proposals, AI review, reports, admin approval, audit rows, and a dedicated live UI test. | Complete. The evidence-based replacement is E1 through E4. |
| 5 | Ported the product to Android Compose, including auth, reader, private data, contributions, FCM wiring, and RevenueCat client parity. | Emulator-verified. Production device delivery remains in D1 and D4. |
| 6 | Added quota-only RevenueCat paywalls, hardened webhooks, release routing, CI, account deletion, push credentials, and App Store drafts. | Code complete. External dashboard gate remains open. |

Development Convex is `festive-cobra-664` in `eu-west-1`. Production Convex is
`giddy-ox-648` in `eu-west-1`.

Known launch facts:

- The Firebase project is `hadithlyapp` (name `hadithly`), created on
  2026-09-03 after the owner directed the product off the legacy `sunnad`
  project naming. The Android app and local `google-services.json` use it.
- The old `sunnad` Firebase Admin keys were revoked on 2026-09-03 after the
  `hadithlyapp` replacement was installed and validated. The Android FCM
  device gate must be re-run against `hadithlyapp` because FCM tokens are
  project-scoped.
- The production APNs key is `MU78HDD896` (Sandbox & Production, Team Scoped).
  The older `48VC` key stays active under the owner's separate
  `adat`/`sunnad` projects by owner decision.
- Production Clerk is incomplete. Production Convex cannot pass its auth gate
  until `CLERK_FRONTEND_API_URL` is correct.
- Production Sunnah.now key rotation is waived by the owner. The Gemini
  replacement is installed and validated in production.
- RevenueCat's current Test Store offering contains monthly and annual packages
  attached to `pro`; weekly was removed on 2026-09-04. Real App Store and Play
  products are not connected.
- `hadithly.app` and its public policy, support, deletion, terms, fallback, and
  Apple association pages are live on Vercel. App Store Connect, Play Console,
  and store agreements remain incomplete.
- Screenshots stay deferred until the redesigned release candidate in L1.

Do not call Phase 6 complete from code, configuration files, or simulator tests.
D4 requires direct production and physical-device evidence.

## Locked experience and data contracts

### Languages and reading direction

Onboarding asks only `Choose your language`. The answer initializes both
`uiLocale` and `translationLocale`. Settings later edits `App language` and
`Hadith translation` separately.

Use BCP 47 identifiers. UI fallback is exact locale, base language, then
English. A hadith translation never changes language silently. The UI labels a
fallback source or a permitted AI translation.

Wave 1 contains 15 fully localized interfaces and store listings:

`en`, `ar`, `ru`, `kk`, `ky`, `uz`, `tr`, `id`, `ur`, `fr`, `es-419`, `pt-BR`,
`sw`, `hi`, and `bn`.

Wave 2 contains:

`de`, `it`, `pl`, `uk`, `fa`, `ms`, `ha`, `so`, `zh-Hans`, `ja`, and `ko`.

Use String Catalogs on iOS and locale resources with ICU plurals on Android.
Arabic, Urdu, and Persian require full RTL layout and mixed-script QA.
Directional icons mirror. Arabic text always lays out RTL.

The reader direction setting has `auto`, `rtl`, and `ltr` values. `auto` uses
RTL for Arabic-only reading, the translation script for translation-only
reading, and the translation language for mixed pages. Arabic blocks remain RTL
inside mixed pages. In an applicable RTL flow, a swipe left moves backward.

### Visibility and position

Arabic and translation have independent visibility controls. The clients reject
any state that disables both.

`ReadingPosition` is versioned and contains:

- the collection slug and provider hadith ID;
- the content version, volume ID, and optional chapter ID;
- a stable page key and a display page index;
- a semantic hadith anchor and normalized intra-anchor offset;
- a layout signature derived from locale, visibility, font, size, width class,
  and pagination version;
- `updatedAt`.

The raw page and offset provide a fast first landing. The semantic anchor and
content version recover after a font, locale, visibility, pagination, or dump
change. Continue Reading and Saved restore the stored offset. Today,
notifications, widgets, and canonical links start at the target hadith unless a
versioned position is present.

### Authenticity and daily selection

Store the source label, normalized grade, claim scope, source name, source URL,
verification method, and license record separately. A manual collection mapping
must never look like a source-provided hadith grade.

Daily Hadith may select only:

- a hadith with a source-verified `sahih` or `hasan` grade; or
- a hadith inside a collection with documented collection-level `sahih` scope.

The UI names the scope. It never invents a grade. Persist the daily selection by
the reader's local date and IANA timezone so cache order cannot change it.

### Saved data

Saved is one private list with bookmark, favorite, and note filters. A saved item
can belong to zero or one user-created folder in the first release. Existing
bookmarks, favorites, and notes keep their meanings. Migration creates Saved
records from current rows and keeps the old tables readable until both clients
have shipped and the backfill has passed.

### Canonical links

The canonical hadith URL is:

`https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}`

The canonical URL stays clean. Optional query parameters may carry a requested
translation locale and a versioned position. The resolver validates them and
falls back to the hadith start.

The web fallback ships before Share UI. It shows only licensed Arabic and
translation content, source identity, authenticity scope, and app-opening or
store actions.

### Offline collections

Convex owns versioned base dumps and separate translation packs. Each manifest
contains the schema version, content version, byte size, SHA-256, minimum app
version, generation time, license record, and compatible translation packs.

Clients download to temporary storage, validate the checksum and schema, and
activate with an atomic swap. They keep the previous version until migration
passes. Canonical provider identity preserves Saved records and positions.
Deleting a download removes files only. Download choices stay on the device.
Convex authorizes and versions the artifact; a low-egress object store/CDN may
serve the immutable bytes so collection downloads do not make Convex egress the
dominant bill.

### Notifications and widgets

A push token stores the platform, UI locale, translation locale, IANA timezone,
delivery time, and last sent local date. A daily notification contains the
selected translation and an exact target. It never silently falls back to
Arabic-only text.

Resolution order is official or approved translation, reusable cached AI, then
one policy-permitted service generation. A service generation is globally
cached and does not consume a user's quota. The message labels AI text.

The first widgets are Daily Hadith and Continue Reading. Both support exact
targets, locked-device redaction, offline fallback, localization, and native
accessibility. No other widget ships in this era.

### Evidence contributions

A submission requires one to three evidence items. Accept an HTTPS URL, JPEG,
PNG, WebP, or PDF. Limit each file to 10 MB and each PDF to 25 pages.

Upload processing validates magic bytes, dimensions, MIME type, redirects, DNS
destinations, private-address resolution, response size, and timeouts. Convex
quarantines uploads until a private commercial-safe malware scanner reports a
clean result. OCR and extracted webpage text are untrusted data.

The review system keeps these records:

- evidence assets and extraction state;
- provenance and citations;
- license assessment and the permitted Hadithly uses;
- independent review passes and confidence;
- publication revisions;
- appeals, abuse events, and deletion state.

The AI has no tools, credentials, or network access during evidence judgment.
Prompts place evidence in a delimited data field and tell the model to ignore
instructions inside it. Deterministic code owns file safety, URL safety,
provenance, licensing, and thresholds.

Auto-publication requires clean evidence, affirmative reuse rights, consistent
citations, no contradiction or abuse flag, and two independent reviews at or
above `0.95`. All other submissions are rejected or enter an exception queue.
The admin tool handles exceptions, audits, appeals, and revocation.

Reject private evidence after a 30-day appeal window. Keep published provenance
while the translation is published. After a privacy, licensing, or takedown
deletion, retain only non-sensitive audit facts that the policy permits.

### AI quota and subscription

- Free users receive five new AI translations in a rolling seven-day window.
- Pro users receive 100 new AI translations in a rolling seven-day window.
- Approved and cached translations consume no quota.
- Usage is an immutable event stream. Generation keys and a single-flight lock
  prevent retries or concurrent requests from double charging.
- App Attest and Play Integrity signals, authentication, rate limits, and
  concurrency limits protect generation. The client never sends an arbitrary
  system prompt.
- Pro costs USD 2.99 monthly or USD 24.99 annually before regional storefront
  pricing. There is no weekly product.
- One RevenueCat `pro` entitlement follows one Hadithly account across that
  person's iOS and Android devices. Apple Family Sharing is off.
- Cancellation keeps access until paid expiry. Grace keeps access. Refund,
  revocation, expiry, and account hold remove it. Restore uses the same signed-in
  Hadithly account.

AI generation is an explicit hadith action. Opening or paging the reader may
load official, approved, or already cached translations, but it must not create
paid AI translations for every visible hadith. The current clients do schedule
generation for an entire non-English page; Q1 must remove that behavior before
production quotas or paid acquisition. Grounding is reserved for evidence
review and exceptional verification, not ordinary translation generation.

Ordinary translation uses licensed source material and cache reuse. It does not
run paid web grounding for every request. Current Gemini pricing and grounding
costs must be rechecked before Q1. Current store fees and RevenueCat fees must be
rechecked before Q2.

### Cost and scale guardrails

- Put a monthly hard budget and alert on every paid service. A provider outage
  or exhausted free tier must degrade to cached/offline reading, never retry in
  an unbounded loop.
- Cache by canonical hadith identity, target language, source revision, model,
  and prompt version. Use single-flight generation and idempotency keys.
- The current 15-minute notification cron collects every enabled push token 96
  times per day. N1 must replace the table scan with indexed delivery buckets,
  bounded batches, retry state, stale-token removal, and provider backpressure.
- The current mobile apps keep four personal Convex subscriptions open after
  sign-in. H3 should measure bandwidth and consolidate them into one private
  library snapshot or screen-scoped queries if that lowers cost without making
  sync less reliable.
- A first reader visit currently fetches and stores a full provider volume. O1
  must compare that cache growth with versioned dumps, enforce content and
  translation retention, and keep provider-fetch fan-out bounded.
- Evidence uploads remain quarantined and expire automatically. OCR, malware
  scanning, and AI review have per-submission and per-account spend ceilings.
- Do not add a second database, a second auth system, newsletters, session
  replay, full-text event payloads, or a full web app until measured demand
  justifies its privacy, maintenance, and cost.

## Session order

Run one session per Codex or OpenCode task. Finish its gate before starting a
session that depends on it. A recorded external blocker does not block an
independent branch. Dashboard sessions stay in a local Codex task because they depend
on the signed-in browser and physical devices. GLM sessions are deliberately
substantive: they own bounded implementation outcomes, not just inventories.

| ID | Outcome | Gate | Primary model |
| --- | --- | --- | --- |
| D0 | Restore browser control and inventory every dashboard without changing state. | Chrome documentation and a read-only page inspection succeed. | GPT-5.6 Sol, high |
| G0 | Turn the current branch and mixed worktree into a reviewable checkpoint plan without rewriting history. | Every change is attributed to a proposed commit and no user work is lost. | GLM-5.3-Flash; Luna high fallback |
| M0 | Record the minimum native toolchain and reclaim only approved rebuildable disk space. | Exact deletion targets, restore commands, and before/after free space are recorded. | GLM-5.3-Flash; Luna medium fallback |
| D1 | Rotate Firebase, Sunnah.now, and Gemini credentials; verify APNs and FCM. | Both physical-device pushes and provider smoke tests pass before old keys are revoked. | GPT-5.6 Sol, high |
| D2 | Configure production Clerk (email + password, optional generated username, email code, Apple, Google via hosted auth) and deploy Convex production. | Password sign-up and sign-in, Apple, Google, email code, restore, sign-out, sync, and deletion pass on production builds. Verified 2026-09-03 on release builds (emulator + simulator); Apple full round-trip and physical devices remain for D4. | GPT-5.6 Sol, xhigh |
| D3A | Finish the available domain, policy, App Store Connect, iOS product, RevenueCat, and iOS sandbox work. | Operational Apple wiring is verified. Legal, compliance, sandbox, screenshots, and submission handoffs are recorded separately. | GPT-5.6 Sol, high |
| D3G | Finish Play Console, Android products, Android App Links, and Android store sandbox work. Deferred until the owner has a Play Console developer account. | The Google Play release gate remains open until the account, products, signing fingerprint, and sandbox evidence exist. | GPT-5.6 Sol, high |
| D4 | Run the production launch-system matrix on physical iPhone and Android devices. | The signed evidence matrix passes. Phase 6 becomes complete. | GPT-5.6 Sol, xhigh |
| F1 | Add canonical content identity, authenticity scope, license records, and eligible daily selection. | Migration fixtures prove that no grade or scope is invented. | GPT-5.6 Sol, xhigh |
| F2 | Add UI locale, translation locale, direction, theme, and visibility preference contracts. | Both clients decode, persist, sync, and reject an all-hidden state. Complete 2026-09-07 (emulator + simulator); physical-device confirmation stays in D4. | GLM-5.3-Flash; Terra high review |
| F3 | Ship `hadithly.app` landing, fallback pages, and native link resolution. | Installed, uninstalled, malformed, stale, and signed-out links pass. | GLM-5.3-Flash; Terra high review |
| R1 | Add semantic reading positions and a compatibility migration. | Old progress migrates and new positions survive a pagination-version change. | GPT-5.6 Sol, xhigh |
| R2 | Restore exact position from Continue Reading, Saved, Today, links, notifications, and widgets. | Every entry point lands on the expected anchor and offset on both apps. | GPT-5.6 Terra, high |
| R3 | Correct paging direction, long-content scrolling, and page boundaries. | LTR, RTL, mixed-script, short, and very long fixtures pass on both apps. | GPT-5.6 Sol, xhigh |
| R4 | Add visibility, fonts, sizes, themes, hidden controls, and progress UI. | Screenshot and accessibility matrices pass on both apps. | GLM-5.3-Flash; Terra high review |
| R5 | Add contents navigation and native context actions; enable sharing through F3. | Actions remain reachable with controls hidden and never obscure reading. | GLM-5.3-Flash; Terra high review |
| R6 | Restyle reader chrome, density, and paging from the Sajda references (slices A through G, owner tests each slice). | Focused reading shows only a thin page bar; every control stays reachable; no invented chapters; source stays one tap away. | Muse Spark; Terra high review |
| H1 | Complete Today with eligible translated content, actions, and long-card behavior. | Empty, loading, long, offline, cached-AI, and exact-open cases pass. | GLM-5.3-Flash; Terra high review |
| H2 | Add per-collection Library progress and remove duplicate Continue Reading. | Unopened, partial, complete, offline, and migrated collections render correctly. | GLM-5.3-Flash; Terra high review |
| H3 | Replace Saved landing cards with the unified list, filters, folders, and migration. | No current bookmark, favorite, or note is lost or duplicated. | GPT-5.6 Terra, high |
| S1 | Complete Settings and profile, including export, privacy, legal, storage, and deletion. | Every row performs a real action and passes accessibility and localization checks. | GLM-5.3-Flash; Terra high review |
| O1 | Generate, license, publish, and validate offline dump manifests and translation packs. | Reproducible dump fixtures pass schema, checksum, and license checks. | GPT-5.6 Sol, xhigh |
| O2 | Add client download, update, rollback, corruption, stale, storage, and deletion flows. | Interrupted and corrupt updates preserve usable data, Saved, and positions. | GPT-5.6 Terra, high |
| N1 | Send the selected translation and route notifications to exact targets. | Locale, DST, denial, retry, stale target, and AI-label cases pass on devices. | GPT-5.6 Sol, xhigh |
| W1 | Add the native Daily Hadith widgets. | Both platforms pass locked, offline, stale, localized, and exact-open cases. | GLM-5.3-Flash; Terra high review |
| W2 | Add the native Continue Reading widgets. | Both platforms pass privacy, no-progress, stale-position, and exact-restore cases. | GLM-5.3-Flash; Terra high review |
| E1 | Add evidence schema, limits, quarantine storage, and upload clients. | Invalid, oversized, duplicate, private, and interrupted uploads fail safely. | GPT-5.6 Terra, high |
| E2 | Add malware scanning, safe URL fetching, OCR, and extraction. | Malware and SSRF suites pass; untrusted content cannot control tools or prompts. | GPT-5.6 Sol, xhigh |
| E3 | Add provenance, licensing, comparison, independent review, and auto-publication. | Only licensed, consistent submissions over the threshold publish automatically. | GPT-5.6 Sol, xhigh |
| E4 | Add the admin exception tool, appeals, audits, abuse controls, revocation, and deletion. | Exception and retention policies pass without a routine approval queue. | GPT-5.6 Terra, high |
| Q1 | Replace monthly counters with rolling usage events, cache reuse, integrity signals, and abuse controls. | Window, race, retry, cache, and tamper tests pass. | GPT-5.6 Sol, xhigh |
| Q2 | Ship monthly and annual entitlement semantics, regional pricing, restore, grace, and quota copy. | Store sandbox lifecycle and cross-platform account tests pass. | GPT-5.6 Sol, high |
| LA1 | Add low-cost crash reporting, structured logs, uptime checks, and privacy-safe alerting. | Redacted test failures arrive from production-like builds and alerts have an owner. | GPT-5.6 Terra, medium |
| LA2 | Add minimal privacy-preserving product analytics and a deletion/retention contract. | A tiny event taxonomy answers launch questions without capturing reading content. | GLM-5.3-Flash; Terra medium review |
| LA3 | Add support email, transactional email, status/incident copy, backups, and cost budgets. | Every channel is tested, has retention and spend limits, and degrades safely. | GLM-5.3-Flash; Terra medium review |
| LA4 | Decide whether to expand the fallback into a read-only web reader after native launch. | Licensing, demand, maintenance, privacy, and cost evidence support an explicit build-or-defer decision. | GLM-5.3-Flash; Terra medium review |
| L1 | Finish Wave 1 localization, native-speaker QA, metadata, screenshots, and the release candidate. | No critical untranslated UI, broken RTL, policy gap, cost alarm, or dashboard blocker remains. | GLM-5.3-Flash; Terra high review; Sol high final gate |

### F1 session record (2026-09-07)

- Outcome: complete. Hadiths now expose a canonical provider identity and a discriminated authenticity claim. License terms live in separate records. Daily Hadith persists one eligible choice for each local date and IANA timezone.
- Design: an embedded authenticity claim won over a separate claims table because reader and daily lookups need one self-contained record. The license remains separate because content identity, authenticity, and reuse permission change independently.
- Backend and migration: `contentPolicy.ts` owns canonical IDs, the two cited manual collection mappings, and the legacy conversion. `migrations:migrateF1Hadiths` backfills bounded pages, removes legacy claim fields, records Sunnah.now licensing as unverified, and preserves any later verified license. New schema fields remain optional until deployed rows complete the backfill.
- Daily policy: only source-provided `sahih` or `hasan` hadith grades and documented collection-level `sahih` claims qualify. Selection sorts by canonical ID before choosing and persists the result. The public action requires no user identity.
- iOS and Android: both clients send the current IANA timezone, decode `provider`, `canonicalId`, and the authenticity claim, and show a quiet source-and-scope line in Today and Reader. The new text has accessibility identifiers. Broader authenticity presentation remains in R4.
- Security: the Sunnah.now adapter parses unknown JSON before normalization, ignores grade-like provider prose, and serializes provider fields into a marked untrusted-data block before AI translation.
- Evidence: backend typecheck passed; all 32 backend tests passed; all 25 iOS unit tests passed on the Hadithly D2 iPhone 17 Pro simulator; all 16 Android debug unit tests passed with JDK 21. Migration, idempotency, local-date, IANA-timezone, collection rotation, cache-order, eligibility, public-read, license-preservation, and prompt-boundary fixtures passed. A live public development request returned canonical `sunnah_now:bukhari:57` with collection scope and `manual_collection_mapping`. The iOS Today screen then rendered Hadith 57 with `Sahih collection scope · Sunnah.com`.
- External state: F1 functions and schema were pushed to development Convex `festive-cobra-664`; the live request persisted its Asia/Almaty daily selection. No production, credential, dashboard, or store state changed, and the production data backfill did not run.
- Next allowed session: F2. This task stopped before F2.

### F2 session record (2026-09-07)

- Outcome: complete. Both clients decode, persist, sync, and reject the
  all-hidden visibility state; the preference contract lives in one versioned
  object on the `users` row shared by iOS and Android.
- Design: a flat, versioned `readerPreferences` object (schemaVersion 1)
  embedded on the user row won over a separate table because preferences are
  always read and written as one unit. Validation is shared domain logic in
  `convex/lib/preferences.ts` (BCP 47 tag pattern, direction and theme
  literals, Arabic font size 18–40, font-id shape, `VISIBILITY_ALL_HIDDEN`
  rejection). Writes are last-write-wins by `updatedAt`; the first signed-in
  call migrates legacy `preferredLanguage` into full preferences behind a
  `localesMigrated` flag. Unknown server-side font ids degrade to the client
  default, so newer clients can add licensed fonts without breaking older ones.
- Backend: `users.readerPreferences` optional field in `schema.ts`;
  `updateReaderPreferences` and `getCurrentUserPreferences` in `users.ts`
  (both `requireIdentity`); `ensureCurrentUser` seeds/migrates preferences.
  Pushed to development Convex `festive-cobra-664` (verified in function-spec).
  Production was not touched.
- iOS and Android: onboarding writes `uiLocale` and `translationLocale`
  together from one choice; Settings shows the Reading card (app language,
  hadith translation, reading direction, Arabic/translation visibility,
  Arabic type size) and the reader sheet reuses the same store. Both clients
  reject hiding the last visible text layer locally and the server rejects it
  again. Accessibility identifiers (`settings.visibility.arabic`,
  `settings.readingDirection.auto`, …) exist on both platforms.
- Localization evidence: F2-scoped strings only (onboarding, Reading card,
  direction labels, plural footer) in `Localizable.xcstrings` and Android
  `values-ar`/`values-ur`; whole-app localization stays in L1. Live checks:
  Arabic and Urdu render RTL with mirrored bars and pickers on both platforms;
  the Arabic plural footer resolves the `few` category ("8 لغات متاحة") and
  Urdu the `other` category ("8 زبانیں دستیاب ہیں"). Android used per-app
  locales (`cmd locale set-app-locales`), the real user-facing mechanism.
- Tests: backend typecheck clean and 47/47 tests passed; iOS 51/51 unit tests
  on the Hadithly D2 simulator (new LocaleFallback, LocalizationCatalog,
  PreferencesMigration, ReaderPreferences suites); Android 39/39 debug unit
  tests with JDK 21 (same new suites plus reader wiring). Live device checks
  ran on an Android 16 emulator and the iOS simulator — physical-device
  confirmation stays in D4.
- Review repair (2026-09-08): a fresh client default can no longer overwrite
  an existing server row's legacy language during the one-time migration;
  explicit local choices still win. Android reader size now uses the synced
  `PreferencesStore` rather than the retired `AppSettings` duplicate. Both
  app roots apply `uiLocale` to localized resources and layout direction.
  The new backend legacy-row fixture passes; backend typecheck and 48 tests,
  iOS 51 tests, and Android debug tests pass. The corrected functions were
  pushed to development Convex `festive-cobra-664`; production was untouched.
  On the Android 16 emulator,
  selecting Arabic and Urdu from the app's own temporary control immediately
  localized F2 controls and mirrored the layout; switching back to English
  restored LTR. Physical-device confirmation remains D4.
- Security: no new untrusted-data surface; every preference mutation derives
  identity from the Clerk JWT. No dashboard, credential, or store state
  changed.
- Handoff: the worktree holds the F2 changes uncommitted (backend, both
  clients, docs/FONT_LICENSES.md, four new suites per client). The named
  Terra high review of this patch has not run yet; schedule it before or with
  F3.
- Next allowed session: F3. This task stopped before F3.

### F3 session record (2026-09-08)

- Outcome: complete. `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}`
  now resolves on the backend, renders through a licensed web fallback on
  Vercel, and routes into both native apps via Universal Links / App Links.
  Share UI remains R5; nothing here generates AI or exposes private positions.
- Design: one public, identity-free Convex query
  (`hadiths:resolveCanonicalLink`) owns resolution and trust decisions;
  each surface parses at its own boundary against a pure shared contract in
  `backend/convex/lib/canonicalLinks.ts` (slug `^[a-z][a-z0-9-]{1,31}$`,
  hadith id `^[1-9][0-9]{0,11}(\.[0-9]{1,12})*$`, `locale` via the shared F2
  tag canonicalizer, `pos` version tag `^v[0-9]{1,12}$`). Malformed, foreign,
  stale, and unsupported-locale links degrade to safe fallbacks — the reader
  start, the labeled provider English, or a quiet web message — never errors.
- License gate (compliance-first): the backend returns text only when the
  hadith's license record is `verified` with `permitsDisplay`. Every current
  cached row records Sunnah.now as `unverified`, so today the web fallback
  shows reference, source, authenticity scope, and app actions only; text
  appears the moment a license record verifies. No AI generation exists on
  the page-load path; only already-live cached translations are read, with
  the exact → base language → provider English chain labeled by
  `translationFallback`.
- Backend: `lib/canonicalLinks.ts`, public `hadiths:resolveCanonicalLink`
  plus `canonicalLinkResultValidator` in `hadiths.ts`. No schema change. The
  `contentVersion` marker is `sourceUpdatedAt` until O1 defines versioned
  dumps. Functions pushed to development Convex `festive-cobra-664` and
  proven live via `POST /api/query` (the region-qualified deployment host
  serves the HTTP API; the bare apex 404s, so `site/convex-config.js` uses
  `https://festive-cobra-664.eu-west-1.convex.cloud`). Production untouched.
- Web: `site/hadith/index.html` rewritten with loading / resolved /
  invalid / not-available states and app actions; `site/canonical.js` parses
  the path at the page boundary (page origin is its own trust boundary) and
  fills the page from the one public query; `site/styles.css` gained the
  RTL Arabic block, translation, scope pill, and fallback-note styles.
  Vercel rewrites already mapped `/hadith/*`; the AASA was already live from
  D3A-domain. Deploying the new files to Vercel is an owner action.
- iOS: entitlements add `applinks:hadithly.app`; `App/LinkRouter.swift`
  mirrors the parse contract and queues at most one link, silently ignoring
  foreign/malformed URLs; `RootView` registers `.onOpenURL`; MainTabs
  presents the reader over the tabs in a full-screen cover, signed-out
  access unchanged. A real routing bug was found and fixed during simulator
  verification: consuming the pending link cleared the queue and re-fired
  `.onChange`, instantly closing the cover; the nil transition no longer
  triggers a consume. Because canonical routes carry no volume, the reader
  now locates the volume holding the target hadith from the
  source-provided outline counts (`ReaderModel.volumeId(forHadithNumber:)`
  over cumulative counts; sub-references use the integer part; unknown or
  stale numbers keep the first volume at page 1).
- Android: manifest gains the `autoVerify` VIEW intent-filter for
  `https://hadithly.app/hadith/`; `core/links/CanonicalHadithLink.kt` is a
  framework-free parser (`parse(scheme, host, path)`); MainActivity threads
  the link through `LocalizedRootApp` → `RootApp` → MainTabs, which opens
  the reader exactly once after onboarding completes;
  `ReaderViewModel` carries the mirrored volume locator as a companion
  function. Domain verification stays unverified (state 1024) until D3G
  supplies the Play signing fingerprint for `assetlinks.json`; the
  emulator matrix used the real user-selection path
  (`pm set-app-links-user-selection`) for the installed cases.
- Evidence: backend typecheck clean, 62/62 tests (14 new); Playwright
  8/8 scenarios (licensed text + RTL translation, labeled provider English,
  unsupported-locale degradation, unverified-license text suppression, AI
  label, malformed, stale, resolver outage) via
  `scripts/test-canonical-fallback.py`; iOS 63/63 unit tests on the
  Hadithly D2 simulator (12 new: parser matrix, router queue-once,
  volume locator) plus simulator proof — valid link opened the reader at
  Volume 2, the page containing Bukhari 57; malformed landed on Today with
  no reader; stale 9999 landed at Volume 1 start; Android 49/49 unit tests
  with JDK 21 (10 new) plus the same matrix on the hadithly emulator:
  installed + signed-out + `?locale=zz&pos=v99` routed into the reader,
  malformed opened Today without a reader, stale fell back to Volume 1,
  uninstalling sent the link to the browser fallback, and the debug
  fingerprint is recorded unverified pending D3G. Live dev proof:
  `POST /api/query` returned `sunnah_now:bukhari:57` with
  `license: unverified` → `text.visible: false`, and `9999` → `not_found`
  with the route echoed.
- Security: no new identity surface (the resolver is public and reads no
  user rows); inbound links are validated by pure functions before any
  backend touch; the web page renders escaped text only, reads no private
  positions, and never triggers generation. No dashboard, credential, or
  store state changed; the Android emulator and iOS simulator state
  changes were app-local.
- Follow-up review (2026-09-08): the named Terra high URL/association review
  found and repaired one parser mismatch. Percent-encoded IDs and duplicate
  separators are now rejected on iOS, Android, backend, and web rather than
  opening the native reader while the fallback rejects the same link. New
  parity fixtures cover encoded IDs and encoded slashes. The iOS AASA and
  entitlement identifiers match; live AASA is valid. The F3 source was
  committed in `4dfdaf3`; this review hardening follows as a separate commit.
- External follow-up: the live canonical URL still serves the pre-F3 fallback.
  The local Vercel CLI has no authenticated account, so deployment needs an
  owner-authenticated Vercel session or a configured non-secret deployment
  path. D3G still owns the Play signing fingerprint and live
  `assetlinks.json`; do not create or substitute a fingerprint until the
  Play Console track is available.
- Next allowed session: R1. This task stopped before R1.

### R1 session record (2026-09-08)

- Outcome: complete. `ReadingPosition` V1 now has the same Convex, Swift, and
  Kotlin wire shape. It stores the F1 provider anchor, content and layout
  versions, volume and chapter context, a stable page key, a one-based display
  page, a raw logical offset, a normalized intra-hadith offset, and `updatedAt`.
- Design: the existing per-user, per-collection `readingProgress` row owns an
  optional V1 position. Legacy fields remain as a derived projection for old
  clients. This avoids a second authoritative table. The pure resolver trusts
  the raw hint only when the content version, layout signature, page key,
  display page, and anchor match. Otherwise it resolves the exact semantic
  anchor. A missing anchor selects the nearest dotted-decimal provider ID,
  preferring the stored volume and chapter, and resets both offsets to zero.
- Backend: `lib/readingPositions.ts` owns validation, legacy conversion, and
  deterministic resolution. `saveReadingProgress` accepts both generations,
  resolves cache-row replacement through provider identity, and applies only a
  newer `updatedAt`. Guest merge uses the same write path. The bounded
  `migrateR1ReadingProgress` backfill keeps all legacy fields.
  `getReaderPage` now returns a SHA-256 content version, pagination version,
  and content-addressed page key. No provider or AI call moved outside Convex.
- Clients: iOS stores the V1 payload as optional SwiftData JSON beside its
  legacy guest fields. Android adds the optional payload to the existing guest
  JSON file. Both clients decode old rows, produce V1 merge payloads, use
  `Double` for every Convex number, and compute the same SHA-256 layout
  signature from locale, visibility, font, size, width class, and pagination
  version. Android guest writes now reject older timestamps instead of
  replacing newer local progress.
- Reader behavior: both clients save a V1 position for the first hadith on the
  current page with zero offsets. R2 owns visible-anchor capture, offset
  restoration, and entry-point routing. R1 changed no visual, localization, or
  accessibility behavior.
- Evidence: backend typecheck and all 70 backend tests passed. All 70 iOS unit
  tests passed on simulator `0B7AA212-A540-4621-8C0A-155C4B063A76`. All 57
  Android debug unit tests passed with JDK 21. The suites cover old-row and
  guest migration, wire round trips, latest-wins replay, cache-row replacement,
  content and layout changes, pagination-signature changes, and missing
  anchors. Development Convex `festive-cobra-664` accepted the new schema and
  validators. A live Bukhari page returned `cv1` and `pg1` digests plus
  pagination version 1. The development backfill migrated five existing rows;
  its second run reported five unchanged and no deferred rows.
- Security and external state: all signed-in functions still derive identity
  from Clerk. Position validators reject malformed versions, identities, and
  numeric ranges. Development data changed only through the R1 backfill.
  Production, dashboards, credentials, stores, and release state were not
  touched.
- Next allowed session: R2. This task stopped before R2.

### R2 session record (2026-09-09)

- Outcome: complete in `7ff3a39`. Continue Reading and Saved restore a stored
  semantic anchor and normalized offset. Today, links, and notification targets
  open at the requested hadith start unless they carry a valid private
  position.
- Clients: both readers save after the initial target resolves, after stable
  scroll changes, after page changes, and on close. Android ignores the pager's
  synthetic first emission during a deep-link landing. Both clients preserve
  signed-out reading and the source-aware close path.
- Evidence refreshed before R3: all pre-R3 iOS and Android unit tests passed.
  Canonical links opened Bukhari 57 on Volume 2, page 12 in both installed
  clients. R3 extends the same position path for very long hadiths.
- Backend and external state: R2 added no schema change. Production,
  dashboards, credentials, and stores did not change.
- Next allowed session: R3.

### R3 session record (2026-09-09)

- Outcome: implementation complete. The physical-device gate remains open.
  Do not start R4 until both physical clients pass the R3 matrix.
- Root cause: iOS treated every left swipe as forward, while Android used the
  pager's default physical order. Neither client connected F2 direction
  metadata to paging. The iOS offset capture also inferred the final hadith's
  height from a missing next anchor.
- Direction contract: one logical policy per client resolves `auto`, `rtl`, and
  `ltr`. A left swipe moves to the previous page in RTL and to the next page in
  LTR. Previous and next stay logical accessibility actions. End controls swap
  physical order and arrow direction in RTL.
- Reading behavior: Arabic-only pages resolve to RTL in `auto` mode.
  Translation-only and mixed pages follow the translation locale. Each Arabic
  block keeps local RTL layout. Both clients now honor the existing Arabic and
  translation visibility preferences in the reader.
- iOS: `ReaderPagingPanHandler` observes the window without cancelling the
  vertical `ScrollView`. It accepts either a settled horizontal distance or a
  short high-velocity flick, ignores vertical and cancelled gestures, and
  removes itself on teardown. Position capture uses each hadith's measured
  height. Restoration converts the normalized intra-hadith offset with the
  measured item and viewport heights.
- Android: `DirectionAwareHorizontalPager` fixes its local layout direction and
  uses `reverseLayout` only for RTL page flow. The nested `LazyColumn` remains
  the native vertical scroller. The end controls and pager expose logical
  accessibility actions.
- Backend: `chunkReaderHadiths` did not change. New fixtures prove deterministic
  source order, the 5,200-character boundary, the ten-item cap, and one intact
  page for a single hadith longer than the target size.
- Automated evidence: backend typecheck and 73 tests passed. All 76 iOS unit
  tests passed. Five focused iOS gesture tests and four simulator UI tests
  covered the full direction and visibility matrix, velocity, cancellation,
  one-line pages, long pages, boundaries, end controls, and vertical scrolling.
  All 60 Android unit tests passed. Six Android 16 emulator tests drove the
  production pager for LTR, RTL, velocity, cancellation, a nested long-page
  scroll, boundaries, and accessibility controls.
- Runtime evidence: both installed clients opened Bukhari 57 on Volume 2,
  page 12. The Android reader moved backward to page 11 on a right swipe in LTR
  and remained on page 11 after a vertical swipe.
- Open gate: Xcode lists the paired iPhone, but the physical UI run timed out
  because the device was unavailable for preparation. Unlock and attach the
  iPhone by cable, or enable its local-network Developer Mode connection.
  `adb devices -l` reports only the Android emulator. Run the same fixture and
  installed-reader matrix on both physical devices, then record the result
  here. No R4 code has started.

### R4 session record (2026-09-09)

- Outcome: implementation and named Terra high review complete on both
  clients. The owner directed this session to proceed despite R3's
  physical-device gate still being open, so that gate remains recorded above
  and still requires its physical-device matrix.
- All 16 Sajda reference images were opened at original detail before code;
  the ten R4-mapped images drove the implemented behaviors: revealed chrome
  with expanded progress, compact thin progress while reading, source-provided
  chapter openings, minimal hadith dividers, System/Light/Paper/Dark themes,
  a focused type sheet with live preview and A−/A+ size steps, visibility
  pills, and direction-aware end controls.
- Themes: reader-scoped `ReaderPalette` (iOS environment values, Android
  CompositionLocal) resolves the F2 `ReaderTheme` preference against the OS
  appearance. Every reader surface — page, chrome, sheets, note editor —
  follows the palette; the rest of the app keeps its dark canvas. System
  follows light/dark; Light, Paper, and Dark are fixed palettes.
- Typography: Amiri, Scheherazade New, and Noto Naskh Arabic (all SIL OFL 1.1)
  are bundled on both platforms with the license text attached beside the
  binaries; records re-verified 2026-09-09 in `docs/FONT_LICENSES.md`. The
  reader settings sheet offers the four faces with a live preview and an
  A−/A+ ladder (18/22/26/30/34/40 pt). Dynamic Type and Android font scaling
  continue to govern UI text; the Arabic face uses the preference size.
- Chrome and progress: with chrome hidden, a thin top progress bar shows the
  page fraction (a11y-hidden; the expanded pill carries the description);
  revealing the chrome shows the top bar and expanded page/volume pills. Page
  turns snap under Reduce Motion (iOS `accessibilityReduceMotion`, Android
  animator-duration-scale 0).
- Boundaries and dividers: `ReaderChapterBoundaries` renders a strong chapter
  header only for source-provided `chapterName` transitions — Hadithly never
  invents a chapter. The numbered medallion became a quiet reference label,
  and hadiths separate with restrained hairlines instead of cards.
- Visibility: reader settings offers Arabic and Translation pills on both
  platforms; the store rejects hiding the last visible layer (F2 contract),
  and the UI surfaces that rule.
- Position recovery: `reanchorAfterLayoutChange` (both platforms) rebuilds
  restoration from the last stable semantic anchor against the recomputed
  layout signature after any font, size, visibility, or translation-locale
  change; the page keys its applied restoration on a generation counter so
  the re-scroll happens exactly once. Theme and direction do not touch the
  layout signature.
- Files: iOS — `ReaderPalette.swift`, `ReaderChapterBoundaries.swift`,
  `ReaderView.swift`, `ReaderSheets.swift`, `ReaderModel.swift`,
  `Theme.swift`, `ReaderPreferences.swift`, `Info.plist`, fonts under
  `Resources/Fonts/`, fixture extended with R4 variables; Android —
  `Theme.kt`, `ArabicTypefaces.kt`, `ReaderChapterBoundaries.kt`,
  `ReaderScreen.kt`, `ReaderViewModel.kt`, `ReaderPreferences.kt`,
  `ReaderTypographicFixture.kt`, `MainActivity.kt`, fonts under `res/font`
  plus `assets/font-licenses/`.
- Tests: backend untouched (no schema, API, or migration change). iOS 86/86
  unit tests (10 new in `ReaderR4Tests`) and 5/5 UI tests including the new
  `testR4LanguageThemeAndAccessibilityMatrix` (en/ar/ur × four themes with
  revealed chrome, compact chrome, and large-content cases) on the Adat
  iPhone 17 Pro simulator. Android unit tests pass with JDK 21 (8 new in
  `ReaderR4Test`) and the R3 instrumentation suite passes on the hadithly
  emulator. A screenshot matrix (fixture-driven, 3 languages × 4 themes per
  platform) was captured locally; it exposed and fixed one real defect — the
  fixture translation text relied on the default label color and was
  invisible on light backgrounds.
- Security and external state: no new identity, network, or AI surface; all
  preference mutations still flow through the F2 stores and derive identity
  from Clerk on the backend. No production, dashboard, credential, or store
  state changed; development Convex was untouched.
- Terra review repair (2026-09-09): Android reader settings now scroll at
  large font scales; visibility, theme, font, and language choices expose
  toggle/radio semantics to TalkBack; both clients provide an explicit
  screen-reader action to reveal hidden chrome; the duplicate Android
  reference line was removed; and `UIAppFonts` now registers all three iOS
  Arabic faces rather than silently falling back to the system face. Touch
  targets for iOS chrome and type steps meet 44 points and Android type steps
  meet 48 dp.
- Review evidence: iOS 86/86 unit tests and its 12-case R4 language/theme
  fixture matrix passed; Android debug unit tests and 6/6 emulator
  instrumentation tests passed. The iOS app bundle was inspected to confirm
  the three `UIAppFonts` entries. A direct Android Urdu/Paper fixture launch
  exposed the expanded progress, source-provided chapter title, Arabic, Urdu
  translation, and logical page controls in the accessibility hierarchy. The
  unrelated live Phase 4 translation UI test still cannot load a stored
  translation; its five reader fixture tests passed.
- Blockers and next: R3's physical-device matrix remains open as recorded.
  Next allowed session: R5 only after the owner confirms the R3 gate.

### R5 session record (2026-09-09)

- Outcome: implementation complete on backend and both clients. The owner
  directed this session to proceed while R3's physical-device gate is still
  open, so that gate remains recorded above and still requires its
  physical-device matrix.
- All 16 Sajda reference images were opened at original detail before code;
  only the R5 mapping was applied: `contents from menu.PNG` (navigable
  contents sheet with progress context, minus Quran-only Surah/Juz grouping),
  `context menu when holding ayah to do actions.PNG` (long-press actions
  without a permanent toolbar, minus Play Ayah and Ask Siri), and `menu
  open.PNG` (quiet compact menu, minus audio/search rows). The three H3
  private-saved references were reviewed in orientation only.
- Backend (pushed to development Convex `festive-cobra-664`; production
  untouched): `lib/sunnahNow.ts` gains source-provided `ChapterOutlineEntry`
  values and a pure `aggregateVolumeOutline` (volume order, counts, and
  first-seen titles preserved; hadiths without chapter identity still count
  toward the volume; nothing is synthesized). `collectionOutlines` schema and
  `upsertOutline` accept the optional per-volume `chapters` array; old cached
  outlines still validate and `getCollectionOutline` rebuilds once when the
  chapters key is missing. `resolveCanonicalLink` returns optional `volumeId`,
  `chapterId`, and `chapterName` canonical targets. New pure
  `formatCanonicalHadithUrl` builder (throws on malformed input; drops
  unsupported locale params instead of sharing them silently).
- Live backend proof: Bukhari outline rebuilt on dev — 97 volumes, 3,512
  source-provided chapters (English titles with Arabic titles where the
  provider supplies them). `resolveCanonicalLink` for Bukhari 57 returns
  `volumeId 2`, `chapterId 42` with its source chapter name.
- iOS: the permanent per-hadith action row and inline Suggest/Report text row
  are gone. Each hadith block has a native `.contextMenu` titled with its
  reference and a quiet trailing ellipsis (`reader.moreActions`, 44pt,
  secondary tint) opening a native `Menu` with the identical actions:
  Bookmark, Favorite, Note, Copy, Share (ShareLink with only the canonical
  URL), plus secondary Report (only when a loaded non-English translation
  exists) and Suggest Translation (existing sheets/flows reused; guests keep
  the sign-in notice). VoiceOver custom actions expose all seven on every
  block. Contents sheet lists volumes that expand to source-provided chapters
  (title, count, Arabic subtitle) plus a jump-to-reference field: well-formed
  numbers navigate the R2 target path (same stale fallback as canonical
  links); malformed input shows an inline error and keeps the sheet open.
  `ReaderShare` owns the URL builder (round-trips through
  `CanonicalHadithLink.parse`) and the copy formatter (visible Arabic and/or
  translation, `— collection · Hadith id · source` line, `· AI translation`
  suffix only for AI text, never the URL). Pre-R5 outlines without chapters
  render volumes exactly as before.
- Android: same behavior through native Compose patterns — `combinedClickable`
  long-press and a 48dp quiet overflow open one shared `DropdownMenu`;
  TalkBack custom actions mirror the menu; copy via ClipboardManager and
  share via `ACTION_SEND` chooser carry the specified payloads; contents
  bottom sheet, chapter jump, and back-compat match iOS.
- Tests: backend typecheck clean, 81/81 tests (8 new: chapter aggregation,
  URL builder, resolver targets). iOS 99/99 unit tests (13 new in
  `ReaderR5Tests`) plus `ReaderR5UITests` 5/5 and `ReaderPagingUITests` 5/5 on
  the Adat iPhone 17 Pro simulator. Android 80/80 debug unit tests (12 new in
  `ReaderR5Test`) plus `ReaderR5SheetTest` 7/7 fresh on the hadithly emulator
  (contents chapters, chapter tap, jump valid/invalid, long-press and overflow
  menus, report gating) and the pager suite unchanged. The simulator screen
  recording shows the native R5 menu (Bookmark, Favorite, Add Note, Copy,
  Share, Suggest Translation) rendering over the reader.
- The unrelated live Phase 4 translation UI test fails exactly as recorded in
  R4: no stored Russian translation loads on dev, so its Report poll exhausts
  ("Stored translation never loaded"). Its R5 menu adaptation was repaired in
  passing (menu toggle-dismiss, hadith-agnostic settling, bidirectional
  search, verdict-dismissal guard); the remaining blocker is the dev content
  gap, not R5 code.
- Security and external state: no new identity, network, or AI surface; share
  carries only the F3 canonical URL; copy carries no URL and labels AI text.
  Sheets preserve exact scroll position on both clients. No dashboard,
  credential, or store state changed.
- Next allowed session: H1. This task stopped before H1.

### R6 session record (proposed 2026-09-09, owner-directed reader polish)

- Goal: make the reader feel like the Sajda references — calm page, hidden
  chrome, bottom-circle controls — without breaking R1/R2 positions, F2
  direction/visibility contracts, F1 source labeling, or the R5 action set.
- Image mapping: revealed chrome plus bottom circles from `when clicking
  anywhere … expands.PNG`; the expanding card stack from `menu open.PNG`;
  thin centered progress and divider-free text from `middle of page, progress
  bar on top, notice minimal divisions between ayahs.PNG`; adjacent page
  buttons from `end of page reader.PNG`; quiet `10:2`-style markers and
  chapter openings from `start page reader.PNG`, `translation + arabic.PNG`,
  and `new surah (could be new chapter in hadithly).PNG`; sheets and
  submenus from `settings open from menu.PNG`, `arabic fonts and size.PNG`,
  `color themes options.PNG`, and `contents from menu.PNG`.
- Slices (owner tests each slice before the next starts):
  - A (first): page density — volume corner label with hadith range,
    start-aligned text, trailing/leading narrator line, minimal `n`-style
    hadith markers, grade dot plus compact label with a tap-for-source sheet,
    chevrons beside the page number, quiet name-only chapter lines, `N
    hadiths` under volume titles. Covers owner notes 3, 7, 8, 9.
  - B (quick wins): haptic on tap-toggle only, hidden native scroll
    indicators, pills moved to the top (static content).
  - C: note 1 — thin dynamic neutral page bar when focused; two filling pills
    at the top when unfocused; no green, no full-width, no mid-screen bar.
  - D: note 2 — no top header; bottom-left back circle, bottom-right menu
    circle expanding upward; scroll or menu-open collapses to focused.
  - E: note 4 — card-stack menu aesthetic plus settings, contents, theme,
    and font subviews in the Sajda pattern (Quran-only modes rejected).
  - F: note 5 — interactive track-the-finger paging with mid-gesture cancel
    (iOS moves to a native paging container; Android pager tuned).
  - G: note 6 — cross-volume swipe and end-of-volume next/previous volume
    actions.
- Owner corrections round 2 (2026-09-09, resolved): page navigation is TWO
  bottom pills — previous and next neighbor page numbers in the Sajda `209
  Page` style — not one centered cluster. At volume edges the pills show the
  neighboring volume's full localized name (`‹ Volume 1`, `Volume 3 ›`) and
  both pills and swipe cross volumes (first page of next / last page of
  previous, with loading state on first fetch). The narrator shows in every
  mode: with the translation in mixed mode, above the Arabic and RTL-aligned
  in Arabic-only mode. Volume references always use full names, never bare
  numbers. Slice B keeps haptic plus hidden scroll indicators; pills-to-top
  is dropped in favor of the bottom pills.
- Owner confirmations (2026-09-09, resolved): Arabic keeps RTL shaping with
  start alignment (never LTR glyphs); the source name leaves the page but
  stays one tap away on the grade label (copy/share keep full source lines);
  the R5 ellipsis is deleted with no visual replacement — the sighted path
  is long-press only, and VoiceOver/TalkBack custom actions are the
  screen-reader equivalent. `menu open.PNG`'s bottom-right stack is the only
  menu: location card, Bookmarks and Notes, Settings, a bottom action row
  (bookmark/note for the positioned hadith; no playback, search stays
  deferred), and X dismiss. Its bookmark acts on the positioned (R2 anchor)
  hadith. Slice A builds on both apps together.
- Gate: R5's action set unchanged and reachable, positions survive every
  restyle, shared links still pass F3 routing. Stop before H1.
- Progress 2026-09-10: Codex implemented the round-2 corrections plus slices
  C, D, F, G on both apps (`80d21d2` two-pill volume paging, `eacd5ad`
  boundary swipe, `c707dee` wider end controls, `61f775b` bottom chrome,
  `a6d8c72` positioned menu actions and drag paging). Repair pass: two stale
  UI expectations updated to the new chrome (pill labels, menu-path
  contents), dead top-bar and bottom-pill chrome deleted on both apps,
  location card wired to contents, Phase4 language path moved to the menu.
  Evidence: backend 81/81, Android 105/105 unit plus 19+7+7/33
  instrumentation on the hadithly emulator, iOS 127/127 unit plus R6A 17/17,
  paging 5/5, and R5 live 5/5 on simulator. The Phase4 live test still stops
  at the recorded dev-content gate (no stored Russian translation), with the
  menu-path language switch verified working. `docs/R6_READER_VIDEO.md`
  holds the frame-by-frame Sajda recording notes for context-less models.
- Fixes round 3 (2026-09-11, owner video `ScreenRecording_09-11-2026
  01-56-24_1.MP4`, 197 s: Sajda reference plus Hadithly defects): (1)
  axis-locked drag paging with pre-rendered neighbor pages; (2) Arabic
  narrator line (`narratorAr`, RTL) in Arabic-only mode, volume/chapter names
  follow the visible layers; (3) source truth: provider English is
  Sunnah.now, never Sunnah.com; (4) any scroll collapses to focused (no
  haptic) and closes the menu; (5) tap-toggle focus plays haptic, scroll
  never does; (6) focused thin narrow dynamic page bar below the notch,
  unfocused static volume bar plus thicker page bar, no mid-screen bar;
  (7) prefetch outline plus first page on Library/Home/Saved entry and
  adjacent volumes in the reader; (8) menu restyle to the Sajda order
  (Contents, Bookmarks and Notes, Settings, Bookmark plus functional
  English-text Search), bookmark placement choice, filled state, chevron-left
  back; (9) green note indicator by the hadith label; (10) Sajda-styled
  contents, settings, search-results, and reader Bookmarks and Notes sheets.
  Search contract (new public query): `hadiths:searchEnglish { text,
  collectionSlug?, limit? }` returns `[{ hadithId, canonicalId,
  collectionSlug, providerHadithId, referenceDisplay, snippet }]` over
  cached English text only.

### H1 Home and reader-polish completion (2026-09-13)

- Outcome: Today keeps one tappable authenticity source-and-scope label with
  its grade dot. The label opens the existing native source sheet. The daily
  card no longer repeats a translation provider line. Home now presents up to
  three private Continue Reading cards and the seven collections as full-bleed
  horizontal rails. Both rails use the same wordless, code-native collection
  covers as Library.
- Library: both clients default to a two-column cover grid and provide one
  direct grid-or-list toggle. List rows reuse the cover treatment and show a
  collection number, full collection name, and an empty progress slot. This
  changes no progress data, no progress calculation, and no backend contract.
  H2 remains unopened.
- Reader: a first visit now scrolls to the actual page-top header. Android
  counts the header as a LazyColumn item before resolving an R1 or R2 hadith
  target. iOS resets a page without a target or cached offset to its header.
  Existing cached offsets and R1/R2 target restoration keep precedence.
- Evidence: backend `npm test` passed 96 tests and `npm run typecheck` passed.
  Android JDK 21 `testDebugUnitTest assembleDebug` passed. iOS `xcodegen
  generate`, build, `TodayTests` 3/3, `ReaderR6Round3Tests` 34/34, and the focused
  `ReaderR6AUITests/testFreshVolumePageShowsItsHeaderAboveTheFirstHadith`
  passed on the current iPhone 17 Pro simulator. Android unit coverage adds a
  fresh-page header index regression. Real iOS and Android screenshots showed
  the Home rails, the source sheet, Library grid and list, Urdu translation,
  Arabic-only reading, and a fresh reader page with its volume header visible.
- External state: no backend file changed, so no Convex deployment ran. No
  dashboard, credential, store, or progress semantic changed.

### H2 Library progress and cover completion (2026-09-13)

- Library now reads a private, platform-neutral progress summary from Convex.
  The summary combines a source-outline count with the reader's latest
  semantic anchor. It returns unopened, in-progress, completed, stale, and
  unavailable states. Guests receive only public count state.
- The generated collection covers are bundled on iOS and Android. Each cover
  carries its collection name and distinct restrained Islamic geometry.
- Reader repair: zero-offset scroll snapshots no longer act as hadith-anchor
  restores. A new page therefore lands at its actual header. Nonzero cached
  offsets and explicit R1/R2 targets still win.
- Evidence: development Convex deployed successfully. A live guest query
  returned all seven source-outline totals. Backend typecheck and 96 tests,
  Android JDK 21 unit tests and debug build, and focused iOS reader and Today
  tests passed. The Android emulator showed the updated Daily label, generated
  covers, unopened progress state, and the next reader page at its true top.

### H3 Saved migration, guest folders, and proof (2026-09-13)

- Saved now has one canonical `(user, hadith)` record with independent
  bookmark, favorite, and note facets. The rollout query folds those records
  together with the three legacy tables, so shipped rollback clients can keep
  reading their existing projections while current iOS and Android callers use
  `listSavedSnapshot`. Reading progress remains the independent second
  subscription.
- Guest stores preserve their existing bookmark, favorite, note, and progress
  data. iOS adds SwiftData folder and membership models; Android adds defaulted
  JSON fields, so old local stores decode as an empty-folder state. A merge
  includes folders and folded Saved items, unions facets, chooses the newest
  note, preserves an existing server folder when the guest item is unfiled,
  and clears local data only after the mutation succeeds.
- Folder names are NFC-normalized, trimmed, limited to 64 Unicode scalar
  values, and reject control characters. Ownership is checked on assignment,
  deletion, and restore. Deletion unfiles material and returns an undo receipt;
  undo restores only memberships that have not moved since deletion.
- Evidence: `npx convex dev --once`, backend typecheck, and 98 backend tests
  passed. The deterministic representative payload fixture measured 1,433
  UTF-8 bytes for the three legacy Saved streams and 1,347 bytes for the
  unified snapshot, a 6.0% reduction. It also proves that progress is not in
  the Saved payload. iOS simulator build and `GuestMergePlannerTests`, plus
  Android JDK 21 unit/debug build, passed. Android instrumentation compiled
  but could not run because no Android device was connected.

### H3 Saved interaction refinement (2026-09-14)

- The global Saved destination and the reader's Bookmarks & Notes sheet now
  use one native Saved row per platform. The row body opens the exact hadith,
  facet icons remove only their facet, the folder button changes membership,
  and the chevron expands an inline preview. Rows retain saved-time metadata
  and show folder names only in the all-folders scope.
- Folder names select on tap and expose deletion on hold. Folder and facet
  removals use compact top undo notices. Bookmark, favorite, and note removal
  asks first by default; readers may choose `Don't ask again` and can restore
  the confirmation in Settings. Undo calls an idempotent facet-restore
  mutation rather than toggling stale state.
- Saved row context menus now include move, remove, copy, share, and suggest
  translation actions in both Saved surfaces. Daily Hadith matches the reader
  bookmark, favorite, note, copy, share, and suggestion action set; reporting
  remains absent when Daily has no reportable translation identifier.
- Evidence: development Convex deployed; backend typecheck and 98 tests passed.
  The full iOS unit suite, focused Saved shortcut UI test, and simulator build
  passed. Android JDK 21 unit tests, debug and instrumentation builds, and all
  51 emulator instrumentation tests passed, including the shared-row hit-target
   and preview fixture.

### S1 Settings and profile completion (2026-09-17)

- Settings is now a grouped root (account, reading, library, general,
  danger) with eleven finished destinations on both clients: profile,
  appearance, app language, hadith translation, reading & type, offline
  storage, notifications, subscription, privacy & data, help & support, and
  about & legal. Every row navigates or performs a real action; the
  signed-out root keeps the guest card and hides profile-only rows.
- Profile shows the Clerk avatar (AsyncImage on iOS, initial badge on
  Android), editable first/last name and username, and read-only email.
  iOS adds change-photo via `setProfileImage`; Android has no Clerk photo
  API in its SDK, so the avatar stays read-only there.
- Appearance, languages, direction, visibility, Arabic font ladder, size
  slider with preview, and the Saved confirm-removal toggle all reuse the
  F2 stores. Subscription shows tier, quota use, and expiry from
  `users:getCurrentUser`, with plans (quota paywall), restore, and store
  management actions. Offline shows real cache size, a clear-cache action,
  an O2 locked notice with an explainer sheet, and a system-storage entry;
  no dead placeholders.
- New identity-scoped `users:exportCurrentUserData` query returns only
  portable data (account summary, preferences, Saved folders/items joined
  to canonical hadith identity, reading progress, legacy rows, own
  submissions). iOS gates export behind device biometrics/passcode plus a
  valid Clerk session; Android uses an explicit confirm plus a system
  save dialog and asserts the forbidden fragments. Deletion keeps its
  separate store-subscription warning on both platforms.
- The admin queue is out of both consumer apps: iOS `AdminReviewView` and
  Android `AdminReviewSheet` deleted, `canModerate` subscriptions removed,
  and the Phase 4 UI flow now asserts the review entry is absent (E4 owns
  the secured exception tool).
- Evidence: development Convex deployed; backend typecheck and 102 tests
  passed (4 new export isolation tests). iOS 174/174 unit tests (8 new
  S1) and the new signed-out `SettingsS1UITests` navigation matrix (10
  destinations) passed on the iPhone 17 Pro simulator. Android JDK 21
  155/155 unit tests (8 new S1) passed; debug build installed on the
  hadithly emulator showed the Settings root and Offline destination with
  a real cache size. No production, credential, or store state changed.
- Next allowed session: O1. This task stopped before O1.

## Delegation policy

Use GLM-5.3-Flash through OpenCode Go as the default author for bounded sessions
whose contracts, files, and tests are explicit: F2, F3, R4, R5, R6, H1, H2, S1,
W1, W2, LA2, LA3, LA4, and the bulk of L1. These are meaningful product
sessions. Give GLM one small vertical slice at a time, require it to run both
platform tests, and end with a compact patch/evidence handoff. GPT-5.6 Luna at
medium or high is the first substitute if GLM is unavailable.

Use GPT-5.6 Terra for bounded work with migrations, lifecycle state, or several
integrations, and as a short review gate for GLM-authored patches. Use GPT-5.6
Sol for signed-in dashboards, production auth, credentials, store money,
authenticity, security boundaries, hard data migrations, concurrency, and final
release decisions. Use Sol xhigh only where the table names it. Reserve max for
a failed xhigh recovery or final security audit.

GLM may design and implement within an already approved contract, but it does
not receive authority to create or revoke credentials, submit stores, rewrite
Git history, approve religious grades or source licenses, change payment
semantics, delete user data, or waive a security gate. Those remain user actions
or Terra/Sol review gates. A review gate inspects the diff, reruns risk-focused
tests, and either accepts it or returns a narrow fix list; it does not redo the
whole session.

Use one working tree at a time. Give each task the exact session prompt. Before
switching between OpenCode and Codex, require a clean checkpoint commit or a
named stash created by the user. Never let two agents edit the same worktree.

Official OpenAI guidance names Sol as the flagship model, Terra as the balanced
model, and Luna as the efficient high-volume model. It recommends medium as the
starting effort and high or xhigh only when they improve measured quality.
ChatGPT Plus limits vary with task size and model, so check the usage dashboard
instead of budgeting by message count.

OpenCode Go currently includes GLM-5.3-Flash and GPT-5.6 Luna. Its model list and
allowances can change. As of 2026-09-02, its own estimate is about 1,580 typical
GLM-5.3-Flash requests per five-hour allowance, 3,950 weekly, and 7,900 monthly;
the service lists GLM prompts as not used for training with zero-day retention.
That makes GLM a sensible first author for the bounded sessions above, not a
second-class fallback. Run `/models` before assigning a task and never send
secrets, production data, private notes, or unpublished evidence to any model.

## Skills and tools by work type

- D0 through D4 use `computer-use:computer-use` and
  `chrome:control-chrome`. Use the signed-in browser, not a cloud task. Ask the
  user to take over for passwords, one-time codes, CAPTCHAs, financial terms,
  account creation, key creation, permission changes, publication, and
  revocation confirmation.
- F1, R1, O1, E1, E3, and Q1 use `architect`, `codebase-design`,
  `principle-foundational-thinking`, `principle-type-system-discipline`, and
  `typescript-best-practices`.
- R2 through R5 and H1 through S1 use `frontend-design`,
  `principle-experience-first`, and `principle-exhaust-the-design-space` when a
  new interaction has no settled answer.
- Patches that cross features use `blast-radius`. Hard failures use
  `diagnosing-bugs` and `principle-fix-root-causes`.
- Every implementation session ends with `principle-prove-it-works`. Web
  fallback verification may use Playwright. Native verification uses Xcode,
  `simctl`, Gradle, Android emulator tools, and physical devices where the gate
  requires them.
- Documentation uses `technical-writing`, `writing-for-agents`, and `unslop`.
- Never use Relay.

## Dependencies

```text
D0 -> G0 -> M0 -> D1 -> D2 -> D3A-ops
D2 -> D3G
D2 -> F1
D3A-domain + F2 -> F3
F1 + D3A-entitlements -> Q1
D3A-release + D3G -> D4
F1 -> F2
F1 -> R1 -> R2 -> R3 -> R4 -> R5 -> R6
R2 -> H1 -> H2 -> H3 -> S1
F1 -> O1 -> O2
F2 + F3 + R2 -> N1
N1 + R2 -> W1 -> W2
F1 -> E1 -> E2 -> E3 -> E4
Q1 + D3G -> Q2
R5 + H3 + S1 + O2 + W2 + E4 + Q2 -> LA1 -> LA2 -> LA3
D4 + LA3 -> L1 -> native launch -> LA4
```

`D3A` and `D3G` are the available-platform and Google Play release tracks of
D3. `D3A-ops` covers the domain, RevenueCat products and offering, webhook, and
app-side SDK configuration. `D3A-domain` is the live domain and association
work. `D3A-entitlements` is the backend and RevenueCat entitlement wiring.
`D3A-release` covers store agreements, compliance answers, iOS sandbox evidence,
and final release handoffs. These labels are dependency slices, not new
sessions.

Full D3 passes only after `D3A-release` and D3G pass. While either release track
is open, continue from F1 through any dependency path that does not reach D4 or
Q2. F2 and F3 may run in sequence while R1 remains unopened. After F3, follow
the listed order. Do not parallelize sessions that modify the same schema,
client navigation, or shared preference models.

## Gate rules

Every session records:

- the intended outcome and the files it changed;
- iOS behavior and Android behavior, including an explicit no-change parity
  check where applicable;
- backend, schema, API, and migration effects;
- accessibility and localization evidence;
- unit, integration, UI, visual, and runtime checks that apply;
- security and prompt-injection checks;
- dashboard changes and direct evidence;
- blockers and the next allowed session.

A build is evidence that code compiles. It is not evidence that a user journey
works. Dashboard configuration is evidence only after a direct readback and an
end-to-end request. A session cannot pass with skipped required tests, an
unreviewed migration, placeholder content, or unverified external state.

## User inputs that cannot be inferred

Collect these only when the matching session reaches the final action:

- D3A needs the legal seller name, support contact, tax and banking details,
  final territories, and store agreement acceptance.
- F3 needs proof that the user controls `hadithly.app` if D3A cannot establish
  it.
- E3 needs affirmative source licenses or permissions. Absence of a prohibition
  is not permission.
- Q2 needs approval of final regional price tiers after the plan shows store
  fees, taxes, provider cost, and contribution margin.
- L1 needs native-speaker approval for each Wave 1 locale and final store
  screenshots.

## Mistakes that still matter

- Swift and Kotlin numeric Convex arguments must use `Double` for `v.number()`.
- Android Convex calls, including subscription collection, run on
  `Dispatchers.IO`.
- Android wire numbers decode as `Double`. Reified calls name their return
  type.
- Reader targets use the same content-sized chunking algorithm as page serving.
- A deep-linked reader ignores the Android pager's synthetic initial page.
- SwiftUI's vertical `ScrollView` consumes ordinary paging gestures. The current
  reader uses a simultaneous window pan recognizer. R3 may replace it only with
  device evidence.
- Convex subscriptions opened before authentication can remain empty. Reopen
  them on every auth transition.
- Each Node-dependent Convex file needs its own `\"use node\"` directive.
- `CLERK_FRONTEND_API_URL` and Clerk's Convex integration must agree on
  `aud: \"convex\"`.
- Never expose a secret through a command argument, terminal output, screenshot,
  document, or chat. Install a tested replacement before revocation.

## Current external references

- [OpenAI GPT-5.6 model guidance](https://developers.openai.com/api/docs/guides/latest-model)
- [GPT-5.6 Sol model](https://developers.openai.com/api/docs/models/gpt-5.6-sol)
- [Codex usage with ChatGPT plans](https://help.openai.com/en/articles/11369540-codex-and-chatgpt-plan-usage-limits)
- [OpenCode Go models and limits](https://opencode.ai/docs/go/)
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing)
- [Apple Small Business Program](https://developer.apple.com/app-store/small-business-program/)
- [Google Play service fees](https://support.google.com/googleplay/android-developer/answer/112622)
- [RevenueCat pricing](https://www.revenuecat.com/pricing/)
- [Convex pricing](https://www.convex.dev/pricing)
