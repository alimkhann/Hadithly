package com.hadithly.app.core.push

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import com.google.firebase.FirebaseApp
import com.google.firebase.messaging.FirebaseMessaging
import com.google.firebase.messaging.FirebaseMessagingService
import com.google.firebase.messaging.RemoteMessage
import com.hadithly.app.BuildConfig
import com.hadithly.app.HadithlyApplication
import com.hadithly.app.MainActivity
import com.hadithly.app.R
import com.hadithly.app.core.data.ConvexRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.util.TimeZone

sealed interface PushRegistrationState {
    data object NotConfigured : PushRegistrationState
    data object Ready : PushRegistrationState
    data object Registering : PushRegistrationState
    data object Registered : PushRegistrationState
    data class Failed(val message: String) : PushRegistrationState
}

/**
 * Per-device N1 profile uploaded with every push registration: the IANA
 * timezone (never a fixed offset — offsets cannot survive DST or zone
 * changes) plus the UI and translation locales the cron materializes.
 */
data class DevicePushProfile(
    val timezoneId: String,
    val uiLocale: String,
    val translationLocale: String,
)

/**
 * Owns the FCM registration identifier (a Firebase Installation ID). It can
 * arrive before Clerk restores;
 * the latest value is kept locally and upserted after Convex authentication.
 */
class PushNotificationManager(
    context: Context,
    private val repository: ConvexRepository,
    private val scope: CoroutineScope,
    private val isSignedIn: () -> Boolean,
    private val deviceProfile: () -> DevicePushProfile = {
        DevicePushProfile(
            timezoneId = timezoneId(),
            uiLocale = "en",
            translationLocale = "en",
        )
    },
) {
    private val appContext = context.applicationContext
    private val prefs = appContext.getSharedPreferences("hadithly", Context.MODE_PRIVATE)

    private val _state = MutableStateFlow<PushRegistrationState>(PushRegistrationState.NotConfigured)
    val state: StateFlow<PushRegistrationState> = _state

    val isConfigured: Boolean
        get() = BuildConfig.FIREBASE_CONFIGURED && FirebaseApp.getApps(appContext).isNotEmpty()

    fun start() {
        if (!isConfigured) {
            _state.value = PushRegistrationState.NotConfigured
            return
        }
        ensureDailyNotificationChannel(appContext, deviceProfile().uiLocale)
        _state.value = PushRegistrationState.Ready
        requestAndSaveToken()
    }

    fun requestAndSaveToken() {
        if (!isConfigured) {
            _state.value = PushRegistrationState.NotConfigured
            return
        }
        _state.value = PushRegistrationState.Registering
        FirebaseMessaging.getInstance().register().addOnCompleteListener { task ->
            if (!task.isSuccessful) {
                _state.value = PushRegistrationState.Failed(
                    task.exception?.message ?: "Could not register this device.",
                )
                return@addOnCompleteListener
            }
            // onRegistered() supplies the FID and performs the server upsert.
        }
    }

    fun handleRegistrationId(installationId: String) {
        prefs.edit().putString(KEY_REGISTRATION_ID, installationId).apply()
        if (!isSignedIn() || !repository.isAuthenticated) {
            _state.value = PushRegistrationState.Ready
            return
        }
        scope.launch {
            runCatching { repository.savePushToken(installationId, deviceProfile()) }
                .onSuccess { _state.value = PushRegistrationState.Registered }
                .onFailure {
                    _state.value = PushRegistrationState.Failed(
                        it.message ?: "Could not save this device.",
                    )
                }
        }
    }

    /** Replays a token received before sign-in. */
    fun syncToken() {
        val installationId = prefs.getString(KEY_REGISTRATION_ID, null)
        if (installationId == null) requestAndSaveToken() else handleRegistrationId(installationId)
    }

    companion object {
        private const val KEY_REGISTRATION_ID = "notifications.fcmInstallationId"

        /** IANA timezone id (e.g. "Asia/Almaty") for N1 scheduling. */
        fun timezoneId(): String = java.time.ZoneId.systemDefault().id

        /** Legacy fixed offset (UTC - local minutes). Kept for reference. */
        fun timezoneOffsetMinutes(now: Long = System.currentTimeMillis()): Double =
            -(TimeZone.getDefault().getOffset(now) / 60_000.0)
    }
}

class HadithlyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        HadithlyApplication.instance().push.handleRegistrationId(installationId)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        postDailyNotification(this, message)
    }
}

internal fun postDailyNotification(context: Context, message: RemoteMessage) {
    val notification = message.notification ?: return
    val locale = HadithlyApplication.instance().preferences.preferences.value.uiLocale
    ensureDailyNotificationChannel(context, locale)
    val manager = context.getSystemService(NotificationManager::class.java)
    val launchIntent = Intent(context, MainActivity::class.java).apply {
        flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
        message.data.forEach { (key, value) -> putExtra(key, value) }
    }
    val pendingIntent = PendingIntent.getActivity(
        context,
        0,
        launchIntent,
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
    val built = NotificationCompat.Builder(context, DAILY_CHANNEL_ID)
        .setSmallIcon(R.drawable.ic_launcher_foreground)
        .setContentTitle(notificationDisplayTitle(context, locale, notification.title))
        .setContentText(notification.body)
        .setStyle(NotificationCompat.BigTextStyle().bigText(notification.body))
        .setContentIntent(pendingIntent)
        .setAutoCancel(true)
        .build()
    manager.notify(DAILY_NOTIFICATION_ID, built)
}

private const val DAILY_NOTIFICATION_ID = 1001
private const val DAILY_CHANNEL_ID = "daily_hadith"

internal fun ensureDailyNotificationChannel(context: Context, locale: String) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    val resources = localizedNotificationResources(context, locale)
    context.getSystemService(NotificationManager::class.java).createNotificationChannel(
        NotificationChannel(
            DAILY_CHANNEL_ID,
            resources.getString(R.string.notification_daily_channel_title),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = resources.getString(R.string.notification_daily_channel_description) },
    )
}

private fun localizedNotificationResources(context: Context, locale: String): android.content.res.Resources {
    val configuration = android.content.res.Configuration(context.resources.configuration).apply { setLocale(java.util.Locale.forLanguageTag(locale.replace('_', '-'))) }
    return context.createConfigurationContext(configuration).resources
}

internal fun notificationDisplayTitle(context: Context, locale: String, receivedTitle: String?): String =
    receivedTitle ?: localizedNotificationResources(context, locale).getString(R.string.widget_daily_title)
