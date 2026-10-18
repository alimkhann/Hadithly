# A1 candidate: separate canonical Daily from first reading

## Problem

`getDailyHadith` fixes one eligible hadith for local date and IANA zone. It returns its exact-locale live default or `null`; the public action never generates. Both onboarding views show Arabic and a Retry that repeats that read, so a guest can finish without reading in the chosen language. A first-reading fallback must use a *different, explicitly named* hadith when necessary, retain Today's identity, and only display text with current rights and publication validity. The signed-out path cannot pass through `translateHadith`, its Clerk identity, attestation, or quota admission.

## Usage (caller's view)

Onboarding calls one public `getFirstReading({ timezone, translationLocale })`. It renders `ready.reading`, whose `kind` is `today` or `starter`; it calls the displayed source and opens the exact displayed hadith. For a starter it says “A first reading in Urdu” and separately “Today's hadith is available in Arabic; its Urdu translation is not available yet.” It never labels the starter “Today's hadith.” If `unavailable`, it shows a chosen-language-specific content notice and a route to Arabic reading or language choice; Retry is reserved for transport errors.

```ts
// iOS OnboardingTranslationView: action result is decoded as FirstReadingOutcome.
let outcome: FirstReadingOutcome = try await convex.action(
  "actions/firstReading:getFirstReading",
  with: ["timezone": TimeZone.current.identifier, "translationLocale": locale])
// .ready(reading: .today | .starter, daily: DailySummary), .unavailable(reason, daily)

// Android TranslationDemonstration: same wire contract, repository on Dispatchers.IO.
val outcome = repository.getFirstReading(selectedLanguage)
// render exact text + provenance only for Ready; separate Empty from network Failure.

// Today, widgets, and push keep their existing canonical Daily reads and targets.
val daily = repository.getDailyHadith(selectedLanguage)
```

## Shape

```ts
type ReadingIdentity = {
  canonicalId: string; provider: HadithProviderName; collectionSlug: string;
  providerHadithId: string; referenceDisplay: string; authenticity: AuthenticityClaim;
};
type ExactReading = {
  kind: "today" | "starter"; identity: ReadingIdentity; arabicText: string;
  translation: { text: string; language: string; source: "official" | "gemini_ai" | "community" | "sunnah_now";
    sourceLabel: string; sourceReferenceUrl?: string; isAI: boolean; };
};
type DailySummary = { identity: ReadingIdentity; hasExactTranslation: boolean } | null;
type FirstReadingOutcome =
  | { kind: "ready"; reading: ExactReading; daily: DailySummary }
  | { kind: "unavailable"; reason: "no_licensed_exact_locale_text" | "no_daily_selection"; daily: DailySummary };

// Public action: validates locale and zone, returns current materialized text only.
getFirstReading(args: { timezone: string; translationLocale: string }): Promise<FirstReadingOutcome>;
// Internal indexed query: resolves a bounded prepared starter set, revalidating live rows.
findFirstReadingStarter(args: { locale: string; excludedCanonicalId?: string }): Promise<ExactReading | null>;
// Internal publication hook: prepares/removes candidate references; never text copies.
syncFirstReadingCandidate(args: { translationId: Id<"translations"> }): Promise<void>;
```

Add `firstReadingCandidates { locale, hadithId, translationId, canonicalId, rank, preparedAt }` with `by_locale_rank` index. A controlled content preparation job inserts only exact-locale, nonempty, live default translations whose hadith has a verified `permitsDisplay` license, Daily-eligible authenticity, and permitted translation/publication provenance. Rank is stable, curated by a deterministic rule, never influenced by request order, user identity, or timezone. The read takes a fixed small window (for example 16) by index and checks each current hadith license, translation availability, current default, AI generation identity, evidence publication validity, and source metadata before choosing the first valid distinct candidate. It must not return a stale reference after revocation. If the window contains no valid rows, return unavailable and queue maintenance outside the request; do not scan the whole locale or generate. Idempotent preparation upserts by translation ID; withdrawn content is removed by publication lifecycle and still fails read-time checks. The maintained candidate set must keep enough top entries to survive ordinary revocations without unbounded lookup.

The action first runs existing `pickDailyHadith`; it does not alter `dailySelections`. If Daily has valid exact text and current display rights, return it as `today`. Otherwise ask the candidate query for a `starter` excluding Daily's canonical ID. The candidate may be the same on many days and across guests; no user-specific write is needed. If none exists, return `unavailable`. A missing Daily does not prevent a valid starter; its summary is null. The action never calls a provider, Gemini, `quotas.admit`, or `generateServiceTranslation`. If `pickDailyHadith` can seed via Sunnah.now today, that existing provider path must be made separate from the first-reading read or this action must use a cache-only Daily selector: opening onboarding must make no hidden provider call. The first-reading response itself has no English fallback field; locale equality is checked server side, and `en` provider English is allowed only under verified display rights.

`firstReadingCandidates` is a lookup accelerator, not an authority for text or rights. `translations.availableDefault` / `publicTranslationAvailable` and the current hadith license stay authoritative. Add one domain resolver in `backend/convex/firstReading.ts` and one thin public action in `backend/convex/actions/firstReading.ts`; the iOS/Android repositories decode the same tagged outcome. Native views share the explicit Today-versus-starter copy policy and retain the existing locale selection. The interface hides candidate ranking, license joins, revocation, and provenance checks; native callers only handle ready/unavailable/transport failure. This follows type-system and boundary discipline, with one source of truth per invariant.

## Synthesis decision

Candidate A proposes an explicit first-reading response with a prepared locale index; arena synthesis pending.

## Tradeoffs accepted

- We accept a small materialized candidate index and publication maintenance in exchange for bounded public reads and an honest guest path.
- We accept that a truly empty locale is unavailable until rights-cleared exact text is prepared; no response contract can guarantee content that does not exist.
- We accept distinct first-reading and Daily payloads in exchange for keeping widget, notification, Today, and canonical-link identity untouched.

## Alternatives considered

- Re-pick Daily from only translated hadiths: a locale-specific selection would make Today's canonical identity vary by language and would leak fallback logic into every Daily caller.
- Generate missing Daily text on opening onboarding: one call site looks simple, but it exposes identity, attestation, quota, provider cost, and failure handling to guests and breaks the public-read boundary.
- Search live translations directly on every read: one query looks smaller, but bounded prefixes can contain unusable rows and the request must discover rights, rank, and publication policy at scale. The prepared index hides that work behind a smaller interface.

## Open questions and risks

- Which exact-locale, quality-reviewed, affirmative-rights text can seed each of the 15 locales, including regional tags such as `es-419` and `pt-BR`? A1 cannot be marked complete for a locale with no qualifying row.
- Does current provider English have affirmative display permission, and do any existing official/community rows carry sufficient translation-specific rights evidence? If not, which approved import path supplies the starter set?
- Should Daily summaries expose Arabic when its own display license is unverified, or should the UI only mention the unavailable translation without reproducing text?
- How will release verification prove revocation immediately hides a starter on both native platforms, including any device cache?

## Verification and next step

First build red backend contract tests for exact Daily, missing Daily translation with distinct starter, empty locale, wrong-region locale, revoked license/publication, stale AI generation, stable Daily ID, no provider/generation/quota calls, concurrent/repeated preparation, and bounded candidate reads. Then add iOS and Android decoder and rendered onboarding tests for all three outcomes plus network failure, locale switch, source labels, and exact target. Run signed-out native journeys with real rights-cleared text in the selected locale; retain every empty-locale gate until content exists.
