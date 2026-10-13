# LA1 diagnostics design

Date: 2026-10-13. Alim authorized LA1 with H3, O2, W2 and Q2 gates retained.
LA2 remains out of scope. Entry dependencies are not retroactively passed.

## Working phases

- Ground: complete. Traced startup, local privacy controls, provider actions,
  notification cron, static fallback and CI.
- Sketch: complete. Two independent candidates and a third independent judge.
- Agree: proceed under the owner's LA1 instruction and dependency exception.
- Implement: complete; development verification is recorded in `LA1_VERIFICATION.md`.
- Scrap: reconsider if redaction prevents readable symbolication or delivery.

## Callers and ownership

Native callers use `diagnostics.setConsent(enabled)` and
`diagnostics.failure(.offlineManifest)` with no error or arbitrary text argument.
The local preference is independent of accounts and analytics. At provider
boundaries, Convex calls `reportFailure(ctx, "generation")`. The static fallback
reports only `canonical_resolver` after local page-error consent.

Each adapter rebuilds its serialized payload from an allowlist. Cocoa copies
the clean fields back into the original capture object to retain private SDK
fatal-capture flags, then checks its serialized top-level keys. Fixed operation codes and
build/environment metadata are the whole backend/web payload. Native events add
bounded code stacks and build-image UUIDs/addresses needed for symbolication.
Exception values, contexts, user fields, requests, source context, variables,
registers, thread names and attachments are discarded. Reporting never accepts
account IDs, notes, evidence, queries, locale/content IDs or text.

## Synthesis

Sentry Developer is the base. Crashlytics was cheaper to integrate on Android,
but its public native APIs cannot replace automatic fatal exception messages
before upload. Its intrinsic installation identifiers also survive custom-key
filtering. Opt-in custom errors alone do not meet the crash contract.

Sentry supplies the missing pre-upload filtering hook. One vendor serves all
four surfaces; backend and web need no Sentry SDK. Google Monitoring uses the
existing Firebase/Google project. No Linear, paid log streaming or second
application backend is needed.

From the Google candidate, retain fixed provider failure enums, bounded coarse
Convex state, shallow health probes and a fixed uptime configuration. Reduce
backend/web admission to 1,000 reports/month so native reports have headroom in
the shared 5,000-error allowance. Direct DSN abuse can still exhaust that quota.

One generated source fingerprint identifies the same code on every surface.
Native app version/build is separate. Cached crash events retain their original
validated release/environment. Apple dSYMs must match event image UUIDs.
Android currently disables R8, so readable frames need no mapping; enabling R8
requires a matching mapping upload before release. Unbundled static JavaScript
and fixed backend operation codes need no source maps or source-content upload.

## Proof required

Actual fatal/restart envelope and symbolicated vendor readback must prove native
filtering. Cocoa runs processors after its callback; the pinned source registers
only the replay processor, and replay must remain disabled. Android NDK/raw
tombstones are disabled. Converted tombstones cover Android 12+; JVM reporting
works on minSdk 26, with Android 8–11 C/C++ coverage explicitly incomplete.

Consent off, opt-out, restart and re-opt-in need cache and transport proof.
Remote completion requires four readable redacted events, release correlation,
symbol readback, provider quota configuration and Alim's test-alert receipt.
Local tests and successful builds do not close those gates.

## Sources checked

- [Firebase crash customization](https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports)
  and [privacy](https://firebase.google.com/support/privacy).
- [Sentry Apple filtering](https://docs.sentry.io/platforms/apple/guides/ios/configuration/filtering/),
  [Android tombstones](https://docs.sentry.io/platforms/android/configuration/tombstones/),
  and [pricing](https://sentry.io/pricing/).
- [Google observability pricing](https://cloud.google.com/products/observability/pricing)
  and [uptime checks](https://docs.cloud.google.com/monitoring/uptime-checks).
- Pinned Sentry Cocoa 9.30.1 and Java 8.60.0 source inspected for serialization,
  callback ordering, attachments and shutdown behavior.
