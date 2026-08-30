# Hadithly master plan

This document is the single source of truth for the rebuild. Read it at the
start of any session. It answers: what is this, what exists, what is next,
and what already went wrong so you do not repeat it.

Last updated: end of Phase 1 (see the phase table for status).

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
| 2 | Reader core: pagination, chrome toggle, AI translation on demand | next |
| 3 | Tabs: Today, Library, Saved, Settings; push notification setup | not started |
| 4 | Translation submissions with AI review and admin approval | not started |
| 5 | Android (Compose) port | not started |
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

### Phase 2 detail

Reader over live Sunnah.now data through `actions/hadithData:getReaderPage`
and `getCollectionOutline`. Swipe left goes forward, right goes back, no
edge-swipe back, the Home tab is the exit. AI translation loads
automatically for the chosen language through `actions/ai:translateHadith`
with the quota check, always labeled, with a citations sheet. No rating UI
anywhere. Respect the legacy provider rule: never call the single-hadith
Sunnah.now route; paginate and use the Convex cache.

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
