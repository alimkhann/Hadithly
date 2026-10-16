# Reader translation states and language round trips

October 17, 2026. Owner-authorized follow-up to the native refinement and the
[product readiness review](PRODUCT_READINESS_REVIEW.md).

[Open the native screenshot gallery](verification/reader-status/index.html).
The iOS captures use production reader blocks in a deterministic fixture. Android
captures show the production status component in a minimal native fixture.
Allowances and translation outcomes in these captures are synthetic.

## Presentation and recovery

| Principle | Severity before | Before | Implemented result |
| --- | --- | --- | --- |
| Explain missing content | Medium | A small generation link occupied an otherwise unexplained gap. | A quiet, leading-aligned status surface identifies missing text and offers Translate. |
| Make recovery clear | High | A generic error/retry sentence, duplicated timing, and inconsistent notice layouts. | One status, one native recovery control, one localized server retry time. Raw provider errors stay hidden. |
| Show honest progress | Medium | Sparkles, animated dots, shimmer, and placeholder lines competed with the text. | One native progress indicator and Preparing translation. No invented completion estimate. |
| Keep reading quiet | Medium | Allowance and reset text remained under loaded translations. | Count and timing stay with unavailable/loading states; readable text has no repeated allowance footer. |
| Match the actual limit | High | Every quota rejection offered plans, including Pro exhaustion. | A known free limit can open plans. A known Pro limit shows its retry time without another upgrade offer. An elapsed deadline offers retry. |
| Use the selected UI locale | High | Dynamic iOS formatted strings could use the system language; Android count/time drafts remained English. | The existing iOS bundle lookup and Android localized resources resolve the selected UI locale. Number/date formatting and status direction follow that locale, independently of the reading language. |

The timestamp is the backend's admission/retry hint. The copy says Try again;
it does not promise that a translation will exist at that time. iOS schedules an
update at the deadline; Android uses a cancelable deadline effect. Retry is
disabled during a known cooldown. No backend, quota, paid generation, entitlement,
source-citation, or deployment policy changed.

Twelve scoped strings have English source values and generated drafts for the
other fourteen supported locales. `docs/reader-state-copy.json` records review as
pending. The generator preserves existing catalog entries and converts Objective-C
string placeholders to Android string placeholders. This is not full L1 completion
or native-speaker approval.

## RTL reproduction and repair

The existing Settings test checked labels, titles, and tab order. It missed row
geometry. A new test drives the real onboarding root and captures the defect:
English name x=62 initially, x=285 after Arabic → English. The native list retained
its RTL cell layout. Recreating only the language list when layout direction
changes repairs it. The same boundary is applied to the native Settings picker.
Onboarding progress, selected preferences, and navigation remain outside that
identity change.

The repaired real-root onboarding test passes both Arabic and Urdu round trips.
The Settings test passes Arabic → English, and its native picker captures were
visually compared:
[before](verification/reader-status/ios-language-english-picker.png) and
[restored](verification/reader-status/ios-language-english-picker-restored.png).
Android's real-root onboarding test checks both languages and row/back geometry;
its Settings Arabic round trip also passes. Android needed test scroll-to-node
handling for the initially uncomposed Urdu row, with no product repair.

## Focused verification

Eleven distinct iOS UI cases and thirteen Android UI cases pass across the
focused runs. These are case counts, not a full application regression run.

| Run | Result |
| --- | --- |
| `/tmp/hadithly-rtl-investigation-retry.xcresult` | The old Settings label/tab test passes, demonstrating its coverage limit. |
| `/tmp/hadithly-reader-status-final.xcresult` | New onboarding geometry assertion fails with x=285 versus x=62. Reader follow-ups pass. |
| `/tmp/hadithly-rtl-roundtrip-repaired.xcresult` | Onboarding geometry passes after the narrow repair. Its Settings setup failed because previous onboarding had not completed. |
| `/tmp/hadithly-reader-status-verified.xcresult` | All nine reader-state cases pass, including cache, quota, Pro, cooldown, expiry and paywall recovery. |
| `/tmp/hadithly-reader-and-rtl-final.xcresult` | Onboarding and reader follow-ups pass. A new Settings leaf-text probe was invalid because native Picker exposes a merged row; it was replaced by native captures. |
| `/tmp/hadithly-reader-status-handoff.xcresult` | Settings round trip and two reader follow-ups pass. Settings launch now explicitly supplies completed onboarding in its process arguments. |
| `/tmp/hadithly-reader-status-copy-final.xcresult` | Both final reader follow-ups pass after deadline/copy changes; the Arabic gallery asserts localized count and time text. |
| Android reader/evidence run | Eleven cases pass after the final copy change: TranslationQ1Test and EvidenceProcessingStatusTest. |
| Android real-root round trips | Two cases pass: OnboardingLA2Test language round trip and LanguageSwitchTest. |

The first status run also exposed an iOS container identifier being inherited by
its controls. Explicit accessibility containment repaired it. Android's first
English-label assertions ran under the emulator's Arabic resources; the component
tests now explicitly supply their locale, with a separate rendered Arabic case.
Earlier failures are retained in the local result bundles rather than counted as
passes.

Rerun the copy contract:

```sh
python3 scripts/generate-ui-polish-copy.py --source docs/reader-state-copy.json --check
```

Re-export native captures after the named UI tests:

```sh
python3 scripts/collect-reader-status-evidence.py \
  --xcresult /tmp/hadithly-reader-status-copy-final.xcresult --android
```

Scoped presentation review: **Approve** for the inspected states. Physical devices,
VoiceOver/TalkBack, large-text stress, live generation/reset, and real purchase
transactions were not verified here. Overall release readiness remains **Block**
under the existing copy, content, account, store, production, and device gates.
