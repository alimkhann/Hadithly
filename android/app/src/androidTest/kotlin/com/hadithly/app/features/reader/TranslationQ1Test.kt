package com.hadithly.app.features.reader

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertHeightIsAtLeast
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.onRoot
import androidx.compose.ui.test.captureToImage
import androidx.compose.ui.graphics.asAndroidBitmap
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.data.TranslationAllowance
import androidx.compose.ui.unit.dp
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.data.TranslationFailure
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class TranslationQ1Test {
    @get:Rule val compose = createComposeRule()
    private val hadith = ReaderHadith("fixture", "sunnah_now", "sunnah_now:bukhari:1", "1", "bukhari",
        arabicText = "اختبار", englishText = "Provider text", referenceDisplay = "Synthetic", collectionName = "Synthetic",
        authenticity = AuthenticityClaim("unverified", claimScope = "none", sourceLabel = "Fixture", sourceName = "Fixture", sourceUrl = "https://example.org", verificationMethod = "unverified"))

    @Test fun missingTranslationWaitsForOneExplicitHadithAction() {
        var requests = 0
        val state = mutableStateOf<TranslationUiState?>(null)
        compose.setContent { ReaderTestTheme { TranslationSection(hadith, state.value, "ru", {
            requests++
            state.value = TranslationUiState.Loaded(ReaderTranslation("generated", "Generated text", source = "gemini_ai", sourceLabel = "AI"))
        }, {}) } }
        compose.onNodeWithTag("reader.generateTranslation").assertHeightIsAtLeast(48.dp).assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, requests) }
        compose.onNodeWithTag("reader.generateTranslation").performClick()
        compose.onNodeWithText("Generated text").assertIsDisplayed()
        compose.runOnIdle { assertEquals(1, requests) }
    }

    @Test fun onlyActualQuotaRejectionOffersPlans() {
        var paywalls = 0
        val state = mutableStateOf<TranslationUiState?>(TranslationUiState.Failed(TranslationFailure.Failed("AI_RATE_LIMITED")))
        compose.setContent { ReaderTestTheme { TranslationSection(hadith, state.value, "ru", {}, { paywalls++ }, TranslationAllowance(5.0, 0.0)) } }
        compose.onNodeWithText("See plans").assertDoesNotExist()
        compose.runOnIdle { state.value = TranslationUiState.Failed(TranslationFailure.RequiresSignIn) }
        compose.onNodeWithText("See plans").assertDoesNotExist()
        compose.runOnIdle { state.value = TranslationUiState.Failed(TranslationFailure.QuotaExceeded) }
        compose.onNodeWithText("See plans").performClick()
        compose.runOnIdle { assertEquals(1, paywalls) }
    }

    @Test fun cachedGuestTranslationRendersWithoutGenerateOrPaywall() {
        compose.setContent { ReaderTestTheme { TranslationSection(hadith, TranslationUiState.Loaded(
            ReaderTranslation("cached", "Cached exact-locale text", source = "official", sourceLabel = "Official", cached = true)), "ru", {}, {}, TranslationAllowance(5.0, 3.0)) } }
        compose.onNodeWithText("Cached exact-locale text").assertIsDisplayed()
        compose.onNodeWithTag("reader.generateTranslation").assertDoesNotExist()
        compose.onNodeWithText("See plans").assertDoesNotExist()
        compose.onNodeWithTag("reader.translationAllowance").assertDoesNotExist()
    }

    @Test fun cooldownDisablesRetryAndShowsOneAvailabilityDate() {
        val deadline = System.currentTimeMillis() + 60_000
        compose.setContent { ReaderTestTheme { TranslationSection(hadith,
            TranslationUiState.Failed(TranslationFailure.Failed("AI_GENERATION_BUSY retryAt: $deadline")), "ru", {}, {}, TranslationAllowance(5.0, 3.0)) } }
        compose.onNodeWithTag("reader.retryTranslation").assertIsNotEnabled()
        compose.onNodeWithTag("reader.translationRetryAt").assertIsDisplayed()
        compose.onNodeWithText("Translation temporarily unavailable").assertIsDisplayed()
        compose.onNodeWithTag("reader.quotaPaywall").assertDoesNotExist()
    }

    @Test fun proLimitDoesNotOfferAnotherUpgradeAndElapsedLimitCanRetry() {
        val allowance = mutableStateOf(TranslationAllowance(100.0, 0.0, (System.currentTimeMillis() + 60_000).toDouble()))
        compose.setContent { ReaderTestTheme { TranslationSection(hadith,
            TranslationUiState.Failed(TranslationFailure.QuotaExceeded), "ru", {}, {}, allowance.value) } }
        compose.onNodeWithText("Translation allowance used").assertIsDisplayed()
        compose.onNodeWithTag("reader.quotaPaywall").assertDoesNotExist()
        compose.onNodeWithTag("reader.translationRetryAt").assertIsDisplayed()
        compose.runOnIdle { allowance.value = TranslationAllowance(100.0, 0.0, (System.currentTimeMillis() - 60_000).toDouble()) }
        compose.onNodeWithTag("reader.retryTranslation").assertIsEnabled()
        compose.onNodeWithTag("reader.translationRetryAt").assertDoesNotExist()
    }

    @Test fun readerStatusGalleryAcrossThemes() {
        val theme = mutableStateOf(ReaderTheme.LIGHT)
        val locale = mutableStateOf("en")
        val state = mutableStateOf<TranslationUiState?>(null)
        val allowance = mutableStateOf<TranslationAllowance?>(TranslationAllowance(5.0, 3.0))
        compose.setContent { ReaderTestTheme(theme.value, locale.value) {
            val colors = LocalHadithlyColors.current
            Surface(Modifier.fillMaxSize(), color = colors.background) {
                Column(Modifier.padding(24.dp), verticalArrangement = Arrangement.spacedBy(18.dp)) {
                    Text("Sahih al-Bukhari · 1", color = colors.textSecondary)
                    Text("إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ", color = colors.textPrimary)
                    TranslationSection(hadith, state.value, "ru", {}, {}, allowance.value)
                }
            }
        } }
        for ((name, appearance, status) in listOf(
            Triple("missing", ReaderTheme.LIGHT, null),
            Triple("loading", ReaderTheme.PAPER, TranslationUiState.Loading),
            Triple("failure", ReaderTheme.DARK, TranslationUiState.Failed(TranslationFailure.Failed("AI_RATE_LIMITED"))),
            Triple("quota", ReaderTheme.LIGHT, TranslationUiState.Failed(TranslationFailure.QuotaExceeded)),
            Triple("quota-ar", ReaderTheme.PAPER, TranslationUiState.Failed(TranslationFailure.QuotaExceeded)),
        )) {
            compose.runOnIdle { theme.value = appearance; state.value = status; locale.value = if (name.endsWith("-ar")) "ar" else "en"
                allowance.value = TranslationAllowance(5.0, if (name.startsWith("quota")) 0.0 else 3.0, if (name.startsWith("quota")) (System.currentTimeMillis() + 60_000).toDouble() else null) }
            compose.onNodeWithTag("reader.translationStatus").assertIsDisplayed()
            val bitmap = compose.onRoot().captureToImage().asAndroidBitmap()
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val file = java.io.File(context.getExternalFilesDir(null), "reader-status-$name.png")
            file.outputStream().use { bitmap.compress(android.graphics.Bitmap.CompressFormat.PNG, 100, it) }
            InstrumentationRegistry.getInstrumentation().uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Pictures/reader-status-$name.png").use { output ->
                java.io.FileInputStream(output.fileDescriptor).readBytes()
            }
        }
    }
}

@androidx.compose.runtime.Composable
private fun ReaderTestTheme(theme: ReaderTheme = ReaderTheme.DARK, locale: String = "en", content: @androidx.compose.runtime.Composable () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val base = androidx.compose.ui.platform.LocalConfiguration.current
    val configuration = androidx.compose.runtime.remember(base, locale) {
        android.content.res.Configuration(base).apply { setLocale(java.util.Locale.forLanguageTag(locale)) }
    }
    val resources = androidx.compose.runtime.remember(context, configuration) { context.createConfigurationContext(configuration).resources }
    androidx.compose.runtime.CompositionLocalProvider(
        androidx.compose.ui.platform.LocalConfiguration provides configuration,
        androidx.compose.ui.platform.LocalResources provides resources,
        androidx.compose.ui.platform.LocalLayoutDirection provides if (locale == "ar") androidx.compose.ui.unit.LayoutDirection.Rtl else androidx.compose.ui.unit.LayoutDirection.Ltr,
    ) { HadithlyTheme(theme, content = content) }
}
