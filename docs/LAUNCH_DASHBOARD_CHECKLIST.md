# Phase 6 dashboard checklist

This file tracks external state. A checked box needs direct dashboard readback
or an end-to-end production result. Local files and code are not proof.

Never record a credential value here. Record the key name, provider-side ID or
last four characters when safe, installation time, test result, and revocation
state.

## Current control status

Audit date: 2026-09-02

- [x] The Codex app received a live Chrome accessibility tree and screenshot.
- [x] Chrome showed signed-in tabs for App Store Connect, Clerk, Convex,
  Firebase, and RevenueCat.
- [x] Chrome is running.
- [x] The ChatGPT extension is installed and enabled in Chrome's active Default
  profile.
- [x] The Chrome native-host manifest exists, names the expected host, and lists
  the expected extension origins.
- [x] The browser-control action channel works.
- [x] The complete Chrome control documentation loaded through the action
  channel.
- [x] Read-only inspection covered the open App Store Connect, Clerk, Convex,
  Firebase, and RevenueCat tabs.
- [x] The original Apple Developer tab remained current after the inspection.

D0 passed on 2026-09-02. The fresh local task exposed
`mcp__node_repl__js`. The Chrome browser client selected the existing Chrome
extension session and returned its complete control documentation. Read-only
tab claims returned each page's current URL, controls, and visible overview
content. The task performed no clicks, typing, navigation, refreshes, form
submissions, or dashboard changes.

D0 evidence:

- App Store Connect showed the **Apps** page. Hadithly iOS 1.0 was in
  **Prepare for Submission**.
- Clerk showed the Hadithly development instance and the production deployment
  prompt.
- Convex showed the `festive-cobra-664` development deployment health page with
  no active insight issue.
- Firebase showed project `sunnad`, the Spark plan, and the Hadithly Android
  app.
- RevenueCat showed Hadithly sandbox data, two of six setup items complete, and
  no live transactions.
- The most recent tab before and after the audit was **Certificates,
  Identifiers & Profiles - Apple Developer** at the same URL.

### D0 recovery

1. In Codex Settings > Browser, enable Developer mode and full CDP access.
2. Quit and reopen the Codex desktop app. Leave the signed-in Chrome Default
   profile open on a non-sensitive dashboard page.
3. Start a fresh **local** Hadithly task and explicitly attach the Chrome plugin
   and Computer Use. Paste only the D0 prompt from `docs/SESSION_PROMPTS.md`.
4. Ask the task to list whether `mcp__node_repl__js` is available before doing
   anything else. The skill name alone is not enough.
5. If present, bind Chrome, read its complete control documentation, inspect one
   existing dashboard page without changing state, and return to the original
   tab.

Gate: the agent can read the current URL, page controls, and dashboard content,
then return to the original tab. If a fresh task still lacks the tool, record it
as a Codex task-tool injection failure; changing the Hadithly project or Chrome
page cannot fix that layer. Reinstall the Browser plugin only if a later task
exposes the tool but extension communication fails. Do not fall back to Relay,
AppleScript, keyboard automation, or an unrelated browser.

## Confirmation boundaries

The agent prepares each dashboard action and stops immediately before:

- creating an account, API key, OAuth credential, service-account key, or other
  persistent access;
- changing cloud permissions;
- revoking or deleting a credential;
- accepting a financial or legal agreement;
- submitting a store record or public release;
- entering a password, one-time code, private key, banking detail, or other
  sensitive value;
- solving a CAPTCHA.

The user takes over for passwords, one-time codes, CAPTCHAs, and sensitive
financial forms. The agent requests action-time confirmation for the remaining
risky clicks.

## D1 credentials and push

### Firebase and FCM

Known state: project `sunnad`, project number `1028365596467`, Android app
`com.hadithly.app`, and local `android/app/google-services.json` exist. The
current Admin private key was exposed.

- [x] Enable the IAM API with a project owner.
- [x] Open service account
  `firebase-adminsdk-fbsvc@sunnad.iam.gserviceaccount.com`.
- [x] Create a replacement JSON key after action-time confirmation.
- [x] Install its `project_id`, `client_email`, and `private_key` in production
  Convex without exposing their values.
- [x] Obtain a fresh production Android token from a physical device.
- [x] Send and receive a real FCM notification.
- [x] Confirm the notification opens the expected current target behavior.
- [x] Revoke the exposed keys after the replacement test passed and after
  action-time confirmation (2026-09-03 owner-confirmed project pivot).

Evidence: replacement key ID, install time, device/build, message ID, receipt
time, target result, and old key revocation time.

2026-09-02 evidence: IAM and IAM Credentials APIs were enabled for project
`sunnad`. Replacement Firebase Admin key ending `b3f2` was created and its
three required fields were installed in production Convex at 19:14 +05. The
replacement then obtained a Firebase Messaging-scoped OAuth access token from
Google with HTTP 200, and Google Cloud showed `fcm.googleapis.com` enabled.
That key was itself revoked on 2026-09-03 after the project pivot below.

Physical-device result: a Samsung SM-A325F running Android 13 registered a
fresh identifier with Firebase project `sunnad` using Hadithly 0.1.0 (1), debug
build. FCM accepted message
`projects/sunnad/messages/0:1788371397987094%4eb5ce3f4eb5ce3f`; Android showed
the notification at 22:49 +05, tapping it cleared the notification, and
`com.hadithly.app/.MainActivity` became the resumed activity. No registration
identifier or OAuth token was printed. The debug build is recorded explicitly
because production Clerk client configuration remains a D2 prerequisite for a
launchable release build. A post-test scan of the app-process log found no
registration identifier, bearer token, private-key marker, or email address.

2026-09-03 exposure incident: during a follow-up agent session, listing
production Convex environment variables echoed the `APNS_PRIVATE_KEY` (p8,
ending `48VC`) and most of the `FCM_PRIVATE_KEY` (key `b3f2`) values into an
AI chat transcript. Both were initially treated as compromised.

2026-09-03 owner decision and Firebase project pivot: after the incident the
owner directed that the product stop using the legacy `sunnad` naming and run
on a dedicated `hadithly` Firebase project instead. Because project IDs cannot
be renamed, a new Firebase/GCP project `hadithlyapp` (name `hadithly`, project number `950157192050`, Spark
plan, Google Analytics and Gemini-in-Firebase disabled) was created with the
Android app `com.hadithly.app` and the Apple app `com.hadithly.app` registered.
The new `google-services.json` replaced `android/app/google-services.json`
(gitignored). The iOS registration is console-only: Hadithly's push goes
through APNs, not Firebase, and no Firebase SDK was added to the iOS app. A new
Admin SDK key ending `d9eb` for
`firebase-adminsdk-fbsvc@hadithlyapp.iam.gserviceaccount.com` was created and
its three fields installed into production Convex as `FCM_PROJECT_ID`,
`FCM_CLIENT_EMAIL`, and `FCM_PRIVATE_KEY` at 02:0x +05 with values never shown
in terminal output. Validation minted a Firebase Messaging-scoped OAuth token
from the installed production values with HTTP 200. With that validation and
explicit owner confirmation, both old `sunnad` service-account keys — the
historically exposed key ending `6a87` and the chat-exposed key `b3f2` — were
deleted at 02:18 +05 on 2026-09-03. Project `sunnad` is retired for Hadithly;
the owner may delete it after confirming no other product depends on it.

Consequence of the pivot: FCM device tokens are project-scoped, so the
2026-09-02 `sunnad` device-push evidence no longer describes the production
path. The Android device push gate is intentionally reopened and stays open
until a device running the new `google-services.json` receives a push. On
2026-09-03 the owner also confirmed no physical Android device is available,
so the re-test is deferred; token-mint validation is the current evidence.

### APNs

Known state: the production APNs credential reached Apple's endpoint and
returned `BadDeviceToken` for a dummy token. That proves credential acceptance,
not delivery.

- [x] Confirm the production topic is `com.hadithly.app`.
- [x] Register a physical iPhone production token.
- [x] Send and receive a real APNs notification.
- [x] Confirm foreground, background, and terminated-app behavior.

Evidence: device/build, token registration time without token value, APNs result,
receipt time, and open behavior.

2026-09-02 readiness note: the physical iPhone 16 Pro is connected, paired, in
Developer Mode, and registered with the Apple developer team. With action-time
confirmation, an Ad Hoc profile named `Hadithly D1 Ad Hoc 2026-09-02` was
created for `com.hadithly.app`, the registered iPhone, and the existing Apple
Distribution identity. A Release archive exported with that profile was
verified as distribution-signed with `aps-environment=production`, then
installed and launched on the physical iPhone. Delivery behavior remained
unchecked at that point pending notification permission and the real-device
tests. No token value or device identifier is recorded here.

Registration result: notification permission was granted and the physical
iPhone produced a structurally valid production APNs token at 23:17 +05. Apple
accepted foreground and background alert requests with HTTP 200 at 23:18 and
23:19 +05 respectively. The owner observed the foreground alert, and tapping
the background alert opened Hadithly. For the terminated test, the app process
was confirmed absent before Apple accepted the alert with HTTP 200 at 23:29
+05; tapping it launched the Hadithly process. No token, JWT, or personal device
identifier is recorded. The compile-time D1 probe was removed afterward;
backend type-checking and a normal iOS simulator build passed.

2026-09-03 clean-build reinstall: the probe build was replaced with a clean
Ad Hoc export of the current source (`Hadithly D1 Ad Hoc 2026-09-02` profile,
Apple Distribution signature, verified `aps-environment=production`). The first
clean build crashed at launch: `AppConfig` hit its `fatalError` because
`Production.xcconfig` had no `CLERK_PUBLISHABLE_KEY` — production Clerk is a D2
prerequisite for a fully configured release build. An interim
`ProductionSecrets.xcconfig` (gitignored) was created with the dev Clerk
publishable key and an intentionally empty RevenueCat key; the installed build
now launches and stays running. Two hardening changes are permanent:
`PurchaseManager` rejects RevenueCat `test_`-prefixed keys in every
configuration, and `ProductionSecrets.xcconfig` is the documented pre-archive
step. The interim dev Clerk key must be replaced when D2 provisions the
production Clerk instance.

2026-09-03 APNs key rotation: a new APNs auth key `MU78HDD896` (named
`Hadithly D1 20260903`) was created in team `6378AFQPXV` after action-time
confirmation, configured as Sandbox & Production, Team Scoped (All Topics),
and its `.p8` downloaded once. `APNS_KEY_ID` and `APNS_PRIVATE_KEY` were
installed into production Convex at 02:5x +05 with the p8 body piped through a
script and never shown in terminal output. Validation read the installed
production values in-process, signed an ES256 provider JWT, and POSTed to
`api.push.apple.com` for topic `com.hadithly.app` with a dummy device token:
Apple returned HTTP 400 `BadDeviceToken`, which proves credential and topic
acceptance without a real device token. iOS delivery gates had already passed
on 2026-09-02 and are unaffected by the signing-key swap.

2026-09-03 owner waiver on revoking `48VC`: the old key `C63UYB48VC` (named
`adat`, Team Scoped, Production, also carrying Sign In with Apple for the
legacy bundle `6378AFQPXV.com.arystan.almasuly.sunnad`) is shared with the
owner's separate `adat`/`sunnad` projects, which still depend on it. The owner
therefore directed that it stay active. The chat-transcript exposure is
accepted by the owner as self-contained (local transcripts, single user), and
its future rotation or revocation belongs to those projects, not to this
repository. Hadithly's production Convex no longer references it.

### Sunnah.now and Gemini

Scope note: on 2026-09-02 the owner removed Sunnah.now rotation from this D1
run. Its credential was not read, installed, or revoked; the unchecked items
below remain intentionally open rather than being treated as passed.

- [ ] Rotate the historically exposed Sunnah.now key.
- [ ] Install only the replacement as `SUNNAH_NOW_API_KEY` in production Convex.
- [ ] Complete one production provider read.
- [x] Create or rotate the Gemini key and restrict it to the intended project and
  API where supported.
- [x] Confirm production data-use and model settings.
- [x] Install only the replacement as `GEMINI_API_KEY` in production Convex.
- [x] Complete one labeled production AI translation.
- [x] Revoke old credentials after the tests passed (2026-09-03, owner-confirmed).

2026-09-02 evidence: a clean replacement Gemini credential named
`Hadithly D1 replacement 2026-09-02` was created in project
`gen-lang-client-0557645035`, bound to the dedicated service account,
restricted to Gemini API, and installed in production Convex at 19:14 +05. The
older key remains active pending the provider-read and labeled-translation
gates. Apple Developer and production Convex both show APNs topic
`com.hadithly.app`; physical-device production delivery and open behavior pass.

Gemini readiness note: AI Studio shows the Hadithly project on the free tier
with API logging disabled. Current backend code selects the stable
`gemini-2.5-flash-lite` model. Google's current terms allow unpaid-service input
and output to be used for product improvement and require paid service for API
clients available in the EEA, Switzerland, or the United Kingdom. No production
AI smoke was run under the free-tier setting. Production Convex also lacks the
current `actions/ai` and provider actions; a production function-spec check at
23:31 +05 confirmed that the older public submission mutation only accepts an
already-produced AI review. Deploying the current provider actions belongs to
D2, so it cannot honestly satisfy either remaining D1 smoke gate.

2026-09-03 deployment and smoke result: the owner explicitly authorized
deploying the current backend to production ahead of D2 to close the D1 smoke
gates. The current Convex code (type-checked, additive schema indexes only) was
pushed to production deployment `giddy-ox-648` with `CLERK_FRONTEND_API_URL`
set (public Clerk domain, same value as the existing issuer-domain variable).
The push removed the legacy `translationVotes` table (public voting is banned
by the product rules) and a one-off mutation stripped legacy `upvotes`,
`downvotes`, and `ratingPercent` fields from the single affected `translations`
document; the transitional validator widening and the patch function were
removed afterward. A temporary internal smoke action then ran against
production: Gemini returned a labeled AI translation ("Indeed, actions are only
by intentions.") using the production `GEMINI_API_KEY` replacement, and the
production FCM credentials minted a Firebase Messaging OAuth token with HTTP
200. The smoke action was removed and a clean deployment pushed immediately
after. Sunnah.now has no key installed in production, so its provider-read gate
remains open as a waived item alongside its waived rotation.

2026-09-03 revocation evidence: with the production `GEMINI_API_KEY`
replacement (`...BKZw`, named `Hadithly D1 replacement 2026-09-02`) already
validated by the labeled production translation, the old key ending `odK4`
(named `Hadithly`, created 2026-05-24, restricted to the Gemini API in project
`gen-lang-client-0557645035`) was deleted at 02:30 +05 on 2026-09-03 through
Google Cloud Credentials after AI Studio's own delete flow failed repeatedly;
the deleted credential can no longer make API requests. The Sunnah.now
rotation remains waived by the owner with no key installed in production.

D1 gate status after the 2026-09-03 run: Firebase Admin and Gemini rotations
are complete with old keys revoked; the APNs replacement is installed and
Apple-validated. Open items carried forward: the Android FCM device-push
re-test (deferred — no physical Android device; required because the FCM
project moved to `hadithlyapp`), and the owner-waived `48VC` key, which stays
active under the separate `adat`/`sunnad` projects. Sunnah.now remains waived.

## D2 production Clerk and Convex

### Clerk

Known state: the development instance supports Apple, Google, and email code.
It still requires generated username and password compatibility values. A usable
production instance is not connected.

- [ ] Create or select the production Hadithly instance.
- [ ] Enable Apple, Google, and email verification code.
- [ ] Disable required username and password.
- [ ] Keep self-deletion enabled.
- [ ] Activate Clerk's Convex integration and confirm `aud: "convex"`.
- [ ] Record the production frontend API URL as
  `CLERK_FRONTEND_API_URL` in production Convex.
- [ ] Install the public `pk_live` values in the two gitignored production client
  configuration files.
- [ ] Verify sign-up, sign-in, restore, sign-out, and deletion for all three
  methods where the provider supports the platform.

### Convex production

Target: `giddy-ox-648` at
`https://giddy-ox-648.eu-west-1.convex.cloud`.

Required variable names:

- `CLERK_FRONTEND_API_URL`
- `SUNNAH_NOW_API_KEY`
- `GEMINI_API_KEY`
- `REVENUECAT_WEBHOOK_SECRET`
- `APNS_KEY_ID`
- `APNS_TEAM_ID`
- `APNS_PRIVATE_KEY`
- `APNS_ENVIRONMENT`
- `APNS_TOPIC`
- `FCM_PROJECT_ID`
- `FCM_CLIENT_EMAIL`
- `FCM_PRIVATE_KEY`

- [ ] Confirm every required name exists without printing its value.
- [ ] Deploy the current schema and functions after Clerk and provider values are
  valid.
- [ ] Confirm unauthenticated user-scoped requests fail.
- [ ] Confirm signed-out public reading works.
- [ ] Confirm authenticated sync and guest merge work.
- [ ] Confirm one provider read and one AI translation work.
- [ ] Confirm the RevenueCat webhook rejects bad authorization.
- [ ] Confirm account deletion removes the promised Convex and Clerk data.

D2 gate: production auth, public reading, private sync, provider calls, and
deletion pass on release builds.

## D3 domain, stores, RevenueCat, and policies

### Domain and public pages

- [ ] Prove control of `hadithly.app`.
- [ ] Configure DNS and HTTPS.
- [ ] Publish privacy, support, and canonical fallback pages.
- [ ] Record the final public URLs in store metadata.
- [ ] Configure Apple Universal Links and Android App Links prerequisites for F3.

### RevenueCat

- [ ] Remove the weekly package from the planned production offering.
- [ ] Create or connect monthly and annual App Store products.
- [ ] Create or connect monthly and annual Play products.
- [ ] Attach all four platform products to `pro` and the current offering.
- [ ] Configure
  `https://giddy-ox-648.eu-west-1.convex.site/webhooks/revenuecat`.
- [ ] Set its Authorization value from the existing Keychain item without
  revealing it.
- [ ] Install production public SDK keys in the two gitignored release configs.
- [ ] Verify purchase, restore, cancellation, grace, expiration, refund or
  revocation, and quota retry on both store sandboxes.

### App Store Connect

- [ ] Finish the app record for `com.hadithly.app`.
- [ ] Confirm the SKU, categories, version, copyright, and public URLs.
- [ ] Create the subscription group and monthly and annual products.
- [ ] Complete agreements, tax, and banking with user takeover.
- [ ] Complete privacy, age rating, content rights, encryption, export,
  availability, and release-mode answers.
- [ ] Add an App Review account and exact quota-paywall instructions.
- [ ] Keep screenshots open for L1.

### Google Play Console

- [ ] Create or finish the app record for `com.hadithly.app`.
- [ ] Complete developer profile, agreements, payments profile, and tax details.
- [ ] Create monthly and annual subscriptions and base plans.
- [ ] Complete Data safety, content rating, target audience, app access, ads,
  content rights, privacy URL, and account-deletion URL.
- [ ] Configure internal testing and upload a signed release artifact when the
  user authorizes the submission.
- [ ] Add test accounts and purchase-license testers.
- [ ] Keep final screenshots and localized listings open for L1.

D3 gate: the domain, policies, store records, product IDs, RevenueCat offering,
and webhook work. Only design-sensitive screenshots and final release submission
remain.

## D4 production matrix

Record the date, app build, OS version, account state, expected result, actual
result, evidence path, and cleanup for every row.

### Both platforms

- [ ] Fresh install and signed-out onboarding.
- [ ] Signed-out collection and reader access.
- [ ] Apple, Google, and email-code authentication where supported.
- [ ] Guest bookmark, favorite, note, and progress merge.
- [ ] Cross-device sync.
- [ ] Provider read and AI translation with source label.
- [ ] Free quota failure opens the paywall and no other route does.
- [ ] Purchase and restore activate `pro`.
- [ ] Cancellation keeps access until expiry.
- [ ] Grace keeps access. Expiry or revocation removes access.
- [ ] Daily push arrives and opens the target.
- [ ] Account deletion removes app data and the Clerk identity while preserving
  the store's independent subscription state.
- [ ] Production logging contains no token, email, private key, note, or proposal
  content beyond the documented policy.

### Storage smoke test

- [ ] Upload a harmless private test file through the chosen production Convex
  storage path.
- [ ] Read it through authorized code.
- [ ] Reject an unauthorized read.
- [ ] Delete the test artifact after action-time confirmation.
- [ ] Record storage and egress observations without user content.

D4 gate: every required row passes on a physical iPhone and Android device. Mark
Phase 6 complete in `docs/PLAN.md` only after this gate.
