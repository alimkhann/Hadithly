package com.hadithly.app

import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.theme.ReaderPalettes
import com.hadithly.app.features.reader.ReaderChapterBoundaries
import com.hadithly.app.features.reader.ReaderGrade
import com.hadithly.app.features.reader.ReaderViewModel
import com.hadithly.app.features.reader.customActionsFor
import com.hadithly.app.features.reader.gradeDotColor
import com.hadithly.app.features.reader.hadithMenuActions
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * R6A slice A (quiet page): grade-dot mapping across all four reader themes,
 * the corner-range rule, the volume-cache gate, short names, volume-title
 * parsing, chapter Arabic lookup, and the ICU plural resources.
 */
class ReaderR6ATest {

    // Grade mapping

    @Test
    fun `grade mapping is case-insensitive and trims`() {
        assertEquals(ReaderGrade.SAHIH, ReaderGrade.from("sahih"))
        assertEquals(ReaderGrade.SAHIH, ReaderGrade.from("Sahih"))
        assertEquals(ReaderGrade.SAHIH, ReaderGrade.from(" SAHIH "))
        assertEquals(ReaderGrade.HASAN, ReaderGrade.from("hasan"))
        assertEquals(ReaderGrade.HASAN, ReaderGrade.from("Hasan"))
        assertEquals(ReaderGrade.DAIF, ReaderGrade.from("daif"))
        assertEquals(ReaderGrade.DAIF, ReaderGrade.from("dhaif"))
    }

    @Test
    fun `unknown and absent grades map to other`() {
        assertEquals(ReaderGrade.OTHER, ReaderGrade.from(null))
        assertEquals(ReaderGrade.OTHER, ReaderGrade.from(""))
        assertEquals(ReaderGrade.OTHER, ReaderGrade.from("  "))
        assertEquals(ReaderGrade.OTHER, ReaderGrade.from("sahih-collection"))
        assertEquals(ReaderGrade.OTHER, ReaderGrade.from("mawdou"))
    }

    @Test
    fun `grade dots resolve from the palette in every reader theme`() {
        val palettes = listOf(
            ReaderPalettes.light,
            ReaderPalettes.paper,
            ReaderPalettes.dark,
            ReaderPalettes.resolved(
                com.hadithly.app.core.preferences.ReaderTheme.SYSTEM,
                systemDark = true,
            ),
            ReaderPalettes.resolved(
                com.hadithly.app.core.preferences.ReaderTheme.SYSTEM,
                systemDark = false,
            ),
        )
        for (palette in palettes) {
            assertEquals(palette.accent, gradeDotColor(ReaderGrade.SAHIH, palette))
            assertEquals(palette.bookmark, gradeDotColor(ReaderGrade.HASAN, palette))
            assertEquals(palette.destructive, gradeDotColor(ReaderGrade.DAIF, palette))
            assertEquals(palette.textSecondary, gradeDotColor(ReaderGrade.OTHER, palette))
        }
    }

    // Corner range rule

    private fun outline() = listOf(
        OutlineVolume(volumeId = "1", title = "Volume 1", hadithCount = 58.0),
        OutlineVolume(volumeId = "2", title = "Volume 2", hadithCount = 44.0),
    )

    @Test
    fun `range accumulates across volumes from outline counts`() {
        assertEquals(1 to 58, ReaderViewModel.volumeHadithRange(outline(), "1"))
        assertEquals(59 to 102, ReaderViewModel.volumeHadithRange(outline(), "2"))
    }

    @Test
    fun `range is null when not computable`() {
        assertNull(ReaderViewModel.volumeHadithRange(emptyList(), "1"))
        assertNull(ReaderViewModel.volumeHadithRange(outline(), "9"))
        assertNull(
            ReaderViewModel.volumeHadithRange(
                listOf(OutlineVolume(volumeId = "1", title = "Volume 1", hadithCount = 0.0)),
                "1",
            ),
        )
        assertNull(
            ReaderViewModel.volumeHadithRange(
                outline() + OutlineVolume(volumeId = "3", title = "Volume 3", hadithCount = -2.0),
                "3",
            ),
        )
    }

    @Test
    fun `fully cached gate needs every page loaded`() {
        assertFalse(ReaderViewModel.isVolumeFullyCached(emptyList()))
        assertFalse(
            ReaderViewModel.isVolumeFullyCached(
                listOf(ReaderPageResult(items = emptyList(), page = 1.0, hasMore = true)),
            ),
        )
        assertFalse(
            ReaderViewModel.isVolumeFullyCached(
                listOf(
                    ReaderPageResult(items = emptyList(), page = 1.0),
                    ReaderPageResult(items = emptyList(), page = 2.0, hasMore = true),
                ),
            ),
        )
        // Skipped-by-jump placeholders (page == 0) are not a full cache.
        assertFalse(
            ReaderViewModel.isVolumeFullyCached(
                listOf(
                    ReaderPageResult(items = emptyList(), page = 0.0),
                    ReaderPageResult(items = emptyList(), page = 3.0),
                ),
            ),
        )
        assertTrue(
            ReaderViewModel.isVolumeFullyCached(
                listOf(
                    ReaderPageResult(items = emptyList(), page = 1.0),
                    ReaderPageResult(items = emptyList(), page = 2.0),
                ),
            ),
        )
    }

    // Short names and volume titles

    @Test
    fun `short names cover every collection slug`() {
        val cases = mapOf(
            "bukhari" to "Bukhari",
            "muslim" to "Muslim",
            "sunan-nasai" to "Nasa'i",
            "abu-dawood" to "Abu Dawood",
            "tirmidhi" to "Tirmidhi",
            "ibn-majah" to "Ibn Majah",
            "mishkat-al-masabih" to "Mishkat",
        )
        for ((slug, short) in cases) {
            assertEquals(short, ReaderViewModel.shortCollectionName(slug, "Full Name"))
        }
        assertEquals("Full Name", ReaderViewModel.shortCollectionName("unknown", "Full Name"))
    }

    @Test
    fun `volume title number parses only the Volume N shape`() {
        assertEquals(2, ReaderViewModel.volumeTitleNumber("Volume 2"))
        assertEquals(10, ReaderViewModel.volumeTitleNumber("  Volume 10  "))
        assertNull(ReaderViewModel.volumeTitleNumber("Volume"))
        assertNull(ReaderViewModel.volumeTitleNumber("Kitab al-Iman"))
        assertNull(ReaderViewModel.volumeTitleNumber("Volume Two"))
        assertNull(ReaderViewModel.volumeTitleNumber("My Volume 2"))
    }

    // Chapter Arabic lookup

    @Test
    fun `arabic title returns only when present and different`() {
        val chapters = listOf(
            OutlineChapter(title = "Revelation", arabicTitle = "الوحي", hadithCount = 7.0, firstProviderHadithId = "1"),
            OutlineChapter(title = "Belief", hadithCount = 51.0, firstProviderHadithId = "8"),
            OutlineChapter(title = "Same", arabicTitle = "Same", hadithCount = 1.0, firstProviderHadithId = "9"),
        )
        assertEquals("الوحي", ReaderChapterBoundaries.arabicTitleFor(chapters, "Revelation"))
        assertNull(ReaderChapterBoundaries.arabicTitleFor(chapters, "Belief"))
        assertNull(ReaderChapterBoundaries.arabicTitleFor(chapters, "Same"))
        assertNull(ReaderChapterBoundaries.arabicTitleFor(chapters, "Unknown"))
        assertNull(ReaderChapterBoundaries.arabicTitleFor(emptyList(), "Revelation"))
    }

    // Plural resources

    private fun pluralQuantities(dir: String, pluralName: String): Set<String> {
        val file = File("src/main/res/$dir/strings.xml")
        assertTrue("missing ${file.path}", file.exists())
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val plurals = doc.getElementsByTagName("plurals")
        for (i in 0 until plurals.length) {
            val node = plurals.item(i)
            if (node.attributes.getNamedItem("name").nodeValue != pluralName) continue
            val quantities = mutableSetOf<String>()
            val items = node.childNodes
            for (j in 0 until items.length) {
                items.item(j).attributes?.getNamedItem("quantity")?.nodeValue?.let {
                    quantities.add(it)
                }
            }
            return quantities
        }
        error("missing plural $pluralName in $dir")
    }

    private fun stringValue(dir: String, name: String): String {
        val file = File("src/main/res/$dir/strings.xml")
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        for (i in 0 until nodes.length) {
            val node = nodes.item(i)
            if (node.attributes.getNamedItem("name").nodeValue == name) return node.textContent
        }
        error("missing string $name in $dir")
    }

    @Test
    fun `hadith count plurals cover en, ar, and ur`() {
        assertEquals(setOf("one", "other"), pluralQuantities("values", "reader_hadith_count"))
        assertEquals(
            setOf("zero", "one", "two", "few", "many", "other"),
            pluralQuantities("values-ar", "reader_hadith_count"),
        )
        assertEquals(setOf("one", "other"), pluralQuantities("values-ur", "reader_hadith_count"))
    }

    @Test
    fun `volume title string is localized and formatted`() {
        for (dir in listOf("values", "values-ar", "values-ur")) {
            val template = stringValue(dir, "reader_volume_title")
            assertTrue("$dir template is blank", template.isNotBlank())
            assertTrue("$dir template needs a number slot: $template", template.contains("%1\$d"))
        }
    }

    // Menu actions and TalkBack equivalence

    private fun menuActions(
        isBookmarked: Boolean = false,
        isFavorite: Boolean = false,
        hasNote: Boolean = false,
        loadedTranslation: ReaderTranslation? = null,
        calls: MutableList<String> = mutableListOf(),
    ) = hadithMenuActions(
        isBookmarked = isBookmarked,
        isFavorite = isFavorite,
        hasNote = hasNote,
        loadedTranslation = loadedTranslation,
        onToggleBookmark = { calls.add("bookmark") },
        onToggleFavorite = { calls.add("favorite") },
        onEditNote = { calls.add("note") },
        onCopy = { calls.add("copy") },
        onShare = { calls.add("share") },
        onReport = { calls.add("report") },
        onSuggest = { calls.add("suggest") },
    )

    private fun loadedTranslation() = ReaderTranslation(
        translationId = "t1",
        translation = "Kazakh rendering",
        source = "gemini_ai",
        sourceLabel = "AI",
    )

    @Test
    fun `menu carries all seven actions with stable tags`() {
        val actions = menuActions(loadedTranslation = loadedTranslation())
        assertEquals(
            listOf(
                "reader.bookmark",
                "reader.favorite",
                "reader.note",
                "reader.copy",
                "reader.share",
                "reader.reportTranslation",
                "reader.suggestTranslation",
            ),
            actions.map { it.testTag },
        )
    }

    @Test
    fun `menu labels follow saved state`() {
        val actions = menuActions(
            isBookmarked = true,
            isFavorite = true,
            hasNote = true,
            loadedTranslation = loadedTranslation(),
        )
        assertEquals(
            listOf(
                "Remove bookmark",
                "Remove from favorites",
                "Edit note",
                "Copy",
                "Share",
                "Report translation",
                "Suggest translation",
            ),
            actions.map { it.label },
        )
        val fresh = menuActions()
        assertEquals("Bookmark", fresh[0].label)
        assertEquals("Add to favorites", fresh[1].label)
        assertEquals("Add note", fresh[2].label)
    }

    @Test
    fun `report is gated on a loaded translation`() {
        val without = menuActions(loadedTranslation = null)
        assertEquals(6, without.size)
        assertTrue(without.none { it.testTag == "reader.reportTranslation" })
        assertTrue(without.any { it.testTag == "reader.suggestTranslation" })
    }

    @Test
    fun `menu invocations delegate to the right callbacks`() {
        val calls = mutableListOf<String>()
        val actions = menuActions(loadedTranslation = loadedTranslation(), calls = calls)
        actions.forEach { it.onInvoke() }
        assertEquals(
            listOf("bookmark", "favorite", "note", "copy", "share", "report", "suggest"),
            calls,
        )
    }

    @Test
    fun `talkback actions mirror the menu label for label`() {
        val actions = menuActions(loadedTranslation = loadedTranslation())
        val custom = customActionsFor(actions)
        assertEquals(actions.map { it.label }, custom.map { it.label })
    }

    @Test
    fun `talkback invocation delegates and returns true`() {
        val calls = mutableListOf<String>()
        val actions = menuActions(calls = calls)
        val custom = customActionsFor(actions)
        for (action in custom) {
            assertTrue(action.action())
        }
        assertEquals(listOf("bookmark", "favorite", "note", "copy", "share", "suggest"), calls)
    }
}
