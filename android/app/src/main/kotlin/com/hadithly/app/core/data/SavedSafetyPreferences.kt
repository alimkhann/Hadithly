package com.hadithly.app.core.data

import android.content.SharedPreferences

/** Device-local protection for destructive Saved actions. */
class SavedSafetyPreferences(private val preferences: SharedPreferences) {
    var confirmsRemoval: Boolean
        get() = preferences.getBoolean(KEY, true)
        set(value) = preferences.edit().putBoolean(KEY, value).apply()

    private companion object { const val KEY = "saved.confirmRemoval" }
}
