# Hadithly Repo Summary

## Product

Hadithly is an Expo iOS/Android hadith reader backed by a Next.js API, Convex state, Clerk auth, Sunnah.now source data, Gemini translations, and RevenueCat mobile subscriptions.

## Workspace

- `apps/mobile`: Expo Router app. It owns onboarding, auth UI, tabs, collection detail, reader, local API caching, notifications, and RevenueCat SDK setup.
- `apps/web`: Next.js app. It owns the landing page plus all server-side API routes. Mobile calls this app, not Sunnah.now or Gemini directly.
- `convex`: Convex schema/functions for users, hadith cache, translations, quotas, library state, community state, and Clerk auth config.
- `packages/hadith-provider`: Sunnah.now provider adapter and provider normalization.
- `packages/types`: shared API/product types.
- `packages/validators`, `packages/config`, `packages/design-tokens`: shared validation, config, and UI tokens.

## Current Architecture

Mobile calls `EXPO_PUBLIC_API_BASE_URL` for reading/search/AI routes. The web API uses server-only `SUNNAH_NOW_API_KEY`, `GEMINI_API_KEY`, `CLERK_SECRET_KEY`, and Convex envs. Clerk-authenticated mutation/AI routes verify bearer tokens server-side. Convex is configured for Clerk with the `convex` JWT template.

The hadith provider contract is source-truth-first. Collections come from `/books`. Collection detail now exposes trusted provider-derived volumes/books, not first-page fake chapters. Chapter IDs are treated as local metadata inside volumes because Sunnah.now chapter IDs repeat across books.

Reader routes use:

```text
/reader/[collectionSlug]?page=1&pageSize=8&volumeId=1
```

`chapterId` remains optional internal metadata for future inside-volume filtering, but top-level collection detail should prefer volumes.

## Dashboard State

- Clerk: Apple, Google, email/password, email verification, native Expo callback URLs, and Convex JWT template are configured on the dev instance.
- Apple Developer: `com.hadithly.app` exists under team `6378AFQPXV`; Push Notifications and Sign in with Apple are enabled.
- App Store Connect: only the old Adat app existed before this work. A Hadithly app creation dialog was prepared with iOS, `Hadithly`, bundle `com.hadithly.app`, SKU `hadithly-ios`, and Full Access. The final Create click requires explicit confirmation.
- Google Cloud: OAuth consent plus iOS and web OAuth clients exist for Hadithly. Clerk Google OAuth uses custom Google credentials.
- Convex: dev and prod have `CLERK_JWT_ISSUER_DOMAIN`; prod deploy succeeded after adding `convex/auth.config.ts`.
- Expo/EAS: dashboard envs were set for API base URL, Convex URL, Clerk publishable key, and iOS RevenueCat key. The EAS CLI is not logged in locally.
- RevenueCat: project currently shows Test Store setup. A real Android Play Store configuration is blocked until Google Play service account credentials JSON is available.

## Important Constraints

- Never call Sunnah.now or Gemini from the mobile app.
- Do not invent books, chapters, topics, or counts. If provider metadata is not proven, show an empty state or collection-level reader entry.
- Treat Sunnah.now `/chapter/{id}` as unsafe for top-level navigation because chapter numbers repeat within volumes.
- Use volumes/books as the collection detail hierarchy for MVP.
- Keep AI authenticity separate from source authenticity. AI can translate or suggest topics later, but cannot grade hadith authenticity.
- Guests can read Arabic/English and cached translations; new AI generation requires signed-in Clerk auth.

## Useful Commands

```bash
pnpm test --filter @hadithly/mobile -- hadith reader-state
pnpm test --filter @hadithly/hadith-provider -- sunnah-now-provider
pnpm --filter @hadithly/mobile exec tsc --noEmit
pnpm --filter @hadithly/hadith-provider exec tsc -p tsconfig.json --noEmit
pnpm exec convex dev --once --env-file .env.local --typecheck try
```

## Manual Verification Priorities

1. Fresh mobile install derives phone language, then respects onboarding/settings override.
2. Apple, Google, email/password, and guest onboarding enter the app deterministically.
3. Signed-in user syncs to Convex.
4. Library shows the seven provider collections only.
5. Collection detail shows provider volumes/books, not first-page chapter rows.
6. Reader opens the selected collection/volume, hides chrome by default, toggles chrome on tap, disables edge-swipe back, and pages left=next/right=previous.
7. Non-English reader loads cached translations and auto-generates only for signed-in users with quota.
8. Android build has a real RevenueCat Android key before production subscription testing.
