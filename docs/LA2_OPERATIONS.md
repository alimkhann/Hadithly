# Reviewing Hadithly analytics

The dashboard counts outcomes, not people. Each record sent to PostHog represents
many native counts. Never use PostHog's default event count or unique-ID chart as
an active-reader metric. The counter property is the measure to sum.

## Five minutes each day

1. Check `analytics:health` on the authorized development/production Convex
   deployment. Collection enabled, last export, failed exports and admitted
   daily/monthly totals explain whether the dashboard is current. Stop exporting
   with `ANALYTICS_ENABLED=0` if payload, privacy or spend behavior is wrong.
2. Inspect signed-out opens and restoration first. A reproducible incorrect
   landing is actionable even when there is too little data for a percentage.
3. Inspect offer availability, pending payments, confirmed access and restore.
   Check [RevenueCat](https://app.revenuecat.com/) for receipts/revenue; analytics never receives transaction IDs.
4. Compare onboarding progress and first-reading outcomes. Account outcomes do not mean distinct users; hosted completion may be unknown. Demonstration taps can repeat.
5. Choose one investigation. Record the question, counts, likely cause and next
   check. A ten-percentage-point decrease with at least 100 opportunities in each
   period merits investigation; it does not establish causation.

For the verified development deployment, run this read-only check from `backend/`:

```sh
npx convex run analytics:health '{}' --deployment festive-cobra-664
```

Collection is currently off after verification. Check the reported export time
before interpreting the dashboard.

## Reading the panels

| Panel | Numerator / denominator | What to do |
| --- | --- | --- |
| First experience | Ordered completed / ordered started; ordered first reader / ordered started | Same local start-hour cohort, thirty-minute uninterrupted window. Demo/auth interactions and account-outcome totals are separate descriptive counts. |
| Reading reliability | Guest/account rendered opens / corresponding started opens; exact restore / restore started | Test both native platforms and the failed entry route. |
| Offline and notifications | Verified activation/update / admitted download; exact routing / notification open started | Check checksum/atomic activation or target landing. Not notification click-through. |
| Translation demand | Cache/generated/quota/failure / explicit requests started | Inspect coverage and quota behavior, not reading volume. |
| Purchase journey | Backend-confirmed Pro / store purchase starts; offer available / paywall shown | Check store availability, cancellation, pending and backend settlement. Not revenue. |
| Measurement health | Latest reported admission/export counters and reported hour | Compare with current Convex health before trusting rates. Staleness is not zero failures or zero usage. |

Periods are the latest seven **settled UTC days** and the preceding seven,
separated by platform. A day closes after a 24-hour arrival window. This means
today and yesterday are not final. Below 20 opportunities display "Too little
data to judge" in the operator's interpretation. The v1 panels show totals and defined opportunity denominators. Percentages are
blank below 20 opportunities and labelled "Too little data to judge". First-reading linkage is local, 30 minutes
and lost on process death. Long-term retention and install-to-purchase attribution
are intentionally unavailable.

Native forty-fact caps, a bounded three-batch queue, summary expiry, opt-out,
under-threshold suppression, cancellation and process death reduce coverage.
The fixed clipping marker reports cap episodes within a UTC day; it is not a
percentage of the full audience. The native cap reserves 39 product facts plus one
marker within 40 total. Exact discarded-fact counts remain in the local `clipped`
value for verification. Rejected HTTP bodies are never logged
or stored as a raw rejection sample. Keep that distinction when investigating
missing data. Backend budget health is not a whole-account Convex billing cap.

## Safe setup and provider check

`node scripts/create-analytics-dashboard.mjs` prints a reviewable six-panel
definition. `--apply` changes the named dashboard and executes each query only
after owner approval. It reads project ID and a scoped personal API credential
from local environment, never arguments or committed files. Do not print keys.
Use a private EU project. Dashboard setup is idempotent by the LA2 names and must
preserve unrelated dashboards. Pagination is bounded and follows only same-project EU URLs. `--production` is a separate approved action.

Confirm directly in the vendor UI:

- Free plan, no payment card, no paid auto-upgrade, product analytics allowance.
- EU hosting, no person profiles, replay, surveys, marketing integrations or
  automatic error reporting; disable GeoIP and discard stored IP data.
- Schema-version 1, exact approved property list and aggregate distinct IDs.
- Native iOS and Android journeys visible, with counts matching private local
  transport evidence. A configured dashboard or mock does not close this gate.

Server `ANALYTICS_POSTHOG_KEY` is the capture credential. A dashboard personal
credential never enters Convex or a mobile build. `ANALYTICS_ENABLED` defaults to
off. Deployment and environment changes require action-time approval. The approved development setup created a project-scoped dashboard credential
and a server-only capture credential. Neither enters git or mobile bundles.

## Retention, deletion and incident response

Turn off the device control to stop collection and cancel pending work. Account
deletion does the same before deleting the identity. Sign-out clears pending
counts without linking the old or next account. Already delivered totals have no
account binding and cannot be selectively deleted by account. Explain this
honestly instead of promising "delete person" behavior the architecture cannot
support. Vendor retention is longer than Convex's ninety-day aggregate retention.

Receipts stop being eligible at 24 hours; hourly cleanup drains all eligible rows
in bounded scheduled batches. Expired data cannot replay while awaiting cleanup.
Small buckets expire after seven days. An outage has three attempts, backoff and
an unchanged export UUID. Monthly provider reservations include retries. Stop
collection/export on cap exhaustion; never enable a paid upgrade to cover it.

## Verified development dashboard

Open [Hadithly launch health](https://eu.posthog.com/project/304602/dashboard/1020618).
The dedicated organization is **Hadithly private analytics**. The free plan has
no card; its UI displayed one-year retention. The project discards IP data.
There are six full-width panels, with measurement freshness first. Development
rows are labelled **Unsettled development verification**. They include synthetic
native fixtures; purchase rows are not real receipts or conversion evidence.
Production definitions compare the latest seven settled UTC days with the prior
seven. Source: `LA2_DASHBOARD.json`; rerun `node scripts/audit-la2.mjs` locally.

After the approved one-time provider proof, `ANALYTICS_ENABLED=0` in development
and `ANALYTICS_VERIFY_CURRENT_DAY` was removed. The dashboard remains reviewable.
No production credential or activation was installed. Re-enabling development
collection/deployment is an action-time approved operation, and current-day
fixture buckets already exported are immutable. `--live` audit needs only the
locally supplied scoped API credential; it performs readback and exact frozen
count comparison, not activation.

Measurement health combines monthly rejected/admitted/exported counters,
suppression at the last reported hour, clipping markers and provider failures.
`analytics:health` also exposes pending buckets, lag, warnings at 80% of daily,
monthly and export budgets, and cap exhaustion. Rejected content is never retained
as a sample. A malicious caller can inflate a bounded rejection counter; it is
service health, not user behavior. If exports are disabled/stale, check Convex
rather than reading an old zero as a clean current bill.

Large-text onboarding → cancelled authentication → guest reading also passed on
both installed platforms: iOS accessibility-XXXL content size and Android font
scale 1.6. Temporary scale changes were restored. This does not close physical
VoiceOver/TalkBack, Urdu or Reduced Motion gates. Fixed recoverable operation
counts appear with their corresponding product panel; a descriptive count has
no conversion denominator.

Offer availability flags and intermediate purchase statuses can overlap after
recovery; they are not a partition that must sum to 100%. Selection taps and fixed
error/recovery counts are descriptive. A rate above its opportunity denominator
is withheld and labelled for measurement investigation. Same-operation recovery
means a subsequent success within 30 minutes, without content/account attribution.
