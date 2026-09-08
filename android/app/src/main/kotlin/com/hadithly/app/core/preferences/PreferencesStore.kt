package com.hadithly.app.core.preferences

import android.content.SharedPreferences
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.serialization.json.Json

private val storeJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }

/**
 * Persists the F2 reader preference contract and performs the one-time
 * migration from the legacy single-language settings. The stored payload is
 * a versioned JSON blob under "reader.preferences.v1" in the shared
 * "hadithly" preferences file; the legacy keys ("user.preferredLanguage",
 * "reader.arabicFontSize") stay readable for the migration and keep being
 * written for backend compatibility. Mirrors the iOS PreferencesStore.
 */
class PreferencesStore(sharedPrefs: SharedPreferences) {

    data class MigrationResult(
        val preferences: ReaderPreferences,
        /** True when the seed came from the legacy language key. */
        val seededFromLegacy: Boolean,
    )

    private val prefs: SharedPreferences = sharedPrefs

    private val _preferences = MutableStateFlow(load(prefs))
    val preferences: StateFlow<ReaderPreferences> = _preferences

    /** Fired after every explicit local change (not after server adoption). */
    var onPreferencesChanged: ((ReaderPreferences) -> Unit)? = null

    companion object {
        const val STORE_KEY = "reader.preferences.v1"
        const val LEGACY_LANGUAGE_KEY = "user.preferredLanguage"
        const val LEGACY_ARABIC_FONT_SIZE_KEY = "reader.arabicFontSize"

        /**
         * One-time migration: an existing v1 payload wins (a later explicit
         * choice is never reset); otherwise both locales seed from the legacy
         * translation-language setting. With neither source, defaults to en/en.
         */
        fun migrate(
            storedJson: String?,
            legacyLanguage: String?,
            legacyArabicFontSize: Float? = null,
        ): MigrationResult {
            if (storedJson != null) {
                runCatching { storeJson.decodeFromString<ReaderPreferences>(storedJson) }
                    .getOrNull()
                    ?.let { stored ->
                        return MigrationResult(preferences = stored, seededFromLegacy = false)
                    }
            }
            val canonical = legacyLanguage?.let { LocaleFallback.canonicalizeLocaleTag(it) }
            if (canonical != null) {
                var seeded = ReaderPreferences(
                    uiLocale = canonical,
                    translationLocale = canonical,
                )
                if (legacyArabicFontSize != null) {
                    seeded = seeded.copy(
                        arabicFontSize = legacyArabicFontSize
                            .coerceIn(ReaderPreferences.MIN_ARABIC_FONT_SIZE, ReaderPreferences.MAX_ARABIC_FONT_SIZE),
                    )
                }
                return MigrationResult(preferences = seeded, seededFromLegacy = true)
            }
            return MigrationResult(preferences = ReaderPreferences(), seededFromLegacy = false)
        }
    }

    // Mutations

    /** Onboarding "Choose your language": writes both locales at once. */
    fun applyOnboardingLanguage(code: String) {
        val canonical = LocaleFallback.canonicalizeLocaleTag(code) ?: return
        update { it.copy(uiLocale = canonical, translationLocale = canonical) }
        writeLegacyLanguage(canonical)
    }

    fun setUILocale(code: String) {
        val canonical = LocaleFallback.canonicalizeLocaleTag(code) ?: return
        update { it.copy(uiLocale = canonical) }
    }

    fun setTranslationLocale(code: String) {
        val canonical = LocaleFallback.canonicalizeLocaleTag(code) ?: return
        update { it.copy(translationLocale = canonical) }
        writeLegacyLanguage(canonical)
    }

    fun setReadingDirection(direction: ReadingDirection) =
        update { it.copy(readingDirection = direction) }

    fun setTheme(theme: ReaderTheme) = update { it.copy(theme = theme) }

    fun setArabicFont(font: ArabicFont) = update { it.copy(arabicFont = font) }

    fun setArabicFontSize(size: Float) = update {
        it.copy(
            arabicFontSize = size.coerceIn(
                ReaderPreferences.MIN_ARABIC_FONT_SIZE,
                ReaderPreferences.MAX_ARABIC_FONT_SIZE,
            ),
        )
    }

    /**
     * Rejects the all-hidden state: returns false without a preference
     * update when both layers would be hidden.
     */
    fun setVisibility(arabic: Boolean? = null, translation: Boolean? = null): Boolean {
        val current = _preferences.value
        val nextArabic = arabic ?: current.arabicVisible
        val nextTranslation = translation ?: current.translationVisible
        if (!nextArabic && !nextTranslation) return false
        update { it.copy(arabicVisible = nextArabic, translationVisible = nextTranslation) }
        return true
    }

    /**
     * Adopts server-side preferences only when they are newer than the local
     * state (last-write-wins by updatedAt). Does not re-emit
     * onPreferencesChanged (no sync loop).
     */
    fun adoptServer(incoming: ReaderPreferences) {
        val validated = runCatching { ReaderPreferencesValidator.validated(incoming) }.getOrNull() ?: return
        if (validated.updatedAt <= _preferences.value.updatedAt) return
        _preferences.value = validated
        persist()
        writeLegacyLanguage(validated.translationLocale)
    }

    // Internals

    private fun load(target: SharedPreferences): ReaderPreferences {
        val storedJson = target.getString(STORE_KEY, null)
        val legacyLanguage = target.getString(LEGACY_LANGUAGE_KEY, null)
        val legacySize = if (target.contains(LEGACY_ARABIC_FONT_SIZE_KEY)) {
            target.getFloat(LEGACY_ARABIC_FONT_SIZE_KEY, 26f)
        } else {
            null
        }
        val result = migrate(storedJson, legacyLanguage, legacySize)
        target.edit().putString(STORE_KEY, storeJson.encodeToString(result.preferences)).apply()
        return result.preferences
    }

    private fun update(mutate: (ReaderPreferences) -> ReaderPreferences) {
        val next = mutate(_preferences.value)
            .copy(updatedAt = System.currentTimeMillis().toDouble())
        val validated = runCatching { ReaderPreferencesValidator.validated(next) }.getOrElse { return }
        _preferences.value = validated
        persist()
        onPreferencesChanged?.invoke(validated)
    }

    private fun persist() {
        prefs.edit().putString(STORE_KEY, storeJson.encodeToString(_preferences.value)).apply()
    }

    private fun writeLegacyLanguage(code: String) {
        prefs.edit().putString(LEGACY_LANGUAGE_KEY, code).apply()
    }
}
