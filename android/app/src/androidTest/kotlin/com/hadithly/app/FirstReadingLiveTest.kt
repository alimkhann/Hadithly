package com.hadithly.app

import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createAndroidComposeRule
import com.hadithly.app.core.data.FirstReadingResult
import com.hadithly.app.features.reader.ReaderViewModel
import java.io.File
import java.io.FileInputStream
import androidx.test.platform.app.InstrumentationRegistry
import java.net.HttpURLConnection
import java.net.URL
import java.time.ZoneId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.decodeFromJsonElement
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

/** Development content readback only. Automatic generation is disabled and restored. */
class FirstReadingLiveTest {
    @get:Rule val compose = createAndroidComposeRule<MainActivity>()
    @Test fun englishReadingOpensItsTarget() = readAndOpen("en")
    @Test fun arabicOriginalOpensItsTarget() = readAndOpen("ar")
    @Test fun russianReadingOpensItsTarget() = readAndOpen("ru")
    @Test fun kazakhStarterOpensItsTarget() = readAndOpen("kk")

    @Test fun cachedReadingReturnsAfterLanguageStep() = readAndOpen("ru", roundTrip = true)

    private fun readAndOpen(locale: String, roundTrip: Boolean = false) {
        val app = compose.activity.application as HadithlyApplication
        val original = app.preferences.preferences.value
        val completed = app.settings.onboardingCompleted.value
        val automatic = app.readerExperience.automaticallyTranslates.value
        val prefs = app.getSharedPreferences("onboarding", 0)
        val old = prefs.all
        try {
            val connection = URL("${BuildConfig.CONVEX_URL}/api/query").openConnection() as HttpURLConnection
            connection.requestMethod = "POST"
            connection.setRequestProperty("Content-Type", "application/json")
            connection.connectTimeout = 20_000
            connection.readTimeout = 20_000
            connection.doOutput = true
            connection.outputStream.use { it.write("""{"path":"firstReading:get","args":{"translationLocale":"$locale","timezone":"${ZoneId.systemDefault().id}"},"format":"json"}""".toByteArray()) }
            val payload = try { connection.inputStream.bufferedReader().use { it.readText() } } finally { connection.disconnect() }
            val expected = Json.decodeFromJsonElement<FirstReadingResult>(Json.parseToJsonElement(payload).jsonObject.getValue("value"))
            check(expected is FirstReadingResult.Ready) { "Expected existing development content for $locale" }
            compose.runOnIdle { app.settings.setOnboardingCompleted(true) }
            compose.runOnIdle {
                prefs.edit().clear().putInt("step", 2).commit()
                app.readerExperience.setAutomaticTranslation(false)
                app.preferences.setUILocale("en")
                app.preferences.setTranslationLocale(locale)
                app.settings.setOnboardingCompleted(false)
            }
            compose.waitUntil(30_000) { compose.onAllNodesWithTag("onboarding.openReading").fetchSemanticsNodes().isNotEmpty() }
            if (locale != "ar") compose.onNodeWithTag("hadith.text.translation").assertTextEquals(expected.reading.text.text).assertIsDisplayed()
            else compose.onNodeWithTag("hadith.text.translation").assertDoesNotExist()
            if (roundTrip) {
                compose.onNodeWithTag("onboarding.back").performClick()
                compose.waitUntil(5_000) { compose.onAllNodesWithTag("onboarding.openReading").fetchSemanticsNodes().isEmpty() }
                compose.onNodeWithTag("onboarding.continue").performClick()
                compose.waitUntil(20_000) { compose.onAllNodesWithTag("onboarding.openReading").fetchSemanticsNodes().isNotEmpty() }
                compose.onNodeWithTag("hadith.text.translation").assertTextEquals(expected.reading.text.text).assertIsDisplayed()
            }
            capture("first-reading-$locale")
            compose.onNodeWithTag("onboarding.openReading").performClick()
            val name = ReaderViewModel.shortCollectionName(expected.reading.collectionSlug, expected.reading.collectionName)
            val target = hasTestTag("reader.hadithLabel") and hasContentDescription("$name – ${expected.reading.providerHadithId}", substring = true)
            compose.waitUntil(30_000) { compose.onAllNodes(target).fetchSemanticsNodes().isNotEmpty() }
            compose.onNode(target).assertIsDisplayed()
            capture("first-reading-target-$locale")
        } catch (failure: Throwable) {
            capture("first-reading-failure-$locale")
            throw failure
        } finally {
            compose.runOnIdle {
                app.preferences.setUILocale(original.uiLocale)
                app.preferences.setTranslationLocale(original.translationLocale)
                app.readerExperience.setAutomaticTranslation(automatic)
                app.settings.setOnboardingCompleted(completed)
                val edit = prefs.edit().clear()
                old.forEach { (key, value) -> when(value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
                edit.commit()
            }
        }
    }
    private fun capture(name: String) {
        val directory = File(compose.activity.getExternalFilesDir(null), "FirstReading").apply { mkdirs() }
        compose.onRoot().captureToImage().asAndroidBitmap().let { bitmap ->
            File(directory, "$name.png").outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
        }
        for (command in listOf("mkdir -p /sdcard/Download/HadithlyFirstReading", "screencap -p /sdcard/Download/HadithlyFirstReading/$name.png")) {
            val shell = InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand(command)
            FileInputStream(shell.fileDescriptor).use { it.readBytes() }
            shell.close()
        }
    }
}
