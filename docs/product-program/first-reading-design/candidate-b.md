# Candidate B: prepared starter slots, cache-only onboarding query

## Problem

Onboarding calls `actions/daily:getDailyHadith` in both native apps; missing translation becomes Arabic plus Retry. That Retry cannot create exact-locale text. Daily currently persists one pick per date/timezone, scans cached collections when absent, and can fetch Sunnah.now on cold cache. Translation lookup is cache-only, but the whole Daily action is therefore not provider-free. A1 needs a separate cheap boundary that never imports the Daily action or generation path. Exact-locale availability cannot be guaranteed out of a genuinely empty corpus: provisioning approved real content is a launch prerequisite, not a client algorithm.

## Usage (caller's view)

```swift
// OnboardingTranslationView: reload on locale and auth-independent network recovery.
let first: FirstReading = try await convex.query("firstReading:get", with: [
    "translationLocale": locale, "timezone": TimeZone.current.identifier
])
// ready: show complete readable translation, source details, and origin-specific heading.
// unavailable: explain absence, Choose another reading language, Continue to library.
// transport failure: Retry. These are distinct states.
```
```kotlin
// ConvexRepository; query and subscription collection remain on Dispatchers.IO.
suspend fun firstReading(locale: String): FirstReading = withContext(Dispatchers.IO) {
    convex.query("firstReading:get", mapOf("translationLocale" to locale,
        "timezone" to ZoneId.systemDefault().id))
}
// TranslationDemonstration uses LaunchedEffect(locale), cancels old work,
// and ignores responses for a superseded locale.
```
```ts
// Internal provisioning tool, never called by a public query or mobile app.
await ctx.runMutation(internal.firstReading.prepareSlot, {
  locale: "uz", rank: 0, hadithId, translationId,
}); // Validates existing authorized text; does not call a provider or grant rights.
```

## Shape

```ts
type FirstReading =
  | { kind: "ready"; locale: SupportedLocale; origin: "daily" | "starter";
      reading: AuthorizedReading; validUntil: number | null }
  | { kind: "unavailable"; locale: SupportedLocale;
      reason: "not_prepared" | "withdrawn" };
type AuthorizedReading = {
  target: { canonicalId: string; collectionSlug: string; providerHadithId: string;
            volumeId: string | null };
  arabicText: string; translation: { text: NonBlankText; language: SupportedLocale;
    source: "official" | "community" | "gemini_ai"; sourceLabel: string;
    sourceUrl: string | null; isAI: boolean; translationId: string | null };
  referenceDisplay: string; authenticity: AuthenticityClaim;
  provenance: PublicProvenance; // Public attribution only, no private evidence/storage URLs.
};
// Schema: firstReadingSlots { locale, rank: 0 | 1 | 2, hadithId,
// translationId?, providerEnglish?: true, sourceDigest, updatedAt }
// index by_locale_rank(locale, rank); exactly three slots maximum per supported locale.
// Provider English is allowed only for exact `en`, with verified underlying display rights.
export const get = query({ args: {translationLocale: v.string(), timezone: v.string()},
  handler: async (ctx, args): Promise<FirstReading> => { throw new Error("not implemented"); }
});
async function resolveAuthorizedReading(ctx: QueryCtx, reference: ReadingReference,
  locale: SupportedLocale): Promise<AuthorizedReading | null> {
  // TODO load exact identity/digest/license; exact-language nonblank text;
  // validate live/default revision, generation identity, public permissions, attribution.
  throw new Error("not implemented");
}
export const prepareSlot = internalMutation({ /* explicit validators and annotated handler */ });
```

`firstReading.ts` owns the query, slot mutation and resolver. Existing content policy, generation identity and publication helpers remain authoritative; native domain types decode the discriminated result. This is one public method hiding identity, authorization, ranking and fallback rules, per boundary-discipline and minimize-reader-load.

Read order: validate supported canonical locale without language fallback; validate IANA timezone; indexed `dailySelections` exact date/timezone lookup without persisting a pick. If a selection already exists, try its authorized exact-locale current default. Otherwise (or missing/invalid translation), inspect up to three prepared locale slots ordered by rank and return the first still authorized. A response with `origin: starter` is visibly titled “A first reading”; it never says today's hadith. No Daily record is created or changed. Today, notifications, widgets and Daily deep links continue using their existing canonical selection.

Prepared slots are references, not copied text or authorization snapshots. Resolve current hadith and translation on every read. Require matching canonical identity and source digest, nonblank complete translation, selected locale equality, live/default eligibility and current rights. Reuse `publicTranslationAvailable`; additionally enforce base Arabic/English display rights for every source, since current helper exempts non-community rows without publication records and legacy AI without generationKey. Never treat existing cached rows or `SUNNAH_NOW_LICENSE_RECORD` (`unverified`) as permission. An official translation also needs a verified permission binding covering its actual text; absence fails closed.

Bound top-level access: one indexed Daily selection, at most one Daily target and three locale slots, fixed point reads. Existing `availableDefault` collects all defaults and publication validation recursively collects dependencies, so merely calling it does not prove a strict bound. For this boundary use indexed `.take(MAX_DEFAULTS + 1)` and fail closed on overflow; cap publication dependencies and ancestry with explicit aggregate budgets (e.g. 100 documents, depth 20, 8 source policies). Exceeding a budget returns unavailable rather than truncating authorization checks. Add shared optional budget to the existing permission validator instead of a weaker parallel validator.

Slot writes use `(locale, rank)` transactional upsert; at most three distinct ranks. Duplicate runs converge. Slots do not mint rights or publish translations. Revoked/expired/deleted/changed content immediately becomes unusable; expiration timer and query updates remove rendered text. Native apps clear prior locale text at load start, and clear content on invalidation; no persisted first-reading cache in A1.

## Provisioning and truly empty locales

Ship readiness requires at least one currently authorized useful first reading for each of the fifteen supported locales, ideally three independent candidates. Enumerate the actual supported locale list from shared preference contracts in the implementation audit; do not infer region equivalence. Reuse already approved real text where available. Where empty, prepare real authorized text through an explicit content task: licensed import, rights-approved original translation, or separately authorized service generation through `quotas.admit(signal: service)` and normal finish/publication checks. No generation happens during onboarding, no free guest generation, no credit reservation from reading, and no unbounded warm-up cron.

If paid generation or missing license approval is needed, keep that locale's readiness gate open until authorized and verified; no local fixture closes it. Runtime says “A reading in [language] is not available yet.” Offer explicit language selection or library continuation. A language change updates the chosen translation preference visibly; it is never a silent English fallback. Continue to library remains available for guest safety, but does not count as reading success. Content absence has no repeated Retry button; Retry is solely for failed transport. Show full text, not the current three-line truncation.

## Synthesis decision

Candidate only; arena orchestrator selects the base.

## Tradeoffs accepted

- We accept a small provisioned content set in exchange for bounded public reads and a reliable guest path.
- We accept that canonical Daily may not appear during onboarding in exchange for keeping its identity independent of locale and avoiding cold-cache provider calls.
- We accept honest unavailability after revocation in exchange for enforcing current permission; no static guarantee overrides withdrawn rights.
- We accept a content readiness gate separate from code completion because an empty corpus cannot become readable through a response type.

## Alternatives considered

- Prepared canonical Daily across every locale: hides fallback choice well but requires provisioning each date/timezone pick and couples supported-locale availability to Daily publication; larger operational and paid-generation surface than three starter slots.
- Query live translations by locale and choose any usable row: avoids slot maintenance but leaks global publication churn into onboarding, requires potentially unbounded rejection scanning and cannot guarantee a useful deterministic first reading.
- Bundle translations in apps: fastest offline startup but duplicates content/revocation policy across releases; current permission and source changes cannot be applied reliably without another online validation boundary.

## Verification

Backend deterministic fixtures: missing Daily + valid starter, untranslated Daily + same starter across timezones, translated Daily wins, locale mismatch rejected, blank text rejected, malformed timezone/locale rejected, source digest change, expired/revoked rights, unpublished/deleted default, legacy AI without generationKey, permission-budget overflow, slot duplicates and idempotent writes. Assert zero provider/action calls, zero quota rows, unchanged Daily selection, signed-out access and bounded reads. Real license fixtures are test evidence only.

Both native UI paths: selected-locale full text and provenance, starter heading, Daily heading only for Daily, slow locale changes, exact target navigation, sign-out parity, RTL geometry, font scaling, publication expiry clears text, content absence has language choice/library action, transport Retry succeeds. LA2 emits existing reading-success metric only after actual readable text renders; never send target/text, and never count library continuation or mere onboarding completion as success. Real runtime readback across all supported locales is the provisioning gate; fixtures/builds are not substitute evidence.

## Open questions and risks

- Which current content has affirmative rights for the Arabic plus each translation, including underlying model-processing rights if generation is needed?
- Can the existing publication validator support a global budget without changing other consumers' defaults?

## Next implementation step

Write the failing cache-only query contract and empty-locale UI fixtures before adding the slot schema and exact-locale resolver.
