# Hadithly

Native mobile apps for reading the hadith collections in your language.

**Start every session by reading `docs/PLAN.md`.** It holds the current gate,
the ordered session list, and the mistakes list. Read the linked session prompt
from `docs/SESSION_PROMPTS.md` before changing files.

- `backend/`: Convex-only backend for data, providers, webhooks, and crons
- `ios/`: SwiftUI app for iOS 17+, built with xcodegen from `ios/project.yml`
- `android/`: Compose app for Android 8.0+ with minSdk 26
- `legacy/`: archived Expo and Next.js monorepo, for reference only
- `docs/`: master plan, dashboard checklist, reference audit, session prompts,
  repository/disk recovery, and launch-stack research

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

# android (JDK 21; secrets in android/secrets.properties, see .example)
cd android
./gradlew assembleDebug        # build
./gradlew testDebugUnitTest    # unit tests
```

## Non-negotiable rules

1. **No competition features.** No leaderboards, public votes or ratings,
   reputation, streaks, or badges. Translation quality comes from evidence,
   deterministic checks, AI review, and an admin exception path. Reading
   progress stays private.
2. **Convex is the only mobile API and control plane.** Sunnah.now and Gemini
   are called exclusively from Convex actions; API keys live in Convex env
   vars. An immutable, checksummed offline artifact may be downloaded from a
   CDN URL and manifest authorized by Convex. No second app backend is allowed.
3. **Users never pass their own identity.** All user-scoped functions
   resolve the user from the verified Clerk JWT (`requireIdentity`).
4. **Secrets never enter git.** `backend/.env.local`, `ios/Secrets.xcconfig`,
   `android/secrets.properties` are gitignored; `.example` files document
   their shape.
5. **Rotate the Sunnah.now key before production.** It leaked historically.
   See `legacy/docs/implementation-notes.md`.

## Conventions

- Backend: TypeScript strict; user-facing mutations/queries in `convex/*.ts`,
  third-party calls in `convex/actions/*.ts` (files with `"use node"`).
  Return-type-annotate action handlers to avoid circular api inference.
- iOS: SwiftUI, `@Observable` state, feature folders under
  `ios/Hadithly/Features/`, design tokens in `Core/Theme/Theme.swift`.
  Regenerate the Xcode project with xcodegen. Never edit `project.pbxproj`.
- Android (Compose) mirrors the iOS feature folders under
  `android/app/src/main/kotlin/com/hadithly/app/`; design tokens in
  `core/theme/Theme.kt` must stay in sync with the iOS Theme.swift.
- Keep backend payloads platform-neutral. Implement and verify every new
  product behavior on both native apps unless the active session says that one
  platform is a no-change parity check.
- Use separate Codex tasks for delegated sessions. Do not use Relay for this
  repository.
