# Q2 pricing and free-user subsidy

Research and calculation date: 2026-10-12. USD 2.99 monthly and USD 24.99 annually
remain the base prices. Annual is a 30.35% discount, with $2.0825 recognized gross
per month. Store package prices supply the consumer's actual local price.
Weekly, lifetime, and Apple Family Sharing are off. One `pro` entitlement follows
the same signed-in Hadithly account on iOS and Android.

These prices cover ordinary translation usage comfortably. They do not prove
willingness to pay, profitability with unlimited free users, or profitability
under maximum-size generation attempts. Those are separate claims.

## Current official fees

- Apple subscriptions ordinarily yield 70% during the first paid year and 85%
  afterward, minus applicable taxes. Small Business enrollment gives 85% from
  the start. Enrollment has not been verified, so retain the 30% case.
  [Apple subscriptions](https://developer.apple.com/app-store/subscriptions/),
  [Small Business Program](https://developer.apple.com/app-store/small-business-program/).
- Play auto-renewing subscriptions ordinarily total 15%. The official October
  page describes updated regions as 10% service plus 5% Play billing, and
  remaining markets as 15%. No alternate billing program is assumed.
  [Play fees](https://support.google.com/googleplay/android-developer/answer/112622).
- RevenueCat is free below $2,500 monthly tracked revenue, then 1% of tracked
  revenue, before the store cut. Reserve 1% of gross in every row to avoid a
  misleading threshold-dependent margin. Annual purchases count when tracked;
  revenue recognition here spreads their economics across 12 months.
  [RevenueCat pricing](https://www.revenuecat.com/pricing).
- Gemini 2.5 Flash-Lite is $0.10/million text input tokens and $0.40/million
  output tokens. Ordinary generation has thinking disabled and no grounding.
  At 2,000 input plus 500 output tokens it costs $0.0004. This is a planning
  assumption, not a measured population average.
  [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).
- Convex Starter includes 1M calls, 20 GB-hours action compute, 0.5 GB database
  storage, 1 GB database I/O, and 1 GB egress. Listed US overages are $2.20/M
  calls, $0.33/GB-hour actions, $0.22/GB database storage and I/O, and
  $0.132/GB egress. Hadithly's `eu-west-1` multiplier must be applied to an
  actual resource forecast. Free has included caps; Starter bills overages.
  No plan upgrade is part of Q2.
  [Convex pricing](https://www.convex.dev/pricing),
  [limits](https://docs.convex.dev/production/state/limits).

## Cost table

Run `python3 scripts/check-q2-pricing.py`. Expected usage is 100 Pro generations
per month. Full average rolling quota is 100 × 365.25 / 12 / 7 = 434.82/month;
it can burst to 500 successes in a 31-day month. The table allocates a
conservative $0.10/month Convex reserve per Pro account. This is not measured
per-account billing. Free active accounts reserve $0.02/month. Shared cache reuse
reduces model spend, but cached content still costs storage and delivery.

| Case | Gross/mo | Included tax | Store fee | RC reserve | Gemini | Convex reserve | Contribution/mo | Margin on proceeds |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| Monthly, 15%, expected | $2.9900 | $0 | $0.4485 | $0.0299 | $0.0400 | $0.1000 | $2.3716 | 94.4% |
| Annual, 15%, expected | $2.0825 | $0 | $0.3124 | $0.0208 | $0.0400 | $0.1000 | $1.6093 | 92.0% |
| Monthly, Apple 30%, expected | $2.9900 | $0 | $0.8970 | $0.0299 | $0.0400 | $0.1000 | $1.9231 | 93.2% |
| Annual, Apple 30%, expected | $2.0825 | $0 | $0.6248 | $0.0208 | $0.0400 | $0.1000 | $1.2969 | 90.3% |
| Annual, 30% + illustrative 25% included tax, expected | $2.0825 | $0.4165 | $0.4998 | $0.0208 | $0.0400 | $0.1000 | $1.0054 | 87.8% |
| Annual, same fee/tax, full average quota | $2.0825 | $0.4165 | $0.4998 | $0.0208 | $0.1739 | $0.1000 | $0.8714 | 76.1% |
| Monthly, same fee/tax, 31-day quota burst | $2.9900 | $0.5980 | $0.7176 | $0.0299 | $0.2000 | $0.1000 | $1.3445 | 81.8% |

Proceeds = gross / (1 + included tax rate) × (1 − store fee) − RC reserve.
Contribution = proceeds − Gemini − Convex reserve. Margin = contribution /
proceeds, rather than a percentage of customer gross. The 25% tax row is a
sensitivity example, not a verified tax rate for a particular storefront.
Actual withholding, VAT on developer/service fees, FX, refunds, corporate and
personal taxes, and store adjustments require seller statements. US sales tax
added to the customer price is not treated as an included deduction here.

Fixed overhead and other variable costs are excluded from unit contribution:
developer membership, domain renewal, Clerk paid usage, evidence scanning/OCR
and two-pass review, notifications, monitoring, support, and acquisition. Review
`COST_REVIEW.md` and the live invoices before calling the business profitable.

## Free is a bounded subsidy

At the typical token assumption, five/week costs $0.00870/month in Gemini.
Including the $0.02 infrastructure reserve gives $0.02870 per free MAU/month.
A 31-day burst of 25 new translations costs $0.01 in Gemini. Failures can cost
money without consuming quota; cached reuse consumes no generation quota.

With every paid user annual and using their full typical quota, the no-fixed-cost
break-even conversion is 1.9% at 15% commission/no included tax, or 3.2% at
30% commission/25% illustrative included tax. That supports 51.4 or 30.4 free
MAUs per Pro respectively. A proposed 60% contribution floor after free subsidy
allows only 14.8 or 6.4 free MAUs per Pro, or about 6.3%/13.5% paying. At 1%
conversion the model loses money before fixed overhead. A 5% conversion can
cover modeled variable costs, but does not retain a 60% margin in either case.

The existing Q1 aggregate admission budget defaults to $10/month, 500 attempts/day,
and 25,000 attempts/month. It reserves $0.02 per provider attempt atomically;
known token usage releases unused money. Unknown, failed, or abandoned paid
attempts retain their reservation. The budget applies to service, free and Pro
generation together. Cached and offline reading survives generation pauses.
Live environment overrides and other services are not covered by this code limit.

Maximum source size is 64 KB and maximum output 8,192 tokens. Conservatively
modeling 65,000 input tokens gives $0.009777/attempt. Five hundred such successful
attempts can cost $4.89 in a month, more than either plan's proceeds. Therefore
the existing quotas are reasonable for typical texts, but are not a per-account
profit guarantee. The aggregate budget bounds exposure by pausing generation;
it does not ensure every subscriber receives their entire quota under stress.
Do not describe the allowance as unlimited or guarantee availability.

## Approved Apple regional tiers

The owner approved the exact Apple monthly and annual exports on 2026-10-12,
after reviewing the cost table. Both exports cover the same 175 storefronts and
only upfront billing. The base US prices remain $2.99/$24.99. Examples:

| Country | Currency | Monthly | Annual |
| --- | --- | ---: | ---: |
| United States | USD | 2.99 | 24.99 |
| Kazakhstan | KZT | 1,790 | 14,990 |
| India | INR | 299 | 2,499 |
| Indonesia | IDR | 49,000 | 399,000 |
| United Kingdom | GBP | 2.99 | 24.99 |
| Germany | EUR | 2.99 | 29.99 |

Raw source records are `q2-pricing/apple-monthly-2026-10-12.csv` and
`q2-pricing/apple-annual-2026-10-12.csv`, downloaded from App Store Connect.
Their estimated proceeds include storefront deductions. The US proceeds of
$2.54 on $2.99 imply the 15% store rate. This is the export's estimate, not
independent proof of Small Business enrollment or a settlement invoice.
Kazakhstan's displayed 1,311.64 proceeds on 1,790 is consistent with an included
16% tax and 15% commission. This is an inference from the export, not a tax filing
instruction. Seller-specific withholding and service taxes remain unverified.

Run `python3 scripts/check-q2-pricing.py --apple-export-dir docs/q2-pricing --floor 0.60`.
The checker requires 175 unique countries in each plan, matching coverage, exact
billing plans, complete FX coverage, and rates dated within seven days of this
snapshot. It adjusts estimated proceeds from 15% to a conservative 30% store
fee, reduces converted proceeds by another 15% for currency risk, then deducts
1% of gross for RevenueCat, $0.10/month infrastructure, and typical-size quota
bursts of 500/month or 5,300/year. No blended FX rates are used.

The lowest modeled paid-unit contribution margin is 78.6% monthly in Russia,
$1.1019/month contribution, and 71.7% annually in Indonesia, $0.7017/month.
Both exceed the selected 60% check under the owner's delegated judgment. These results still exclude free-user
subsidy and fixed overhead, and do not cover the maximum-source stress case.
Availability and financial settlement eligibility are separate from price math.

`q2-pricing/fx-2026-10-12.json` records conversion rates and provenance. Most
rates come directly from the National Bank of Kazakhstan's 2026-10-12 RSS.
Eight missing currencies use named official providers through Frankfurter's
attributed feed: Chile BCCH, Colombia BANREP, Nigeria CBN, New Zealand and
Philippines ECB, Peru BCP, Taiwan MAS, and Tanzania BOTA. Dates range from
2026-10-09 to 2026-10-12. Each entry retains the issuing provider's data URL.
[National Bank rates](https://nationalbank.kz/rss/rates_all.xml),
[Frankfurter provider attribution](https://frankfurter.dev/).

The approved $2/month free/service generation sub-budget sits within the $10
aggregate AI budget. At typical token sizes it funds roughly 5,000 new
translations across all free users and service generation each month. Conservative
pending/unknown-call reservations and the daily attempt cap can pause generation
earlier. Unattributed pre-Q2 monthly spend is conservatively charged against
that sub-budget until the month ends. A paid admission uses the remaining shared
budget; no claim is made that each subscriber is guaranteed the entire allowance
when the aggregate service budget is exhausted. Live deployment is development
only; production activation remains an action-time approval gate.

Google regional prices and sandbox evidence remain open because Play Console
is unavailable. Do not invent Google prices from Apple tiers. Once Play exists,
export its own prices, taxes, and proceeds, check the same floor and obtain final
approval before publication. Keep store-managed equivalents and avoid custom
purchasing-power discounts without another margin check.

The generic checker accepts normalized rows with `region`, `monthlyUsd`,
`annualUsd`, `taxRate`, and `storeFee` using `--regions /path/to/export.json`.
A passing subset is not evidence of complete Google storefront coverage.
