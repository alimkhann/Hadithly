# Activate the tested LA3 candidate

Local implementation and separate security/cost review are complete. These are
the concrete pending external actions. Use the owner's operational mailbox
provided in the current chat, keep credentials private, and retain every earlier
gate. No paid upgrade, production Convex deployment, real-user export/restore,
marketing activation, or git push is part of this candidate.

1. Redirect only `support@hadithly.app` from the earlier mailbox to the requested
   Gmail mailbox in Porkbun. Preserve existing MX/SPF and all other routes.
2. Add `updates.hadithly.app` to the existing Resend Free team. Disable open and
   click tracking, keep paid overages off, and obtain a sending-only key restricted
   to that domain. Create one signed webhook for delivered, bounced, and complained
   operational messages. Respect the account's one-webhook limit and do not replace
   another project's existing webhook. If the slot is occupied, resolve isolation
   with the owner instead of silently replacing it or buying capacity.
3. Add only Resend's generated public DKIM and return-path SPF/MX DNS records to
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
8. Add a $30 monthly all-services alarm for the Hadithly Google project at 50%,
   80%, 100%, plus forecast warning. Keep its existing $10 Cloud Run cap and app
   $10/$2 translation reservations. A budget is not permission to spend and its
   reporting delay is not a hard no-overshoot guarantee. Do not disable billing
   for the owner's whole account. Read back scope and actual alert recipient.
9. Obtain remaining provider plan/free-boundary/limit and recipient readbacks.
   Convex's browser login currently requires GitHub OAuth read-profile/email
   authorization. Do not grant new permissions silently. Vercel commercial hosting,
   Sunnah.now contractual allowance, and production backup scheduling remain owner
   decisions even after development email proof.

Action-time approval is required by the owner's recorded Hadithly credential,
deployment, cloud, and billing boundaries. Signing into the dashboards establishes
access for inspection, not permission for every credential or service change.
If the owner is unavailable, keep this candidate disabled and commit the finished
implementation with these exact gates open.
