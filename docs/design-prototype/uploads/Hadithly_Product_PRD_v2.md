# Hadithly — Product PRD v2

**Version:** 2.0  
**Date:** May 23, 2026  
**Status:** Refined build PRD for coding agents  
**Primary platforms:** iOS and Android  
**Future platform:** Web reader + account dashboard  
**Core stack decision:** Expo React Native + Next.js API on Vercel + Convex + Clerk + Gemini + RevenueCat + Polar for web only

---

## 0. What changed from the previous PRD

This version intentionally corrects and expands the previous draft:

1. **AI provider is Gemini, not OpenAI.**
   - Use Gemini for translation generation, translation QA, community-submission review, topic tagging, and optional batch pre-translation.
2. **Reader metadata is a first-class feature.**
   - Every hadith block must show, at the top-right of the hadith area:
     - authenticity chip,
     - translation source badge,
     - AI badge when applicable,
     - positive rating percentage,
     - like / dislike controls.
3. **Authenticity must not be guessed.**
   - Show collection-level authenticity only when per-hadith grade is unavailable.
   - Store `authenticitySource`, `authenticityGrade`, and `authenticityConfidence`.
4. **Paywall placement is now explicit.**
   - Do not hard-block the first experience.
   - Show the main paywall after the user has seen value during onboarding and after auth.
   - Show contextual paywall when the user hits the AI-generation limit.
5. **sunnah.now replaces the previous sunnah.com-first assumption.**
   - The API layer should support sunnah.now now, with adapters so another hadith data provider can be swapped later.
6. **Community translations need stronger moderation.**
   - AI review helps, but public religious-text changes should be gated by reputation, vote thresholds, and/or admin override.

---

## 1. Product summary

Hadithly is a minimal, book-like hadith reader for Muslims who want to read hadith in their own language. The app starts with Arabic and English hadith data from the hadith API, then uses Gemini to generate translations into additional languages. Users can rate AI translations, suggest better community translations, and earn public contribution stats by language.

The product should feel like a premium Islamic reading app, not an AI toy. AI must be useful but humble: clearly labeled, rateable, improvable, and never presented as scholarly certainty.

---

## 2. Problem

Most hadith readers are strong in Arabic and English but weak for users who need Kazakh, Russian, Uzbek, Turkish, Indonesian, Malay, Urdu, German, French, and other languages. Generic machine translation is too risky for religious texts, while manual translation is too slow. Hadithly combines:

- reliable source text,
- AI-assisted translation,
- visible provenance,
- community correction,
- rating feedback,
- language-specific contributor reputation.

---

## 3. Goals

### MVP goals

- Ship a polished iOS and Android reader.
- Support Arabic + English source display.
- Support Gemini translations for priority languages.
- Show translation provenance and authenticity transparently.
- Let users like/dislike translations.
- Let authenticated users suggest translations.
- Provide bookmarks, favorites, notes, daily hadith, search, and reader settings.
- Add a fair freemium paywall around AI generation without making basic reading feel greedy.

### Business goals

- Build trust first, monetization second.
- Make Pro valuable for users in under-served languages.
- Convert through the AI translation aha moment, not by blocking basic reading.
- Keep monthly AI costs predictable through global caching, batch generation, and quotas.

### Non-goals for MVP

- No fatwa, fiqh-answering, or religious advice chatbot.
- No claim that AI translations are scholar-approved.
- No public comments/discussion threads under hadiths.
- No complex social network.
- No full web app in Phase 1.

---

## 4. Target users

### Primary users

1. **Everyday Muslim reader**
   - Wants a clean daily hadith and occasional searching.
   - Needs simplicity, bookmarks, and shareable hadith links.

2. **Non-English / non-Arabic reader**
   - Wants hadith in Kazakh, Russian, Uzbek, Turkish, Indonesian, Urdu, etc.
   - Most likely to hit AI translation features and convert.

3. **Student / note-taker**
   - Uses bookmarks, favorites, notes, search, and collection navigation.
   - Needs stable references and exportable/shareable links.

4. **Community contributor**
   - Knows another language well.
   - Wants to improve translations and receive visible credit.

### Secondary users

- Imams / teachers who want to share hadith references.
- Productive habit users who want daily notifications.
- Language communities wanting to improve local translations.

---

## 5. Success metrics

### Activation

- 70%+ complete language selection.
- 55%+ reach the first reader screen.
- 35%+ enable daily hadith notifications.
- 25%+ use a non-English preferred language.

### Engagement

- Day 7 retention: 30%+
- Day 30 retention: 12–20%+
- Average reader sessions per active user per week: 3+
- Bookmark/favorite/note creation: 15%+ of active users.

### Translation quality

- AI translation positive rating: 85%+ after 20 votes.
- Downvote reason completion rate: 30%+ of downvotes.
- Community override rate: tracked by language; high override rate flags weak AI quality.

### Monetization

- Free → trial start: 4–8%
- Trial → paid: 35–55%
- Free → paid without trial: 1–3%
- Monthly AI cost per paid user kept below 20–30% of subscription revenue.

---

## 6. Product principles

1. **Reader first.** The app must work as a beautiful hadith reader even if the user never touches community or Pro.
2. **Truth over growth.** Never hide that a translation is AI-assisted.
3. **Minimal surface, deep sheets.** Main tabs stay simple; advanced controls live in bottom sheets.
4. **No noisy cards in the reader.** Hadiths flow like a book, with subtle dividers and metadata.
5. **Source-aware design.** Every hadith has a stable reference, collection, chapter, and authenticity metadata.
6. **Community improves AI, not replaces scholarship.** The app should invite correction but avoid “scholar-approved” claims unless a real review process exists.

---

## 7. Information architecture

### Recommended tab bar

Use **4 tabs**, not 5, to keep the app minimal:

1. **Home**
   - Daily hadith
   - Continue reading
   - Recent collections
   - Topic shelves
   - Search entry point

2. **Library**
   - Collections
   - Books / chapters
   - Authenticity filters
   - Coverage indicators

3. **Community**
   - Language leaderboard
   - Translation stats
   - Help review
   - My language progress

4. **You**
   - Profile
   - Bookmarks / favorites / notes
   - My translations
   - Subscription
   - Settings

### Why not a separate Search tab?

Search is essential but should be accessible from Home and Reader. A standalone tab is optional later. For MVP, keep it as a modal/full-screen route:

- `/search`
- `/reader-search`

### Core routes

```txt
/(tabs)/home
/(tabs)/library
/(tabs)/community
/(tabs)/you

/onboarding
/auth
/paywall
/search

/library/[collection]
/library/[collection]/[book]
/reader/[collection]/[book]/[hadithRef]

/translation/submit/[hadithRef]
/translation/review
/settings
/settings/reader
/settings/notifications
```

---

## 8. Core user flows

### Flow A — First launch

1. Splash screen.
2. Welcome: “Read hadith in your language.”
3. Language selection with coverage indicator.
4. Daily hadith notification choice.
5. Preview screen showing the same hadith in Arabic, English, and the chosen language.
6. Auth screen:
   - Continue with Apple
   - Continue with Google
   - Email
   - Continue as guest
7. Post-auth soft paywall:
   - 3-day Pro trial.
   - Dismissible.
   - “Continue free” visible but visually secondary.
8. Home.

### Flow B — Read hadith

1. User opens Daily Hadith or Continue Reading.
2. Reader opens full-screen.
3. Status bar hidden, minimal progress pill visible.
4. Hadiths flow continuously with reference dividers.
5. Each hadith block shows top-right metadata:
   - authenticity,
   - source badge,
   - AI badge when relevant,
   - rating percentage,
   - like/dislike.
6. Tap page → reader chrome appears.
7. Long press hadith → context menu.

### Flow C — Translate missing language

1. User’s selected language is missing for hadith.
2. Show inline placeholder:
   - “No Kazakh translation yet.”
   - “Generate with Gemini” button.
   - remaining free uses shown.
3. If quota available:
   - call backend,
   - generate translation,
   - save globally,
   - show AI badge and rating controls.
4. If quota exceeded:
   - show contextual paywall sheet.

### Flow D — Rate translation

1. User taps like/dislike.
2. Optimistic update.
3. If dislike, optional bottom sheet:
   - inaccurate meaning,
   - awkward language,
   - missing nuance,
   - spelling/grammar,
   - inappropriate wording,
   - other.
4. Rating percentage updates:
   - `positiveRating = upvotes / (upvotes + downvotes) * 100`.
   - If votes < 5, show “New” instead of a percentage.

### Flow E — Suggest community translation

1. User long-presses hadith or taps translation source menu.
2. Selects “Suggest translation.”
3. Editor shows Arabic, English, existing translation, and target-language input.
4. User submits.
5. Gemini QA produces:
   - quality score,
   - risk flags,
   - glossary consistency check,
   - missing/added meaning warnings.
6. Submission goes to:
   - auto-approve queue for trusted users only, or
   - community review queue, or
   - admin review queue.
7. Approved translation becomes the default community translation.
8. Original AI version remains accessible.

---

## 9. Reader requirements

### Layout

- Full-screen immersive reader.
- Continuous scroll.
- No large cards.
- Subtle hadith blocks separated by:
  - centered reference divider,
  - whitespace,
  - very faint line or ornament.
- Multiple hadiths per page/viewport depending on content length.
- Arabic text:
  - right-aligned,
  - high line-height,
  - premium Arabic font,
  - no cramped UI around it.
- Translation:
  - below Arabic,
  - calm readable font,
  - medium-gray / foreground-muted.

### Reader default state

Visible:

- top progress pill only,
- hadith text,
- hadith metadata top-right,
- no app header,
- no tab bar,
- status bar hidden if platform allows.

Hidden:

- home button,
- menu button,
- bookmark button,
- search button,
- status bar.

### Reader active state on tap

Show:

- status bar,
- progress pill expands into page number + fill,
- bottom-left circular Home button,
- bottom-right circular Menu button,
- right-side Bookmark button,
- right-side Search button below bookmark.

Hide again on:

- second tap,
- scroll after delay,
- timeout after 3 seconds of no interaction.

### Hadith metadata row — required

At the **top-right** of every hadith unit, show a compact metadata group. It must not look like a card header. It should feel like a quiet marginal annotation.

Required elements:

1. **Authenticity chip**
   - Examples:
     - `Sahih`
     - `Hasan`
     - `Da'if`
     - `Collection: Sahih`
     - `Grade unavailable`
   - Tapping opens authenticity/source sheet.

2. **Translation source badge**
   - `Official EN`
   - `Gemini AI`
   - `Community`
   - `Community + AI reviewed`

3. **AI badge**
   - Only if current visible translation was generated by Gemini or AI-reviewed.
   - Short visible form: `AI`
   - Expanded sheet: “Generated with Gemini. May contain mistakes. Rate or suggest an improved translation.”

4. **Rating percentage**
   - Format:
     - `94%`
     - `New` if fewer than 5 votes
     - `Needs review` if below 70%
   - Calculation:
     - `upvotes / (upvotes + downvotes) * 100`
   - Must be separate from authenticity; rating means community satisfaction, not hadith authenticity.

5. **Like / dislike**
   - Small thumb up/down or arrow up/down buttons.
   - Haptic feedback on vote.
   - After vote, selected state is clear but subtle.

### Metadata hierarchy

Visual order from right to left in LTR UI:

```txt
[Authenticity] [AI/Source] [94%] [↑] [↓]
```

For Arabic RTL mode, keep semantic order but align gracefully:

```txt
[↓] [↑] [94%] [AI/Source] [Authenticity]
```

### Authenticity source sheet

Opened by tapping authenticity chip.

Show:

- grade,
- what it applies to:
  - per-hadith grade,
  - collection-level grade,
  - or unavailable,
- source provider,
- reference,
- disclaimer:
  - “Hadithly displays authenticity metadata from its source datasets. AI does not determine hadith authenticity.”

### Context menu on long press

Actions:

- Bookmark
- Favorite
- Add note
- Suggest translation
- View translation details
- Listen
- Copy Arabic
- Copy translation
- Copy reference
- Share hadith
- Report issue

### Reader menu bottom sheet

Primary rows:

1. Book contents
2. Bookmarks, favorites, notes
3. Reader search
4. Reader settings
5. Translation details
6. Report issue

### Reader settings

Display:

- Arabic toggle
- Translation toggle
- At least one must remain on.

Language:

- Translation language picker
- Shows coverage:
  - official,
  - AI cached,
  - community approved,
  - missing.

Typography:

- Arabic font size
- Translation font size
- Arabic font family
- Translation font family
- Line spacing
- Text width / margins

Appearance:

- Auto / light / dark / sepia
- Background texture toggle
- Reduce visual effects

Behavior:

- Haptics
- Keep screen awake
- Hide status bar in reader
- Auto-open last position
- Show metadata always / only active mode

---

## 10. Home requirements

### Top area

- Greeting: “Assalamu alaikum”
- Search field
- Small language chip with current language and coverage.

### Daily Hadith card

Must show:

- reference,
- authenticity chip,
- short Arabic preview,
- selected-language translation preview,
- translation source badge,
- CTA: “Read today’s hadith.”

### Continue reading

- Collection + book/chapter
- progress pill/ring
- last read time
- CTA: “Continue.”

### Topic shelves

Only if source or internal tagging supports it. If API topics are unavailable, use internally generated/cached topic tags created offline by Gemini and manually spot-checked.

Examples:

- Faith
- Prayer
- Character
- Knowledge
- Fasting
- Family
- Charity
- Manners

### Collections quick access

- Bukhari
- Muslim
- Abu Dawud
- Tirmidhi
- More

---

## 11. Library requirements

### Collection list

Each row/card:

- collection name,
- Arabic name,
- hadith count,
- coverage in selected language,
- authenticity / collection status,
- download/cache indicator if offline cache is available.

### Filters

- All
- Sahih collections
- Sunan collections
- Popular
- Downloaded
- Has my language
- Needs translation

### Collection detail

- Overview,
- books/chapters list,
- progress,
- language coverage,
- start/continue CTA.

---

## 12. Community requirements

### Community tab structure

Top:

- Language selector.
- Current language coverage:
  - official,
  - Gemini AI,
  - community approved,
  - missing.

Sections:

1. **Translation progress**
   - total hadiths translated,
   - AI translated,
   - community approved,
   - needs review.

2. **Leaderboard**
   - language-specific,
   - all-time / monthly,
   - approved translations,
   - average rating,
   - review helpfulness,
   - streak.

3. **Help review**
   - pending community submissions in user’s language.
   - side-by-side existing vs suggested translation.
   - approve/downvote/report.

4. **My contributions**
   - submitted,
   - approved,
   - pending,
   - average rating.

### Leaderboard scoring

Use a weighted score, not just count:

```txt
score =
  approvedTranslations * 10
  + helpfulVotesReceived * 2
  + acceptedReviews * 3
  - rejectedSubmissions * 5
```

Display simpler labels to users:

- “124 approved”
- “92% avg rating”
- “Top 3 in Kazakh”

---

## 13. AI translation system

### Provider

Use **Gemini**.

Recommended runtime model strategy:

- **Gemini Flash / Flash-Lite** for first-pass translation and low-cost background generation.
- **Gemini Pro** or stronger model for QA/review of community submissions and high-risk translations.
- **Gemini Batch API** for non-urgent pre-translation of popular collections/languages.
- **Grounding with Google Search** only when needed:
  - first translation of important/popular hadith,
  - review of disputed translations,
  - admin moderation,
  - downvote cluster investigation.

### Translation prompt requirements

The backend prompt must require structured JSON, not raw prose.

Expected output fields:

```ts
{
  translation: string;
  transliterationNotes?: string[];
  glossary: {
    sourceTerm: string;
    renderedTerm: string;
    rationale?: string;
  }[];
  confidence: number; // 0 to 1
  riskFlags: string[];
  sourceUse: {
    usedArabic: boolean;
    usedEnglishReference: boolean;
    usedGrounding: boolean;
    groundingSources?: string[];
  };
  shouldPublish: boolean;
}
```

### Translation rules

- Preserve meaning over literalness.
- Do not add commentary inside the translation.
- Do not invent authenticity grades.
- Do not translate honorifics inconsistently.
- Preserve named people.
- Use stable glossary per language:
  - salah,
  - zakah,
  - iman,
  - taqwa,
  - hadith,
  - isnad,
  - sunnah, etc.
- Store model version and prompt version.

### Caching policy

Cache by:

```txt
hadithId + sourceTextVersion + targetLanguage + promptVersion + modelFamily
```

Global cached translations are free to view. Quotas apply to generating new uncached translations, not viewing existing translations.

### Why cached translations should be free to view

- Makes the app useful.
- Encourages network effects.
- Avoids punishing users for popular languages.
- Keeps monetization focused on generating more coverage, priority queue, batch/offline features, and contribution tools.

### AI disclaimer

Required copy in translation details sheet:

> This translation was generated with Gemini and may contain mistakes. Hadithly users can rate it or suggest an improved translation. Authenticity grades are not determined by AI.

---

## 14. Paywall and subscription model

### Free plan

- Full reader.
- Arabic + English source text.
- View cached translations.
- 20 new AI translation generations/month.
- Like/dislike translations.
- Bookmarks/favorites/notes.
- Submit limited community suggestions.

### Trial

- 3 days.
- Pro limits.
- Shown after onboarding/auth and on first AI aha moment.
- Dismissible.

### Pro monthly

Recommended price:

- **$3.99/month** for MVP.

Includes:

- 500 new AI translation generations/month.
- priority translation queue,
- higher daily generation limit,
- advanced search across AI/community translations,
- offline language packs for selected collections when available,
- contribution tools with more submissions/reviews,
- Pro badge optional but not spiritually gamified.

### Pro annual

Recommended price:

- **$29.99/year**.

Position as:

- best value,
- supports translation coverage,
- helps maintain Hadithly.

### Paywall placements

1. **Post-auth soft paywall**
   - shown once after onboarding/auth,
   - after user chooses language and sees a translation preview,
   - dismissible.

2. **Contextual AI-limit paywall**
   - shown when free quota is exhausted,
   - explains exact reason:
     - “You have used 20/20 new AI translations this month.”

3. **High-intent paywall**
   - when user taps:
     - generate language pack,
     - batch translate a book,
     - advanced AI search,
     - priority translate.

### Paywall must not block

- Arabic/English reading.
- Previously cached translations.
- Existing bookmarks/favorites/notes.
- Viewing authenticity metadata.
- Viewing community translations.

### Mobile payment implementation

- iOS/Android: RevenueCat over App Store / Google Play billing.
- Web: Polar can be used as Merchant of Record.
- Do not route mobile in-app digital subscriptions to Polar from inside the app unless platform rules explicitly permit it in the user’s region and the implementation is reviewed.

---

## 15. Data model

### User

```ts
type User = {
  id: string;
  clerkId: string;
  email?: string;
  displayName?: string;
  username?: string;
  avatarUrl?: string;

  preferredLanguage: string; // BCP-47
  subscriptionTier: "guest" | "free" | "trial" | "pro";
  trialStartedAt?: number;
  aiGenerationsThisMonth: number;
  aiGenerationLimit: number;

  createdAt: number;
  updatedAt: number;
};
```

### Hadith source record

```ts
type Hadith = {
  id: string; // stable internal ID
  provider: "sunnah_now" | "sunnah_com" | "local_dump";
  providerHadithId: string;
  collectionSlug: string;
  bookId?: string;
  chapterId?: string;
  volumeId?: string;

  arabicText: string;
  englishText?: string;

  referenceDisplay: string;
  collectionName: string;
  bookName?: string;
  chapterName?: string;

  authenticityGrade?: "sahih" | "hasan" | "daif" | "mawdu" | "mixed" | "unknown";
  authenticityAppliesTo: "hadith" | "collection" | "none";
  authenticitySource?: string;
  authenticityConfidence: "source_provided" | "manual_mapping" | "unavailable";

  createdAt: number;
  sourceUpdatedAt?: number;
};
```

### Translation

```ts
type Translation = {
  id: string;
  hadithId: string;
  language: string;
  content: string;

  source: "official" | "gemini_ai" | "community";
  sourceLabel: "Official" | "Gemini AI" | "Community";
  aiModel?: string;
  aiPromptVersion?: string;
  generatedByUserId?: string;

  status: "live" | "pending" | "archived" | "rejected";
  isDefault: boolean;

  confidence?: number;
  riskFlags?: string[];
  groundingUsed: boolean;
  groundingSourceCount?: number;

  upvotes: number;
  downvotes: number;
  ratingPercent?: number;

  contributorUserId?: string;
  contributorDisplayName?: string;

  createdAt: number;
  updatedAt: number;
  approvedAt?: number;
};
```

### Translation vote

```ts
type TranslationVote = {
  id: string;
  userId: string;
  translationId: string;
  vote: "up" | "down";
  reason?: "meaning" | "language" | "missing_nuance" | "grammar" | "inappropriate" | "other";
  createdAt: number;
};
```

### Community submission

```ts
type CommunitySubmission = {
  id: string;
  hadithId: string;
  language: string;
  submittedBy: string;

  proposedContent: string;
  replacesTranslationId?: string;

  aiReview: {
    model: string;
    score: number;
    riskFlags: string[];
    missingMeaning?: string[];
    addedMeaning?: string[];
    glossaryIssues?: string[];
    recommendation: "approve" | "community_review" | "admin_review" | "reject";
  };

  status: "pending" | "approved" | "rejected" | "needs_admin";
  upvotes: number;
  downvotes: number;
  createdAt: number;
  reviewedAt?: number;
};
```

### Reading progress

```ts
type ReadingProgress = {
  id: string;
  userId: string;
  collectionSlug: string;
  bookId?: string;
  hadithId: string;
  scrollOffset?: number;
  visibleHadithId?: string;
  updatedAt: number;
};
```

### Notes/bookmarks/favorites

```ts
type Bookmark = {
  id: string;
  userId: string;
  hadithId: string;
  scrollOffset?: number;
  createdAt: number;
};

type Favorite = {
  id: string;
  userId: string;
  hadithId: string;
  createdAt: number;
};

type Note = {
  id: string;
  userId: string;
  hadithId: string;
  content: string;
  createdAt: number;
  updatedAt: number;
};
```

### Language coverage

```ts
type LanguageCoverage = {
  language: string;
  collectionSlug?: string;
  totalHadiths: number;
  officialCount: number;
  aiCachedCount: number;
  communityApprovedCount: number;
  missingCount: number;
  updatedAt: number;
};
```

---

## 16. Backend/API requirements

### API architecture

- Mobile app talks to:
  - Convex for reactive user/community data,
  - Next.js API for privileged operations:
    - Gemini,
    - hadith provider proxy,
    - payment webhooks,
    - cron jobs,
    - moderation tasks.

### Required API routes

```txt
GET  /api/hadith/books
GET  /api/hadith/book/:slug
GET  /api/hadith/book/:slug/hadith
GET  /api/hadith/book/:slug/hadith/:id
GET  /api/hadith/search

POST /api/translate/generate
POST /api/translate/review
POST /api/translate/report

POST /api/payments/revenuecat-webhook
POST /api/payments/polar-webhook

POST /api/cron/daily-hadith
POST /api/cron/reset-ai-usage
POST /api/cron/recompute-language-coverage
POST /api/cron/recompute-leaderboards
```

### Hadith provider adapter

Create a provider interface:

```ts
interface HadithProvider {
  listBooks(): Promise<Book[]>;
  getBook(slug: string): Promise<Book>;
  listHadiths(params: ListHadithParams): Promise<Paginated<Hadith>>;
  getHadith(slug: string, id: string): Promise<Hadith>;
  search(query: HadithSearchQuery): Promise<SearchResult[]>;
}
```

Implement:

- `SunnahNowProvider`
- optional future `SunnahComProvider`
- optional `LocalDumpProvider`

---

## 17. Moderation and trust

### User-generated content risks

Community translations are UGC. MVP needs:

- report button,
- banned words / abuse filters,
- spam throttling,
- contributor reputation,
- audit logs,
- admin override,
- rollback to previous translation.

### Approval policy

Do not rely on AI alone for every approval.

Suggested MVP policy:

- New users:
  - always pending community/admin review.
- Trusted users:
  - can auto-approve if Gemini score is high and no risk flags.
- High-impact hadiths:
  - require admin review if many readers or many downvotes.
- Downvote clusters:
  - if rating drops below 70% after 10+ votes, mark as “Needs review.”

---

## 18. Notifications

### Daily hadith

- User chooses notification time in onboarding.
- Notification language uses preferred language.
- If translation missing:
  - use English fallback,
  - or use cached Gemini translation if available.
- Notification opens exact reader deep link.

### Other notifications

- Translation approved.
- Translation receives milestone rating.
- Someone reports translation — admin only.

---

## 19. Offline behavior

MVP:

- Cache last opened collection/book.
- Cache daily hadith.
- Cache user bookmarks/favorites/notes locally.
- Queue votes and notes offline, sync later.

Phase 2:

- Download selected collection.
- Download selected language pack.
- Offline search over downloaded text.

---

## 20. Accessibility and localization

- Support RTL Arabic text.
- Respect device font scaling.
- Touch targets minimum 44pt.
- VoiceOver/TalkBack labels for:
  - authenticity chip,
  - AI badge,
  - rating,
  - vote buttons,
  - reader controls.
- Localize UI strings into:
  - English,
  - Russian,
  - Kazakh,
  - Turkish,
  - Uzbek,
  - Indonesian,
  - Urdu where possible.

---

## 21. Analytics events

```txt
onboarding_started
language_selected
notification_enabled
auth_started
auth_completed
paywall_viewed
trial_started
paywall_dismissed

reader_opened
reader_controls_shown
hadith_long_pressed
bookmark_created
favorite_created
note_created
share_tapped

translation_missing_seen
translation_generate_tapped
translation_generated
translation_cache_hit
translation_quota_exceeded
translation_liked
translation_disliked
translation_reported

community_submission_started
community_submission_submitted
community_submission_approved
community_submission_rejected
review_vote_submitted
```

Avoid collecting private note contents in analytics.

---

## 22. Phase plan

### Phase 0 — Design prototype

- Build the full visual system.
- Prototype:
  - onboarding,
  - home,
  - library,
  - reader default/active states,
  - reader settings sheet,
  - translation details sheet,
  - paywall,
  - community.

### Phase 1 — MVP

- Expo app shell.
- Auth.
- Hadith API provider adapter.
- Reader.
- Bookmarks/favorites/notes.
- Gemini translation generation.
- Translation cache.
- Rating controls.
- Basic paywall and quotas.
- Daily notification.
- Basic community submission.

### Phase 2 — Trust and community

- Review queue.
- Leaderboard.
- Contributor profiles.
- Admin moderation.
- Language coverage dashboards.
- Better search.

### Phase 3 — Growth

- Web reader.
- Share image cards.
- Widgets.
- Offline packs.
- Reading plans.
- Public language translation campaigns.

---

## 23. Acceptance criteria

### Reader

- Hadith text is continuous, not card-based.
- Metadata appears top-right of each hadith.
- Authenticity chip is visible and tappable.
- AI badge appears only for AI-generated/AI-reviewed translations.
- Rating percentage is visible when enough votes exist.
- Like/dislike work with optimistic UI.
- Long press opens context menu.
- Tap toggles reader chrome.

### AI translation

- Missing translation can be generated.
- Gemini output is structured and validated.
- Translation is cached globally.
- Quota increments only on uncached generation.
- Translation details sheet shows model/source/disclaimer.

### Paywall

- Paywall appears after onboarding/auth as dismissible.
- Paywall appears when free quota is hit.
- Paywall does not block basic reader.
- Mobile purchase uses RevenueCat/IAP.
- Web purchase can use Polar.

### Community

- Authenticated users can submit translation.
- Gemini review runs on submission.
- Pending queue exists.
- Approved community translation can become default.
- Old AI translation remains accessible.

---

## 24. Open questions

1. Is Hadithly final as the app name?
2. Which languages are absolute launch priorities: Kazakh, Russian, Uzbek, Turkish, Urdu, Indonesian?
3. Will you use only sunnah.now, or keep a fallback source/offline dump?
4. Do you want admin review in MVP or only AI+community review?
5. Should Pro include “priority language coverage campaigns” as a visible value prop?
6. Should the app allow guest notes locally, or require account for notes?
7. Should ratings apply to each translation version or to the hadith display as a whole? Recommendation: translation version only.
