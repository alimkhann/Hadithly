# Hadithly master plan

This document is the single source of truth for the rebuild. Read it at the
start of any session. It answers: what is this, what exists, what is next,
and what already went wrong so you do not repeat it.

Last updated: Phase 5 Android feature parity implemented and emulator-verified;
live FCM registration awaits Firebase project credentials.

## What Hadithly is

A native mobile app for reading the seven major hadith collections in the
reader's language. Arabic text plus a translation, nothing louder than that.

Three product rules override every other consideration:

1. No competition. No leaderboards, public votes, ratings, reputation,
   streaks, or badges. Translation quality comes from AI review plus admin
   approval. Reading progress stays private.
2. Reading works signed out. An account only adds sync. Onboarding must
   never gate the reader behind signup.
3. AI translations are labeled as AI, grounded in cited sources, and never
   presented as authoritative. The paywall appears only when a user hits
   the free AI quota, never as a nag.

## Repository map

```
backend/          Convex-only backend. The one server.
  convex/schema.ts          all tables (no vote/rating/leaderboard tables)
  convex/actions/           "use node" files: sunnahData (Sunnah.now), ai (Gemini)
  convex/http.ts            RevenueCat webhook (POST /webhooks/revenuecat)
  convex/lib/sunnahNow.ts   provider adapter, ported from the legacy package
  convex/lib/identity.ts    requireIdentity(): clerkId = identity.subject
ios/              SwiftUI app (iOS 17+), generated with xcodegen
  project.yml               edit this, never project.pbxproj; run xcodegen
  Secrets.xcconfig          gitignored: CONVEX_URL, CLERK_PUBLISHABLE_KEY
  Hadithly/App/             HadithlyApp, AppEnvironment, RootView
  Hadithly/Core/Theme/      design tokens (Theme.swift)
  Hadithly/Features/        one folder per feature
android/          Compose app (minSdk 26), mirrors the iOS feature folders
  gradle/libs.versions.toml version catalog
  secrets.properties        gitignored: convex.url, clerk.publishableKey
  app/src/main/kotlin/com/hadithly/app/
    core/{data,push,session,theme,settings}  Convex repo, guest store, FCM, tokens
    features/{onboarding,auth,today,library,saved,reader,settings}
legacy/           the old Expo/Next.js monorepo. Reference only. Do not build on it.
docs/PLAN.md      this file
```

Dev deployment: festive-cobra-664 (eu-west-1). Production: giddy-ox-648,
created during the legacy build, still empty of the new schema.

## Architecture

Clients (SwiftUI now, Compose in Phase 5) talk only to Convex through the
official clients. Clerk issues the JWT; Convex validates it through
`auth.config.ts`. Sunnah.now and Gemini are called only inside Convex
actions, with keys in Convex env vars. Users never pass a userId; every
user-scoped function resolves identity from the token.

Why Convex stayed: free tier covers an MVP, realtime subscriptions replace
client cache logic, scheduled functions replace cron endpoints, and the
legacy build already had working data modeling we could keep.

Costs at MVP scale: Convex free, Clerk free to 10k MAU, Gemini flash-lite
pennies, RevenueCat free under $2.5k MRR. Total: $0 until real traction.

## Design language

The reference is the Sajda Quran app (screenshots in
`legacy/docs/design-prototype/uploads/`). The direction, stated once so
every session builds the same app: a quiet book in a dark room.

- Canvas: `#0D0D0D`. Surfaces: `#1A1A1A` and `#2A2A2C`. Defined in
  `ios/Hadithly/Core/Theme/Theme.swift`; always use Theme tokens, never raw
  colors in views.
- One accent: emerald `#10B981`, used for selection, progress, and the
  primary button. Bookmark amber and favorite pink exist only on their own
  actions. Nothing else gets color.
- The reader hides chrome. A tap toggles controls. Arabic sits centered
  with a numbered medallion. Translation follows below in a plain readable
  face. Floating pills show page and volume. Navigation lives in bottom
  sheets: saved items, index, reader settings.
- Motion is small and physical: sheets slide, toggles spring, pages settle.
  No confetti, no bounce, no marketing animation.
- Typography is the product. Arabic gets a proper naskh-compatible face at
  generous size with real line height. UI text uses the system face and
  stays out of the way. Dynamic Type must work everywhere.
- Avoid the generic AI look: no purple gradients, no glassy card grids, no
  rounded-everything sameness. If a screen would look at home in a template
  app, redesign it.

## Phases

| Phase | Scope | Status |
| --- | --- | --- |
| 0 | Archive legacy, Convex-only backend, SwiftUI scaffold, onboarding shell | done, verified |
| 1 | Auth (Apple, Google, email) + guest mode + user sync | done, verified |
| 2 | Reader core: pagination, chrome toggle, AI translation on demand | done, verified |
| 3 | Tabs: Today, Library, Saved, Settings; push notification setup | done, verified |
| 4 | Translation submissions with AI review and admin approval | done, verified |
| 5 | Android (Compose) port | done, emulator-verified except live FCM provisioning |
| 6 | RevenueCat paywall, App Store prep, CI | not started |

Each phase ends with a gate: the feature works on the simulator, tests pass
where logic exists, and the work is committed. Do not start a phase before
the previous gate passes.

### Phase 1 detail (done, 2026-08-30)

Sign-in screen with three methods (Apple, Google, email code), all through
ClerkKit custom flows so the UI stays ours. After sign-in the app calls
`users:ensureCurrentUser` and then `guestMerge:mergeGuestData`, which merges
the guest's SwiftData bookmarks and notes into Convex and clears the local
store. The merge is idempotent: re-sent items are skipped, and note conflicts
keep the newer `updatedAt`. Merge planning lives in
`ios/Hadithly/Core/GuestData/GuestMergePlanner.swift` with unit tests in
`GuestMergePlannerTests`.

Clerk ↔ Convex auth: the **Convex integration must be activated in the Clerk
dashboard** (dashboard.clerk.com/apps/setup/convex). It adds `aud: "convex"`
to session tokens, which is what `applicationID: "convex"` in
`auth.config.ts` validates. The Convex env var is `CLERK_FRONTEND_API_URL`
(not CLERK_JWT_ISSUER_DOMAIN). The app points at the dev instance
`warm-yeti-51.clerk.accounts.dev` and dev deployment festive-cobra-664.

Verified end to end on the simulator with UI automation: onboarding as guest,
guest data persisted across relaunches, email-code sign-in (dev test address
`+clerk_test` with code 424242), `ensureCurrentUser` creating the user row,
merge into Convex confirmed via `npx convex data`, idempotent re-merge, local
clear, sign-out. Installed on the connected iPhone (team 6378AFQPXV,
automatic signing) and launched.

Still pending for full parity of all three buttons:

- Clerk dashboard: enable the **Apple** provider (needs a Services ID + signing
  key from the Apple Developer console) and the **Google** provider (Google
  Cloud OAuth client, or Clerk's shared dev credentials for development).
  Both buttons are wired and will work once the providers exist.
- Clerk instance currently requires username + password at sign-up, which
  email-code sign-up cannot satisfy from the UI; the app auto-fills generated
  values (`fulfillMissingRequirements` in SignInView). Cleaner: in Clerk
  dashboard set Username = off and password = optional, then that code path
  never runs.
- Sign in with Apple on device needs the Apple ID signed in on the device.

Physical device install: the project uses automatic signing with
DEVELOPMENT_TEAM=6378AFQPXV (the free personal team had no Xcode account and
cannot use the Sign in with Apple entitlement). CLI builds must run with the
login keychain unlocked (`errSecInternalComponent` otherwise), or build from
Xcode.

### Phase 2 detail (done, 2026-08-31)

Reader built over live Sunnah.now data through the existing Convex actions.
`LibraryView` (ios/Hadithly/Features/Reader/LibraryView.swift) lists the seven
collections and opens the reader full screen; the reader's close chevron is
the exit — there is no edge-swipe back. `ReaderModel` loads the volume
outline through `getCollectionOutline`, then pages hadiths through
`getReaderPage` and prefetches one page ahead. Chrome (top bar with close /
contents / settings, bottom pills with volume + page) toggles on tap.

Swipe paging does NOT use TabView or a SwiftUI DragGesture — a vertical
ScrollView inside any pager swallows horizontal pans and the swipe dies. It
is a window-level `UIPanGestureRecognizer` (WindowSwipeRecognizer in
ReaderView.swift) that recognizes simultaneously, never cancels touches, and
only acts on horizontal-dominant drags; vertical scrolling inside a page
stays native.

Volume reads are now cache-first in `getReaderPage`: the first visit to a
volume fetches it whole (new `fetchVolumeHadiths` in sunnahNow.ts), upserts
every hadith into the `hadiths` table (new index
`hadiths.by_collection_volume`), and all later page turns are served from
the Convex cache via `hadiths:listByVolume`, chunked with the same
`chunkReaderHadiths` so page boundaries match the provider path.

AI translation: for non-English languages the reader auto-translates the
current page's hadiths sequentially through `actions/ai:translateHadith`,
with per-hadith states (loading / loaded / quota / sign-in needed / failed
+ retry). Every AI translation carries an "AI · sources" badge that opens a
citations sheet (translation, source reference URL, grounding citations,
model disclaimer). Guests see a quiet sign-in notice; the quota wall shows a
quiet notice and stops further calls on the page. Reader settings (bottom
sheet) switch translation language (resets and reloads translations) and
Arabic type size (AppStorage `reader.arabicFontSize`). English reading uses
the provider's englishText with no AI involvement.

Verified on the simulator with UI automation: collection open, chrome
toggle, swipe forward/back (pill page counts correct), volume switch from
the contents sheet, Russian AI translation loading live from Gemini with
label + glossary notes, citations sheet, close back to Library. 20 unit
tests pass (including ReaderModelsTests for wire decoding and
quota/sign-in error classification). `npm run typecheck` and `npx convex
dev --once` clean.

### Phase 3 detail (done, 2026-08-31)

The four tabs are live. **Today** shows the daily hadith (deterministic
per-UTC-date pick over the cached `hadiths` table via
`actions/daily:getDailyHadith`; every reader sees the same hadith the same
day) plus a private continue-reading card. **Library** lists the seven
collections with cached volume/hadith counts from `collectionOutlines`
(realtime subscriptions; collections never opened show no counts) and a
continue-reading shortcut. **Saved** shows Bookmarks / Favorites / Notes
cards that open bottom sheets in the Sajda style; rows show reference,
Arabic snippet, and note text, tap reopens the reader at that exact hadith,
and items can be removed. **Settings** holds account, Arabic type size
(with live Arabic preview), translation language, and the daily hadith
notification toggle + time.

Personal data wiring: signed-in users get bookmarks, favorites, notes, and
reading progress through realtime Convex subscriptions
(`library:list*Detailed` queries join the hadith so lists render in one
round trip); guests use SwiftData (`GuestFavorite` and
`GuestReadingProgress` models added, plus display metadata captured on
save). The reader has a quiet per-hadith action row (bookmark amber,
favorite pink, note) with a note editor sheet, and saves private progress
on every page turn and on close. Reader deep links accept
volumeId + hadithNumber; `getReaderPage` resolves the containing page via
`targetHadithNumber`, skipped pages load on demand when swiped back onto.
`guestMerge:mergeGuestData` now also merges favorites and reading progress
(latest-wins per collection), idempotently as before.

Push: the app registers APNs (`Core/Push/PushNotificationManager.swift`,
aps-environment entitlement added) and upserts the token via
`library:savePushToken` (deduped by token, prefs never clobbered). Settings
toggle + time persist through `library:setDailyNotification`. The cron
(`crons.ts`, every 15 min) calls `actions/daily:sendDueDailyPushes`, which
sends within each token's local-time window (tz offset stored per token,
`lastSentDate` guards double sends) via `lib/apns.ts` (ES256 JWT + HTTP/2).
It is a no-op until the APNS_* env vars are set:
`APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_PRIVATE_KEY` (p8 PEM),
`APNS_ENVIRONMENT` (sandbox default), `APNS_TOPIC` (defaults to
com.hadithly.app). The p8 key must be created in the Apple Developer
portal; simulator push registration and delivery work with sandbox.

Verified on the simulator with UI automation as guest and signed in
(email code 424242): daily hadith card opens the reader at the right
volume/page, bookmark/favorite/note toggles round-trip through Convex and
appear in Saved sheets, continue-reading card restores the exact position,
guest data lives in SwiftData and merges on sign-in ("Merged 0 bookmarks,
1 favorites, 0 notes. Restored 1 reading positions."), notification toggle
registers a real APNs token into `pushTokens`, and the cron action runs
clean (no-op until APNs keys). 23 unit tests pass, `npm run typecheck` and
`npx convex dev --once` clean.

### Phase 4 detail (done, 2026-08-31)

Translation contributions now live inside each hadith block rather than in a
social/community tab. **Suggest translation** opens a focused editor for the
reader's current language and calls `actions/ai:submitTranslation`; Gemini
checks meaning fidelity and terminology, then the sheet shows the contributor
the private verdict and review notes. Recommendations are deliberately limited
to `approve`, `admin_review`, and `reject` — there is no community-review,
voting, ranking, reputation, or public-stat path.

Stored AI/community translations also expose a quiet **Report** action. It
calls `actions/ai:reportTranslation` with the actual translation row id, trims
and validates the private reason, and confirms delivery without turning the
report into a vote or rating.

Admin approval is server-authorized. `users.isAdmin` can only be assigned with
the internal `community:setAdmin` dashboard/CLI function; the app observes
`community:canModerate` and reveals a minimal Settings review queue only to
admins. The queue comes from `community:listPendingSubmissions`, and approval
calls the authenticated `community:approveSubmission` mutation. Approval is
idempotent, writes `adminAuditLog`, demotes the prior default without deleting
it, and publishes the approved community text as the new default. The reader
labels it **Community · admin approved**, never as AI.

Verified end to end on the Adat iPhone 17 Pro simulator with the dedicated
`Phase4Live` XCUITest scheme: open Bukhari, select Russian, submit a proposal,
receive and display Gemini's verdict, file a private report, approve from the
admin queue, reopen the reader, and observe the approved community default.
The test kept screenshots for the verdict, report confirmation, empty admin
queue, and community badge; Convex rows were confirmed for the approved
submission, open report, live default translation, and admin audit entry.
24 unit tests pass, `npm run typecheck` and `npx convex dev --once` are clean.
The live scheme intentionally calls Gemini and mutates the dev deployment, so
it is separate from the normal `Hadithly` unit-test scheme.

### Phase 5 detail (done, 2026-08-31; FCM provisioning pending)

The Android app lives in `android/` (applicationId `com.hadithly.app`,
minSdk 26, target/compileSdk 36). Toolchain: AGP 9.3.1 (built-in Kotlin),
Gradle wrapper 9.7.1, Kotlin 2.4.10, Compose BOM 2026.06.01. Secrets come
from gitignored `android/secrets.properties` (`convex.url`,
`clerk.publishableKey`), read into BuildConfig by `app/build.gradle.kts`.

Stack: Clerk Android SDK (`clerk-android-api` 1.1.4) + `clerk-convex-kotlin`
0.15.0 (`createClerkConvexClient` → `ConvexClientWithAuth<String>`,
authState as StateFlow) + `android-convexmobile` 0.8.0. Structure mirrors
iOS: `core/data` (ConvexRepository, wire models, GuestDataStore + planner,
UserLibraryModel), `core/session` (SessionManager = iOS AppEnvironment),
`features/` (onboarding, auth, today, library, saved, reader, settings), tokens in
`core/theme/Theme.kt` synced with iOS Theme.swift.

The four Material destinations now match iOS behavior without cloning iOS
navigation chrome. **Today** calls `actions/daily:getDailyHadith` and adds the
private continue-reading card. **Saved** has Sajda-style Material bottom
sheets for bookmarks, favorites, and notes; joined rows carry an Arabic
snippet and exact reader target. Guest drafts retain the same display and
target metadata and merge idempotently on sign-in. The reader now includes
the contextual contribution/report row: `actions/ai:submitTranslation`
returns a contributor-private Gemini verdict, and
`actions/ai:reportTranslation` confirms a private, non-voting report.
Settings observes `community:canModerate` and exposes the live approval queue
only to authorized users.

Android push uses Firebase Messaging. The app conditionally enables the
Google Services plugin when gitignored `android/app/google-services.json` is
present, creates the `daily_hadith` notification channel, requests the Android
13+ notification permission from the daily toggle, and upserts the current FCM
Firebase Installation ID through `library:savePushToken` with
`platform: "android"`. Toggle/time changes
call `library:setDailyNotification`. The scheduled backend dispatch stays
platform-neutral at the data boundary and routes each token to APNs or FCM;
FCM HTTP v1 credentials are `FCM_PROJECT_ID`, `FCM_CLIENT_EMAIL`, and
`FCM_PRIVATE_KEY`. APNs and FCM can be configured independently.

Verified on an Android 16 emulator with UI automation: onboarding
(welcome → language), Library with live cached counts from
`collections:getOutline` subscriptions, reader over live Sunnah.now data
(paging pill counts correct, swipe turns, chrome toggle, contents sheet
with volume switch, settings sheet), guest translation wall ("Sign in to
get AI translations"), guest bookmark + note, email-code sign-in (dev test
`+clerk_test` / 424242) with automatic sign-up fallback (Clerk still
requires username+password; generated values fill it like on iOS),
`users:ensureCurrentUser`, `guestMerge:mergeGuestData` ("Merged 1
bookmarks … 1 notes"), local store cleared, session restored across
relaunch, and the reader serving the admin-approved Russian community
default with the "Community · admin approved" badge.

The continued parity pass verified, as guest and signed in (email code
424242), the live daily card, private Continue Reading, guest bookmark /
favorite / note / progress persistence, sign-in merge and local-store clear,
all three Saved sheets, and exact-hadith reader reopening. A signed-in Russian
proposal received and displayed the live Gemini verdict, a private report was
stored, and a temporarily authorized test moderator saw the pending queue,
approved it, and watched the realtime queue become empty; the temporary admin
flag was then revoked. Backend rows confirmed the approved submission and
open report. 16 Android unit tests pass; `npm run typecheck`, `npx convex
dev --once`, and `assembleDebug` are clean.

Live FCM token registration, toggle delivery, and scheduled notification
delivery could not be exercised in this checkout because
`android/app/google-services.json` and the FCM service-account env vars have
not been provisioned. The build deliberately reports this state in Settings
and disables the toggle instead of shipping placeholder Firebase resources.

Phase 5 mistakes already made, do not repeat:

- The Convex Android client's uniffi FFI calls (`action`, `mutation`,
  `subscribe` registration) BLOCK the calling thread until the RPC
  completes. Calling them on Main ANRs the app. Run every Convex call on
  `Dispatchers.IO` — including subscription collection, not just actions.
- Convex numbers arrive as floats (`7.0`) on the Android wire; `Int`
  fields fail to decode. Wire-model numeric fields must be `Double`.
- Kotlin→Convex encodes Int/Long as the `$integer` wrapper, which
  `v.number()` validators reject (same trap as iOS) — pass numbers as
  `Double`.
- `mutation<T>`/`action<T>` are reified; the no-type overload decodes
  `Unit?` and fails when the backend returns a value
  (`users:ensureCurrentUser` returns the user id string → use
  `mutation<String>`).
- With edge-to-edge, the reader chrome must pad with `statusBarsPadding()`
  or its buttons sit under the status bar, which swallows their taps.
- Clerk sign-up fallback: the failure message is "Couldn't find your
  account." — match that (plus "not found"/"doesn't exist") before
  switching to the sign-up path.
- The published `clerk-convex-kotlin` 0.15.0 POM pins clerk-android-api
  1.0.36 but works with 1.1.4; `Clerk.userFlow` is typed non-nullable, so
  sign-in state comes from `Clerk.sessionsFlow` instead.
- Reader pages are content-sized, not `index / pageSize` chunks. Exact-hadith
  target resolution on the backend must call the same `chunkReaderHadiths`
  algorithm used to serve pages or Saved/Today links land on the wrong page.
- Compose's pager emits a synthetic initial page 0. Drop that first settled
  emission for deep links, scroll the visual pager when the resolved page
  arrives, and give each reader open a fresh ViewModel key so an old reader
  cannot overwrite a new target.
- Save progress when the initial/deep-linked page resolves, not only after a
  swipe; otherwise opening and closing a hadith never creates Continue
  Reading.
- Both clients send timezone offsets as `UTC - local` (JavaScript
  `Date.getTimezoneOffset` convention). The cron must subtract that value to
  derive local time. Keep `platform` only on push-token storage/dispatch;
  shared daily-hadith and reader payloads remain platform-neutral.

## Mistakes already made, do not repeat

- Convex action handlers that use `api` or `internal` need explicit return
  type annotations, or TypeScript hits circular inference (TS7022).
- `getUserIdentity()` is sync in queries and mutations, a Promise in
  actions. `requireIdentity` awaits, which handles both.
- `ConvexClientWithAuth` is generic. With Clerk it is
  `ConvexClientWithAuth<String>` and the ClerkConvex convenience init is
  MainActor-only.
- `httpRouter` comes from `convex/server`, not `_generated/server`.
- `.env` values copied from legacy files carry literal quotes and `\n`.
  Strip them before `convex env set`.
- `xcrun simctl spawn defaults` writes the device-level plist, not the app
  sandbox. To reset app state, uninstall and reinstall, or delete the plist
  inside `simctl get_app_container ... data`.
- SPM dependency naming in xcodegen: one package key per repo, products
  selected separately (clerk-ios provides both ClerkKit and ClerkKitUI).
- `//` in an xcconfig value starts a comment. `CONVEX_URL = https://…`
  silently became `https:`. Escape as `https:/$()/…`.
- Clerk↔Convex: activate the **Convex integration** in the Clerk dashboard
  (adds `aud: "convex"` to session tokens); Convex validates it via
  `applicationID: "convex"`, and the env var is `CLERK_FRONTEND_API_URL`.
  Without it, Convex websocket auth fails and mutations hang forever with no
  server-side logs.
- ClerkKit's independent auth events (`decodeIndependentEvent`) never emit
  `signInCompleted`/`signUpCompleted` for custom service-level flows — handle
  completion directly in the calling view (see SignInView.onAuthenticated).
- A default Clerk instance requires username + password at sign-up; email-code
  sign-up then ends in `missingRequirements` with no session. Either disable
  them in the dashboard or fill generated values via `SignUp.update`.
- Clerk restores its client asynchronously; reading `Clerk.shared.session`
  at app start races the load. Wait for `Clerk.shared.isLoaded` first.
- `ASWebAuthenticationSession` (Google OAuth) callbacks use the bundle id as
  the scheme; it is registered in Info.plist via CFBundleURLTypes.
- ConvexMobile (convex-swift 0.8.x) encodes Swift `Int` args with the
  `$integer` wrapper, which Convex action validators reject with
  ArgumentValidationError — strings decode fine. Pass numeric args as
  `Double`.
- A vertical SwiftUI ScrollView swallows horizontal pan gestures, killing
  TabView page-style swipes AND simultaneous SwiftUI DragGestures. Reader
  paging uses a window-level UIPanGestureRecognizer (simultaneous, non-
  canceling, horizontal-dominant only) instead.
- A page-turn selection can legitimately sit one past the last loaded page;
  prefetch must key off `pages.last` / `pages.count`, not
  `pages.indices.contains(pageIndex)`.
- Convex subscriptions opened before the Convex session activates fail with
  Unauthenticated and stay empty forever — no data, no crash. Library
  subscriptions must re-open on every auth-state transition (AppEnvironment
  observes `convex.authState`) plus bounded retries.
- A Convex lib file that imports node builtins (`node:crypto`, `node:http2`)
  needs its own `"use node"` directive, even if it only exports plain
  functions for a "use node" action file — the bundler resolves modules
  per-file.
- ConvexMobile's `subscribe` argument label is `yielding:` (external label
  of `yielding output:`); passing `yielding output:` fails to parse.
- Reading a raw Convex row's `v.id()` field as `string` in a validator-adjacent
  type needs `Doc<"table">["_id"]` (this repo's generated `Doc` is generic).

## Secrets and rotation

`backend/.env.local` and `ios/Secrets.xcconfig` hold real values and are
gitignored. The Sunnah.now key leaked historically and must be rotated
before production. The Gemini key and RevenueCat webhook secret appeared in
a terminal listing during Phase 0 setup, so rotate all three before launch.
Set them with `npx convex env set KEY value`.

## Session prompts

Paste the matching prompt at the start of a session. Each assumes the
agent reads `AGENTS.md` and `docs/PLAN.md` first.

**Phase 1 (auth and guest mode):**

> Read AGENTS.md and docs/PLAN.md fully before writing code. We are on
> Phase 1: auth and guest mode. Build the sign-in screen with Apple,
> Google, and email-code flows using ClerkKit custom flows, wire
> users:ensureCurrentUser after first sign-in, and implement guest mode
> with SwiftData for local bookmarks and notes plus a tested merge into
> Convex on sign-in. I will do the Clerk dashboard steps you list for me.
> When the flow works end to end on the simulator, also install and run
> the app on my connected iPhone with free provisioning. Verify with
> simulator UI automation before you claim anything works, commit at the
> end, and update the phase table in docs/PLAN.md.

**Phase 2 (reader):**

> Read AGENTS.md and docs/PLAN.md fully before writing code. We are on
> Phase 2: reader core. Build the reader per the design language section:
> dark quiet pages, content-size pagination through
> actions/hadithData:getReaderPage, collection outline through
> getCollectionOutline, chrome that hides on tap, swipe paging with no
> edge-back, and AI translation through actions/ai:translateHadith with
> quota handling and an AI label plus citations sheet. Follow the
> mistakes-already-made section. Verify on the simulator with UI
> automation, commit, and update the phase table in docs/PLAN.md.

**Phase 3 (tabs and data):**

> Read AGENTS.md and docs/PLAN.md fully before writing code. We are on
> Phase 3: fill in the four tabs. Today shows the daily hadith and
> continue-reading card, Library lists the seven collections and their
> volumes from the Convex cache, Saved shows bookmarks, favorites, and
> notes with bottom-sheet behavior like the Sajda reference, Settings
> holds reading preferences, language, and notification time. Wire
> bookmarks, favorites, notes, and reading progress to Convex for signed-in
> users and SwiftData for guests. Register APNs push for the daily hadith
> and add the scheduled send on the backend. Verify on the simulator,
> commit, and update the phase table in docs/PLAN.md.

**Phase 4 (submissions):**

> Read AGENTS.md and docs/PLAN.md fully before writing code. We are on
> Phase 4: translation submissions. Add a contextual submit flow in the
> reader, run actions/ai:submitTranslation for the AI review, show the
> verdict to the contributor, and add a minimal admin approval path using
> community:approveSubmission. Reports flow through
> actions/ai:reportTranslation. There is no voting, ranking, or public
> stats anywhere, and there never will be. Verify on the simulator,
> commit, and update the phase table in docs/PLAN.md.

**Phase 5 (Android):**

> Read AGENTS.md and docs/PLAN.md fully before writing code. We are on
> Phase 5: the Android app in Jetpack Compose, matching the iOS app
> feature for feature using the same Convex backend with the Clerk Android
> SDK and clerk-convex-kotlin. Start with auth, onboarding, and reader.
> Keep payloads platform-neutral and follow the design language section
> translated to Material conventions.

**Phase 6 (launch):**

> Read AGENTS.md and docs/PLAN.md fully before writing code. We are on
> Phase 6: launch prep. RevenueCat paywall that appears only at the AI
> quota, rotate the Sunnah.now, Gemini, and RevenueCat secrets, point the
> backend at the production deployment, add GitHub Actions for backend
> typecheck and iOS build plus tests, and prepare App Store metadata and
> screenshots.
