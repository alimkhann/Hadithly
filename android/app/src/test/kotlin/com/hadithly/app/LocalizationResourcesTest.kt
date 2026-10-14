package com.hadithly.app

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Resource fixture tests for the F2 localization foundations. Unit tests run
 * on the JVM, so these read the res XML from the module source tree and prove
 * the en, ar, and ur foundations are complete and the plural fixture carries
 * the right quantities.
 */
class LocalizationResourcesTest {

    private fun resDir(name: String): File =
        File("src/main/res/$name")

    private fun strings(name: String): Map<String, String> {
        val file = File(resDir(name), "strings.xml")
        assertTrue("missing ${file.path}", file.exists())
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        val map = mutableMapOf<String, String>()
        for (i in 0 until nodes.length) {
            val node = nodes.item(i)
            val key = node.attributes.getNamedItem("name").nodeValue
            map[key] = node.textContent
        }
        return map
    }

    private fun pluralQuantities(name: String, pluralName: String): Set<String> {
        val file = File(resDir(name), "strings.xml")
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val plurals = doc.getElementsByTagName("plurals")
        for (i in 0 until plurals.length) {
            val node = plurals.item(i)
            if (node.attributes.getNamedItem("name").nodeValue != pluralName) continue
            val items = node.childNodes
            val quantities = mutableSetOf<String>()
            for (j in 0 until items.length) {
                val item = items.item(j)
                val quantity = item.attributes?.getNamedItem("quantity")?.nodeValue ?: continue
                quantities.add(quantity)
            }
            return quantities
        }
        error("missing plural $pluralName in $name")
    }

    @Test
    fun `Wave 1 resource directories contain every English resource`() {
        val locales = mapOf(
            "ar" to "values-ar", "ru" to "values-ru", "kk" to "values-kk", "ky" to "values-ky",
            "uz" to "values-uz", "tr" to "values-tr", "id" to "values-id", "ur" to "values-ur",
            "fr" to "values-fr", "es-419" to "values-b+es+419", "pt-BR" to "values-pt-rBR",
            "sw" to "values-sw", "hi" to "values-hi", "bn" to "values-bn",
        )
        for (fileName in listOf("strings.xml", "la2.xml")) {
            val englishFile = File(resDir("values"), fileName)
            val englishDoc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(englishFile)
            val englishStrings = englishDoc.getElementsByTagName("string").length
            val englishPlurals = englishDoc.getElementsByTagName("plurals").length
            for ((locale, directory) in locales) {
                val file = File(resDir(directory), fileName)
                assertTrue("missing $locale/$fileName resources", file.exists())
                val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
                assertEquals("$locale/$fileName string count", englishStrings, doc.getElementsByTagName("string").length)
                assertEquals("$locale/$fileName plural count", englishPlurals, doc.getElementsByTagName("plurals").length)
            }
        }
    }

    @Test
    fun `English foundations exist with the plural fixture`() {
        val strings = strings("values")
        assertEquals("Choose your language", strings["onboarding_choose_language_title"])
        assertTrue(strings.containsKey("settings_app_language"))
        assertTrue(strings.containsKey("settings_hadith_translation"))
        assertTrue(strings.containsKey("settings_reading_direction"))
        assertTrue(strings.containsKey("settings_visibility_arabic"))
        assertTrue(strings.containsKey("settings_visibility_translation"))
        assertEquals(
            setOf("one", "other"),
            pluralQuantities("values", "settings_languages_available"),
        )
    }

    @Test
    fun `Arabic foundations carry every key and the full plural set`() {
        val english = strings("values")
        val arabic = strings("values-ar")
        for (key in english.keys.filterNot { it == "app_name" }) {
            assertTrue("values-ar missing $key", arabic.containsKey(key))
            assertTrue("values-ar $key is empty", arabic[key]!!.isNotBlank())
        }
        assertEquals(
            setOf("zero", "one", "two", "few", "many", "other"),
            pluralQuantities("values-ar", "settings_languages_available"),
        )
    }

    @Test
    fun `Urdu foundations carry every key and the plural set`() {
        val english = strings("values")
        val urdu = strings("values-ur")
        for (key in english.keys.filterNot { it == "app_name" }) {
            assertTrue("values-ur missing $key", urdu.containsKey(key))
            assertTrue("values-ur $key is empty", urdu[key]!!.isNotBlank())
        }
        assertEquals(
            setOf("one", "other"),
            pluralQuantities("values-ur", "settings_languages_available"),
        )
    }
}
