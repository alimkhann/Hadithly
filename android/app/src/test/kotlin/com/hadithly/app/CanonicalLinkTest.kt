package com.hadithly.app

import com.hadithly.app.core.links.CanonicalHadithLink
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

/**
 * F3 gate: canonical App Link parsing on the Android boundary. Mirrors
 * `backend/convex/lib/canonicalLinks.ts` and the iOS CanonicalLinkTests so
 * all three surfaces accept and reject the same links.
 */
class CanonicalLinkTest {

    @Test
    fun parsesCanonicalLink() {
        val link = CanonicalHadithLink.parse("https", "hadithly.app", "/hadith/bukhari/57")
        assertEquals("bukhari", link?.collectionSlug)
        assertEquals("57", link?.providerHadithId)
        assertEquals("Sahih al-Bukhari", link?.collectionName)
    }

    @Test
    fun parsesDottedSubreferenceAndKeepsQueryStringOut() {
        val link = CanonicalHadithLink.parse("https", "hadithly.app", "/hadith/muslim/4.5")
        assertEquals("muslim", link?.collectionSlug)
        assertEquals("4.5", link?.providerHadithId)
    }

    @Test
    fun toleratesTrailingSlashOnly() {
        val link = CanonicalHadithLink.parse("https", "hadithly.app", "/hadith/nasai/1000/")
        assertEquals("nasai", link?.collectionSlug)
        assertEquals("1000", link?.providerHadithId)
    }

    @Test
    fun fallsBackToSlugForUnknownCollection() {
        val link = CanonicalHadithLink.parse("https", "hadithly.app", "/hadith/muwatta/7")
        assertEquals("muwatta", link?.collectionName)
    }

    @Test
    fun rejectsForeignHostAndScheme() {
        assertNull(CanonicalHadithLink.parse("http", "hadithly.app", "/hadith/bukhari/57"))
        assertNull(CanonicalHadithLink.parse("https", "evil.example", "/hadith/bukhari/57"))
        assertNull(
            CanonicalHadithLink.parse("https", "hadithly.app.evil.example", "/hadith/bukhari/57"),
        )
    }

    @Test
    fun rejectsMalformedShapes() {
        val malformed = listOf(
            "/hadith/bukhari",
            "/hadith/bukhari/57/extra",
            "/hadith//57",
            "/hadith/bukhari/",
            "/hadith/Bukhari/57",
            "/hadith/bukhari/57abc",
            "/hadith/bukhari/57.",
            "/hadith/bukhari/.5",
            "/hadith/bukhari/0",
            "/reader/bukhari/57",
            "/privacy/",
            "/",
            "",
        )
        for (path in malformed) {
            assertNull(
                "should reject $path",
                CanonicalHadithLink.parse("https", "hadithly.app", path),
            )
        }
        assertNull(CanonicalHadithLink.parse("https", "hadithly.app", null))
    }

    @Test
    fun linkDataClassCarriesIdentity() {
        val link = CanonicalHadithLink("bukhari", "57")
        assertEquals(CanonicalHadithLink("bukhari", "57"), link)
        assertNotNull(link)
    }
}
