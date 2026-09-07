package com.hadithly.app

import android.content.res.Configuration
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.SystemBarStyle
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalResources
import androidx.compose.ui.graphics.toArgb
import com.hadithly.app.core.theme.ThemeColors
import com.hadithly.app.core.theme.HadithlyTheme
import com.hadithly.app.core.preferences.LocaleFallback
import com.hadithly.app.features.auth.SignInScreen
import com.hadithly.app.features.main.MainTabs
import com.hadithly.app.features.onboarding.OnboardingFlow
import kotlinx.coroutines.launch
import java.util.Locale

/**
 * Top-level routing: onboarding (welcome → language → straight in) or the
 * main tabs. Guest mode is a first-class state — reading works without an
 * account. Sign-in lives in a full-screen dialog; post-sign-in sync happens
 * in SessionManager so every auth method converges on the same path.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge(
            statusBarStyle = SystemBarStyle.dark(ThemeColors.Background.toArgb()),
            navigationBarStyle = SystemBarStyle.dark(ThemeColors.Background.toArgb()),
        )
        setContent {
            HadithlyTheme {
                LocalizedRootApp()
            }
        }
    }
}

/** Applies the synced UI locale to resources and directional Compose layout. */
@Composable
private fun LocalizedRootApp() {
    val baseContext = LocalContext.current
    val app = baseContext.applicationContext as HadithlyApplication
    val preferences by app.preferences.preferences.collectAsState()
    val baseConfiguration = LocalConfiguration.current
    val localizedConfiguration = remember(baseConfiguration, preferences.uiLocale) {
        Configuration(baseConfiguration).apply {
            setLocale(Locale.forLanguageTag(preferences.uiLocale))
        }
    }
    val localizedResources = remember(baseContext, localizedConfiguration) {
        baseContext.createConfigurationContext(localizedConfiguration).resources
    }
    val layoutDirection = if (LocaleFallback.isRTL(preferences.uiLocale)) {
        LayoutDirection.Rtl
    } else {
        LayoutDirection.Ltr
    }

    CompositionLocalProvider(
        LocalConfiguration provides localizedConfiguration,
        LocalResources provides localizedResources,
        androidx.compose.ui.platform.LocalLayoutDirection provides layoutDirection,
    ) {
        RootApp()
    }
}

@Composable
fun RootApp() {
    val app = LocalContext.current.applicationContext as HadithlyApplication
    val onboardingCompleted by app.settings.onboardingCompleted.collectAsState()

    var showSignIn by remember { mutableStateOf(false) }

    if (onboardingCompleted) {
        MainTabs(
            showSignIn = showSignIn,
            onShowSignIn = { showSignIn = true },
            onDismissSignIn = { showSignIn = false },
        )
    } else {
        OnboardingFlow(
            selectedLanguage = app.preferences.preferences.value.uiLocale,
            onSelectLanguage = { app.preferences.applyOnboardingLanguage(it) },
            onComplete = { app.settings.setOnboardingCompleted(true) },
        )
    }

    if (showSignIn) {
        SignInScreen(
            onAuthenticated = {
                app.appScope.launch { app.session.completeSignIn() }
                showSignIn = false
            },
            onDismiss = { showSignIn = false },
        )
    }
}
