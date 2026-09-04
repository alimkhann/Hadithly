# App Store Connect handoff

This directory contains the English (U.S.) launch metadata draft for iOS
0.1.0. It intentionally contains no screenshots.

## App record

- Name: Hadithly
- Bundle ID: `com.hadithly.app`
- SKU: `hadithly-ios` (the immutable value in App Store Connect)
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

1. Enter the published support and privacy-policy URLs in App Store Connect.
2. Finish agreements, tax, and banking, then connect the existing
   `com.hadithly.app.pro.monthly` and `com.hadithly.app.pro.annual` products to
   RevenueCat's `pro` entitlement and current offering. Do not add a weekly
   production product.
3. Supply an App Review account that can reach the quota paywall, plus exact
   product IDs and subscription durations in `en-US/review_notes.txt`.
4. Complete the privacy questionnaire from `app-privacy.md`, checking the
   shipped Clerk and RevenueCat SDK privacy manifests before publishing.
5. Complete age rating, content rights, and encryption/export-compliance. The
   app is already free, available in all regions, and set to manual release.
6. Add screenshots in the dedicated later design session. None are prepared or
   included here by request.

Placeholders are written in square brackets and must never be submitted.

## URLs

- Privacy policy: `https://hadithly.app/privacy/`
- Support: `https://hadithly.app/support/`
- Marketing: `https://hadithly.app/`
- Terms of Use: Apple's standard EULA unless a custom EULA is adopted
