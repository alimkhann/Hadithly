# A5 requirement audit

October 31, 2026. A5’s original engineering criterion is complete. The owner
expanded the bounded follow-up into finishing A5. The original criterion is:
“Resolve reproduced architecture, system, behavior, and UI defects that prevent
the core reading/saving/return journeys. Retain the RTL regressions.”

This audit applies that criterion to the reported defects and retained native
journeys below. A5 does not absorb A1/A3 content/provider acceptance, A2's deferred
storage cutover, A4 exact-copy/accessibility approval, A6 external readiness, A7
observation, E or the later backlog. It cannot certify the absence of all future
bugs or make the original product program release-ready.

| Requirement / journey | Evidence and scope | Status |
| --- | --- | --- |
| Actual Contents Go tap, dismissal and target ownership during an active fetch | `A5_CONTENTS_NAVIGATION.md`: confirmed race on both native apps; generation ownership repair in `694081c`; controlled native malformed/valid tap, one target request, late old callback, visible hadith 57 and close/return refreshed here | Repaired; accepted native readbacks pass |
| Source and progress controls at large text | `A5_READER_CONTROLS.md`: before bounds overlap on both; intrinsic captions, wrapped controls and measured stable viewport; actual Go, rendered bounds and focus taps in ar/ur/ru/bn | Repaired; accepted native readbacks pass |
| Translation size controls affect reading | Actual 14→22 text-growth test failed before on both hardcoded renderers; existing preference now reaches text; layout identity/projection and old-position semantic-anchor tests | Repaired; accepted native readbacks pass |
| Core reading, paging and return | Native production Go/close/focus/target matrix plus retained controlled direction/visibility, vertical scroll, chapter/volume edges, source and settings entry-point suites | Passed accepted native scopes |
| Guest saving, favorite, note, removal/Undo and Saved-to-reader return | Both native production readers use isolated guest stores; actual menus/editor/Undo and Saved row reopen hadith 57 with opaque note intact; Android reader Undo uses the injected library consistently | Passed controlled native journey |
| Folders, local reopen and stale callbacks | Four actual-facade tests per native library cover durable offline intentions, folders, accepted notes, stale reads/Undo after fake scope switch/sign-out and oversized-note rejection; no real SDK account operation | Passed accepted native scopes |
| RTL language return | Guarded guest root Settings: English → Arabic → back → picker → English → back → Settings and relaunch/recreation; rendered row orientation, logical direction and translation-locale separation | iOS mirror reproduced and repaired; rendered return/relaunch and Android parity pass |
| Fifteen-locale bindings and large text | Production progress components in en/ar/ru/kk/ky/uz/tr/id/ur/fr/es-419/pt-BR/sw/hi/bn; focused ar/ur/ru/bn large text; unchanged catalog/resource bytes and localization audit | Passed; native and resource readbacks refreshed |
| Source/user data and geometry identity | Opaque source title/body/note `%@`/Arabic, unchanged ReadingPosition wire schema and Saved sync/storage; matching native signature vector, old normalized anchor preserved and stale raw offset discarded | Passed refreshed native unit checks |
| Preservation and delivery | `scripts/verify-a5-program.py`: exact incoming hashes/index entries, explicit source scope, A2/A4/B/C/D/OPEN_GATES and historical requirements; staged/unstaged inspection, scoped commit without push | Preservation and scoped inspection pass; the delivery commit accompanies this record |

## Defect and report ledger

| Report / finding | Disposition |
| --- | --- |
| Contents Go loses the target during prefetch | Confirmed and repaired on both apps; the original button-style theory was rejected after tracing iOS keyboard/sheet geometry. |
| Large-text top controls overlap/clip | Confirmed on both apps and repaired. Padding-only candidates were rejected because semantic scrolling could still put the source under the HUD. |
| Translation font-size preference does nothing | Confirmed on both apps and repaired within the original core reader requirement. This overlaps a later report; no broader backlog redesign was started. |
| Android injected reader Undo uses the singleton | Confirmed in the isolated fixture; owning library/controller is now consistent. No claim of observed real-account corruption. |
| Arabic → English Settings return looks RTL | Confirmed in rendered iOS root Settings despite passing labels/tab order; a pixel-orientation regression fails before repair. Replace only the hidden native List on RTL/LTR change. Android rendered parity passes without a product change. |
| Older paging/loading assertions fail | Missing debug launch flag and obsolete spinner expectation are harness defects. Keep their failing results, correct the expectations to the existing fixture/skeleton, and rerun. |
| iOS focus checks use ambiguous page coordinates | The Russian coordinate tapped an inline page-navigation control: retained hierarchy shows a neighbor loading, the target off-screen and new prefetch. Actual Arabic-text taps now pass chrome, status-bar and stable-target checks. |
| iOS scrolling lag / page-cache loading jerks | No broad performance redesign was authorized. Retain the actual production scrolling/rebuild safeguard and behavioral paging/landing tests; physical traces and measured cache/latency optimization remain separate work. |
| Free/pro translation reliability and exact-locale content | Unfinished A1/A3 acceptance remains open. Controlled passages cannot establish live provider quality, rights, generation success or bounded paid cost. |

## Evidence boundary and remaining original program

No reproduced A5 blocker remains in these checked core journeys. The accepted
readbacks contain 173 unique iOS cases (124 unit/facade and 49 UI), 80 unique
Android device cases and 110 Android unit cases. Thirteen localization script
tests and the resource audit pass with draft-copy approval still open. Eight
failures in mixed iOS bundles have explicit passing reruns; mixed bundles are
never counted as wholly passing. The Settings pixel regression was added only
after rendered review exposed the semantic test's blind spot.

Use `verification/a5-completion/results.json`, `local-checks.json`, the capture
manifest and repeat commands for exact artifacts and per-case outcomes. Mixed
bundles and rejected attempts remain separately identified; repeated cases are
not additional coverage. Controlled fixtures exercise production UI and data
facades, with fake transport/session responses where needed. Root language tests
check guest UI and direction only; ordinary feed startup may read/cache
development content. No live-content/provider or authenticated-operation claim
is inferred from them.

No real account action, paid-model call, cloud/account/credential configuration change,
deployment, migration, publication, external message or push was performed.
Incoming catalog/project work stays unstaged. A2 remains wrapped with row mode
off; B/C/D keep local completion and A4 keeps its finite local audit. Exact-copy
native-speaker and full accessibility/authenticated/physical acceptance stay open.

A1/A3 content/semantic acceptance, A4's original checkbox, A6–A7/readiness,
physical/authenticated/store/purchase/content/disclosure/production/backup/recovery
and integration gates, actual annual billing total, publication, LA4, the Android
physical-phone incident, E's actual Linear hub and the final original-program
audit remain open. The original program precedes POST_GOAL_BACKLOG. The next
exact prompt is an A6 local gate audit; this goal does not start that work.
