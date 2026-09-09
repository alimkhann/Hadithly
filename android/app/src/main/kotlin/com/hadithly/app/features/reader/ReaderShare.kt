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
     * The canonical URL is never included in copied text.
     */
    fun formatCopyText(
        arabicText: String?,
        translationText: String?,
        translationIsAi: Boolean,
        collectionName: String,
        providerHadithId: String,
        sourceName: String,
    ): String {
        val body = listOfNotNull(
            arabicText?.takeIf { it.isNotBlank() },
            translationText?.takeIf { it.isNotBlank() },
        ).joinToString("\n\n")
        val aiSuffix = if (translationText != null && translationIsAi) " · AI translation" else ""
        val sourceLine = "— $collectionName · Hadith $providerHadithId · $sourceName$aiSuffix"
        return if (body.isEmpty()) sourceLine else "$body\n\n$sourceLine"
    }
}
