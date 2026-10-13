package com.hadithly.app.features.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.R
import com.hadithly.app.core.analytics.AnalyticsMetric
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.core.theme.TranslationPresentationPhase
import com.hadithly.app.core.theme.TranslationReveal
import com.hadithly.app.features.auth.SignInScreen
import kotlinx.coroutines.launch

@Composable
fun OnboardingFlow(selectedLanguage: String, onSelectLanguage: (String) -> Unit, onComplete: () -> Unit) {
    val app = LocalContext.current.applicationContext as HadithlyApplication
    val prefs = remember { app.getSharedPreferences("onboarding", 0) }
    var step by remember { mutableIntStateOf(prefs.getInt("step", 0).coerceIn(0, 3)) }
    var completedCreation by remember { mutableStateOf<Boolean?>(null) }
    var auth by remember { mutableStateOf<Boolean?>(null) }
    val colors = LocalHadithlyColors.current
    fun advance(value: Int) { prefs.edit().putInt("step", value).apply(); step = value }
    fun finish(metric: AnalyticsMetric) {
        app.analytics.completeOnboarding(metric); prefs.edit().clear().apply(); onComplete()
    }
    LaunchedEffect(step) {
        val bit = 1 shl step
        val visited = prefs.getInt("visited", 0)
        if (visited and bit == 0) {
            prefs.edit().putInt("visited", visited or bit).apply()
            app.analytics.record(listOf(AnalyticsMetric.onboardingStepWelcomeViewed, AnalyticsMetric.onboardingStepLanguageViewed,
                AnalyticsMetric.onboardingStepDemoViewed, AnalyticsMetric.onboardingStepEntryViewed)[step])
        }
        if (step > 0) app.analytics.startOnboarding()
    }
    if (auth != null) {
        val create = auth == true
        SignInScreen(onAuthenticated = {
            app.appScope.launch { app.session.completeSignIn(); auth = null
                if (!app.isSignedIn()) app.analytics.record(AnalyticsMetric.onboardingStepAuthFailed)
                else finish(when (completedCreation) { true -> AnalyticsMetric.onboardingCompletedAccountNew; false -> AnalyticsMetric.onboardingCompletedAccountExisting; null -> AnalyticsMetric.onboardingCompletedAccountUnknown }) }
        }, onDismiss = { app.analytics.record(AnalyticsMetric.onboardingStepAuthCancelled); auth = null }, initialSignUp = create, onCreationResult = { completedCreation = it },
            onAuthenticationFailure = { app.analytics.record(AnalyticsMetric.onboardingStepAuthFailed) })
        return
    }
    Column(Modifier.fillMaxSize().background(colors.background).statusBarsPadding().navigationBarsPadding()) {
        if (step > 0) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
            TextButton(onClick = { advance(step - 1) }, modifier = Modifier.testTag("onboarding.back")) { Text(stringResource(R.string.la2_back)) }
            Spacer(Modifier.weight(1f))
            if (step == 2) TextButton(onClick = { app.analytics.record(AnalyticsMetric.onboardingStepDemoSkipped); advance(3) },
                modifier = Modifier.testTag("onboarding.skip")) { Text(stringResource(R.string.la2_skip)) }
        }
        when (step) {
            0 -> WelcomeScreen { app.analytics.startOnboarding(); advance(1) }
            1 -> LanguagePickerScreen(selectedLanguage, onSelectLanguage) { advance(2) }
            2 -> TranslationDemonstration(selectedLanguage, { app.analytics.record(AnalyticsMetric.onboardingStepDemoUsed) }) { advance(3) }
            3 -> Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
                    horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.spacedBy(20.dp)) {
                BookArtwork(Modifier.fillMaxWidth().height(240.dp))
                Text(stringResource(R.string.la2_account_title), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary, textAlign = TextAlign.Center)
                Text(stringResource(R.string.la2_account_body), style = MaterialTheme.typography.bodyLarge, color = colors.textSecondary, textAlign = TextAlign.Center)
                AccentButton(stringResource(R.string.la2_create_account), { app.analytics.record(AnalyticsMetric.onboardingStepAuthStarted); auth = true }, "onboarding.createAccount")
                OutlinedButton(onClick = { app.analytics.record(AnalyticsMetric.onboardingStepAuthStarted); auth = false }, modifier = Modifier.fillMaxWidth().testTag("onboarding.signIn")) {
                    Text(stringResource(R.string.la2_sign_in), color = colors.textPrimary)
                }
                TextButton(onClick = { finish(AnalyticsMetric.onboardingCompletedGuest) }, modifier = Modifier.testTag("onboarding.guest")) {
                    Text(stringResource(R.string.la2_guest), color = colors.textSecondary)
                }
                Text(stringResource(R.string.la2_reading_free), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
            }
        }
    }
}

@Composable
fun BookArtwork(modifier: Modifier = Modifier) {
    Image(painterResource(R.drawable.onboarding_book), contentDescription = null, modifier = modifier,
        contentScale = androidx.compose.ui.layout.ContentScale.Crop)
}

@Composable
fun WelcomeScreen(onContinue: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Text("Hadithly", style = MaterialTheme.typography.titleLarge, color = colors.textPrimary, modifier = Modifier.padding(top = 36.dp))
            Text(stringResource(R.string.la2_welcome), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary,
                textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 28.dp))
            BookArtwork(Modifier.fillMaxWidth().height(400.dp))
        }
        Box(Modifier.padding(24.dp)) { AccentButton(stringResource(R.string.la2_get_started), onContinue, "onboarding.getStarted") }
    }
}

@Composable
fun LanguagePickerScreen(selection: String, onSelect: (String) -> Unit, onContinue: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxSize().padding(24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.la2_language), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary)
        Text(stringResource(R.string.la2_suggested), style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
        LazyColumn(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            items(SupportedLanguages.all, key = { it.first }) { (code, name) ->
                Row(Modifier.fillMaxWidth().background(if (selection == code) colors.accentSoft else colors.surface, RoundedCornerShape(12.dp))
                    .selectable(selected = selection == code, role = Role.RadioButton, onClick = { onSelect(code) }).heightIn(min = 56.dp).padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(name, style = MaterialTheme.typography.bodyLarge, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    RadioButton(selected = selection == code, onClick = null)
                }
            }
        }
        AccentButton(stringResource(R.string.la2_continue), onContinue, "onboarding.continue")
    }
}

@Composable
private fun TranslationDemonstration(locale: String, onReveal: () -> Unit, onContinue: () -> Unit) {
    val colors = LocalHadithlyColors.current
    var phase by remember { mutableStateOf(TranslationPresentationPhase.Idle) }
    Column(Modifier.fillMaxSize()) {
        Column(Modifier.weight(1f).verticalScroll(rememberScrollState()).padding(28.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            Text(stringResource(R.string.la2_demo_title), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary)
            Text(stringResource(R.string.la2_source), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
            Text(PreparedTranslationExample.arabic, style = MaterialTheme.typography.headlineMedium.copy(fontFamily = com.hadithly.app.core.theme.ArabicTypefaces.amiri, textDirection = androidx.compose.ui.text.style.TextDirection.Rtl),
                color = colors.textPrimary, textAlign = TextAlign.End, modifier = Modifier.fillMaxWidth())
            TranslationReveal(phase) {
                Text(if (locale == "ar") stringResource(R.string.la2_source_details) else PreparedTranslationExample.translations[locale] ?: "",
                    style = MaterialTheme.typography.titleLarge, color = colors.textPrimary,
                    modifier = Modifier.testTag("onboarding.example").semantics { liveRegion = LiveRegionMode.Polite })
            }
            if (phase == TranslationPresentationPhase.Idle) TextButton(onClick = { phase = TranslationPresentationPhase.Available; onReveal() }, modifier = Modifier.testTag("onboarding.reveal")) {
                Text(stringResource(R.string.la2_see_example), color = colors.interactive)
            }
            Text(stringResource(R.string.la2_sample_label), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
            Text(stringResource(R.string.la2_sample_notice), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
        }
        Box(Modifier.padding(24.dp)) { AccentButton(stringResource(R.string.la2_continue), onContinue, "onboarding.continue") }
    }
}

@Composable
fun AccentButton(text: String, onClick: () -> Unit, tag: String = "") {
    val colors = LocalHadithlyColors.current
    Button(onClick = onClick, shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag(tag)) { Text(text, style = MaterialTheme.typography.titleMedium) }
}
