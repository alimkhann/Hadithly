# LA3 support, mail, status, recovery, and costs

Recorded October 14, 2026, Asia/Almaty. This is the operating contract for the
approved LA3 development activation and published static surfaces. Production
activation and backup operation remain separate gates.
L1 has not started. Earlier device, account, store, consent, rights, and release
gates stay open. See `LA3_VERIFICATION.md` for tested scope.

## Support and email

Alim owns support, incidents, recovery, and budgets. The owner supplied an
existing Gmail mailbox in this session. Keep its address in server configuration
and dashboards, not the repository. All LA3 operational notices use that one
fixed recipient. No additional operator or escalation service is required.

Porkbun is the authoritative DNS provider. Its dashboard forwards
`support@hadithly.app` only to the selected Gmail mailbox. The controlled routing
test was received there. Porkbun allows twenty free forwarding addresses.
Keep existing MX and apex SPF records. Cloudflare DNS migration and paid inboxes
are unnecessary. Inbound forwarding does not grant authenticated outbound use
of `support@hadithly.app` in Gmail.

Clerk continues to send verification, sign-in codes, password recovery, and
authentication notices. Apple, Google, and RevenueCat retain their billing
messages. LA3's only added transactional template is a support-request or budget
notification to the operator. It contains a fixed message and a support reference,
never the visitor's address, message, account, reading history, or attachments.
The support database keeps the contact address and request text privately.

To answer a form request, open the owned Convex dashboard, select development
`festive-cobra-664`, then Data → `supportRequests` and locate the emailed
`requestId`. Read only that request, reply manually to its contact address from
the selected mailbox, and apply the retention policy below. Do not export the
inbox or forward request bodies into email/CRM. The optional `support.inbox`
query requires a verified Clerk identity whose existing server user is an admin;
it accepts bounded pagination and never grants operator access from the browser.
No operator UI is added to consumer Settings.

Resend fits this scope. The live existing account is Free with 3,000 monthly and
100 daily emails, three domains, one webhook, and paid transactional overages
disabled. It has the unrelated domain plus the verified Hadithly domain and
35 emails this month, three today after the approved proof. These allowances are
shared across the account. The installed sending-only key is restricted to
`updates.hadithly.app`; do not use or alter the unrelated domain.
If independent isolation is required, create a dedicated free team only after
approval. Provider refusal must pause mail, never trigger an upgrade.

The shared web form is reached through both native Help & Support links. It
accepts only reply email, topic, platform, and up to 2,000 characters. It has no
file upload, account lookup, arbitrary recipients, HTML, or subject input.
Turnstile must verify server-side with hostname `hadithly.app` and action
`support`. A honeypot and exact origin check add defense, but are not identity
or bot guarantees. Requests never supply their Hadithly user identity.

Admission limits are atomic in Convex:

| Resource | Boundary | Response |
| --- | --- | --- |
| Challenge verification attempts | Ten per minute and 1,000 per UTC day globally | 429 before external verification |
| Support requests | Three per contact per fixed twenty-four-hour window, twenty per UTC day, 200 per UTC month globally | 429 and direct-email fallback |
| Operational email attempts | Fifty per UTC day and 500 per UTC month globally, including unknown outcomes | Pause delivery; preserve private requests |
| Ordinary AI | Existing $10 monthly reservation, with $2 free/service sub-budget | Existing cached/offline reading fallback |
| Evidence review pairs | 100 per UTC month, with at most 128 KiB packet data and 8,192 output tokens per pass | Remain private; no provider calls after exhaustion |

Evidence's monthly count is an attempt ceiling, not a verified dollar cap. Model
pricing, thinking, serialized prompt overhead, infrastructure, and other API keys
still need provider billing alarms. An ambiguous request failure consumes its
reservation. Each review attempt makes two existing no-tool model calls.

Support references deduplicate retried intake. Mail claims reserve the attempt
before the network call and use a Resend idempotency key. An ambiguous timeout
stays `attempted`. It is not automatically resent. Queued notices can resume when
configured, within the same daily and monthly limits. An accepted browser receipt
confirms database intake, not provider delivery or a reply.

## Domain authentication and delivery

The verified Resend sending domain is `updates.hadithly.app` with its generated
public DKIM and
return-path CNAME SPF records installed. Preserve these records at the dedicated
return-path host. Do not replace the apex forwarding MX or create a
second SPF TXT record at an existing host. The fixed visible sender is
`operations@updates.hadithly.app`. Keep domain open and click tracking disabled. No image tracking, contacts, broadcasts, CRM, or sending
automation is installed in LA3.

`_dmarc.updates.hadithly.app` is installed with `v=DMARC1; p=none; adkim=r; aspf=r` for
initial monitoring. Add reporting only to a verified operator-controlled report
mailbox, because reports contain third-party sender metadata. Verify Clerk's
existing sender separately before tightening apex DMARC. No apex DMARC TXT was
returned by DNS at the start of LA3. Record an owner-reviewed apex policy after
inventorying all legitimate senders. After seven days of legitimate-message
authentication checks, progress to quarantine, then reject. Keep DNS values and
header evidence, never API or webhook secrets.

Gate proof requires all of:

1. Resend domain readback says verified for SPF and DKIM.
2. The owner receives one synthetic notice.
3. The received message's original headers show SPF pass, DKIM pass, and DMARC
   pass with aligned `updates.hadithly.app`. API acceptance and a green DNS badge
   alone do not prove the third condition.
4. Signed `email.delivered`, `email.bounced`, and `email.complained` tests exercise
   `/webhooks/operations-mail`. Verify raw bytes, HMAC, and a five-minute timestamp
   tolerance. Unknown message IDs receive 503 so the provider can retry after the
   send result is bound. Unrelated webhook types and other senders are ignored with 204.
   This isolates the existing Free team-wide webhook from other projects.

A bounce or complaint on the fixed recipient permanently suppresses operational
mail until the owner verifies a working address and explicitly resets suppression.
Late delivered events cannot undo suppression. Inspect Resend's suppression list
and signed delivery outcomes. Notify through the provider dashboard or existing
Google/Sentry channels while mail is unavailable. Do not keep sending to diagnose
a suppressed mailbox. The webhook contains no stored recipient or bounce body.

Keep direct mailbox replies manual during launch. Reply from the actual existing
mailbox unless an authenticated send-as identity is separately configured. Never
assume forwarding alone makes Gmail replies come from the support address.

## Retention and support response

Support text and contact addresses expire after thirty days from intake. Rate
hashes use a secret HMAC and expire after one day. Support mail references and delivery
states expire after thirty days. Coarse budget notices expire after thirty-two
days so deduplication covers every full UTC month. Monthly review counters expire after ninety days.
The hourly cleanup drains bounded batches and filters expired inbox rows before
cleanup. No raw IP, user ID, challenge token, or webhook body is stored by LA3.
Convex and Turnstile platform request/argument retention still require the launch
privacy assessment. Do not claim that a private argument is absent from every
provider's operational logging system.

Resend's published Free retention is thirty days. Manually delete closed direct
support threads from the mailbox within ninety days after closure. This mailbox
policy is a runbook, not an automated purge. Backups can retain erased request
data within their seven-day rotation. Apply deletion records before reopening a
restored environment. Account deletion ownership still belongs to Clerk and the
existing authenticated Convex path. Anonymous support records are not inferred
to belong to a Clerk account. A separate support erasure request verifies control
of the contact address and removes matching requests and inbox copies.

Response target is two business days. Escalate account takeover, unintended
private-data disclosure, widespread sign-in failure, failed deletion, purchase
ownership, or unexpected bills immediately to the owner. Do not request passwords,
one-time codes, receipts with payment tokens, reading notes, or evidence by email.

Support response template:

> Thanks for contacting Hadithly. We received your request, reference [reference].
> Please share your platform and app version if you have not already included
> them. Do not send passwords, sign-in codes, private notes, or payment details.
> For cancellation or refunds, use the store account that made the purchase.

## Status and incidents

`site/status/` is a static operator update page on the existing host. It has five
components: Website, Reading API, Sign-in, Notifications, and Translation. It
does not call Gemini, publish usage, or expose the database. The page renders
data as text. Updates older than thirty minutes, future timestamps, and fetch
failures make current availability unknown. A displayed past incident remains
historical, not evidence of present availability. The synthetic incident is
explicitly marked Exercise and does not announce a real outage.

The approved page is published at `/status/`; an optional `status.hadithly.app` alias can use the same
static project after approved DNS/domain setup. Do not add Better Stack merely
for this page. LA1 already has four Google uptime checks and owner email alerts.
The static host survives a Convex/provider outage but shares the website hosting
failure domain. During a host outage, use direct support email and the provider
status pages. No independent-host status promise is made.

Incident template fields are ID, UTC start, affected component, investigating,
identified, monitoring or resolved state, impact, mitigation, resolution, and
resolution time. Publish within thirty minutes of confirming a material outage.
Update at least every thirty minutes while unresolved. Never publish names,
account IDs, private data, receipts, stack traces, or an unsupported recovery ETA.
Only mark operational after the actual user-facing function is verified.

| Outage | User fallback | Operator response |
| --- | --- | --- |
| Convex or Sunnah.now | Existing cached/downloaded reading; syncing and fresh content can pause | Publish impact, avoid refresh storms, check owned health probes |
| Clerk | Guest reading; no second auth system | Use Clerk's status and recovery, preserve pending auth state |
| Gemini or review budget | Cached translations; new translation unavailable; evidence stays private | Disable new paid calls, inspect quota and provider status |
| RevenueCat or store | Existing server-confirmed access; no invented entitlement | Follow Q2 reconciliation, original-account restore and store support |
| APNs or FCM | In-app Today and cached content | Follow N1 bounded retries and stale-token removal |
| Resend or Turnstile | Direct support email; form fails closed | Check inbox and provider dashboard; preserve accepted private requests |
| Static host or DNS | Installed cached/downloaded reader and direct email | Use registrar/host recovery; status page may also be unavailable |

## Recover from a backup

Targets for launch are an RPO of twenty-four hours and an RTO of four hours.
These are objectives, not proven guarantees. RTO includes operator availability,
schema/code recovery, identity checks, file restoration, and native readback.
While one operator sleeps, automated daily backup or an approved external job is
required to meet a reliable daily RPO. No recurring cloud job was provisioned here.

Convex backups are consistent table snapshots and can include file storage.
They exclude code, environment variables, schedules, and deployment configuration.
Free/Starter retain at most two manual backups for seven days. Managed periodic
backups require Pro. Choose approved managed daily backups or a disciplined daily
encrypted off-device export before production launch. Never upgrade automatically.

Use `npx convex export --include-file-storage --path <private-path>` against the
explicit approved deployment. Encrypt the ZIP before copying off-device. Keep
encryption keys separate in the owner's password manager. Keep daily exports for
seven days, and remove unencrypted temporary files after verification. Backups
contain real personal data, so never put them in git, email, screenshots, or chat.
Retain only file hashes, counts, dates, scope, and recovery results as evidence.

For an incident restore:

1. Suspend scheduled work and new writes. Snapshot the current bad state privately.
2. Restore the chosen snapshot into an isolated approved deployment first.
3. Deploy the matching known-good git commit and configure secrets separately.
4. Verify private ownership, Saved/progress references, file bytes and licenses.
5. Apply account/support/evidence deletion and revocation records newer than the
   snapshot. Reconcile subscriptions against live RevenueCat before paid access.
6. Keep mail, analytics, pushes, processing, and model calls disabled during the
   drill. Scheduled jobs and reservations cannot be assumed recovered.
7. Obtain specific action-time approval before destructive production import or
   cutover. Take a fresh snapshot and record the rollback target.
8. Verify signed-in native reads on both platforms and reopen writes deliberately.

`node scripts/drill-convex-recovery.mjs` runs real export, destructive wipe, and
ZIP import only in a new anonymous localhost deployment. It refuses any pre-existing legacy anonymous-agent state and verifies its new
project-local deployment before seeding or restoring. It copies the current
Hadithly schema, clears crons, supplies no cloud env or provider keys, and uses
five synthetic records plus one file. It compares IDs, exact records, relationships,
storage metadata, and fetched file bytes. Its temporary database and ZIP are
removed afterward. `LA3_RECOVERY_EVIDENCE.json` proves this drill, not a production
data restore or the promised RPO/RTO. Test at least quarterly and before a schema
or storage migration. The first production encrypted off-device copy is still open.

## Budget operation

`LA3_COST_LEDGER.json` records each provider, unit, boundary, evidence, recipient,
warning, stop action, and unresolved gate. Review weekly for the first launch
month, then monthly. UTC app budgets and provider billing periods may differ.
Do not equate app admission ceilings with whole-account invoice caps.

The saved Google $30 monthly all-services alarm covers both `hadithlyapp` and
`gen-lang-client-0557645035`, with credits excluded, actual 50/80/100% and forecast
100% thresholds. Only the linked **Hadithly owner email** channel is enabled and
its address matches the selected operational mailbox. Budget delivery itself was
not forced by creating a real charge. The existing Cloud Run-only $10 monthly
cap and app $10/$2 translation reservations remain. Google's reporting delay can
allow overshoot; the new all-services alarm is not a hard cap or authorization to
spend $30. Do not disable billing globally.

Application budget warnings email the fixed owner at 80% once per UTC month.
No alert can be guaranteed when its own mail cap, suppression, provider, or operator
is unavailable. Provider billing emails and dashboard checks are the independent
fallback. Clerk, Sentry and RevenueCat account invoice/recipient settings
still require current dashboard readback where the ledger says open. Convex Free
and whole-project Google scope/recipient have been read back. Vercel's
current Hobby plan has no team budget and no payment method. Commercial hosting
eligibility must be resolved before launch. No paid upgrade is authorized here.

Sources checked for LA3:

- [Convex backup and restore](https://docs.convex.dev/database/backup-restore)
- [Convex export](https://docs.convex.dev/database/import-export/export)
- [Convex usage limits](https://docs.convex.dev/production/usage-limits)
- [Resend pricing](https://resend.com/pricing)
- [Resend domain authentication](https://resend.com/docs/dashboard/domains/introduction)
- [Resend webhook verification](https://resend.com/docs/webhooks/verify-webhooks-requests)
- [Turnstile server verification](https://developers.cloudflare.com/turnstile/get-started/server-side-validation/)
- [Vercel spend management](https://vercel.com/docs/spend-management)
