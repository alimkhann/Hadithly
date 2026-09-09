package com.hadithly.app.features.reader

import androidx.compose.runtime.Composable
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import com.hadithly.app.core.data.AuthenticityClaim
import com.hadithly.app.core.data.ReaderHadith
import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPageTurn
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test

/**
 * R6A slice A on the hadithly emulator: the Sajda-quiet page. No dividers,
 * no overflow button, dim provider-number markers, grade dot plus compact
 * label, source sheet, volume corner/header, and the adjacent chevron
 * cluster — with the long-press menu and TalkBack actions intact.
 */
class ReaderR6AQuietTest {
    @get:Rule
    val compose = createComposeRule()

    private fun hadith(
        providerHadithId: String = "57",
        authenticity: AuthenticityClaim = AuthenticityClaim(
            kind = "source",
            normalizedGrade = "sahih",
            claimScope = "hadith",
            sourceLabel = "Sunnah.com",
            sourceName = "Sunnah.com",
            sourceUrl = "https://sunnah.com/bukhari:57",
            verificationMethod = "provider",
        ),
    ) = ReaderHadith(
        _id = "h-$providerHadithId",
        provider = "sunnah_now",
        canonicalId = "sunnah_now:bukhari:$providerHadithId",
        providerHadithId = providerHadithId,
        collectionSlug = "bukhari",
        arabicText = "حَدَّثَنَا",
        englishText = "He said:",
        narrator = "Narrated Abu Huraira:",
        referenceDisplay = "Sahih al-Bukhari · Hadith $providerHadithId",
        collectionName = "Sahih al-Bukhari",
        chapterName = "Belief",
        authenticity = authenticity,
    )

    private class FakeDeps : HadithBlockDeps {
        var bookmarks = 0
        var favorites = 0
        override val isBookmarked = false
        override val isFavorite = false
        override val hasNote = false
        override fun onToggleBookmark() {
            bookmarks += 1
        }
        override fun onToggleFavorite() {
            favorites += 1
        }
    }

    @Composable
    private fun block(
        hadith: ReaderHadith = hadith(),
        deps: HadithBlockDeps = FakeDeps(),
        translationState: TranslationUiState? = null,
        onShowSource: () -> Unit = {},
    ) {
        HadithlyTheme {
            HadithBlock(
                hadith = hadith,
                translationState = translationState,
                language = "en",
                arabicFontSize = 26f,
                preferences = ReaderPreferences(),
                deps = deps,
                onTap = {},
                onRetry = {},
                onShowCitations = {},
                onShowSource = onShowSource,
                onEditNote = {},
                onSuggest = {},
                onReport = {},
                onShowPaywall = {},
            )
        }
    }

    @Test
    fun quietBlockHasNoOverflowOrLegacyLines() {
        compose.setContent { block() }

        compose.onNodeWithTag("reader.moreActions").assertDoesNotExist()
        compose.onNodeWithTag("reader.reference").assertDoesNotExist()
        compose.onNodeWithTag("reader.authenticity").assertDoesNotExist()
        compose.onNodeWithText("Hadith 57", substring = true).assertDoesNotExist()
    }

    @Test
    fun markerShowsProviderNumberOnly() {
        compose.setContent { block() }

        compose.onNodeWithTag("reader.hadithMarker", useUnmergedTree = true)
            .assertIsDisplayed()
            .assertTextEquals("57")
    }

    @Test
    fun dotAndLabelTapOpensSource() {
        var opened = 0
        compose.setContent { block(onShowSource = { opened += 1 }) }

        // The dot lives inside the label's clickable, so it merged into the
        // label node: assert it in the unmerged tree.
        compose.onNodeWithTag("reader.gradeDot", useUnmergedTree = true).assertIsDisplayed()
        compose.onNodeWithTag("reader.hadithLabel").assertIsDisplayed()
        compose.onNodeWithText("Bukhari – 57").assertIsDisplayed()
        compose.onNodeWithTag("reader.hadithLabel").performClick()
        compose.runOnIdle { assertEquals(1, opened) }
    }

    @Test
    fun sourceSheetShowsNameScopeAndUrl() {
        compose.setContent {
            HadithlyTheme { HadithSourceSheet(hadith = hadith()) }
        }

        compose.onNodeWithTag("reader.sourceSheet").assertIsDisplayed()
        compose.onNodeWithText("Sunnah.com").assertIsDisplayed()
        compose.onNodeWithText("Sahih hadith · Sunnah.com").assertIsDisplayed()
        compose.onNodeWithText("https://sunnah.com/bukhari:57").assertIsDisplayed()
    }

    @Test
    fun sourceSheetOmitsMissingUrl() {
        val noUrl = hadith().copy(
            authenticity = hadith().authenticity.copy(sourceUrl = ""),
        )
        compose.setContent {
            HadithlyTheme { HadithSourceSheet(hadith = noUrl) }
        }

        compose.onNodeWithTag("reader.sourceSheet").assertIsDisplayed()
        compose.onNodeWithText("https://", substring = true).assertDoesNotExist()
    }

    @Test
    fun volumeCornerShowsTitleOnly() {
        compose.setContent {
            HadithlyTheme {
                VolumeCornerLabel(title = "Volume 2", range = null)
            }
        }
        compose.onNodeWithTag("reader.volumeCorner").assertIsDisplayed()
        compose.onNodeWithText("Volume 2").assertIsDisplayed()
    }

    @Test
    fun volumeCornerAppendsCachedRange() {
        compose.setContent {
            HadithlyTheme {
                VolumeCornerLabel(title = "Volume 2", range = 58 to 101)
            }
        }
        compose.onNodeWithText("Volume 2: 58–101").assertIsDisplayed()
    }

    @Test
    fun volumeHeaderShowsLocalizedCount() {
        // Resolve the expectation through the framework ICU plural table in
        // the same configuration (the emulator may run a non-English system
        // locale); the XML quantities per locale are proven in ReaderR6ATest.
        var expectedCount = ""
        compose.setContent {
            HadithlyTheme {
                expectedCount = androidx.compose.ui.platform.LocalContext.current.resources
                    .getQuantityString(
                        com.hadithly.app.R.plurals.reader_hadith_count,
                        10,
                        10,
                    )
                VolumeStartHeader(title = "Volume 2", hadithCount = 10)
            }
        }

        compose.onNodeWithText("Volume 2").assertIsDisplayed()
        compose.runOnIdle { assertTrue(expectedCount.isNotBlank()) }
        compose.onNodeWithText(expectedCount).assertIsDisplayed()
    }

    @Test
    fun chapterHeaderIsQuietNameOnly() {
        compose.setContent {
            HadithlyTheme {
                ReaderChapterHeader(title = "Belief", arabicTitle = "الإيمان")
            }
        }

        compose.onNodeWithTag("reader.chapterHeader").assertIsDisplayed()
        compose.onNodeWithText("Belief").assertIsDisplayed()
        compose.onNodeWithText("الإيمان").assertIsDisplayed()
        compose.onNodeWithText("Chapter", substring = true).assertDoesNotExist()
    }

    @Test
    fun chapterHeaderOmitsArabicWhenMissing() {
        compose.setContent {
            HadithlyTheme {
                ReaderChapterHeader(title = "Belief", arabicTitle = null)
            }
        }
        compose.onNodeWithText("Belief").assertIsDisplayed()
    }

    @Test
    fun chapterHeaderOmitsArabicWhenSame() {
        compose.setContent {
            HadithlyTheme {
                ReaderChapterHeader(title = "Belief", arabicTitle = "Belief")
            }
        }
        // Exactly one Belief node: no duplicate Arabic second line.
        compose.onAllNodesWithText("Belief").assertCountEquals(1)
    }

    @Test
    fun pageClusterKeepsChevronsAdjacent() {
        var turn: ReaderPageTurn? = null
        compose.setContent {
            HadithlyTheme {
                ReaderEndNavigation(
                    policy = ReaderPagingPolicy(PageDirection.LTR),
                    currentPageIndex = 1,
                    pageCount = 5,
                    onTurn = { turn = it },
                )
            }
        }

        compose.onNodeWithTag("reader.pageCluster").assertIsDisplayed()
        compose.onNodeWithText("Page 2 of 5").assertIsDisplayed()
        compose.onNodeWithTag("reader.previousPage").assertIsDisplayed()
        compose.onNodeWithTag("reader.nextPage").assertIsDisplayed()
        compose.onNodeWithTag("reader.previousPage").performClick()
        compose.runOnIdle { assertEquals(ReaderPageTurn.PREVIOUS, turn) }
    }

    @Test
    fun pageClusterHidesMissingChevronAtBoundaries() {
        compose.setContent {
            HadithlyTheme {
                ReaderEndNavigation(
                    policy = ReaderPagingPolicy(PageDirection.LTR),
                    currentPageIndex = 0,
                    pageCount = 5,
                    onTurn = {},
                )
            }
        }

        compose.onNodeWithTag("reader.pageCluster").assertIsDisplayed()
        compose.onNodeWithText("Page 1 of 5").assertIsDisplayed()
        compose.onNodeWithTag("reader.previousPage").assertDoesNotExist()
        compose.onNodeWithTag("reader.nextPage").assertIsDisplayed()
    }

    @Test
    fun longPressOpensMenuWithAllActions() {
        // A loaded non-English translation gates the Report item in.
        val loaded = TranslationUiState.Loaded(
            com.hadithly.app.core.data.ReaderTranslation(
                translationId = "t1",
                translation = "Rendering",
                source = "gemini_ai",
                sourceLabel = "AI",
            ),
        )
        compose.setContent { block(translationState = loaded) }

        compose.onNodeWithTag("reader.copy").assertDoesNotExist()
        compose.onNodeWithTag("reader.hadithBlock").performTouchInput {
            down(0, center)
            move()
            advanceEventTime(viewConfiguration.longPressTimeoutMillis)
            up(0)
        }
        compose.waitForIdle()

        for (tag in listOf(
            "reader.bookmark",
            "reader.favorite",
            "reader.note",
            "reader.copy",
            "reader.share",
            "reader.reportTranslation",
            "reader.suggestTranslation",
        )) {
            compose.onNodeWithTag(tag).assertIsDisplayed()
        }
    }

    // TalkBack custom actions ride on the same seven-action list as the
    // long-press menu (one code path in HadithBlock); their label-for-label
    // equivalence and invocation are proven in ReaderR6ATest, since this
    // Compose version keeps the CustomActions storage key private and the
    // test API cannot read it back. The menu side is proven on-device above.
}
