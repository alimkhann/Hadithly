# A5 Contents navigation

Historical bounded-unit record. Current A5 engineering closure and the resolved
large-text/Settings follow-ups are audited in `A5_REQUIREMENT_AUDIT.md` and
`A5_READER_CONTROLS.md`. The next-unit boundary below records the earlier handoff.

October 31, 2026. One bounded A5 unit covers the Contents Go tap and replacement
of an in-flight page fetch. At this checkpoint full A5 and the original product
program remained open.

## Reproduction and ownership trace

The controlled journey uses the production reader, menu, Contents presentation,
validation, target selection, page publication and native landing. A synthetic
outline has one source-named volume containing 100 hadiths. Its initial page shows
hadith 1. The page transport holds the next-page prefetch open. Open the menu,
choose Contents, type `57` and tap Go. Release the old response afterward.

On Android 16, `emulator-5554`, Go reached the model and dismissed Contents. The
request trace contained only `page0, page1`; the target request never started.
The native test failed with expected hadith 57 and actual null. Clearing pages
before `loadPage` encountered the old `isLoadingPage` guard lost the new target.

On the explicitly selected iOS 27 simulator
`D47D7363-4705-4767-8617-F47DDB6A3241`, initial automation tapped during the
keyboard-driven sheet resize. Go left Contents visible and the trace contained
only `prefetch`; keyboard Submit produced `jump:57` and `dismissed` but no target
page request. Added tracing and a settled-frame tap check isolated the observation
problem. The original borderless button then dispatched malformed and valid taps. A second
red run restored the original loader with only the transport/tracing seam: the
settled Go tap dismissed Contents but never started the target fetch.
The button-style hypothesis was rejected and its behavior change removed. The
confirmed product failure is the shared in-flight page-ownership race. Early
rejected runs and the original Bengali-interface capture remain separate evidence.

## Repair

The existing Go control, localized label, disabled-empty rule and keyboard Submit
path are retained. Both models invalidate the previous page generation before clearing state for a
new target. Old results, failures and cleanup cannot publish into the new
navigation or release its loading state. iOS explicit target tasks are now owned
by the reader and cancelled when replaced or closed. Page and volume-edge writers
use the same ownership check. Android keeps real timeout/offline fallback by
checking the active parent coroutine instead of swallowing every cancellation
exception as a navigation cancellation.

Backend actions, schema, API arguments, volume selection, target resolution,
semantic anchors, Saved payloads and return destinations retain their contracts.
The DEBUG iOS page transport and injected Android loaders make the race repeatable
without content generation or real account operations. Android's new fixture uses
an isolated guest library directory. The synthetic `%@` body/title values stay
opaque. They are not localization keys or format strings.

## Evidence and limits

The native builds are Debug. Both local targets resolve the system reader theme
as light in the selected captures; this unit is not a theme matrix. The simulator
is iPhone 18 Pro / iOS 27.0; the Android AVD is `hadithly` / Android 16.

Native run summaries and exact test names are in
[results](verification/a5-contents/results.json). Repeat commands are in
[commands](verification/a5-contents/commands.md). Raw bundles, logs and rejected
runs remain under `/tmp/hadithly-a5-go`. The results record retains failures and
later passing scopes separately. A mixed bundle is not described as fully passing.

The focused journey covers blank and malformed input, one Go callback, real sheet
dismissal, the page holding hadith 57, old callback release while the target is
still pending, visible native landing, opaque source/body fields, and close/return
callbacks. Arabic, Urdu, Russian and Bengali use Accessibility XXXL on iOS and
fontScale 2.0 through the Android composition. iOS also receives the native Accessibility XXXL launch override so presented sheets
use that size. This is controlled text sizing, not physical-device acceptance.

Existing Contents guidance/validation bindings are rechecked in all fifteen UI
locales: `en`, `ar`, `ru`, `kk`, `ky`, `uz`, `tr`, `id`, `ur`, `fr`, `es-419`,
`pt-BR`, `sw`, `hi`, `bn`. Resource and catalog bytes remain unchanged. The
localization audit and its thirteen script tests pass; draft-copy review remains
pending. Existing reader landing, RTL/paging, opaque-copy, Saved and callback
regressions remain part of the scoped readback.

Latest accepted scopes include 66 iOS reader unit cases, the three unchanged
Contents/landing/marker UI scopes from the mixed bundle, the final four-test
Go/large-text/return/Saved run, and its capture refresh. Android retains 59 passing
cases from the first 61-case run, two corrected Saved/menu reruns, a six-case
Go/fifteen-locale run and the final five-case close/callback run. Repeated cases
are not additional product coverage. Its 55 focused unit cases pass.
[Local checks](verification/a5-contents/local-checks.json) records the unit and
resource audit readbacks. None of the selected native scopes was skipped.

Older Saved assertions expected pre-A4 relative-time and bookmark-action wording.
Their first failures are retained. The tests now check the native timestamp and
both creation/removal semantics, and are rerun without changing product behavior.

No actual live content fetch/landing, authenticated cross-device journey,
physical device, VoiceOver/TalkBack traversal or exact-copy native-language approval
is established here. The models and native UI use controlled synthetic pages.
No real sign-in, account change, deletion, export, purchase, notification, model
call, cloud/account/credential configuration, deployment, migration, publication,
external message or push is part of this unit.

## Preservation and next boundary

The rerunnable scope check compares the incoming catalog and four project/scheme
hashes with the session snapshot, checks their index entries, and verifies unchanged
backend, native data/control-plane code and Android resources. It also compares
A2, A4's requirement audit, B/C/D records, OPEN_GATES and historical PLAN/program
requirements to the starting commit. Build outputs and incoming Python cache files
stay outside the commit.

A2 remains wrapped with row mode off. B/C/D retain local completion. Unfinished
A1/A3 content/semantic acceptance, A4 exact-copy/native accessibility acceptance,
A6-A7/readiness, E's actual Linear hub, the final original-program audit and every
existing external gate remain open. This includes physical/authenticated/store/
purchase/content/disclosure/production/backup/recovery, actual annual billing total,
publication, LA4 and the unresolved Android physical-phone incident.

The controlled Android large-text capture also exposes clipping/overlap in the
reader's top source/page controls. The hadith-57 body/header and close callback
remain usable in this test. That visual issue is retained for the next bounded A5
reproduction and iOS parity check, not absorbed into this navigation repair.
Follow PRODUCT_PROGRAM before POST_GOAL_BACKLOG. Stop after this unit's verified
commit without pushing; use NEXT_SESSION_PROMPT for the next exact goal.
