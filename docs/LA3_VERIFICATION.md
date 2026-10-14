# LA3 verification

October 14, 2026, Asia/Almaty. LA2's scoped development implementation, aggregate
provider readback, and privacy review passed. Its full physical-device, account,
store, legal, and production gates remain open. The owner requested LA3 with GPT
6.1 Sol High and a separate delivery-security/cost review. Only LA3 runs here.
Stop before L1.

## Local proof

- Backend typecheck and 345 tests passed. Twelve new LA3 tests exercise the actual
  HTTP route, strict payloads, server-side challenge validation, hostname/action
  failures, atomic admission and mail races, caps, rollover, operator identity,
  expiry, signed raw webhook bytes, stale signatures, bounce suppression, and
  monthly warnings. Provider network responses in these tests are test doubles.
- The current full schema ran on a real isolated anonymous local Convex backend.
  A ZIP export included five synthetic records and a storage file. After wiping
  them, `convex import --replace-all` restored every record and ID exactly. The
  restored file's fetched bytes matched. Recovery took about 2.1 seconds for this
  small fixture. No shared development or production data was exported or restored.
- Headless Chrome exercised the actual local pages at 390px: disabled email
  fallback, enabled synthetic form, exact serialized fields, accepted receipt,
  429 and text preservation, five components, visible synthetic incident, stale
  availability, escaped injection text, and status fetch outage all passed. Safe
  screenshots are in `evidence/la3/`. Provider network responses are fixtures.
- Three email drafts render at 390px without overflow. The desktop gallery and
  mobile welcome were captured. Drafts include no remote images, scripts, fonts,
  or tracking. Real email-client rendering remains an activation prerequisite.
- The separate delivery-security/cost review passed after repairs. The reviewer
  independently ran 80 focused tests/typecheck. Corrected issues include the actual
  AI budget key/config, paginated inbox, byte-limit queue behavior, restore isolation,
  and whole-month warning deduplication. See `LA3_REVIEW.md`.
- Both native apps already use `https://hadithly.app/support` and
  `support@hadithly.app` in their S1 Help & Support contracts. LA3 adds shared web
  behavior with an explicit no-change native parity check. No SDK, navigation,
  auth, purchase, reader, or local data changes were made on either native app.
  Full physical browser/accessibility and localized form copy remain release work.

## Current external readback

- Porkbun DNS is authoritative. Apex MX uses its forwarding service and SPF is
  `v=spf1 include:_spf.porkbun.com ~all`. No apex DMARC TXT was returned. The live
  support alias forwards to the owner's earlier Proton mailbox. The requested
  Gmail route is not yet applied or tested.
- Resend is already signed in. Current team is Free, 32/3,000 monthly and 0/100
  daily messages, one of three domains used, transactional paid overages disabled.
  The only verified domain belongs to an unrelated project. Hadithly's sending
  domain, scoped key, webhook, and disabled-tracking readback are not yet configured.
- Vercel's existing team is Hobby, no payment method, no team budget, 1M CDN
  requests and 100 GB transfer allocation shown. No upgrade was performed.
- Google budget readback confirms the existing Hadithly E2 Cloud Run monthly $10
  budget, alerts at 50%, 80%, 100%, and cap configured. Its Cloud Run-only scope
  does not cover other cloud services. All-services project alert remains open.
- Convex dashboard login reached a GitHub OAuth authorization boundary. No new
  OAuth permission was granted. The existing CLI can generate bindings. No LA3
  schema/function development rollout has run.

## Gate still open

LA3 is not passed until support forwarding and a real form request reach the
operator, one controlled transactional message is received with aligned SPF,
DKIM and DMARC passes, the synthetic status exercise is visible on a published
site, the production backup schedule/off-device recovery plan is verified, and
every active provider's free or spend boundary is read back as specified in the
ledger. The successful local restore drill closes the synthetic restore test,
not production RPO/RTO or privacy deletion replay.

The user later requested engagement email designs. Three optional-consent email
drafts are previewable separately. They create no contacts, sending chain,
tracking, or extra auth-email path. Sending requires a separately implemented
consent, suppression, localization, and unsubscribe contract.

Earlier H3/O2/W2/Q1/Q2, E1, physical-device, sync, widget, purchase, rights,
production activation, privacy/store, and D3/D4 gates remain open as recorded in
`OPEN_GATES.md`. No push or L1 work occurred.
