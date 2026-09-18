package com.hadithly.app.core.push

import com.hadithly.app.core.links.CanonicalHadithLink

/**
 * N1 exact-target parsing for daily-push taps, shared by the cold
 * (`onCreate`) and warm (`onNewIntent`) paths. Pure: intent extras in,
 * validated canonical identity out. Extra N1 keys (`volumeId`, `locale`,
 * `ai`, `hadithId`) ride along harmlessly; malformed identity returns null
 * so the app opens wherever it normally would instead of displacing the
 * reader with a bad target.
 */
data class NotificationHadithTarget(
    val collectionSlug: String,
    val collectionName: String,
    val providerHadithId: String,
    val volumeId: String?,
)

fun notificationHadithTarget(extras: Map<String, String?>): NotificationHadithTarget? {
    val slug = extras["collectionSlug"] ?: return null
    val hadithNumber = extras["providerHadithId"] ?: return null
    val link = CanonicalHadithLink.parse(
        "https",
        CanonicalHadithLink.HOST,
        "/hadith/$slug/$hadithNumber",
    ) ?: return null
    return NotificationHadithTarget(
        collectionSlug = link.collectionSlug,
        collectionName = link.collectionName,
        providerHadithId = link.providerHadithId,
        volumeId = extras["volumeId"],
    )
}
