package com.hadithly.app.core.data

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.JsonClassDiscriminator

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
@Serializable
@JsonClassDiscriminator("kind")
sealed interface FirstReadingResult {
    val locale: String
    val daily: FirstReadingDailySummary?

    @Serializable
    @SerialName("ready")
    data class Ready(
        override val locale: String,
        val origin: FirstReadingOrigin,
        val reading: FirstReadingDocument,
        val validUntil: Double?,
        override val daily: FirstReadingDailySummary?,
    ) : FirstReadingResult {
        init {
            require(validUntil == null || validUntil.isFinite() && validUntil >= 0)
            require(reading.text.language == locale && reading.text.text.isNotBlank())
            require(origin != FirstReadingOrigin.DAILY || (daily?.canonicalId == reading.canonicalId && daily.hasExactText))
            require(reading.text.kind != FirstReadingTextKind.ORIGINAL || (locale == "ar" && !reading.text.isAI && reading.text.text == reading.arabicText))
            require(reading.provider == "sunnah_now" && Collections.all.any { it.first == reading.collectionSlug })
            require(reading.canonicalId == "${reading.provider}:${reading.collectionSlug}:${reading.providerHadithId}")
        }
    }

    @Serializable
    @SerialName("unavailable")
    data class Unavailable(
        override val locale: String,
        val reason: String,
        override val daily: FirstReadingDailySummary?,
    ) : FirstReadingResult
}

@Serializable
enum class FirstReadingOrigin { @SerialName("daily") DAILY, @SerialName("starter") STARTER }

@Serializable
enum class FirstReadingTextKind { @SerialName("original") ORIGINAL, @SerialName("translation") TRANSLATION }

@Serializable
data class FirstReadingText(val kind: FirstReadingTextKind, val text: String, val language: String, val sourceLabel: String, val sourceUrl: String?, val isAI: Boolean, val credits: List<FirstReadingCredit>)

@Serializable
data class FirstReadingDocument(
    val canonicalId: String, val provider: String, val collectionSlug: String, val providerHadithId: String,
    val collectionName: String, val volumeId: String?, val referenceDisplay: String, val referenceUrl: String?,
    val authenticity: AuthenticityClaim, val arabicText: String, val text: FirstReadingText,
)

@Serializable
data class FirstReadingDailySummary(val canonicalId: String, val referenceDisplay: String, val hasExactText: Boolean)

@Serializable
data class FirstReadingCredit(val scope: String, val attribution: String, val licenseName: String, val url: String?)
