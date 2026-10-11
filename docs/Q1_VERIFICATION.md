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
| Backend | Typecheck and 292 tests pass. `/tmp/hadithly-q1-complete-proof.log`. |
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

## Open action boundaries

No `convex dev --once`, live migration, env edit, credential/IAM/billing change,
production deployment, or paid live Gemini request ran in Q1. `convex codegen`
refreshed local bindings; it does not activate the deployment. The new native
builds need the Q1 backend rollout to load their new batch query.

The reviewable next step is development deployment to `festive-cobra-664`, bounded
`migrateQ1Users` pages, and `materializeQ1CollectionCounts`. The old monthly aggregate
cannot recover historical event dates, so rollout erases it without synthesizing
charges. Existing Saved, progress, subscriptions and cached translations remain.
A simulator generation check additionally needs the explicitly unverified dev
lane or actual device attestation. Neither is enabled here.

Still open: real physical App Attest round trip, configured Play Integrity decode
and native round trip, and a bounded real native generation/cache/quota retry
check after the approved development rollout. Production remains the release
track. Prior E1, device, widget, sync, rights and release gates remain open.
Do not start Q2.
