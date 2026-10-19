package com.hadithly.app.core.data

import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*

@OptIn(kotlinx.serialization.ExperimentalSerializationApi::class)
private val libraryWireJson = Json { encodeDefaults = true; explicitNulls = false }

fun SyncFrame.toConvexArgument(): Any? = libraryArgument(libraryWireJson.encodeToJsonElement(this))
fun SyncAcknowledgement.toConvexArgument(): Any? = libraryArgument(libraryWireJson.encodeToJsonElement(this))

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
