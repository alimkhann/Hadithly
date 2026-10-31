package com.hadithly.app.features.reader

/**
 * R5 copy/share text helpers. Copy carries the visible text plus a source
 * line; share carries only the canonical URL (see CanonicalHadithUrl).
 */
object ReaderShare {

    /**
     * Formats clipboard text for one hadith: the visible Arabic when shown,
     * the visible translation when shown, then a source line
     * `— {collectionName} · Hadith {id} · {sourceName}` with an ` · AI
     * translation` suffix only when the copied translation is AI-generated.
     * The canonical URL is never included in copied text. Interface labels come from the selected UI locale.
     */
    fun formatCopyText(
        arabicText: String?,
        translationText: String?,
        translationIsAi: Boolean,
        collectionName: String,
        providerHadithId: String,
        sourceName: String,
        hadithLabel: String,
        aiLabel: String,
    ): String {
        val body = listOfNotNull(
            arabicText?.takeIf { it.isNotBlank() },
            translationText?.takeIf { it.isNotBlank() },
        ).joinToString("\n\n")
        val sourceLine = CopyAttribution.line(collectionName, providerHadithId, sourceName, translationText != null && translationIsAi, hadithLabel, aiLabel)
        return if (body.isEmpty()) sourceLine else "$body\n\n$sourceLine"
    }
}

internal object CopyAttribution {
    fun line(collection: String, id: String, source: String, isAi: Boolean, hadithLabel: String, aiLabel: String): String =
        "— $collection · $hadithLabel $id · $source" + if (isAi) " · $aiLabel" else ""
}
