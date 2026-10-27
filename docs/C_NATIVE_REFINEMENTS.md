# C native refinements

October 27, 2026. B's findings are in
[`product-program/research-decisions.md`](product-program/research-decisions.md).
C local refinements are verified below. Continue D, then return to A4–A7. Existing content,
physical-device, auth, purchase and release gates remain open.

| Requirement | Current result |
| --- | --- |
| C1 paywall | Local prototype presentation and interaction pass on both apps, including large RTL text. Actual annual total remains a release requirement. |
| C2 translation reveal and states | Centered states have simple icons and no cards. Limits stay inline until an explicit plan action; unknown allowance retains that action. Native reveal, interruption and reduced-motion checks pass. |
| C3 focus and thin progress | Real iOS focus toggles retain text position and the thin progress strip. Android HUD updates and focus toggles retain the four-dp strip, including unknown totals. |
| C4 separate glass elements | iOS fusion reproduced and repaired; sampled rendered gaps and Android Material parity pass. |
| C5 Daily appearance | Reproduced and fixed on both apps. Daily and its source presentation use app appearance, independent of the reader theme. |
| C6 Contents names and navigation | Source names now carry their actual source volume numbers. iOS removes the extra start row and opens the volume from its name. Direct volume, chapter and jump paths pass locally. |
| C7 page controls | iOS page-switching pills now use the shared glass control, including its Reduce Transparency and pre-iOS-26 fallbacks. Native labels, edges, LTR/RTL and Android Material pager checks pass locally; older-OS runtime remains a device gate. |
| C8 onboarding/auth | Official Google artwork and a contextual browser hint are implemented. Entry, cancellation, recovery and keyboard checks pass locally. External OAuth/account acceptance limits remain. |

## Daily appearance and Contents

The Daily regression uses the real Today view with prepared text and opposite
app/reader themes. Before the fix, a light app rendered a dark Daily card on both
platforms. iOS sampled red channel 26 against the light threshold of 180.
Both light-app/dark-reader and dark-app/light-reader cases now pass on both apps.
Typography, text visibility and the independent reader preference are preserved.
No content generation is involved.

Contents now uses the same source-name selection already used by reader headers.
It takes the number from the source title or numeric volume ID, never from the
array position. A source with volumes 1 and 3 therefore keeps 3. Missing names
retain the existing generic title; missing numbers are not invented. iOS checks
the raw generic title before localizing it, so an Arabic generic title does not
receive a second numeric prefix. Existing native List/disclosure controls and
Material rows remain. The source name itself opens the volume on both apps;
chapter selection and valid/invalid jump handling remain verified.

Independent GPT-6.1 Terra review identified the noncontiguous-number and Arabic
generic-title cases. Both were repaired and covered through actual native views.
The review used a different GPT model, respecting the owner's GPT-only rule;
it was not a cross-family review.

## Verification and rendered evidence

Eight distinct iOS checks cover this unit across the recorded runs: Daily in both
appearances, the existing sheet gallery, five Contents interaction checks and the
source-number/Arabic generic-title case. Eleven Android checks cover Daily, the
sheet gallery and nine Contents/context-action cases. The final failing cases
were rerun successfully. This is local native fixture evidence, not a claim of
continuous manual QA, full accessibility traversal or live provider/auth proof.

| Evidence | Result |
| --- | --- |
| `/tmp/hadithly-c-daily-red-ios.xcresult` and `/tmp/hadithly-c-daily-red-android.log` | Both reproduce the Daily appearance defect before the fix. |
| `/tmp/hadithly-c-daily-contents-ios.xcresult` | Daily and gallery pass; two Contents identifier lookups failed and were repaired. |
| `/tmp/hadithly-c-contents-fixed-ios.xcresult` | Chapter/jump/render checks pass; direct volume query exposed inherited duplicate identifiers. |
| `/tmp/hadithly-c-volume-tap-ios.xcresult` | The scoped query taps the actual volume name and dismissal passes. |
| `/tmp/hadithly-c-source-numbers-ios.xcresult` | Three checks pass, including source volumes 1/3 and Arabic generic-title handling. |
| `/tmp/hadithly-c-daily-contents-android.log` | Nine of ten pass. The lone failure expected an English digit on an Arabic device. |
| `/tmp/hadithly-c-contents-locale-android.log` | Locale-aware numeral assertion passes. |
| `/tmp/hadithly-c-source-numbers-android.log` | Both source-number and chapter-label checks pass. |

The iOS result collector retains per-case rerun history in
[`verification/c-native/verification.json`](verification/c-native/verification.json).
Android's final two-case XML reports are archived beside it; the broader-run
summary is retained with its command log. An initial Android run had no connected
device. The stopped AVD was launched, and a cold-boot System UI error overlay was
dismissed. Its obscured screenshot is excluded from the rendered evidence below.

| iOS before | iOS after |
| --- | --- |
| ![Daily incorrectly used the dark reader theme](verification/c-native/daily-ios-before.png) | ![Daily follows the light app theme](verification/c-native/daily-ios-after.png) |
| ![Generic volume label and extra start row](verification/c-native/contents-ios-before.png) | ![Numbered source name and direct navigation](verification/c-native/contents-ios-after.png) |

| Android before | Android after |
| --- | --- |
| ![Daily incorrectly used the dark reader theme](verification/c-native/daily-android-before.png) | ![Daily follows the light app theme](verification/c-native/daily-android-after.png) |
| Contents baseline obscured by the system overlay is excluded. | ![Numbered source name in native Contents](verification/c-native/contents-android-after.png) |

Prepared interface text is labeled in the captures. It is not offered as a real
hadith or as semantic/content-availability proof. At this checkpoint, five incoming
Xcode/catalog files remained byte-for-byte unchanged against the C snapshot. No project
regeneration, deployment, paid provider request, billing change or publication
occurred.

## Separate glass controls and coherent auth

C4's production-reader fixture reproduced visible fusion between menu cards. The
container's 12-point blending distance exceeded the six-point visual gaps. Setting
the blending distance to zero preserves the existing sizes, gaps and native glass
while keeping each control separate. The rendered gap test failed with an average
RGB-channel difference of 25 from the underlying reader, then passed at 2 and 3.
The first diagnostic attempt merely started focused and did not find the menu;
it is not counted as reproduction of the glass defect. Android retains native
Material surfaces, with passing order/size checks and a rendered parity capture.

C8 replaces the hand-drawn Google mark with the unmodified official
[Google G asset](https://developers.google.com/static/identity/images/g-logo.png),
linked from [Google's branding guidance](https://developers.google.com/identity/branding-guidelines).
Both native resource files have SHA-256
`d1ce9c2af0b10a7333abc99bc706f9a6a199e5b65bf3e3009624f076b8638e6a`.
They preserve its color and aspect ratio. The nearby hint explains the existing
browser handoff. Apple and email flows, Clerk calls, identity resolution,
cancellation/recovery handling and billing are unchanged.

The hint uses `c-native-copy.json` and the existing scoped copy generator. All 15
locale entries are present; non-English copy remains draft/needs_review. The full
A4 sweep and native-speaker approval are still open. Removing exactly this new
catalog entry restores every byte of the incoming catalog snapshot. Only this
entry is staged for C8; the four incoming project/scheme files remain untouched.

Four iOS checks pass in `/tmp/hadithly-c-glass-auth-ios.xcresult`, covering the
glass gap, auth previews/keyboard, first-install route and Settings cancellation.
The final hint render also passes in `/tmp/hadithly-c-browser-hint-ios.xcresult`.
Android's three auth/entry checks pass in `/tmp/hadithly-c-auth-android.log`, its
final hint/keyboard check in `/tmp/hadithly-c-browser-hint-android.log`, and both
menu parity checks in `/tmp/hadithly-c-menu-android.log`. These are local native
checks. They do not prove an external OAuth round trip or an account/store receipt.
Independent GPT-6.1 Terra review found no actionable regression in this unit.

| Fused menu before | Separate native controls after |
| --- | --- |
| ![Glass menu cards fused across their gaps](verification/c-native/menu-ios-before.png) | ![Each native glass menu control stays separate](verification/c-native/menu-ios-after.png) |

| iOS Google handoff | Android Google handoff |
| --- | --- |
| ![Official Google artwork and browser explanation on iOS](verification/c-native/auth-ios.png) | ![Official Google artwork and browser explanation on Android](verification/c-native/auth-android.png) |

No new hosted Motion Agent credit was used. The prior authorized run and native
motion references remain recorded in `NATIVE_READER_REFINEMENT.md`. Continue C1
and the remaining C2/C3/C7 verification before D.

## Paywall prototype

C1 reuses the native entry artwork behind a simpler heading and two native plan
choices. The annual recommendation and savings labels overlap the option's upper
edge, wrapping naturally when larger text needs more space. Accessibility sizes
stack the price and billing labels. The renewal text has an opaque-enough reader
background to remain readable over the artwork. Selection, price calculation,
purchase, restore and entitlement logic are unchanged.

Independent GPT-family review caught the missing explanation for the rejected
request. The shared heading now retains the existing seven-day exhaustion message
and free-reading assurance. Visual review then found Bengali text incorrectly
copied into seven Android locales. `scripts/sync-paywall-quota-copy.py` reuses this
single message's existing iOS drafts across all fifteen Android locales, with a
rerunnable parity check. These remain drafts awaiting native review.

The two iOS checks in `/tmp/hadithly-c-paywall-reason-ios.xcresult` pass. They
exercise light/dark selection and full price visibility at large Arabic Dynamic
Type, including the Arabic savings label. Android's final copy rerun is recorded
in `verification/c-native/paywall/verification.json`. Earlier layout checks also
passed, but the earlier Android Arabic capture revealed the copy defect and is
superseded. A separate real Android sheet check with an empty purchase API key
passed the existing finite allowance, account explanation, restore guard and close
journey. No store request or receipt is proved by these fixtures.

| iOS prototype | Android prototype |
| --- | --- |
| ![Light native paywall](verification/c-native/paywall/ios-light.png) | ![Dark native paywall](verification/c-native/paywall/android-dark.png) |

Prices are prepared samples. The owner-approved monthly-equivalent-only prototype
is retained. The missing actual annual total is an explicit store-readiness gate;
this unit does not approve the paywall for release. Large RTL captures demonstrate
scrollable access to both complete prices, not native-copy approval.

## Translation state, focus and page controls

C2 removes the card backgrounds and centers missing, sign-in, temporary failure
and allowance states, with a small redundant icon. Existing exact-text reveal,
manual translation, cache reads, allowance values and retry deadlines remain.
A quota failure no longer opens a paywall over the reader. The user can choose
See plans inline. Unknown allowance also retains that explicit action without
inventing a tier or count; a known Pro limit offers no further upgrade.

The production iOS quota fixture reproduced the automatic sheet interruption,
then passed after removing the watcher. Both native watchers are removed; the
explicit callbacks remain. Independent review caught the unknown-allowance edge
case, now covered on both platforms.

The iOS system Reduce Motion check reproduced a moving native spinner. The
waiting view now uses a static hourglass when that setting is on. Android uses a
restrained native glyph opacity pulse through the existing foreground/motion
policy. The complete text appears without an artificial delay; its reveal remains
400 ms, or no animation with reduced motion. An actual iOS reader test pages away
and back while preparation continues, without losing access or state.

Android's initial active-animation assertions failed because the test put the
indicator behind the opaque system status bar. Animation-value probes advanced
normally; a full device capture exposed the hidden row. The final fixture adds
safe-area padding and waits for draw completion before comparing the rendered
indicator itself. It checks enabled platform animation state, visible motion,
static reduced motion and full-result completion. Temporary probes were removed.
A cold-boot System UI ANR overlay was dismissed and its captures are excluded.
The failing test attempts are retained as diagnostic history, not app defects.

C3 preserves the actual iOS Arabic text position to within one point through
focus entry and exit, hides controls and retains an 88-by-4-point progress strip.
Android checks the visible four-dp strip with unknown totals, focus toggles and
real fill updates without recomposing its host. C7 replaces the remaining painted
iOS page capsules with the existing shared native glass modifier. The modifier
already uses an opaque surface for Reduce Transparency and native thin material
before iOS 26. Those branches compile; this run's actual iOS runtime is 27.
Android retains Material controls. Current control labels, touch targets, absolute
edges, adjacent volume names, LTR/RTL swipes, short-drag cancellation, vertical
scroll arbitration and incoming-page geometry remain covered locally.

The final native evidence has 19 distinct iOS and 21 Android passing cases.
`verification/c-native/reader/verification.json` combines each case's latest result
and retains the earlier failed iOS attempts. The three old R6A control tests first
failed before opening their fixture because they omitted the now-required test
opt-in; their helper is repaired and their final runs pass. The glass capture
fixture also now receives its theme before the native appearance boundary, so its
UIKit glass uses the same appearance as the real reader. Its initially mismatched
light-glass-on-dark capture is superseded. These checks do not
prove physical-device frame pacing, a full VoiceOver/TalkBack traversal, an older
OS runtime, live generation or account/store acceptance.

| Inline state without a card | Native page controls |
| --- | --- |
| ![Centered allowance state](verification/c-native/reader/ios-reader-status-quota-light-en.png) | ![Glass page-switching pills](verification/c-native/reader/ios-native-page-controls.png) |

No deployment, paid provider request, new hosted Motion Agent credit, billing or
publication occurred. The incoming four project/scheme files and every original
catalog byte are still preserved. C8's single committed hint is the only catalog
addition from this run. Continue D locally, then A4–A7; all recorded external,
content, native-copy and release gates remain open.
