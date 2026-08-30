# Hadithly

Native mobile apps for reading the hadith collections in your language.

- `backend/` — Convex-only backend (data, Sunnah.now proxy, Gemini AI, webhooks, crons)
- `ios/` — SwiftUI app (iOS 17+), built with xcodegen (`ios/project.yml`)
- `legacy/` — archived Expo/Next.js monorepo (reference only, do not build on it)
- `docs/` — PRD and notes (`legacy/docs/prd/` holds the original product PRDs)

## Commands

```sh
# backend
cd backend && npm install
npx convex dev        # push to dev deployment + watch
npm run typecheck     # tsc --noEmit

# ios (regenerate project after adding files or changing project.yml)
cd ios && xcodegen generate
xcodebuild -project Hadithly.xcodeproj -scheme Hadithly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

## Non-negotiable rules

1. **No competition features.** No leaderboards, public votes/ratings,
   reputation, streaks, or badges — anywhere in the product. Translation
   quality is enforced by AI review + admin approval only. Reading progress
   is private per user.
2. **Mobile apps talk only to Convex.** Sunnah.now and Gemini are called
   exclusively from Convex actions; API keys live in Convex env vars.
3. **Users never pass their own identity.** All user-scoped functions
   resolve the user from the verified Clerk JWT (`requireIdentity`).
4. **Secrets never enter git.** `backend/.env.local`, `ios/Secrets.xcconfig`
   are gitignored; `.example` files document their shape.
5. **Rotate the Sunnah.now key before production** (it leaked historically —
   see `legacy/docs/implementation-notes.md`).

## Conventions

- Backend: TypeScript strict; user-facing mutations/queries in `convex/*.ts`,
  third-party calls in `convex/actions/*.ts` (files with `"use node"`).
  Return-type-annotate action handlers to avoid circular api inference.
- iOS: SwiftUI, `@Observable` state, feature folders under
  `ios/Hadithly/Features/`, design tokens in `Core/Theme/Theme.swift`.
  Regenerate the Xcode project with xcodegen — never edit `project.pbxproj`.
- Android (Compose) lands in Phase 5; keep backend payloads platform-neutral.
