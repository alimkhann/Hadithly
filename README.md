# Hadithly

Read hadith collections in your language. Clean, calm, and true to the sources.

[hadithly.app](https://hadithly.app) is live. The apps themselves are still in development.

- **iOS** — SwiftUI (`ios/`), iOS 17+
- **Android** — Jetpack Compose (`android/`), minSdk 26
- **Backend** — Convex (`backend/`): hadith data, AI translations, reading data

## Why I built this

Most hadith apps are cluttered or mix weak sources with strong ones. I wanted one reading app that stays close to the source texts and tells you plainly when a translation came from AI.

## How it works

Input: you pick a collection, volume, and language. The backend pulls the Arabic source text plus existing translations from Sunnah.now, then asks Gemini for a grounded draft translation only when no approved human translation exists.

Human control: AI drafts never publish on their own. They sit in a review queue until an admin approves them. The app labels every AI translation as AI.

Risk I designed around: an AI translation presented as authoritative. The guardrails are grounding in the source text, citation parsing, no public voting or ranking, and private reading progress. Paywalls only gate AI quota (20 free per month, 500 pro), never the source texts.

## Quickstart

```sh
# backend
cd backend && npm install
npx convex dev
npm run typecheck

# iOS (regenerate after changing project.yml)
cd ios && xcodegen generate
xcodebuild -project Hadithly.xcodeproj -scheme Hadithly \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Android (JDK 21)
cd android && ./gradlew assembleDebug
```

Copy `.env.local.example` to `.env.local` and fill in your own keys. Secrets live in Convex env vars and local config files only. They never go into git.

## Product principles

1. A reading app, not a social network. No leaderboards, votes, ratings, or streaks.
2. Reading works signed out. Accounts only add sync.
3. AI translations are always labeled and grounded in real sources.
4. Paywalls only appear when you hit the free AI quota.

## Built with

- SwiftUI and xcodegen on iOS
- Jetpack Compose (Material 3) on Android
- Convex for the backend, Clerk for auth, Gemini for grounded translation drafts
- Sunnah.now as the source-text provider

## Roadmap

- Finish the reader experience on iOS, then bring Android to parity
- Daily push and quota reset crons
- Subscriptions through RevenueCat once the reading flow feels right

## Contact

Alimkhan Yergebayev — alimkhan.yergebayev@gmail.com

Project link: [https://github.com/alimkhann/Hadithly](https://github.com/alimkhann/Hadithly). The archived Expo monorepo lives on the `archive/legacy` branch.

See `AGENTS.md` for the dev guide and `backend/README.md` for backend setup.
