# A5 reader controls and type

October 31, 2026. The owner expanded the bounded follow-up into completing A5.
This record covers the confirmed controls/type defects and the retained core
reading/saving/return matrix. The earlier Contents race and its actual tap,
dismissal, target ownership and landing trace remain in
[A5_CONTENTS_NAVIGATION.md](A5_CONTENTS_NAVIGATION.md).

November 1 follow-up: the owner reported the reserved viewport as a visual
regression. The active scrolling goal restores a full-screen viewport with
measured content clearance, allowing manually scrolled text behind floating
controls while preserving large-type explicit landing and focus stability. See
[SCROLLING_VERIFICATION.md](SCROLLING_VERIFICATION.md). The reserved-viewport
implementation below is historical; its source/glyph safety requirements remain.

## Reproduced defects and repair

Both production readers reproduced overlapping source and progress controls
following Contents → hadith 57 at large text. Android fontScale 2.0 put the
progress pills at y=152–236 pixels and the source at y=147–273. iOS Accessibility
XXXL put the fixed 30-point pills at y=70–100 and the source at y=94–142. The
104×30 iOS and 32dp-high Android capsules also constrained scaled captions.
The before assertions fail on those actual native bounds.

Progress capsules now size to their captions, with a wrapped row when needed.
The reader reserves the measured header outside its scrolling viewport, so a
semantic jump cannot scroll the source back under the controls. Measurement is
stable for a locale/width/type context across focus and system-bar transitions;
hiding and revealing chrome preserves the visible target. Android uses Compose
FlowRow and intrinsic bounds; iOS retains its native control surface and uses
ViewThatFits. No new product controls or navigation destinations were added.

The existing translation-size preference also failed on both actual text paths:
14→22 left Android's text height at 61→61 pixels, and the equivalent iOS growth
assertion failed. Both renderers hardcoded 16. They now receive the existing
preference; iOS also scales that base with Dynamic Type. The layout projection
and derived signature include translation size. The signature's canonical input
is versioned because the header geometry changed. Existing stored positions use
the unchanged semantic-anchor fallback instead of stale pixel offsets. The wire
schema, opaque position data, Saved storage, sync and backend contracts are
unchanged; no migration or remote operation was performed.

The isolated Android saving fixture exposed mixed ownership: its reader actions
used the injected library while Undo looked up the application singleton. The
reader and its Saved sheet now pass their owning library/controller consistently.
The normal application instance was already shared; this is dependency consistency
and controlled-test coverage, not evidence of real-account data corruption.

The rendered guest Settings return exposed a further confirmed iOS defect:
English labels and tab order were correct after Arabic → English, but the hidden
native List retained a horizontal cell transform and mirrored the entire body.
Relaunch restored normal ink; Android's same-process/recreation journey rendered
normally. A row-image regression compares the returned ink with a fresh English
baseline in normal and flipped orientations. Before repair its direct difference
was 668,028 versus only 22,368 after flipping. The root Settings List now gets a
new identity only when RTL/LTR direction changes. Its NavigationStack, destination
registration, Settings state and app/reader owners retain their identities. The
picker remains open through selection and Back returns to the proper root.

## Evidence

The explicit native targets are iPhone 18 Pro / iOS 27 simulator
`D47D7363-4705-4767-8617-F47DDB6A3241` and `hadithly` Android 16 AVD
`emulator-5554`. Android UI runs use the repository's guarded runner. The tests
use Debug builds, synthetic pages, in-memory or isolated guest stores, and fake
account transports for callback ownership. Raw runs are under
`/tmp/hadithly-a5-finish`; portable summaries, commands and selected captures are
in `verification/a5-completion/`. Selected production captures use Android light and iOS dark. The separate
settings matrix does not establish full production contrast or accessibility
approval.

The focused matrix covers actual Contents taps, dismissal, a held old callback,
one target request and visible landing; progress glyph/capsule and viewport
bounds; real focus taps without target movement; translation text growth; guest
bookmark/favorite/note, removal/Undo, close, Saved row and exact reader return;
folders and local reopen; stale read/note/Undo ownership; source URLs and opaque
`%@`/Arabic note text; page/volume/chapter and visibility/direction contracts.

The fifteen UI bindings are `en`, `ar`, `ru`, `kk`, `ky`, `uz`, `tr`, `id`, `ur`,
`fr`, `es-419`, `pt-BR`, `sw`, `hi`, `bn`. Production progress controls run in all
fifteen; ar/ur/ru/bn also run the actual Go/focus journey at fontScale 2.0 or
Accessibility XXXL. This checks rendered bounds and callback/state behavior,
not native-language meaning or full screen-reader traversal.

## Rejected attempts and interpretation

Initial padding-only candidates still allowed a scrolled source behind the HUD
and were rejected. A hidden header measurement now reserves the viewport even
when the reader starts focused. Android status-bar changes initially moved the
anchor; retaining the measured context height fixes that. A Compose paragraph's
allocated width was wider than a short numeric glyph: the assertion now checks
actual glyph bounds, line count and ellipsis rather than treating allocated
paragraph width as clipped ink. iOS viewport comparisons allow half a point of
floating-point edge rounding; focus movement still has a one-point limit.

An older iOS paging suite lacked the required HADITHLY_UI_TESTING flag and never
opened its fixture. Another expected an activity spinner although C's shared
article skeleton was already installed. Only those harness assumptions change;
the failed attempts remain classified in the result record. The final Russian Go attempt reached hadith 57, then the coordinate used to
reveal chrome selected an inline page-navigation control instead. Its retained
hierarchy shows the target page off-screen, a neighbor loading and a new prefetch.
The older focus regression also used an ambiguous page-center coordinate. The
focus checks now tap the actual Arabic reading text and retain target and status-bar assertions; their rejected attempts
remain recorded. An intermediate text-growth assertion also timed out although
its retained recording visibly grew the text. Accepted font checks capture the 14/22 native
presentations before comparing frames; no font implementation changed in response.
The first iOS saving attempt reached and saved the note but failed the localized debug-summary
assertion. Its fixture summary is now verbatim; the exact note and all callbacks
are checked. Mixed or rejected bundles are never counted as wholly passing.

Inline neighbor-page pills retain their existing single-line shortening and
full accessibility labels. The top progress capsules are the clipping repair;
full accessibility acceptance remains open.

## Limits and preservation

Actual live content, authenticated cross-device operation, physical devices,
VoiceOver/TalkBack traversal, native-speaker exact-copy approval, store receipts
and release readiness remain separate open gates. The root language-switch
regression uses a guarded guest session and does not invoke sign-in. Ordinary
feed startup may read/cache development content; it is outside the controlled
page transport and does not establish content/provider or authenticated acceptance. No real account action, paid model call, cloud or
credential configuration, deployment, migration, publication, external message
or push was performed.

The rerunnable `scripts/verify-a5-program.py` checks incoming catalog/project
hashes and unstaged index entries, the explicit source scope, unchanged backend,
Android resources, A2/A4/B/C/D evidence and OPEN_GATES. Historical PLAN and the
original program are preserved except the authorized A5 completion checkbox.
The current requirement audit and next prompt retain unfinished A1/A3/A4,
A6–A7/readiness, E and the final original-program audit. A2 remains wrapped with
row mode off; no deferred storage work or later backlog redesign was started.
