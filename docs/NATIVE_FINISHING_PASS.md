# Native finishing pass

Owner goal, 2026-10-16. Continue from `4c24b08`; preserve the reader behavior,
automatic/manual translation, source details and paging fixes already verified.

## Acceptance

- [x] Reader controls keep their 52 pt/dp layout and actions while adopting native
  Liquid Glass on supported iOS versions, a material fallback on iOS 17–25, and
  Material tonal/elevated controls on Android. Reduced transparency/motion work.
- [x] Android Today/Library/Saved/Settings navigation has a modern native surface,
  stable destination state, selected semantics, readable labels and safe insets.
- [x] Contents, Search, Bookmark placement and Bookmarks & Notes use consistent
  native sheet/dialog chrome, simple rows and restrained state transitions on both
  platforms. All existing navigation, saved actions, filtering and search scope work.
- [x] First-install Welcome → language → prepared example → account choice and
  sign-in/sign-up/code/recovery screens have rendered screenshots on both platforms.
  Welcome uses separate light and dark artwork; forms use plain surfaces. System
  theme and the device language apply before Get started;
  keyboard, small screen, large text, RTL and reduced motion are checked.
- [x] Xcode build/test diagnostics have no warnings or errors. Required native
  tests pass, final screenshots are inspected, decisions/gates are recorded.
- [x] Finished work is committed and pushed to the existing repository upstream,
  without force or unrelated external-service changes.

The official Transitions.dev patterns inform timing and state continuity; existing
native controls remain the implementation. A hosted fix was already used once
for this thread; further quota is not needed to apply the native patterns.
The native interface uses its existing neutral palettes rather than wallpaper
colors. First-entry artwork is decorative, with all text supplied as accessible
native content. No live sign-in, email delivery or paid generation is needed for
presentation screenshots. Existing device/account, store, localization and release
gates remain open; this does not start L1.

## Owner revision, October 16

The first navigation and sheet styling was rejected after screenshot review.
The revised pass uses Material 3 ShortNavigationBar with a shallow neutral surface,
shared bottom Saved filters with icons on both platforms, simpler saved rows and
purpose-specific empty states. The old heavy shadow/capsule and artwork behind
forms are superseded. iOS first-launch detection now covers all fifteen offered
languages; regional Spanish and Portuguese resolve to the offered regional locale.
Compose copy reads the localized resource environment, not the device context.

## Native references and design decisions

Android keeps Compose. The revised bar uses the native Material 3
[ShortNavigationBar](https://developer.android.com/reference/kotlin/androidx/compose/material3/package-summary#ShortNavigationBar(androidx.compose.ui.Modifier,androidx.compose.ui.graphics.Color,androidx.compose.ui.graphics.Color,androidx.compose.foundation.layout.WindowInsets,androidx.compose.material3.ShortNavigationBarArrangement,kotlin.Function0))
with a shallow surface and no added shadow. Large text uses two rows so labels
remain readable. [Now in Android's navigation components](https://github.com/android/nowinandroid/blob/main/core/designsystem/src/main/kotlin/com/google/samples/apps/nowinandroid/core/designsystem/component/Navigation.kt)
also retain native Material selection, focus and feedback rather than replacing
them with a web runtime. The heavy elevated capsule was rejected in screenshot
review. Saved uses its own smaller semantic group above primary app navigation.

The iOS reader uses [Liquid Glass](https://developer.apple.com/documentation/SwiftUI/Applying-Liquid-Glass-to-custom-views)
on supported OS versions, a material fallback otherwise, and opaque palette
surfaces when Reduce Transparency is enabled. Native navigation, searchable
fields, confirmation dialogs, menus and buttons keep platform feedback.
The official [Transitions.dev skill](https://transitions.dev/skill.html) informs
motion roles and state continuity; native controls own their own animation.
The thread's one hosted agent run is documented separately in
`docs/verification/TRANSITIONS_AGENT_REVIEW.md`.

The light welcome asset is an imagegen companion to the existing dark asset,
created for this project. Neither background contains UI text. Artwork is used
only at welcome, with all controls and copy rendered natively. Auth, language,
prepared-example and account forms have plain surfaces.

## Empty-state audit

| Surface | Result |
| --- | --- |
| Search before typing | Search icon, clear title and available-English scope. |
| Search without matches | No-results title and a shorter-phrase suggestion. |
| Search unavailable | Existing offline/error explanation retained; reading remains available. |
| Saved / each facet | Specific empty title and long-press instructions; filters remain reachable. |
| Empty folder | Explains how to move a saved hadith into it. |
| Saved loading/failure | Separate from empty filters; retry and skeleton states retained. |
| Today without content | Replaced internal eligibility/cache terminology with reading guidance. |
| Library | Static collection choices remain available; progress is optional. |
| Reader load failure | Existing retry/close path retained, rather than treating a failure as empty. |
| Source details | Missing citations stay explicit; source/AI attribution is not invented. |
| Offline storage | Existing per-collection download/locked/error actions remain available. |

## Diagnostics compatibility

A fresh build found an existing Swift weak-capture warning and Sentry 9.30.1's
transitional hint-hook deprecation. The capture is now explicitly weak. Sentry's
current public event-only callback cannot remove attachments, so replacing the
hint callback would weaken the privacy boundary. `SentryHintCompatibility.m`
contains one typed setter call and one local deprecation exception; other
warnings remain enabled. No runtime selectors, private API, SDK fork, global
warning suppression, service change or SDK upgrade is used. This adapter must be
removed when Sentry provides the replacement hint-aware callback. The actual SDK
transport-envelope test proves that attachment/private canaries are still absent.
See the [Sentry release notes](https://github.com/getsentry/sentry-cocoa/releases/tag/9.28.0)
for the supported hint API. AppIntents is linked for the current Xcode metadata
build step; this adds no Siri actions.

## Review artifacts

- [Original screenshot gallery](verification/native-finishing/index.html)
- [Screenshot hashes and sizes](verification/native-finishing/screenshots.json)
- [Verification results](verification/native-finishing/verification.json)
- Rebuild the gallery with `python3 scripts/export-native-finishing-gallery.py --ios-result <xcresult> --android`.
- Check onboarding copy with `python3 scripts/sync-onboarding-copy.py`.
- Existing locale audit also rejects onboarding cross-locale drift.

The earlier failed runs found wrong-locale Android resources, a native bookmark
choose/dismiss race, missing filter identifiers and locale-dependent old test
selectors. Each was repaired before final acceptance. Original captures replace
blank/early-window or stale screenshots; auth delivery and paid generation were
not submitted to create this evidence. Existing physical-device, account, store,
production and native-speaker review gates stay open.

## Verification checkpoints

The clean build-for-testing in `/tmp/hadithly-finishing-clean-final.log` succeeds
with zero compiler warnings/errors. The final iOS runtime bundle is
`/tmp/hadithly-finishing-verified.xcresult`; its 251 non-opt-in unit checks pass,
including both diagnostics tests. Eight live/device/store opt-in tests remain
skipped, consistently with the existing gates. The final 23 UI checks also pass: 274 passes, eight explicit opt-in skips and no
failures across 282 tests. Results are recorded in the machine-readable file.
A later gallery review found Saved's Paper canvas falling through to white; the
background is now explicit. The two-case focused rerun passes, including its
rendered-pixel assertion and the Saved row/filter/edit behavior.

Android passes 204 unit checks and 71 unique UI checks across the finishing and
regression runs. The six-case final gallery run and one-case actual OnboardingFlow
first-launch rerun repeat earlier checks to refresh evidence after their fixture
inset/copy corrections. The R5 malformed-jump test checks that the sheet remains
open rather than requiring a scrolling header to remain visible above the IME.
No production validation was relaxed.

## Source handoff

Implementation and original evidence were committed as `38547783775e98f63eaccc6b38c01d6e46d3087a` and pushed
normally to `origin/main`. The upstream readback matched that commit. The final
record includes the later Paper canvas check. GPT-6 Luna found no remaining
source or evidence-integrity flags; all screenshot hashes and gallery links were
checked. Existing device, account, store, production and native-copy review gates
remain separate. No force push, deployment or account/service changes were made.
