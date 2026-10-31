package com.hadithly.app.features.onboarding

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInHorizontally
import androidx.compose.animation.togetherWith
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.interaction.collectIsPressedAsState
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
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.R
import com.hadithly.app.core.analytics.AnalyticsMetric
import com.hadithly.app.core.data.FirstReadingResult
import com.hadithly.app.core.data.FirstReadingDocument
import com.hadithly.app.core.data.FirstReadingTextKind
import com.hadithly.app.core.data.ReaderTargetSource
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.preferences.nativeText
import com.hadithly.app.core.theme.HadithReadingText
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.auth.SignInScreen
import kotlinx.coroutines.launch

@Composable
fun OnboardingFlow(selectedLanguage: String, onSelectLanguage: (String) -> Unit, onComplete: () -> Unit) {
    val app = LocalContext.current.applicationContext as HadithlyApplication
    val prefs = remember { app.getSharedPreferences("onboarding", 0) }
    var step by remember { mutableIntStateOf(prefs.getInt("step", 0).coerceIn(0, 3)) }
    var completedCreation by remember { mutableStateOf<Boolean?>(null) }
    var auth by remember { mutableStateOf(false) }
    var openedFirstReading by remember { mutableStateOf<FirstReadingDocument?>(null) }
    val firstReadingSession = remember(openedFirstReading) { System.nanoTime() }
    val readingPreferences by app.preferences.preferences.collectAsState()
    val colors = LocalHadithlyColors.current
    fun advance(value: Int) { prefs.edit().putInt("step", value).apply(); step = value }
    fun finish(metric: AnalyticsMetric) {
        app.analytics.completeOnboarding(metric)
        prefs.edit().clear().apply()
        onComplete()
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
    val opened = openedFirstReading
    if (opened != null) {
        com.hadithly.app.features.reader.ReaderScreen(collectionSlug = opened.collectionSlug, collectionName = opened.collectionName,
            openVolumeId = opened.volumeId, openHadithNumber = opened.providerHadithId, openPosition = null,
            targetSource = ReaderTargetSource.CANONICAL_LINK, instanceKey = firstReadingSession, onClose = { openedFirstReading = null })
        return
    }
    if (auth) {
        SignInScreen(onAuthenticated = {
            app.appScope.launch {
                app.session.completeSignIn()
                auth = false
                if (!app.isSignedIn()) app.analytics.record(AnalyticsMetric.onboardingStepAuthFailed)
                else finish(when (completedCreation) {
                    true -> AnalyticsMetric.onboardingCompletedAccountNew
                    false -> AnalyticsMetric.onboardingCompletedAccountExisting
                    null -> AnalyticsMetric.onboardingCompletedAccountUnknown
                })
            }
        }, onDismiss = {
            app.analytics.record(AnalyticsMetric.onboardingStepAuthCancelled)
            auth = false
        }, onCreationResult = { completedCreation = it }, onAuthenticationFailure = {
            app.analytics.record(AnalyticsMetric.onboardingStepAuthFailed)
        })
        return
    }
    Box(Modifier.fillMaxSize()) {
        if (step == 0 || step == 3) com.hadithly.app.core.theme.EntryArtworkBackdrop()
        else Box(Modifier.matchParentSize().background(colors.background))
        Column(Modifier.fillMaxSize().statusBarsPadding().navigationBarsPadding()) {
            if (step > 0) Row(Modifier.fillMaxWidth().padding(horizontal = 16.dp), verticalAlignment = Alignment.CenterVertically) {
                TextButton(onClick = { advance(step - 1) }, modifier = Modifier.testTag("onboarding.back")) { Text(stringResource(R.string.la2_back)) }
            }
            val motionAllowed = com.hadithly.app.core.theme.rememberMotionAllowed()
            val stepDistance = with(androidx.compose.ui.platform.LocalDensity.current) { com.hadithly.app.core.theme.InterfaceMotion.TRAVEL_DP.dp.roundToPx() } *
                if (androidx.compose.ui.platform.LocalLayoutDirection.current == androidx.compose.ui.unit.LayoutDirection.Rtl) -1 else 1
            AnimatedContent(targetState = step, label = "onboarding step", modifier = Modifier.weight(1f), transitionSpec = {
                val distance = if (motionAllowed) { if (targetState > initialState) stepDistance else -stepDistance } else 0
                (fadeIn(tween(if (motionAllowed) com.hadithly.app.core.theme.InterfaceMotion.STEP else 0)) + slideInHorizontally(tween(if (motionAllowed) com.hadithly.app.core.theme.InterfaceMotion.STEP else 0)) { distance }) togetherWith fadeOut(tween(if (motionAllowed) com.hadithly.app.core.theme.InterfaceMotion.QUICK else 0))
            }) { currentStep ->
                when (currentStep) {
                    0 -> WelcomeScreen(showsBackground = false)
                    1 -> LanguagePickerScreen(selectedLanguage, onSelectLanguage)
                    2 -> TranslationDemonstration(readingPreferences.translationLocale, onChooseLanguage = { advance(1) }, onOpen = { openedFirstReading = it })
                    3 -> AccountEntryScreen()
                }
            }
            if (step == 3) {
                Column(Modifier.fillMaxWidth().padding(horizontal = 24.dp, vertical = 20.dp), horizontalAlignment = Alignment.CenterHorizontally) {
                    AccentButton(stringResource(R.string.la2_sign_in), {
                        completedCreation = null
                        app.analytics.record(AnalyticsMetric.onboardingStepAuthStarted)
                        auth = true
                    }, "onboarding.signIn")
                    TextButton(onClick = { finish(AnalyticsMetric.onboardingCompletedGuest) }, modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).testTag("onboarding.guest")) {
                        Text(stringResource(R.string.la2_guest), color = colors.textSecondary)
                    }
                }
            } else {
                val label = if (step == 0) stringResource(R.string.la2_get_started) else stringResource(R.string.la2_continue)
                Box(Modifier.padding(24.dp)) {
                    AccentButton(label, {
                        if (step == 0) app.analytics.startOnboarding()
                        advance(step + 1)
                    }, if (step == 0) "onboarding.getStarted" else "onboarding.continue")
                }
            }
        }
    }
}

@Composable
private fun AccountEntryScreen() {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp),
        horizontalAlignment = Alignment.CenterHorizontally, verticalArrangement = Arrangement.Center) {
        Text(stringResource(R.string.la2_account_title), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary, textAlign = TextAlign.Center)
        Spacer(Modifier.height(12.dp))
        Text(stringResource(R.string.la2_account_body), style = MaterialTheme.typography.bodyLarge, color = colors.textSecondary, textAlign = TextAlign.Center)
    }
}

@Composable
fun WelcomeScreen(showsBackground: Boolean = true) {
    val colors = LocalHadithlyColors.current
    Box(Modifier.fillMaxSize()) {
        if (showsBackground) com.hadithly.app.core.theme.EntryArtworkBackdrop()
        Column(Modifier.fillMaxSize()) {
            Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(24.dp)) {
                Text("Hadithly", style = MaterialTheme.typography.titleLarge, color = colors.textPrimary, modifier = Modifier.padding(top = 36.dp))
                Text(stringResource(R.string.la2_welcome), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary,
                    textAlign = TextAlign.Center, modifier = Modifier.padding(horizontal = 28.dp))
            }
        }
    }
}

@Composable
fun LanguagePickerScreen(selection: String, onSelect: (String) -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxSize().padding(horizontal = 24.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
        Text(stringResource(R.string.la2_language), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary)
        Text(stringResource(R.string.la2_suggested), style = MaterialTheme.typography.bodyMedium, color = colors.textSecondary)
        LazyColumn(Modifier.weight(1f).fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(24.dp)) {
            items(SupportedLanguages.all, key = { it.first }) { (code, name) ->
                Row(Modifier.fillMaxWidth().background(if (selection == code) colors.accentSoft else colors.surface, RoundedCornerShape(12.dp))
                    .selectable(selected = selection == code, role = Role.RadioButton, onClick = { onSelect(code) }).heightIn(min = 56.dp).padding(16.dp),
                    verticalAlignment = Alignment.CenterVertically) {
                    Text(SupportedLanguages.flag(code), style = MaterialTheme.typography.titleLarge, modifier = Modifier.padding(end = 12.dp).clearAndSetSemantics {})
                    Text(name, style = MaterialTheme.typography.bodyLarge, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    RadioButton(selected = selection == code, onClick = null)
                }
            }
        }
    }
}

internal sealed interface FirstReadingPhase {
    data object Loading : FirstReadingPhase
    data object Failed : FirstReadingPhase
    data class Result(val value: FirstReadingResult) : FirstReadingPhase
}

@Composable
internal fun TranslationDemonstration(locale: String, onChooseLanguage: () -> Unit = {}, onOpen: (FirstReadingDocument) -> Unit = {}) {
    val app = LocalContext.current.applicationContext as HadithlyApplication
    FirstReadingSession(locale, app.repository::observeFirstReading, onChooseLanguage, onOpen) {
        app.analytics.record(AnalyticsMetric.onboardingStepDemoUsed)
    }
}

@Composable
internal fun FirstReadingSession(locale: String, source: (String) -> kotlinx.coroutines.flow.Flow<FirstReadingResult>, onChooseLanguage: () -> Unit = {}, onOpen: (FirstReadingDocument) -> Unit = {}, onRendered: () -> Unit = {}) {
    var phase by remember(locale) { mutableStateOf<FirstReadingPhase>(FirstReadingPhase.Loading) }
    var retry by remember(locale) { mutableIntStateOf(0) }
    var recorded by remember(locale) { mutableStateOf(false) }
    LaunchedEffect(locale, retry) {
        phase = FirstReadingPhase.Loading
        try {
            source(locale).collect { result ->
                phase = if (result.locale != locale) FirstReadingPhase.Failed
                else if (result is FirstReadingResult.Ready && result.validUntil != null && result.validUntil <= System.currentTimeMillis()) {
                    FirstReadingPhase.Result(FirstReadingResult.Unavailable(locale, "not_prepared", result.daily))
                } else FirstReadingPhase.Result(result)
            }
        } catch (cancelled: kotlinx.coroutines.CancellationException) { throw cancelled }
        catch (_: Exception) { phase = FirstReadingPhase.Failed }
    }
    val ready = (phase as? FirstReadingPhase.Result)?.value as? FirstReadingResult.Ready
    LaunchedEffect(ready?.validUntil) {
        val expiry = ready?.validUntil ?: return@LaunchedEffect
        kotlinx.coroutines.delay((expiry - System.currentTimeMillis()).toLong().coerceAtLeast(0))
        if ((phase as? FirstReadingPhase.Result)?.value == ready) phase = FirstReadingPhase.Result(FirstReadingResult.Unavailable(locale, "not_prepared", ready.daily))
    }
    FirstReadingContent(phase, { retry++ }, onChooseLanguage, onOpen) {
        if (!recorded) { recorded = true; onRendered() }
    }
}

@Composable
internal fun FirstReadingContent(phase: FirstReadingPhase, onRetry: () -> Unit, onChooseLanguage: () -> Unit, onOpen: (FirstReadingDocument) -> Unit, onRendered: () -> Unit = {}) {
    val colors = LocalHadithlyColors.current
    val uri = androidx.compose.ui.platform.LocalUriHandler.current
    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp, vertical = 28.dp), verticalArrangement = Arrangement.spacedBy(24.dp)) {
        Text(stringResource(R.string.la2_demo_title), style = MaterialTheme.typography.headlineLarge, color = colors.textPrimary)
        when (phase) {
            FirstReadingPhase.Loading -> com.hadithly.app.core.theme.ContentSkeleton(kind = com.hadithly.app.core.theme.SkeletonKind.Daily, label = nativeText("Loading…"), modifier = Modifier.fillMaxWidth().testTag("onboarding.dailyLoading"))
            FirstReadingPhase.Failed -> {
                Text(nativeText("Reading could not load"), color = colors.textSecondary)
                TextButton(onClick = onRetry, modifier = Modifier.heightIn(min = 48.dp).testTag("onboarding.dailyRetry")) { Text(nativeText("Try again")) }
            }
            is FirstReadingPhase.Result -> when (val result = phase.value) {
                is FirstReadingResult.Unavailable -> {
                    Text(nativeText("No reading in this language is available yet."), color = colors.textSecondary, modifier = Modifier.testTag("onboarding.readingUnavailable"))
                    TextButton(onClick = onChooseLanguage, modifier = Modifier.heightIn(min = 48.dp).testTag("onboarding.chooseReadingLanguage")) { Text(nativeText("Choose another language")) }
                }
                is FirstReadingResult.Ready -> {
                    val item = result.reading
                    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                        Text(nativeText(if (result.origin == com.hadithly.app.core.data.FirstReadingOrigin.DAILY) "Today's hadith" else "A first reading"), style = MaterialTheme.typography.labelMedium, color = colors.textSecondary, modifier = Modifier.testTag("onboarding.readingOrigin"))
                        TextButton(onClick = { onOpen(item) }, modifier = Modifier.heightIn(min = 48.dp).testTag("onboarding.openReading")) { Text(item.referenceDisplay, style = MaterialTheme.typography.labelMedium, color = colors.textSecondary) }
                        Text(com.hadithly.app.core.preferences.authenticityText(item.authenticity.claimScope, item.authenticity.normalizedGrade, item.authenticity.sourceName), style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                    }
                    HadithReadingText(arabicText = item.arabicText,
                        translation = if (item.text.kind == FirstReadingTextKind.TRANSLATION) item.text.text else null,
                        translationLanguage = item.text.language, textColor = colors.textPrimary, arabicVisible = item.text.kind == FirstReadingTextKind.ORIGINAL,
                        modifier = Modifier.testTag("onboarding.dailyText"))
                    if (item.text.kind == FirstReadingTextKind.TRANSLATION) {
                        var arabicExpanded by remember(item.canonicalId) { mutableStateOf(false) }
                        TextButton(onClick = { arabicExpanded = !arabicExpanded }, modifier = Modifier.testTag("onboarding.readingArabic")) { Text(nativeText("Arabic")) }
                        if (arabicExpanded) HadithReadingText(arabicText = item.arabicText, translation = null,
                            translationLanguage = "ar", textColor = colors.textPrimary)
                    }
                    val sourceLabel = if (item.text.isAI) nativeText("AI translation") else item.text.sourceLabel
                    Column(verticalArrangement = Arrangement.spacedBy(4.dp), modifier = Modifier.testTag("onboarding.translationSource")) {
                        if (item.text.sourceUrl != null) TextButton(onClick = { uri.openUri(item.text.sourceUrl) }) { Text(sourceLabel, color = colors.textSecondary) }
                        else Text(sourceLabel, color = colors.textSecondary, style = MaterialTheme.typography.bodySmall)
                        if (item.referenceUrl != null && item.referenceUrl != item.text.sourceUrl) TextButton(onClick = { uri.openUri(item.referenceUrl) }) { Text(nativeText("Original source"), color = colors.textSecondary) }
                    }
                    var creditsExpanded by remember(item.canonicalId) { mutableStateOf(false) }
                    TextButton(onClick = { creditsExpanded = !creditsExpanded }, modifier = Modifier.testTag("onboarding.readingCredits")) { Text(nativeText("Sources")) }
                    if (creditsExpanded) for (credit in item.text.credits) {
                        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
                            Text(nativeText(if (credit.scope == "original") "Original source" else "Translation source"), style = MaterialTheme.typography.labelSmall, color = colors.textSecondary)
                            Text(credit.attribution, style = MaterialTheme.typography.bodySmall, color = colors.textPrimary)
                            if (credit.url != null) TextButton(onClick = { uri.openUri(credit.url) }) { Text(credit.licenseName, color = colors.textSecondary) }
                            else Text(credit.licenseName, style = MaterialTheme.typography.bodySmall, color = colors.textSecondary)
                        }
                    }
                    LaunchedEffect(item.canonicalId, item.text.language) { withFrameNanos { }; onRendered() }
                }
            }
        }
    }
}

@Composable
fun AccentButton(text: String, onClick: () -> Unit, tag: String = "") {
    val colors = LocalHadithlyColors.current
    val interactions = remember { androidx.compose.foundation.interaction.MutableInteractionSource() }
    val pressed by interactions.collectIsPressedAsState()
    val scale by androidx.compose.animation.core.animateFloatAsState(
        if (pressed && com.hadithly.app.core.theme.rememberMotionAllowed()) .96f else 1f,
        animationSpec = tween(com.hadithly.app.core.theme.InterfaceMotion.QUICK), label = "button press")
    Button(onClick = onClick, interactionSource = interactions, shape = RoundedCornerShape(16.dp),
        colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
        modifier = Modifier.fillMaxWidth().heightIn(min = 52.dp).graphicsLayer { scaleX = scale; scaleY = scale }.testTag(tag)) { Text(text, style = MaterialTheme.typography.titleMedium) }
}
