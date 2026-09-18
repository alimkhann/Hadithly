package com.hadithly.app.features.settings

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

/**
 * S1 Settings information architecture (mirrors iOS SettingsS1.swift).
 * Every row in the Settings root maps to exactly one destination or one
 * immediate action — no dead placeholders. Pure Kotlin so unit tests can
 * enforce the gate without an emulator.
 */
enum class SettingsDestination(
    val id: String,
    val title: String,
    val subtitle: String,
) {
    PROFILE("profile", "Profile", "Picture, name, username"),
    APPEARANCE("appearance", "Appearance", "System, Light, Paper, Dark"),
    APP_LANGUAGE("appLanguage", "App language", "Interface language"),
    HADITH_TRANSLATION("hadithTranslation", "Hadith translation", "Translation language"),
    READING_AND_TYPE("readingAndType", "Reading & type", "Direction, visibility, Arabic type"),
    OFFLINE_STORAGE("offlineStorage", "Offline storage", "Downloads arrive in O2"),
    NOTIFICATIONS("notifications", "Notifications", "Daily hadith reminder"),
    SUBSCRIPTION("subscription", "Subscription", "Free or Pro"),
    PRIVACY_AND_DATA("privacyAndData", "Privacy & data", "Export, policies, deletion"),
    HELP_AND_SUPPORT("helpAndSupport", "Help & support", "Contact, FAQ, share"),
    ABOUT_AND_LEGAL("aboutAndLegal", "About & legal", "Version, licenses, terms"),
    ;

    val testTag: String get() = "settings.row.$id"
}

/** Canonical external destinations; the site pages are live on hadithly.app. */
object SettingsLinks {
    const val PRIVACY = "https://hadithly.app/privacy"
    const val TERMS = "https://hadithly.app/terms"
    const val SUPPORT = "https://hadithly.app/support"
    const val DELETE_ACCOUNT_INFO = "https://hadithly.app/delete-account"
    const val PLAY_SUBSCRIPTIONS = "https://play.google.com/store/account/subscriptions"
    const val SUPPORT_EMAIL = "support@hadithly.app"
    const val SHARE_URL = "https://hadithly.app"
}

/**
 * Deletion keeps its own subscription warning, separate from the generic
 * data-removal copy.
 */
object SettingsDeletionCopy {
    const val TITLE = "Delete account permanently?"
    const val MESSAGE =
        "This removes your synced bookmarks, favorites, notes, reading " +
            "progress, submissions, and sign-in. It cannot be undone."
    const val SUBSCRIPTION_WARNING =
        "Your Play Store subscription is separate: deleting your Hadithly " +
            "account does not cancel it. Manage or cancel it in your Google " +
            "Play subscriptions first if you do not want to keep paying."
}

/** Portable-export helpers for the `users:exportCurrentUserData` query. */
object SettingsExport {
    fun fileName(date: Date = Date()): String {
        val formatter = SimpleDateFormat("yyyy-MM-dd", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }
        return "hadithly-export-${formatter.format(date)}.json"
    }

    /** Key fragments that must never appear in an export payload. */
    val forbiddenFragments = listOf("pushTokens", "adminAuditLog", "revenueCatAppUserId")
}

/** Subscription display derived from the `users:getCurrentUser` row. */
object SettingsSubscription {
    fun displayName(tier: String?): String = when (tier) {
        "pro" -> "Hadithly Pro"
        "trial" -> "Pro trial"
        else -> "Free"
    }

    fun quotaLine(used: Double?, limit: Double?): String? {
        if (used == null || limit == null || limit <= 0) return null
        return "${used.toInt()} of ${limit.toInt()} AI translations used this month"
    }
}
