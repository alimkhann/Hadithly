# Hadithly master plan

This file is the source of truth for sequencing and product decisions. Read it
before any Hadithly session. Then open the matching standalone prompt in
`docs/SESSION_PROMPTS.md`.

Last updated: 2026-09-04. Phases 0 through 5 are complete. Phase 6 code is
implemented; its production dashboard gate is open. Sessions D0, G0, M0, D1,
and D2 are complete; D3A is in progress. D3G is explicitly deferred by the
owner until a Play Console developer account is available. D3 cannot pass until
both subgates pass, but D3G does not block F1 or its product-work branches.
D2's social sign-in runs through Clerk hosted
auth, and the username contract is now: optional, auto-generated from the
email local part at password sign-up, editable in Settings. The Android FCM
device-push re-test deferred from D1 folds into D4's physical-device matrix.

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

The design uses System, Light, Paper, and Dark themes. Emerald remains the
single general accent. Bookmark and favorite colors appear only where their
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
| D3A | Finish the domain, policies, App Store Connect, iOS products, RevenueCat webhook, and iOS sandbox work. | No non-Google, non-screenshot dashboard blocker remains; real iOS monthly and annual purchases reach `pro`. | GPT-5.6 Sol, high |
| D3G | Finish Play Console, Android products, Android App Links, and Android store sandbox work. Deferred until the owner has a Play Console developer account. | No Google Play dashboard blocker remains; real Android monthly and annual purchases reach `pro`. | GPT-5.6 Sol, high |
| D4 | Run the production launch-system matrix on physical iPhone and Android devices. | The signed evidence matrix passes. Phase 6 becomes complete. | GPT-5.6 Sol, xhigh |
| F1 | Add canonical content identity, authenticity scope, license records, and eligible daily selection. | Migration fixtures prove that no grade or scope is invented. | GPT-5.6 Sol, xhigh |
| F2 | Add UI locale, translation locale, direction, theme, and visibility preference contracts. | Both clients decode, persist, sync, and reject an all-hidden state. | GLM-5.3-Flash; Terra high review |
| F3 | Ship `hadithly.app` landing, fallback pages, and native link resolution. | Installed, uninstalled, malformed, stale, and signed-out links pass. | GLM-5.3-Flash; Terra high review |
| R1 | Add semantic reading positions and a compatibility migration. | Old progress migrates and new positions survive a pagination-version change. | GPT-5.6 Sol, xhigh |
| R2 | Restore exact position from Continue Reading, Saved, Today, links, notifications, and widgets. | Every entry point lands on the expected anchor and offset on both apps. | GPT-5.6 Terra, high |
| R3 | Correct paging direction, long-content scrolling, and page boundaries. | LTR, RTL, mixed-script, short, and very long fixtures pass on both apps. | GPT-5.6 Sol, xhigh |
| R4 | Add visibility, fonts, sizes, themes, hidden controls, and progress UI. | Screenshot and accessibility matrices pass on both apps. | GLM-5.3-Flash; Terra high review |
| R5 | Add contents navigation and native context actions; enable sharing through F3. | Actions remain reachable with controls hidden and never obscure reading. | GLM-5.3-Flash; Terra high review |
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

## Delegation policy

Use GLM-5.3-Flash through OpenCode Go as the default author for bounded sessions
whose contracts, files, and tests are explicit: F2, F3, R4, R5, H1, H2, S1,
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
D0 -> G0 -> M0 -> D1 -> D2 -> D3A
D2 -> D3G
D2 -> F1
D3A + D3G -> D4
F1 -> F2
F2 + D3A -> F3
F1 -> R1 -> R2 -> R3 -> R4 -> R5
R2 -> H1 -> H2 -> H3 -> S1
F1 -> O1 -> O2
F2 + F3 + R2 -> N1
N1 + R2 -> W1 -> W2
F1 -> E1 -> E2 -> E3 -> E4
F1 + D3A -> Q1
Q1 + D3G -> Q2
R5 + H3 + S1 + O2 + W2 + E4 + Q2 -> LA1 -> LA2 -> LA3
D4 + LA3 -> L1 -> native launch -> LA4
```

`D3A` and `D3G` are the available-platform and Google Play subgates of D3. D3
passes only after both pass. While D3G is deferred, continue from F1 through
any dependency path that does not reach D4 or Q2. F2 and F3 may run in sequence
while R1 remains unopened. After F3, follow the listed order. Do not parallelize
sessions that modify the same schema, client navigation, or shared preference
models.

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
