package com.hadithly.app.core.settings

import android.content.Context
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Small preference store backing the reader and onboarding. Mirrors the iOS
 * UserDefaults keys so behavior matches feature for feature.
 */
class AppSettings(context: Context) {

    private val prefs = context.getSharedPreferences("hadithly", Context.MODE_PRIVATE)

    private val _onboardingCompleted = MutableStateFlow(prefs.getBoolean(KEY_ONBOARDED, false))
    val onboardingCompleted: StateFlow<Boolean> = _onboardingCompleted

    private val _dailyNotificationEnabled = MutableStateFlow(prefs.getBoolean(KEY_DAILY_ENABLED, false))
    val dailyNotificationEnabled: StateFlow<Boolean> = _dailyNotificationEnabled

    private val _dailyNotificationTime = MutableStateFlow(prefs.getString(KEY_DAILY_TIME, "08:00") ?: "08:00")
    val dailyNotificationTime: StateFlow<String> = _dailyNotificationTime

    fun setOnboardingCompleted(completed: Boolean) {
        prefs.edit().putBoolean(KEY_ONBOARDED, completed).apply()
        _onboardingCompleted.value = completed
    }

    fun setDailyNotificationEnabled(enabled: Boolean) {
        prefs.edit().putBoolean(KEY_DAILY_ENABLED, enabled).apply()
        _dailyNotificationEnabled.value = enabled
    }

    fun setDailyNotificationTime(time: String) {
        prefs.edit().putString(KEY_DAILY_TIME, time).apply()
        _dailyNotificationTime.value = time
    }

    private companion object {
        const val KEY_ONBOARDED = "onboarding.completed"
        const val KEY_DAILY_ENABLED = "notifications.dailyEnabled"
        const val KEY_DAILY_TIME = "notifications.dailyTime"
    }
}
