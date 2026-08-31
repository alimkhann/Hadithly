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

    private val _preferredLanguage = MutableStateFlow(prefs.getString(KEY_LANGUAGE, "en") ?: "en")
    val preferredLanguage: StateFlow<String> = _preferredLanguage

    private val _arabicFontSize = MutableStateFlow(prefs.getFloat(KEY_ARABIC_SIZE, 26f))
    val arabicFontSize: StateFlow<Float> = _arabicFontSize

    private val _onboardingCompleted = MutableStateFlow(prefs.getBoolean(KEY_ONBOARDED, false))
    val onboardingCompleted: StateFlow<Boolean> = _onboardingCompleted

    fun setPreferredLanguage(code: String) {
        prefs.edit().putString(KEY_LANGUAGE, code).apply()
        _preferredLanguage.value = code
    }

    fun setArabicFontSize(size: Float) {
        prefs.edit().putFloat(KEY_ARABIC_SIZE, size).apply()
        _arabicFontSize.value = size
    }

    fun setOnboardingCompleted(completed: Boolean) {
        prefs.edit().putBoolean(KEY_ONBOARDED, completed).apply()
        _onboardingCompleted.value = completed
    }

    private companion object {
        const val KEY_LANGUAGE = "user.preferredLanguage"
        const val KEY_ARABIC_SIZE = "reader.arabicFontSize"
        const val KEY_ONBOARDED = "onboarding.completed"
    }
}
