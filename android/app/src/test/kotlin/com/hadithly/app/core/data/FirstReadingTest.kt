package com.hadithly.app.core.data

import java.io.File
import kotlinx.serialization.json.Json
import org.junit.Assert.*
import org.junit.Test

class FirstReadingTest {
    private val json = Json { ignoreUnknownKeys = true }
    private fun fixture(name: String): String {
        val directory = listOf("testdata/first-reading", "../testdata/first-reading", "../../testdata/first-reading")
            .map(::File).first { it.isDirectory }
        return File(directory, "$name.json").readText()
    }

    @Test fun actualBackendOutcomesDecodeWithoutLanguageFallback() {
        for (name in listOf("starter-en", "starter-ru", "daily-ru", "original-ar")) {
            val result = json.decodeFromString<FirstReadingResult>(fixture(name))
            assertTrue(result is FirstReadingResult.Ready)
            val ready = result as FirstReadingResult.Ready
            assertEquals(ready.locale, ready.reading.text.language)
            assertTrue(ready.reading.text.text.isNotBlank())
        }
        assertTrue(json.decodeFromString<FirstReadingResult>(fixture("unavailable-ru")) is FirstReadingResult.Unavailable)
    }

    @Test fun wrongLanguageAndFalseDailyIdentityAreRejected() {
        val source = fixture("starter-ru")
        assertThrows(IllegalArgumentException::class.java) {
            json.decodeFromString<FirstReadingResult>(source.replace("\"locale\": \"ru\"", "\"locale\": \"fr\""))
        }
        assertThrows(IllegalArgumentException::class.java) {
            json.decodeFromString<FirstReadingResult>(source.replace("\"origin\": \"starter\"", "\"origin\": \"daily\""))
        }
    }
    @Test fun unsupportedReaderProviderIsRejected() {
        assertThrows(IllegalArgumentException::class.java) {
            json.decodeFromString<FirstReadingResult>(fixture("starter-en").replace("sunnah_now", "sunnah_com"))
        }
    }

}
