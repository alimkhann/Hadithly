# Reader and product reference audit

This file records the evidence behind the post-launch plan. It is reference,
not an implementation checklist. Re-run the inventory if an image changes.

## Sajda screenshot inventory

Source directory: `/Users/alim/Downloads/sajda reader`

Audit date: 2026-09-02

All 16 images were opened with original-detail inspection. Every file is a
1206 by 2622 PNG. A filename is a behavioral note from the user, not an
instruction embedded in the image.

| File and SHA-256 | Observed behavior | Decision | Session |
| --- | --- | --- | --- |
| `arabic fonts and size.PNG`<br>`4ede9592ac6c8f50ddc0b79c8e0cf68d22bd9e7fd52086553dd75c5d0b326453` | A focused sheet chooses an Arabic face and size with a live preview. | Adopt the control pattern. Offer only fonts with verified redistribution licenses. | F2, R4 |
| `bookmarks tab under bookmarks and notes menu.PNG`<br>`0f170ab6063d2e0902835a0a97aa69367a578d911f972cb69350bbf3d7b9da8c` | Reader-saved locations live in a compact tabbed sheet. | Adapt into one full Saved destination with filters and folders. Do not bury the primary library behind a reader sheet. | H3 |
| `color themes options.PNG`<br>`c719c6d1a5da9379a27927d07e6edba93034011fc9c943bf55ca2a3010e3540e` | System, white, paper, and dark choices are visual and immediate. | Adopt as System, Light, Paper, and Dark with accessible contrast. | F2, R4 |
| `contents from menu.PNG`<br>`dbc06a7a4d7b5db350c748ca8a49721583d20ae078eb4953dedeb121378e8439` | Contents opens as a navigable sheet with progress context. | Adapt to collections, volumes, chapters, and jump-to-reference. Reject Quran-only grouping. | R5 |
| `context menu when holding ayah to do actions.PNG`<br>`a5eace0f6c50809c3321e088181f9e483b73f468e449064e434685c094f3a124` | Long press reveals actions without a permanent toolbar. | Adopt native context menus for save, favorite, note, copy, and share. Add contribution as a secondary overflow action. Reject playback and Siri until Hadithly has real audio. | R5 |
| `end of page reader.PNG`<br>`ae3244042de95c46b5610c6ef1c53e268489fdd35dd3a98d86e51a804649e3a1` | The page ends with clear previous and next movement. | Adapt to direction-aware hadith page navigation. Keep controls quiet and accessible. | R3, R4 |
| `favorites tab under bookmarks and notes tab from menu.PNG`<br>`752ff6a36a7ebc6fa26481efcb510d645addb4165f012007f5625f664c6052b6` | Favorites remain distinct from bookmarks. | Preserve the meaning as a Saved filter. Do not create a popularity signal. | H3 |
| `menu open.PNG`<br>`bc398a05d8cad7232641362a33efb81825a72eb3ec774d73c97e32b4d1a9f50f` | A compact menu groups contents, saved material, and reader settings. | Adapt into native sheets and menus. Keep global destinations in the tab bar and reader-only controls in the reader. | R5 |
| `middle of page, progress bar on top, notice minimal divisions between ayahs.PNG`<br>`ee0e0e29c8fe509c3b4d1b5f7b1b8c26a14d93045341b812d931e1dbc4af983a` | A thin progress indicator and restrained separators keep focus on text. | Adopt compact progress and minimal hadith dividers. Avoid card-per-hadith styling. | R4 |
| `new surah (could be new chapter in hadithly).PNG`<br>`b78b4033bca9a6c72e2840eac858bb135f81e360014fde4c5f785ec50e9c8545` | A new section receives a strong typographic divider. | Adapt to source-provided volume and chapter boundaries. Never invent a chapter. | F1, R4 |
| `notes tab under bookmarks and notes menu.PNG`<br>`33e415dbc697db3898136d319d5a23af3d27f355e054bdf91a0073c10fbb20ec` | Notes are private saved annotations with their reading target. | Preserve notes as a Saved filter and migrate them without data loss. | H3 |
| `only arabic.PNG`<br>`cfa4043bd605129e43fefd71ba15ddbdba11c6e99eb2932f574a770ad0da6d48` | The reader can hide translation and let Arabic fill the page. | Adopt Arabic-only mode. Auto direction becomes RTL. | F2, R3, R4 |
| `settings open from menu.PNG`<br>`df93e4bb4d0143ec0461384d9bf8d330a1ea7c62f9c81eb511c572c4dbfd2041` | Reader settings are close to the text and use direct controls. | Adapt for page-specific reading options. Keep account, storage, privacy, and subscription settings in global Settings. | R4, S1 |
| `start page reader.PNG`<br>`7206e67a017d7902c7d5319e400639a01fe1a554de3a090a141760922acb20bb` | The opening page has generous space and a clear section start. | Adopt the typographic hierarchy. Do not copy Quran ornament or labels. | R4 |
| `translation + arabic.PNG`<br>`2e056b903a82b0dff8ae95934dd90128cf9191f1b696c8d59e65bdc9b1b4c943` | Arabic and translation form one reading unit with different typographic roles. | Adopt mixed mode. Follow the translation language for page direction while each Arabic block stays RTL. | F2, R3, R4 |
| `when clicking anywhere in reader, these buttons that are hidden by default appear, bottom left (smart back from where was opened), menu open bottom right, top time, battery visible when by default is not and finally the progress pill expands.PNG`<br>`b8a789d992c021fae3dbea607c6cb1dcfe071fcb8f8e274ee3a3c599c911f86d` | A tap reveals status chrome, source-aware back, menu, and expanded progress. | Adopt hidden controls and entry-aware back behavior. Keep the system status transition native and accessible. | R2, R4 |

## Reader-session image obligations

Before making any R1 through R5 change, the assigned agent must open all 16
files above at original detail. This is a behavioral reference pass, not a
license to copy Quran-specific content, ornament, audio, Siri, reciter,
transcription, mushaf, surah, juz, or tafsir features. The following is the
implementation map for the reader sequence; use the exact filenames to make
the visual reference testable rather than relying on a prose recollection.

| Session | Images to apply in that session | Required adaptation |
| --- | --- | --- |
| R1 | All 16: orientation only; no visual implementation. | Preserve enough semantic position data that the later text-first layouts can recover accurately after a preference or pagination change. |
| R2 | `when clicking anywhere in reader, these buttons that are hidden by default appear, bottom left (smart back from where was opened), menu open bottom right, top time, battery visible when by default is not and finally the progress pill expands.PNG` | Restore targets without breaking the source-aware back behavior that the revealed chrome will use in R4. |
| R3 | `end of page reader.PNG`; `only arabic.PNG`; `translation + arabic.PNG` | Direction-aware previous/next behavior, Arabic-only RTL reading, and mixed-script reading units with Arabic locally RTL. |
| R4 | `arabic fonts and size.PNG`; `color themes options.PNG`; `end of page reader.PNG`; `middle of page, progress bar on top, notice minimal divisions between ayahs.PNG`; `new surah (could be new chapter in hadithly).PNG`; `only arabic.PNG`; `settings open from menu.PNG`; `start page reader.PNG`; `translation + arabic.PNG`; `when clicking anywhere in reader, these buttons that are hidden by default appear, bottom left (smart back from where was opened), menu open bottom right, top time, battery visible when by default is not and finally the progress pill expands.PNG` | Native reader controls, compact/expanded progress, type and theme controls, source-provided boundaries, restrained dividers, and clear Arabic/translation hierarchy. |
| R5 | `contents from menu.PNG`; `context menu when holding ayah to do actions.PNG`; `menu open.PNG` | Source-provided outline navigation and native context actions. Keep Saved global, add no audio/Siri action, and share only the F3 canonical URL. |

The three private-saved references — `bookmarks tab under bookmarks and notes
menu.PNG`, `favorites tab under bookmarks and notes tab from menu.PNG`, and
`notes tab under bookmarks and notes menu.PNG` — remain assigned to H3. They
are reviewed during every reader-session orientation pass but must not pull H3
scope into R1 through R5.

## Current code audit

### Reader

- Both clients use content-sized server pages and a vertical scroll inside each
  page.
- iOS uses a window-level `UIPanGestureRecognizer`. Android uses
  `HorizontalPager`. Neither implementation derives paging direction from the
  reading language.
- Arabic and translation always appear together. The clients have no visibility
  invariant or translation-only mode.
- Convex accepts `scrollOffset` for bookmarks and progress, but clients neither
  send a meaningful offset nor restore one.
- Progress stores a target hadith and page. It has no content version, semantic
  anchor, layout signature, or migration policy.
- The reader shows permanent bookmark, favorite, note, contribution, and report
  controls. That creates more interface than the text needs.
- Contents navigation lists volumes. It does not expose a source-provided chapter
  hierarchy or a direct reference jump.

### Today and notifications

- Today renders Arabic and provider English rather than the selected translation
  language.
- Long content has no deliberate collapse, expand, or internal-scroll policy.
- Daily selection hashes the current cache and does not filter by authenticity.
- Push sends provider English or Arabic fallback. It does not resolve the saved
  translation locale.
- Push tokens store a fixed timezone offset. DST and timezone changes can shift
  delivery.
- Android writes target extras to the notification intent, but `MainActivity`
  does not consume them. iOS has no complete notification-response route.

### Library, Saved, and Settings

- Library shows cached volume and hadith counts, not reading progress. It repeats
  the global Continue Reading card already shown on Today.
- Saved begins with three cards and opens separate sheets. It has no folders.
- Settings covers account, Arabic size, translation language, notifications, and
  an admin queue. It lacks a separate UI language, appearance, reading direction,
  offline storage, subscription status, privacy, help, legal, export, and a
  complete profile.
- The admin queue is a privileged operations tool placed inside the consumer app.

### Authenticity, links, and offline data

- The backend stores authenticity fields. The provider adapter also adds manual
  collection mappings for Bukhari and Muslim. Clients do not show the source,
  confidence, or scope.
- There is no universal link, Android App Link, canonical web page, or fallback
  site.
- There are no versioned offline dumps, translation packs, manifests, download
  state machines, or update migrations.
- There are no native widgets.

### Contributions and AI quota

- The current contribution prompt places the user's proposal in a model prompt
  without an evidence boundary. The next version must treat every proposal,
  upload, OCR result, and webpage as hostile data.
- The schema has submissions, reports, translations, and audit rows. It has no
  evidence assets, license assessments, publication revisions, appeals, or
  abuse records.
- Admin approval is the normal publication path. The new design makes it an
  exception path.
- The launch quota is a monthly counter with 20 free and 500 paid generations.
  The agreed model is five and 100 new generations per rolling seven days.
- RevenueCat currently exposes weekly, monthly, and annual Test Store packages.
  The product plan keeps monthly and annual only.

## Product recommendations from the audit

- Keep Today as the single home destination. Do not add a second dashboard.
- Keep the Library about collections and progress. Search remains deferred.
- Keep all Saved material private. Folders organize personal reading; they do
  not become shareable collections.
- Show authenticity next to the reference when space allows and in a source
  sheet when it does not. Do not turn grades into colored scores.
- Make AI generation an exception after cache and approved-source lookup. The
  best cost optimization is not generating the same translation twice.
- Build the fallback web page before Share UI. A share button without a durable
  destination is a broken promise.
- Keep only Daily Hadith and Continue Reading widgets. More widgets would add
  maintenance and privacy risk without improving the core journey.
- Require affirmative licensing records. A technically accessible source is not
  automatically reusable.
- Keep administrative work off the reader's phone. A secured web or dashboard
  tool is easier to audit and less likely to leak privileged controls.

## Regenerate the inventory

```sh
for file in "/Users/alim/Downloads/sajda reader"/*.PNG; do
  basename "$file"
  shasum -a 256 "$file"
  sips -g pixelWidth -g pixelHeight "$file"
done
```
