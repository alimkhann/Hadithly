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
