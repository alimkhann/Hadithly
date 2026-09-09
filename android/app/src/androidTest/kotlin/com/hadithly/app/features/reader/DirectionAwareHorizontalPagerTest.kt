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
import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.assertIsNotDisplayed
import androidx.compose.ui.test.assertContentDescriptionEquals
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performTouchInput
import androidx.compose.ui.test.swipe
import androidx.compose.ui.test.swipeUp
import androidx.compose.ui.unit.dp
import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPageTurn
import com.hadithly.app.core.theme.HadithlyTheme
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test

class DirectionAwareHorizontalPagerTest {
    @get:Rule
    val compose = createComposeRule()

    @Test
    fun ltrSwipeLeftMovesForwardOnOneLinePages() {
        setPager(PageDirection.LTR)

        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerRight, end = centerLeft, durationMillis = 250)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-2").assertIsDisplayed()
    }

    @Test
    fun rtlSwipeLeftMovesBackwardOnOneLinePages() {
        setPager(PageDirection.RTL)

        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerRight, end = centerLeft, durationMillis = 250)
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-0").assertIsDisplayed()
    }

    @Test
    fun fastShortSwipeUsesNativePagerVelocity() {
        setPager(PageDirection.LTR)

        compose.onNodeWithTag("pager").performTouchInput {
            swipe(
                start = centerRight,
                end = center,
                durationMillis = 35,
            )
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-2").assertIsDisplayed()
    }

    @Test
    fun cancelledSwipeDoesNotTurnPage() {
        setPager(PageDirection.LTR)

        compose.onNodeWithTag("pager").performTouchInput {
            down(centerRight)
            moveTo(center, delayMillis = 60)
            cancel()
        }
        compose.waitForIdle()
        compose.onNodeWithTag("page-1").assertIsDisplayed()
    }

    @Test
    fun verticalScrollOnMultiScreenPageDoesNotTurnPage() {
        setPager(PageDirection.RTL, longContent = true)

        compose.onNodeWithTag("long-page-1").performTouchInput { swipeUp() }
        compose.waitForIdle()
        compose.onNodeWithTag("page-1").assertIsDisplayed()
        compose.onNodeWithTag("line-1-0").assertIsNotDisplayed()
    }

    @Test
    fun firstOutwardSwipeAtTheLastPageReachesVolumeTurn() {
        var outwardTurn: ReaderPageTurn? = null
        compose.setContent {
            val pagerState = rememberPagerState(initialPage = 2, pageCount = { 3 })
            DirectionAwareHorizontalPager(
                state = pagerState,
                policy = ReaderPagingPolicy(PageDirection.LTR),
                onOutwardEdgeTurn = {
                    outwardTurn = it
                    true
                },
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("pager"),
            ) { page -> TestPage(page, longContent = false) }
        }

        compose.onNodeWithTag("pager").performTouchInput {
            swipe(start = centerRight, end = centerLeft, durationMillis = 250)
        }
        compose.runOnIdle { assertEquals(ReaderPageTurn.NEXT, outwardTurn) }
    }

    @Test
    fun firstAndLastBoundariesExposeLogicalAccessibilityControls() {
        var turn: ReaderPageTurn? = null
        compose.setContent {
            HadithlyTheme {
                ReaderEndNavigation(
                    policy = ReaderPagingPolicy(PageDirection.RTL),
                    currentPageIndex = 0,
                    pageCount = 3,
                    onTurn = { turn = it },
                )
            }
        }

        compose.onNodeWithTag("reader.previousPage").assertDoesNotExist()
        compose.onNodeWithTag("reader.nextPage")
            .assertContentDescriptionEquals("Next page, Page 2")
            .performClick()
        compose.runOnIdle { assertEquals(ReaderPageTurn.NEXT, turn) }
    }

    private fun setPager(direction: PageDirection, longContent: Boolean = false) {
        compose.setContent {
            val pagerState = rememberPagerState(initialPage = 1, pageCount = { 3 })
            DirectionAwareHorizontalPager(
                state = pagerState,
                policy = ReaderPagingPolicy(direction),
                modifier = Modifier
                    .fillMaxSize()
                    .testTag("pager"),
            ) { page ->
                TestPage(page, longContent)
            }
        }
    }

    @Composable
    private fun TestPage(page: Int, longContent: Boolean) {
        if (longContent) {
            Box(modifier = Modifier.fillMaxSize()) {
                LazyColumn(
                    modifier = Modifier
                        .fillMaxSize()
                        .testTag("long-page-$page"),
                ) {
                    items((0..40).toList()) { line ->
                        Text(
                            text = "Page $page line $line",
                            modifier = Modifier
                                .height(64.dp)
                                .testTag("line-$page-$line"),
                        )
                    }
                }
                Text(
                    "Page $page",
                    modifier = Modifier
                        .align(Alignment.TopEnd)
                        .testTag("page-$page"),
                )
            }
        } else {
            Box(modifier = Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                Text("Page $page", modifier = Modifier.testTag("page-$page"))
            }
        }
    }
}
