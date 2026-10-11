# Hadithly operating cost and backend options

Research date: 2026-10-10. This combines current public pricing, source inspection, and a read-only usage audit in the signed-in Convex dashboard. It is not an invoice. Prices are USD before tax and can change. Hadithly's Convex deployments are in `eu-west-1`; Convex says non-US usage rates are 1.3 times its listed US rates. [Convex limits](https://docs.convex.dev/production/state/limits).

## Answer to the cost concern

Convex is not inherently expensive at the usage volumes modeled below. Its Free plan has hard team-wide resource caps. Starter has no monthly developer fee and meters usage above the same included amounts. Professional costs $25 per developer per month and includes larger allowances and daily backups. A sole tester hitting a Free cap does not show that the eventual bill will be high. It shows that one or more resources need attribution before choosing a plan or another backend. The cap may be database storage, database I/O, action compute, egress, or function calls. Free limits are shared by all projects and deployments on the team, including development and production. Free deployments can return errors after sustained overuse; Starter meters excess. [Convex pricing](https://www.convex.dev/pricing), [limits](https://docs.convex.dev/production/state/limits), [pricing FAQ](https://www.convex.dev/pricing/faq).

The dashboard audit below identifies the limiting resource. Set per-deployment warning and hard limits if moving to Starter; Convex documents that a hard limit disables the deployment until the window resets or the limit changes. [Usage limits](https://docs.convex.dev/production/usage-limits).

## Live Convex readback

Read on 2026-10-10, filtered to Hadithly, including its development and production deployments. The billing dashboard applies the Free allowances at team level. Only Hadithly appeared in the project selector.

| Resource | September billing period | October 1-10 | Free monthly allowance |
| --- | ---: | ---: | ---: |
| Function calls | 191K | 90K | 1 million |
| Action compute | 1.5 GB-hours | 0.62 GB-hours | 20 GB-hours |
| Database storage | 151.48 MB | 151.48 MB | 512 MB |
| Database I/O | **1.42 GB** | 148.25 MB | **1 GB** |
| File storage | 23.58 MB | 23.58 MB | 1 GB |
| Data egress | 302.78 MB | 75.28 MB | 1 GB |

September exceeded database I/O by about 0.42 GB. At the published Starter rate with the EU multiplier, its overage equivalent is `0.42 × $0.22 × 1.3 = $0.12012`. Other measured resources fit their Free allowances. This is a hypothetical Starter charge, not an invoice or a plan change. [Convex pricing](https://www.convex.dev/pricing), [regional pricing](https://docs.convex.dev/production/state/limits).

The September database-I/O breakdown attributes 615.29 MB to `library:listCollectionProgressSummaries`, 365.31 MB to `collections:getOutline`, 168.12 MB to `hadiths:listByVolume`, 162.11 MB to `hadiths:upsertPage`, and 106.76 MB to `hadiths:listByCollection`, all on development. The first two account for roughly 69% of the displayed database traffic. In October, `library:listBucketPage` accounts for about 85K of 90K function calls, also on development. These are dashboard readings, not estimates. [Hadithly usage dashboard](https://dashboard.convex.dev/t/alimkhan-yergebayev/settings/usage?projectSlug=hadithly).

Source inspection explains the leading read cost. `library.ts:946` collects every complete collection outline whenever the progress query reruns. Those records include the large chapter arrays, although the query only needs totals. Android also subscribes to the progress summary globally for its widget and in Library, and both clients subscribe to full outlines for Library counts. A small materialized collection-summary record would preserve the current behavior while avoiding these repeated large reads. That repair is separate from E2; no backend plan or provider was changed by this audit.

My recommendation for the measured workload is to keep Convex, reduce these large reads, and consider Starter with spending limits if Free caps keep blocking testing. Professional's $25 base is not justified merely by this September overage. Backups and higher concurrency are separate reasons to choose it.

## Q1 read-cost repair on 2026-10-12

Q1 now uses compact `collectionCounts` for progress and removes seven unused
chapter-rich outline subscriptions from each native Library implementation.
A representative fixture proves that counts are over 100 times smaller and
produce the same progress results even after full outlines are removed.
Both readers also request existing translations in one page batch. Opening and
paging never initiate Gemini. User and notification generation share one lock.
Ordinary generation has no Search grounding or JSON repair call.

The server reserves a conservative cost before provider work and settles returned
numeric token usage against a default $10 monthly application budget. Unknown or
abandoned calls retain their reservation. This preserves more usable short-text
capacity than a flat small attempt limit. Rate, concurrency, output and attempt
backstops remain. It is an application admission budget at the recorded prices,
not an invoice or cloud billing-account cap. [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).

Development deployment and compact-count backfill still need the owner's
existing action-time confirmation. No paid plan, dashboard setting, provider,
credential or hosting migration changed. The October 12 dashboard refresh reached
a sign-in page, so the readings above remain the dated October 10 audit.
No post-deployment bill reduction is claimed. See `Q1_VERIFICATION.md` for the
local proof and rollout boundaries.

The next cost work to measure is reader page materialization, indexed next-due
notification dispatch, and CDN delivery for licensed immutable offline bytes.
Those are separate scoped changes, not Q2 or part of this Q1 patch.

## Current price points

| Service | Current public price and allowance | Hadithly implication |
| --- | --- | --- |
| Convex Free | 1 million function calls, 20 action GB-hours, 0.5 GB database storage including indexes, 1 GB monthly database I/O, 1 GB file storage, and 1 GB monthly egress, shared per team. | Free has hard caps. A live subscription update, scheduled execution, and file access also count as function calls. [Limits](https://docs.convex.dev/production/state/limits). |
| Convex Starter | $0 base. Above the Free allowances, listed US rates are $2.20 per million calls, $0.33 per action GB-hour, $0.22 per database GB-month, $0.22 per database I/O GB, $0.033 per file GB-month, and $0.132 per egress GB. Non-US rates are 1.3 times those rates. | This is the likely first paid comparison, subject to measured usage. [Pricing](https://www.convex.dev/pricing), [regional note](https://docs.convex.dev/production/state/limits). |
| Convex Professional | $25 per developer per month. Includes 25 million calls, 250 action GB-hours, 50 GB database storage, 50 GB monthly I/O, 100 GB file storage, and 50 GB monthly egress; daily backups, log streaming, and exception reporting are included. | One developer's base cost is $25 before any overage and tax. [Pricing](https://www.convex.dev/pricing). |
| Clerk | Hobby: $0 and 50,000 monthly retained users per app. Pro: $25 monthly or $20 monthly billed annually, with the same 50,000 included and $0.02 per additional retained user from 50,001 to 100,000. A retained user returns at least 24 hours after signing up. | Signed-out reading incurs no Clerk retained-user charge. Clerk's billing unit differs from monthly active users. [Clerk pricing](https://clerk.com/pricing). |
| Gemini 2.5 Flash-Lite | Paid standard text input $0.10 per million tokens; output, including thinking tokens, $0.40 per million. Paid Google Search grounding includes 1,500 requests per day shared with Flash, then $35 per 1,000 grounded prompts. Free-tier requests may be used to improve Google's products; paid-tier requests are marked no. | Hadithly's current translation action requests Google Search grounding on new translations. Token cost can be tiny while a grounding burst costs more. [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing). |
| Vercel static site | Hobby $0 but restricted to personal, non-commercial use. Pro $20 per month with $20 included usage credit. | Budget $20 monthly for a commercial Hadithly site if the current site stays on Vercel; the account's actual plan was not checked. A static site's usage should be modest but is not guaranteed free. [Vercel pricing](https://vercel.com/pricing), [Hobby terms](https://vercel.com/docs/plans/hobby). |
| Cloud Run E2 processor | Request-based free tier is 180,000 vCPU-seconds, 360,000 GiB-seconds, and 2 million requests monthly, aggregated at the billing-account level and applied as a Tier 1 price discount. Tier 1 active rates are $0.000024 per vCPU-second and $0.0000025 per GiB-second; requests are $0.40 per million. `europe-west1` is Tier 1. | With 1 CPU, 1 GiB, zero minimum instances, and 20 seconds per evidence item, 1,000 items use 20,000 CPU seconds and 10,000 use 200,000. The latter is about $0.48 CPU over the free tier if the full allowance remains and other billable costs are excluded. Startup, builds, logs, registry, and network costs are not included. [Cloud Run pricing](https://cloud.google.com/run/pricing). |
| RevenueCat | Free under $2,500 monthly tracked revenue; once above, 1% of *all* tracked revenue before store commissions and taxes, not merely the portion over $2,500. | $2,600 tracked revenue means a $26 RevenueCat charge. [RevenueCat billing](https://www.revenuecat.com/docs/welcome/set-up-revenuecat/account-management). |
| Store distribution | Apple Developer Program $99 yearly. Apple Small Business Program commission is 15% if approved and eligible. Google Play registration is $25 once; subscription fees and regional rules vary, with 15% for recurring subscriptions in remaining markets and new EEA, UK, and US rules from June 2026. | Store commissions reduce subscription proceeds; they are not backend hosting charges. Do not assume Small Business enrollment or one global Play fee. [Apple membership](https://developer.apple.com/programs/), [Apple terms](https://developer.apple.com/support/terms/apple-developer-program-license-agreement/), [Play account](https://support.google.com/googleplay/android-developer/answer/6112435), [Play fees](https://support.google.com/googleplay/android-developer/answer/112622). |

The existing offline artifacts are currently generated into Convex storage. The plan allows a narrow immutable, checksummed CDN delivery exception. Cloudflare R2 Standard has 10 GB-month storage, 1 million Class A writes, 10 million Class B reads, and no internet egress charge in its monthly free tier; above that, storage is $0.015 per GB-month and reads are $0.36 per million. Moving *only* licensed offline bytes to R2 would not change the mobile API or control plane, but it is separate authorized implementation work. [R2 pricing](https://developers.cloudflare.com/r2/pricing/).

For the marketing and legal website, Cloudflare Pages offers free, unlimited static asset requests. That could remove the modeled $20 Vercel base without changing the app backend. Functions have separate limits and billing. Porkbun publishes a standard `.app` renewal price of $14.93/year; Hadithly's actual renewal invoice was not inspected. [Pages pricing](https://developers.cloudflare.com/pages/functions/pricing/), [Porkbun .app pricing](https://porkbun.com/tld/app).

Google Cloud's linked automatic billing account charges the payment method after usage, at its billing threshold or monthly billing date. This setup does not require topping up a prepaid balance. The configured E2 Cloud Run cap is $10/month; enforcement can lag and it excludes builds, image storage, and other Google services. Convex stays on its existing Free plan. A future Starter switch would add usage billing, and Professional would add its developer subscription. No Convex upgrade was made. [Google billing cycle](https://cloud.google.com/billing/docs/how-to/billing-cycle).

Gemini API in AI Studio can have a separate Prepay payments account under the same Cloud Billing account. It then needs purchased credits, with a $10 minimum, before paid Gemini usage. Hadithly's actual Gemini charging cycle and balance were not read back. E2's scanner and OCR use no Gemini calls and needed no prepaid top-up. [Google split charging cycles](https://docs.cloud.google.com/billing/docs/how-to/billing-cycle), [Gemini billing](https://ai.google.dev/gemini-api/docs/billing).

## Repository cost multipliers worth measuring

These are code-path observations, not proof of which Convex meter hit the cap.

1. **The daily push cron has a fixed call floor.** `backend/convex/crons.ts:16-21` runs every 15 minutes. When APNs or FCM is configured, `actions/daily.ts:602-615` enters `runDuePushes`, which walks all 96 quarter-hour buckets (`lib/notifyContent.ts:82-93`) and invokes `library:listBucketPage` at least once per bucket (`actions/daily.ts:442-459`). At 30 days, that is 96 cron runs/day × 96 bucket queries × 30 = **276,480 internal queries**, plus 2,880 cron actions, before due-token work. This is roughly 28% of the Free call allowance. It does not apply when neither push provider is configured. E2 adds two five-minute crons and hourly cleanup, roughly another 18,720 scheduled calls monthly before their internal work (`crons.ts:23-44`). Convex counts scheduled executions and internal calls under function-call usage. [Convex limits](https://docs.convex.dev/production/state/limits).
2. **A reader page reads the whole cached volume.** `actions/hadithData.ts:144-164` calls `hadiths:listByVolume`, which `.collect()`s all cached hadith rows in that volume (`hadiths.ts:159-178`), then chunks and returns only the selected page (`actions/hadithData.ts:248-267`). Every page turn repeats the volume read. This can amplify database I/O and Node action time even when Sunnah.now is never called.
3. **The first page visit can ingest an entire volume.** If the cache count is below the outline count, `actions/hadithData.ts:168-190` fetches the volume and upserts every hadith. `hadiths:upsertPage` patches existing rows too (`hadiths.ts:64-121`). Repeated partial-count mismatches could repeat the work. Both clients prefetch forward and quietly warm up to two adjacent volumes (`ios/Hadithly/Features/Reader/ReaderModel.swift:805-830`; `android/app/src/main/kotlin/com/hadithly/app/features/reader/ReaderViewModel.kt:657-683`). The iOS Library entry also warms the outline and target first page (`ReaderR6Round3.swift:392-417`). A single tester can therefore populate far more content than the visible page.
4. **Non-English page opening may call Gemini for every hadith on that page.** `ios/Hadithly/Features/Reader/ReaderModel.swift:835-875` loops through the page; Android calls `scheduleTranslationsForCurrentPage` after page load and settlement (`ReaderViewModel.kt:565-569, 633-650`). The backend checks a shared cache first (`actions/ai.ts:134-158`), but each miss invokes `gemini-2.5-flash-lite` with `googleSearch` (`actions/ai.ts:183-192`) and may call a repair model on malformed JSON (`actions/ai.ts:194-198`). The plan already identifies whole-page generation for removal in Q1. This is a call, model, and grounding risk, not merely a UI matter.
5. **Evidence files travel twice through Convex.** E1 uploads files to private Convex storage; E2's `actions/evidenceProcessing.ts:89-95` reads each blob and sends it as base64 JSON to the Cloud Run worker. Base64 is about 4/3 the binary size. Convex documents file access and outgoing fetch egress as billable categories. At 10,000 items averaging 1 MB, the processor request bodies alone are roughly 13.3 GB before HTTP overhead; the first storage read also consumes file egress. [Convex file limits](https://docs.convex.dev/production/state/limits), [usage metrics](https://docs.convex.dev/production/usage-limits).
6. **Offline downloads remain an egress multiplier.** O1 produces content artifacts in Convex storage (`docs/PLAN.md` O1 and O2 records). The recorded Bukhari development artifact is 1,544,910 bytes for 635 cached hadiths; the full catalog can grow as content is cached. Measure actual manifest sizes and download counts before projecting. Every fresh device, update, and retry may download the immutable bytes. The planned R2 exception addresses this data-plane cost without replacing Convex.

The repository's `convex-test` unit suite runs locally. It is not evidence of deployed production demand. Signed-in device, live UI, provider, webhook, OCR, and dashboard tests can touch development or production deployments. The dashboard is needed to separate that test traffic by function and meter.

## Two illustrative monthly scenarios

These quantities are invented to show the bill formula. They are not measured Hadithly usage. Convex resource quantities aggregate development and production on one team. The EU factor is applied to Starter overage prices. Search usage, separate cloud build and registry charges, taxes, provider API fees, external monitoring, email, and offline CDN charges are omitted.

| Assumption | Small launch | Medium launch |
| --- | ---: | ---: |
| Convex function calls | 2 million | 10 million |
| Database I/O | 10 GB | 50 GB |
| Convex egress | 5 GB | 30 GB |
| Database storage incl indexes | 1 GB | 5 GB |
| File storage | 2 GB | 10 GB |
| Action compute | 30 GB-hours | 100 GB-hours |
| E2 worker items, 20 seconds each | 1,000 | 10,000 |
| Paid Gemini 2.5 Flash-Lite generations | 500 | 10,000 |
| Convex Starter, US list rates | $8.15 | $62.10 |
| Convex Starter, 1.3× EU overage estimate | **$10.60** | **$80.72** |
| Convex Professional, one developer and within inclusions | $25 | **$25** |
| Gemini tokens at 2,000 input and 500 output tokens each | $0.20 | $4.00 |
| Cloud Run active compute after unused free allowance | $0 | ~$0.48 |
| Vercel commercial Pro base | $20 | $20 |
| Apple membership amortized monthly | $8.25 | $8.25 |
| Illustrative total using cheaper Convex plan | **~$39.05/month** | **~$57.73/month** |

Formula: Starter small at US rates is `(2−1)×2.20 + (10−1)×0.22 + (5−1)×0.132 + (1−0.5)×0.22 + (2−1)×0.033 + (30−20)×0.33 = $8.151`; multiply metered amount by 1.3 for EU. Medium Starter uses the same formula and equals $62.095 US. Professional's listed inclusions cover both scenarios, so one seat is $25 before tax. Gemini token cost per generation is `2,000×$0.10/1M + 500×$0.40/1M = $0.0004`; this excludes paid grounding. The 10,000 E2 items use 200,000 vCPU-seconds at 20 seconds each; with the full 180,000 free seconds available, 20,000 excess seconds × $0.000024 = $0.48. Cloud Run's free discount is shared across a billing account, and cold starts, logs, registry, network, and different execution times change the figure. [Convex pricing](https://www.convex.dev/pricing), [Convex regional multiplier](https://docs.convex.dev/production/state/limits), [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing), [Cloud Run pricing](https://cloud.google.com/run/pricing).

Grounding sensitivity matters more than those token estimates. At 3,000 grounded prompts in a single day after the 1,500/day included paid-tier allowance, the extra 1,500 × $35/1,000 is $52.50 for that day. This assumes those prompts actually incur the grounding charge. The current action requests `googleSearch` for each generation. Check provider usage and response metadata before treating the model column above as a forecast. [Gemini pricing](https://ai.google.dev/gemini-api/docs/pricing).

## Backend alternatives and migration cost

| Option | Published starting point | What Hadithly would need |
| --- | --- | --- |
| Stay on Convex Starter or Professional | Starter $0 base plus overage; Professional $25/developer/month. | Measure the limiting resource and reduce the hot paths above. This preserves current SwiftUI and Compose repositories, Clerk JWT auth, private mutations, live queries, crons, and evidence state machine. [Convex pricing](https://www.convex.dev/pricing). |
| Supabase | Free: 500 MB database, 5 GB egress, 1 GB files, 50,000 auth MAU, and idle project pausing after a week. Pro starts at $25/month, with 8 GB database, 250 GB egress, 100 GB files, and 100,000 auth MAU. | PostgreSQL schema/data migration, RLS for every private table and file, rewrites of actions, crons, live queries, upload/quarantine, and both native clients. Clerk can remain via Supabase's current third-party Clerk auth integration, but Supabase may count third-party MAU separately. This is not a drop-in Convex replacement. [Supabase pricing](https://supabase.com/pricing), [Clerk integration](https://supabase.com/docs/guides/auth/third-party/clerk). |
| Firebase Firestore plus Cloud Functions | Firestore's free tier: 1 GiB stored, 50,000 reads/day, 20,000 writes/day, 20,000 deletes/day, and 10 GiB egress/month. Beyond that, region-specific document and index-read charges apply; Functions have a separate allowance and charges. | Rebuild query model and indexes, security rules, functions, scheduled work, file safety, and native data flow. Firestore listeners bill document reads on updates and reconnects. Clerk would need secure token bridging or a deliberate auth migration. [Firestore billing](https://firebase.google.com/docs/firestore/pricing), [Firebase pricing](https://firebase.google.com/pricing), [custom tokens](https://firebase.google.com/docs/auth/admin/create-custom-tokens). |
| Cloudflare Workers plus D1 and R2 | Workers Paid minimum $5/month, 10 million requests/month included, then $0.30/million plus CPU time. D1 Free includes 5 million rows read/day, 100,000 written/day, and 5 GB storage; Paid includes 25 billion reads and 50 million writes/month, then metered rows. R2 has free egress and 10 GB-month free storage. | Build and operate a new API, authorization, subscription or polling semantics, relational migration, background jobs, and native clients. Workers' 128 MB memory limit is unsuitable for the ClamAV/OCR process, so E2 still needs a separate worker. [Workers pricing](https://developers.cloudflare.com/workers/platform/pricing/), [D1 pricing](https://developers.cloudflare.com/d1/platform/pricing/), [Workers limits](https://developers.cloudflare.com/workers/platform/limits/), [R2 pricing](https://developers.cloudflare.com/r2/pricing/). |
| Managed Postgres plus custom API | Neon announced 1 GB per Free project in October 2026 and $0.106 per CU-hour for Launch compute after a 2025 reduction; Railway Hobby has a $5 monthly minimum with $5 usage credit. Those are database/hosting prices, not a complete mobile backend. | Own every API, Clerk verification, user authorization, real-time transport, queues, cron, blob storage, backups, deployment, and security operations. That engineering and maintenance cost is likely larger than modest Convex overage. [Neon free change](https://neon.com/blog/neon-free-plan-1-gb-per-project), [Neon compute price](https://neon.com/blog/major-compute-price-reduction-on-neon), [Railway plans](https://docs.railway.com/pricing/plans). |

Hadithly's current product contract says Convex is the only mobile API and control plane. A full backend migration would need an owner decision to change that contract and a staged export, identity mapping, cutover, rollback, and iOS/Android parity gate. Convex supports database export; an export is only the beginning of this work. [Convex import/export](https://docs.convex.dev/database/import-export/).

## Data needed to choose a plan

Collect a 30-day or current-cycle usage report by resource, deployment, and function, with no user content: total function calls; top functions; database I/O; database storage and indexes; file storage and file egress; action GB-hours; search use; and the dates on which Free warnings fired. Split development from production. Record number and total bytes of offline downloads, volume fetches/upserts, daily push invocations, Gemini generations and grounded prompts, and E2 processor requests. Then re-run the table above using those measured quantities. If one dimension dominates, fix or move that data path before changing the whole backend.

## Costs not yet attributed

The domain's actual renewal invoice, the current Vercel plan, Sunnah.now provider terms or paid allowances, and Gemini's app-specific billed usage were not read back. Store memberships and subscription commissions are separate from backend hosting. Optional monitoring and support services should enter the budget when their launch sessions configure them. No subscription, backend upgrade, or migration was purchased during this audit.
