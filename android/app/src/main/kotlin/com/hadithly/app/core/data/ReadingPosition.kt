package com.hadithly.app.core.data

import kotlinx.serialization.Serializable
import java.security.MessageDigest
import kotlin.math.abs
import kotlin.math.roundToInt

@Serializable
data class ReadingPositionAnchor(
    val provider: String,
    val collectionSlug: String,
    val providerHadithId: String,
)

@Serializable
data class ReadingPosition(
    val schemaVersion: Double = SCHEMA_VERSION,
    val anchor: ReadingPositionAnchor,
    val contentVersion: String,
    val volumeId: String,
    val chapterId: String? = null,
    val pageKey: String,
    val displayPageIndex: Double,
    val rawPageOffset: Double,
    val normalizedOffset: Double,
    val layoutSignature: String,
    val updatedAt: Double,
) {
    init {
        require(schemaVersion == SCHEMA_VERSION)
        require(anchor.provider in setOf("sunnah_now", "sunnah_com", "local_dump"))
        require(anchor.collectionSlug.matches(Regex("^[a-z][a-z0-9-]{1,31}$")))
        require(anchor.providerHadithId.matches(Regex("^[0-9]{1,12}(\\.[0-9]{1,12})*$")))
        require(contentVersion.matches(Regex("^(cv1:[A-Za-z0-9._:-]{1,128}|legacy)$")))
        require(volumeId.matches(Regex("^[A-Za-z0-9._:-]{1,128}$")))
        require(chapterId == null || chapterId.matches(Regex("^[A-Za-z0-9._:-]{1,128}$")))
        require(pageKey.matches(Regex("^(pg1:[A-Za-z0-9._:-]{1,160}|legacy)$")))
        require(displayPageIndex.isFinite() && displayPageIndex >= 1.0 && displayPageIndex % 1.0 == 0.0)
        require(rawPageOffset.isFinite() && rawPageOffset >= 0.0)
        require(normalizedOffset.isFinite() && normalizedOffset in 0.0..1.0)
        require(layoutSignature.matches(Regex("^(ls1:[A-Za-z0-9._:-]{1,160}|legacy)$")))
        require(updatedAt.isFinite() && updatedAt >= 0.0)
    }

    companion object {
        const val SCHEMA_VERSION = 1.0

        fun legacy(
            collectionSlug: String,
            providerHadithId: String,
            volumeId: String,
            updatedAt: Double,
            provider: String = "sunnah_now",
            chapterId: String? = null,
        ): ReadingPosition? {
            if (!collectionSlug.matches(Regex("^[a-z][a-z0-9-]{1,31}$"))) return null
            if (!providerHadithId.matches(Regex("^[0-9]{1,12}(\\.[0-9]{1,12})*$"))) return null
            if (volumeId.isBlank()) return null
            return ReadingPosition(
                anchor = ReadingPositionAnchor(provider, collectionSlug, providerHadithId),
                contentVersion = "legacy",
                volumeId = volumeId,
                chapterId = chapterId,
                pageKey = "legacy",
                displayPageIndex = 1.0,
                rawPageOffset = 0.0,
                normalizedOffset = 0.0,
                layoutSignature = "legacy",
                updatedAt = updatedAt,
            )
        }
    }
}

enum class ReadingWidthClass(val wire: String) {
    COMPACT("compact"),
    REGULAR("regular");

    companion object {
        fun fromWidthDp(widthDp: Double): ReadingWidthClass =
            if (widthDp < 600.0) COMPACT else REGULAR
    }
}

data class ReadingLayout(
    val locale: String,
    val arabicVisible: Boolean,
    val translationVisible: Boolean,
    val arabicFontId: String,
    val arabicFontSize: Double,
    val widthClass: ReadingWidthClass,
    val paginationVersion: Double,
) {
    val signature: String
        get() {
            val canonical = listOf(
                "v1",
                "locale=$locale",
                "arabic=${if (arabicVisible) 1 else 0}",
                "translation=${if (translationVisible) 1 else 0}",
                "font=$arabicFontId",
                "size=${(arabicFontSize * 1_000).roundToInt()}",
                "width=${widthClass.wire}",
                "pagination=${paginationVersion.toInt()}",
            ).joinToString("|")
            val digest = MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8))
            return "ls1:" + digest.joinToString("") { "%02x".format(it.toInt() and 0xff) }
        }
}

data class ReadingPositionAnchorLocation(
    val anchor: ReadingPositionAnchor,
    val volumeId: String,
    val chapterId: String?,
)

data class ReadingPositionPage(
    val pageKey: String,
    val displayPageIndex: Double,
    val anchors: List<ReadingPositionAnchorLocation>,
)

data class ReadingPositionTopology(
    val contentVersion: String,
    val layoutSignature: String,
    val pages: List<ReadingPositionPage>,
)

object ReadingPositionResolver {
    enum class Kind { RAW, SEMANTIC, NEAREST, UNAVAILABLE }

    data class Result(
        val kind: Kind,
        val anchor: ReadingPositionAnchor?,
        val volumeId: String?,
        val chapterId: String?,
        val pageKey: String?,
        val displayPageIndex: Double,
        val rawPageOffset: Double,
        val normalizedOffset: Double,
    )

    private data class Located(
        val location: ReadingPositionAnchorLocation,
        val pageKey: String,
        val displayPageIndex: Double,
        val itemIndex: Int,
    )

    fun resolve(position: ReadingPosition, topology: ReadingPositionTopology): Result {
        val candidates = topology.pages.flatMap { page ->
            page.anchors.mapIndexed { itemIndex, anchor ->
                Located(anchor, page.pageKey, page.displayPageIndex, itemIndex)
            }
        }.filter {
            it.location.anchor.provider == position.anchor.provider &&
                it.location.anchor.collectionSlug == position.anchor.collectionSlug
        }
        val exact = candidates.firstOrNull { it.location.anchor == position.anchor }
        if (exact != null) {
            val rawMatches = topology.contentVersion == position.contentVersion &&
                topology.layoutSignature == position.layoutSignature &&
                exact.pageKey == position.pageKey &&
                exact.displayPageIndex == position.displayPageIndex
            return result(
                if (rawMatches) Kind.RAW else Kind.SEMANTIC,
                exact,
                if (rawMatches) position.rawPageOffset else 0.0,
                position.normalizedOffset,
            )
        }
        if (candidates.isEmpty()) {
            return Result(Kind.UNAVAILABLE, null, null, null, null, 1.0, 0.0, 0.0)
        }
        var preferred = candidates
        val sameVolume = preferred.filter { it.location.volumeId == position.volumeId }
        if (sameVolume.isNotEmpty()) preferred = sameVolume
        position.chapterId?.let { chapterId ->
            val sameChapter = preferred.filter { it.location.chapterId == chapterId }
            if (sameChapter.isNotEmpty()) preferred = sameChapter
        }
        val nearest = preferred.minWithOrNull { left, right ->
            compareDistance(position.anchor.providerHadithId, left, right)
        } ?: return Result(Kind.UNAVAILABLE, null, null, null, null, 1.0, 0.0, 0.0)
        return result(Kind.NEAREST, nearest, 0.0, 0.0)
    }

    private fun result(kind: Kind, located: Located, raw: Double, normalized: Double) = Result(
        kind = kind,
        anchor = located.location.anchor,
        volumeId = located.location.volumeId,
        chapterId = located.location.chapterId,
        pageKey = located.pageKey,
        displayPageIndex = located.displayPageIndex,
        rawPageOffset = raw,
        normalizedOffset = normalized,
    )

    private fun compareDistance(targetId: String, left: Located, right: Located): Int {
        val target = segments(targetId) ?: return compareLocated(left, right)
        val leftParts = segments(left.location.anchor.providerHadithId)
        val rightParts = segments(right.location.anchor.providerHadithId)
        if (leftParts == null || rightParts == null) {
            if (leftParts != null) return -1
            if (rightParts != null) return 1
            return compareLocated(left, right)
        }
        val width = maxOf(target.size, leftParts.size, rightParts.size)
        for (index in 0 until width) {
            val targetPart = target.getOrElse(index) { 0L }
            val leftDistance = abs(leftParts.getOrElse(index) { 0L } - targetPart)
            val rightDistance = abs(rightParts.getOrElse(index) { 0L } - targetPart)
            if (leftDistance != rightDistance) return leftDistance.compareTo(rightDistance)
        }
        val providerOrder = compareSegments(leftParts, rightParts)
        if (providerOrder != 0) return providerOrder
        return compareLocated(left, right)
    }

    private fun compareLocated(left: Located, right: Located): Int {
        val idOrder = left.location.anchor.providerHadithId.compareTo(right.location.anchor.providerHadithId)
        if (idOrder != 0) return idOrder
        val pageOrder = left.displayPageIndex.compareTo(right.displayPageIndex)
        return if (pageOrder != 0) pageOrder else left.itemIndex.compareTo(right.itemIndex)
    }

    private fun segments(value: String): List<Long>? {
        val result = value.split('.').map(String::toLongOrNull)
        if (result.any { it == null }) return null
        return result.filterNotNull()
    }

    private fun compareSegments(left: List<Long>, right: List<Long>): Int {
        for (index in 0 until maxOf(left.size, right.size)) {
            val result = left.getOrElse(index) { 0L }.compareTo(right.getOrElse(index) { 0L })
            if (result != 0) return result
        }
        return left.size.compareTo(right.size)
    }
}

fun ReadingPosition.toWireMap(): Map<String, Any?> = buildMap {
    put("schemaVersion", schemaVersion)
    put("anchor", mapOf(
        "provider" to anchor.provider,
        "collectionSlug" to anchor.collectionSlug,
        "providerHadithId" to anchor.providerHadithId,
    ))
    put("contentVersion", contentVersion)
    put("volumeId", volumeId)
    chapterId?.let { put("chapterId", it) }
    put("pageKey", pageKey)
    put("displayPageIndex", displayPageIndex)
    put("rawPageOffset", rawPageOffset)
    put("normalizedOffset", normalizedOffset)
    put("layoutSignature", layoutSignature)
    put("updatedAt", updatedAt)
}
