# LA2 verification

Recorded October 14, 2026 (Asia/Almaty); provider buckets use October 13 UTC.
LA1 passed its October 13 development gate. LA2 implementation and the approved
aggregate development readback are complete. Full device/account/store and
production gates remain open. Stop before LA3.

## What passed

- Backend typecheck and 333 tests, including 12 LA2 tests. Strict HTTP/property
  canaries, actual final SDK-request serialization, concurrent admission/dedup,
  expiry cleanup bursts, caps/rollover, leases, network rejection/429 and the
  development-only early-export guard are deterministic.
- Both native closed contracts, forty-fact bound (39 product plus one marker),
  independent opt-out, sign-out/deletion queue clearing, expiry during retry,
  actual serialization, prepared-example parity and ordered flow checks pass.
  Full iOS final suite executed 250 tests (eight opt-in skips, zero failures);
  latest consent/corruption checks passed 13 tests (one live opt-in skip). The
  explicitly enabled earlier live run executed all ten tests successfully. Android
  build and 201 units passed; eight installed onboarding/contract/paywall checks
  passed with one live opt-in skip, followed by seven contract/paywall rechecks.
- iOS simulator `D47D7363-4705-4767-8617-F47DDB6A3241` (Hadithly LA2 iPhone18 Pro,
  iOS27) and Android emulator `emulator-5554` (hadithly AVD, Android16) exercised
  welcome, language, prepared reveal, account choice, cancelled sign-up, guest
  entry and a real development collection. iOS restart did not repeat onboarding.
  Android's final journey used production MainActivity. Retained screenshots show
  English dark iOS and Arabic RTL/light Android. These are scoped layout proofs.
- An actual Android readback caught acknowledgement cancelling its measurement
  coroutine. The command now finishes at acknowledgement; a separate active-page
  probe waits for the frame. Real guest visible-reading counters increased above
  the five synthetic-fixture baseline on both platforms after the repair.
- Real quota sheet tests retained Q2's offer/restore behavior on Android; iOS
  lifecycle/unit/UI evidence is retained from the local implementation pass.
  Store lifecycle fixtures do not prove real subscription receipts.

## Provider and exact-count proof

The owner approved free development provisioning, credentials, six dashboard
panels and development deployment. A new isolated EU organization was required
because the existing personal organization was on a paid plan. The final project
is 304602, dashboard 1020618, free/no-card/capped allowance. UI readback confirmed
IP discard and disabled autocapture/heatmaps/web-vitals/replay. Only aggregate
server capture is installed; no native PostHog SDK or customer integration exists.
The free plan UI displayed one-year retention, longer than local 90-day aggregates.

Five synthetic Swift and Kotlin flow/transport fixtures each produced 15 summaries
per platform. Actual native UI journeys and quota-sheet verification added
separate development counts. Frozen pre-export buckets had 18 iOS and 33 Android
summaries. These are summaries, never distinct people. The 62 exported metric rows
match those frozen counters exactly, with 16 approved properties and no content,
locale, account/device ID, raw error, batch UUID or canonical target.

For immediate proof, the internal export action used `verifyCurrentDay:true` only
while a dedicated flag and the exact development URL allowed it. Production and
ordinary cron require settled days. The flag was removed after proof; development
`ANALYTICS_ENABLED=0` was read back. Production was never activated. Further
admission to an exported fixture bucket is rejected instead of changing totals.

Evidence:

- `evidence/la2/native-counts.json`: safe frozen ingress counters.
- `evidence/la2/provider-readback.json`: exact provider counts and property keys.
- `evidence/la2/posthog-free-plan.jpg`, `posthog-dashboard.jpg`: actual vendor UI.
- `evidence/la2/ios-demo.png`, `ios-account.png`, `android-demo.png`,
  `android-account.png`: native scoped visual proof.
- `scripts/audit-la2.mjs`: rerunnable catalog/resources/dashboard parity,
  deterministic expiry/cap/retry/property tests; optional `--live` provider
  readback/exact comparison and approved `--dev-ingress` forbidden-key checks.

## Gates deliberately still open

1. Fresh real sign-up/sign-in across both platforms, authentication failure and
   interruption, pending links/notification targets through restart/authentication.
2. Full Urdu RTL, small screens, large text, VoiceOver/TalkBack and Reduced Motion
   matrix on physical devices. Copy/sample coverage is tested, native-speaker
   localization approval remains release work.
3. Physical signed-out/cached/offline reading, artifact update/corruption,
   eight-point/dp restoration, notification landing and account-switch/retry matrix.
4. Genuine Apple/Play store receipts and product availability, pending payment,
   refund/renewal/restore/entitlement delay and confirmed quota retry. Q2's existing
   Apple agreements/device and Play Console prerequisites remain unchanged.
5. Published privacy/store disclosures, distribution-specific consent mechanism,
   platform request-log/IP retention assessment and separately approved production
   activation. The privacy HTML change is a candidate, not a live publication.

Anonymous local expiry/opt-out/deletion mechanics are proven by serialized native
and server tests. No analytics identity or account mapping exists to delete at
PostHog. Already accepted anonymous totals cannot be selectively subtracted; this
is disclosed rather than described as account-linked analytics deletion.

Large-text onboarding → cancelled authentication → guest reading also passed on
both installed platforms: iOS accessibility-XXXL content size and Android font
scale 1.6. Temporary scale changes were restored. This does not close physical
VoiceOver/TalkBack, Urdu or Reduced Motion gates. Fixed recoverable operation
counts appear with their corresponding product panel; a descriptive count has
no conversion denominator.

Final review also verified genuine Boolean consent types, bounded corrupted queues,
clipping-invalidated ordering, completed-resource authentication facts, and fenced
late backend access. Numeric/string consent corruption fails closed.

Implementation checkpoints: `2d38ed3` (contract/backend), `8dc4747` (native
measurement/controls), `42ce9d2` (onboarding), `d6e4edb` (quota sheet). Documentation,
operator dashboard tooling and safe evidence are the final proof checkpoint.
No push or production activation was performed.
