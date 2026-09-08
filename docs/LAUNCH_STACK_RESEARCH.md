# Hadithly low-cost launch stack

Research date: 2026-09-02

This document recommends a small launch stack for Hadithly's native iOS and Android apps. It is a decision aid, not a dashboard-state record: prices, quotas, store rules, and provider terms must be rechecked in their dashboards immediately before purchase or submission.

The governing constraint is that Hadithly is a quiet, private reader. Reading behavior can reveal religious interests, so product telemetry must be intentionally less detailed than the providers allow. The objective is enough visibility to operate a reliable app without constructing a behavioral profile of a reader.

## Recommended launch stack

| Area | Launch choice | Cost boundary | Revisit when |
| --- | --- | --- | --- |
| Landing, legal, and link fallback | Static site on Cloudflare Pages; a narrowly scoped Pages Function or Worker only for dynamic link routing | Pages Free; Workers Free allows 100,000 requests/day and 10 ms CPU per invocation | The fallback needs server rendering, authenticated state, or exceeds the free Worker limits |
| Full web reader | Do not build for launch | None | Canonical links are used, licensing is recorded, and real demand for desktop reading is demonstrated |
| Future dump/CDN storage | Cloudflare R2 for immutable, versioned, licensed artifacts, authorized by Convex | 10 GB-month, 1 million Class A operations, and 10 million Class B operations free; no internet egress charge | Storage or operation volume exceeds the free allowance |
| Native crash reporting | Firebase Crashlytics, separately consented, with content and identity scrubbed | No-cost Firebase product | Crashlytics cannot provide enough diagnostic context after a real incident |
| Native product analytics | TelemetryDeck with a small event allowlist and paid auto-upgrade disabled | New accounts receive 50,000 events/month and stop at the limit | The team needs cohort/funnel analysis that cannot be answered with aggregate, anonymous events |
| Richer analytics alternative | PostHog Cloud EU, with autocapture, replay, and person profiles disabled | 1 million product analytics events/month free | Only choose this instead of TelemetryDeck, not alongside it |
| Website analytics | Cloudflare Web Analytics | Free | Never add advertising pixels merely to get more metrics |
| Authentication email | Clerk | Already part of the authentication service | Clerk's deliverability or template constraints become material |
| Support email | `support@hadithly.app` through Cloudflare Email Routing to an existing mailbox | Free inbound forwarding | A real support volume requires ticket assignment or service-level tracking |
| Transactional app email | Resend, only for messages Clerk and the stores cannot send | 3,000 messages/month and 100/day free | Either free limit is approached for two consecutive months |
| Uptime and public status | Better Stack free tier | 10 monitors/heartbeats, one status page; free checks run every three minutes | More monitors, faster checks, or on-call escalation becomes necessary |
| Backend and scheduled work | Convex remains the API and control plane | Starter usage is metered; enable hard usage limits before launch | Pay for Professional before meaningful synced user data if daily managed backups and production observability justify $25/developer/month |
| AI translation | Gemini 2.5 Flash-Lite behind Convex, with cached reuse and server-side budgets | Approximately $0.10/million input tokens and $0.40/million output tokens at the researched rate | Quality tests require a different model or the monthly budget is threatened |
| Subscription state | RevenueCat | Free through $2,500 in monthly tracked revenue, then 1% of tracked revenue in months above the threshold | Revenue or product count makes direct store management economically preferable |

Do not install Sentry, PostHog, and Crashlytics together. Each additional SDK expands privacy disclosures, binary size, maintenance, and incident surface. The launch default should be Crashlytics plus one restrained analytics provider.

## Landing page and exact-link fallback

Create a new minimal static web surface rather than restoring the legacy web application. Its launch responsibility is trust and routing, not feature parity. The first version needs only:

- a quiet home page with one value proposition, store badges when available, and no waitlist gate;
- privacy, terms, support, account-deletion, and content/licensing methodology pages;
- the stable canonical route `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}` with optional, validated query or fragment state for translation and exact position;
- an exact-link fallback page that shows safe, source-attributed public metadata and offers Open in app / Get the app actions;
- appropriate Open Graph metadata without including private reading state; and
- a small `/.well-known/` surface for iOS Universal Links and Android App Links.

[Cloudflare Pages limits](https://developers.cloudflare.com/pages/platform/limits/) give the free plan 500 builds per month, 100 custom domains per project, 20,000 files, and a 25 MiB maximum per asset. Pages Functions are billed as Workers. The [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/) page lists 100,000 requests/day and 10 ms CPU on Free; the Paid plan starts at $5/month, includes 10 million requests, then charges $0.30/million. Static asset requests are free and unlimited unless billed through a Worker feature such as Cache API use.

Keep the launch site static wherever possible. Do not put a Worker in front of every asset, and do not make the canonical fallback call Gemini. A public fallback must remain useful during an AI, authentication, or app-store outage.

### Optional read-only web reader

A complete signed-in web app would duplicate native account, sync, offline, purchase, accessibility, and security work. It should not be a launch dependency. If demand is demonstrated, the first web reader should be read-only and use the same canonical identifiers, attribution rules, authenticity language, and localized metadata as the apps. It should omit AI generation, contributions, personal saves, and subscription management until those surfaces have a justified web threat model.

Large immutable collection dumps deserve a separate delivery path. [Cloudflare R2 pricing](https://developers.cloudflare.com/r2/pricing/) includes 10 GB-month storage, 1 million Class A operations, and 10 million Class B operations per month at no cost; internet egress is free. Above that, standard storage is $0.015/GB-month, Class A is $4.50/million, and Class B is $0.36/million. Use content-addressed filenames, signed manifests, checksums, versions, long immutable cache headers, and an atomic manifest switch.

The master plan records the narrow architecture exception: Convex remains the authority and API/control plane, while a client may download an immutable, checksummed, licensed content artifact from a CDN URL issued by Convex. Otherwise, serving all offline dumps through Convex can make bulk content delivery the dominant bill. The [Convex pricing page](https://www.convex.dev/pricing) lists Starter egress after the included 1 GB at $0.132/GB, and [Convex limits](https://docs.convex.dev/production/state/limits) note a 1.3x rate in the EU region. As an illustration, not a forecast, 100,000 readers downloading 20 MB/month is about 2 TB and roughly $264/month at the base rate before the regional factor.

[Cloudflare Web Analytics](https://developers.cloudflare.com/web-analytics/about/) is sufficient for the public site. Cloudflare describes it as free and privacy-first, without using visitors' personal data. Do not add Meta, Google Ads, or similar marketing pixels at launch.

## Crash reporting and privacy-conscious analytics

### Crash reporting

Use Firebase Crashlytics because Firebase is already required for messaging. Firebase lists [Crashlytics as a no-cost product](https://firebase.google.com/pricing), and its [product page](https://firebase.google.com/products/crashlytics) supports Android and Apple platforms. Both [Apple](https://firebase.google.com/docs/crashlytics/ios/customize-crash-reports) and [Android](https://firebase.google.com/docs/crashlytics/android/customize-crash-reports) SDKs support controlling automatic collection.

Add independent Settings switches for “Send crash reports” and “Share anonymous usage.” Do not make one consent authorize the other. Store the choice locally before initializing collection, and document the precise behavior in Privacy. If the product later makes crash collection on by default, it needs a legal review and plain disclosure; opt-in is the safer launch default.

Crash reports and custom keys must never contain:

- names, email addresses, Clerk IDs, RevenueCat App User IDs, Firebase installation or push tokens;
- Arabic or translated hadith text, search text, notes, saves, evidence, proposal text, or file names;
- canonical hadith, chapter, collection, or language identifiers that could reconstruct an individual's reading history; or
- full URLs when their path or query contains a content or account identifier.

Allow only build, operating-system, device-class, screen name, anonymous session crash ID, network-state category, and coarse operation result. Disable Analytics breadcrumbs. Verify symbol and mapping uploads, then perform and delete a forced-crash build on physical iOS and Android devices before release.

Sentry is a later alternative, not an additional launch SDK. Its [pricing](https://sentry.io/pricing/) lists a one-user Developer tier with 5,000 errors, 5 GB logs, 5 million spans, 50 replays, and one uptime or cron monitor; Team starts at $26/month and Business at $80/month. If adopted later, turn off replay, screenshots, PII, and body capture first.

### Product analytics

TelemetryDeck is the preferred launch option because it has official [Swift and Android integration guidance](https://telemetrydeck.com/docs/) and a small free allowance that hard-stops instead of silently creating overage. Its [July 2026 pricing change](https://telemetrydeck.com/blog/pricing-update-2026/) gives new accounts 50,000 events/month. Disable paid auto-upgrade.

TelemetryDeck is not “no data.” Its [privacy FAQ](https://telemetrydeck.com/docs/guides/privacy-faq/) says it processes events, an anonymized per-install identifier, hour-rounded timestamps, and device metadata; it does not store IP addresses or use cookies. It also describes long retention for cold events, with no guaranteed individual-event deletion and analytics retained after account closure. That retention must appear in the vendor assessment and privacy policy.

Use a random installation identifier that is never joined to Clerk, RevenueCat, Firebase Messaging, email, or crash identity. Regenerate it when a user opts out. Allow only these launch events and properties:

| Event | Allowed properties |
| --- | --- |
| `onboarding_completed` | app version only; do not send the selected language |
| `reader_opened` | entry point and offline/online boolean |
| `position_restore_result` | success or a fixed fallback-reason enum |
| `offline_download_result` | result and coarse size bucket |
| `translation_result` | approved, cache, generated, quota, or failure; never text |
| `paywall_shown` | fixed reason, which must be quota |
| `purchase_result` | store, period, and result; never amount or identity |
| `account_sync_result` | fixed result enum |
| `notification_opened` | whether exact routing succeeded; no content identifier |

Do not collect searches, reading duration by content, collection or hadith identifiers, notes, saves, language selection, evidence/contribution activity, precise location, or any free-form property.

PostHog is a valid alternative when aggregate funnels become operationally necessary. Its [official pricing page](https://posthog.com/) lists 1 million product analytics events/month free and then $0.00005/event, with EU hosting in Frankfurt. Official [iOS](https://github.com/PostHog/posthog-ios) and [Android](https://github.com/PostHog/posthog-android) SDKs are available. If chosen, use the EU region and disable autocapture, session replay, person profiles, and all content-bearing properties. Do not run PostHog and TelemetryDeck in parallel.

## Email and support

Keep authentication messages in Clerk. Route `support@hadithly.app` to an existing mailbox using [Cloudflare Email Routing](https://developers.cloudflare.com/email-service/get-started/route-emails/), which is free inbound forwarding when Cloudflare manages the domain's DNS. This is adequate while one person owns support.

Use Resend only for a transactional message that Clerk, RevenueCat, Apple, or Google cannot send. [Resend pricing](https://resend.com/pricing) provides 3,000 messages/month and 100/day on Free; Pro is $20/month for 50,000 messages, with $0.90 per additional 1,000. Configure a dedicated subdomain such as `updates.hadithly.app`. Resend requires [SPF and DKIM](https://resend.com/docs/dashboard/domains/introduction); add [DMARC](https://resend.com/docs/dashboard/domains/dmarc) in monitoring mode and tighten it only after observing legitimate traffic.

At launch:

- send no daily-hadith email and no newsletter by default;
- give support a documented response template, escalation rule, and deletion-request workflow;
- do not email reading history, saved items, translated text, or evidence attachments;
- use expiring dashboard links rather than sensitive message bodies where practical; and
- if a waitlist or newsletter is later added, use double opt-in, record consent time/source, provide one-click unsubscribe, and keep its suppression list separate from auth and service mail.

Resend supports [inbound webhooks](https://resend.com/docs/dashboard/receiving/introduction) and [threaded replies](https://resend.com/docs/dashboard/receiving/reply-to-emails), but those are not needed until forwarding becomes operationally inadequate.

## Uptime and public status

Better Stack's [pricing](https://betterstack.com/pricing) and [uptime product](https://betterstack.com/uptime) list 10 monitors or heartbeats and one status page on Free. [Free checks run every three minutes](https://betterstack.com/docs/uptime/check-frequency/), which is sufficient for a small launch.

Monitor only inexpensive public probes:

1. `https://hadithly.app/`
2. one canonical hadith fallback URL
3. a shallow Convex-backed `/health/public` endpoint
4. the daily-notification scheduler heartbeat

The health response may expose a deployment/version identifier and coarse dependency state. It must not expose provider secrets, user counts, database details, or make a live Gemini request. A synthetic health probe must never generate a translation or notification.

Publish `status.hadithly.app` with Website, Reading API, Sign-in, Notifications, and Translation components. Third-party-provider incidents may be updated manually. Use email and app push alerts, not paid phone or SMS escalation. Define an incident template with start time, affected function, mitigation, user impact, and resolution; never include a user's data in it.

## Cost controls and scaling risks

### Provider facts

- [Convex pricing](https://www.convex.dev/pricing) lists Starter allowances of 1 million function calls, 0.5 GB database storage, 1 GB file storage, and 1 GB egress, followed by $2.20/million calls, $0.22/GB database storage, $0.033/GB file storage, and $0.132/GB egress. Professional starts at $25/developer/month and includes daily backups, exception reporting/log streaming, and 50 GB egress. Set [warning and hard usage limits](https://docs.convex.dev/production/usage-limits) before launch. Free and Starter allow [manual backups](https://docs.convex.dev/database/backup-restore), up to two retained for seven days; scheduled backups require Professional.
- [Clerk pricing](https://clerk.com/pricing) gives Hobby up to 50,000 monthly retained users per app. Pro starts at $20/month billed annually and charges $0.02 per retained user above 50,000. Because reading works signed out, never force or silently create an account; ask only when a person wants sync.
- [RevenueCat pricing](https://www.revenuecat.com/pricing/) is free through $2,500 monthly tracked revenue, then charges 1% of tracked revenue in months above that threshold.
- [Gemini API pricing](https://ai.google.dev/gemini-api/docs/pricing) lists Gemini 2.5 Flash-Lite at $0.10/million input tokens and $0.40/million output tokens. Search grounding is far more expensive after its free allowance: $35 per 1,000 grounded prompts. Do not use grounding for ordinary translation generation.
- [Apple Developer Program membership](https://developer.apple.com/programs/whats-included/) costs $99/year. Eligible developers can apply for the [Small Business Program](https://developer.apple.com/app-store/small-business-program/) for a 15% commission. Google's [developer-account registration fee](https://support.google.com/googleplay/android-developer/answer/14659200) is a one-time $25, and [automatically renewing subscriptions](https://support.google.com/googleplay/android-developer/answer/112622) generally carry a 15% service fee, subject to regional and program rules.

### Translation economics

At the researched Flash-Lite rates, an illustrative request with 1,500 input tokens and 500 output tokens costs about $0.00035. A subscriber using 100 translations every rolling week can make about 433 translations in an average month, or roughly $0.15 in raw model cost. At a $2.99 monthly price, a 15% store fee plus RevenueCat's 1% after its threshold leaves about $2.51 before tax, refunds, support, backend, and currency effects. This suggests the quota can work, but only while token limits, cache reuse, and model pricing remain true.

The free cohort is the larger exposure. Fifty thousand readers each using five translations per week would request 250,000 generations/week, about $87.50/week under that illustration, before cache reuse. Grounding all of them after the free allowance would be economically unacceptable. Enforce:

- a stable model ID and explicit maximum input/output tokens;
- per-install and per-account rolling quota rules that cannot be doubled by signing in or reinstalling without abuse controls;
- normalized cache keys over source text, source language, target language, policy version, and model version;
- a global daily and monthly generation budget with warning and hard-stop thresholds;
- request concurrency limits and an emergency kill switch; and
- provider-failure language that does not silently spend through retries.

Google Cloud documents preview [spend-cap budgets](https://docs.cloud.google.com/billing/docs/how-to/budgets-spend-caps) that can pause eligible services at 100%, plus [service quota controls](https://docs.cloud.google.com/docs/quotas/view-manage). Use them as a second boundary, not a replacement for application-level limits.

### Other risks and gates

| Risk | Launch control | Upgrade trigger |
| --- | --- | --- |
| Offline-dump egress | Small manifest, delta-aware versioning, checksums, Wi-Fi preference, delete stale downloads; decide CDN exception before scaling | Projected content egress exceeds the cost of R2/CDN delivery and its operational overhead |
| Clerk retained-user charges | Signed-out reading, no automatic account, account prompt only for sync | Monthly retained users approach 40,000; model conversion and churn before 50,000 |
| Evidence storage | File-type allowlist, 30 MB/submission maximum, per-user/week cap, quarantine, malware scan, thumbnail/OCR limits, retention schedule | Stored evidence or scan workload crosses a documented monthly budget |
| Notification fan-out | Preselect/cached daily content, batch work, retry cap, dead-letter audit | A run approaches the Convex function or bandwidth alert |
| Observability | Curated event allowlist, no replay, no dual vendors, free-tier hard stop | A named operational question cannot be answered safely |
| Backups | Before real accounts, exercise export/restore; choose Convex Professional or a disciplined encrypted off-device manual-backup runbook | First meaningful synced personal data or launch, whichever comes first |
| Email abuse | Provider-side rate limit, verified domain, no user-controlled arbitrary recipient/body, webhook signatures | Free daily/monthly threshold is approached twice |
| Subscription margin | Price by store region, model net proceeds after tax/fees/refunds/support, retain a provider-cost reserve | Any supported region or annual product becomes contribution-margin negative |

Maintain a monthly cost ledger with provider, billed unit, free allowance, current usage, warning threshold, hard threshold, owner, and response. Review it weekly for the first month, then monthly. Do not enable automatic paid upgrades for a service until its hard maximum is written down.

## Mobile launch gate

### Shared gate

- Production authentication, purchases, restore, entitlement expiry/grace, notification delivery, deletion, export, and sync are verified from real dashboard state and physical devices.
- Signed-out reading, exact routes from links/notifications/widgets, offline downloads, stale/corrupt dumps, upgrades, and restored positions pass on both platforms.
- Arabic and translated long content pass large text, screen reader, RTL, reduced motion, low-memory, slow-network, no-network, and provider-outage tests.
- Privacy policy and store disclosures name every SDK and actual data flow; they do not rely on SDK marketing labels.
- Content rights, source scope, grades, AI labels, and canonical-link fallback are reviewed with production data.
- Crash/analytics consent is tested both ways, including opt-out reset and deletion behavior.
- The production cost ledger, hard limits, backup/restore evidence, rollback instructions, incident contacts, and kill switches are complete.

### Apple

- Complete App Store Connect [app privacy disclosures](https://developer.apple.com/help/app-store-connect/manage-app-information/manage-app-privacy/) for Hadithly and every included SDK.
- Complete [app information](https://developer.apple.com/help/app-store-connect/reference/app-information/app-information/), including privacy URL, age rating, and content-rights declarations.
- Provide in-app account deletion as required by Apple's [account deletion guidance](https://developer.apple.com/support/offering-account-deletion-in-your-app/); deletion must remove the whole account, not merely deactivate it.
- Verify the [App Review Guidelines](https://developer.apple.com/app-store/review/guidelines/) for sign-in, privacy, subscriptions, restore purchases, and review access.
- Finish agreements, tax/banking, export compliance, subscription copy/terms, review notes, a working review account when necessary, screenshots/localization, privacy manifests/required-reason APIs, SDK signatures, TestFlight validation, and deliberate manual or phased release.

### Google Play

- Complete [Data safety](https://support.google.com/googleplay/android-developer/answer/10787469) for app and SDK behavior.
- Provide both an in-app path and public web URL for [account deletion](https://support.google.com/googleplay/android-developer/answer/13327111).
- Run the [pre-launch report](https://support.google.com/googleplay/android-developer/answer/9842757), including its stability, performance, accessibility, deep-link, and language coverage.
- From 2026-08-31, new apps and updates must [target Android 16 / API 36](https://developer.android.com/google/play/requirements/target-sdk); the repository already declares target SDK 36, but the release artifact must be rechecked.
- If the account is a new personal account created after 2023-11-13, complete the [closed test with at least 12 testers opted in continuously for 14 days](https://support.google.com/googleplay/android-developer/answer/14151465) and [device verification](https://support.google.com/googleplay/android-developer/answer/14316361).
- Prepare for [Android developer verification](https://support.google.com/android-developer-console/answer/16561738), which begins enforcement in selected countries on 2026-09-30 and expands globally in 2027.
- Complete Play App Signing, App Integrity, content rating, app access, subscription license testers, AI/content declarations where applicable, internal then closed testing, verified App Links, and a staged production rollout.

Start Android at a small staged percentage such as 1–5% and pause automatically on crash, purchase, auth, deletion, routing, or backend-cost regressions. Use a manual iOS release or Apple's phased release. Define numerical stop conditions before pressing release, not during an incident.

## Master-plan session crosswalk

Keep these concerns in the plan's existing small sessions instead of creating a
second sequence:

1. **F3 — Domain and trust surface.** Static home, privacy, terms, support,
   deletion, content methodology, association files, and the canonical fallback.
2. **LA1 — Diagnostics and operational visibility.** Crashlytics, redacted logs,
   Better Stack probes/status, symbols, alerts, and provider-outage evidence.
3. **LA2 — Minimal analytics.** Exactly one analytics SDK behind its own local
   control and a fixed event/property allowlist.
4. **LA3 — Support, mail, backups, and cost controls.** Support routing,
   SPF/DKIM/DMARC where needed, hard budgets, kill switches, cost ledger, and a
   restore drill.
5. **D3, D4, and L1 — Store and release readiness.** Dashboard disclosures,
   physical-device journeys, reviewer access, metadata, screenshots, and staged
   release controls.
6. **LA4 — Read-only web reader decision, deferred.** Decide from real
   usage/licensing evidence; no personal or AI surface in the first approved
   scope.

## Community evidence — anecdotal, not product requirements

These posts are not authoritative evidence. Engagement is a visible snapshot taken on 2026-09-02 and can change. X also states that [view counts are not unique](https://help.x.com/en/using-x/view-counts), so repeat viewing may be included.

- A 2022 r/startups retrospective, [“How we failed with a waitlist”](https://www.reddit.com/r/startups/comments/w9cpsg), showed 86 upvotes when checked. The author reported gathering 1,130 email addresses over 12 months, then receiving responses from about 20% of the first 300 invitations. The useful lesson is modest: a large waitlist is not activation, so Hadithly should not delay a usable native launch for an elaborate acquisition funnel.
- A 2025 r/indiehackers post, [“First-time founder launching in 5 days”](https://www.reddit.com/r/indiehackers/comments/1nr3z8k/firsttime_founder_launching_in_5_days_heres_my/), showed 13 upvotes when checked. Its checklist emphasized the signup-to-payment funnel, email, and payment verification, while commenters challenged polishing the landing page ahead of payment validation. For Hadithly, verify account, quota, purchase, restore, and deletion journeys before expanding marketing pages.
- Marc Lou's [2025-08-03 X post](https://x.com/marc_louvion/status/1951949978441830623) showed approximately 27,300 views, 74 likes, 1 repost, 9 bookmarks, and 19 replies when checked. It described resuming a weekly newsletter and dedicating more time to marketing. The limited inference is that launch communication is ongoing work, not a single announcement; it does not justify collecting a newsletter by default.
- Pieter Levels's [2018-03-01 X dashboard post](https://x.com/levelsio/status/969441437338058752) showed 125 likes, 8 reposts, 6 bookmarks, and 8 replies when checked. Public revenue and user metrics suit a founder audience, but conflict with Hadithly's quiet product rules. Do not add public usage statistics, rankings, or social proof counters to imitate that strategy.

The community material supports one narrow recommendation: launch a small, reliable trust surface and keep communicating, but measure success through private operational and user-outcome signals. It does not override primary provider documentation, app-store rules, or Hadithly's privacy constraints.
