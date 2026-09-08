package com.hadithly.app

import com.hadithly.app.core.data.GuestReadingProgressDraft
import com.hadithly.app.core.data.GuestMergePlanner
import com.hadithly.app.core.data.ReadingLayout
import com.hadithly.app.core.data.ReadingPosition
import com.hadithly.app.core.data.ReadingPositionAnchor
import com.hadithly.app.core.data.ReadingPositionAnchorLocation
import com.hadithly.app.core.data.ReadingPositionPage
import com.hadithly.app.core.data.ReadingPositionResolver
import com.hadithly.app.core.data.ReadingPositionTopology
import com.hadithly.app.core.data.ReadingWidthClass
import com.hadithly.app.core.data.toWireMap
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Test

class ReadingPositionTest {
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = true }

    private fun position(
        contentVersion: String = "cv1:content-a",
        layoutSignature: String = "ls1:layout-a",
        volumeId: String = "1",
        updatedAt: Double = 2_000.0,
    ) = ReadingPosition(
        anchor = ReadingPositionAnchor("sunnah_now", "bukhari", "50"),
        contentVersion = contentVersion,
        volumeId = volumeId,
        chapterId = "10",
        pageKey = "pg1:page-a",
        displayPageIndex = 2.0,
        rawPageOffset = 144.5,
        normalizedOffset = 0.375,
        layoutSignature = layoutSignature,
        updatedAt = updatedAt,
    )

    @Test
    fun `wire round trip uses Double numbers`() {
        val encoded = json.encodeToString(ReadingPosition.serializer(), position())
        val objectValue = json.parseToJsonElement(encoded).jsonObject
        assertEquals("1.0", objectValue.getValue("schemaVersion").jsonPrimitive.content)
        assertEquals("2.0", objectValue.getValue("displayPageIndex").jsonPrimitive.content)
        assertEquals(position(), json.decodeFromString<ReadingPosition>(encoded))
        assertEquals(1.0, position().toWireMap()["schemaVersion"])
        assertEquals(2.0, position().toWireMap()["displayPageIndex"])
    }

    @Test(expected = IllegalArgumentException::class)
    fun `decoder rejects an unsupported version`() {
        val encoded = json.encodeToString(ReadingPosition.serializer(), position())
            .replace("\"schemaVersion\":1.0", "\"schemaVersion\":2.0")
        json.decodeFromString<ReadingPosition>(encoded)
    }

    @Test
    fun `layout signature matches golden vector and changes with pagination`() {
        val base = ReadingLayout(
            locale = "ur-PK",
            arabicVisible = true,
            translationVisible = true,
            arabicFontId = "noto-naskh-arabic",
            arabicFontSize = 26.0,
            widthClass = ReadingWidthClass.COMPACT,
            paginationVersion = 1.0,
        )
        assertEquals("ls1:7bfbec6f3b66f12f662f28de140565cff6e4b521c0cd3f1c6deac9fb49b31b0d", base.signature)
        assertNotEquals(base.signature, base.copy(paginationVersion = 2.0).signature)
    }

    @Test
    fun `content and layout changes use the semantic anchor`() {
        val page = ReadingPositionPage(
            pageKey = "pg1:page-a",
            displayPageIndex = 4.0,
            anchors = listOf(ReadingPositionAnchorLocation(position().anchor, "1", "10")),
        )
        val changedContent = ReadingPositionResolver.resolve(
            position(), ReadingPositionTopology("cv1:content-b", "ls1:layout-a", listOf(page)),
        )
        val changedLayout = ReadingPositionResolver.resolve(
            position(), ReadingPositionTopology("cv1:content-a", "ls1:layout-b", listOf(page)),
        )
        assertEquals(ReadingPositionResolver.Kind.SEMANTIC, changedContent.kind)
        assertEquals(4.0, changedContent.displayPageIndex, 0.0)
        assertEquals(0.375, changedContent.normalizedOffset, 0.0)
        assertEquals(ReadingPositionResolver.Kind.SEMANTIC, changedLayout.kind)
    }

    @Test
    fun `missing anchor chooses nearest and resets offset`() {
        val anchors = listOf("1", "49", "80").map {
            ReadingPositionAnchorLocation(
                ReadingPositionAnchor("sunnah_now", "bukhari", it),
                if (it == "1") "1" else "2",
                null,
            )
        }
        val resolved = ReadingPositionResolver.resolve(
            position(volumeId = "2"),
            ReadingPositionTopology(
                "changed", "changed",
                listOf(ReadingPositionPage("pg1:new", 3.0, anchors)),
            ),
        )
        assertEquals(ReadingPositionResolver.Kind.NEAREST, resolved.kind)
        assertEquals("49", resolved.anchor?.providerHadithId)
        assertEquals(0.0, resolved.normalizedOffset, 0.0)
    }

    @Test
    fun `legacy guest progress migrates at offset zero`() {
        val legacy = GuestReadingProgressDraft(
            collectionSlug = "bukhari",
            collectionName = "Bukhari",
            hadithId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
            volumeId = "2",
            hadithNumber = "57",
            updatedAt = 5_000.0,
        )
        val migrated = legacy.readingPosition
        assertEquals("57", migrated?.anchor?.providerHadithId)
        assertEquals("2", migrated?.volumeId)
        assertEquals(0.0, migrated?.rawPageOffset ?: -1.0, 0.0)
        assertEquals(5_000.0, migrated?.updatedAt ?: -1.0, 0.0)
        assertEquals(
            "0",
            ReadingPosition.legacy("muslim", "0", "1", 5_000.0)?.anchor?.providerHadithId,
        )
    }

    @Test
    fun `guest merge carries the complete newest V1 position`() {
        val older = position(updatedAt = 1_000.0)
        val newer = position(contentVersion = "cv1:content-b", updatedAt = 2_000.0)
        val payload = GuestMergePlanner.makePayload(
            progress = listOf(
                GuestReadingProgressDraft(
                    collectionSlug = "bukhari",
                    collectionName = "Bukhari",
                    hadithId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    updatedAt = 1_000.0,
                    position = older,
                ),
                GuestReadingProgressDraft(
                    collectionSlug = "bukhari",
                    collectionName = "Bukhari",
                    hadithId = "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
                    updatedAt = 2_000.0,
                    position = newer,
                ),
            ),
        )
        assertEquals(listOf(newer), payload.readingProgress.mapNotNull { it.readingPosition })
    }
}
