# LA3 verification

October 14, 2026, Asia/Almaty. LA2's scoped development implementation, aggregate
provider readback, and privacy review passed. Its full physical-device, account,
store, legal, and production gates remain open. The owner requested LA3 with GPT
6.1 Sol High and a separate delivery-security/cost review. Only LA3 runs here.
Stop before L1.

## Local proof

- Backend typecheck and 346 tests passed. Thirteen new LA3 tests exercise the actual
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
  and whole-month warning deduplication. A second final activation review passed
  with 81 focused tests/typecheck after pinning the routing script deployment.
  See `LA3_REVIEW.md`.
- Both native apps already use `https://hadithly.app/support` and
  `support@hadithly.app` in their S1 Help & Support contracts. LA3 adds shared web
  behavior with an explicit no-change native parity check. No SDK, navigation,
  auth, purchase, reader, or local data changes were made on either native app.
  Full physical browser/accessibility and localized form copy remain release work.

## Approved live proof

The owner approved `LA3_ACTIVATION.md` in chat and asked to finish while away.
Only that bounded activation ran. Safe structured results are in
`LA3_LIVE_EVIDENCE.json`; cropped screenshots are in `evidence/la3/live-*.jpg`.

- Porkbun now forwards `support@hadithly.app` only to the selected Gmail mailbox.
  A controlled message reached that mailbox. The earlier support destination was
  removed; apex MX/SPF and Clerk's existing DNS records were preserved.
- Resend's EU `updates.hadithly.app` domain is verified. A sending-only key is
  restricted to that domain. Received original headers show aligned SPF, DKIM,
  and DMARC **PASS**, TLS 1.3, and plain-text MIME. No tracking pixels or tracking
  subdomain are used. Free usage is 35/3,000 monthly and 3/100 daily; paid overages
  are disabled. These are shared-team allowances.
- Exactly three approved synthetic messages were sent: the operational test,
  the real support form's reference-only operator notice, and the support-alias
  forwarding test. No engagement message or real-user message was sent.
- The public form passed real Managed Turnstile verification for `hadithly.app`
  and action `support`. The private record matched the self-authored body and
  fake `example.invalid` contact; its reference-only notice reached the operator.
  Signed provider delivery returned 204 and the notice became delivered. The
  synthetic request was deleted; the temporary verification function was removed
  and development redeployed. Coarse attempt counters remain for quota accounting.
- The shared Free Resend webhook ignores other senders with 204 before database
  lookup. It accepts only the fixed operational sender; unknown IDs from that
  sender retain retry behavior. Thirteen route/policy tests include this isolation.
- Development schema/functions and private configuration are active only on
  `festive-cobra-664`. Its HTTP URL includes `eu-west-1`; the bare hostname fails.
  Convex billing reads Free. Production Convex was not changed.
- `https://hadithly.app/status/` visibly renders five components and a resolved,
  explicitly synthetic exercise. Stale assessment makes availability unknown.
- Static production deployment `dpl_GwA7h6AXgWW4xSKLqqDBVo7WFY9W` is READY.
  Publication overlaid only approved support/status files on the existing
  `54f78ca9b0c6a51f9133fdc936069d99bb187f30` site's baseline. Final byte comparison
  preserved home, privacy, terms, deletion, and hadith fallback pages. This avoids
  publishing unrelated pending F3/LA1/LA2 policy or fallback work.
- Google has a saved $30 monthly **all-services alarm** across `hadithlyapp` and
  the recorded Gemini project `gen-lang-client-0557645035`, actual thresholds
  50/80/100%, forecast 100%, credits excluded. Its linked owner-email channel
  matches the selected mailbox; broad billing/project-owner recipients are off.
  The existing $10 Cloud Run cap remains. The new alarm is not a hard spend cap.
- Vercel remains Hobby with no card or paid upgrade. The ledger documents runtime
  free boundaries and spend controls. Remaining Clerk/RevenueCat/Sentry invoice
  readbacks, domain/membership renewals, broader Sunnah.now contract, and commercial
  hosting eligibility are recorded as release gates rather than invented limits.

## Completion boundary

LA3 implementation and the approved development/live proof are complete: support,
received transactional mail, authenticated domain, public synthetic incident,
real isolated restore, and documented provider boundaries/Google alarm all have
proof. This does not close the production operations gate. Daily encrypted
**off-device** backups, production RPO/RTO and deletion replay, production Convex
rollout, remaining provider invoice/contract readbacks and commercial hosting
remain open. The 2.1-second fixture restore is not a promise for production data.

The user later requested engagement email designs. Three optional-consent email
drafts are previewable separately. They create no contacts, sending chain,
tracking, or extra auth-email path. Sending requires a separately implemented
consent, suppression, localization, and unsubscribe contract.

Earlier H3/O2/W2/Q1/Q2, E1, physical-device, sync, widget, purchase, rights,
production activation, privacy/store, and D3/D4 gates remain open as recorded in
`OPEN_GATES.md`. No push or L1 work occurred.
