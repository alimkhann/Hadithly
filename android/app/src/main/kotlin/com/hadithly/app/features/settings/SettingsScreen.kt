@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.settings

import com.hadithly.app.core.preferences.nativeText

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.provider.Settings as SystemSettings
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.ArrowBack
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.automirrored.filled.OpenInNew
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Help
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.Language
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Notifications
import androidx.compose.material.icons.filled.Palette
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Star
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.clerk.api.Clerk
import com.clerk.api.network.model.error.ClerkErrorResponse
import com.clerk.api.network.serialization.ClerkResult
import com.clerk.api.network.serialization.errorMessage
import com.clerk.api.user.User
import com.clerk.api.user.update
import com.hadithly.app.BuildConfig
import com.hadithly.app.R
import com.hadithly.app.core.data.Collections
import com.hadithly.app.core.data.ExportPayload
import com.hadithly.app.core.data.SubscriptionStatusResult
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.offline.OfflineCollectionStatus
import com.hadithly.app.core.offline.OfflineEnqueueResult
import com.hadithly.app.core.offline.OfflineModels
import com.hadithly.app.core.preferences.ArabicFont
import com.hadithly.app.core.preferences.PreferencesStore
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReaderTheme
import com.hadithly.app.core.preferences.ReadingDirection
import com.hadithly.app.core.push.DevicePushProfile
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.push.PushRegistrationState
import com.hadithly.app.core.theme.HadithlyColors
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.rememberApp
import com.hadithly.app.features.purchases.QuotaPaywallSheet
import kotlinx.coroutines.launch
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * S1 Settings root. Every row opens a finished destination or performs a
 * real action — no dead placeholders. Reading controls reuse the F2
 * preference contracts; the admin queue no longer ships in the consumer app
 * (E4 owns the secured exception tool). Destinations are internal state
 * (matching the manual tab navigation) with system-back support.
 */
@Composable
fun SettingsScreen(onShowSignIn: () -> Unit) {
    var route by remember { mutableStateOf<SettingsDestination?>(null) }
    BackHandler(enabled = route != null) { route = null }
    val destination = route
    if (destination == null) {
        SettingsRoot(onOpen = { route = it }, onShowSignIn = onShowSignIn)
    } else {
        SettingsDestinationScreen(destination = destination, onBack = { route = null }, onShowSignIn = onShowSignIn)
    }
}

@Composable
private fun SettingsDestinationScreen(
    destination: SettingsDestination,
    onBack: () -> Unit,
    onShowSignIn: () -> Unit,
) {
    val colors = LocalHadithlyColors.current
    Column(Modifier.fillMaxSize().background(colors.background)) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            modifier = Modifier.fillMaxWidth().padding(horizontal = 4.dp, vertical = 4.dp),
        ) {
            IconButton(onClick = onBack) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = nativeText("Back"), tint = colors.textPrimary)
            }
            Text(destination.localizedTitle(), fontSize = 20.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
        }
        when (destination) {
            SettingsDestination.PROFILE -> ProfileDestination()
            SettingsDestination.APPEARANCE -> AppearanceDestination()
            SettingsDestination.APP_LANGUAGE -> AppLanguageDestination()
            SettingsDestination.HADITH_TRANSLATION -> TranslationLanguageDestination()
            SettingsDestination.READING_AND_TYPE -> ReadingTypeDestination()
            SettingsDestination.OFFLINE_STORAGE -> OfflineStorageDestination()
            SettingsDestination.NOTIFICATIONS -> NotificationDestination()
            SettingsDestination.SUBSCRIPTION -> SubscriptionDestination()
            SettingsDestination.PRIVACY_AND_DATA -> PrivacyDataDestination(onShowSignIn)
            SettingsDestination.HELP_AND_SUPPORT -> HelpSupportDestination()
            SettingsDestination.ABOUT_AND_LEGAL -> AboutLegalDestination()
        }
    }
}

@Composable
private fun SettingsRoot(onOpen: (SettingsDestination) -> Unit, onShowSignIn: () -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val syncSummary by app.session.syncSummary.collectAsStateWithLifecycle()
    val sessions by Clerk.sessionsFlow.collectAsStateWithLifecycle()
    val signedIn = sessions.isNotEmpty()
    val scope = rememberCoroutineScope()
    var subscriptionTier by remember(signedIn) { mutableStateOf<String?>(null) }
    val notificationsOn by app.settings.dailyNotificationEnabled.collectAsStateWithLifecycle()
    val notificationTime by app.settings.dailyNotificationTime.collectAsStateWithLifecycle()
    val notificationsStatus = if (!signedIn) null else if (notificationsOn) notificationTime else "Off"
    LaunchedEffect(signedIn) {
        subscriptionTier = if (signedIn) {
            runCatching { app.repository.getSubscriptionStatus()?.subscriptionTier }.getOrNull()
        } else {
            null
        }
    }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState()).padding(16.dp),
    ) {
        Text(stringResource(R.string.app_settings), fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        if (signedIn) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface, RoundedCornerShape(16.dp))
                    .clickable { onOpen(SettingsDestination.PROFILE) }
                    .testTag(SettingsDestination.PROFILE.testTag)
                    .padding(16.dp),
            ) {
                ProfileBadge(Modifier.size(44.dp))
                Spacer(Modifier.size(12.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(accountName(), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    val email = Clerk.user?.emailAddresses?.firstOrNull { it.id == Clerk.user?.primaryEmailAddressId }?.emailAddress
                    Text(email ?: "View profile, picture, and name", fontSize = 12.sp, color = colors.textSecondary)
                }
                Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary)
            }
            syncSummary?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
        } else {
            CardColumn {
                Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                    Icon(Icons.Filled.Person, null, tint = colors.textSecondary)
                    Text(nativeText("Reading as a guest"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                }
                Text(
                    nativeText("Everything you need to read works without an account. Sign in to carry your bookmarks, favorites, and notes across devices."),
                    fontSize = 14.sp,
                    color = colors.textSecondary,
                )
                Button(
                    onClick = onShowSignIn,
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
                    modifier = Modifier.fillMaxWidth().testTag("settings.signin"),
                ) { Text(nativeText("Sign in"), fontWeight = FontWeight.SemiBold) }
            }
        }

        SettingsGroup(
            header = "Reading",
            rows = listOf(
                SettingsDestination.APPEARANCE to null,
                SettingsDestination.APP_LANGUAGE to languageName(preferences.uiLocale),
                SettingsDestination.HADITH_TRANSLATION to languageName(preferences.translationLocale),
                SettingsDestination.READING_AND_TYPE to null,
            ),
            onOpen,
        )
        SettingsGroup(
            header = "Library",
            rows = listOf(
                SettingsDestination.OFFLINE_STORAGE to null,
                SettingsDestination.NOTIFICATIONS to notificationsStatus,
                SettingsDestination.SUBSCRIPTION to SettingsSubscription.displayName(subscriptionTier),
            ),
            onOpen,
        )
        SettingsGroup(
            header = "Support",
            rows = listOf(
                SettingsDestination.PRIVACY_AND_DATA to null,
                SettingsDestination.HELP_AND_SUPPORT to null,
                SettingsDestination.ABOUT_AND_LEGAL to null,
            ),
            onOpen,
        )

        if (signedIn) {
            TextButton(
                onClick = { scope.launch { Clerk.auth.signOut() } },
                modifier = Modifier.testTag("settings.signout"),
            ) { Text(nativeText("Sign out"), color = colors.textPrimary) }
        }
        Spacer(Modifier.size(16.dp))
    }
}

private fun accountName(): String {
    val user = Clerk.user
    val full = listOfNotNull(user?.firstName?.trim(), user?.lastName?.trim())
        .filter { it.isNotEmpty() }.joinToString(" ")
    return full.ifEmpty { user?.username ?: "Account" }
}

private fun languageName(code: String): String? =
    SupportedLanguages.all.firstOrNull { it.first == code }?.second

@Composable
private fun SettingsGroup(header: String, rows: List<Pair<SettingsDestination, String?>>, onOpen: (SettingsDestination) -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(modifier = Modifier.fillMaxWidth()) {
        Text(
            header,
            fontSize = 13.sp,
            fontWeight = FontWeight.Medium,
            color = colors.textSecondary,
            modifier = Modifier.padding(horizontal = 16.dp, vertical = 6.dp),
        )
        Column(modifier = Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp))) {
            rows.forEachIndexed { index, (destination, detail) ->
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { onOpen(destination) }
                        .testTag(destination.testTag)
                        .padding(horizontal = 16.dp, vertical = 13.dp),
                ) {
                    SettingsIcon(destination)
                    Spacer(Modifier.size(14.dp))
                    Text(destination.localizedTitle(), fontSize = 16.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    detail?.let { Text(it, fontSize = 14.sp, color = colors.textSecondary) }
                    Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary, modifier = Modifier.size(18.dp))
                }
                if (index < rows.lastIndex) {
                    HorizontalDivider(color = colors.surfaceElevated, thickness = 0.75.dp, modifier = Modifier.padding(start = 52.dp))
                }
            }
        }
    }
}

@Composable
private fun SettingsIcon(destination: SettingsDestination) {
    val colors = LocalHadithlyColors.current
    val icon: ImageVector = when (destination) {
        SettingsDestination.PROFILE -> Icons.Filled.Person
        SettingsDestination.APPEARANCE -> Icons.Filled.Palette
        SettingsDestination.APP_LANGUAGE -> Icons.Filled.Language
        SettingsDestination.HADITH_TRANSLATION -> Icons.Filled.MenuBook
        SettingsDestination.READING_AND_TYPE -> Icons.Filled.TextFields
        SettingsDestination.OFFLINE_STORAGE -> Icons.Filled.Download
        SettingsDestination.NOTIFICATIONS -> Icons.Filled.Notifications
        SettingsDestination.SUBSCRIPTION -> Icons.Filled.Star
        SettingsDestination.PRIVACY_AND_DATA -> Icons.Filled.Lock
        SettingsDestination.HELP_AND_SUPPORT -> Icons.Filled.Help
        SettingsDestination.ABOUT_AND_LEGAL -> Icons.Filled.Info
    }
    Icon(icon, null, tint = colors.textPrimary, modifier = Modifier.size(22.dp))
}

@Composable
private fun ProfileBadge(modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Box(modifier.background(colors.surfaceElevated, CircleShape), contentAlignment = Alignment.Center) {
        val initial = accountName().trim().firstOrNull()?.uppercase() ?: "H"
        Text(initial.toString(), fontSize = 18.sp, fontWeight = FontWeight.SemiBold, color = colors.textSecondary)
    }
}

// ── Profile ────────────────────────────────────────────────────────────────

@Composable
private fun ProfileDestination() {
    val colors = LocalHadithlyColors.current
    val scope = rememberCoroutineScope()
    var firstName by remember { mutableStateOf(Clerk.user?.firstName.orEmpty()) }
    var lastName by remember { mutableStateOf(Clerk.user?.lastName.orEmpty()) }
    var username by remember { mutableStateOf(Clerk.user?.username.orEmpty()) }
    var notice by remember { mutableStateOf<String?>(null) }
    var saving by remember { mutableStateOf(false) }

    ScrollColumn {
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                ProfileBadge(Modifier.size(56.dp))
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text(accountName(), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    val email = Clerk.user?.emailAddresses?.firstOrNull { it.id == Clerk.user?.primaryEmailAddressId }?.emailAddress
                    email?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
                    if (Clerk.user?.hasImage != true) {
                        Text(nativeText("Avatar is set by your sign-in method."), fontSize = 11.sp, color = colors.textSecondary)
                    }
                }
            }
        }
        CardColumn {
            Text(nativeText("Name"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            OutlinedTextField(value = firstName, onValueChange = { firstName = it }, label = { Text(nativeText("First name")) }, singleLine = true, enabled = !saving)
            OutlinedTextField(value = lastName, onValueChange = { lastName = it }, label = { Text(nativeText("Last name")) }, singleLine = true, enabled = !saving)
            Button(
                enabled = !saving,
                onClick = {
                    saving = true
                    scope.launch {
                        val result = Clerk.user?.update(User.UpdateParams(firstName = firstName.trim(), lastName = lastName.trim()))
                        saving = false
                        notice = if (result is ClerkResult.Success<*>) "Name saved." else (result as? ClerkResult.Failure<ClerkErrorResponse>)?.errorMessage ?: "Could not save your name."
                    }
                },
                modifier = Modifier.fillMaxWidth().testTag("settings.profile.saveName"),
            ) { Text(nativeText("Save name")) }
        }
        CardColumn {
            Text(nativeText("Username"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            Text(nativeText("Usernames start with a letter and use letters, numbers, and underscores."), fontSize = 13.sp, color = colors.textSecondary)
            OutlinedTextField(value = username, onValueChange = { username = it }, label = { Text(nativeText("Username")) }, singleLine = true, enabled = !saving)
            Button(
                enabled = !saving && username.trim().length >= 3,
                onClick = {
                    saving = true
                    scope.launch {
                        val result = Clerk.user?.update(User.UpdateParams(username = username.trim()))
                        saving = false
                        notice = if (result is ClerkResult.Success<*>) "Username saved." else "That username is not available."
                    }
                },
                modifier = Modifier.fillMaxWidth().testTag("settings.profile.saveUsername"),
            ) { Text(nativeText("Save username")) }
        }
        notice?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
    }
}

// ── Appearance / languages / reading ───────────────────────────────────────

@Composable
private fun AppearanceDestination() {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    ScrollColumn {
        CardColumn {
            Text(stringResource(R.string.settings_appearance), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            Text(nativeText("Applies across the app. The reader previews each theme live."), fontSize = 12.sp, color = colors.textSecondary)
            ReaderTheme.entries.forEach { theme ->
                SettingsSingleChoiceRow(
                    label = themeLabel(theme),
                    selected = theme == preferences.appTheme,
                    onClick = { app.preferences.setTheme(theme) },
                    modifier = Modifier.testTag("settings.appearance.${theme.wire}"),
                )
            }
        }
    }
}

private fun themeLabel(theme: ReaderTheme): String = when (theme) {
    ReaderTheme.SYSTEM -> "System"
    ReaderTheme.LIGHT -> "Light"
    ReaderTheme.PAPER -> "Paper"
    ReaderTheme.DARK -> "Dark"
}

@Composable
private fun AppLanguageDestination() {
    val app = rememberApp()
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    LanguageList(title = stringResource(R.string.settings_app_language), selection = preferences.uiLocale, prefix = "settings.uiLanguage", onSelect = app.preferences::setUILocale)
}

@Composable
private fun TranslationLanguageDestination() {
    val app = rememberApp()
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    LanguageList(title = stringResource(R.string.settings_hadith_translation), selection = preferences.translationLocale, prefix = "settings.language", onSelect = app.preferences::setTranslationLocale)
}

@Composable
private fun LanguageList(title: String, selection: String, prefix: String, onSelect: (String) -> Unit) {
    val colors = LocalHadithlyColors.current
    ScrollColumn {
        CardColumn {
            Text(title, fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            SupportedLanguages.all.forEach { (code, name) ->
                SettingsSingleChoiceRow(
                    label = name,
                    selected = code == selection,
                    onClick = { onSelect(code) },
                    modifier = Modifier.testTag("$prefix.$code"),
                )
            }
            Text(
                pluralStringResource(R.plurals.settings_languages_available, SupportedLanguages.all.size, SupportedLanguages.all.size),
                fontSize = 12.sp,
                color = colors.textSecondary,
            )
        }
    }
}

private fun fontLabel(font: ArabicFont): String = when (font) {
    ArabicFont.SYSTEM -> "System"
    ArabicFont.AMIRI -> "Amiri"
    ArabicFont.SCHEHERAZADE_NEW -> "Scheherazade New"
    ArabicFont.NOTO_NASKH_ARABIC -> "Noto Naskh Arabic"
}

@Composable
private fun ReadingTypeDestination() {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val preferences by app.preferences.preferences.collectAsStateWithLifecycle()
    val store: PreferencesStore = app.preferences
    var showingDetail by remember { mutableStateOf(false) }
    ScrollColumn {
        if (!showingDetail) {
            SettingsDestinationLabel("DISPLAY")
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                SettingsDisplayPill("Arabic", preferences.arabicVisible, Modifier.weight(1f).testTag("settings.visibility.arabic")) { store.setVisibility(arabic = !preferences.arabicVisible) }
                SettingsDisplayPill("Translation", preferences.translationVisible, Modifier.weight(1f).testTag("settings.visibility.translation")) { store.setVisibility(translation = !preferences.translationVisible) }
            }
            Text(nativeText("At least one layer stays visible."), fontSize = 12.sp, color = colors.textSecondary)

            SettingsDestinationLabel("READER SETTINGS")
            SettingsDestinationNavigationRow("Arabic font", "${fontLabel(preferences.arabicFont)} · ${preferences.arabicFontSize.toInt()} pt") { showingDetail = true }
            SettingsDestinationNavigationRow("Translation", preferences.translationLocale.uppercase()) { showingDetail = true }
            SettingsDestinationNavigationRow("Color themes", themeLabel(preferences.readerTheme)) { showingDetail = true }

            SettingsDestinationLabel("READING DIRECTION")
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                ReadingDirection.entries.forEach { direction ->
                    val selected = direction == preferences.readingDirection
                    TextButton(
                        onClick = { store.setReadingDirection(direction) },
                        modifier = Modifier.weight(1f).background(if (selected) colors.surfaceElevated else colors.surface, RoundedCornerShape(50)).testTag("settings.readingDirection.${direction.wire}"),
                    ) { Text(directionLabel(direction), color = if (selected) colors.textPrimary else colors.textSecondary, maxLines = 1) }
                }
            }

            SettingsDestinationLabel("SAVED")
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().background(colors.surfaceElevated, RoundedCornerShape(18.dp)).padding(horizontal = 16.dp, vertical = 8.dp)) {
                Text(stringResource(R.string.saved_confirm_removal), fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Switch(checked = app.savedSafety.confirmsRemoval, onCheckedChange = { app.savedSafety.confirmsRemoval = it }, colors = SwitchDefaults.colors(checkedTrackColor = colors.interactive), modifier = Modifier.testTag("settings.confirmSavedRemoval"))
            }
        } else {
            TextButton(onClick = { showingDetail = false }) {
                Icon(Icons.AutoMirrored.Filled.ArrowBack, contentDescription = null, tint = colors.textSecondary)
                Text(stringResource(R.string.settings_reading_type), color = colors.textSecondary)
            }
        CardColumn {
            Text(nativeText("Arabic type"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            ArabicFont.entries.forEach { font ->
                SettingsSingleChoiceRow(
                    label = fontLabel(font),
                    selected = font == preferences.arabicFont,
                    onClick = { store.setArabicFont(font) },
                    modifier = Modifier.testTag("settings.arabicFont.${font.wire}"),
                )
            }
            Text(stringResource(R.string.settings_arabic_type_size), fontSize = 14.sp, color = colors.textPrimary)
            Slider(
                value = preferences.arabicFontSize,
                onValueChange = store::setArabicFontSize,
                valueRange = 18f..40f,
                steps = 21,
                colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent, inactiveTrackColor = colors.surfaceElevated),
                modifier = Modifier.testTag("settings.arabicSize"),
            )
            Text(nativeText("%1\$s pt", preferences.arabicFontSize.toInt()), fontSize = 11.sp, color = colors.textSecondary)
            Text("نَعْبُدُكَ وَإِيَّاكَ نَسْتَعِينُ", fontSize = preferences.arabicFontSize.sp, color = colors.textPrimary, modifier = Modifier.fillMaxWidth())
        }
        CardColumn {
            Text(stringResource(R.string.settings_reading_direction), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            ReadingDirection.entries.forEach { direction ->
                SettingsSingleChoiceRow(
                    label = directionLabel(direction),
                    selected = direction == preferences.readingDirection,
                    onClick = { store.setReadingDirection(direction) },
                    modifier = Modifier.testTag("settings.readingDirection.${direction.wire}"),
                )
            }
        }
        CardColumn {
            Text(nativeText("Text layers"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            LayerSwitch(
                label = stringResource(R.string.settings_visibility_arabic),
                checked = preferences.arabicVisible,
                onCheckedChange = { store.setVisibility(arabic = it) },
                modifier = Modifier.testTag("settings.visibility.arabic"),
            )
            LayerSwitch(
                label = stringResource(R.string.settings_visibility_translation),
                checked = preferences.translationVisible,
                onCheckedChange = { store.setVisibility(translation = it) },
                modifier = Modifier.testTag("settings.visibility.translation"),
            )
            Text(nativeText("At least one layer stays visible."), fontSize = 12.sp, color = colors.textSecondary)
        }
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
                Text(stringResource(R.string.saved_confirm_removal), fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Switch(
                    checked = app.savedSafety.confirmsRemoval,
                    onCheckedChange = { app.savedSafety.confirmsRemoval = it },
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
                    modifier = Modifier.testTag("settings.confirmSavedRemoval"),
                )
            }
        }
        }
    }
}

@Composable
private fun SettingsDestinationLabel(text: String) {
    val colors = LocalHadithlyColors.current
    Text(text, fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.textSecondary, modifier = Modifier.padding(top = 12.dp))
}

@Composable
private fun SettingsDisplayPill(title: String, isOn: Boolean, modifier: Modifier = Modifier, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = modifier.heightIn(min = 52.dp).background(if (isOn) colors.surfaceElevated else colors.surface, RoundedCornerShape(50)).toggleable(value = isOn, role = androidx.compose.ui.semantics.Role.Switch, onValueChange = { onClick() }).padding(horizontal = 12.dp),
    ) {
        Icon(if (isOn) Icons.Filled.Check else Icons.Outlined.RadioButtonUnchecked, contentDescription = null, tint = if (isOn) colors.interactive else colors.textSecondary, modifier = Modifier.size(18.dp))
        Text(title, fontSize = 14.sp, fontWeight = FontWeight.Medium, color = if (isOn) colors.textPrimary else colors.textSecondary, modifier = Modifier.padding(start = 6.dp))
    }
}

@Composable
private fun SettingsDestinationNavigationRow(title: String, subtitle: String, onClick: () -> Unit) {
    val colors = LocalHadithlyColors.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth().heightIn(min = 72.dp).clickable(onClick = onClick)) {
        Column(modifier = Modifier.weight(1f)) {
            Text(title, fontSize = 21.sp, fontWeight = FontWeight.Medium, color = colors.textPrimary)
            Text(subtitle, fontSize = 16.sp, color = colors.textSecondary, modifier = Modifier.padding(top = 4.dp))
        }
        Icon(Icons.AutoMirrored.Filled.NavigateNext, contentDescription = null, tint = colors.textSecondary, modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun LayerSwitch(label: String, checked: Boolean, onCheckedChange: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Row(verticalAlignment = Alignment.CenterVertically, modifier = Modifier.fillMaxWidth()) {
        Text(label, fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
        Switch(
            checked = checked,
            onCheckedChange = onCheckedChange,
            colors = SwitchDefaults.colors(checkedTrackColor = colors.accent),
            modifier = modifier,
        )
    }
}

@Composable
private fun directionLabel(direction: ReadingDirection): String = when (direction) {
    ReadingDirection.AUTO -> stringResource(R.string.direction_automatic)
    ReadingDirection.RTL -> stringResource(R.string.direction_right_to_left)
    ReadingDirection.LTR -> stringResource(R.string.direction_left_to_right)
}

// ── Offline storage (O2 download management) ─────────────────────────────────

@Composable
private fun OfflineStorageDestination() {
    val colors = LocalHadithlyColors.current
    val context = LocalContext.current
    val app = rememberApp()
    val store = app.offline
    val locale = app.preferences.preferences.collectAsStateWithLifecycle().value.translationLocale
    // Read (not just collect) so every registry/progress change recomposes.
    val revision by store.revision.collectAsStateWithLifecycle()
    val progressMap by store.progress.collectAsStateWithLifecycle()
    var cacheSize by remember { mutableStateOf("…") }
    var notice by remember { mutableStateOf<String?>(null) }
    var actionNotice by remember { mutableStateOf<String?>(null) }
    var showLearnMore by remember { mutableStateOf(false) }
    val scope = rememberCoroutineScope()

    fun refreshSize() {
        scope.launch {
            val bytes = runCatching {
                context.cacheDir.walkTopDown().filter { it.isFile }.sumOf { it.length() }
            }.getOrDefault(0L)
            cacheSize = OfflineModels.formatBytes(bytes)
        }
    }
    LaunchedEffect(Unit) {
        refreshSize()
        runCatching { store.refresh(locale) }
    }

    key(revision) {
    ScrollColumn {
        CardColumn {
            Text(nativeText("Offline collections"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            Text(
                nativeText("Downloads: %1\$s · Free: %2\$s", OfflineModels.formatBytes(store.offlineBytes()), OfflineModels.formatBytes(store.freeBytes())),
                fontSize = 14.sp,
                color = colors.textSecondary,
            )
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(nativeText("Wi-Fi only"), fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Switch(
                    checked = store.isWifiOnly(),
                    onCheckedChange = { store.setWifiOnly(it) },
                    modifier = Modifier.testTag("settings.offline.wifiOnly"),
                )
            }
            TextButton(
                onClick = { showLearnMore = true },
                modifier = Modifier.testTag("settings.offline.learnMore"),
            ) { Text(nativeText("How offline works"), color = colors.accent) }
            actionNotice?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
            store.lastError?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
            Text(
                nativeText("Base Arabic files plus a translation pack for your language. Every file is checksummed and licensed before it activates. The previous copy stays readable until the replacement and your saved positions check out."),
                fontSize = 12.sp,
                color = colors.textSecondary,
            )
        }
        CardColumn {
            Text(nativeText("Collections"), fontSize = 14.sp, fontWeight = FontWeight.Medium, color = colors.textSecondary)
            Collections.all.forEachIndexed { index, (slug, name) ->
                OfflineCollectionRow(
                    slug = slug,
                    name = name,
                    locale = locale,
                    progressMap = progressMap,
                    onNotice = { actionNotice = it },
                )
                if (index < Collections.all.lastIndex) {
                    HorizontalDivider(color = colors.surfaceElevated, thickness = 0.75.dp)
                }
            }
        }
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(nativeText("Temporary cache"), fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Text(cacheSize, fontSize = 14.sp, color = colors.textSecondary)
            }
            TextButton(
                onClick = {
                    runCatching {
                        context.cacheDir.listFiles()?.forEach { if (it.name != "clerk") it.deleteRecursively() }
                    }
                    notice = "Temporary cache cleared."
                    refreshSize()
                },
                modifier = Modifier.testTag("settings.offline.clearCache"),
            ) { Text(nativeText("Clear temporary cache"), color = colors.accent) }
            notice?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
            Text(nativeText("Clearing never deletes bookmarks, favorites, notes, reading progress, or downloaded collections."), fontSize = 12.sp, color = colors.textSecondary)
        }
        CardColumn {
            TextButton(
                onClick = {
                    runCatching {
                        val intent = Intent(SystemSettings.ACTION_INTERNAL_STORAGE_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                        context.startActivity(intent)
                    }.onFailure {
                        runCatching {
                            context.startActivity(Intent(SystemSettings.ACTION_SETTINGS).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                        }
                    }
                },
                modifier = Modifier.testTag("settings.offline.systemSettings"),
            ) { Text(nativeText("Open device storage"), color = colors.textPrimary) }
            Text(nativeText("See Hadithly's total device storage from the system settings page."), fontSize = 12.sp, color = colors.textSecondary)
        }
    }
    }

    if (showLearnMore) {
        AlertDialog(
            onDismissRequest = { showLearnMore = false },
            title = { Text(nativeText("How offline works")) },
            text = {
                Text(nativeText("Hadithly ships versioned offline collections: a base Arabic dump plus translation packs, each checksummed and licensed. Downloads validate before activating and keep your Saved items and reading positions intact. Deleting a download removes files only — your bookmarks, notes, and positions stay."))
            },
            confirmButton = { TextButton(onClick = { showLearnMore = false }) { Text(nativeText("Done")) } },
            containerColor = colors.surface,
        )
    }
}

@Composable
private fun OfflineCollectionRow(
    slug: String,
    name: String,
    locale: String,
    progressMap: Map<String, Double>,
    onNotice: (String) -> Unit,
) {
    val colors = LocalHadithlyColors.current
    val app = rememberApp()
    val store = app.offline
    val status = store.status(slug, locale)
    Column(modifier = Modifier.testTag("settings.offline.$slug.row")) {
        Text(name, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
        Text(
            offlineStatusLine(status, store, slug, locale),
            fontSize = 13.sp,
            color = colors.textSecondary,
        )
        val fraction = when (status) {
            is OfflineCollectionStatus.Downloading -> status.progress
            is OfflineCollectionStatus.Queued -> status.progress.takeIf { it > 0 }
            else -> null
        }
        if (fraction != null) {
            LinearProgressIndicator(
                progress = { fraction.toFloat() },
                modifier = Modifier.fillMaxWidth().testTag("settings.offline.$slug.progress"),
            )
        }
        Row(horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            when (status) {
                is OfflineCollectionStatus.NotInstalled -> {
                    TextButton(
                        onClick = {
                            when (val result = store.enqueue(slug, "base", locale)) {
                                is OfflineEnqueueResult.Blocked -> onNotice(result.reason)
                                else -> Unit
                            }
                        },
                        modifier = Modifier.testTag("settings.offline.$slug.download"),
                    ) { Text(nativeText("Download"), color = colors.accent) }
                }
                is OfflineCollectionStatus.Queued, is OfflineCollectionStatus.Downloading -> {
                    TextButton(
                        onClick = { store.pause(slug) },
                        modifier = Modifier.testTag("settings.offline.$slug.pause"),
                    ) { Text(nativeText("Pause"), color = colors.accent) }
                    TextButton(
                        onClick = { store.cancel(slug) },
                        modifier = Modifier.testTag("settings.offline.$slug.cancel"),
                    ) { Text(nativeText("Cancel"), color = colors.accent) }
                }
                is OfflineCollectionStatus.Paused -> {
                    TextButton(
                        onClick = { store.retry(slug) },
                        modifier = Modifier.testTag("settings.offline.$slug.resume"),
                    ) { Text(nativeText("Resume"), color = colors.accent) }
                    TextButton(
                        onClick = { store.cancel(slug) },
                        modifier = Modifier.testTag("settings.offline.$slug.cancel"),
                    ) { Text(nativeText("Cancel"), color = colors.accent) }
                }
                is OfflineCollectionStatus.Verifying -> {
                    Text(nativeText("Checking…"), fontSize = 13.sp, color = colors.textSecondary)
                }
                is OfflineCollectionStatus.Failed -> {
                    TextButton(
                        onClick = { store.retry(slug) },
                        modifier = Modifier.testTag("settings.offline.$slug.retry"),
                    ) { Text(nativeText("Retry"), color = colors.accent) }
                    TextButton(
                        onClick = { store.cancel(slug) },
                        modifier = Modifier.testTag("settings.offline.$slug.cancel"),
                    ) { Text(nativeText("Cancel"), color = colors.accent) }
                }
                is OfflineCollectionStatus.Active -> {
                    if (status.updateAvailable) {
                        TextButton(
                            onClick = { store.update(slug, locale) },
                            modifier = Modifier.testTag("settings.offline.$slug.update"),
                        ) { Text(nativeText("Update"), color = colors.accent) }
                    } else if (store.packManifest(slug, locale) != null &&
                        store.recordFor(slug).activePacks[locale] == null
                    ) {
                        TextButton(
                            onClick = {
                                when (val result = store.enqueue(slug, "pack", locale)) {
                                    is OfflineEnqueueResult.Blocked -> onNotice(result.reason)
                                    else -> Unit
                                }
                            },
                            modifier = Modifier.testTag("settings.offline.$slug.downloadPack"),
                        ) { Text(nativeText("Download translation"), color = colors.accent) }
                    }
                    TextButton(
                        onClick = {
                            store.delete(slug)
                            onNotice("Deleted the $name files. Your saved items and positions stay.")
                        },
                        modifier = Modifier.testTag("settings.offline.$slug.delete"),
                    ) { Text(if (status.updateAvailable) "Delete" else "Delete download", color = colors.accent) }
                }
                is OfflineCollectionStatus.AppUpdateRequired -> Unit
            }
        }
    }
}

private fun offlineStatusLine(
    status: OfflineCollectionStatus,
    store: com.hadithly.app.core.offline.OfflineStore,
    slug: String,
    locale: String,
): String = when (status) {
    is OfflineCollectionStatus.NotInstalled -> {
        val manifest = store.baseManifest(slug)
        if (manifest != null) "Not downloaded · ${OfflineModels.formatBytes(manifest.byteSize.toLong())}"
        else "Not downloaded"
    }
    is OfflineCollectionStatus.Queued -> "Waiting to download…"
    is OfflineCollectionStatus.Downloading -> "Downloading… ${(status.progress * 100).toInt()}%"
    is OfflineCollectionStatus.Paused -> "Paused — resumes where it stopped."
    is OfflineCollectionStatus.Verifying -> "Checking the file…"
    is OfflineCollectionStatus.Failed -> status.reason
    is OfflineCollectionStatus.Active -> {
        val parts = mutableListOf("Downloaded")
        if (status.updateAvailable) parts.add("update available")
        if (status.stalePack) parts.add("translation outdated")
        val pack = store.packManifest(slug, locale)
        if (pack != null && store.recordFor(slug).activePacks[locale] == null) {
            parts.add("${OfflineModels.formatBytes(pack.byteSize.toLong())} translation available")
        }
        parts.joinToString(" · ")
    }
    is OfflineCollectionStatus.AppUpdateRequired -> "Needs Hadithly ${status.minVersion} or newer."
}

// ── Notifications (ported from the pre-S1 card) ────────────────────────────

@Composable
private fun NotificationDestination() {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val signedIn = Clerk.sessionsFlow.collectAsStateWithLifecycle().value.isNotEmpty()
    val enabled by app.settings.dailyNotificationEnabled.collectAsStateWithLifecycle()
    val time by app.settings.dailyNotificationTime.collectAsStateWithLifecycle()
    val pushState by app.push.state.collectAsStateWithLifecycle()
    var showTimePicker by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }

    fun persist(nextEnabled: Boolean, nextTime: String = time) {
        scope.launch {
            runCatching {
                val current = app.preferences.preferences.value
                app.repository.setDailyNotification(
                    nextEnabled,
                    nextTime,
                    DevicePushProfile(
                        timezoneId = PushNotificationManager.timezoneId(),
                        uiLocale = current.uiLocale,
                        translationLocale = current.translationLocale,
                    ),
                )
            }.onSuccess {
                app.settings.setDailyNotificationEnabled(nextEnabled)
                app.settings.setDailyNotificationTime(nextTime)
            }.onFailure { status = it.message ?: "Could not save notification settings." }
        }
    }

    fun enableNotifications() {
        app.push.requestAndSaveToken()
        persist(true)
        status = "Registering this device…"
    }

    val permissionLauncher = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) enableNotifications() else {
            app.settings.setDailyNotificationEnabled(false)
            status = "Notifications are not allowed in system settings."
        }
    }

    ScrollColumn {
        CardColumn {
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
                Icon(Icons.Filled.Notifications, null, tint = colors.textSecondary)
                Text(stringResource(R.string.app_daily_hadith), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            }
            if (!signedIn) {
                Text(nativeText("Sign in to receive the daily hadith on this device."), fontSize = 14.sp, color = colors.textSecondary)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(nativeText("Send me a hadith every day"), fontSize = 14.sp, color = colors.textPrimary)
                        val stateLine = status ?: when (val currentPushState = pushState) {
                            PushRegistrationState.NotConfigured -> "Add Firebase configuration to enable FCM in this build."
                            PushRegistrationState.Registered -> "This device is registered."
                            is PushRegistrationState.Failed -> currentPushState.message
                            else -> null
                        }
                        stateLine?.let { Text(it, fontSize = 11.sp, color = colors.textSecondary) }
                    }
                    Switch(
                        checked = enabled,
                        enabled = app.push.isConfigured,
                        onCheckedChange = { checked ->
                            if (!checked) {
                                status = null
                                persist(false)
                            } else if (Build.VERSION.SDK_INT >= 33 && ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED) {
                                permissionLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                            } else {
                                enableNotifications()
                            }
                        },
                        colors = SwitchDefaults.colors(checkedThumbColor = colors.onInteractive, checkedTrackColor = colors.interactive),
                        modifier = Modifier.testTag("settings.notificationsToggle"),
                    )
                }
                if (enabled) {
                    Row(
                        verticalAlignment = Alignment.CenterVertically,
                        modifier = Modifier.fillMaxWidth().background(colors.surfaceElevated, RoundedCornerShape(10.dp)).clickable { showTimePicker = true }.testTag("settings.notificationsTime").padding(14.dp),
                    ) {
                        Text(nativeText("Time"), fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                        Text(time, fontSize = 14.sp, color = colors.accent)
                    }
                }
            }
        }
    }

    if (showTimePicker) {
        val parts = time.split(":").mapNotNull(String::toIntOrNull)
        val picker = rememberTimePickerState(initialHour = parts.getOrElse(0) { 8 }, initialMinute = parts.getOrElse(1) { 0 }, is24Hour = true)
        AlertDialog(
            onDismissRequest = { showTimePicker = false },
            confirmButton = {
                TextButton(onClick = {
                    val next = "%02d:%02d".format(picker.hour, picker.minute)
                    persist(enabled, next)
                    showTimePicker = false
                }) { Text(nativeText("Done"), color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { showTimePicker = false }) { Text(nativeText("Cancel"), color = colors.textSecondary) } },
            text = { TimePicker(state = picker) },
            containerColor = colors.surface,
        )
    }
}

// ── Subscription ───────────────────────────────────────────────────────────

@Composable
private fun SubscriptionDestination() {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val accountId = Clerk.userFlow.collectAsStateWithLifecycle().value?.id
    val signedIn = accountId != null
    val purchaseState by app.purchases.state.collectAsStateWithLifecycle()
    var status by remember(accountId) { mutableStateOf<SubscriptionStatusResult?>(null) }
    var restoring by remember { mutableStateOf(false) }
    LaunchedEffect(accountId) {
        status = null
        if (signedIn) {
            try { app.repository.observeSubscriptionStatus().collect { value ->
                if (Clerk.user?.id == accountId) status = value
            } } catch (error: kotlinx.coroutines.CancellationException) { throw error }
            catch (_: Exception) { status = null }
        }
    }

    ScrollColumn {
        CardColumn {
            if (!signedIn) {
                Text(nativeText("Sign in to see your subscription. Purchases stay attached to your Hadithly account across devices."), fontSize = 14.sp, color = colors.textSecondary)
            } else {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(SettingsSubscription.displayName(status?.subscriptionTier), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    if (status?.subscriptionTier == "pro") {
                        Text(nativeText("Active"), fontSize = 12.sp, fontWeight = FontWeight.SemiBold, color = colors.accent)
                    }
                }
                Text(androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.q2_quota), fontSize = 12.sp, color = colors.textSecondary)
                TextButton(
                    enabled = !restoring,
                    onClick = {
                        restoring = true
                        app.purchases.restore { _ ->
                            restoring = false
                            scope.launch { status = runCatching { app.repository.getSubscriptionStatus() }.getOrNull() }
                        }
                        // restore() early-returns when unconfigured; never strand the spinner.
                        if (!purchaseState.configured) restoring = false
                    },
                    modifier = Modifier.testTag("settings.subscription.restore"),
                ) { Text(if (restoring) "Restoring…" else "Restore purchases", color = colors.textPrimary) }
                TextButton(onClick = { uriHandler.openUri(if (status?.store == "app_store") "https://apps.apple.com/account/subscriptions" else SettingsLinks.PLAY_SUBSCRIPTIONS) }) {
                    Text(nativeText("Manage subscription"), color = colors.textSecondary)
                }
                Text(androidx.compose.ui.res.stringResource(com.hadithly.app.R.string.q2_manage), fontSize = 12.sp, color = colors.textSecondary)
                purchaseState.errorMessage?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }

            }
        }
    }
}

// ── Privacy & data (export + deletion) ─────────────────────────────────────

@Composable
private fun PrivacyDataDestination(onShowSignIn: () -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val signedIn = Clerk.sessionsFlow.collectAsStateWithLifecycle().value.isNotEmpty()
    var showExportConfirm by remember { mutableStateOf(false) }
    var exporting by remember { mutableStateOf(false) }
    var exportNotice by remember { mutableStateOf<String?>(null) }
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var deletingAccount by remember { mutableStateOf(false) }
    var deletionError by remember { mutableStateOf<String?>(null) }
    var crashConsent by remember { mutableStateOf(com.hadithly.app.core.diagnostics.CrashReporting.hasConsent) }
    val usageSharing by app.analytics.sharing.collectAsStateWithLifecycle()

    val saveDocument = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/json")) { uri ->
        if (uri == null) {
            exporting = false
            return@rememberLauncherForActivityResult
        }
        scope.launch {
            try {
                val payload = app.repository.exportUserData()
                if (payload == null) {
                    exportNotice = "Export is unavailable right now."
                    return@launch
                }
                val json = Json { prettyPrint = true }.encodeToString<ExportPayload>(payload)
                for (fragment in SettingsExport.forbiddenFragments) {
                    check(!json.contains(fragment)) { "Export leaked $fragment" }
                }
                context.contentResolver.openOutputStream(uri)?.use { it.write(json.toByteArray()) }
                exportNotice = "Export saved: ${payload.savedItems.size} saved items, ${payload.readingProgress.size} reading positions."
            } catch (error: Exception) {
                exportNotice = error.message ?: "Export failed. Please try again."
            } finally {
                exporting = false
            }
        }
    }

    ScrollColumn {
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    .toggleable(value = usageSharing, role = androidx.compose.ui.semantics.Role.Switch,
                        onValueChange = { app.analytics.setSharing(it) }).testTag("settings.usageStatistics")) {
                Text(stringResource(R.string.la2_usage), modifier = Modifier.weight(1f), color = colors.textPrimary)
                Switch(checked = usageSharing, onCheckedChange = null,
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.interactive))
            }
            Text(stringResource(R.string.la2_usage_explanation), color = colors.textSecondary)
        }
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth().heightIn(min = 48.dp)
                    .toggleable(value = crashConsent, role = androidx.compose.ui.semantics.Role.Switch,
                        onValueChange = { enabled ->
                            com.hadithly.app.core.diagnostics.CrashReporting.setConsent(enabled)
                            crashConsent = com.hadithly.app.core.diagnostics.CrashReporting.hasConsent
                        }).testTag("settings.crashReports")) {
                Text(stringResource(R.string.diagnostics_consent), modifier = Modifier.weight(1f), color = colors.textPrimary)
                Switch(checked = crashConsent, onCheckedChange = null,
                    colors = SwitchDefaults.colors(checkedTrackColor = colors.interactive))
            }
            Text(stringResource(R.string.diagnostics_privacy), fontSize = 14.sp, color = colors.textSecondary)
        }
        CardColumn {
            Text(nativeText("Your data"), fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
            if (signedIn) {
                Text(nativeText("Export your profile, preferences, Saved items, folders, reading progress, and your own contributions as JSON."), fontSize = 14.sp, color = colors.textSecondary)
                Button(
                    enabled = !exporting,
                    onClick = { showExportConfirm = true },
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.surfaceElevated, contentColor = colors.textPrimary),
                    modifier = Modifier.fillMaxWidth().testTag("settings.export"),
                ) { Text(if (exporting) "Preparing…" else "Export my data", fontWeight = FontWeight.SemiBold) }
                exportNotice?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
            } else {
                Text(nativeText("Sign in to export your synced data. Guest data never leaves this device."), fontSize = 14.sp, color = colors.textSecondary)
                Button(
                    onClick = onShowSignIn,
                    shape = RoundedCornerShape(10.dp),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.interactive, contentColor = colors.onInteractive),
                    modifier = Modifier.fillMaxWidth().testTag("settings.signin"),
                ) { Text(nativeText("Sign in"), fontWeight = FontWeight.SemiBold) }
            }
        }
        CardColumn {
            PolicyRow(title = "Privacy Policy", onClick = { uriHandler.openUri(SettingsLinks.PRIVACY) })
            PolicyRow(title = "Terms of Use", onClick = { uriHandler.openUri(SettingsLinks.TERMS) })
            PolicyRow(
                title = "How deletion works",
                onClick = { uriHandler.openUri(SettingsLinks.DELETE_ACCOUNT_INFO) },
                modifier = Modifier.testTag("settings.deletionInfo"),
            )
        }
        if (signedIn) {
            CardColumn {
                Text(SettingsDeletionCopy.SUBSCRIPTION_WARNING, fontSize = 12.sp, color = colors.textSecondary)
                TextButton(
                    enabled = !deletingAccount,
                    onClick = { showDeleteConfirmation = true },
                    modifier = Modifier.testTag("settings.deleteAccount"),
                ) { Text(if (deletingAccount) "Deleting…" else "Delete account", color = Color(0xFFFF6B6B)) }
            }
        }
    }

    if (showExportConfirm) {
        AlertDialog(
            onDismissRequest = { if (!exporting) showExportConfirm = false },
            title = { Text(nativeText("Export your data?")) },
            text = { Text(nativeText("The file contains only your portable data. You must be signed in; an expired session signs you in again first.")) },
            confirmButton = {
                TextButton(
                    onClick = {
                        showExportConfirm = false
                        exporting = true
                        saveDocument.launch(SettingsExport.fileName())
                    },
                ) { Text(nativeText("Choose location")) }
            },
            dismissButton = {
                TextButton(onClick = { showExportConfirm = false }) { Text(nativeText("Cancel"), color = colors.textSecondary) }
            },
            containerColor = colors.surface,
        )
    }
    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { if (!deletingAccount) showDeleteConfirmation = false },
            title = { Text(SettingsDeletionCopy.TITLE) },
            text = { Text("${SettingsDeletionCopy.MESSAGE} ${SettingsDeletionCopy.SUBSCRIPTION_WARNING}") },
            confirmButton = {
                TextButton(
                    enabled = !deletingAccount,
                    onClick = {
                        deletingAccount = true
                        scope.launch {
                            app.session.deleteAccount()
                                .onSuccess { showDeleteConfirmation = false }
                                .onFailure {
                                    showDeleteConfirmation = false
                                    deletionError = it.message ?: "Please try again."
                                }
                            deletingAccount = false
                        }
                    },
                ) { Text(nativeText("Delete account and data"), color = Color(0xFFFF6B6B)) }
            },
            dismissButton = {
                TextButton(enabled = !deletingAccount, onClick = { showDeleteConfirmation = false }) {
                    Text(nativeText("Cancel"), color = colors.textSecondary)
                }
            },
            containerColor = colors.surface,
        )
    }
    deletionError?.let { message ->
        AlertDialog(
            onDismissRequest = { deletionError = null },
            title = { Text(nativeText("Account deletion failed")) },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { deletionError = null }) { Text(nativeText("OK")) } },
            containerColor = colors.surface,
        )
    }
}

@Composable
private fun PolicyRow(title: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp),
    ) {
        Text(title, fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
        Icon(Icons.AutoMirrored.Filled.OpenInNew, null, tint = colors.textSecondary, modifier = Modifier.size(16.dp))
    }
}

// ── Help & support / About ─────────────────────────────────────────────────

@Composable
private fun HelpSupportDestination() {
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    val context = LocalContext.current
    ScrollColumn {
        CardColumn {
            PolicyRow(title = "FAQ & guides", onClick = { uriHandler.openUri(SettingsLinks.SUPPORT) })
            PolicyRow(
                title = "Contact support",
                onClick = {
                    runCatching {
                        context.startActivity(
                            Intent(Intent.ACTION_SENDTO, android.net.Uri.parse("mailto:${SettingsLinks.SUPPORT_EMAIL}?subject=Hadithly%20support"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
                },
                modifier = Modifier.testTag("settings.help.contact"),
            )
            Text(SettingsLinks.SUPPORT_EMAIL, fontSize = 12.sp, color = colors.textSecondary)
            PolicyRow(
                title = "Report a translation issue",
                onClick = {
                    runCatching {
                        context.startActivity(
                            Intent(Intent.ACTION_SENDTO, android.net.Uri.parse("mailto:${SettingsLinks.SUPPORT_EMAIL}?subject=Translation%20issue"))
                                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK),
                        )
                    }
                },
            )
            Text(nativeText("Include the collection and hadith number."), fontSize = 12.sp, color = colors.textSecondary)
            PolicyRow(
                title = "Share Hadithly",
                onClick = {
                    val send = Intent(Intent.ACTION_SEND).apply {
                        type = "text/plain"
                        putExtra(Intent.EXTRA_TEXT, SettingsLinks.SHARE_URL)
                    }
                    runCatching {
                        context.startActivity(Intent.createChooser(send, "Share Hadithly").addFlags(Intent.FLAG_ACTIVITY_NEW_TASK))
                    }
                },
                modifier = Modifier.testTag("settings.help.share"),
            )
        }
    }
}

@Composable
private fun AboutLegalDestination() {
    val colors = LocalHadithlyColors.current
    val uriHandler = LocalUriHandler.current
    var showLicenses by remember { mutableStateOf(false) }
    ScrollColumn {
        CardColumn {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text("Hadithly", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary, modifier = Modifier.weight(1f))
                Text("${BuildConfig.VERSION_NAME} (${BuildConfig.VERSION_CODE})", fontSize = 12.sp, color = colors.textSecondary)
            }
            Text(
                nativeText("A quiet reader for the seven major hadith collections. Arabic text is licensed from its sources; AI translations are always labeled."),
                fontSize = 14.sp,
                color = colors.textSecondary,
            )
        }
        CardColumn {
            PolicyRow(title = "Font licenses", onClick = { showLicenses = true }, modifier = Modifier.testTag("settings.about.licenses"))
            PolicyRow(title = "Privacy Policy", onClick = { uriHandler.openUri(SettingsLinks.PRIVACY) })
            PolicyRow(title = "Terms of Use", onClick = { uriHandler.openUri(SettingsLinks.TERMS) })
        }
    }
    if (showLicenses) {
        AlertDialog(
            onDismissRequest = { showLicenses = false },
            title = { Text(nativeText("Licenses")) },
            text = {
                Text("Arabic reading faces — Amiri, Scheherazade New, and Noto Naskh Arabic — are licensed under the SIL Open Font License 1.1 (https://openfontlicense.org). Full license records live in docs/FONT_LICENSES.md. Hadith source identity, authenticity scope, and license records travel with every text.")
            },
            confirmButton = { TextButton(onClick = { showLicenses = false }) { Text(nativeText("Done")) } },
            containerColor = colors.surface,
        )
    }
}

// ── Shared layout ──────────────────────────────────────────────────────────

@Composable
private fun ScrollColumn(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState()).padding(16.dp),
        content = content,
    )
}

@Composable
private fun CardColumn(content: @Composable androidx.compose.foundation.layout.ColumnScope.() -> Unit) {
    val colors = LocalHadithlyColors.current
    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxWidth().background(colors.surface, RoundedCornerShape(16.dp)).padding(16.dp),
        content = content,
    )
}

@Composable
internal fun SettingsSingleChoiceRow(
    label: String,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalHadithlyColors.current
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 48.dp)
            .selectable(selected = selected, onClick = onClick, role = androidx.compose.ui.semantics.Role.RadioButton)
            .padding(horizontal = 4.dp),
    ) {
        androidx.compose.material3.RadioButton(
            selected = selected,
            onClick = null,
            colors = androidx.compose.material3.RadioButtonDefaults.colors(
                selectedColor = colors.interactive,
                unselectedColor = colors.textSecondary,
            ),
        )
        Text(label, fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f).padding(start = 8.dp))
    }
}

@Composable
private fun SettingsDestination.localizedTitle(): String = stringResource(when (this) {
    SettingsDestination.PROFILE -> R.string.settings_profile
    SettingsDestination.APPEARANCE -> R.string.settings_appearance
    SettingsDestination.APP_LANGUAGE -> R.string.settings_app_language
    SettingsDestination.HADITH_TRANSLATION -> R.string.settings_hadith_translation
    SettingsDestination.READING_AND_TYPE -> R.string.settings_reading_type
    SettingsDestination.OFFLINE_STORAGE -> R.string.settings_offline_storage
    SettingsDestination.NOTIFICATIONS -> R.string.settings_notifications
    SettingsDestination.SUBSCRIPTION -> R.string.settings_subscription
    SettingsDestination.PRIVACY_AND_DATA -> R.string.settings_privacy_data
    SettingsDestination.HELP_AND_SUPPORT -> R.string.settings_help_support
    SettingsDestination.ABOUT_AND_LEGAL -> R.string.settings_about_legal
})
