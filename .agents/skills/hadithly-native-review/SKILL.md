---
name: hadithly-native-review
description: Review one Hadithly native journey for platform fit, accessibility and cross-platform meaning.
---

Choose one journey and record device/OS, build, locale, theme and text size.
Use the existing native harness and the explicit Android target runner from
AGENTS.md. Inspect the rendered app and interactions before proposing changes.

Review each platform against its own conventions. Consult installed Apple HIG
for iOS and one Material/Android guideline skill for Android. Parity means the
same capability, meaning, privacy and state transitions; layout and interaction
may differ. An iOS screenshot alone cannot establish Android's correct design.

Inspect hierarchy, navigation/back behavior, loading/empty/error states, touch
targets, focus, scrolling, wrapping and reduced motion where the journey uses it.
For language changes, check Arabic to English in the same process and revisit
Settings, including back-navigation and restarted state. Use representative long
copy and large text. Keep language-review approval distinct from layout evidence.

Return a ranked short list with reproduction, screenshot/trace path, user impact
and the smallest proposed repair. If asked to implement, fix only the selected
unit, rerun its original journey and verify the other native app's contract.
Keep fixtures and authenticated/device evidence labeled separately.
