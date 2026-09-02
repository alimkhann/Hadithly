@file:OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)

package com.hadithly.app.features.settings

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.NavigateNext
import androidx.compose.material.icons.filled.Check
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.NotificationsNone
import androidx.compose.material.icons.filled.Person
import androidx.compose.material.icons.filled.Security
import androidx.compose.material.icons.filled.TextFields
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.TimePicker
import androidx.compose.material3.rememberTimePickerState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.content.ContextCompat
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.clerk.api.Clerk
import com.hadithly.app.core.data.SupportedLanguages
import com.hadithly.app.core.push.PushNotificationManager
import com.hadithly.app.core.push.PushRegistrationState
import com.hadithly.app.core.theme.LocalHadithlyColors
import com.hadithly.app.features.main.rememberApp
import kotlinx.coroutines.launch

@Composable
fun SettingsScreen(onShowSignIn: () -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val language by app.settings.preferredLanguage.collectAsStateWithLifecycle()
    val arabicFontSize by app.settings.arabicFontSize.collectAsStateWithLifecycle()
    val syncSummary by app.session.syncSummary.collectAsStateWithLifecycle()
    val canModerate by app.session.canModerate.collectAsStateWithLifecycle()
    val sessions by Clerk.sessionsFlow.collectAsStateWithLifecycle()
    val signedIn = sessions.isNotEmpty()
    var showAdminReview by remember { mutableStateOf(false) }

    Column(
        verticalArrangement = Arrangement.spacedBy(12.dp),
        modifier = Modifier.fillMaxSize().background(colors.background).verticalScroll(rememberScrollState()).padding(16.dp),
    ) {
        Text("Settings", fontSize = 30.sp, fontWeight = FontWeight.Bold, color = colors.textPrimary)
        AccountCard(signedIn, syncSummary, onShowSignIn)
        ReadingCard(language, arabicFontSize, app.settings::setPreferredLanguage, app.settings::setArabicFontSize)
        NotificationCard(signedIn)
        if (canModerate) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.surface, RoundedCornerShape(16.dp))
                    .clickable { showAdminReview = true }
                    .testTag("settings.translationReview")
                    .padding(16.dp),
            ) {
                Icon(Icons.Filled.Security, null, tint = colors.accent)
                Spacer(Modifier.size(12.dp))
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("Translation review", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                    Text("Approve AI-reviewed contributions", fontSize = 12.sp, color = colors.textSecondary)
                }
                Icon(Icons.AutoMirrored.Filled.NavigateNext, null, tint = colors.textSecondary)
            }
        }
        Spacer(Modifier.size(16.dp))
    }
    if (showAdminReview) AdminReviewSheet { showAdminReview = false }
}

@Composable
private fun AccountCard(signedIn: Boolean, syncSummary: String?, onShowSignIn: () -> Unit) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val scope = rememberCoroutineScope()
    val uriHandler = LocalUriHandler.current
    var showDeleteConfirmation by remember { mutableStateOf(false) }
    var deletingAccount by remember { mutableStateOf(false) }
    var deletionError by remember { mutableStateOf<String?>(null) }
    CardColumn {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Box(Modifier.size(38.dp).background(colors.surfaceElevated, CircleShape), contentAlignment = Alignment.Center) {
                Icon(Icons.Filled.Person, null, tint = colors.textSecondary, modifier = Modifier.size(20.dp))
            }
            Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                Text(if (signedIn) (Clerk.user?.firstName ?: "Account") else "Reading as a guest", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
                Text(if (signedIn) "Your reading syncs across devices." else "Reading works without an account.", fontSize = 12.sp, color = colors.textSecondary)
            }
        }
        if (!signedIn) {
            Text("Sign in to carry your bookmarks, favorites, and notes across devices.", fontSize = 14.sp, color = colors.textSecondary)
        }
        syncSummary?.let { Text(it, fontSize = 12.sp, color = colors.textSecondary) }
        if (signedIn) {
            TextButton(onClick = { scope.launch { Clerk.auth.signOut() } }, modifier = Modifier.testTag("settings.signout")) {
                Text("Sign out", color = colors.textPrimary)
            }
            TextButton(onClick = { uriHandler.openUri("https://play.google.com/store/account/subscriptions") }) {
                Text("Manage subscription", color = colors.textSecondary)
            }
            TextButton(
                enabled = !deletingAccount,
                onClick = { showDeleteConfirmation = true },
                modifier = Modifier.testTag("settings.deleteAccount"),
            ) {
                Text(if (deletingAccount) "Deleting…" else "Delete account", color = Color(0xFFFF6B6B))
            }
        } else {
            Button(
                onClick = onShowSignIn,
                shape = RoundedCornerShape(10.dp),
                colors = ButtonDefaults.buttonColors(containerColor = colors.accent, contentColor = Color.Black),
                modifier = Modifier.fillMaxWidth().testTag("settings.signin"),
            ) { Text("Sign in", fontWeight = FontWeight.SemiBold) }
        }
    }

    if (showDeleteConfirmation) {
        AlertDialog(
            onDismissRequest = { if (!deletingAccount) showDeleteConfirmation = false },
            title = { Text("Delete account permanently?") },
            text = {
                Text("This removes your synced bookmarks, favorites, notes, reading progress, submissions, and sign-in. It cannot be undone. Store subscriptions are not cancelled automatically.")
            },
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
                ) { Text("Delete account and data", color = Color(0xFFFF6B6B)) }
            },
            dismissButton = {
                TextButton(enabled = !deletingAccount, onClick = { showDeleteConfirmation = false }) {
                    Text("Cancel", color = colors.textSecondary)
                }
            },
            containerColor = colors.surface,
        )
    }
    deletionError?.let { message ->
        AlertDialog(
            onDismissRequest = { deletionError = null },
            title = { Text("Account deletion failed") },
            text = { Text(message) },
            confirmButton = { TextButton(onClick = { deletionError = null }) { Text("OK") } },
            containerColor = colors.surface,
        )
    }
}

@Composable
private fun ReadingCard(language: String, arabicFontSize: Float, onLanguage: (String) -> Unit, onArabicSize: (Float) -> Unit) {
    val colors = LocalHadithlyColors.current
    CardColumn {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.TextFields, null, tint = colors.textSecondary)
            Text("Reading", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
        }
        Text("Arabic type size", fontSize = 14.sp, color = colors.textPrimary)
        Slider(
            value = arabicFontSize,
            onValueChange = onArabicSize,
            valueRange = 18f..40f,
            steps = 21,
            colors = SliderDefaults.colors(thumbColor = colors.accent, activeTrackColor = colors.accent, inactiveTrackColor = colors.surfaceElevated),
            modifier = Modifier.testTag("settings.arabicSize"),
        )
        Text("${arabicFontSize.toInt()} pt", fontSize = 11.sp, color = colors.textSecondary)
        Text("نَعْبُدُكَ وَإِيَّاكَ نَسْتَعِينُ", fontSize = arabicFontSize.sp, color = colors.textPrimary, modifier = Modifier.fillMaxWidth())
        Text("Translation language", fontSize = 14.sp, color = colors.textPrimary)
        SupportedLanguages.all.forEach { (code, name) ->
            val selected = code == language
            Row(
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier
                    .fillMaxWidth()
                    .background(if (selected) colors.accentSoft else colors.surfaceElevated, RoundedCornerShape(10.dp))
                    .clickable { onLanguage(code) }
                    .testTag("settings.language.$code")
                    .padding(horizontal = 14.dp, vertical = 11.dp),
            ) {
                Text(name, fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                if (selected) Icon(Icons.Filled.Check, null, tint = colors.accent, modifier = Modifier.size(16.dp))
            }
        }
    }
}

@Composable
private fun NotificationCard(signedIn: Boolean) {
    val app = rememberApp()
    val colors = LocalHadithlyColors.current
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val enabled by app.settings.dailyNotificationEnabled.collectAsStateWithLifecycle()
    val time by app.settings.dailyNotificationTime.collectAsStateWithLifecycle()
    val pushState by app.push.state.collectAsStateWithLifecycle()
    var showTimePicker by remember { mutableStateOf(false) }
    var status by remember { mutableStateOf<String?>(null) }

    fun persist(nextEnabled: Boolean, nextTime: String = time) {
        app.settings.setDailyNotificationEnabled(nextEnabled)
        scope.launch {
            runCatching {
                app.repository.setDailyNotification(nextEnabled, nextTime, PushNotificationManager.timezoneOffsetMinutes())
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

    CardColumn {
        Row(horizontalArrangement = Arrangement.spacedBy(10.dp), verticalAlignment = Alignment.CenterVertically) {
            Icon(Icons.Filled.NotificationsNone, null, tint = colors.textSecondary)
            Text("Daily hadith", fontSize = 17.sp, fontWeight = FontWeight.SemiBold, color = colors.textPrimary)
        }
        if (!signedIn) {
            Text("Sign in to receive the daily hadith on this device.", fontSize = 14.sp, color = colors.textSecondary)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Text("Send me a hadith every day", fontSize = 14.sp, color = colors.textPrimary)
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
                    colors = SwitchDefaults.colors(checkedThumbColor = Color.Black, checkedTrackColor = colors.accent),
                    modifier = Modifier.testTag("settings.notificationsToggle"),
                )
            }
            if (enabled) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    modifier = Modifier.fillMaxWidth().background(colors.surfaceElevated, RoundedCornerShape(10.dp)).clickable { showTimePicker = true }.testTag("settings.notificationsTime").padding(14.dp),
                ) {
                    Text("Time", fontSize = 14.sp, color = colors.textPrimary, modifier = Modifier.weight(1f))
                    Text(time, fontSize = 14.sp, color = colors.accent)
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
                    app.settings.setDailyNotificationTime(next)
                    persist(enabled, next)
                    showTimePicker = false
                }) { Text("Done", color = colors.accent) }
            },
            dismissButton = { TextButton(onClick = { showTimePicker = false }) { Text("Cancel", color = colors.textSecondary) } },
            text = { TimePicker(state = picker) },
            containerColor = colors.surface,
        )
    }
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
