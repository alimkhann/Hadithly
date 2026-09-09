package com.hadithly.app.core.links

/**
 * Builds the shareable canonical hadith URL:
 * `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}`.
 * Mirrors `formatCanonicalHadithUrl` in `backend/convex/lib/canonicalLinks.ts`.
 * Share sheets use only this URL — never a deep link with private position
 * data. Throws on a malformed slug or hadith id so construction bugs fail
 * fast in tests, not in shares.
 */
object CanonicalHadithUrl {
    private const val BASE = "https://hadithly.app/hadith/"

    fun build(collectionSlug: String, providerHadithId: String): String {
        require(CanonicalHadithLink.isValidCollectionSlug(collectionSlug)) {
            "Invalid collection slug for canonical URL: $collectionSlug"
        }
        require(CanonicalHadithLink.isValidProviderHadithId(providerHadithId)) {
            "Invalid provider hadith id for canonical URL: $providerHadithId"
        }
        return "$BASE$collectionSlug/$providerHadithId"
    }
}
