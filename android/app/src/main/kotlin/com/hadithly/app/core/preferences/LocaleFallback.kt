package com.hadithly.app.core.preferences

/**
 * BCP 47 fallback: exact locale, base language, then English (docs/PLAN.md).
 * Mirrors the iOS LocaleFallback port and backend lib/preferences.ts.
 */
object LocaleFallback {

    private val rtlBaseLanguages: Set<String> = setOf(
        "ar", "fa", "he", "ps", "sd", "ug", "ur", "yi", "ckb", "mzn", "sdh",
    )

    /** Canonicalizes a BCP 47 tag: "EN_us" → "en-US", "pt-br" → "pt-BR",
     * "ES-419" → "es-419", "zh-HANS" → "zh-Hans". Null when malformed. */
    fun canonicalizeLocaleTag(tag: String): String? {
        val trimmed = tag.trim()
        if (trimmed.isEmpty() || trimmed.length > 35) return null
        val parts = trimmed.split('-', '_')
        if (parts.size > 8) return null
        val language = parts.first()
        if (!Regex("^[A-Za-z]{2,3}$").matches(language)) return null
        val canonical = mutableListOf(language.lowercase())
        for (part in parts.drop(1)) {
            when {
                part.length == 4 && Regex("^[A-Za-z]{4}$").matches(part) ->
                    canonical.add(part.lowercase().replaceFirstChar { it.uppercaseChar() })
                part.length == 2 && Regex("^[A-Za-z]{2}$").matches(part) ->
                    canonical.add(part.uppercase())
                Regex("^[A-Za-z0-9]{2,8}$").matches(part) ->
                    canonical.add(part.lowercase())
                else -> return null
            }
        }
        val joined = canonical.joinToString("-")
        return if (Regex("^[A-Za-z]{2,3}(-[A-Za-z0-9]{2,8})*$").matches(joined)) joined else null
    }

    /** Fallback chain: exact locale, base language, then English. */
    fun fallbackChain(tag: String): List<String> {
        val canonical = canonicalizeLocaleTag(tag) ?: return listOf("en")
        val base = canonical.substringBefore('-')
        val chain = if (canonical == base) listOf(canonical) else listOf(canonical, base)
        return if ("en" in chain) chain else chain + "en"
    }

    /** First entry of the chain present in [supported], or null. */
    fun resolve(tag: String, supported: Set<String>): String? =
        fallbackChain(tag).firstOrNull { it in supported }

    fun baseLanguage(tag: String): String {
        val canonical = canonicalizeLocaleTag(tag) ?: tag
        return canonical.substringBefore('-').substringBefore('_').lowercase()
    }

    /** True for Arabic, Urdu, Persian, and other RTL-script base languages.
     * Covers pseudolocales too: "ar-XB" is RTL, "en-XA" is not. */
    fun isRTL(tag: String): Boolean = baseLanguage(tag) in rtlBaseLanguages
}
