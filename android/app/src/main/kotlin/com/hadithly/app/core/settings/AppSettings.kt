package com.hadithly.app.core.settings

import android.content.Context
import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow

/**
 * Small preference store backing the reader and onboarding. Mirrors the iOS
 * UserDefaults keys so behavior matches feature for feature.
 */
class AppSettings internal constructor(private val prefs: SharedPreferences) {
    constructor(context: Context) : this(context.getSharedPreferences("hadithly", Context.MODE_PRIVATE))

    private val _onboardingCompleted = MutableStateFlow(prefs.getBoolean(KEY_ONBOARDED, false))
    val onboardingCompleted: StateFlow<Boolean> = _onboardingCompleted

    private val _onboardingNotificationPromptPending = MutableStateFlow(prefs.getBoolean(KEY_NOTIFICATION_PROMPT_PENDING, false))
    val onboardingNotificationPromptPending: StateFlow<Boolean> = _onboardingNotificationPromptPending

    private val _dailyNotificationEnabled = MutableStateFlow(prefs.getBoolean(KEY_DAILY_ENABLED, false))
    val dailyNotificationEnabled: StateFlow<Boolean> = _dailyNotificationEnabled

    private val _dailyNotificationTime = MutableStateFlow(prefs.getString(KEY_DAILY_TIME, "08:00") ?: "08:00")
    val dailyNotificationTime: StateFlow<String> = _dailyNotificationTime

    fun setOnboardingCompleted(completed: Boolean) {
        prefs.edit().putBoolean(KEY_ONBOARDED, completed).apply()
        _onboardingCompleted.value = completed
    }

    fun finishOnboarding() {
        if (_onboardingCompleted.value) return
        prefs.edit().putBoolean(KEY_ONBOARDED, true).putBoolean(KEY_NOTIFICATION_PROMPT_PENDING, true).commit()
        _onboardingNotificationPromptPending.value = true
        _onboardingCompleted.value = true
    }

    fun consumeOnboardingNotificationPrompt(subject: String?) {
        prefs.edit().putBoolean(KEY_NOTIFICATION_PROMPT_PENDING, false)
            .putString(KEY_NOTIFICATION_PROMPT_OWNER, subject ?: GUEST_OWNER).commit()
        _onboardingNotificationPromptPending.value = false
    }

    fun onboardingPromptOwner(): String? = prefs.getString(KEY_NOTIFICATION_PROMPT_OWNER, null)
    fun clearOnboardingPromptOwner() { prefs.edit().remove(KEY_NOTIFICATION_PROMPT_OWNER).commit() }

    fun recordOnboardingNotificationGrant() {
        val owner = onboardingPromptOwner() ?: return
        prefs.edit().putString(KEY_NOTIFICATION_GRANT_OWNER, owner).remove(KEY_NOTIFICATION_PROMPT_OWNER).commit()
    }

    fun claimOnboardingNotificationGrant(subject: String): Boolean {
        val owner = prefs.getString(KEY_NOTIFICATION_GRANT_OWNER, null) ?: return false
        if (owner == GUEST_OWNER) prefs.edit().putString(KEY_NOTIFICATION_GRANT_OWNER, subject).commit()
        return owner == GUEST_OWNER || owner == subject
    }

    fun clearOnboardingNotificationGrant() { prefs.edit().remove(KEY_NOTIFICATION_GRANT_OWNER).commit() }

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
        const val KEY_NOTIFICATION_PROMPT_PENDING = "notifications.onboardingPromptPending"
        const val KEY_NOTIFICATION_PROMPT_OWNER = "notifications.onboardingPromptOwner"
        const val KEY_NOTIFICATION_GRANT_OWNER = "notifications.onboardingGrantOwner"
        const val GUEST_OWNER = "guest"
        const val KEY_DAILY_ENABLED = "notifications.dailyEnabled"
        const val KEY_DAILY_TIME = "notifications.dailyTime"
    }
}
