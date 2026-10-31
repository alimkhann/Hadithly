# A4 requirement audit

October 31, 2026. A4's finite locally verifiable checklist is complete. Full A4
acceptance remains open. The requirement is the A4 checklist entry in
[Product completion program](PRODUCT_PROGRAM.md).

| Requirement | Local evidence | Acceptance status |
| --- | --- | --- |
| Audit runtime copy | `a4-runtime-dispositions.json` records the lexical candidates, variable-text source review, and required boundary bindings. `final-local-audit.json` records source hashes. The review includes root Settings, reader chrome, semantic labels, models, and wrappers that the lexical scan cannot infer. | Complete locally; final raw native readbacks pass. |
| Audit all Android XML | The structural audit visits every string/plural XML file under `values` and every supported qualifier. The review ledger now covers `native.xml` and counts nested iOS plural draft units. A temporary two-resource fixture reproduced the former ledger omission. | Local structure passes. Resource presence does not prove rendering or language quality. |
| Repair fifteen locales | Offline notices, Settings/evidence wrappers, fixed conditional labels, auth email prompts, folder fallback, clipboard attribution, root summaries, reader menus, semantic names, and authenticity claim templates use the selected UI locale. Existing native drafts are reused where correct. | New and reused copy remains pending exact-copy review. |
| Fallback | Compiled iOS fallback and native boundary checks cover supported regional/base resolution and an unknown locale. Diagnostic boundaries accept fixed known messages and use bounded localized retry copy for unknown details. | Local checks pass. Provider/auth behavior remains separate. |
| Placeholders | The resource audit compares exact argument multisets. Native matrices exercise counts, progress, versions, storage sizes, and opaque names with `%lld` and `%@` characters. Copy-format checks preserve body/source text and folder names. | Local checks pass. No user content becomes a localization key. |
| Pluralization | Existing count-category resources and compiled plural checks retain Arabic/Urdu category coverage. New notices use neutral count templates that do not require singular/plural noun selection. | Local structure and compiled checks pass. Native linguistic review remains open. |
| RTL | Changed presentations cover Arabic and Urdu among all fifteen locales. Opaque arguments retain their source values. Reader/menu actions retain local callback safeguards. | Controlled fifteen-locale rendering passes. Full native/device acceptance stays open. |
| Accessibility and large text | Focused Arabic, Urdu, Russian, and Bengali checks use iOS Accessibility XXXL and Android fontScale 2.0. Actual reader menus wrap and scroll. Bounds, full text, ellipsis, labels, and callback counts are checked. | Focused controlled checks pass. Full VoiceOver, TalkBack, keyboard, focus, and physical-device acceptance stays open. |
| Critical-copy review | Every ledger row is `pending exact-copy review`, with reviewer `unassigned`. Copy sources retain `native_review: pending`. Catalog translation state and generated fixtures confer no approval. | OPEN for reading, authenticity, AI labels, quotas, purchase, privacy, evidence, export, and deletion copy. |

The native UI locales are `en`, `ar`, `ru`, `kk`, `ky`, `uz`, `tr`, `id`, `ur`,
`fr`, `es-419`, `pt-BR`, `sw`, `hi`, and `bn`.

The scoped before/after records are linked below. Each covers fifteen UI locales
and focused ar/ur/ru/bn large text on both platforms.

| Completed unit | Controlled scope | Record |
| --- | --- | --- |
| Offline | 30 copy templates plus synthetic offline-store checks | [Offline notices](verification/a4-localization/offline-notices.json) |
| Settings/evidence | 68 presentations, known-message boundary and bounded fallback | [Runtime notices](verification/a4-localization/runtime-notices.json) |
| Runtime edges | 14 presentations, actual Android menu/action labels, copy/folder safeguards | [Runtime edges](verification/a4-localization/runtime-edges.json) |
| Final wrappers | 37 lookups plus actual reader menu/circle components and local callbacks | [Reader chrome](verification/a4-localization/reader-chrome.json) |
| Authenticity | Six formatter cases preserving scope and source fields | [Authenticity](verification/a4-localization/authenticity.json) |

These records retain expected reproduction failures and rejected assertion/build runs
separately from the final passing scopes. Raw result bundles and XML reports remain
under `/tmp/hadithly-a4-finish-1031`. Selected original captures and hashes are committed.
[Re-run commands](verification/a4-localization/commands.md) explain their scope and
readback requirements. Older unchanged A4 units retain their completion records in
[A4 runtime localization](A4_RUNTIME_LOCALIZATION.md).

The current audit covers 594 iOS keys and 589 Android resources, with zero
structural failures. It retains 8,492 iOS draft units (8,452 localizations) and 48 Android English-identical
candidates. Eighteen generator/staging/audit tests pass. New entries in this goal
total 108 keys across fifteen locales; indexed reuse adds no language approval.
The final raw readback selects passing tests explicitly inside mixed-result bundles,
including the failed before checks and rejected early assertions in the evidence.
The last authenticity formatter matrix passes six cases per locale and focused
large text while retaining source fields and existing scope decisions.

The lexical report retains numeric/data/brand candidates and catalog-backed runtime
candidates. Its strict mode is not an acceptance test: it also flags valid SwiftUI
literal lookup and fixture text. The supplementary source review supplies the missing
variable/model provenance. Identical Android values remain visible as candidates;
shared words, units, greetings, and grade transliterations still require exact-copy
native review.

Implementation commits are `ad0a831` (offline), `9a2b025` (Settings/evidence),
and `390ff52` (remaining runtime bindings and reader wrappers). The final audit
re-read twenty native result artifacts, selecting passing scopes explicitly.
Both staged and unstaged changes were inspected; the four incoming project/scheme
files, incoming catalog formatting/extraction, and Python cache remain outside
these commits. No push was performed.

The preservation report compares against the incoming catalog snapshot and starting
commit. Existing catalog entries, incoming project/scheme bytes, Android resource rows,
A2's records and data/control-plane code remain preserved. The original product
checklist and historical PLAN gates retain their initial bytes.

A2 stays wrapped for its agreed normal-use development scope, with row mode off.
B, C, and D retain local completion. A1/A3 content and semantic acceptance, full A4,
A6 content/store/purchase/device/disclosure/production/backup and integration gates,
A7 observation and consented reader sessions, E's actual Linear hub, and the final
original-program audit remain open. Actual annual billing totals, publication, LA4,
and the unresolved Android physical-phone incident keep their own gates.

A5 has not started. The Contents Go-tap navigation failure remains for the exact next
goal in `NEXT_SESSION_PROMPT.md`. `PRODUCT_PROGRAM.md` precedes `POST_GOAL_BACKLOG.md`.
This work invoked no real account, deletion, purchase, export, notification, provider,
paid-model, deployment, migration, publication, external-message or push action.
