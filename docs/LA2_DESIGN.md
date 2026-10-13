# LA2 design

Owner-approved scope: minimal analytics plus four native onboarding screens and
quota-only paywall polish. Author model: GPT-6.1 Sol High. LA1 passed its development
gate on October 13; earlier release/store/device gates remain open. Stop before LA3.

## Privacy contract

Ten families in `analytics-catalog.json` answer activation, signed-out reading,
restoration, offline activation, notification routing, translation demand, quota,
purchase and recoverable-error questions. Every variant is a literal. No caller
can add properties. `generate-analytics-catalog.py --check` proves platform parity.
This is not a per-user behavioral analytics system. No locale, content identity,
text, search, note, evidence, account, purchase or device identifier is admitted.

Local reducers coalesce typed facts, with a forty-fact UTC-day cap (39 product facts plus one reserved clipping marker), a three-summary
FIFO, 32 entries and 4 KiB per summary. They freeze the old day's counters at UTC
midnight. Each summary records only an hour-rounded creation hour and a random v4
batch UUID. It expires within 24 hours, including during retry backoff. A UUID is
used for one summary's at-most-three attempts and never exported. No stable
installation or journey identifier exists. In-memory first-reading completion is
bounded to thirty minutes after onboarding and does not survive process death.

The HTTP ingress rejects credentials/cookies/browser origins, unknown fields,
unknown versions/metrics, fractions, oversized counts and expired or future hours.
It reconstructs the typed summary. One transaction admits, deduplicates, sums the
counters into a day/platform bucket, and writes a UUID-only expiry receipt. It does
not retain an individual summary or mapping to a bucket. Request bodies are never
logged by application code. Platform security/request-log retention still belongs
to the existing release gate.

Buckets need ten accepted summaries before export. Ten summaries do not mean ten
people. Export waits until the day ends plus a 24-hour late-arrival window, so the
bucket is immutable when exported. Provider events use day/platform/environment
aggregate identifiers, never reader identifiers. Charts sum `count`; envelope
counts and distinct IDs are not people, sessions or active users.

PostHog Node is the sole analytics vendor SDK. Profiles, GeoIP, local flag
evaluation, exception autocapture and compression are disabled. Its final HTTP
adapter reconstructs a fixed JSON body after SDK serialization. Only one actual
network request is allowed per claimed export, including SDK shutdown after a
failed flush. Stable per-variant export UUIDs make transport replay idempotent.
The exporter fences stale lease completions and allows three claims at most.
Outbound events also carry a fixed operational snapshot: measurement month,
admitted/exported monthly totals, failed exports, bounded rejected-summary totals,
suppressed buckets and an hour-rounded observation hour. These are server-owned service totals, never per-device measurements. The health panel uses monthly maxima and the last reported suppression snapshot;
clipping markers are summed. None of these numbers represents distinct people.

## Retention and operations

- Unsent device summaries and batch receipts: at most 24 hours eligibility;
  physical server cleanup has an hourly cadence and drains bursts in bounded
  follow-up batches. No expired summary can replay during that interval.
- Unpublished small buckets: seven days; exported anonymous totals: ninety days
  in Convex. PostHog has independent, longer retention. It receives only totals.
- Admission: 2,000 summaries/day and 50,000/month. Provider budget: 10,000 admitted
  event envelopes/month, including reservations for retry attempts. Warn at 80%.
- Three-second requests, bounded retries and explicit `ANALYTICS_ENABLED` kill
  switch. Collection/export is disabled on the server unless explicitly enabled.
- Free PostHog EU project, no payment card, no other PostHog products or marketing
  integrations. Cloud provisioning, credentials and deployment require the
  owner's separate action-time approval.

Opt-out and deletion stop/cancel work, erase local queues and prevent stale
completion callbacks. Sign-out erases queued measurement without changing the
device's privacy preference. Sign-in creates no analytics identity. Already
accepted totals cannot be selectively subtracted by account because no such
mapping exists. This is an intentional privacy boundary, not account-linked
deletion. Requests already delivered can finish.

The owner chose disclosure and a Settings opt-out, with no controls on welcome.
Privacy policy text is not blanket consent. A jurisdiction-specific consent basis,
effective policy publication and store disclosure remain release work. This
session must not silently activate production analytics.

## Product behavior

Welcome -> language -> card-free prepared example -> account choice. Create
account is primary, Sign in secondary, guest clearly accessible. Device language
seeding happens only before first preference persistence; explicit or synced
choices win. The OS controls System appearance. Eight existing locales are in
scope. No survey or automatic permission request. Interrupted onboarding resumes.

The prepared example is original illustrative text dedicated as CC0 1.0, clearly
labeled as not a hadith. Its eight translations have no canonical religious
identity and require no provider/generation request. Arabic selection reveals
source information. The approved book artwork is decorative AI-generated art
with blank pages. It is bundled on both platforms. Native fonts, themes, larger
text, RTL and reduced motion govern the actual implementation.

The quota sheet retains RevenueCat/Q2 ownership and entitlement semantics. Store
prices and real monthly/annual packages populate selectable rows. Monthly is the
default. One purchase button, visible Close, free-reading exit and restore remain
available. Cancellation, pending payment, purchased-but-syncing and backend
confirmed access differ. Only confirmed backend access unlocks the rejected
request. Store lifecycle receipts remain Q2's open gate.

Reader success is emitted only after native visible-list landing acknowledgement.
Exact target measurement compares the original semantic anchor and the first
post-landing frame within eight iOS points or eight Android dp. Zero-offset
chapter openings measure the actual chapter landing container. The initial
verdict freezes once; subsequent manual navigation cannot turn a fallback into
an exact result. No target/offset is passed to analytics. Closing a still-loading
reader is abandonment, not a provider error. Actual failures and subsequent
visible recovery are separate fixed facts. A usable visible text layer is
required for reading success; a reference or sign-in notice alone is not success.
Offline success follows verified atomic activation, not completed byte transfer.

## Small reader stories

| Reader intention | Native flow | Measurement meaning |
| --- | --- | --- |
| Try without an account | Welcome → suggested language → optional prepared example → guest → visible reading | Ordered thirty-minute completion and guest open outcome |
| Keep a place across devices | Choose Create account or Sign in; cancel returns to guest choice | Chosen entry mode and fixed authentication friction, without an account binding |
| Resume interrupted setup | Restart at the saved screen; existing users stay in the app | No fabricated earlier ordered stages after process death |
| Read a cached collection offline | Open existing verified content; no generation request | Usable visible offline open, not just screen creation |
| Resume or follow a notification | Apply original semantic target and acknowledge native landing | Initial anchor/offset verdict only; manual scrolling cannot manufacture success |
| Ask for a new translation | Explicit request; cache, generation, sign-in, failure or backend quota | One request/result pair; no content or language properties |
| Consider Pro after quota | Native sheet → real offer → one store action → backend-confirmed access | Ordered thirty-minute quota offer flow; pending/cancel/syncing are separate |
| Recover after a failure | Retry an actual fixed operation and return to visible usable content | Fixed failure/recovery; closing a loading reader is abandonment |
| Withdraw statistics | Settings opt-out or account deletion cancels uploads and clears queues | No identity merge; already accepted anonymous totals cannot be individually subtracted |

## Known measurement limits

Ordered onboarding progress is admitted only after the preceding stage. Its
start-hour cohort stays unchanged across UTC midnight. Repeated views do not
advance it. It expires after thirty minutes and ends on process death or opt-out.
Only these ordered variants can form an onboarding funnel; calendar-window view
and completion totals cannot. Resumed partial onboarding still has entry outcomes
but does not fabricate an earlier welcome stage.
The four screen-view signals are reducer inputs, not additional uploaded view
counts. This avoids spending the forty-fact budget twice on every onboarding
stage. Demo interaction and account entry outcomes remain separate fixed counts.

These are clipped counts and short flow outcomes, not unique readers. Offline
loss, opt-out, small-bucket suppression, process death and caps affect coverage.
View counts and entry-route totals are not acquisition, lifetime conversion or
retention. Notification click-through cannot be inferred without a delivery
denominator. RevenueCat remains the financial source of truth. Native-speaker
approval of scoped text remains part of release localization work.

A cap episode emits one fixed `recoverable_error.measurement_clipped` marker from
the reserved fortieth slot. It reports clipping episodes within the measured UTC
day, not the number of people or every discarded fact. The local `clipped` value
retains the exact rejection count only for deterministic verification. No extra
counter bypasses the forty-fact limit.

Ordered paywall shown/available/purchase-started/confirmed stages share their
original local hour and expire after thirty minutes, process death or opt-out.
They ignore repeated/out-of-order callbacks. SDK purchase/restore attempts remain
separate descriptive outcomes. A current-day verification exception is internal,
flag-gated and restricted to the exact development deployment; normal cron and
production never use it. Exported verification buckets reject further admissions.

Account completion is based on Clerk's completed SignUp/SignIn resource, rather
than the initial button or an inferred account age. Hosted completion without
that resource distinction reports `account_unknown`. No account identity enters
the measurement contract. Failed completion returns to account choice with guest
entry available, and fixed authentication failure signals never include an error
message. Unknown hosted outcomes are excluded from new-versus-existing claims.

Fixed error pairs track the next successful outcome of the same operation kind
within thirty minutes. They intentionally cannot establish that the content or
account target was identical. Describe them as subsequent same-operation success,
not content-specific retry conversion. They are in-memory, expire, clear on
opt-out/sign-out, and do not include a target or identifier. Clipping invalidates
ordered flow state so a later UTC-day reset cannot fabricate a missing stage.

The paywall observes delayed backend-confirmed Pro only after a purchase/restore
attempt and within the same Q2 operation revision. A once-only completion fence
prevents the direct callback and state observer from retrying twice. An annual-only
offer requires explicit selection; it is never silently preselected. A recovered
offer outage can record both unavailable and subsequently available once.
