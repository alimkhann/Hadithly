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
