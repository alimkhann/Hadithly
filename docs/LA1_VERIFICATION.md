# LA1 verification

Date: 2026-10-13. Scope: development activation only; stop before LA2.

Development acceptance passed: four readable redacted reports, shared release,
matching Apple symbols without source, owner-confirmed test alert and recorded
admission/configuration caps. The release limitations below remain open.

## Entry and authorization

R5, S1 and E4 have passed their recorded development gates. H3, O2, W2
and Q2 still have open product/device/store gates. Alim explicitly authorized
LA1 to proceed while retaining them. This is an exception to entry sequencing,
not a claim that all dependencies passed.

Alim approved the four free Sentry projects, ignored local DSNs, development
Convex deployment, Vercel preview, four Google checks, source-free symbol upload
and an owner test alert. He later authorized temporary `org:ci` token creation
and permanent cleanup of the initial synthetic issues and obsolete dSYM.
There was no production deployment, paid upgrade, Relay use or LA2 work.

## Implementation and local proof

- Native privacy controls start off and remain independent of account identity.
  SDK adapters discard raw exceptions, user/request/context data, breadcrumbs,
  attachments, source context and variables. They retain fixed operations,
  release/environment and bounded code frames/debug-image metadata.
- Backend provider boundaries report fixed enums. Daily raw provider/token/content
  log strings were removed. No external raw Convex log stream is configured.
  The new logger emits only the same allowlisted event sent to Sentry.
- Web reporting uses the actual served `diagnostics.js`, local consent and one
  fixed request per page. It sends no page URL, content, cookies or account data.
  A private preview-only test page exercised its synthetic method through a
  visible button. That test page is not part of the repository or production.
- Backend typecheck and all 321 tests passed. The diagnostics cases exercise
  real HTTP ingress, strict payload/body/origin checks, concurrent admission,
  separate web/backend budgets, stale heartbeat, health recovery, monthly
  rollover and one safe request with no retry on a provider 429.
- Android debug/verification builds and 199 units passed. The SDK serialization
  test removes private canaries. The final fatal test used the non-debuggable
  `diagnosticsVerification` variant on the Android 16 `hadithly` emulator.
- The final iOS full suite executed 238 tests,
  with seven pre-existing opt-in skips and zero failures. Focused diagnostics
  tests also passed after the adapter and symbol-build changes. They inspect the actual
  compressed SDK envelope through an intercepted URLSession, and test opt-out
  cache deletion without contacting the vendor. Fatal/restart vendor proof uses
  a standalone Release simulator build with `DIAGNOSTICS_VERIFICATION`, not an
  Xcode-attached process. Temporary DEBUG transport probes were removed.

## Remote evidence

The shared source release is `hadithly@fdf9ebf96361`; environment is
`development`. `LA1_EVIDENCE.json` records only event IDs, safe tags, readable
frame counts and hashes of private vendor exports. It excludes vendor routing
keys, account/project metadata, raw SDK envelopes and credentials.

Run `python3 scripts/audit-diagnostics-evidence.py <private-export-directory>`
against the four actual vendor exports. The checker requires the same release,
fixed exception values, filtered geography, no personal identity/request/extra
data or source variables, readable native frames and source-free Apple symbols.
It fails if a symbolicated stack contains a local `/Users/` path.

Apple's first dSYM exposed a local developer path after symbolication. The
release build now applies Swift debug/file prefix maps and disables serialized
debugging options. The symbol-upload script rejects any dSYM containing a local
user path. The final dSYM UUID is
`543FB4B1-C54C-3D03-9D08-1DFB8EA6A8C0`; raw local-user-path count is zero.
CLI 3.8.0 uploaded it with `--type dsym --no-sources`; vendor readback shows
symbols/debug info present and sources absent. The obsolete UUID
`84F81C47-7B36-39B5-B5D7-37641D5A6227` and initial synthetic issues were deleted
under Alim's explicit cleanup approval. Deletion does not refund quota usage.

Sentry adds geography on the server even when the SDK sends no user. Prevent
IP storage and additional sensitive-field scrubbing are saved on all projects;
new exports show only `[Filtered]` geography. One UI read inadvertently included
an unused Sentry source-fetch security field. Source fetching remains off;
that field is neither an app DSN nor a Hadithly API credential, and is excluded
from committed evidence. Do not activate source fetching with that field.

## Uptime, alerts and cost readback

Exactly four standard Google checks are saved in `hadithlyapp`: website,
canonical fallback, development API and development notification heartbeat.
Each checks HTTPS/200 every five minutes in Singapore, Belgium and Virginia,
with TLS validation, ten-second timeout, fixed content match and failure logging
off. All four regions-by-check status rows read available after test recovery.

Downloaded policy JSON confirms `REDUCE_COUNT_FALSE`, threshold greater than
one, 600-second retest, 1,200-second `ALIGN_NEXT_OLDER`, one owner email channel
and enabled policies. `LA1_UPTIME_EVIDENCE.json` stores that redacted readback.
The notification policy now targets `/health/notifications`, not the test URL.

Google opened one test incident at 12:20 Almaty time. Alim explicitly confirmed
receipt of the test email. `/health/alert-test` was disabled and read back ready;
the temporary policy was converted to the permanent heartbeat alert. Recovery
notifications are enabled. Sentry's development error rule covers only the four
Hadithly projects, not the organization's other projects. New issues,
escalations and regressions notify Alim with a one-hour per-issue cooldown.
The rule was paused during cleanup and restored after fresh proof. The test
preview's origin is no longer admitted; the regular preview origin is restored.
Native consent reads off and the owned caches read absent on both platforms.
The ordinary Android debug APK was restored without deleting user data, and only
the task-created disposable iOS simulator was removed.

Sentry billing reads Developer, 5,000 shared monthly errors and no payment
method; trial ended. No paid additions were activated. Backend admission is
800/month, web 200/month, each one/minute; native is five/day/device. Google
configuration contributes at most 107,136 regional executions per 31-day month,
within its one-million standard-check allowance. Two Convex endpoints contribute
53,568 ordinary HTTP calls/month. No probe invokes a model or push provider.

These are admission/configuration limits, not a global Google/Convex billing
hard stop. Public ingress abuse still consumes rejected HTTP calls; public Sentry
DSN abuse can consume its shared free quota. Convex account-plan, platform-log
retention and hard-limit readback remain a release gate because dashboard login
requested a new GitHub OAuth grant. That grant was cancelled, with no access
expansion. Existing plan/billing settings were not changed. See
`LA1_OPERATIONS.md` for sampling, retention, outage behavior and incident response.

## Remaining release proof

- Production DSNs, production alert environment, release disclosures/effective
  date, store privacy declarations and distributed-device verification need
  separate approval. The privacy changes are a Vercel preview only.
- Android 8–11 C/C++ crash coverage is incomplete with NDK disabled. Android
  12+ converted tombstones and ANRs need device proof; no raw dumps are uploaded.
- Native 429/offline retry timing, cached crash across an app upgrade, restart
  with consent revoked and subsequent re-opt-in need the physical release matrix.
  Local opt-out transport/cache tests and installed cache readback are narrower.
- Verify provider log retention/hard limits and actual account usage before
  production. Uploaded symbols have independent retention from 30-day events.
- Earlier H3/O2/W2/Q2 and all release/store gates remain open. LA2 is not started.
