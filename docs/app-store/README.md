# App Store Connect handoff

This directory contains the English (U.S.) launch metadata draft for iOS
0.1.0. It intentionally contains no screenshots.

## App record

- Name: Hadithly
- Bundle ID: `com.hadithly.app`
- SKU: `hadithly-ios-001`
- Primary language: English (U.S.)
- Primary category: Reference
- Secondary category: Books
- Price: Free, with monthly and annual auto-renewable subscriptions for
  additional AI translations
- Version: 0.1.0
- Copyright: `2026 [LEGAL NAME REQUIRED]`

Apple currently limits the name and subtitle to 30 characters, promotional
text to 170 characters, description to 4,000 characters, and keywords to 100
bytes. The files in `en-US/` are checked by `scripts/check-app-store-metadata.sh`.

## Required before submission

1. Publish real support and privacy-policy pages. Enter their public HTTPS URLs
   in App Store Connect and replace the placeholders below.
2. Create the app record for `com.hadithly.app` if it is still only staged in
   the creation dialog.
3. Create the USD 2.99 monthly and USD 24.99 annual subscription products,
   finish agreements, tax, and banking, and connect them to RevenueCat's `pro`
   entitlement and current offering. Do not add a weekly production product.
4. Supply an App Review account that can reach the quota paywall, plus exact
   product IDs and subscription durations in `en-US/review_notes.txt`.
5. Complete the privacy questionnaire from `app-privacy.md`, checking the
   shipped Clerk and RevenueCat SDK privacy manifests before publishing.
6. Complete age rating, content rights, encryption/export-compliance, pricing,
   territories, and release mode. Use manual release for the first version.
7. Add screenshots in the dedicated later design session. None are prepared or
   included here by request.

Placeholders are written in square brackets and must never be submitted.

## URLs

- Privacy policy: `[PUBLIC PRIVACY URL REQUIRED]`
- Support: `[PUBLIC SUPPORT URL REQUIRED]`
- Marketing: optional; leave blank until a real page exists
- Terms of Use: Apple's standard EULA unless a custom EULA is adopted
