package com.hadithly.app.core.theme

import android.graphics.Bitmap
import androidx.compose.foundation.layout.*
import androidx.compose.material3.Surface
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.Alignment
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.test.*
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.features.auth.SignInMode
import com.hadithly.app.features.auth.SignInScreen
import com.hadithly.app.features.main.HadithlyBottomNavigation
import com.hadithly.app.features.onboarding.OnboardingFlow
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test
import java.io.File

class NativeFinishingTest {
    @get:Rule val compose = createComposeRule()

    @Test fun freshStoreAndLightWelcomeUseDeviceDefaults() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val defaults = context.getSharedPreferences("native-finishing-first-launch", 0)
        defaults.edit().clear().commit()
        try {
            val preferences = com.hadithly.app.core.preferences.PreferencesStore(defaults, listOf("ru-RU"))
            assertEquals(ReaderTheme.SYSTEM, preferences.preferences.value.appTheme)
            assertEquals("ru", preferences.preferences.value.uiLocale)
            preferences.setUILocale("kk")
            assertEquals("kk", com.hadithly.app.core.preferences.PreferencesStore(defaults, listOf("fr-FR")).preferences.value.uiLocale)
        } finally { defaults.edit().clear().commit() }
        val onboarding = context.getSharedPreferences("onboarding", 0)
        val previous = onboarding.all
        onboarding.edit().clear().commit()
        try {
            compose.setContent { LocalizedPreview(ReaderTheme.LIGHT, locale = "ru") {
                com.hadithly.app.features.onboarding.OnboardingFlow("ru", {}, {})
            } }
            compose.onNodeWithTag("onboarding.getStarted").assertTextContains("Начать")
            capture("welcome-light-russian")
        } finally {
            val edit = onboarding.edit().clear()
            previous.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
            edit.commit()
        }
    }

    @OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
    @Test fun nativeReaderSheetsAndEmptyStates() {
        var scene by mutableStateOf("contents")
        val app = com.hadithly.app.HadithlyApplication.instance()
        val hadith = com.hadithly.app.core.data.ReaderHadith(_id = "finishing-57", provider = "sunnah_now", canonicalId = "sunnah_now:bukhari:57", providerHadithId = "57", collectionSlug = "bukhari",
            arabicText = "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ", englishText = "Actions are judged by intentions.", referenceDisplay = "Sahih al-Bukhari · Hadith 57", collectionName = "Sahih al-Bukhari",
            authenticity = com.hadithly.app.core.data.AuthenticityClaim(kind = "collection_scope", normalizedGrade = "sahih", claimScope = "collection", sourceLabel = "Documented Sahih collection", sourceName = "Sunnah.now", sourceUrl = "https://sunnah.now", verificationMethod = "manual_collection_mapping"))
        val ref = com.hadithly.app.core.data.HadithRef(hadithId = hadith._id, collectionSlug = "bukhari", collectionName = hadith.collectionName, volumeId = "1", hadithNumber = "57", referenceDisplay = hadith.referenceDisplay, arabicText = hadith.arabicText, englishText = hadith.englishText)
        compose.setContent { LocalizedPreview(ReaderTheme.PAPER) {
            Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                key(scene) {
                    if (scene == "saved-main") androidx.compose.material3.Scaffold(bottomBar = { HadithlyBottomNavigation(2) {} }, containerColor = LocalHadithlyColors.current.background) { padding -> Box(Modifier.padding(padding)) { com.hadithly.app.features.saved.SavedScreen {} } }
                    else if (scene == "bookmark") com.hadithly.app.features.reader.BookmarkPlacementSheet(com.hadithly.app.features.reader.BookmarkPlacementTargets(hadith, hadith), { false }, {}, {})
                    else androidx.compose.material3.ModalBottomSheet(onDismissRequest = {}, containerColor = LocalHadithlyColors.current.background,
                        sheetState = androidx.compose.material3.rememberModalBottomSheetState(skipPartiallyExpanded = true)) {
                        when (scene) {
                            "contents" -> com.hadithly.app.features.reader.ContentsSheet(listOf(com.hadithly.app.core.data.OutlineVolume("1", "Volume 1", "Revelation", 58.0,
                                listOf(com.hadithly.app.core.data.OutlineChapter("1", "Revelation", "كتاب بدء الوحي", 7.0, "1")))), "1", "Sahih al-Bukhari", true, {}, { _, _ -> }, { true }, {})
                            "search" -> com.hadithly.app.features.reader.ReaderSearchSheet({ emptyList() }, {}, {})
                            "saved" -> com.hadithly.app.features.reader.ReaderSavedSheet(listOf(com.hadithly.app.core.data.SavedItemEntry(hadith._id, System.currentTimeMillis().toDouble() - 300_000, System.currentTimeMillis().toDouble() - 300_000, bookmarkCreatedAt = System.currentTimeMillis().toDouble() - 300_000, hadith = ref)), emptyList(), app.library, {}, {}, {})
                            else -> com.hadithly.app.features.saved.SavedScreen {}
                        }
                    }
                }
            }
        } }
        for (next in listOf("contents", "search", "saved", "bookmark", "saved-main")) {
            compose.runOnIdle { scene = next }
            compose.waitForIdle()
            capture("reader-$next")
            if (next == "search") {
                compose.onNodeWithTag("reader.search.field").performTextInput("zzz-no-match")
                compose.mainClock.advanceTimeBy(1000)
                compose.onNodeWithTag("reader.search.empty").assertIsDisplayed()
                capture("reader-search-empty")
            }
            if (next == "saved-main") {
                compose.onNodeWithTag("saved.filter.notes").performClick().assertIsSelected()
                capture("reader-saved-main-notes")
            }
            if (next == "saved") {
                compose.onNodeWithTag("reader.saved.tab.notes").performClick().assertIsSelected()
                compose.onNodeWithTag("reader.saved.empty").assertIsDisplayed()
                capture("reader-saved-notes-empty")
            }
        }
    }

    @Test fun firstInstallAndAccountRoutes() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("onboarding", 0)
        val previous = prefs.all
        prefs.edit().clear().commit()
        try {
            compose.setContent { LocalizedPreview(ReaderTheme.DARK) { OnboardingFlow("en", {}, {}) } }
            compose.onNodeWithTag("onboarding.getStarted").assertIsDisplayed()
            capture("01-welcome")
            compose.onNodeWithTag("onboarding.getStarted").performClick()
            compose.onNodeWithTag("onboarding.continue").assertIsDisplayed()
            capture("02-language")
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.reveal").assertIsDisplayed()
            capture("03-example-ready")
            compose.onNodeWithTag("onboarding.reveal").performClick()
            compose.onNodeWithTag("onboarding.example").assertIsDisplayed()
            capture("04-example-revealed")
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.guest").performScrollTo().assertIsDisplayed()
            capture("05-account")
            compose.onNodeWithTag("onboarding.createAccount").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.sign_up").assertExists()
            capture("06-sign-up")
            compose.onNodeWithTag("signin.close").performClick()
            compose.onNodeWithTag("onboarding.signIn").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.methods").assertExists()
            capture("07-auth-methods")
            compose.onNodeWithText("Continue with email").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.password_sign_in").assertExists()
            capture("08-password")
            compose.onNodeWithTag("signin.forgot").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.forgot_password_entry").assertExists()
            capture("09-recovery")
            compose.onNodeWithTag("signin.back").performClick()
            compose.onNodeWithTag("signin.useCode").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.email_entry").assertExists()
            capture("10-email-code-entry")
        } finally {
            val edit = prefs.edit().clear()
            previous.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
            edit.commit()
        }
    }

    @Test fun codeResetAndKeyboardPreviewStates() {
        var mode by mutableStateOf(SignInMode.CODE_ENTRY)
        var imeVisible = false
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.executeShellCommand("settings put secure show_ime_with_hard_keyboard 1").close()
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT) {
            val imeBottom = WindowInsets.ime.getBottom(LocalDensity.current)
            SideEffect { imeVisible = imeBottom > 0 }
            key(mode) { SignInScreen({}, {}, previewMode = mode) }
        } }
        for (entry in listOf(SignInMode.CODE_ENTRY, SignInMode.RESET_PASSWORD, SignInMode.SIGN_UP)) {
            compose.runOnIdle { mode = entry }
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("signin.screen.${entry.name.lowercase()}").fetchSemanticsNodes().isNotEmpty() }
            capture("auth-${entry.name.lowercase()}")
        }
        compose.onNodeWithText("you@example.com").performClick().performTextInput("reader@example.org")
        compose.waitUntil(10_000) { imeVisible }
        compose.onNodeWithText("Create account").performScrollTo().assertIsDisplayed()
        capture("sign-up-keyboard")
    }

    @Test fun bottomNavigationKeepsSelectionAndSupportsLargeRTLText() {
        var large by mutableStateOf(false)
        compose.setContent {
            LocalizedPreview(ReaderTheme.LIGHT) {
                CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, if (large) 2f else 1f),
                    LocalLayoutDirection provides if (large) LayoutDirection.Rtl else LayoutDirection.Ltr) {
                    var selected by remember { mutableIntStateOf(0) }
                    Surface(Modifier.fillMaxSize(), color = LocalHadithlyColors.current.background) {
                        androidx.compose.material3.Scaffold(containerColor = LocalHadithlyColors.current.background,
                            bottomBar = { HadithlyBottomNavigation(selected) { selected = it } }) { padding ->
                            Box(Modifier.padding(padding)) { com.hadithly.app.features.settings.SettingsScreen {} }
                        }
                    }
                }
            }
        }
        for (tag in listOf("today", "library", "saved", "settings")) {
            compose.onNodeWithTag("tabs.$tag").performClick().assertIsSelected()
        }
        capture("bottom-navigation")
        compose.runOnIdle { large = true }
        compose.onNodeWithTag("tabs.today").performClick().assertIsSelected()
        compose.onNodeWithTag("tabs.settings").performClick().assertIsSelected()
        capture("bottom-navigation-large-rtl")
    }

    @Test fun smallLargeTextAuthRemainsScrollable() {
        compose.setContent { LocalizedPreview(ReaderTheme.LIGHT) {
            CompositionLocalProvider(LocalDensity provides Density(LocalDensity.current.density, 2f), LocalLayoutDirection provides LayoutDirection.Rtl) {
                Box(Modifier.fillMaxWidth().height(560.dp)) { SignInScreen({}, {}, previewMode = SignInMode.SIGN_UP) }
            }
        } }
        compose.waitUntil(10_000) { compose.onAllNodesWithTag("signin.screen.sign_up").fetchSemanticsNodes().isNotEmpty() }
        compose.onNodeWithText("Create account").performScrollTo().assertIsDisplayed()
        capture("sign-up-small-large-rtl")
    }

    private fun capture(name: String) {
        compose.waitForIdle()
        Thread.sleep(350) // Native window presentation completes outside the Compose test clock.
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val file = File(instrumentation.targetContext.getExternalFilesDir(null), "finishing-$name.png")
        instrumentation.uiAutomation.takeScreenshot().let { bitmap ->
            file.outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }; bitmap.recycle()
        }
        instrumentation.uiAutomation.executeShellCommand("cp ${file.absolutePath} /sdcard/Pictures/finishing-$name.png").close()
    }
}

@Composable
private fun LocalizedPreview(theme: ReaderTheme, locale: String = "en", content: @Composable () -> Unit) {
    val context = androidx.compose.ui.platform.LocalContext.current
    val configuration = android.content.res.Configuration(androidx.compose.ui.platform.LocalConfiguration.current).apply { setLocale(java.util.Locale.forLanguageTag(locale)); setLayoutDirection(java.util.Locale.forLanguageTag(locale)) }
    val localized = context.createConfigurationContext(configuration)
    CompositionLocalProvider(androidx.compose.ui.platform.LocalContext provides localized,
        androidx.compose.ui.platform.LocalConfiguration provides configuration,
        androidx.compose.ui.platform.LocalResources provides localized.resources,
        LocalLayoutDirection provides if (locale == "ar") LayoutDirection.Rtl else LayoutDirection.Ltr) { HadithlyTheme(theme, content) }
}
