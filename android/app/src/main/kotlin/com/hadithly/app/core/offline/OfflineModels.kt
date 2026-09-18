package com.hadithly.app.core.offline

import kotlinx.serialization.Serializable

/**
 * O2 download-management domain. Mirrors
 * `backend/convex/lib/offlineDumps.ts` for identity rules and
 * `chunkReaderHadiths` for offline paging, and the iOS `OfflineModels`.
 * Pure and unit-testable: no network, no Convex, no UI.
 */

@Serializable
data class OfflineDownloadRecord(
    val kind: String, // "base" or "pack"
    val contentVersion: String,
    val locale: String? = null,
    val state: String, // OfflineDownloadState wire value
    val reason: String? = null,
    val updatedAt: Double,
)

@Serializable
data class OfflineCollectionRecord(
    val activeBase: String? = null,
    val activeBaseGeneratedAt: Double? = null,
    val activePacks: Map<String, String> = emptyMap(), // locale -> contentVersion
    val stagedBase: String? = null,
    val stagedPacks: Map<String, String> = emptyMap(),
    val download: OfflineDownloadRecord? = null,
)

/** Device-local registry. Never synced, never exported, never merged. */
@Serializable
data class OfflineRegistry(
    val version: Double = CURRENT_VERSION,
    val wifiOnly: Boolean = true,
    val lastManifestCheck: Double? = null,
    val collections: Map<String, OfflineCollectionRecord> = emptyMap(),
) {
    companion object {
        const val CURRENT_VERSION = 1.0
    }
}

enum class OfflineDownloadState(val wire: String) {
    QUEUED("queued"),
    DOWNLOADING("downloading"),
    PAUSED("paused"),
    VERIFYING("verifying"),
    FAILED("failed"),
    ;

    companion object {
        fun fromWire(wire: String): OfflineDownloadState =
            entries.firstOrNull { it.wire == wire } ?: FAILED
    }
}

/** User-facing status derived from registry + manifests. */
sealed interface OfflineCollectionStatus {
    data object NotInstalled : OfflineCollectionStatus
    data class Queued(val progress: Double) : OfflineCollectionStatus
    data class Downloading(val progress: Double) : OfflineCollectionStatus
    data class Paused(val progress: Double) : OfflineCollectionStatus
    data object Verifying : OfflineCollectionStatus
    data class Failed(val reason: String) : OfflineCollectionStatus
    data class Active(val version: String, val updateAvailable: Boolean, val stalePack: Boolean) : OfflineCollectionStatus
    data class AppUpdateRequired(val minVersion: String) : OfflineCollectionStatus
}

sealed interface OfflineEnqueueResult {
    data object Started : OfflineEnqueueResult
    data object AlreadyActive : OfflineEnqueueResult
    data class Blocked(val reason: String) : OfflineEnqueueResult
}

object OfflineModels {
    /** Sanitizes `od1:<hex>` for use as a directory name. */
    fun directoryName(contentVersion: String): String = contentVersion.replace(":", "-")

    /**
     * Dotted-decimal provider-id order ("2" < "4.5" < "10"), not
     * lexicographic. Mirrors `compareProviderHadithIds` on the backend.
     */
    fun compareProviderHadithIds(left: String, right: String): Int {
        val lParts = left.split(".").map { it.toIntOrNull() ?: 0 }
        val rParts = right.split(".").map { it.toIntOrNull() ?: 0 }
        for (index in 0 until maxOf(lParts.size, rParts.size)) {
            val l = lParts.getOrElse(index) { 0 }
            val r = rParts.getOrElse(index) { 0 }
            if (l != r) return l - r
        }
        return 0
    }

    /**
     * Mirrors `chunkReaderHadiths`: at most 10 items or 5,200 chars per page
     * so offline pages match the server's content-sized paging.
     */
    fun <T> chunkHadiths(
        items: List<T>,
        arabicText: (T) -> String,
        englishText: (T) -> String?,
        narrator: (T) -> String?,
        narratorAr: (T) -> String?,
    ): List<List<T>> {
        val maxItems = 10
        val maxChars = 5200
        val pages = mutableListOf<List<T>>()
        var current = mutableListOf<T>()
        var currentChars = 0
        for (item in items) {
            val itemChars = arabicText(item).length + (englishText(item)?.length ?: 0) +
                (narrator(item)?.length ?: 0) + (narratorAr(item)?.length ?: 0)
            if (current.isNotEmpty() && (current.size >= maxItems || currentChars + itemChars > maxChars)) {
                pages.add(current)
                current = mutableListOf()
                currentChars = 0
            }
            current.add(item)
            currentChars += itemChars
        }
        if (current.isNotEmpty()) pages.add(current)
        return pages
    }

    /** Compares semantic versions. Malformed parts count as 0 (fail closed). */
    fun compareAppVersions(left: String, right: String): Int {
        val lParts = left.split(".").map { it.toIntOrNull() ?: 0 }
        val rParts = right.split(".").map { it.toIntOrNull() ?: 0 }
        for (index in 0 until maxOf(lParts.size, rParts.size)) {
            val l = lParts.getOrElse(index) { 0 }
            val r = rParts.getOrElse(index) { 0 }
            if (l != r) return l - r
        }
        return 0
    }

    fun appVersionSatisfiesMinimum(current: String, minimum: String): Boolean =
        compareAppVersions(current, minimum) >= 0

    fun formatBytes(bytes: Long): String = when {
        bytes < 1024 -> "$bytes B"
        bytes < 1024 * 1024 -> "${bytes / 1024} KB"
        else -> "%.1f MB".format(bytes / 1024.0 / 1024.0)
    }

    fun progressKey(slug: String, kind: String, locale: String?): String =
        "$slug#$kind#${locale ?: "-"}"

    fun packKey(slug: String, locale: String): String = "$slug#$locale"
}
