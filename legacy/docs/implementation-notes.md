# Hadithly Implementation Notes

## Secrets

Do not ship Sunnah.now or Gemini credentials in the mobile app. Set `SUNNAH_NOW_API_KEY` and `GEMINI_API_KEY` only in `apps/web/.env.local` locally and in Vercel project environment variables for deployed API routes.

The Sunnah.now key was provided during setup and should be rotated before production because it appeared in chat history.

## Convex

The Convex schema and functions are present under `convex/`. Run `pnpm exec convex dev` after creating or selecting a Convex project so Convex can set `CONVEX_DEPLOYMENT` and generate `convex/_generated/*`.

## API Caveat

Live checks showed Sunnah.now is available, but the single-hadith route may not respect the collection slug yet. The provider adapter keeps stable internal IDs as `provider:collectionSlug:providerHadithId` and the app should prefer paginated book/volume/chapter reads until the provider route behavior stabilizes.

## Mobile

The Expo app is iOS/Android-first. The default monorepo `build` task typechecks mobile rather than exporting a web build; the Next app owns the web landing surface.

## Auth and AI quota

Mobile auth uses Clerk Expo with secure token cache. Configure the Clerk dashboard with Apple, Google, and email-code sign-in, and add the native redirect URL:

```txt
hadithly://oauth-native-callback
```

Convex should be configured with the Clerk JWT template named `convex` before using authenticated Convex mutations from mobile. New Gemini generations require a Clerk bearer token and Convex quota enforcement; cached translations remain readable without auth.

## Provider-truth navigation

Do not add local fake book/chapter rows to the mobile app. Collection detail may show chapter links only when they were discovered from real provider/cache metadata. Otherwise, the reader opens the collection at page 1 and uses provider paginated reads.
