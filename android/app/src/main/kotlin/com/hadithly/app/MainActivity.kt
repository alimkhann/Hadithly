package com.hadithly.app

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import com.hadithly.app.core.theme.HadithlyTheme
import com.hadithly.app.features.auth.SignInScreen
import com.hadithly.app.features.main.MainTabs
import com.hadithly.app.features.onboarding.OnboardingFlow
import kotlinx.coroutines.launch

/**
 * Top-level routing: onboarding (welcome → language → straight in) or the
 * main tabs. Guest mode is a first-class state — reading works without an
 * account. Sign-in lives in a full-screen dialog; post-sign-in sync happens
 * in SessionManager so every auth method converges on the same path.
 */
class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            HadithlyTheme {
                RootApp()
            }
        }
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
            selectedLanguage = app.settings.preferredLanguage.value,
            onSelectLanguage = { app.settings.setPreferredLanguage(it) },
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
