# Live language-switch repair

2026-10-12. Owner-requested follow-up while finishing Q1/E2. No Q2 or full
LA1 localization session started.

## Reproduction and causes

Captured the owner's running iPhone 16 Pro with `devicectl device capture
screenshot` before installing changes: `/tmp/hadithly-rtl-proof/iphone-before.png`.
English Today headings appeared at the right and tabs were mirrored. Read only
the saved reader preference fields: `uiLocale=ar`, `translationLocale=en`,
`readingDirection=ltr`. The Arabic interface preference was legitimate; English
translation and reader direction do not control app chrome.

The actual defect was mixed untranslated chrome in an Arabic layout. Main shell
labels lacked Arabic/Urdu catalog entries. Settings row/title Strings also skipped
localized-key lookup. A second physical regression showed that the picker
navigation title retained its previous language after a live locale change.

## Repair

Added Arabic/Urdu shell and Settings destination labels on both apps. iOS dynamic
Settings labels use localized keys; navigation titles explicitly resolve the
current locale's compiled bundle with exact/base/English fallback. Today's date
uses the selected interface locale. Guest greeting/copy also resolve locally.
Android shell, headers and Settings titles use its existing reactive localized
resource provider. Changing app language still preserves translation language,
navigation and reading state. Arabic hadith blocks remain RTL inside English UI.

Left the owner's app and translation preferences in English as requested. Other
reader preferences remain unchanged. This is a bounded repair of the reproduced
language switch; complete Wave 1 translation and native-speaker review remain LA1.

## Actual proof

- Physical iPhone and simulator test both failed on the missing Arabic shell
  label before the fix: `/tmp/hadithly-rtl-before2.xcresult` and
  `/tmp/hadithly-rtl-simulator-before.xcresult`.
- The stricter physical picker-title test failed on the retained English title:
  `/tmp/hadithly-rtl-title-before.xcresult`.
- Both defects pass after repair on the actual iPhone, including Arabic RTL tab
  order and English LTR restoration: `/tmp/hadithly-rtl-final.xcresult`.
- Android's installed live language-switch test passes: one test, zero skips,
  `/tmp/hadithly-language-android-live.log`. It also proves translation preference
  is unchanged and both picker/destination titles localize.
- iOS final unit suite has 225 passes, four separately opt-in live skips and zero
  failures; compiled-bundle tests resolve Arabic/Urdu/English and fallback titles.
  Android build and 195 unit tests pass.
- Final physical suite adds an actual Urdu translation switch while English
  chrome stays LTR: both language tests and four Q1 reader UI cases pass, zero
  skips/failures, `/tmp/hadithly-q1-phone-final.xcresult`. Android's final four
  Q1/language cases pass in `/tmp/hadithly-q1-android-final-ui.log`.
- The language-count footer also retains its localized plural key; the final
  installed two-language-test rerun passes in
  `/tmp/hadithly-language-footer-final.xcresult`.

Screenshots were exported from the physical result into
`/tmp/hadithly-rtl-proof/final/`; `language-english-restored.png` and
`language-arabic-picker.png` show the actual result. Private preference/proof data
are excluded from git. Device Hub was used for live viewing/control after the
phone became available; XCTest provides the repeatable regression.

The first physical UI run required the owner's iPhone passcode to enable Apple's
UI automation. It timed out before approval; it is not counted as app evidence.
