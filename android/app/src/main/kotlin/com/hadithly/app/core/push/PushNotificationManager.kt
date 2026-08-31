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
 * Owns the FCM registration identifier (a Firebase Installation ID). It can
 * arrive before Clerk restores;
 * the latest value is kept locally and upserted after Convex authentication.
 */
class PushNotificationManager(
    context: Context,
    private val repository: ConvexRepository,
    private val scope: CoroutineScope,
    private val isSignedIn: () -> Boolean,
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
        ensureDailyNotificationChannel(appContext)
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
            runCatching { repository.savePushToken(installationId, timezoneOffsetMinutes()) }
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

        /** Same platform-neutral convention as iOS/JavaScript: UTC - local. */
        fun timezoneOffsetMinutes(now: Long = System.currentTimeMillis()): Double =
            -(TimeZone.getDefault().getOffset(now) / 60_000.0)
    }
}

class HadithlyFirebaseMessagingService : FirebaseMessagingService() {
    override fun onRegistered(installationId: String) {
        HadithlyApplication.instance().push.handleRegistrationId(installationId)
    }

    override fun onMessageReceived(message: RemoteMessage) {
        val notification = message.notification ?: return
        ensureDailyNotificationChannel(this)
        val manager = getSystemService(NotificationManager::class.java)
        val launchIntent = Intent(this, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP
            message.data.forEach { (key, value) -> putExtra(key, value) }
        }
        val pendingIntent = PendingIntent.getActivity(
            this,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val built = NotificationCompat.Builder(this, DAILY_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(notification.title ?: "Hadith of the day")
            .setContentText(notification.body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(notification.body))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(DAILY_NOTIFICATION_ID, built)
    }

    private companion object {
        const val DAILY_NOTIFICATION_ID = 1001
    }
}

private const val DAILY_CHANNEL_ID = "daily_hadith"

private fun ensureDailyNotificationChannel(context: Context) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
    context.getSystemService(NotificationManager::class.java).createNotificationChannel(
        NotificationChannel(
            DAILY_CHANNEL_ID,
            "Daily hadith",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = "The daily hadith reminder" },
    )
}
