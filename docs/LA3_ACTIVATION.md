# LA3 bounded activation record

The owner approved this bounded activation in chat on October 14, 2026.
The actions below have completed within that approval; see
`LA3_LIVE_EVIDENCE.json` and `LA3_VERIFICATION.md` for the results. This is a
historical action boundary, not permission to repeat sends or expand scope.
No paid upgrade, production Convex deployment, real-user export/restore,
marketing activation, or git push was authorized or performed.

1. Redirect only `support@hadithly.app` from the earlier mailbox to the requested
   Gmail mailbox in Porkbun. Preserve existing MX/SPF and all other routes.
2. Add `updates.hadithly.app` to the existing Resend Free team. Disable open and
   click tracking, keep paid overages off, and obtain a sending-only key restricted
   to that domain. Create one signed webhook for delivered, bounced, and complained
   operational messages. Respect the account's one-webhook limit and do not replace
   another project's existing webhook. If the slot is occupied, resolve isolation
   with the owner instead of silently replacing it or buying capacity.
3. Add only Resend's generated public DKIM and return-path SPF DNS records to
   Porkbun, plus monitoring DMARC at `_dmarc.updates`. Inventory Clerk before an
   owner-approved apex DMARC policy. Never replace an existing SPF record blindly.
4. Create a free Turnstile widget limited to `hadithly.app`, with `support` action
   validation. Keep its secret and a new rate HMAC secret only in Convex. Its
   public site key belongs in `site/operations-config.js`.
5. Deploy the reviewed schema/functions only to `festive-cobra-664`, and configure
   `operations.env.example` values privately. Start with support/mail disabled.
   Confirm fixed recipient, tracking-off domain, webhook signature, provider quota,
   and suppression behavior before enabling them for bounded synthetic proof.
6. Send at most three synthetic owner-only operational messages. Submit one real
   protected form with self-authored text, inspect the owned private request and
   notification, and retain only safe results. Obtain received SPF/DKIM/DMARC
   header evidence. API success or provider delivered status is insufficient.
7. Publish only the reviewed LA3 support/status files and required assets to the
   existing static site, preserving unrelated pending policy/fallback changes.
   Verify its five components and explicitly synthetic incident from the public
   URL. Add an optional status subdomain only if needed.
8. Add a $30 monthly all-services alarm across the two Hadithly Google projects at 50%,
   80%, 100%, plus forecast warning. Keep its existing $10 Cloud Run cap and app
   $10/$2 translation reservations. A budget is not permission to spend and its
   reporting delay is not a hard no-overshoot guarantee. Do not disable billing
   for the owner's whole account. Read back scope and actual alert recipient.
9. Read back provider boundaries without changing plans. Convex reads Free;
   existing Vercel Hobby and shared Resend Free boundaries remain. Remaining
   Clerk/RevenueCat/Sentry account invoice readbacks, Sunnah.now's broader contract,
   commercial hosting eligibility, and production backup scheduling remain release
   gates in the ledger. No paid limit is invented where evidence is absent.

Private credentials were installed directly into the development environment;
no secret values were saved in repository files or evidence. An automatic login
URL briefly exposed an expiring OIDC callback token in tool output. It expired
before handoff and was not retained in artifacts or commits. Long-lived sending,
webhook, Turnstile, and rate keys were kept out of outputs. The operating-system
clipboard was cleared after credential installation.

Exactly three synthetic emails consumed the approved test allowance. Do not run
`backend/scripts/verify-la3-routing.mjs --send` again without a fresh bounded test
authorization. No further activation is required to reproduce the local tests.
