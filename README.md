# Hadithly

Hadithly is an Expo React Native + Next.js monorepo for a premium hadith reader with transparent Gemini-assisted translations, community review, and mobile subscriptions.

## Apps

- `apps/mobile`: Expo app for iOS and Android.
- `apps/web`: Next.js landing page and privileged API routes.
- `convex`: Convex schema and backend functions.

## Packages

- `@hadithly/hadith-provider`: provider abstraction and Sunnah.now adapter.
- `@hadithly/types`: shared product and API types.
- `@hadithly/validators`: shared Zod schemas.
- `@hadithly/config`: server/client environment helpers.
- `@hadithly/design-tokens`: colors, spacing, typography, and reader themes copied from the provided design direction.

## Local Setup

```bash
pnpm install
cp .env.local.example .env.local
pnpm dev
```

Mobile secrets are never shipped directly. Sunnah.now and Gemini are called only from server-side code.
