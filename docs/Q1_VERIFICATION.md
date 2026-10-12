# Q1 rolling generation and cost verification

Date: 2026-10-12. F1 is complete in the plan's 2026-09-07 record. This session
implements Q1 and the owner's related read-cost request. It stops before Q2.

## Result

The local race/property gate passes. New global generation publishes its cache
row and one immutable success event in the same Convex mutation. The former direct
cache writer is deleted; only fenced completion publishes new AI. The initiating
account receives a separately erasable charge. Approved, official, cached,
failed, superseded, and stale results create no new success event or user charge.
A notification service generation uses the same global lock and success event,
with no user charge.

Free allowance is five and Pro allowance is 100 in `(now - seven days, now]`.
Live reservations count at admission. Exact expiry frees the slot. Entitlement
changes preserve history, and a downgrade's retry time waits for enough events
to expire. Admitted work is grandfathered across a downgrade.

Both readers load existing translations in one exact-locale batch. Opening,
paging, changing locale, and purchase retry cannot generate an unrequested page.
Only an explicit hadith action can request new generation. Public cached text is
readable signed out. Only an actual quota rejection offers the paywall. General
Settings retains restore/manage actions and no allowance or paywall shortcut.
Remaining allowance and retry time appear with the requested hadith. Account
and locale changes clear private request state.

Ordinary Gemini uses one structured-output call, no tools, no JSON repair call,
8,192 output tokens maximum, a 40-second timeout, and no SDK retries. Its lease
lasts 120 seconds. Source identity, source permission, and the proof's generation
key are rechecked at publication/admission. A stale worker cannot publish or
charge. A crashed external request can still have incurred upstream cost.

## Local proof

| Check | Result and artifact |
| --- | --- |
| Backend | Final typecheck and 293 tests pass. `/tmp/hadithly-q1-final-backend.log`. |
| Race/property gate | Same-key user/service races, last-slot distinct-key races, public-action provider race, replay, generated schedules, failure/retry, lease takeover, permission/source/proof races, and zero-event real E3-approved cache all pass in `backend/convex/quotas.test.ts`. |
| Platform integrity | Actual signed App Attest fixtures validate and tampered challenge/key/app or development-in-production fail. Challenge expiry, user/locale/source binding, one-use consumption and atomic assertion counters pass. Play decoded-verdict policy rejects wrong hash/package/certificate/device/license/time. |
| Cost | Known token usage settles the reservation; unknown failures retain it. Service exhaustion never becomes user quota. Telemetry has no prompt, source/user text, account, raw proof, response, or provider exception. |
| Counts/migration | Compact progress works after full outlines are deleted. Representative count records are over 100 times smaller. Backfill and old-monthly-field erasure are idempotent and invent no event dates. |
| iOS | App/test build passes. 224 local unit tests pass; two older E2/E3 opt-in live tests are skipped. Three Q1 unit tests pass without skips. `/tmp/hadithly-q1-ios-complete.xcresult`. |
| iOS UI | Four Q1 UI tests pass without skips on iPhone 18 Pro, iOS 27, `40FDE642-C9F1-46C4-83E3-4D2469BDE3A6`. Opening/paging, 44-point explicit action, guest cached rendering, request-only allowance/retry, quota and rate distinction. `/tmp/hadithly-q1-ios-ui-final.xcresult`. |
| Android | JDK 21 build and 195 unit tests pass, zero skips/failures. Three installed Q1 UI tests pass on `hadithly`, Android 16, `emulator-5554`. `/tmp/hadithly-q1-android-complete.log`. |
| Review | Two independent read-only reviewers reproduced permission revocation, stale-source availability, and proof/source race defects. Repairs passed their actual Convex regressions and are retained in the repository suite. Native allowance leakage across locale changes was repaired and tested on iOS. |

The first iOS UI run missed the explicit test authorization environment. The
second exposed a 14-point accessibility target because the frame was outside the
Button label, plus a test querying a merged button as StaticText. The final run
uses the real 44-point label and the correct button identifier. It passes.
The pinned RevenueCat checkout was repaired by reusing the existing verified
source package directory. No package version changed.

## Cost evidence

Official pricing read on 2026-10-12 remains $0.10 per million text input tokens
and $0.40 per million output tokens for Gemini 2.5 Flash-Lite. Search grounding
is $35 per 1,000 grounded prompts beyond the shared 1,500/day paid allowance.
At 2,000 input and 500 output tokens, a new translation costs about $0.0004.
A reusable cached result makes no provider call. [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).

Convex's listed Starter database I/O is $0.22/GB above 1 GB included; egress is
$0.132/GB above 1 GB. Region multipliers can apply. No plan was changed.
[Convex pricing](https://www.convex.dev/pricing).

The prior October 10 dashboard audit attributed September's 1.42 GB cap to
**database I/O**, with only 302.78 MB egress. Progress and outline reads were
about 69% of its displayed database traffic. Q1 replaces progress's large outline
reads with `collectionCounts` and removes seven unused full-outline Library
subscriptions on each platform. This is a proven reduction in read shape, not a
measured post-deployment bill reduction. See `COST_REVIEW.md` for dated readings.
A current dashboard refresh reached a sign-in page, so today's meter was not read.

Other savings are cache-only page reads, global single flight, removal of Search
and the repair call, and removal of the monthly all-user reset scan. Full volume
page-read materialization, 96-bucket notification scanning, CDN delivery of licensed
immutable offline artifacts, and service-plan changes remain separate cost work.

## Server spend and integrity settings

`backend/generation.env.example` documents server-only configuration.

- Default generation budget: $10 per UTC calendar month. Admission reserves
  $0.02 per provider attempt. The serialized source block is capped at 64,000
  UTF-8 bytes; output is capped at 8,192 tokens. Numeric returned token usage
  settles the reservation at the pinned rates. Unknown or abandoned requests
  conservatively retain their reservation. A later stale completion can settle
  its own attempt without publishing or charging.
- Backstops: 500 provider attempts/day, 25,000/month, 60/minute globally, ten
  concurrent global flights, ten attempts/minute/account, two concurrent flights
  per account. The unverified development lane allows five attempts/minute.
- `AI_MONTHLY_BUDGET_USD` and `AI_MONTHLY_ATTEMPT_LIMIT` allow a deliberate launch
  budget adjustment. Clients cannot set them. These are application admission
  controls at the recorded rates, not a provider invoice or billing-account cap.
- Production requires proof. App Attest checks the configured app ID prefix and
  bundle, certificate/nonce/key, environment and assertion signature/counter.
  Play Integrity is decoded by Google's authenticated API and checked for the
  configured package, signing certificate, request hash, freshness, licensed app
  and device integrity. [Apple server validation](https://developer.apple.com/documentation/devicecheck/validating-apps-that-connect-to-your-server),
  [Play standard requests](https://developer.android.com/google/play/integrity/standard).
- Unavailable proof is allowed only if the owner enables `AI_ALLOW_UNATTESTED_DEV`
  on the exact named development URL. Production ignores it. Supplied invalid
  proofs fail even in development. Raw proofs/tokens are never stored.

## Approved development rollout and live proof

The owner authorized the remaining Q1/E2 development work. `convex dev --once`
deployed only to `festive-cobra-664`; the final deployment removed the temporary
internal fixture module. Production was untouched.

| Check | Actual result and artifact |
| --- | --- |
| Migration | Four monthly aggregates erased without inventing event dates; seven compact collection counts materialized. Repetition changed zero rows. Existing account entitlements, Saved, folders, progress and translations preserved. `/tmp/hadithly-q1-live-migrations.log`. |
| Actual count payload | Existing outlines: 965,228 bytes; counts: 1,077 bytes, a 99.89% reduction. This measures read shape, not invoice savings. |
| Real backend/model boundary | Five free new generations, full-allowance cached reuse, sixth rejected, fixture-only entitlement upgrade and retry, and one service generation. Seven unique global success events, six private charges, zero service charges and zero new events for cache/rejection. Numeric estimated token cost $0.000316. `/tmp/hadithly-q1-live-backend3.log`. |
| Authenticated iOS simulator | Actual Clerk/Convex new generation, cached retry, exact-locale cache and allowance delta passed. Fixed omitted optional App Attest key being sent as JSON null. `/tmp/hadithly-q1-live-ios2.xcresult`; strict-policy cached rerun `/tmp/hadithly-q1-live-ios-cached.xcresult`. |
| Physical Apple proof | iPhone 16 Pro produced real Apple attestation and then an assertion. Deployed certificate/nonce/app validation and signature/counter validation admitted two actual generations; consumed-challenge replay rejected; counter readback was one. `/tmp/hadithly-q1-hardware-proof.log`. |
| Android live guest | Actual deployed public exact-locale cache read, missing-locale null and authenticated-action denial passed, one test, zero skips. `/tmp/hadithly-q1-android-guest-live.log`. |
| Aggregate provider/event proof | Ten fresh global generations, ten unique immutable events and ten ungrounded model calls across backend, simulator and hardware runs. Estimated token cost $0.000455. |
| Cleanup | Ten disposable self-authored fixture sources and their cached translations removed; private charge links erased; anonymous global events/cost facts retained. Existing rows preserved. Temporary unverified development flag removed. `/tmp/hadithly-q1-live-cleanup.log`; `/tmp/hadithly-q1-final-deploy.log`. |

The Apple hardware test deliberately uses a trusted development operator fixture
identity. It proves the hardware/server cryptographic round trip; it is not a
physical Clerk login test. The public native production path remains authenticated.
Development Apple attestation is accepted only on the exact named development
origin, independently of the unavailable-proof simulator flag. Production rejects
development attestation, and invalid supplied proofs always fail.

The first entitlement-retry run hit the five-per-minute unverified rate limit.
The continuation after cooldown reused its completed generations and passed.
No provider retry or duplicate charge was introduced.

Final iOS local suite: 225 passed, four opt-in live tests skipped, zero failures
(`/tmp/hadithly-q1-final-ios-unit.xcresult`). Skips are not live evidence: E2,
Q1 simulator and hardware checks above were executed separately under their flags.
Android's final build and 195 unit tests pass (`/tmp/hadithly-language-android.log`).
Installed final reader/language UI proof also passes: four tests on Android
(`/tmp/hadithly-q1-android-final-ui.log`) and six on the physical iPhone
(`/tmp/hadithly-q1-phone-final.xcresult`), all without failures or skips. Physical
Q1 reader cases use the existing explicit fixtures; they do not substitute for
the open authenticated real-generation journey.

## Rerunning the live checks

Live helpers are development operator tools, not mobile endpoints. Obtain fresh
action-time authorization for deployment, paid calls and credentials. From
`backend/`, run `node scripts/rollout-q1.mjs` for bounded migrations and preservation
checks. For disposable model proof, temporarily copy
`scripts/fixtures/q1LiveVerification.ts` into `convex/q1LiveVerification.ts` and
deploy to the named development environment. Then use
`node scripts/verify-q1-live.mjs prepare <private-metadata-path>`, `verify`, and
`cleanup`. Reuse an active metadata path to resume; use a fresh path after cleanup.
The completed backend checkpoint makes no further provider calls on replay.
Remove the fixture module and redeploy after cleanup, including after a failed run.

`verify-q1-device.mjs` drives opt-in physical hardware XCTest using private
challenge/proof files. Set `Q1_IOS_DEVICE_ID` and `Q1_SWIFT_PACKAGES` to the
connected phone and verified package directory; build the physical Hadithly test
scheme into `/tmp/hadithly-q1-device` before its `test-without-building` run.
`private-convex-run.mjs` keeps raw proof out of operating-system
process arguments. Raw artifacts are erased by the controller. Native live tests
accept an existing development login or a separately authorized short-lived sign-in
ticket file; consume and delete ticket files, never log them.

## Remaining gates

Play Console remains explicitly deferred by the owner, so real Google decode and
native Play Integrity proof cannot pass yet. Authenticated Android generation and
the physical iPhone Clerk-to-generation journey remain open: the emulator's cached
login was removed by Gradle's connected-test cleanup and the phone has no test
session. The owner authorized two ten-minute sign-in tickets, but none was created:
the Clerk CLI has no admin session, and neither workspace nor development Convex
has a usable development admin key. No authentication was bypassed. Guest reader
and language checks require no account and proceeded.

Q1's implementation, local race/property gate, development deployment/migration,
backend live quotas and Apple hardware gate pass. Its complete cross-platform
integrity/authenticated-device gate is not declared passed. Production, prior E1,
widget, sync, rights and release gates stay open. Q2 has not started.
