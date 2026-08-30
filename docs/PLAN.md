# Hadithly master plan

This document is the single source of truth for the rebuild. Read it at the
start of any session. It answers: what is this, what exists, what is next,
and what already went wrong so you do not repeat it.

Last updated: end of Phase 0 (see the phase table for status).

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
| 1 | Auth (Apple, Google, email) + guest mode + user sync | next |
| 2 | Reader core: pagination, chrome toggle, AI translation on demand | not started |
| 3 | Tabs: Today, Library, Saved, Settings; push notification setup | not started |
| 4 | Translation submissions with AI review and admin approval | not started |
| 5 | Android (Compose) port | not started |
| 6 | RevenueCat paywall, App Store prep, CI | not started |

Each phase ends with a gate: the feature works on the simulator, tests pass
where logic exists, and the work is committed. Do not start a phase before
the previous gate passes.

### Phase 1 detail (next)

Sign-in screen with three methods (Apple, Google, email code), all through
ClerkKit custom flows so the UI stays ours. After first sign-in the app
calls `users:ensureCurrentUser`. Guest mode stays available and equal:
guests read everything, their bookmarks and notes live in SwiftData, and a
later sign-in merges local items into Convex. The merge logic needs tests.

Clerk dashboard work the user must do by hand (agent cannot): enable Native
API under Native applications, add the iOS app with bundle id
`com.hadithly.app`, enable Apple and Google providers, and add the
associated domain `webcredentials:elegant-tetra-44.clerk.accounts.dev`.

Physical device install (user request): connect the iPhone, select it as
the run destination in Xcode, sign with the personal team in Signing and
Capabilities, then run. Free provisioning works for development builds.
If Xcode is awkward, `xcrun devicectl device install app` after an archive.

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
