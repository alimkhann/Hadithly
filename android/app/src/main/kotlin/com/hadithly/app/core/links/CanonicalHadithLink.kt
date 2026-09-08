package com.hadithly.app.core.links

import com.hadithly.app.core.data.Collections

/**
 * The canonical hadith link contract at the Android boundary. Mirrors
 * `backend/convex/lib/canonicalLinks.ts`:
 * `https://hadithly.app/hadith/{collectionSlug}/{providerHadithId}`.
 * A link from another host, scheme, or shape is not Hadithly's link and
 * must never move the reader.
 */
data class CanonicalHadithLink(
    val collectionSlug: String,
    val providerHadithId: String,
) {
    /** Display name from the seven-collection catalog; falls back to the slug. */
    val collectionName: String =
        Collections.all.firstOrNull { it.first == collectionSlug }?.second
            ?: collectionSlug

    companion object {
        const val HOST = "hadithly.app"
        const val PATH_PREFIX = "/hadith/"
        const val PATH_SEGMENT = "hadith"

        private val COLLECTION_SLUG = Regex("[a-z][a-z0-9-]{1,31}")
        private val PROVIDER_HADITH_ID = Regex("[1-9][0-9]{0,11}(\\.[0-9]{1,12})*")

        /**
         * Parses an inbound https App Link. Callers pass the pieces of the
         * resolved `Uri` so this stays framework-free and unit-testable.
         * Returns null for any foreign, truncated, or malformed link.
         */
        fun parse(
            scheme: String?,
            host: String?,
            path: String?,
            encodedPath: String? = path,
        ): CanonicalHadithLink? {
            if (scheme != "https" || host != HOST || path != encodedPath) return null
            if (path == null || !path.startsWith(PATH_PREFIX)) return null
            val normalizedPath = path.removeSuffix("/")
            if (normalizedPath.endsWith("/")) return null
            val segments = normalizedPath
                .removePrefix(PATH_PREFIX)
                .split("/")
            if (segments.size != 2) return null
            val (slug, id) = segments
            if (!COLLECTION_SLUG.matches(slug)) return null
            if (!PROVIDER_HADITH_ID.matches(id)) return null
            return CanonicalHadithLink(slug, id)
        }
    }
}
