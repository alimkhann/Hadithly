package com.hadithly.app

import com.hadithly.app.core.data.OutlineChapter
import com.hadithly.app.core.data.OutlineVolume
import com.hadithly.app.core.data.ReaderPageResult
import com.hadithly.app.core.data.ReaderTranslation
import com.hadithly.app.core.theme.ReaderPalettes
import com.hadithly.app.features.reader.ReaderChapterBoundaries
import com.hadithly.app.features.reader.ReaderGrade
import com.hadithly.app.features.reader.ReaderPagePills
import com.hadithly.app.features.reader.ReaderViewModel
import com.hadithly.app.features.reader.SavedMiniMarker
import com.hadithly.app.features.reader.customActionsFor
import com.hadithly.app.features.reader.gradeDotColor
import com.hadithly.app.features.reader.hadithHeaderText
import com.hadithly.app.features.reader.hadithMenuActions
import com.hadithly.app.features.reader.savedMiniMarkers
import com.hadithly.app.features.reader.shouldShowNarrator
import com.hadithly.app.features.reader.visibleArabicChapterTitle
import com.hadithly.app.features.reader.volumeCornerText
import com.hadithly.app.core.preferences.ReaderPageTurn
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

    // R6A owner fixes: corner text, narrator gating, saved mini markers

    private fun cachedPages(): List<ReaderPageResult> = listOf(
        ReaderPageResult(items = emptyList(), page = 1.0),
        ReaderPageResult(items = emptyList(), page = 2.0),
    )

    @Test
    fun `corner text shows the whole volume range only when fully cached`() {
        // Volume 2 of the fixture outline spans 59–102.
        assertEquals(
            "Volume 2: 59–102",
            volumeCornerText("Volume 2", outline(), "2", cachedPages()),
        )
        assertEquals(
            "Volume 1: 1–58",
            volumeCornerText("Volume 1", outline(), "1", cachedPages()),
        )
    }

    @Test
    fun `corner text is title-only until computable`() {
        // Still loading: hasMore outstanding.
        assertEquals(
            "Volume 2",
            volumeCornerText(
                "Volume 2",
                outline(),
                "2",
                listOf(ReaderPageResult(items = emptyList(), page = 1.0, hasMore = true)),
            ),
        )
        // No pages yet.
        assertEquals("Volume 2", volumeCornerText("Volume 2", outline(), "2", emptyList()))
        // Unknown volume.
        assertEquals("Volume 9", volumeCornerText("Volume 9", outline(), "9", cachedPages()))
        // No volume selected.
        assertEquals("Volume 2", volumeCornerText("Volume 2", outline(), null, cachedPages()))
        // Uncomputable counts.
        assertEquals(
            "Volume 1",
            volumeCornerText(
                "Volume 1",
                listOf(OutlineVolume(volumeId = "1", title = "Volume 1", hadithCount = 0.0)),
                "1",
                cachedPages(),
            ),
        )
    }

    @Test
    fun `narrator shows in every valid visibility mode`() {
        assertTrue(shouldShowNarrator("Narrated Abu Huraira:", arabicVisible = true, translationVisible = true))
        assertTrue(shouldShowNarrator("Narrated Abu Huraira:", arabicVisible = true, translationVisible = false))
        assertTrue(shouldShowNarrator("Narrated Abu Huraira:", arabicVisible = false, translationVisible = true))
        assertFalse(shouldShowNarrator("Narrated Abu Huraira:", arabicVisible = false, translationVisible = false))
        assertFalse(shouldShowNarrator(null, arabicVisible = true, translationVisible = true))
        assertFalse(shouldShowNarrator("", arabicVisible = true, translationVisible = true))
        assertFalse(shouldShowNarrator("  ", arabicVisible = true, translationVisible = true))
    }

    @Test
    fun `two page pills use neighbor pages volume titles and absolute ends`() {
        val volumes = listOf(
            OutlineVolume(volumeId = "1", title = "Sahih al-Bukhari: Revelation", hadithCount = 1.0),
            OutlineVolume(volumeId = "2", title = "Sahih al-Bukhari: Belief", hadithCount = 3.0),
            OutlineVolume(volumeId = "3", title = "Sahih al-Bukhari: Knowledge", hadithCount = 1.0),
        )
        val first = ReaderPagePills.state(
            pageIndex = 0, hasPreviousPage = false, hasNextPage = true,
            atLoadedPage = true, volumes = volumes, selectedVolumeId = "2",
        )
        assertEquals("Sahih al-Bukhari: Revelation", first.previous?.label)
        assertEquals(ReaderPagePills.Target.VolumeLast("1"), first.previous?.target)
        assertEquals(ReaderPageTurn.PREVIOUS, first.previous?.turn)
        assertEquals("Page 2", first.next?.label)
        assertEquals(ReaderPagePills.Target.Page(1), first.next?.target)

        val last = ReaderPagePills.state(
            pageIndex = 1, hasPreviousPage = true, hasNextPage = false,
            atLoadedPage = true, volumes = volumes, selectedVolumeId = "2",
        )
        assertEquals("Page 1", last.previous?.label)
        assertEquals("Sahih al-Bukhari: Knowledge", last.next?.label)
        assertEquals(ReaderPagePills.Target.VolumeFirst("3"), last.next?.target)

        val absoluteStart = ReaderPagePills.state(
            pageIndex = 0, hasPreviousPage = false, hasNextPage = false,
            atLoadedPage = true, volumes = volumes, selectedVolumeId = "1",
        )
        assertNull(absoluteStart.previous)
        assertEquals("Sahih al-Bukhari: Belief", absoluteStart.next?.label)
    }

    @Test
    fun `header label is short name and id without brackets`() {
        assertEquals("Bukhari – 57", hadithHeaderText("bukhari", "Sahih al-Bukhari", "57"))
        assertEquals("Muslim – 4.5", hadithHeaderText("muslim", "Sahih Muslim", "4.5"))
        assertEquals("Forty Nawawi – 1", hadithHeaderText("forty-nawawi", "Forty Nawawi", "1"))
    }

    @Test
    fun `Arabic chapter name follows Arabic text visibility`() {
        assertEquals(
            "كتاب الإيمان",
            visibleArabicChapterTitle(true, "Belief", "كتاب الإيمان"),
        )
        assertNull(visibleArabicChapterTitle(false, "Belief", "كتاب الإيمان"))
        assertNull(visibleArabicChapterTitle(true, "Belief", "Belief"))
        assertNull(visibleArabicChapterTitle(true, "Belief", null))
    }

    @Test
    fun `grade display names mirror the source label`() {
        assertEquals("Sahih", ReaderGrade.SAHIH.displayName)
        assertEquals("Hasan", ReaderGrade.HASAN.displayName)
        assertEquals("Daif", ReaderGrade.DAIF.displayName)
        assertEquals("Unverified", ReaderGrade.OTHER.displayName)
    }

    @Test
    fun `saved mini markers follow bookmark and favorite only`() {
        assertEquals(listOf(SavedMiniMarker.BOOKMARK), savedMiniMarkers(true, false))
        assertEquals(listOf(SavedMiniMarker.FAVORITE), savedMiniMarkers(false, true))
        assertEquals(
            listOf(SavedMiniMarker.BOOKMARK, SavedMiniMarker.FAVORITE),
            savedMiniMarkers(true, true),
        )
        assertTrue(savedMiniMarkers(false, false).isEmpty())
        // Notes never produce a marker: no note icon exists.
    }
}
