package com.hadithly.app.core.data

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import java.security.MessageDigest

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
private val libraryWireJson = Json { encodeDefaults = true; explicitNulls = false }

fun SyncFrame.toConvexArgument(): Any? = libraryArgument(libraryWireJson.encodeToJsonElement(this))
fun SyncAcknowledgement.toConvexArgument(): Any? = libraryArgument(libraryWireJson.encodeToJsonElement(this))
fun SyncPending.toConvexArgument(): Any? = libraryArgument(libraryWireJson.encodeToJsonElement(this))

fun SyncBatch.intentDigest(): String {
    fun encode(value: JsonElement): String = when (value) {
        JsonNull -> "z"
        is JsonObject -> "o${value.size}:" + value.keys.sorted().joinToString("") { key -> encode(JsonPrimitive(key)) + encode(value.getValue(key)) }
        is JsonArray -> "a${value.size}:" + value.joinToString("") { encode(it) }
        is JsonPrimitive -> when {
            value.isString -> "s${value.content.toByteArray(Charsets.UTF_8).size}:" + value.content
            value.booleanOrNull != null -> if (value.boolean) "t" else "f"
            else -> {
                val number = value.doubleOrNull ?: throw LibrarySyncFailure.InvalidReceipt
                if (!number.isFinite()) throw LibrarySyncFailure.InvalidReceipt
                "n" + (if (number == 0.0) 0L else number.toRawBits()).toULong().toString(16).padStart(16, '0')
            }
        }
    }
    val canonical = "library-intent-v1:" + encode(libraryWireJson.encodeToJsonElement(this))
    return MessageDigest.getInstance("SHA-256").digest(canonical.toByteArray(Charsets.UTF_8)).joinToString("") { "%02x".format(it.toInt() and 255) }
}

private fun libraryArgument(value: JsonElement): Any? = when (value) {
    JsonNull -> null
    is JsonObject -> value.mapValues { libraryArgument(it.value) }
    is JsonArray -> value.map(::libraryArgument)
    is JsonPrimitive -> when {
        value.isString -> value.content
        value.booleanOrNull != null -> value.boolean
        value.doubleOrNull != null -> value.double
        else -> throw LibrarySyncFailure.InvalidReceipt
    }
}

/** Only provider fields are removed; notes containing these words remain intact. */
fun JsonElement.withoutProviderPassages(): JsonElement = when (this) {
    is JsonObject -> JsonObject(filterKeys { it !in setOf("arabicText", "englishText", "capability") }.mapValues { it.value.withoutProviderPassages() })
    is JsonArray -> JsonArray(map { it.withoutProviderPassages() })
    else -> this
}

fun JsonElement.containsExportKey(keys: Set<String>): Boolean = when (this) {
    is JsonObject -> this.keys.any { it in keys } || values.any { it.containsExportKey(keys) }
    is JsonArray -> any { it.containsExportKey(keys) }
    else -> false
}
