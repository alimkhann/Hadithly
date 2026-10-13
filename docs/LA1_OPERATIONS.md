# LA1 operating contract

Owner: Alim. Initial escalation is email to the existing verified owner channel.
No phone/SMS, Linear, analytics, replay, paid plan, automatic upgrade or Seer.
All four Sentry projects must disable source fetching and IP storage. Additional
sensitive fields include city, subdivision, region, country_code and ip_address
to remove server-derived geography. SDK user removal alone does not prevent
this enrichment; verify a new event after the settings propagate.

## Development activation

Use four projects (`hadithly-ios`, `hadithly-android`, `hadithly-backend`,
`hadithly-web`) in the existing Sentry organization on Developer. Confirm the
actual plan and disable any trial/paid additions before ingestion. Install DSNs
only in ignored native configuration and development Convex environment.
No application API token or privileged Sentry API token belongs in an app.

Deploy only development Convex and a Vercel preview of `site/`. Production
activation, disclosures and store distribution remain release gates. Native
consent is off; enable it only on disposable verification installations.

## Collection and retention

| Stream | Sampling and cap | Retention |
| --- | --- | --- |
| Native errors | First five eligible errors/day/device after consent; no sessions or success telemetry. Fatal events share this cap, so a noisy handled-error day can hide later crashes. | At most ten SDK cached envelopes; purge files older than seven days at startup. Opt-out purges owned cache. Sentry events: 30 days, subject to actual account readback. |
| Backend | At most one error/minute globally, 800 admitted reports/month. Development synthetic errors bypass interval, still spend the cap. | One coarse state row; monthly scheduler rollover erases old failure counters. No raw event rows. |
| Web fallback | Local consent, one fixed error/page, no cookies or user identity, 200 reports/month across browsers. | No browser queue; same bounded server counters and Sentry event retention. |
| Logs | Safe fixed event JSON only; no external raw Convex log streaming. | Convex platform logs use the provider's retention, not a promised local TTL. Confirm account retention before launch. |
| Build symbols | Apple debug symbols without source contents, matching UUIDs. | Retain only active supported releases; review/delete retired artifacts separately from event retention. |

The five-per-day native limit uses UTC days and the device clock.
SDKs can store local crash material before callback reconstruction. This stays
in the protected app sandbox, is never joined to an account, and is purged on
revocation. In-flight network requests can complete after revocation. No claim
of retroactive removal of received reports is made.

Sentry Cocoa 9.30.1 and Java 8.60.0 are pinned. Android raw NDK/minidump and raw
tombstone attachments are off; converted tombstones require Android 12+.
Android 8–11 C/C++ coverage is incomplete. JVM crash reporting remains available.
iOS hang, watchdog and MetricKit collection are disabled. This acceptance proof
covers ordinary fatal crashes; it does not claim coverage of every OS termination.

## Uptime and alerts

Four standard Google public uptime checks in `hadithlyapp`, five-minute interval,
three checker regions, HTTPS GET, ten-second timeout, expected HTTP 200:

1. `https://hadithly.app/`
2. `https://hadithly.app/hadith/bukhari/57`
3. Development Convex `/health/public`
4. Development Convex `/health/notifications`

The HTML checks prove HTTP availability, not JavaScript execution or licensed
text. `/health/public` reads only the tiny diagnostics row. Five sampled backend
failures in ten minutes or the exhausted backend diagnostic quota produce 503.
The failure counter uses a fixed ten-minute window beginning with its first
admitted failure, rather than storing every failure timestamp. Public web errors
cannot increment that backend failure count. Notifications
produce 503 when the cron heartbeat is older than 45 minutes. Empty cron runs
can advance its heartbeat; this proves scheduler execution, not push receipt.
No probe performs provider work, content generation, personal reads or sends.

Uptime alerts require failed checks in at least two regions for ten minutes;
email recovery closes the incident. Sentry's saved development rule watches
only the four Hadithly projects. A new issue, escalation or resolved-issue
regression notifies Alim, with a one-hour cooldown per issue. Its email subject
carries surface, environment, release and the fixed failure title. Existing
issues can span releases; a new release alone does not guarantee a new
notification. Production alert activation remains a release handoff.
`/health/alert-test` has a development-only internal switch and
automatically recovers after 15 minutes; it does not change real API health.

## Cost boundaries and outage behavior

- Sentry Developer: $0, 5,000 errors/month shared across projects, no paid
  upgrade/overage. Set provider usage warnings at 50% and 80% if available.
  The free-tier stop drops reports. Public DSN abuse can exhaust the allowance;
  client admission is not an organization-wide quota guarantee.
- Google standard uptime: 107,136 regional executions in a 31-day month for
  this four-check configuration, within the current 1,000,000/project allowance.
  Excess is $0.30/1,000. No synthetic monitors or custom metrics. Fixed check
  count/frequency is a configuration ceiling, not a billing hard stop.
  Audit existing project usage and quota controls. Alert pricing is currently
  scheduled no sooner than September 2027; recheck before then.
- Convex probes contribute about 53,568 HTTP checks/month across the two
  endpoints at three regions. Each HTTP action also invokes one internal health
  query; include those executions when checking the account's usage. Admission
  caps limit diagnostic writes/sends, not
  rejected HTTP calls. Read back provider hard usage limits; otherwise a public
  flood remains a spend risk. Provider hard limits can affect normal API
  availability, which must be recorded explicitly.
- Backend/web delivery: one three-second request, drop on timeout, 429 or any
  error. No reporting of reporter failures. Native SDK caches are bounded and
  provider Retry-After applies; actual retry/cache replay still needs proof.
- Gemini/push/processor outages preserve existing product retry/skip behavior;
  telemetry does not retry those providers. Reading uses cached/offline paths.
  Reporting outages must never block reading, sync, purchases or deletion.

## Incident response

Open the linked release/operation. Check whether the failure is the app, Convex,
or provider. Preserve cached/offline reading, pause the affected bounded worker
or release if needed, and use its existing kill switch. Record start time,
affected function, user impact, mitigation and recovery without user data.
Never paste raw provider responses, URLs, account IDs or evidence into an alert.

## Symbol verification

Build with neutral Swift debug/file prefix maps and debugging-option
serialization disabled. Upload the actual archive's dSYMs with
`scripts/upload-diagnostics-symbols.py`, an owner-approved token in the
environment, never an argument or committed file. The script rejects local
user paths and disables source upload.
Record `dwarfdump --uuid` and compare with the redacted fatal event's debug ID.
Current Android releases are unminified; record the class/file/line readback.
If R8 is enabled later, its mapping upload becomes a release requirement.
Backend fixed codes and unbundled web JavaScript require no source-map upload.

For an archive, pass the neutral Swift flags to `xcodebuild` as well, so Swift
package compilation receives them: `OTHER_SWIFT_FLAGS='$(inherited)
-debug-prefix-map $(HOME)=/build -file-prefix-map $(HOME)=/build'` and
`SWIFT_SERIALIZE_DEBUGGING_OPTIONS=NO`. Keep the normal approved signing and
production configuration for a release archive. Upload only its matching
`dSYMs/Hadithly.app.dSYM`; the script's byte check must pass first.

## Acceptance checklist

- Actual iOS and Android fatal/restart transmitted envelope, sanitized fields
  and symbolicated vendor stack.
- Consent off, opt-out, crash then disabled restart, re-opt-in without old reports.
- One backend and one served web synthetic error received with the same release
  fingerprint/environment; exported vendor payloads contain no forbidden data.
- Google/Sentry plan, caps, monitors, rule and channel readbacks.
- Alim confirms receipt of one test alert, then temporary testing is disabled.
- Production rollout/disclosures and earlier product gates remain explicit.

Pricing sources: [Sentry](https://sentry.io/pricing/) and
[Google Observability](https://cloud.google.com/products/observability/pricing),
checked 2026-10-13. Dashboard settings and actual delivery remain separate proof.
