<!-- BEGIN RELAY MANAGED BLOCK: codex -->
## Relay for Codex

- Start or resume with `get_brief`. Only call `list_projects` and `set_current_project` if Relay reports project ambiguity or the wrong project.
- Before architecture, product, or process decisions, prefer `search_context` or `recall_context` when local context may be incomplete.
- Use `get_project_state` when you need the structured objective, constraints, or open tasks instead of a prose brief.
- Use `add_memory` only for clearly confirmed durable facts: decisions, constraints, tasks, and stable product truths. Do not save speculative brainstorming until it is confirmed.
- If a Relay recall/search returns nothing, continue with normal local investigation. If that investigation discovers confirmed durable facts, save those facts; do not save the empty search attempt itself.
- For coding work, save files/modules touched, public API or schema changes, migrations, tests run, unresolved blockers, and next steps when those facts would help a future session continue.
- Use `checkpoint_context` only before compaction-equivalent risk, task switches, or explicit milestone saves. Use `save_context` only when wrapping up a meaningful unit of work.
- Use `checkpoint_context` only at meaningful milestones, before switching tasks, or before compaction-equivalent actions.
- Avoid repeated Relay reads or writes when the current local conversation already contains the needed context.
<!-- END RELAY MANAGED BLOCK: codex -->

# Hadithly Agent Guide

## Project Shape

Hadithly is a monorepo with Expo mobile, Next.js API/landing, Convex backend, and shared packages. The mobile app must call the Next API for source data and AI; it must not call Sunnah.now or Gemini directly.

## Source Truth

- Sunnah.now is the MVP hadith source.
- `/books` gives the seven real collections.
- Collection detail should use provider-proven volumes/books.
- Do not build top-level chapter lists from the first reader page.
- Do not use `/chapter/{id}` for top-level navigation; chapter IDs repeat inside volumes.
- Hide topics or show empty states until reviewed/generated topic data exists.

## Auth And Env

- Clerk is the mobile/web auth provider.
- Convex auth uses Clerk issuer plus the `convex` JWT template.
- Clerk, Sunnah.now, Gemini, Convex server URL, cron, webhook, and payment secrets stay server-side.
- Expo public envs may include API base URL, Convex URL, Clerk publishable key, and RevenueCat public SDK keys.
- Do not print secrets in chat or docs.

## Mobile UX Rules

- Keep the custom visual UI, but wire real handlers.
- Reader chrome is hidden by default and toggled by tapping the reader.
- Reader edge-swipe back is disabled; Home is the reader exit.
- Reader swipe direction is left = next page, right = previous page, regardless of Arabic RTL text.
- Official/source hadiths should not show like/dislike/rating UI. Feedback is only for AI/community translations.
- Missing non-English translations should auto-load or auto-generate based on auth/quota; do not show a manual generate button.

## Verification

Run targeted tests after touching provider/mobile reader/auth code:

```bash
pnpm test --filter @hadithly/hadith-provider -- sunnah-now-provider
pnpm test --filter @hadithly/mobile -- hadith reader-state auth-flow onboarding
pnpm --filter @hadithly/mobile exec tsc --noEmit
```

For dashboard changes, record what was verified and what remains blocked. Do not claim real Apple/Google/email device flows pass unless they were tested on a dev build/device.
