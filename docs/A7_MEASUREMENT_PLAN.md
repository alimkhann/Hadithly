# A7 activation, return and conversion measurement plan

October 31, 2026. Local planning complete; actual A7 acceptance remains open.
No participant was contacted or observed. No account, vendor or store was read.
No analytics was activated. This document proposes later work, not permission to
start it. Use the [reader-session protocol](A7_READER_SESSION_PROTOCOL.md) for
instructions and blank records. The [requirement audit](A7_REQUIREMENT_AUDIT.md)
records what was verified locally.

## What the evidence can answer

Activation means reaching usable reading. Return means choosing to read again
later. Conversion means moving from a precisely defined eligible population to a
confirmed paid purchase. Each needs a different source of evidence.

LA2 measures anonymous operation outcomes. It deliberately cannot connect a
person's first reading to next week's reading or a later purchase. Keep that
boundary. The proposed small reader study uses voluntary, private study notes to
understand obstacles and return decisions. Those notes never enter analytics,
Convex, an account profile, Linear, git or a model prompt.

The last recorded provider proof is October 14, with October 13 UTC buckets:
62 exported rows mixed synthetic fixtures and actual development guest journeys.
These are metric rows, not 62 people, sessions, purchases or returning readers.
Development collection was then disabled; production was never activated in that
record. This planning unit does not verify current vendor or deployment state.
An old zero is neither current zero usage nor zero demand.

Sources are [LA2 design](LA2_DESIGN.md), [verification](LA2_VERIFICATION.md),
[operations](LA2_OPERATIONS.md), the [closed catalog](analytics-catalog.json),
[dashboard definition](LA2_DASHBOARD.json), and native `ReaderMeasurement` reducers.
Their dates and scopes take precedence over inference from older dashboard boxes.

## Name the population before the number

| Term | Meaning and boundary |
| --- | --- |
| Rendered first reading | The first usable exact-locale hadith text layer visibly lands after onboarding. A reference, loading view, sign-in notice, or illustrative prepared example does not count. Visible text does not prove comprehension, semantic quality or rights. |
| Guest reading | An open in signed-out state. Repeated opens, shared devices and reinstalls prevent a unique-guest count. A guest is not a registered account. |
| Registered accounts | Distinct completed verified account resources in the authorized account system at a dated cutoff. Accounts are not people or active readers. Anonymous `account_new` flow totals cannot supply this inventory. |
| Active users | Distinct people with at least one usable rendered reading in a defined window, if person-level measurement has been approved and proved. LA2 has no such identifier. Report active reading operations instead, or a separately labelled study-participant count. |
| Returning reader | In the study, an activated participant who voluntarily reads again in a specified later window. A restored position at an arranged session proves restoration, not voluntary return. Product-wide returning people are unavailable. |
| Confirmed paying customers | Deduplicated customers with a real positive-value settled production purchase, reconciled to store and RevenueCat records at a cutoff. Exclude sandbox, fixtures, TEST events, free grants and fully refunded or revoked purchases. Report current paid access separately from historical purchasers. Renewal transactions are not new customers. |
| Eligible conversion population | The same nonpaying people or accounts, eligible for the offer and observed for the entire stated window, who form the numerator's source population. Downloads, onboarding starts, all accounts and purchase attempts are different denominators. |
| Study participants | At most eight consenting adults in a small convenience sample. Their study code is a private research link, not an app identity. Findings cannot estimate the whole audience or fifteen-locale retention. |

## Metric definitions

Each row specifies population, numerator, denominator, time window, source,
limits and the actual readback required. `N/A` means no rate is defined, not zero.
LA2 metric names below already exist. This plan adds no metric or property.

| ID and measure | Population | Numerator | Denominator | Time window | Source | Limits | Required real readback |
| --- | --- | --- | --- | --- | --- | --- | --- |
| M01 Ordered first-reading activation | Admitted local onboarding flows on one platform and environment | `onboarding_step.ordered_first_reader` summed `count` | `onboarding_step.ordered_started` summed `count` from the same start-hour flow population | One uninterrupted 30-minute local flow; aggregate latest seven settled UTC days versus preceding seven | LA2 ordered reducer and frozen export | Process death, opt-out and clipping break linkage. Resumed onboarding lacks a fabricated start. Flows are not people; examples are not reading. No cross-day independent-total division | After separate activation approval, real native first-text landing on each app, safe ingress/export reconciliation and current health, with fixtures excluded by a separate clean period/environment |
| M02 Guest rendered-open reliability | Admitted signed-out open operations | `reader_open_result.guest_online` plus `reader_open_result.guest_offline` counts | `reader_open_result.guest_started` count | Latest seven settled UTC days, by platform/environment | LA2 reader reducer after visible acknowledgement | Repeated opens and recovery starts are operations, never unique guests. Loss may affect numerator and denominator differently | Real signed-out rendered online/offline outcomes on both named devices, current transport/export totals and health; no target or identity in analytics |
| M03 Account rendered-open reliability | Admitted signed-in open operations | `reader_open_result.account_online` plus `reader_open_result.account_offline` counts | `reader_open_result.account_started` count | Same settled seven-day comparison as M02 | LA2 reader reducer | Does not count distinct accounts or prove live auth, sync or account isolation | Approved real authenticated native opens and current safe aggregate readback; G07-G09 remain independent |
| M04 Exact restoration reliability | Admitted restoration operations | `restoration_result.exact` count | `restoration_result.started` count | Settled seven-day windows; verdict freezes at first landing | LA2 semantic-anchor and native frame acknowledgement | Eight iOS points or Android dp is the existing tolerance. Later manual scroll cannot turn fallback into exact. Not a retention metric | Actual original-target versus first-frame result on each app; private local target check, only fixed aggregate verdict exported |
| M05 Backend access after purchase start | Admitted ordered offer flows that start a store operation | `paywall_result.confirmed` count | `paywall_result.purchase_started` count in the same ordered population | One uninterrupted 30-minute flow, then settled seven-day totals | LA2 paywall reducer and actual backend Pro acknowledgement | Backend access is not settled money. Delayed completion beyond window is missed. Fixture purchases, grants and restore are not new paying customers | Real store/RevenueCat/Convex/native readback under G22-G24, current safe totals and health; label sandbox separately |
| M06 Study rendered activation | Consenting participants starting the day-0 first-reading task, excluding withdrawn records | Participants with witnessed usable exact-locale text, once per participant | All retained task starters, including blocked and assisted starts | Day-0 task capped at ten minutes, within 30-minute session | Private task sheet; facilitator sees text without copying it | Small sample; assisted and unassisted outcomes split. Missing language/content is a blocked task, not success. No semantic approval inferred | Dated consent version, build/OS/platform, language scope, start and landing result, assistance level and blocker; no results exist yet |
| M07 Study voluntary return D1, D7, D14 | Retained M06 activated participants whose complete target window elapsed | Participants reporting voluntary usable reading in each window; directly witnessed voluntary cases labelled separately | All retained activated participants with a mature window, including unknown follow-up outcomes | D1 [24,48), D7 [168,192), D14 [336,360) hours after first rendered reading | Participant-held minimal diary, discussed after day 15; no background observation | Self-report and recall are not independently verified cohort retention. Arranged or reminder-led opens excluded. Unknown is not no return. No app identifiers or analytics joins | Per-code mature-window record: yes/no/unknown, self-report/witnessed, voluntary/prompted, evidence date and withdrawal state; show counts and unknowns, not population uplift |
| M08 Study prompted resume | Retained participants attempting the arranged follow-up resume task | Participants reaching the intended saved place, with assisted result separate | All retained participants attempting that task | Arranged day-15 to day-17 follow-up, at most 15 minutes | Private observation sheet | Proves task usability only. Never counted in M07 | Actual first landing and expected place checked privately without saving reading history or note content |
| M09 Study active participants | Retained consented sample | Participants with at least one reported usable reading during the interval | N/A for count; optional coverage denominator is all retained enrolled participants | Baseline and follow-up weeks reported separately | Private task/diary record | Sample activity only; self-report separate from witnessed tasks. This cannot become app DAU, WAU or MAU | Dated count by evidence type, mature coverage and missing records; suppress small public breakdowns |
| M10 Registered-account inventory | Authorized completed account resources in a specified environment | Distinct completed, nondeleted registered accounts at cutoff | N/A for inventory count | Exact as-of timestamp; new registrations separately bounded by seven days | Future approved read-only Clerk inventory reconciled to Convex account provisioning | Currently unavailable. One person may have several accounts; deleted, pending and test resources need explicit exclusions. LA2 totals cannot replace inventory | Dated environment, counts and dedup/exclusion method, no email or account IDs in committed output; separate authorization before account access |
| M11 Product active users and return retention | Entire real reader population, including guests | Unique readers with rendered reading in week; for retention, eligible activated readers returning in D1/D7/D14 | N/A for active count; same mature activated-reader cohort for return rate | Fixed UTC week and exact relative return windows | No existing approved source | Unavailable under LA2. No stable identity, cross-device dedup or enduring first-reading link. Registered-account inventory alone cannot establish activity | Would require separately approved collection design, consent/disclosures, expiry/deletion controls and genuine dedup/visibility readback before any number is reported |
| M12 Confirmed paying-customer inventory | Real production purchasers, deduplicated across both stores and restores | Customers with positive settled payments, excluding full refunds/revocations as of cutoff | N/A for count | Dated cutoff plus seven-day purchase period; refunds reconciled through that cutoff | Future approved store financial/receipt and RevenueCat readback; backend entitlement corroborates access | Currently unavailable. Pro flag, sandbox success, subscription start, intent and analytics `confirmed` do not prove payment. Later refunds can revise counts. Net revenue, commission and annual total are separate G18 evidence | Actual dated environment/store/currency/payment status, safe reconciliation receipt and dedup method; no raw transaction/customer IDs in repo |
| M13 Activation-to-paid and registration-to-paid conversion | Separately defined initially nonpaying activated-reader cohort and newly registered-account cohort | Members of each same cohort with M12-confirmed first payment within 14 days | All eligible retained cohort members with a full 14-day follow-up, separately for activation and registration | [0,336) hours after each member's qualifying activation or registration | No approved linked cohort source; financial and activity sources alone cannot join | Unavailable now, including in this guest-first study. No estimate from starts, stock account count, clipped totals or unmatched receipts. Account conversion is not person conversion | Separate approved minimal linking design, eligibility/exclusion register, mature cohort and actual matched payment readback with refunds/censoring reported |
| M14 Study offer comprehension and interest | Retained participants choosing the optional nontransactional offer task | Participants accurately describing actual billing period/total; interest recorded separately | Retained participants attempting the task | Optional five-minute day-0 discussion after core reading | Private task sheet, approved exact store-sourced total if available | Intent is not conversion. Current monthly-equivalent-only prototype cannot establish annual-total comprehension. If real total unavailable, record blocked. No purchase action | Actual displayed offer/version and paraphrase category, no quotes or financial details; G18/G22/G23 stay open |

## Interpret clipped totals conservatively

If cross-store customer deduplication cannot be established from approved
financial records, report per-store payer records and mark the combined unique
customer count unavailable. Never assume that two store purchasers are two people.

Use `sum(count)`, not vendor event counts or distinct IDs. Keep platform and
environment separate. A UTC day settles only after its 24-hour arrival window.
Compare the latest seven settled days with the preceding seven, not today or
yesterday. Preserve the ordered local start hour across midnight.

The native cap admits 39 product facts and one clipping marker within forty
facts per UTC day. There are three queued summaries, a 24-hour eligibility limit,
three attempts, and a 4 KiB summary bound. Ten accepted summaries are required for
a bucket to export, not ten readers. Unpublished small buckets expire after seven
days. Convex exported totals have ninety-day retention. The historical vendor UI
showed one year, which requires fresh verification before collection resumes.

Record current collection/export status, last settled export, lag, cap warnings,
suppressed buckets, clipping markers, rejected/admitted/exported counters and
outages alongside every LA2 report. Those are service-health measures. A clipping
marker counts cap episodes, not lost people or the percentage of missing data.
The exact discarded-fact count is local verification state, not a vendor field.

Opt-out, offline expiry, process death, queue pressure, under-threshold suppression,
retries and caps can remove different parts of a ratio. Never scale totals up to
estimate missing readers or divide unrelated period totals to invent a funnel.
Below twenty admitted opportunities, withhold percentages and say "Too little
data to judge." With zero denominator, show unavailable. If numerator exceeds
denominator, withhold the rate and investigate measurement. Report health limits
even above twenty; a large denominator does not repair bias.

For the small study, report participant counts such as "R of N mature activated
participants reported return; U unknown," not a general retention percentage.
Keep yes, no, unknown, not-yet-mature, withdrawn and prompted separate. Report
enrolled count and exclusions without retaining identifying withdrawal details.
For uncertainty, show R/N and (R+U)/N only as possible response bounds when N is
nonzero, not as confidence intervals or verified retention. Remove withdrawn
records and recompute all linked results before the deletion deadline. Do not
drop nonresponders to improve the apparent result or carry an immature window
into the denominator.

Participation, the diary and being watched can change reading behavior. Volunteers
also differ from readers who decline. Report these selection and observation
effects alongside recall and missing-data limits. The study cannot prove organic
population retention, causation, or an improvement over the earlier app.

## What needs new approval and collection

Product-wide distinct guests, unique active people, person-level retention,
cross-device return, install-to-paid conversion, activated-reader-to-paid
conversion and acquisition attribution are not available. No approved LA2 field
can recover them. Stable install hashes, account pseudonyms, locale properties,
fingerprints or exported reading histories would change the privacy contract.
Do not introduce them as a reporting fix.

The study itself introduces a private longitudinal study code and diary. Obtain
specific owner approval and participant consent before collecting either. Keep
that collection separate from product analytics. Genuine whole-product cohorts
would need a new minimised proposal explaining purpose, linkage, consent,
retention, withdrawal/deletion and actual serialized readback on both apps. Prepare
that separately only if the small study cannot answer the decision at hand.
This unit neither implements nor approves that collection.

## Decisions and acceptance

The study asks whether readers can reach useful text, save a place, resume it,
and describe why they chose to return or did not return. Investigate a witnessed
blocking reading/privacy failure immediately. For lesser issues, preserve counts
and evidence strength before selecting a bounded repair. No arbitrary activation,
retention or conversion target is invented for this small sample.

The local planning checklist can pass once definitions, consent, procedures,
templates, schedule and preservation checks are complete. The original A7 box
stays unchecked until actual consented sessions and the bounded observation
period have produced dated activation/return evidence, a reconciled conversion
readout or an explicit unavailable finding, and an owner-reviewed acceptance
decision. Unavailable conversion is not a passed conversion test. No deadline,
fixture, sandbox receipt or completed document can close a missing evidence gate.

All [G01-G41 carried gates](A7_GATE_CARRY_FORWARD.md) remain open. A1/A3 content
and semantic acceptance, A4 exact-copy/full accessibility, actual purchases,
production, E's actual Linear hub and the independent final program audit remain
part of the original program before `POST_GOAL_BACKLOG.md`.
