package com.hadithly.app.core.preferences

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow

class ReaderExperiencePreferences(private val preferences: SharedPreferences) {
    private val automatic = MutableStateFlow(preferences.getBoolean("reader.automaticTranslation", true))
    val automaticallyTranslates = automatic.asStateFlow()
    private val hint = MutableStateFlow(false)
    val showsActionHint = hint.asStateFlow()

    fun setAutomaticTranslation(enabled: Boolean) {
        preferences.edit().putBoolean("reader.automaticTranslation", enabled).apply()
        automatic.value = enabled
    }

    fun offerActionHint() {
        if (preferences.getBoolean("reader.actionsHintSeen", false)) return
        preferences.edit().putBoolean("reader.actionsHintSeen", true).apply()
        hint.value = true
    }

    fun dismissActionHint() { hint.value = false }
}

class ReaderAutomaticTranslationLedger {
    private val attempted = mutableSetOf<Pair<String, String>>()
    fun claim(hadithId: String, locale: String, hasTranslation: Boolean, hasRequestState: Boolean): Boolean =
        !hasTranslation && !hasRequestState && attempted.add(hadithId to locale)
    fun reset() = attempted.clear()
}
