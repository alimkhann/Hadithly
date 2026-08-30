# Hadithly Backend

Convex-only backend. The mobile apps talk **only** to Convex; Sunnah.now and
Gemini are called exclusively from Convex actions with secrets in env vars.

## Layout

```
convex/
  schema.ts            all tables (no votes/ratings/leaderboards by design)
  auth.config.ts       Clerk JWT integration
  users.ts             user upsert from Clerk identity, entitlement sync
  hadiths.ts           cached hadith rows, public search
  collections.ts       cached collections + volume outlines
  translations.ts      translation cache/publish (internal)
  community.ts         submission queue, moderation, audit log (internal)
  library.ts           bookmarks, favorites, notes, reading progress, push tokens
  quotas.ts            AI generation quota (free 20/mo, pro 500/mo)
  actions/hadithData.ts  Sunnah.now proxy: books, outlines, reader pages
  actions/ai.ts          Gemini: grounded translation + submission review
  http.ts               RevenueCat webhook (POST /webhooks/revenuecat)
  crons.ts              monthly quota reset (daily push lands in Phase 3)
  lib/sunnahNow.ts      provider adapter (ported from legacy hadith-provider)
  lib/grounding.ts      Gemini JSON/citation parsing (ported from legacy web)
  lib/identity.ts       Clerk identity helpers (subject = clerkId)
```

## Env vars

| Variable | Purpose |
| --- | --- |
| `CONVEX_DEPLOYMENT` | set automatically by `npx convex dev` |
| `CLERK_JWT_ISSUER_DOMAIN` | Clerk Frontend API domain (auth.config.ts) |
| `SUNNAH_NOW_API_KEY` | Sunnah.now early-access API key |
| `GEMINI_API_KEY` | Google AI Studio key (translation + review) |
| `REVENUECAT_WEBHOOK_SECRET` | shared secret for webhook auth header |

Set the secret ones with `npx convex env set KEY value`.

## Commands

```
npm install
npx convex dev        # push to dev deployment + watch
npx convex deploy     # push to production
npm run typecheck     # tsc --noEmit
```

## Auth model

Clients send Clerk JWTs; Convex validates them via `auth.config.ts`.
`requireIdentity()` returns `clerkId = identity.subject`. **Users never pass
their own userId** — rows are always resolved from the verified identity.

## Removed vs legacy (ethical/product decisions)

- No `translationVotes`, no upvotes/downvotes/ratingPercent anywhere
- No leaderboards, streaks, badges, or reputation
- Community submissions go through AI review + admin approval; nothing is
  publicly ranked
- Reading progress is private per user and never surfaced to others
