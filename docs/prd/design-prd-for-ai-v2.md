# Hadithly — Design PRD for Figma Make AI / Claude Design v2

**Purpose:** Pasteable design specification for generating a premium mobile app design.  
**Platforms:** iOS first, Android adapted.  
**Style goal:** Minimal, sacred, modern, book-like, impeccable.  
**Design direction:** Premium Islamic reader + calm AI transparency + subtle community trust layer.

---

## 1. Design north star

Design Hadithly as if Apple Books, Quran.com, Linear, and a premium Islamic manuscript reader were merged into one calm mobile app.

It should feel:

- quiet,
- trustworthy,
- spacious,
- precise,
- premium,
- spiritual without being decorative,
- modern without looking like generic SaaS,
- AI-assisted without looking like a chatbot app.

Avoid:

- clutter,
- heavy cards in the reader,
- loud gradients,
- fake glass everywhere,
- gamified religious aesthetics,
- cheap Islamic clip-art,
- excessive green/gold,
- emoji-heavy UI,
- dashboard-like complexity.

---

## 2. Visual identity

### Brand mood

- “A beautiful hadith reader in your language.”
- “AI-assisted, community-improved, source-aware.”
- Not “AI hadith app.”

### Logo direction

Simple wordmark + small geometric mark.

Possible mark concepts:

- small book opening into a subtle star,
- minimal arch-shaped bookmark,
- dot-and-line isnad chain abstracted into a quiet symbol,
- folded page with a small light point.

Do not use:

- mosque silhouettes,
- crescent clichés,
- overused calligraphy marks unless custom and minimal.

---

## 3. Color system

Use soft neutral foundations with one restrained accent.

### Light theme

```txt
Background:        #FBF8F1   warm paper
Surface:           #FFFFFF / #F6F0E6
Text primary:      #1B1A17
Text secondary:    #6F6A5E
Text tertiary:     #9B9486
Hairline:          #E8DFD0

Accent:            #0F766E   deep teal
Accent soft:       #DDF3EE
Gold detail:       #B8893B   use rarely
Success:           #15803D
Warning:           #B7791F
Danger:            #B91C1C
```

### Dark theme

```txt
Background:        #11100D
Surface:           #1A1814
Surface raised:    #232018
Text primary:      #F5EFE3
Text secondary:    #BFB6A4
Text tertiary:     #837968
Hairline:          #302B23

Accent:            #5EEAD4
Accent muted:      #164E46
Gold detail:       #D6B06B
```

### Sepia reader theme

```txt
Background:        #F4ECD8
Text:              #241D13
Muted:             #8A7B63
Divider:           #D8C8A5
Accent:            #7C5C2E
```

### Rule

Use accent color for interaction and state, not decoration.

---

## 4. Typography

### Arabic text

Use a beautiful Arabic reading font.

Recommended options:

- KFGQPC Uthmanic Script Hafs
- Noto Naskh Arabic
- Amiri Quran / Amiri
- Scheherazade New

Reader Arabic default:

```txt
Font size: 26–30pt
Line height: 2.0–2.2x
Alignment: right
Letter spacing: normal
```

### Translation text

Recommended options:

- iOS: New York / Georgia-like serif for reader translation, SF Pro for UI
- Cross-platform: Literata, Source Serif 4, or system serif for reader; Inter/Outfit for UI
- If keeping one app font: use system UI with excellent spacing.

Reader translation default:

```txt
Font size: 17–19pt
Line height: 1.65–1.85x
Alignment: left in LTR languages, right in RTL languages
```

### UI text

Use SF Pro-like sizing hierarchy:

```txt
Display: 32/38 semibold
Title: 24/30 semibold
Section: 17/24 semibold
Body: 16/24 regular
Caption: 12/16 medium
Micro: 11/14 medium
```

---

## 5. Spacing and layout

Base spacing scale:

```txt
4, 8, 12, 16, 20, 24, 32, 40
```

Screen padding:

```txt
Home / Library / Community / You: 20–24
Reader: 24 horizontal, responsive max text width
Bottom sheets: 20–24
```

Corner radius:

```txt
Small: 10
Medium: 16
Large: 24
Pill: 999
```

Shadows:

- Use extremely soft shadows.
- Prefer hairlines and background layering over heavy elevation.

---

## 6. Motion and haptics

Motion must feel calm and intentional.

### Use motion for

- reader chrome fade in/out,
- progress pill expansion,
- bottom sheet spring open,
- vote micro-feedback,
- bookmark save,
- language coverage fill,
- paywall benefit reveal.

### Avoid

- bouncy cartoon animations,
- confetti for religious reading,
- aggressive gamification.

### Haptics

- light impact on like/dislike,
- selection haptic on language picker,
- medium impact on bookmark save,
- soft notification permission confirmation.

---

## 7. Component system

Use React Native Reusables / shadcn-inspired primitives where possible:

- Button
- Card
- Sheet / Bottom Sheet
- Dialog
- Tabs / Segmented Control
- Input
- Textarea
- Switch
- Slider
- Badge
- Progress
- Avatar
- Separator
- Toast
- Context menu/action sheet

Design components should map cleanly to React Native implementation.

---

## 8. Main screens to design

Create these frames for iPhone first:

1. Splash
2. Onboarding — Welcome
3. Onboarding — Language selection
4. Onboarding — Daily hadith notification
5. Onboarding — Translation preview / aha moment
6. Auth
7. Soft paywall after auth
8. Home
9. Library
10. Collection detail
11. Reader default state
12. Reader active state
13. Reader settings sheet
14. Translation details sheet
15. Reader context menu
16. Search
17. Community
18. Review translation screen
19. User/Profile
20. Settings

Then create Android variants for:

- Home
- Reader
- Paywall
- Bottom sheet

---

## 9. Onboarding design

### Screen 1 — Welcome

Content:

```txt
Hadithly
Read hadith in your language.

Arabic and English source text,
Gemini-assisted translations,
community-improved over time.
```

Visual:

- warm paper background,
- simple logo,
- one elegant hadith reference preview,
- no clutter.

CTA:

- Continue

### Screen 2 — Language

Title:

```txt
Choose your reading language
```

Subtitle:

```txt
Hadithly shows available coverage and can generate missing translations with Gemini.
```

Language rows:

```txt
Kazakh     12% community · AI available
Russian    38% community · AI available
Turkish    22% community · AI available
English    Official
Arabic     Source
```

Row details:

- language name,
- native name,
- coverage pill,
- AI available badge.

### Screen 3 — Daily hadith

Title:

```txt
A hadith every day
```

Controls:

- notification toggle,
- time picker,
- language preview.

Default:

- toggle ON but ask permission respectfully.

### Screen 4 — Translation aha moment

Show a real-looking hadith preview with:

- Arabic,
- English,
- chosen language translation,
- top-right `Gemini AI`, `New`, thumbs.

This is the moment before paywall.

Copy:

```txt
When a translation is missing, Hadithly can generate one and let the community improve it.
```

### Screen 5 — Auth

Use premium auth sheet.

Options:

- Continue with Apple
- Continue with Google
- Continue with Email
- Continue as Guest

Small copy:

```txt
Create an account to sync notes, bookmarks, and translation contributions.
```

### Screen 6 — Soft paywall

Shown after auth or guest continuation.

Title:

```txt
Help bring hadith to every language
```

Benefits:

- 500 Gemini translations/month
- Priority translation queue
- Offline language packs when available
- More contribution/review tools
- Supports Hadithly

Pricing:

- Monthly $3.99
- Annual $29.99, highlighted as best value
- 3-day free trial

Buttons:

- Start 3-day trial
- Continue free
- Restore purchases

Design:

- full-screen sheet or modal page,
- calm, high-trust,
- no manipulative close hiding.

---

## 10. Home design

### Structure

Top:

- small greeting,
- language chip,
- search bar.

Main:

- Daily Hadith card,
- Continue Reading,
- topic shelves,
- collection shortcuts.

### Daily Hadith card

Must include:

- reference,
- authenticity chip,
- Arabic preview,
- chosen-language translation preview,
- source badge,
- rating chip if translation exists,
- CTA.

Keep card beautiful but not bulky.

### Topic shelves

Use small elegant horizontal chips/cards:

- Faith
- Prayer
- Character
- Knowledge
- Fasting
- Charity

---

## 11. Library design

Collection row/card:

```txt
Sahih al-Bukhari
صحيح البخاري
7,563 hadith · Collection: Sahih
Kazakh coverage 12%
[Continue]
```

Visual:

- low-height rows,
- subtle progress bars,
- no huge icons.

Filters:

- All
- Sahih
- Popular
- Downloaded
- Needs translation

---

## 12. Reader design — most important

### Design intent

The reader must not feel like scrolling social cards. It should feel like reading a refined digital book.

### Reader default state frame

Visible:

- full-screen warm paper background,
- tiny progress pill at top center,
- continuous text,
- reference dividers,
- hadith metadata top-right.

Hidden:

- app header,
- tab bar,
- bottom buttons,
- status bar if possible.

### Hadith block layout

Each hadith block:

```txt
                 [Sahih] [Gemini AI] [94%] [↑] [↓]

Arabic text right-aligned with generous line-height.

Translation text below in selected language.

                    — Bukhari 1:1 —
```

Alternative if divider above:

```txt
                    Bukhari 1:1

                 [Sahih] [Gemini AI] [94%] [↑] [↓]

Arabic text...

Translation...
```

### Top-right metadata design

Use tiny pills, not loud badges.

- Authenticity: outlined chip.
- AI/source: soft filled chip.
- Rating: plain text inside small pill.
- Like/dislike: micro icon buttons.

States:

```txt
[Sahih] [Gemini AI] [New] [↑] [↓]
[Sahih] [Community] [96%] [↑ selected] [↓]
[Grade unavailable] [Official EN] [—]
[Needs review] [Gemini AI] [62%] [↑] [↓]
```

Important:

- Rating percentage means translation rating, not authenticity.
- Authenticity is separate and must visually read as separate.

### Reader active state frame

On tap, show:

- status bar,
- expanded progress pill:
  - “Page 12 · 38%”
  - fill behind the text.
- bottom-left circular Home button,
- bottom-right circular Menu button,
- right-side bookmark button,
- right-side search button below.

Buttons:

- translucent surface,
- blur/glass on iOS,
- Material-style surface on Android,
- haptic on tap.

### Reader menu sheet

Bottom sheet title:

```txt
Reader
```

Rows:

- Book contents
- Bookmarks, favorites, notes
- Search in this book
- Reader settings
- Translation details
- Report issue

### Reader settings sheet

Use grouped sections:

Display:
- Arabic
- Translation

Language:
- Translation language row with coverage %

Typography:
- Arabic size slider
- Translation size slider
- Arabic font
- Translation font
- Line spacing

Appearance:
- Auto / Light / Dark / Sepia
- Background texture
- Reduce effects

Behavior:
- Haptics
- Keep screen awake
- Hide status bar

### Translation details sheet

This sheet opens from AI/source badge.

Header:

```txt
Translation details
```

Fields:

```txt
Source: Gemini AI
Model: Gemini Flash
Generated: May 23, 2026
Language: Kazakh
Rating: 94% positive from 32 votes
Grounding: Used / Not used
Status: Live
```

Copy:

```txt
This translation was generated with Gemini and may contain mistakes. Authenticity grades are not determined by AI.
```

Actions:

- Suggest improved translation
- View original English
- Report translation

### Authenticity details sheet

Header:

```txt
Authenticity
```

Fields:

```txt
Grade: Sahih
Applies to: collection / hadith
Source: source dataset / manual mapping
```

Copy:

```txt
Hadithly displays authenticity metadata from source datasets. If a per-hadith grade is unavailable, the app shows collection-level information only.
```

---

## 13. Search design

Search screen:

- large search input,
- collection filter chips,
- language filter,
- recent searches,
- results list.

Result item:

- reference,
- authenticity chip,
- Arabic snippet,
- translation snippet with highlight,
- source badge.

Reader search variant:

- compact bottom sheet,
- supports:
  - text,
  - page,
  - hadith number,
  - chapter name.

---

## 14. Community design

### Top panel

```txt
Kazakh translation progress
12% community approved
38% Gemini cached
50% missing
```

Use a beautiful stacked progress bar.

### Leaderboard

Rows:

```txt
#1  Aigerim
124 approved · 96% avg rating · Kazakh
```

Keep it humble; avoid flashy trophies everywhere.

### Review queue

Card-like comparison is okay here, unlike reader.

Show:

- reference,
- Arabic collapsed preview,
- current translation,
- suggested translation,
- Gemini QA status,
- approve / downvote / report.

### My contribution profile

Stats:

- approved,
- pending,
- average rating,
- languages contributed.

---

## 15. Profile / You design

Top:

- avatar,
- name,
- language,
- Pro/free badge.

Stats:

- reading streak,
- hadiths read,
- bookmarks,
- notes,
- contributions.

Shortcuts:

- Bookmarks
- Favorites
- Notes
- My translations
- Settings
- Manage subscription

---

## 16. Paywall design

### Placement

Design two variants:

1. **Post-onboarding paywall**
   - calmer, mission-oriented.
   - after user saw translation preview.

2. **Quota-hit paywall**
   - contextual.
   - “You used 20/20 free Gemini translations this month.”

### Layout

Top:

- headline,
- one beautiful translation preview,
- mission/support subtext.

Middle:

- benefits list with checkmarks.

Pricing cards:

- Annual highlighted.
- Monthly secondary.

Bottom:

- primary CTA,
- continue free,
- restore purchases,
- terms/privacy microcopy.

### Copy

Headline options:

```txt
Bring hadith to every language
```

```txt
Continue translating with Gemini
```

```txt
Support better translations
```

Benefit copy:

```txt
500 Gemini translations each month
Priority translation queue
Offline language packs when available
More contribution and review tools
Supports a cleaner hadith reader
```

---

## 17. Empty, loading, and error states

### Missing translation

Inline:

```txt
No Kazakh translation yet.
Generate with Gemini or help translate it.
```

Buttons:

- Generate with Gemini
- Suggest translation

### AI loading

Use calm skeleton:

```txt
Generating translation…
Checking wording…
Saving translation…
```

No flashy “AI magic.”

### AI error

```txt
Translation could not be generated.
Try again later or read the English version for now.
```

### Low-rated translation

Show subtle warning chip:

```txt
Needs review
```

Not alarmist.

---

## 18. Platform adaptation

### iOS

- Use translucent floating controls.
- Native-feeling sheets.
- Soft blur where appropriate.
- Respect safe areas.
- Reader can use hidden status bar.

### Android

- Use Material-like surfaces.
- Avoid excessive iOS glass.
- Use native back behavior.
- Use Android typography scaling.
- Bottom sheets and ripples should feel Android-native.

---

## 19. Figma Make AI master prompt

Paste this into Figma Make AI:

```txt
Create a premium cross-platform mobile app design for “Hadithly”, an Islamic hadith reader for iOS and Android.

The app is a minimal, beautiful, book-like hadith reader with Arabic and English source text, Gemini AI translations into many languages, community translation suggestions, authenticity metadata, and translation rating feedback.

Design style:
- minimal, warm, premium, sacred, modern
- calm paper-like backgrounds
- deep teal accent, rare gold details
- no clutter, no heavy dashboards, no cheap Islamic clip art
- no card-based reader; reader should feel like a continuous digital book
- iOS-first with subtle glass controls; Android variants should feel Material-native

Required screens:
1. Splash
2. Onboarding welcome
3. Language selection with coverage indicators
4. Daily hadith notification setup
5. Translation preview / aha moment
6. Auth screen
7. Soft paywall after auth
8. Home
9. Library / collections
10. Collection detail
11. Reader default state
12. Reader active state
13. Reader settings bottom sheet
14. Translation details sheet
15. Authenticity details sheet
16. Reader context menu
17. Search
18. Community tab
19. Review translation screen
20. Profile / You
21. Settings

Critical reader requirements:
- Full-screen immersive reader
- Status bar hidden by default
- Thin progress pill at top center
- Continuous text, not cards
- Multiple hadiths per page/viewport
- Arabic text right-aligned, large, elegant, high line-height
- Translation below Arabic
- Each hadith has a subtle reference divider
- At the top-right of each hadith block, show a compact metadata row:
  [Authenticity chip] [Translation source / AI badge] [Rating percentage] [Like] [Dislike]
- Examples:
  [Sahih] [Gemini AI] [94%] [↑] [↓]
  [Collection: Sahih] [Community] [New] [↑] [↓]
  [Grade unavailable] [Official EN] [—]
- Rating percentage means community rating of translation only, not hadith authenticity.
- AI badge appears only when the translation is generated or reviewed by Gemini.
- Tapping the page reveals status bar, expanded progress pill, bottom-left home button, bottom-right menu button, side bookmark and search buttons.

Onboarding/paywall:
- Paywall should appear logically after onboarding/auth and after the user sees a translation preview.
- Also design a quota-hit paywall for when free users use all monthly Gemini translations.
- Paywall must be elegant, transparent, and dismissible.
- Free plan includes basic reader and cached translations.
- Pro: 3-day trial, $3.99/month, $29.99/year, 500 Gemini translations/month, priority queue, offline language packs when available.

Community:
- Language-specific leaderboard
- Translation coverage stats
- Help review pending translations
- Profile stats by language
- Keep community design humble, not overly gamified.

Use polished mobile UI components:
- buttons, badges, sheets, segmented controls, sliders, progress bars, cards where appropriate outside the reader
- haptic/motion annotations
- light, dark, and sepia reader states
- accessible touch targets and readable typography

Output high-fidelity mobile frames with a coherent design system, reusable components, and annotations for interaction states.
```

---

## 20. Claude Design / Claude Code design prompt

Paste this into Claude for a design system + React Native component plan:

```txt
You are designing Hadithly, a premium Islamic hadith reader mobile app for Expo React Native.

Create a complete design system and screen-level UI spec. The app must be minimal, beautiful, book-like, and trustworthy. It uses Gemini AI translations, community translation feedback, authenticity metadata, bookmarks, notes, daily hadith notifications, and a freemium paywall.

Important constraints:
- Reader is not card-based.
- Reader is continuous, like a digital book.
- Status bar hidden by default in reader.
- Progress pill at top.
- Tap reveals reader chrome.
- Every hadith block has top-right metadata:
  authenticity chip, source/AI badge, rating percentage, like/dislike.
- Authenticity is separate from rating.
- AI badge is shown only for Gemini AI-generated or AI-reviewed translations.
- Paywall appears after onboarding/auth and when AI quota is hit.
- Basic reading should remain free.

Produce:
1. design tokens,
2. component list,
3. navigation layout,
4. screen-by-screen layout,
5. reader interaction specification,
6. bottom sheet specifications,
7. paywall copy/layout,
8. accessibility notes,
9. implementation notes for Expo React Native with NativeWind/React Native Reusables.
```

---

## 21. Design acceptance checklist

A design is successful only if:

- The reader looks premium enough to be the heart of the app.
- The UI does not feel like generic SaaS.
- AI is visible but not dominant.
- Authenticity is visible and not confused with translation rating.
- Paywall feels logical and respectful.
- Community features are useful but not distracting.
- The app can be understood in under 30 seconds.
- The design can realistically be built in Expo React Native.
