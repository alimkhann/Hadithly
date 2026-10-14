# LA4 decision: defer the read-only web reader

Date: 2026-10-14, Asia/Almaty

## Decision

**DEFER.** LA4 is a pre-launch dependency and evidence audit, not an approval
to build a web reader. The LA4 post-launch acceptance gate remains **OPEN**.

No implementation sessions are created. The shipped landing page and canonical
route remain the current public surface. L1, D4, release, physical-device,
store, production, rights, privacy, analytics, backup, sync, widget, and other
open gates remain open.

## Evidence audit

Native launch is not established. The plan says that L1 has not started and D4
is blocked. LA2's 62 vendor rows are development verification, not readers,
referrals, or production demand. Collection and export were disabled after the
development proof. See [LA2 verification](LA2_VERIFICATION.md),
[the provider fixture readback](evidence/la2/provider-readback.json), and
[the current release gates](OPEN_GATES.md). The fixture readback names its
environment as development.

The production Vercel Web Analytics request for 2026-09-02 through 2026-10-14,
grouped by `deviceType`, returned `404 Web Analytics not found`. That is
unavailable measurement, not zero demand. No valid desktop demand result is
available.

The [LA4 readback](LA4_EVIDENCE.json) records the October 14 checks and SHA-256
hashes. The public readback shows the limit of the shipped surface:

| Surface | Verified state |
| --- | --- |
| `/` | `200`, 1,279 bytes, CDN hit, matches the checkout, no scripts, resolver, Open Graph metadata, or analytics beacon |
| `/hadith/bukhari/1` | `200`, 1,212 bytes, `noindex`, CDN miss, no scripts, resolver, text, Open Graph metadata, or analytics beacon |
| `/canonical.js`, `/robots.txt`, `/sitemap.xml` | `404` |

The deployed hadith page says "Continue in Hadithly" and links to About and
Support. It does not provide a working app or store action. The local F3
resolver is unshipped. The current production route therefore cannot establish
desktop reading demand, indexing value, or a working web reading experience.

## Shipped fallback versus a future reader

| Question | Shipped fallback | FUTURE signed-out reader |
| --- | --- | --- |
| Demand | No usable desktop or referral measurement | Measure coarse route-family outcomes and referrer class only. Do not claim unique readers or conversion. |
| Rights | Static routing notice with no hadith text or runtime license gate; the unshipped F3 resolver suppresses unverified text | Display only exact, affirmatively licensed corpus and translation entries. Rights must cover web display, commercial hosting, CDN delivery, attribution, and revocation. |
| Accessibility | No reader proof exists | Target [WCAG 2.2 AA](https://www.w3.org/TR/WCAG22/), keyboard and focus order, headings, language and RTL, 200% text, 320 CSS pixel reflow, contrast, and screen-reader proof. These are targets, not tested results. |
| Indexing | The route is `noindex`; robots and sitemap are absent | Keep indexing off at first. Clean URLs, locale aliases, query-position handling, Open Graph data, and a sitemap need a separate rights and privacy decision. |
| Maintenance | Static page and existing routing only | Prove content refresh, purge, source-policy recheck, broken-link handling, and owner time before expanding. |
| Abuse | No reader text or broad content endpoint | Bound route and query inputs, rate-limit resolver access, escape all text, and stop on scraping or abuse signals. Do not add accounts, contributions, or public user content. |
| Privacy | No reader identity or reading position | Keep the same boundary. Do not collect canonical IDs, locales, positions, IP-derived profiles, account IDs, replay, or raw referrer URLs. |
| Cache | Existing fallback is public static content | Use short, purgeable rights-sensitive responses. Checksums can verify bytes, but they do not grant permission. Do not add a service worker or persistent offline cache in the first pilot. |
| Cost | Existing hosting state only | Use static or cached licensed outputs, with Convex as the sole authority and CDN as a data-only delivery path. Do not add a second backend. |

## Rights gate

The [offline license contract](../backend/convex/offlineDumps.ts) in
`recordSunnahNowLicense` records `permitsDisplay` and
`permitsOfflineDistribution`, but `permitsRedistribution` is explicitly false.
O1 and production rights remain open. The [local canonical resolver](../backend/convex/hadiths.ts)
checks display permission, and [E4 publication validity](../backend/convex/lib/evidencePublication.ts)
checks translation permission dependencies. Those mechanisms do not prove a
future static copy will respect revocation. The current `permitsDisplay` value does
not establish a commercial web, CDN, indexing, or public corpus-distribution
grant.

The [Sunnah.now early-access guidance](https://docs.sunnah.now/guide/going-in-the-future.html)
describes free early-access Bukhari Arabic and English data and MIT software.
That does not make every data version, translation, or public delivery use
permitted. The [database README](https://github.com/sunnah-now/database) uses
offline-use wording, but does not establish public corpus redistribution. The
[Sunnah.com terms and about material](https://sunnah.com/about) forbids scraping
and mass reproduction while allowing narrower individual teaching selections.
API access does not override those limits.

Before any web text is approved, record the exact corpus version, each
translation's permission and attribution, canonical citations, commercial and
CDN scope, expiry, and revocation behavior. Cached text must fail closed and be
purgeable. A checksum proves content identity, not reuse rights.

## Cost boundary

The refreshed [Vercel Hobby terms](https://vercel.com/docs/plans/hobby) restrict
Hobby to noncommercial personal use, with a 1 million CDN-request allowance and 100 GB transfer. Vercel
[Pro starts at $20 per developer per month](https://vercel.com/pricing).
Commercial eligibility is unresolved, and
current shared usage and invoices are unknown. The LA3 same-day readback recorded
Vercel Hobby with no card and Convex Free. Hobby is not a valid commercial reader
plan.

[Convex pricing](https://www.convex.dev/pricing) includes 1 million calls and
1 GB egress for Free and Starter. Free has hard caps; Starter permits paid
overages. Published US East overages are $2.20 per million calls and $0.132
per GB. Account for the EU region
[1.3x price factor](https://docs.convex.dev/production/state/limits) and shared
allowances. [Cloudflare R2](https://developers.cloudflare.com/r2/pricing/) includes
10 GB-month storage, 1 million writes, 10 million reads, and free internet
egress. Published overages are $0.015 per GB-month, $4.50 per million writes,
and $0.36 per million reads, with provider billing-unit rounding. These are
published rates, not an actual Hadithly invoice.

The following are illustrations, not forecasts. They assume 50 KiB compressed
total response bytes per pageview, a 10% cache-miss rate, one Convex call per
miss, and CDN delivery for the page bytes. They exclude storage growth, builds,
support, taxes, shared usage, model calls, and any required paid plan. Convex
outside the US has a published 1.3x regional price factor. It does not multiply
the byte allowance. Shared allowances still need a live billing readback.

| Monthly pageviews | Formula | Illustration |
| --- | --- | --- |
| 10,000 | `10,000 × 50 KiB` total transfer; `10,000 × 10%` misses; `1,000 × 1` Convex calls | About 0.512 GB edge transfer, 1,000 calls, and about 0.0512 GB of Convex miss egress. This fits the published Convex Starter call and egress allowances if no shared usage consumes them. |
| 100,000 | `100,000 × 50 KiB` total transfer; `100,000 × 10%` misses; `10,000 × 1` Convex calls | About 5.12 GB edge transfer, 10,000 calls, and about 0.512 GB of Convex miss egress. This is below the 1 GB allowance before shared usage. The EU factor changes overage price, not the allowance. |

At 100% cache misses, 100,000 pageviews would send about 5.12 GB through
Convex, so the shared 1 GB Free egress allowance would be exceeded before any
paid upgrade. This is why the table is a cache assumption, not a forecast.

LA4 adds zero new hosting services. That does not mean zero total bill or zero
model usage. A $10 per month proposed incremental ceiling makes a $20 Vercel
Pro reader upgrade ineligible unless Pro is already required and accounted for
as baseline, or the owner changes the cap. No R2 migration or new R2 service is
authorized by this decision.

## Reopen criteria

These are policy proposals for discussion, not observed or approved thresholds.
Unavailable measurement blocks the decision.

Reopen LA4 only after all of the following are available:

- a documented native launch and store date, followed by a full 28-day
  production window;
- credible aggregate canonical-fallback desktop or referral demand and
  unsolicited desktop-reading support requests, with definitions and blind
  spots written down;
- no unique-reader, identity, content, or conversion claims from the proposed
  measurement;
- affirmative production rights for the exact corpus and translation scope;
- accessibility, privacy, security, cache-purge, maintenance, and cost
  evidence; and
- a cost ledger that includes shared allowances, provider invoices, taxes,
  support, builds, and model usage.

As an initial discussion threshold only, consider 200 valid desktop fallback
landings, a 20% desktop share, and five unsolicited desktop-reading requests.
Desktop share means valid desktop canonical-fallback landings divided by all
valid canonical-fallback landings in the same window. Valid means production
responses on syntactically valid canonical routes after excluding identified tests, uptime checks, previews, and known
bots. Unknown bots, repeat visits, missing referrers, and blocked collection
remain explicit blind spots. Referrers are coarse classes only, never raw URLs
or hostnames. No canonical ID, locale, position, or persistent reader identity
enters the measurement. Small cohorts below five are suppressed in reports.
These numbers are not current observations and do not authorize analytics.
Any future instrumentation needs its own approved session. LA2 remains
unchanged.

## Maximum future pilot

If the criteria reopen, the first pilot is limited to 100 canonical hadith pages
from one collection. It may contain Arabic and one existing translation locale
only when that translation is affirmatively licensed. It may provide simple
previous, next, list, and app links.

The pilot excludes search, accounts, contributions, AI generation, Saved sync,
subscriptions, community content, and a second backend. Convex remains the sole
identity, rights, and control plane. Static or cached licensed outputs may be
served through a CDN. Indexing stays off until separately approved.

## Proposed shutdown rules

These rules apply only to a separately approved 28-day pilot. They are not
active now because no pilot exists.

- Stop serving reader content and keep only metadata and routing fallback for any
  rights, privacy, security, or accessibility incident.
- Refuse new text at the origin immediately when rights expire or are revoked.
  Purge public copies within a proposed 15-minute deadline; disable the pilot if
  that deadline is missed. Browser responses must revalidate or use no-store,
  with no stale-on-error serving. A checksum or immutable filename cannot bypass
  the rights deadline. Already delivered or copied text cannot be recalled.
- Stop before native service is threatened if projected incremental cost exceeds
  $10 per month or any shared allowance reaches 80%.
- Stop if maintenance exceeds two hours per week for two consecutive weeks.
- Do not extend by default if the pilot records fewer than 100 valid desktop
  views over 28 days or telemetry is unusable.

All counts mean views, not people, and do not demonstrate reading. The existing
deployed fallback is unaffected, so no shutdown action is required now.

## Handoff

LA4 is deferred and not complete. No code, analytics activation, hosting
service, migration, deployment, or implementation session was added. Both native
apps and the backend, schema, and API retain their existing behavior. See
[verification](LA4_VERIFICATION.md) and [the independent review](LA4_REVIEW.md).
Earlier release and device gates remain in [Open gates](OPEN_GATES.md).
