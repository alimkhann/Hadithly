# Optional reading-tip email drafts

The owner requested retention email designs during LA3 on October 14. These
drafts extend the original session's design scope. They do not activate sending
or change Clerk authentication mail.

Preview `email-drafts/index.html`. Regenerate the three HTML and plain-text
messages with `python3 scripts/build-la3-email-drafts.py`.

| Time from optional email consent | Subject | Purpose |
| --- | --- | --- |
| Day 0 | A quieter place to read | Explain private bookmarks with one app-opening action |
| Day 4 | Take a collection with you | Explain verified offline downloads |
| Day 12 | Make your reading space your own | Explain text size and appearance; offer support |

The visual direction is a warm paper page, dark green ink, serif headline, and
one concise tip. Email HTML uses presentation tables, inline styles, local font
fallbacks, and live text. It includes no image requests, remote fonts, tracking
pixels, shortened links, personalized reading history, urgency, streaks, rewards,
guilt, pricing campaign, religious quotation, or invented authenticity claim.
Plain text carries the same message and action.

Activation contract for a later explicitly approved implementation:

- Offer a separate unchecked choice for this finite three-message series. Clerk
  account creation, analytics consent, and support intake are not email consent.
- Verify address control and keep consent version, source, timestamp, withdrawal,
  and a dedicated suppression record. Schedule from consent time alone. LA2's
  anonymous aggregate totals cannot support individual inactivity triggers.
- End the chain after message three. No silent weekly or evergreen continuation.
- Check consent and suppression again immediately before delivery. Signing out
  does not imply fresh consent; account deletion ends the series. Never re-enroll
  a suppressed address because the person contacts support or creates an account.
- Replace `{{unsubscribe_url}}` with an expiring, purpose-bound HTTPS link and
  implement a durable one-click unsubscribe path. Do not ship literal placeholders.
  Add approved sender/footer information and localization before sending.
- Use a separate marketing sending identity and budget, including bounce/complaint
  handling. Keep operator mail independent of marketing suppression and vice versa.
  The current LA3 sending key/template cannot send these recipient-selected drafts.
- Read back tracking disabled and render each final message in actual email
  clients, including dark mode, large text, and image-blocking behavior. Browser
  previews are visual draft evidence, not inbox compatibility or deliverability.

Resend can host these templates later, but its free quota is shared across the
current team and inbound mail. Three messages for 1,000 consenting people would
use 3,000 deliveries before transactional mail, bounces, or retries. Keep LA3's
operational allowance reserved. Do not activate a chain without a recipient-count
and daily/monthly admission plan. No contacts, broadcasts, chains, new provider
credentials, or paid upgrades were created for these drafts.
