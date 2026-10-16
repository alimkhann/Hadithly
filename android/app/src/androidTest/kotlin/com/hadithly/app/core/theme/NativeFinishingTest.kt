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
import com.hadithly.app.core.preferences.LocaleFallback
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
        var previewLocale by mutableStateOf("en")
        val app = com.hadithly.app.HadithlyApplication.instance()
        val hadith = com.hadithly.app.core.data.ReaderHadith(_id = "finishing-57", provider = "sunnah_now", canonicalId = "sunnah_now:bukhari:57", providerHadithId = "57", collectionSlug = "bukhari",
            arabicText = "إِنَّمَا الأَعْمَالُ بِالنِّيَّاتِ", englishText = "Actions are judged by intentions.", referenceDisplay = "Sahih al-Bukhari · Hadith 57", collectionName = "Sahih al-Bukhari",
            authenticity = com.hadithly.app.core.data.AuthenticityClaim(kind = "collection_scope", normalizedGrade = "sahih", claimScope = "collection", sourceLabel = "Documented Sahih collection", sourceName = "Sunnah.now", sourceUrl = "https://sunnah.now", verificationMethod = "manual_collection_mapping"))
        val ref = com.hadithly.app.core.data.HadithRef(hadithId = hadith._id, collectionSlug = "bukhari", collectionName = hadith.collectionName, volumeId = "1", hadithNumber = "57", referenceDisplay = hadith.referenceDisplay, arabicText = hadith.arabicText, englishText = hadith.englishText)
        compose.setContent { LocalizedPreview(ReaderTheme.PAPER, previewLocale) {
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
        for (locale in listOf("ar", "ur")) {
            compose.runOnIdle { previewLocale = locale; scene = "contents" }
            compose.waitForIdle()
            capture("normal-$locale-reader-contents")
            compose.runOnIdle { scene = "saved" }
            compose.waitForIdle()
            capture("normal-$locale-reader-saved")
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
            compose.waitUntil(30_000) {
                compose.onAllNodesWithTag("onboarding.dailyText").fetchSemanticsNodes().isNotEmpty() ||
                    compose.onAllNodesWithTag("onboarding.dailyRetry").fetchSemanticsNodes().isNotEmpty()
            }
            val dailyText = compose.onAllNodesWithTag("onboarding.dailyText").fetchSemanticsNodes().isNotEmpty()
            if (dailyText) {
                compose.onNodeWithTag("onboarding.dailyText").assertIsDisplayed()
                capture("03-daily-hadith")
            } else {
                compose.onNodeWithTag("onboarding.dailyRetry").assertIsDisplayed()
                capture("03-daily-unavailable-retry")
            }
            compose.onNodeWithTag("onboarding.continue").performClick()
            compose.onNodeWithTag("onboarding.guest").assertIsDisplayed()
            capture("05-account")
            compose.onNodeWithTag("onboarding.signIn").performClick()
            compose.onNodeWithTag("signin.screen.methods").assertExists()
            capture("06-auth-methods")
            compose.onNodeWithTag("signin.createAccount").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.sign_up").assertExists()
            capture("07-sign-up")
            compose.onNodeWithTag("signin.close").performClick()
            compose.onNodeWithTag("onboarding.signIn").performClick()
            compose.onNodeWithTag("signin.screen.methods").assertExists()
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

    @Test fun settingsSignInHidesTheUnderlyingAccessibilityTreeAndCancelRestoresTheTab() {
        val app = InstrumentationRegistry.getInstrumentation().targetContext.applicationContext as com.hadithly.app.HadithlyApplication
        val previous = app.settings.onboardingCompleted.value
        try {
            app.settings.setOnboardingCompleted(true)
            compose.setContent { LocalizedPreview(ReaderTheme.LIGHT) { com.hadithly.app.RootApp() } }
            compose.waitUntil(10_000) { compose.onAllNodesWithTag("tabs.settings").fetchSemanticsNodes().isNotEmpty() }
            compose.onNodeWithTag("tabs.settings").performClick()
            compose.onNodeWithTag("settings.signin").performClick()
            compose.onNodeWithText("Continue with email").performScrollTo().performClick()
            compose.onNodeWithTag("signin.screen.password_sign_in").assertIsDisplayed()
            compose.onNodeWithTag("tabs.settings").assertDoesNotExist()
            capture("settings-inline-sign-in")
            compose.onNodeWithTag("signin.close").performClick()
            compose.onNodeWithTag("tabs.settings").assertIsSelected()
            compose.onNodeWithTag("settings.signin").assertIsDisplayed()
        } finally { app.settings.setOnboardingCompleted(previous) }
    }

    @Test fun annualPricingPrototypeShowsMonthlyEquivalentAndNativeSelection() {
        var theme by mutableStateOf(ReaderTheme.LIGHT)
        compose.setContent { LocalizedPreview(theme) {
            var annual by remember { mutableStateOf(true) }
            Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(20.dp)) {
                androidx.compose.material3.Text(androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.la2_more_translations),
                    style = androidx.compose.material3.MaterialTheme.typography.headlineLarge, color = LocalHadithlyColors.current.textPrimary)
                androidx.compose.material3.Text(androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.la2_allowance),
                    style = androidx.compose.material3.MaterialTheme.typography.bodyMedium, color = LocalHadithlyColors.current.textSecondary)
                com.hadithly.app.features.purchases.PaywallPlanOption(true, annual, "$2.08", 30) { annual = true }
                com.hadithly.app.features.purchases.PaywallPlanOption(false, !annual, "$2.99", null) { annual = false }
                androidx.compose.material3.Button(onClick = {}, enabled = false, modifier = Modifier.fillMaxWidth()) {
                    androidx.compose.material3.Text(androidx.compose.ui.res.stringResource(if (annual) com.hadithly.app.R.string.la2_subscribe_annual else com.hadithly.app.R.string.la2_subscribe_monthly))
                }
                androidx.compose.material3.Text(androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.la2_renewal),
                    style = androidx.compose.material3.MaterialTheme.typography.bodySmall, color = LocalHadithlyColors.current.textSecondary)
            }
        } }
        compose.onNodeWithTag("paywall.annual").assertIsSelected()
        compose.onNodeWithText("$2.08").assertIsDisplayed()
        compose.onNodeWithText("$24.99").assertDoesNotExist()
        compose.onNodeWithTag("paywall.monthly").performClick().assertIsSelected()
        compose.onNodeWithTag("paywall.annual").performClick()
        capture("paywall-prototype-light")
        compose.runOnIdle { theme = ReaderTheme.DARK }
        capture("paywall-prototype-dark")
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

    @Test fun normalArabicAndUrduWelcomeAndAccountScreens() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val prefs = context.getSharedPreferences("onboarding", 0)
        val previous = prefs.all
        var route by mutableStateOf("ar-welcome")
        try {
            prefs.edit().clear().putInt("step", 0).commit()
            compose.setContent {
                key(route) {
                    val locale = route.substringBefore('-')
                    LocalizedPreview(ReaderTheme.LIGHT, locale) { OnboardingFlow(locale, {}, {}) }
                }
            }
            for (next in listOf("ar-welcome", "ar-account", "ur-welcome", "ur-account")) {
                if (next != route) compose.runOnIdle {
                    prefs.edit().putInt("step", if (next.endsWith("account")) 3 else 0).commit()
                    route = next
                }
                compose.waitForIdle()
                if (next.endsWith("welcome")) {
                    compose.onNodeWithTag("onboarding.getStarted").assertIsDisplayed()
                } else {
                    compose.onNodeWithTag("onboarding.signIn").assertIsDisplayed()
                    compose.onNodeWithTag("onboarding.guest").assertIsDisplayed()
                }
                capture("normal-$next")
            }
        } finally {
            val edit = prefs.edit().clear()
            previous.forEach { (key, value) -> when (value) { is Int -> edit.putInt(key, value); is Boolean -> edit.putBoolean(key, value); is String -> edit.putString(key, value) } }
            edit.commit()
        }
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
        LocalLayoutDirection provides if (LocaleFallback.isRTL(locale)) LayoutDirection.Rtl else LayoutDirection.Ltr) { HadithlyTheme(theme, content) }
}
