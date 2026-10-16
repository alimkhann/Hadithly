# Native reader refinement

October 16, 2026. This follows `71b0cde` and the owner's thirteen-item
refinement. The incoming String Catalog extraction was preserved separately in
`6ad5246`. No backend, schema, provider, deployment, product-price or entitlement
contract changed. L1 and the existing release gates remain open.

[Review the native screenshots](verification/native-refinement/index.html).
These are original simulator/emulator captures. Normal Arabic/Urdu layouts and
large-text accessibility stress captures are separate gallery categories.

| Item | Result | Evidence |
| --- | --- | --- |
| 1. Native Contents | iOS grouped `List` and `DisclosureGroup` rows; Android Material `ListItem` rows. Jump validation, chapter navigation and source-provided structure remain. | ReaderR5 native tests; Contents gallery captures. |
| 2. Normal RTL | Added default-size Arabic and Urdu welcome, account, reader and Saved captures. Large text remains a separate stress case. | `normal-ar-*`, `normal-ur-*` images and native UI tests. |
| 3. Theme leaks | Removed cached iOS separator tints, propagated reader appearance to UIKit menus, and let System appearance retain an unspecified UIKit override. Android app/reader use one complete neutral Material color scheme. | Divider red-to-green test, Luna's live menu/sheet captures, live System dark/light/dark pixel check, native Material-role test. |
| 4. Performance | Isolated scrolling progress from the reader's page composition on both platforms. iOS's identical vertical drag dropped from 17 reader-root evaluations to 2. Android verifies the rendered HUD updates without recomposing its host. | Reader render-count artifacts; ReaderProgressObservationTest. These are not frame-rate or physical-device claims. |
| 5. Reader chrome | Menu/progress controls use native glass on supported iOS and native Material surfaces on Android. Focus physically removes Back/Menu. Status-bar changes use the native animation path; content geometry remains fixed. | Focus rendered-pixel/control test, focused/restored captures, existing LTR/RTL swipe and handoff tests. |
| 6. Transient notices | Reader notices use an inset-safe bottom host. Undo has one absolute deadline; re-rendering does not restart it. Countdown drawing stays inside the ring; canceled hosts cannot expire a replacement notice. | iOS real in-memory Saved-store removal/Undo test and screenshot; Android undo/controller and reader tests. |
| 7. Break testing | Luna reproduced and rechecked iOS theme/menu defects through CUA, inspected safe auth entry, and authored Android native edge-case tests. Review also found and repaired stale drag state, overlapping notices, wrong locale labels and a pinned System appearance. | Native test records and decision trail. Android CUA was unavailable; see limits below. |
| 8. Saved | Narrower bottom filter dock, drag selection in LTR/RTL, native accessibility fallbacks, and semantic bookmark/favorite colors. | Native drag tests, including tap-then-drag regression and 48dp Android targets; Saved captures. |
| 9. Appearance groups | App choices, separate-reader toggle, and conditional reader choices are distinct groups: two off, three on. | iOS group-spacing/toggle test and two/three-group captures; Android AppearanceOptionsTest. |
| 10. Crash reports | Default on when no choice exists. Existing explicit off remains off. Redaction and opt-out clearing remain in place. | iOS persistence/default test and actual SDK-envelope redaction test; Android stored-default implementation and diagnostics tests. |
| 11. Privacy/legal | Plain consumer copy; vendor and file-format jargon removed from these descriptions. Font-license navigation removed; bundled font notices retained. | Native Settings source, privacy tests, bundled notices unchanged. |
| 12. Entry/auth | Stable Welcome/language/demo CTA position, native language rows/insets, automatic real daily hadith with retry, compact Arabic/translation preview, and shared Today text rendering. Account art returns; Sign In is primary and Guest secondary. Forms stay plain. Settings and onboarding use inline native Clerk-backed navigation; Android hides the covered app from accessibility and preserves its tab. One Back/Close pair, Apple light outline and multicolor Google mark. | Both native onboarding/route tests and current gallery. The captured real daily item is Bukhari 140 with Sunnah.now attribution. |
| 13. Paywall | Annual defaults to its actual localized monthly equivalent, with computed same-currency savings and recommendation. Restore/legal actions are in More. Missing price, retry, cancellation, pending and identity-revision behavior remain recoverable. | Pure price/locale tests, native restore/recovery tests, and the production native price-row prototype captures. This is the owner's monthly-equivalent-only prototype, not store-review-ready. |

## Verification record

Machine-readable latest results and rerun history live in
[`verification/native-refinement/verification.json`](verification/native-refinement/verification.json).
Latest coverage is 255 iOS unit and 40 iOS UI passes, with eight opt-in skips;
Android has 209 unit and 99 UI passes, with six opt-in skips.
The earlier failures are retained as red evidence, then superseded by the named
passing reruns. A build or fixture does not establish a successful external
account, purchase, entitlement receipt, or paid-generation transaction.

Focused iOS results include:

- `/tmp/hadithly-refinement-theme-baseline.xcresult`: Paper divider leak reproduced.
- `/tmp/hadithly-refinement-native-separator.xcresult`: native separator repair passes.
- `/tmp/hadithly-refinement-scroll-baseline2.xcresult`: 17 root evaluations; threshold fails.
- `/tmp/hadithly-refinement-scroll-isolated2.xcresult`: 2 evaluations; threshold passes.
- `/tmp/hadithly-refinement-verified.xcresult`: broad unit/UI run; its catalog,
  onboarding isolation, Contents identifier and moved restore-menu failures were repaired.
- `/tmp/hadithly-refinement-unit-final.xcresult`: final unit/privacy/price run.
- `/tmp/hadithly-refinement-onboarding-fixed.xcresult`: production guest entry,
  cold relaunch and live Contents/context-menu path pass.
- `/tmp/hadithly-refinement-focus-pixels.xcresult`: focus, rendered system bar,
  safe-area Undo and bookmark restoration pass. The Undo fixture uses the real
  in-memory guest store, including timestamps, rather than marker-only state.
- `/tmp/hadithly-refinement-demo-preview.xcresult`: current compact daily preview,
  shared-text visibility, CTA position and inline auth routes pass.
- `/tmp/hadithly-refinement-groups-verified.xcresult`: two/three native Appearance groups pass.
- `/tmp/hadithly-refinement-settings-auth.xcresult`: Settings sign-in uses native
  navigation and cancellation restores the same tab.
- `/tmp/hadithly-refinement-pricing-preview.xcresult`: native annual/monthly
  option selection and the real paywall's restore recovery pass.

Android's final Gradle run assembles the app and runs all unit and connected
native tests. Its opt-in external-service/widget skips remain explicit. The
report collector reads actual XML, not the runner's doubled skipped-case count.

Repeat the local checks:

```sh
python3 scripts/check-native-palette.py
python3 scripts/verify-native-system-appearance.py \
  --device <simulator-uuid> --output /tmp/hadithly-system-check
# Installed DEBUG app required; this exercises the gated fresh-install fixture.

cd android
JAVA_HOME=/path/to/jdk21 ./gradlew assembleDebug testDebugUnitTest connectedDebugAndroidTest
```

For iOS use `LA2Verification`, the simulator destination, the existing package
checkout, `-parallel-testing-enabled NO`, and `-collect-test-diagnostics never`.
The latter avoids an unrelated ten-minute simulator sysdiagnose after a failed
assertion; assertions, test recordings and result bundles remain available.

The gallery exporter accepts `--output` and `--android-since` so a new pass does
not silently include old screenshot files. The result collector accepts repeated
`--ios-result` arguments and both Android report directories; `--require-green`
rejects any case whose latest recorded result still fails.

Pricing captures use the production native option component with sample USD
amounts ($24.99 annual / 12 and $2.99 monthly). Their purchase CTA is disabled.
They demonstrate presentation and selection, not live offering or receipt proof.

## Motion and native design references

The requested Transitions.dev skill and one hosted Motion Agent run were used in
the earlier pass; that hosted result describes its isolated UI study, not native
apps. This refinement used the skill's
[sliding-tab](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-dev/16-tabs-sliding.md)
and [toast](https://github.com/Jakubantalik/transitions.dev/blob/main/skills/transitions-dev/22-toast.md)
patterns through SwiftUI/Compose, including reduced-motion handling. It does not
add a web runtime or redistribute the CSS library. Android keeps native
[Material navigation](https://developer.android.com/develop/ui/compose/components/navigation-bar).

## Attention

Reviewed by GPT-6 Astra. Its concrete findings were repaired: Android banner
clearance, cached drag selection, app-locale paywall labels, and iOS System-theme
pinning. The final captures also exposed and led to repairs for duplicate auth
Back controls and a daily preview that hid the translation below long Arabic.

Android CUA could not bind the emulator. It was first headless; restarting the
same AVD with a GUI still exposed no supported CUA app, and documented `getApp`
returned `Invalid app`. No alternate UI protocol was substituted. Android evidence
comes from Luna-authored native instrumentation and rendered captures. iOS CUA's
app accessibility tree also stopped exposing children late in the run; XCTest
completed the remaining UI checks. This is not a claim of exhaustive manual QA.

The annual total is intentionally hidden in the owner-selected prototype. Apple
and Google require the total billed amount to be visible before store submission:
[Apple](https://developer.apple.com/app-store/subscriptions/),
[Google Play](https://support.google.com/googleplay/android-developer/answer/9900533).
The underlying annual store package/charge was not changed. The app directly
invokes RevenueCat/StoreKit or Play Billing; an OS request to authenticate a store
account cannot be bypassed by app UI. No real purchase was made during this pass.

No credentials, email sends, real paid generation, store/product changes, new
service deployments or production changes were used for this verification.
Authenticated provider/store lifecycles, physical devices, published-policy
alignment, native-speaker copy approval and all earlier release gates remain open.
Scoped copy revisions across the existing fifteen locales are drafts, not L1
approval. Stop before L1.
