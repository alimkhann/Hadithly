package com.hadithly.app

import com.hadithly.app.core.data.SavedUndoController
import com.hadithly.app.core.data.UNDO_NOTICE_MILLIS
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.setMain
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SavedUndoControllerTest {

    private val dispatcher = StandardTestDispatcher()
    private var nowElapsed = 0L

    @Before
    fun setUp() {
        Dispatchers.setMain(dispatcher)
    }

    @After
    fun tearDown() {
        Dispatchers.resetMain()
    }

    private fun controller(scope: kotlinx.coroutines.CoroutineScope) =
        SavedUndoController(scope) { nowElapsed }

    @Test
    fun `notice survives past its deadline until the expiry job runs`() {
        runTest {
            val scope = this
            val undo = controller(scope)
            var undone = false
            undo.show("Bookmark removed") { undone = true }
            nowElapsed = UNDO_NOTICE_MILLIS + 1
            assertEquals(0f, undo.remainingFraction(undo.notice.value!!), 0.001f)
            assertFalse(undone)
            advanceUntilIdle()
            assertNull(undo.notice.value)
            assertFalse(undone)
        }
    }

    @Test
    fun `undo after the deadline clears the notice without running the action`() {
        runTest {
            val undo = controller(this)
            var undone = false
            undo.show("Bookmark removed") { undone = true }
            nowElapsed = UNDO_NOTICE_MILLIS
            undo.undo()
            assertNull(undo.notice.value)
            assertFalse(undone)
            advanceUntilIdle()
        }
    }

    @Test
    fun `undo before the deadline runs the action once`() {
        runTest {
            val undo = controller(this)
            var count = 0
            undo.show("Bookmark removed") { count += 1 }
            undo.undo()
            assertEquals(1, count)
            assertNull(undo.notice.value)
            advanceUntilIdle()
            assertEquals(1, count)
        }
    }

    @Test
    fun `a new notice replaces the previous deadline and action`() {
        runTest {
            val undo = controller(this)
            var first = false
            var second = false
            undo.show("First") { first = true }
            undo.show("Second") { second = true }
            undo.undo()
            assertFalse(first)
            assertTrue(second)
            advanceUntilIdle()
            assertNull(undo.notice.value)
        }
    }

    @Test
    fun `remaining fraction counts down from one to zero`() {
        runTest {
            val undo = controller(this)
            undo.show("Bookmark removed") {}
            val notice = undo.notice.value
            assertNotNull(notice)
            assertEquals(1f, undo.remainingFraction(notice!!), 0.001f)
            nowElapsed = UNDO_NOTICE_MILLIS / 2
            assertEquals(0.5f, undo.remainingFraction(notice), 0.01f)
            nowElapsed = UNDO_NOTICE_MILLIS + 5_000
            assertEquals(0f, undo.remainingFraction(notice), 0.001f)
        }
    }
}
