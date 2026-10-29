# A4 runtime localization

October 27, 2026. A4 is active. B, C and D local work is committed. A4–A7 and E
remain in scope; native review and all existing release gates remain open.

The fifteen locales are en, ar, ru, kk, ky, uz, tr, id, ur, fr, es-419, pt-BR, sw,
hi and bn. GPT-family draft generation is local; no translation endpoint or paid
provider is used. Drafts are not native-speaker approval.

## First bounded repair

The visible Today empty state uses `Your daily reading` and the full message
`Today’s hadith is not available yet. Choose a collection below to keep reading.`
Both keys were absent. The incoming draft for `Today's reading is not available
yet.` is unused and did not repair that view. The actual title and full collection
guidance now have scoped drafts for all fifteen locales on both apps.

`docs/a4-runtime-copy.json` and the existing scoped generator reproduce this
repair. One native test per platform drives Arabic, Russian, Kazakh and English
through the actual Today empty view. Both failed before the resource additions
and pass afterward. The remaining eleven runtime locale checks stay open.
Native-review approval remains open for every non-English draft.

The audit now compares formatter argument multisets per string and plural unit,
including repeated arguments, numbered reordering and escaped percent signs.
Six regression cases reproduced audit gaps and pass after their fixes. Independent
review found the last case: an empty Android plural with no formatter argument
previously passed. Every localized plural item now needs text. The audit also
counts nested iOS plural string units correctly. The stricter audit flags six
Arabic zero/dual forms where the count is expressed by the wording rather than a
formatter argument. Those grammatical forms are unchanged and remain explicit
review findings; the full resource audit is not claimed green.

Current post-repair inventory: 303 iOS catalog keys, 4,378 draft locale entries;
318 Android resources and 1,374 English-identical candidates. English identity
can be valid for a name or symbol. The old hardcoded scan still reports 280 Swift
and 240 Kotlin candidates, including already-localized calls and debug fixtures.
Next, distinguish real runtime-key gaps and direct unlocalized text from those
candidates, audit every Android XML file and plural form, and repair genuine
normal-use copy defects. Keep RTL, fallback, accessibility, widget, notification,
purchase/privacy and critical-copy review coverage explicit.

All pre-existing catalog bytes remain preserved. Only the two new runtime keys
are staged. `scripts/stage-new-catalog-copy.py` inserts new keys into the existing
Git index without copying unrelated working-tree edits. A real temporary Git
fixture proves preservation and idempotent reruns. Existing indexed keys cannot
be replaced by this helper. The four incoming Xcode/project scheme files remain
unchanged and excluded.

Evidence is in `verification/a4-localization/first-unit.json`, the captured native
screens and `audit-exact.txt`. No full A4, localization, native-speaker or release
acceptance is claimed by this first repair.

## Shared copy and reading progress, October 28

Library and Today reading progress now use localized labels and locale-formatted
counts instead of constructing English strings. Five new keys have fifteen-locale
drafts in `a4-reading-progress-copy.json`. The scoped catalog staging helper keeps
the incoming catalog edits separate.

`a4-shared-copy-aliases.json` records 82 existing iOS keys and 83 Android resource
targets. The generator reads only the Git-indexed iOS versions when applying these
aliases, preserving their draft status. It repairs 1,140 differing locale values
without overwriting the incoming iOS drafts. Eight ambiguous resource matches were
excluded for contextual review. The English-identical Android candidate count
falls from 1,374 to 493; this is an inventory change, not native approval.

Wiring the existing numeric allowance copy exposed an Android formatter crash:
`nativeText` wrapped every argument as a string, including `%d` integers. Only
text arguments now receive bidi isolation; numeric arguments retain their types.
The native regression reproduced `IllegalFormatConversionException` before the
fix. A real temporary Git fixture checks indexed-copy provenance, multiple aliases,
Kotlin dollar escaping, unchanged incoming catalog bytes and idempotent reruns.

Expanding the actual Today-empty and Library-progress checks beyond en/ar/ru/kk
found an Android Indonesian resource-selection failure. `values-id` was packaged
but not selected for the app's Indonesian configuration. All three resource files
now use `values-in`; the generators, audit and resource tests use that same folder.
The public/backend locale identifier remains `id`. This is a resource packaging
repair. The failing all-locale run is retained with the evidence.

Android's default `ar` number formatter returns Latin digits on the tested OS;
iOS's returns Arabic-Indic digits. Preserve each platform's locale formatting.
The Android UI check additionally selects `ar-u-nu-arab` and requires Arabic-Indic
digits, proving the formatter follows the selected numbering system. This agrees
with [Unicode's Arabic numbering data](https://www.unicode.org/cldr/charts/49/verify/numbers/ar.html).
[Android's language-code behavior](https://developer.android.com/about/versions/15/behavior-changes-15#openjdk-api-changes)
and the actual compiled-resource/native readbacks are distinct evidence; source
folder presence alone did not prove Indonesian runtime coverage.

The actual Today-empty and Library-progress views pass in all fifteen locales on
both platforms (two iOS UI cases and three Android UI cases, including the typed
formatter regression). Five Android resource unit cases and seven Python tool
regressions pass. The progress UI additionally checks the Arabic numbering-system
override. Forty-five iOS and thirty-one Android captures are archived locally; selected
examples and their manifest are in `verification/a4-localization/progress/`. The
combined run record is `verification/a4-localization/reading-progress.json`.

Screenshot review caught an incorrect Abu Dawood slug in the iOS DEBUG fixture;
the corrected fixture and explicit stale-state assertion pass the final
fifteen-locale progress rerun. Count and lower-row captures are both retained. The Today continuation caption retains the stored/provider reference display,
including “Hadith”; its citation context needs review before changing that text.

Native-speaker approval, full runtime
copy classification, critical-copy review, widgets/notifications and the broader
A4–A7/E program remain open. The stricter resource audit still reports the same
six Arabic zero/dual formatter findings. No production or external action was used.

Independent source review identified the next real runtime gaps: Contents passes
a conditional `String` directly to `Text`, Saved undo banners display stored
English strings, and several folder/action/VoiceOver labels lack catalog entries
or bypass lookup through conditional expressions. These findings take priority
over the crude scanner's raw candidate totals. Android's folder/removal/Cancel
resources are still English-identical and cannot supply translated drafts.

## Contents, Undo and missing controls, October 28

Native red checks reproduced two lookup failures. The Contents footer passed a
conditional `String` directly to `Text` on iOS and directly to Material `Text` on
Android. Both now resolve their guidance/error keys. iOS Undo notices now carry
`LocalizedStringKey`, preserving folder-name interpolation and allowing the banner
to resolve the selected UI language. The existing five-second lifetime, action and
restoration paths are unchanged.

`a4-saved-contents-copy.json` adds forty-two missing iOS catalog keys across all fifteen
locales and updates their Android resource aliases. Eleven are new GPT-family
drafts for folder actions, jump accessibility/validation and folder-deletion
notices. Thirty-one reuse complete existing Android drafts from `a5c2407`, with
source resource names retained in the JSON. None is native-speaker approval.
`a4-contents-hint-alias.json` reuses the indexed iOS hint for Android without
writing the catalog. The same generator and precise catalog staging helper remain
in use. Full resource audit findings remain the six Arabic zero/dual forms;
English-identical Android candidates fall from 493 to 367.

The Contents guidance/invalid-input paths pass all fifteen locales on both apps.
The well-formed/invalid Go checks retain their normal dismissal/inline behavior.
iOS's separate real reader interaction removes a bookmark and restores it through
Undo. The final fifteen-locale Undo and consolidated Android reruns pass. The combined
record has five latest iOS cases, four Android UI cases and five Android
resource unit cases; no skipped case is counted
as passed. `verification/a4-localization/contents-undo.json` retains red runs and
the corrected-fixture reruns. Selected captures and the complete 31-iOS/15-Android
capture manifest are in `verification/a4-localization/contents-undo/`.

Two verification corrections are explicit. SwiftUI surrounds an interpolated
English folder name with directional isolates in Arabic; the exact-text check
ignores only directional formatting marks and still requires every translated
word and the unchanged name. The earlier Android malformed-jump check hardcoded
an English expectation despite inheriting the Arabic device locale. It now expects
the current locale's actual resource. These are test corrections, distinct from
the production lookup fixes.

`localization_audit.py --runtime-report PATH` now exports source/line candidates
classified as missing keys/mappings, dynamic/direct-string review, examples,
DEBUG fixtures or catalog-backed but runtime-unverified. The lexical report
explicitly excludes any claim of comprehensive Swift/Kotlin dataflow analysis.
It exposes further auth, accessibility, settings and conditional/wrapper gaps;
resource presence never counts as rendered localization. Ten Python audit
regressions plus the isolated generator fixture pass.

The remaining full A4 runtime/accessibility, native-review, widget/notification,
critical-copy and release gates remain open. Continue those repairs before the
remaining A5–A7/E work. No deployment, paid call, publication or account change was
performed.

Capture review found two further missing iOS keys behind the custom sheet-title
wrapper: Contents and Volumes. Both now reuse existing Android drafts, with an
explicit new resource for the title-case Volumes key so Android's existing
uppercase heading stays unchanged. The final iOS Contents rerun asserts both
headings in every locale. The lexical inventory now also recognizes the custom
sheet and navigation-title wrappers. Chapter/source names remain verbatim.

The next source priorities include unbound Android privacy/appearance wording,
auth field labels and remaining Saved/Reader accessibility labels. Some native
mapper findings may be prepared examples or superseded text; inspect each caller
before changing a content/provenance claim. The report is a candidate list, not
an instruction to translate user notes, provider citations or source titles.

## Privacy disclosures, October 28

Android privacy source used unmapped English analytics/crash phrases and an
unmapped authenticated-export description. Its label also said “anonymous usage” while iOS uses the existing private
usage-statistics label. Android now resolves the same label and disclosure wording
as iOS. Both crash footers explicitly retain the exclusion of reading text, notes
and account details, and explain clearing pending reports on this device. The
existing analytics and diagnostics implementations retain their defaults, consent
setters, serialized allowlists, collection, queue and retention behavior.

`a4-privacy-copy.json` contains seven scoped keys. Two are the earlier incoming
analytics/export paragraph drafts, now explicitly staged by key without changing
their working text. The crash paragraph, Policies heading and three policy-link labels are new
local GPT-family drafts. `a4-privacy-aliases.json` reuses the indexed `la2.usage` copy for
Android. The new paragraph avoids adding a server-retention claim. All non-English
copy still requires native review. Other incoming catalog/project bytes remain
preserved; the whole catalog is never staged.

The Android missing-Arabic-disclosure check failed before the resource binding.
Actual privacy pages now pass all fifteen locales on both platforms, including
unchanged consent readbacks. The final policy-label reruns also check link
reachability and Android touch height. Android's Contents test also passes all fifteen
locales after the test-host correction. Evidence is in
`verification/a4-localization/privacy.json`, selected captures and their complete
60-capture manifest. No consent toggle, export, provider setting, publication or
account action was performed. Authenticated export/deletion flows, live telemetry
and published-policy acceptance remain their separate gates.

Two fixture issues were corrected. Android's localized test wrapper replaced the
Activity context with a configuration context, hiding the Activity Result owner
needed to register the export launcher. It now follows MainActivity and overrides
resources/configuration while retaining the real Activity. iOS XCTest rejects
identifier-style queries over 128 characters; full paragraphs now use exact-label
predicates. These failures are retained separately from the product lookup defect.

The full audit still reports six Arabic zero/dual formatter findings. The next
reader-settings pass must also remove the confirmed unconditional native reader-settings
caption on both platforms claiming that AI translations are grounded in cited sources. The real A3
path has no eligible published comparison content in the last verified development
inventory. Keep source names/citations and prepared content distinct from UI copy.
Continue appearance, auth, accessibility, widgets/notifications and the remaining
A4–A7/E program. This unit closes no full localization, native-review, privacy,
physical-device, content or release gate.

Capture review found policy-link labels still in English because both shared link
rows displayed plain title strings and the three labels had no catalog entries.
iOS link titles now carry localized keys, while Android resolves them through
`nativeText`. Their destinations remain the same. Android's policy rows also use
the existing 48 dp minimum target convention. The final checks inspect all three
labels without opening any URL. The lexical audit now recognizes these link-row
wrappers so their remaining Help/About labels are not silently omitted.

## Reader settings, previews and appearance, October 28

Both reader-settings captions now say AI translations may contain errors and that
source details appear when available. The earlier unconditional grounding claim
is absent from the active native call sites. Its unused legacy catalog entry is
not current product copy. This wording repair makes no new A3 retrieval, rights,
semantic-quality or provider-readback claim and makes no model call.

Arabic and translation type previews reuse the existing prepared interface
example instead of a fixed English hadith fragment. The translation preview
follows the selected translation language, using the existing exact/base/English
fallback chain. These are generic interface examples, not live first-reading
content. User reading text, provider source names and citations are unchanged.

Fifteen new keys in `a4-reader-settings-copy.json` cover the disclosure, reader/type
labels, theme names, separate appearance control and smaller/larger accessibility
labels in all fifteen locales. `a4-appearance-aliases.json` reuses three indexed
iOS entries for Android, including the existing type-size formatter. New copy is
local GPT-family draft text; native review remains pending.

Theme labels now resolve localized keys in both native appearance lists. Reader
summary values localize theme/font labels and format type sizes using the UI
locale. Existing iOS and Android defaults may select different numbering systems;
the native locale formatter remains the authority. Reader theme separation, size
bounds, language selection and the last-visible-layer safeguard stay in place.

Native red checks reproduced missing appearance labels and the fixed English
preview. The fifteen-locale appearance and preview/disclosure checks now pass on
both platforms. Existing app/reader theme separation, Paper rendering, font-size
and last-visible-layer checks pass too. The final iOS live preview-update assertion passes its targeted rerun in both
entry points. The combined latest results are four iOS and five Android cases. Evidence is in
`verification/a4-localization/reader-settings.json` and selected captures, with a
90-capture manifest. No paid call, generation, backend/schema, credential or
publication change was used.

The iOS compiler caught a new numbered type-size key that would generate the same
Swift symbol as the existing `%@ pt` key. The duplicate was removed from the index,
working catalog, Android resources and mapper; callers now reuse the existing
indexed formatter. Direct string-symbol generation and native compilation pass.
The older Android control fixture also assumed English text while inheriting the
Arabic device locale. It now explicitly supplies English resources/configuration
while retaining its Activity, matching the locale scope of those assertions.
Separate fifteen-locale cases retain coverage of the other locales.

The full resource audit still has the same six Arabic zero/dual formatter findings.
Critical-copy/native review, full runtime and assistive-technology coverage,
physical devices, first-reading content, A3 grounding and A5–A7/E remain open.
Next, finish auth and Saved/Reader accessibility copy, inspect the remaining
wrapper/dynamic-string findings, and retain widget/notification and external gates.

## Auth, static copy and private Saved semantics, October 28

The known lexical missing-key/mapping list is now clear after adding fifty-two
static interface keys and reusing sixteen indexed auth entries for Android.
`a4-auth-accessibility-copy.json` records the new local GPT-family drafts plus ten
complete existing Android drafts. The new keys include auth fields, reader/Saved
states and actions, search/profile/help/export labels. Resource compilation is
not runtime proof of every authenticated or evidence-processing branch; those
paths retain their existing gates. All non-English drafts need native review.

The native auth wrappers now resolve their labels rather than rendering stored
English strings. Email and verification-code fields have explicit accessible
names independent of technical examples and current input. Password fields retain
secure-entry semantics. The linked consent sentence is one localized template,
so word order and both link spans follow the locale. It uses the existing iOS
meaning: agreement to Terms and a separate instruction to read Privacy Policy.
The URLs are unchanged. No link, auth submit, account creation, email, code request
or share action is activated by the checks. This local interface draft is not a
legal or published-policy approval.

Private Saved rows now announce bookmark/favorite/note state on Android and use
localized state/action labels on iOS. User notes, folders and source references
remain verbatim. Native row roles and action callbacks remain intact; reader
custom actions/menu labels use the same sentence case as their localized resources.
The final active incoming Saved confirmation draft is committed explicitly via
`a4-saved-confirmation-copy.json`; unused older incoming entries remain separate.

Source review found an existing Share Hadithly entry whose Arabic and Urdu values
incorrectly said Set new password. `a4-existing-copy-repairs.json` corrects only
those two iOS values and records the expected indexed-entry hash. The other locale
values and metadata remain identical. Android uses the corrected indexed wording.
The catalog staging helper requires an explicit repair flag, expected hash and
locale allowlist for an existing entry. A real temporary-Git regression verifies
rejection without the flag/hash, rejection of unrelated locale edits, exact
index-only changes, unchanged incoming working bytes and idempotence.

Initial native failures reproduced auth/Saved label gaps. The expanded checks cover
all seven auth preview states, persistent field names after entering a synthetic
identifier, the complete linked sentence, private Saved semantics, and Help/Share
labels in all fifteen locales. Auth is a preview-only component test; hosted/provider
round trips remain open. Existing Saved row preview/menu/navigation checks and the
reader Undo restoration check are included. The final iOS consent-line rerun passes. Latest combined results are four iOS
and six Android cases. `verification/a4-localization/auth-saved.json` retains the
runs; selected captures and the 270-capture manifest are in `auth-saved/`. Directional isolation marks in that exact-label check use the same
normalization helper as the earlier folder-name check; words and links still match
exactly. Full VoiceOver/TalkBack traversal is not inferred from these labels.

The lexical report still has dynamic/direct-string candidates. Relative Saved
timestamps are confirmed English-only on both platforms and remain next, together
with dynamic errors/counts, notification/widget coverage, fallback/plural checks
and critical-copy/native review. The six Arabic zero/dual formatter findings remain
open. No backend/schema, provider, paid generation, deployment or publication change
was performed. A1/A3, full A4, A5–A7/E and existing release gates remain in scope.

## Native Saved timestamps, October 28

Both Saved rows now format elapsed time using the selected UI locale instead of
building English phrases. The output is a standalone relative value. Stored
created/updated timestamps, sort order, note/folder data and reading positions
are unchanged. Android now shares the existing iOS week/month/year grouping
instead of showing every old item as an unbounded day count. Future clock skew
still clamps to the current-time label.

The native formatter supplies language, number and singular/dual/plural forms:
[Foundation RelativeDateTimeFormatter](https://developer.apple.com/documentation/foundation/relativedatetimeformatter)
and [Android ICU RelativeDateTimeFormatter](https://developer.android.google.cn/reference/kotlin/android/icu/text/RelativeDateTimeFormatter).
The Android formatter is available from API 24, below the app's minimum API 26,
as verified in the installed SDK API-version metadata. No new translation draft,
backend payload, timer, data migration or provider action is introduced.

The actual Arabic Saved row failed before the repair on both platforms. Native UI
checks now pass all fifteen locales. Boundary tests compare eighteen explicit
elapsed-time/component pairs in every locale, including future time, zero,
singular/dual quantities and minute/hour/day/week/month/year transitions.
Existing reader round-3 logic and native Saved row tests also pass: 34 latest iOS
cases and five Android cases, with no skipped pass claim. Evidence and the
30-capture manifest are in `verification/a4-localization/saved-time.json` and
`verification/a4-localization/saved-time/`.

The first consolidated iOS run exposed blank output for `weekOfYear` components,
even though the current-time UI check passed. A direct formatter probe and the
native rerun show that this API expects `weekOfMonth` for the relative-week unit.
That correction passes all fifteen-locale boundary cases. The failed run remains
in the evidence history. The earlier commentary that all boundaries passed was
premature and is corrected by this record.

Widget review found additional work: Android's Daily/Continue copy still falls
back to English outside Arabic/Urdu; iOS Continue progress/empty/lock coverage is
partial; the iOS Kazakh offline label incorrectly says online. Widget-gallery
metadata and Android notification fallback/channel labels also need coverage.
These findings, dynamic/count copy, six Arabic manual plural findings, native
review and the remaining A4–A7/E and release gates stay open.

## Widget and notification interface copy, October 29

Daily and Continue widgets now share seventeen interface keys across all fifteen
locales. `a4-widget-copy.json` retains the drafts and their pending native-review
status. Existing complete iOS Daily/title drafts and progress templates are reused;
missing phrases are local GPT-family drafts. The Kazakh offline label now says
“Желіден тыс сақталған көшірме” instead of describing an online copy. The generator
updates both typed native tables and Android picker/channel resources; its isolated
regression checks repeatability, surrounding-model preservation, the Indonesian
resource qualifier and rejection of dropped formatter arguments before any write.

Continue progress uses native locale number formatting. Source reference strings
remain byte-for-byte intact rather than replacing the English word Hadith inside
provider text. Snapshot schemas, raw-position exclusion, canonical Daily identity,
exact-locale content requirements and generation behavior are unchanged. Gallery
metadata and Android receiver labels resolve the same interface drafts. Both
Android widget declarations now include Glance's required initial loading layout.

Actual Android AppWidgetHost views render real Glance RemoteViews in all fifteen
locales at 320 × 220 dp with 320 × 200 dp host options. Prepared interface examples
exercise AI/offline/stale labels without generating or publishing content. The
latest check asserts a visible translation excerpt, zero metadata ellipsis and
locale-specific title alignment, independent of the emulator's Arabic host locale.
The fixture restores its cached strings, temporary bind grant and own widget IDs.
The initial binding failure was a test setup problem: explicit numeric Android
user IDs are required here; `--user current` did not record the grant. Gradle also
uninstalls the app after the test, so absent providers afterward are not a product
failure.

Capture review exposed truncated status metadata and then a blank excerpt, despite
earlier text assertions passing. The blank-excerpt regression reproduces the
failure. Daily now declares three responsive sizes; Glance's default Single mode
kept LocalSize at the minimum widget size, so the larger rendered host still chose
the compact branch. The [official Glance size guidance](https://developer.android.com/develop/ui/compose/glance/build-ui)
confirms this distinction. Excerpts use the remaining space, status labels can
wrap and full-width text alignment follows the locale. The latest medium-host run
passes. Earlier captures are retained only in the local archive, not presented as
final evidence. Compact and large layouts still need their complete native matrix.

Android notification channel names/descriptions and missing-title fallback now
follow the UI locale. The existing daily_hadith channel ID, importance and supplied
provider title/body are preserved. Instrumentation reads back the actual channel
in every locale and restores its original metadata. It does not post a notification
or exercise provider delivery, permission prompts, tokens or account registration.
Backend notification localization remains a separate review.

Latest evidence totals are fifteen iOS cases, eleven Android unit cases and two
Android instrumentation cases in `verification/a4-localization/widgets.json`.
The iOS check installs and opens Continue Reading through the actual WidgetKit
gallery in English. It does not prove fifteen-locale WidgetKit rendering. The
sixteen-capture manifest and selected images are in `verification/a4-localization/widgets/`.
Native review, compact/large and locked states, physical devices, full VoiceOver
and TalkBack traversal, W1/W2/N1/D4 and existing source/content/release gates stay
open. The incoming catalog and project files are untouched by this unit.

## Count categories and backend notifications, October 29

Native red cases reproduced Android's Russian count as “3 hadiths” and iOS's
accessible singular as “1 hadiths.” The two scoped count resources now share the
existing iOS drafts, with corrected Arabic and Russian categories, on both apps.
The iOS volume header resolves the selected UI-locale bundle before formatting;
its visible and accessible count agree. The volume eyebrow uses the same locale.
Source titles and numbering stay unchanged. The language-selector total retains
its existing native plural call. All non-English wording still needs native review.

`a4-plural-copy.json` records the exact two entries, draft forms and indexed-entry
hashes. `sync-plural-copy.py` changes only their catalog blocks and Android plural
blocks. The staging helper's explicit repair mode now supports scoped plural
localizations; its real-Git regression rejects missing authorization flags, bad
hashes and unrelated entry metadata, preserves incoming working bytes and remains
idempotent. The generator regression checks surrounding-resource preservation and
rejects a lost count before partial writes. `plural-preservation.json` verifies
all remaining incoming catalog bytes and all four project/scheme fingerprints.
The two count entries and the prior Arabic/Urdu Share repair are the only existing
catalog entry exceptions in that byte comparison.

The earlier six Arabic zero/dual formatter findings are resolved structurally.
Those exact forms express zero/two in words, so the audit records their permitted
implicit count instead of requiring an awkward number. It accepts only the exact
manifest value, quantity and single integer argument; altered text, other
quantities, unrelated keys and dropped additional arguments still fail. This
structural exception does not grant native-copy approval. Twelve audit regressions
pass. With drafts allowed, the full audit reports zero structural failures across
422 iOS keys and 418 Android resources. It still reports 323 English-identical
Android candidates and lexical/dynamic candidates for review.

Latest native evidence is three iOS and four Android cases in `plurals.json`,
including all fifteen rendered reader counts and language totals, 240 compiled
iOS count/locale comparisons and 32 Android Arabic/Russian boundary comparisons.
The red iOS result remains in the run history. The 45-capture manifest and selected
images are in `plurals/`. Capture QA also confirms that dynamic page-control
labels can still remain English; those labels and other dynamic/error templates
remain next. These count checks do not imply complete runtime or assistive-tech
coverage.

Backend notification review found existing fifteen-locale AI labels and exact
translation-locale payload binding. Thirty-five targeted local tests pass without
backend changes, provider delivery or cloud access. `notification-review.json`
records helper, due-token and payload tests. Actual notification delivery,
physical devices, native-copy review, A1/A3 and A5–A7/E/release gates remain open.

## Page controls and reading direction, October 29

Both native Russian controls reproduced the English accessible label “Next page,
Page 2.” Eleven scoped keys now cover page/volume progress, destinations and reader
control actions in fifteen locales. Page and page-total templates reuse existing
Android drafts; the remaining phrases are local GPT-family drafts in
`a4-page-control-copy.json`, with native review pending. Generic Arabic-only volume
labels reuse the indexed iOS drafts through `a4-volume-label-parity.json`.
Source-provided names remain verbatim in the existing display modes.

The view derives a page label from its typed destination index. It does not parse
the old English label. iOS's typed formatter replaces the count-only helper, with
all callers migrated and the existing 240 plural comparisons retained. Android
copy generation now converts Swift integer formatters to Android integer formats;
the isolated generator regression covers numbered integer and string arguments.
Both native formatter checks cover regional/base fallback, English fallback and
opaque reference text containing formatter syntax. The source argument is retained.

An Android native failure also proved that the previous pill stayed left for RTL
reading in an English interface. The pill row now follows the reading policy,
independently of UI language, and its chevrons avoid double mirroring. Target sizes,
logical previous/next routing and source-title preservation pass in thirty
locale/direction combinations on each platform. Android progress labels are
combined for accessibility. iOS production progress labels render in all fifteen
locales; focus/thin progress and cross-volume swipe checks still pass. Russian and
Arabic Arabic-only volume-title checks pass on both apps.

The first expanded checks exposed fixture issues: a direct iOS reader test inherited
a saved Russian UI preference, and string comparisons differed in native direction
marks. The English fixture now sets its existing UI-locale override explicitly.
Comparisons normalize only direction-control marks and retain exact words, numbers
and source references. An early Android test oracle also used Swift's formatter
syntax and was corrected to Android syntax. Earlier failed iOS runs remain in the
history; none are counted as green.

Latest results are seven iOS and six Android cases in `page-controls.json`. The
80-capture manifest and selected images are in `page-controls/`. The scoped staging
helper adds only eleven new catalog entries; `page-preservation.json` confirms the
remaining incoming catalog bytes and four project/scheme fingerprints. The audit
with drafts allowed has zero structural failures across 433 iOS keys and 426
Android resources, with 299 English-identical Android candidates still listed.
This is not full runtime localization or assistive-technology traversal proof. Diff review restored unrelated Contents/search chevrons; the icon change stays scoped to page controls, and the final Android debug build passes.

Source review confirms that account-deletion confirmation and separate App Store /
Play Store subscription warnings still bypass localization on both platforms and
lack catalog entries. Those critical disclosures are next, followed by remaining
evidence/search/dynamic templates and the A5–A7/E work. Native review, authenticated
and physical-device checks, A1/A3, full A4 and release gates remain open. No account,
provider, paid generation, deployment or publication action was performed.
