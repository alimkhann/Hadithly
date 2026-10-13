# App privacy response draft

This is an implementation-derived worksheet, not a published legal statement.
It covers data stored by Hadithly and the integrated Clerk, Convex, RevenueCat,
Apple Push Notification service, Firebase Cloud Messaging, Gemini, and
Sunnah.now services. Recheck provider behavior immediately before publishing.

Hadithly does not contain ads and does not use data for third-party advertising
or cross-company tracking.

## LA2 disclosure candidate

The new binary includes device-local grouped usage measurement, independently
controlled by Settings, Privacy & data, Share private usage statistics. No native
analytics vendor SDK or stable installation identifier is installed. Convex
receives hour-rounded count summaries and a 24-hour batch-deduplication UUID;
PostHog EU receives only settled daily platform counts. No account linking,
locale, content identifiers, text, searches, notes, evidence or purchase identity
enters analytics. Assess unlinked Product Interaction for Analytics against the
actual distributed binary and provider configuration. Do not mark it Tracking.
Production activation, a jurisdiction-appropriate disclosure/consent basis and
the effective published policy remain release gates. Policy prose is not consent.
Already accepted aggregate counts have no account binding and are not removable
as a person's history. Opt-out/deletion remove queued device data; anonymous
receipts expire and are physically purged by bounded hourly cleanup. See
`docs/LA2_DESIGN.md` for exact retention and limitations.

| App Store data type | Linked to user | Tracking | Purpose | Why |
| --- | --- | --- | --- | --- |
| Name | Yes | No | App Functionality | Optional profile name from Clerk |
| Email Address | Yes | No | App Functionality | Account authentication and sync |
| User ID | Yes | No | App Functionality | Clerk/Convex/RevenueCat account association |
| Device ID | Yes | No | App Functionality | APNs/FCM delivery token and purchase-service installation identity |
| Purchase History | Yes | No | App Functionality, Analytics | Subscription entitlement, restore, and aggregate subscription analytics |
| Other User Content | Yes | No | App Functionality | Private notes, translation proposals, and report reasons |
| Product Interaction | Yes | No | App Functionality, Product Personalization | Bookmarks, favorites, reading position, language and notification preferences |

AI translation inputs include the hadith text, target language, and, for a
community proposal, the contributor's proposed translation. The Gemini request
does not include the user's email or display name. Provider retention and model
training settings must be verified in the production Google project.

Items to verify in App Store Connect before clicking Publish:

- whether Clerk or RevenueCat's production configuration adds diagnostics or
  additional identifiers beyond the types above;
- whether Apple considers the push token and RevenueCat installation identifier
  under Device ID for this exact binary;
- that every type is marked not used for tracking;
- that account deletion removes Clerk and Convex records and that the documented
  RevenueCat deletion/retention process is accurate;
- that the public privacy policy matches these answers.
