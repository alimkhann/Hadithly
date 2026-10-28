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
