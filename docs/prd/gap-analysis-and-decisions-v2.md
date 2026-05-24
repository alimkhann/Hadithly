# Hadithly — Gap Analysis and Product Decisions v2

This document lists the main gaps found in the earlier PRD and the decisions needed before implementation.

---

## 1. AI provider mismatch

### Gap

The earlier PRD named OpenAI/GPT-4o mini in the AI translation section, but the latest product requirement says Gemini.

### Decision

Use Gemini everywhere:

- translation generation,
- translation review,
- risk flagging,
- topic tagging,
- language coverage campaigns,
- batch pre-translation.

### Implementation note

Use structured JSON outputs for translation and QA so the app can safely parse model output.

---

## 2. sunnah.now is early-stage

### Gap

The earlier PRD references sunnah.com endpoints, but the latest direction says the new sunnah.now API supports English and Arabic. sunnah.now documentation indicates an early API version and route structure.

### Decision

Build a provider adapter layer instead of coupling the app to one API.

### Required abstraction

```ts
HadithProvider {
  listBooks()
  getBook(slug)
  listHadiths(params)
  getHadith(slug, id)
  search(query)
}
```

### Why

If sunnah.now changes, rate-limits, lacks search, or misses metadata, you can swap to local dumps or another provider without rewriting the app.

---

## 3. Authenticity metadata is underspecified

### Gap

The app wants categories by authenticity and authenticity shown in the reader, but APIs may not always provide per-hadith grading.

### Decision

Never infer hadith authenticity with AI.

Use:

- `authenticityGrade`
- `authenticityAppliesTo`
- `authenticitySource`
- `authenticityConfidence`

### UI rule

If only collection-level info exists, show:

```txt
Collection: Sahih
```

not:

```txt
Sahih
```

If no reliable data exists, show:

```txt
Grade unavailable
```

---

## 4. Translation rating can be confused with authenticity

### Gap

You asked for percentage rating at the top-right of hadiths. Users may think “94%” means the hadith is 94% authentic.

### Decision

Rating percentage must visually belong to the translation source, not authenticity.

### Copy rule

Use tooltips/sheets:

```txt
94% positive translation rating
```

Never say:

```txt
94% authentic
```

---

## 5. AI badge needs a details sheet

### Gap

A small AI badge alone is not enough for religious-text trust.

### Decision

The AI badge opens a translation details sheet showing:

- provider: Gemini,
- model,
- generated date,
- whether grounding was used,
- rating,
- disclaimer,
- suggest/report actions.

---

## 6. AI auto-approval is risky

### Gap

Earlier PRD allowed AI auto-review and approval. For religious translations, silent auto-approval can create trust and accuracy risk.

### Decision

Use AI as a reviewer, not final authority for all users.

Suggested approval policy:

- New contributors: pending review.
- Trusted contributors: auto-approve only if Gemini score high and no risk flags.
- High-impact/low-rated/disputed translations: admin review.
- Admin can rollback.

---

## 7. Monetization value could be weak if cached translations are free

### Gap

If AI translations are globally cached and free to view, many users may never pay.

### Decision

Free users can view cached translations, but Pro unlocks:

- more new AI generations,
- priority queue,
- batch/book translation,
- offline language packs,
- advanced search over AI/community translations,
- higher submission/review limits,
- early language coverage campaigns.

### Why

Blocking cached translations hurts user growth and community coverage. Monetize generation, convenience, scale, and contribution tooling instead.

---

## 8. Paywall placement was too vague

### Gap

“Show paywall somewhere logical” is not precise enough for design or implementation.

### Decision

Use three placements:

1. Dismissible post-auth paywall after onboarding value preview.
2. Contextual quota-hit paywall.
3. High-intent paywall for batch/offline/priority translation features.

### Avoid

Do not show a hard paywall before the user understands the app.

---

## 9. Payments stack must respect platform rules

### Gap

The earlier PRD mixes RevenueCat and Polar without explaining where each applies.

### Decision

- iOS/Android: RevenueCat + App Store / Google Play in-app billing.
- Web: Polar as Merchant of Record if you want tax handling.
- Shared entitlement stored in Convex.

### Important

Do not put a Polar checkout inside the mobile app for digital AI subscriptions unless platform-specific rules allow it in that region.

---

## 10. Search scope is unclear

### Gap

Search “inside reader” and “home/tab search” are mentioned, but not defined.

### Decision

MVP supports:

- global search route,
- reader-scoped search sheet,
- jump by hadith number/reference,
- translation text search only over cached translations.

### Future

Semantic search over all hadiths and translations can be added after local indexing.

---

## 11. Topics may not exist in the API

### Gap

Home topics depend on the API supporting topics. If not, design may promise impossible content.

### Decision

For MVP:

- use static curated topics if available,
- or generate internal topic tags offline with Gemini,
- manually spot-check popular topics,
- do not generate live topic labels per user request.

---

## 12. “Real book pages” needs a technical definition

### Gap

The PRD says the pages should feel like real books and contain 2–10 hadiths, but APIs usually do not provide page numbers.

### Decision

Use virtual page segmentation:

- group hadiths by chapter/book,
- estimate page breaks by measured text height,
- persist user progress by visible hadith + scroll offset, not fake page number only.

### UI

Show page progress as a reading-position abstraction, not a claim of original printed page number unless the source provides page metadata.

---

## 13. Offline strategy needs boundaries

### Gap

Offline support was broad but not scoped.

### Decision

MVP:

- cache last opened book/collection,
- cache daily hadith,
- local notes/bookmarks/favorites,
- queue votes and notes.

Phase 2:

- downloaded collections,
- downloaded language packs,
- offline search.

---

## 14. User-generated content moderation is missing

### Gap

Community translations are UGC and need moderation tools.

### Decision

MVP must include:

- report translation,
- report user,
- moderation queue,
- rollback,
- banned/spam filter,
- contributor reputation,
- admin override,
- audit log.

---

## 15. Legal / trust copy is missing

### Gap

The app must distinguish source hadith text, translation, AI output, and authenticity data.

### Decision

Add required copy:

```txt
Hadithly displays hadith text and authenticity metadata from source datasets. AI translations are generated with Gemini and may contain mistakes. AI does not determine hadith authenticity.
```

Also add:

- Terms
- Privacy
- AI disclaimer
- Source attribution
- Report issue flow

---

## 16. Privacy boundaries for AI

### Gap

It is unclear what user data is sent to Gemini.

### Decision

Send only:

- Arabic hadith,
- English reference translation,
- target language,
- glossary/prompt context.

Do not send:

- user notes,
- user identity,
- private bookmarks,
- email,
- profile data.

---

## 17. Admin panel is more important than Phase 2 suggests

### Gap

Community translations and religious text moderation need admin tools earlier than the previous PRD suggested.

### Decision

Build a minimal admin interface in Phase 1.5:

- pending translations,
- reports,
- downvote clusters,
- rollback translation,
- edit language glossary,
- recompute coverage,
- trigger batch translation.

Can be a protected Next.js route.

---

## 18. AI cost control needs a plan

### Gap

Monthly limits are listed, but cost control is not robust.

### Decision

Use:

- global cache,
- per-user quota,
- per-language daily cap,
- per-IP abuse cap for guests,
- Gemini Batch API for non-urgent pretranslation,
- lower-cost Flash/Flash-Lite for first-pass,
- stronger model only for QA/disputes,
- grounding only when high value.

---

## 19. Data rights and attribution are unresolved

### Gap

Hadith data sources may have usage conditions.

### Decision

Before launch:

- confirm sunnah.now API terms,
- confirm offline dump license,
- display source attribution,
- avoid scraping without permission,
- cache responsibly.

---

## 20. MVP build order

Recommended order:

1. Design prototype.
2. Expo app shell + navigation.
3. Hadith provider adapter.
4. Reader.
5. Local bookmarks/favorites/notes.
6. Auth.
7. Translation cache schema.
8. Gemini generation.
9. Reader metadata row + voting.
10. Paywall/quota.
11. Daily hadith notification.
12. Community submission.
13. Minimal admin.
14. Leaderboard and coverage stats.

---

## 21. Highest-priority design gaps to fix now

1. Reader metadata top-right.
2. Translation details sheet.
3. Authenticity details sheet.
4. Paywall after auth/onboarding.
5. Quota-hit paywall.
6. Community review screen.
7. Language coverage UI.
8. Missing translation empty state.
9. Low-rated translation state.
10. Guest vs signed-in limitations.
