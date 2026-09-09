package com.hadithly.app

import com.hadithly.app.core.preferences.PageDirection
import com.hadithly.app.core.preferences.ReaderPageTurn
import com.hadithly.app.core.preferences.ReaderPagingPolicy
import com.hadithly.app.core.preferences.ReaderPreferences
import com.hadithly.app.core.preferences.ReadingDirection
import com.hadithly.app.core.preferences.SwipeDirection
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class ReaderPagingTest {
    @Test
    fun `behavioral direction matrix matches iOS`() {
        data class Case(
            val name: String,
            val preferences: ReaderPreferences,
            val pageDirection: PageDirection,
            val leftTurn: ReaderPageTurn,
        )
        val cases = listOf(
            Case("Arabic-only auto", preferences("en", true, false), PageDirection.RTL, ReaderPageTurn.PREVIOUS),
            Case("translation-only English auto", preferences("en", false, true), PageDirection.LTR, ReaderPageTurn.NEXT),
            Case("translation-only Urdu auto", preferences("ur", false, true), PageDirection.RTL, ReaderPageTurn.PREVIOUS),
            Case("mixed Arabic and English auto", preferences("en", true, true), PageDirection.LTR, ReaderPageTurn.NEXT),
            Case("mixed Arabic and Urdu auto", preferences("ur", true, true), PageDirection.RTL, ReaderPageTurn.PREVIOUS),
            Case("forced LTR", preferences("ur", true, true, ReadingDirection.LTR), PageDirection.LTR, ReaderPageTurn.NEXT),
            Case("forced RTL", preferences("en", true, true, ReadingDirection.RTL), PageDirection.RTL, ReaderPageTurn.PREVIOUS),
        )

        cases.forEach { case ->
            val policy = ReaderPagingPolicy(case.preferences)
            assertEquals(case.name, case.pageDirection, policy.pageDirection)
            assertEquals(case.name, case.leftTurn, policy.turn(SwipeDirection.LEFT))
            assertEquals(
                case.name,
                if (case.leftTurn == ReaderPageTurn.NEXT) ReaderPageTurn.PREVIOUS else ReaderPageTurn.NEXT,
                policy.turn(SwipeDirection.RIGHT),
            )
        }
    }

    @Test
    fun `first and last page boundaries and end control order`() {
        val ltr = ReaderPagingPolicy(PageDirection.LTR)
        assertNull(ltr.destination(0, 3, ReaderPageTurn.PREVIOUS))
        assertEquals(1, ltr.destination(0, 3, ReaderPageTurn.NEXT))
        assertEquals(1, ltr.destination(2, 3, ReaderPageTurn.PREVIOUS))
        assertNull(ltr.destination(2, 3, ReaderPageTurn.NEXT))
        assertEquals(listOf(ReaderPageTurn.PREVIOUS, ReaderPageTurn.NEXT), ltr.endControlOrder)

        val rtl = ReaderPagingPolicy(PageDirection.RTL)
        assertEquals(listOf(ReaderPageTurn.NEXT, ReaderPageTurn.PREVIOUS), rtl.endControlOrder)
        assertEquals(true, rtl.reverseLayout)
        assertEquals(false, ltr.reverseLayout)
    }

    private fun preferences(
        locale: String,
        arabic: Boolean,
        translation: Boolean,
        direction: ReadingDirection = ReadingDirection.AUTO,
    ) = ReaderPreferences(
        translationLocale = locale,
        arabicVisible = arabic,
        translationVisible = translation,
        readingDirection = direction,
    )
}
