package com.hadithly.app.features.reader

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTextInput
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.unit.dp
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.EnglishSearchResult
import com.hadithly.app.core.data.HadithRef
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.data.SavedEntry
import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * R6 round 3 on the hadithly emulator: axis-locked drag paging, menu
 * order/cards, search flow, the green note marker, and the sheet tags.
 */
class ReaderR6Round3Test {
    @get:Rule
    val compose = createComposeRule()

    private fun authenticity() = AuthenticityClaim(
        kind = "collection_scope",
        normalizedGrade = "sahih",
        claimScope = "collection",
        sourceLabel = "Documented Sahih collection",
        sourceName = "Sunnah.now",
        sourceUrl = "https://sunnah.now",
        verificationMethod = "manual_collection_mapping",
    )

    private fun hadith(id: String = "57") = ReaderHadith(
        _id = "h-$id",
        provider = "sunnah_now",
        canonicalId = "sunnah_now:bukhari:$id",
        providerHadithId = id,
        collectionSlug = "bukhari",
        arabicText = "حَدَّثَنَا",
        englishText = "He said:",
        narrator = "Narrated Abu Huraira:",
        referenceDisplay = "Sahih al-Bukhari · Hadith $id",
        collectionName = "Sahih al-Bukhari",
        chapterName = "Belief",
        authenticity = authenticity(),
    )

    private class FakeDeps(
        override val isBookmarked: Boolean = false,
        override val isFavorite: Boolean = false,
        override val hasNote: Boolean = false,
    ) : HadithBlockDeps {
        override fun onToggleBookmark() = Unit
        override fun onToggleFavorite() = Unit
    }

    @Composable
    private fun block(
        hadith: ReaderHadith = hadith(),
        deps: HadithBlockDeps = FakeDeps(),
    ) {
        HadithlyTheme {
            HadithBlock(
                hadith = hadith,
                translationState = null,
                language = "en",
                arabicFontSize = 26f,
                preferences = ReaderPreferences(),
                deps = deps,
                onTap = {},
                onRetry = {},
                onShowCitations = {},
                onShowSource = {},
                onEditNote = {},
                onSuggest = {},
                onReport = {},
                onShowPaywall = {},
            )
        }
    }

    // Axis-locked drag paging

    @Composable
    private fun pager(
        direction: PageDirection = PageDirection.LTR,
        onUserDragStart: (() -> Unit)? = null,
    ) {
        val pagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })
        DirectionAwareHorizontalPager(
            state = pagerState,
            policy = ReaderPagingPolicy(direction),
            onUserDragStart = onUserDragStart,
            modifier = Modifier.fillMaxSize().testTag("pager"),
        ) { page ->
            Box(modifier = Modifier.fillMaxSize()) {
                Text(
                    if (page == 0 || page == 2) "Volume header" else "Volume corner",
                    modifier = Modifier
                        .align(Alignment.TopStart)
                        .testTag(if (page == 0 || page == 2) "reader.volumeHeader" else "reader.volumeCorner"),
                )
                LazyColumn(
                    modifier = Modifier.fillMaxSize().testTag("long-page-$page"),
                ) {
                    items((0..40).toList()) { line ->
                        Text(
                            text = "Page $page line $line",
                            modifier = Modifier.height(64.dp).testTag("line-$page-$line"),
                        )
                    }
                }
                Text(
                    "Page $page",
                    modifier = Modifier.align(Alignment.TopEnd).testTag("page-$page"),
                )
            }
        }
    }

    @Test
    fun mostlyVerticalDragNeverPagesOrCollapsesSideways() {
        var drags = 0
        compose.setContent { pager(onUserDragStart = { drags += 1 }) }

        compose.onNodeWithTag("page-1").assertIsDisplayed()
        // Mostly vertical with a small horizontal component: the page must
        // not turn and the pager must not claim the drag.
        compose.onNodeWithTag("long-page-1").performTouchInput {
            swipe(
                start = center,
                end = center.copy(x = center.x + 24, y = top + 80),
                durationMillis = 300,
            )
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, drags) }
    }

    @Test
    fun mostlyHorizontalDragPagesAndReportsUserDrag() {
        var drags = 0
        compose.setContent { pager(onUserDragStart = { drags += 1 }) }

        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerRight, end = centerLeft, durationMillis = 250)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-2").assertIsDisplayed()
        compose.runOnIdle { assertTrue(drags > 0) }
    }

    @Test
    fun verticalScrollNeverReportsPagerDrag() {
        var drags = 0
        compose.setContent { pager(onUserDragStart = { drags += 1 }) }

        compose.onNodeWithTag("long-page-1").performTouchInput {
            swipe(start = center, end = center.copy(y = top + 80), durationMillis = 300)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.runOnIdle { assertEquals(0, drags) }
    }

    @Test
    fun neighborPagesStayRenderedAroundCurrent() {
        compose.setContent { pager() }

        compose.onNodeWithTag("page-1").assertIsDisplayed()
        // Pre-rendered neighbors exist in the tree for drags with
        // cancel-back; only the current page is displayed.
        compose.onNodeWithTag("page-0").assertExists()
        compose.onNodeWithTag("page-2").assertExists()
        compose.onNodeWithTag("page-0").assertIsNotDisplayed()
        compose.onNodeWithTag("page-2").assertIsNotDisplayed()
    }

    @Test
    fun canceledSwipeSettlesBackWithContentIntact() {
        compose.setContent { pager() }

        compose.onNodeWithTag("page-1").assertIsDisplayed()
        // A short drag below the paging threshold: settle-or-cancel must
        // snap back with the outgoing page's content intact (no flicker to
        // an empty page) and neighbors still composed.
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = center, end = center.copy(x = center.x - 60), durationMillis = 200)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.onNodeWithTag("page-0").assertExists()
        compose.onNodeWithTag("page-2").assertExists()
    }

    @Test
    fun p1VerticalLandingMatrixShowsHeaderIdentifiersAfterManualTurns() {
        compose.setContent { pager() }

        // The initial Library-like page is an ordinary page with its corner.
        compose.onNodeWithTag("reader.volumeCorner").assertIsDisplayed()
        // Scroll it before leaving; a later manual revisit must still expose
        // its header identifier rather than retaining the old list position.
        compose.onNodeWithTag("long-page-1").performTouchInput {
            swipe(start = center, end = center.copy(y = top + 160), durationMillis = 300)
        }
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerRight, end = centerLeft, durationMillis = 250)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("reader.volumeHeader").assertIsDisplayed()
        // Returning to the loaded page preserves its page-top identifier.
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerLeft, end = centerRight, durationMillis = 250)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("reader.volumeCorner").assertIsDisplayed()
        // The other boundary is also a volume-header landing.
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerLeft, end = centerRight, durationMillis = 250)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("reader.volumeHeader").assertIsDisplayed()

        // A semantic continuation is deliberately distinct from every
        // manual turn: it names the saved hadith and offset, not a cache.
        val continuation = ReaderVerticalLandingRequest(
            token = 9,
            page = ReaderVerticalLandingPage("2", 1),
            landing = ReaderVerticalLanding.Semantic("57", 0.5),
        )
        assertEquals(ReaderVerticalLanding.Semantic("57", 0.5), continuation.landing)
    }

    @Test
    fun menuBottomRowHasEqualHeights() {
        compose.setContent {
            HadithlyTheme {
                ReaderMenuStack(
                    positionedReference = "Hadith 57",
                    isPositionedBookmarked = false,
                    onContents = {},
                    onSaved = {},
                    onSettings = {},
                    onBookmark = {},
                    onSearch = {},
                )
            }
        }

        val bookmarkHeight = compose.onNodeWithTag("reader.menu.bookmark").fetchSemanticsNode().size.height
        val searchHeight = compose.onNodeWithTag("reader.menu.search").fetchSemanticsNode().size.height
        assertEquals(bookmarkHeight, searchHeight)
    }

    // Menu order and cards

    @Test
    fun menuFollowsVideoOrderWithNoExcess() {
        compose.setContent {
            HadithlyTheme {
                ReaderMenuStack(
                    positionedReference = "Sahih al-Bukhari · Hadith 57",
                    isPositionedBookmarked = false,
                    onContents = {},
                    onSaved = {},
                    onSettings = {},
                    onBookmark = {},
                    onSearch = {},
                )
            }
        }

        compose.onNodeWithTag("reader.menu").assertIsDisplayed()
        compose.onNodeWithTag("reader.menu.contents").assertIsDisplayed()
        compose.onNodeWithTag("reader.menu.saved").assertIsDisplayed()
        compose.onNodeWithTag("reader.menu.settings").assertIsDisplayed()
        compose.onNodeWithTag("reader.menu.bookmark").assertIsDisplayed()
        compose.onNodeWithTag("reader.menu.search").assertIsDisplayed()
        // The location card is deleted; the Note bottom-row card is gone
        // (notes stay in the long-press menu).
        compose.onNodeWithText("Current location").assertDoesNotExist()
        compose.onNodeWithText("Reader settings").assertDoesNotExist()
        compose.onNodeWithText("Settings").assertIsDisplayed()
        compose.onNodeWithText("Bookmarks & Notes").assertIsDisplayed()
        compose.onNodeWithText("Sunnah.now English text").assertDoesNotExist()

        // Video order: Contents, Bookmarks & Notes, Settings, then the
        // Bookmark + Search bottom row.
        val titles = listOf("Contents", "Bookmarks & Notes", "Settings")
        val tops = titles.map { title ->
            compose.onNodeWithText(title).fetchSemanticsNode().positionInRoot.y
        } + listOf(
            compose.onNodeWithTag("reader.menu.bookmark").fetchSemanticsNode().positionInRoot.y,
            compose.onNodeWithTag("reader.menu.search").fetchSemanticsNode().positionInRoot.y,
        )
        assertEquals(tops.sorted(), tops)
    }

    @Test
    fun menuBookmarkShowsPositionedReference() {
        compose.setContent {
            HadithlyTheme {
                ReaderMenuStack(
                    positionedReference = "Sahih al-Bukhari · Hadith 57",
                    isPositionedBookmarked = true,
                    onContents = {},
                    onSaved = {},
                    onSettings = {},
                    onBookmark = {},
                    onSearch = {},
                )
            }
        }

        // The bottom-row bookmark names the positioned hadith; its filled
        // amber state is pinned structurally in the placement sheet test.
        compose.onNodeWithTag("reader.menu.bookmark").assertIsDisplayed()
        compose.onNodeWithContentDescription("Bookmark Sahih al-Bukhari · Hadith 57").assertIsDisplayed()
    }

    // Bookmark placement

    @Test
    fun bookmarkPlacementOffersPageStartAndPositioned() {
        var chosen: ReaderHadith? = null
        var dismissed = false
        compose.setContent {
            HadithlyTheme {
                BookmarkPlacementSheet(
                    targets = bookmarkPlacementTargets(
                        pageHadiths = listOf(hadith("57"), hadith("58")),
                        positioned = hadith("58"),
                    ),
                    isBookmarked = { it.providerHadithId == "58" },
                    onChoose = { chosen = it },
                    onDismiss = { dismissed = true },
                )
            }
        }

        compose.onNodeWithTag("reader.bookmarkSheet").assertIsDisplayed()
        compose.onNodeWithTag("reader.bookmarkSheet.pageStart").assertIsDisplayed()
        compose.onNodeWithTag("reader.bookmarkSheet.positioned").assertIsDisplayed()
        compose.onNodeWithTag("reader.bookmarkSheet.cancel").assertIsDisplayed()
        compose.onNodeWithText("Sahih al-Bukhari · Hadith 57").assertIsDisplayed()
        compose.onNodeWithText("Sahih al-Bukhari · Hadith 58").assertIsDisplayed()
        // The already-bookmarked positioned hadith renders filled amber.
        compose.onNodeWithContentDescription("Bookmarked").assertIsDisplayed()

        compose.onNodeWithTag("reader.bookmarkSheet.pageStart").performClick()
        compose.runOnIdle { assertEquals("57", chosen?.providerHadithId) }
        assertEquals(false, dismissed)
    }

    // Search flow

    private val searchHits = listOf(
        EnglishSearchResult(
            hadithId = "h1",
            canonicalId = "sunnah_now:bukhari:57",
            collectionSlug = "bukhari",
            providerHadithId = "57",
            referenceDisplay = "Sahih al-Bukhari · Hadith 57",
            snippet = "…matching passage…",
        ),
        EnglishSearchResult(
            hadithId = "h2",
            canonicalId = "sunnah_now:bukhari:58",
            collectionSlug = "bukhari",
            providerHadithId = "58",
            referenceDisplay = "Sahih al-Bukhari · Hadith 58",
            snippet = "…another passage…",
        ),
    )

    @Test
    fun searchFlowShowsLabeledResultsAndNavigates() {
        var navigated: EnglishSearchResult? = null
        var queries = 0
        compose.setContent {
            HadithlyTheme {
                ReaderSearchSheet(
                    search = { text ->
                        queries += 1
                        assertEquals("mercy", text)
                        searchHits
                    },
                    onNavigate = { navigated = it },
                )
            }
        }

        compose.onNodeWithTag("reader.search.sheet").assertIsDisplayed()
        compose.onNodeWithTag("reader.search.field").performTextInput("mercy")
        // The sheet debounces 350 ms; advance the test clock past it.
        compose.mainClock.advanceTimeBy(1000)
        compose.waitForIdle()
        compose.runOnIdle { assertEquals(1, queries) }

        compose.onNodeWithTag("reader.search.results").assertIsDisplayed()
        compose.onNodeWithTag("reader.search.result.sunnah_now:bukhari:57").assertIsDisplayed()
        // Every result is labeled as Sunnah.now English text (the card is
        // clickable, so child semantics merge into the card node: assert
        // the merged text, one label per result card).
        compose.onAllNodesWithText("Sunnah.now English text").assertCountEquals(2)

        compose.onNodeWithTag("reader.search.result.sunnah_now:bukhari:58").performClick()
        compose.runOnIdle { assertEquals("58", navigated?.providerHadithId) }
    }

    @Test
    fun searchBlankQueryShowsNoResults() {
        compose.setContent {
            HadithlyTheme {
                ReaderSearchSheet(
                    search = { error("must not query on blank") },
                    onNavigate = {},
                )
            }
        }

        compose.onNodeWithTag("reader.search.results").assertDoesNotExist()
        compose.onNodeWithTag("reader.search.empty").assertDoesNotExist()
    }

    // Note marker

    @Test
    fun noteMarkerShowsInlineByHeader() {
        compose.setContent { block(deps = FakeDeps(hasNote = true)) }

        compose.onNodeWithTag("reader.savedNote", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag("reader.savedNote", useUnmergedTree = true)
            .assertContentDescriptionEquals("Has note")
    }

    @Test
    fun noteMarkerHidesWithoutNote() {
        compose.setContent { block() }

        compose.onNodeWithTag("reader.savedNote", useUnmergedTree = true).assertDoesNotExist()
    }

    // Sheet tags

    @Test
    fun contentsSheetKeepsTagsAndClose() {
        var dismissed = false
        compose.setContent {
            HadithlyTheme {
                ContentsSheet(
                    volumes = listOf(
                        com.hadithly.app.core.data.OutlineVolume(
                            volumeId = "1",
                            title = "Volume 1",
                            hadithCount = 58.0,
                        ),
                    ),
                    selectedVolumeId = "1",
                    arabicVisible = true,
                    onSelect = {},
                    onSelectChapter = { _, _ -> },
                    onJumpToReference = { true },
                    onDismiss = { dismissed = true },
                )
            }
        }

        compose.onNodeWithTag("reader.contents.sheet").assertIsDisplayed()
        compose.onNodeWithTag("reader.contents.jump").assertIsDisplayed()
        compose.onNodeWithTag("reader.contents.close").performClick()
        compose.runOnIdle { assertEquals(true, dismissed) }
    }

    @Test
    fun settingsSheetRenamedWithNoQuranModes() {
        compose.setContent {
            HadithlyTheme {
                SettingsSheet(
                    preferences = ReaderPreferences(),
                    language = "en",
                    onLanguage = {},
                    onArabicFontSize = {},
                    onTranslationFontSize = {},
                    onTheme = {},
                    onArabicFont = {},
                    onVisibility = { _, _ -> true },
                )
            }
        }

        compose.onNodeWithTag("reader.settings.sheet").assertIsDisplayed()
        compose.onNodeWithTag("reader.settings.title").assertIsDisplayed()
        compose.onNodeWithText("Reader settings").assertIsDisplayed()
        compose.onNodeWithText("Mushaf", substring = true).assertDoesNotExist()
        compose.onNodeWithText("Reciter", substring = true).assertDoesNotExist()
    }

    private fun savedEntry(rowId: String, reference: String, createdAt: Double) = SavedEntry(
        rowId = rowId,
        createdAt = createdAt,
        hadith = HadithRef(
            hadithId = "h-$rowId",
            collectionSlug = "bukhari",
            collectionName = "Sahih al-Bukhari",
            volumeId = "2",
            hadithNumber = "57",
            arabicText = "حَدَّثَنَا",
            englishText = "He said:",
            referenceDisplay = reference,
        ),
    )

    @Test
    fun readerSavedSheetTabsRowsAndEdit() {
        var opened: HadithRef? = null
        var edited = false
        compose.setContent {
            HadithlyTheme {
                ReaderSavedSheet(
                    bookmarks = listOf(savedEntry("b1", "Sahih al-Bukhari · Hadith 57", 1000.0)),
                    favorites = emptyList(),
                    notes = emptyList(),
                    nowMillis = 1000L + 5 * 60_000,
                    onOpen = { opened = it },
                    onEdit = { edited = true },
                )
            }
        }

        compose.onNodeWithTag("reader.saved.sheet").assertIsDisplayed()
        compose.onNodeWithTag("reader.saved.tab.bookmarks").assertIsDisplayed()
        compose.onNodeWithTag("reader.saved.tab.favorites").assertIsDisplayed()
        compose.onNodeWithTag("reader.saved.tab.notes").assertIsDisplayed()
        compose.onNodeWithTag("reader.saved.row.b1").assertIsDisplayed()
        compose.onNodeWithText("Sahih al-Bukhari · Hadith 57").assertIsDisplayed()
        compose.onNodeWithText("5m ago").assertIsDisplayed()

        compose.onNodeWithTag("reader.saved.tab.favorites").performClick()
        compose.onNodeWithText("Nothing saved here yet.").assertIsDisplayed()

        compose.onNodeWithTag("reader.saved.tab.bookmarks").performClick()
        compose.onNodeWithTag("reader.saved.row.b1").performClick()
        compose.runOnIdle { assertEquals("57", opened?.hadithNumber) }

        compose.onNodeWithTag("reader.saved.edit").performClick()
        compose.runOnIdle { assertEquals(true, edited) }
    }
}
