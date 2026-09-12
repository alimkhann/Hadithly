package com.hadithly.app

import com.hadithly.app.features.today.TodayContentPolicy
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class TodayTest {
    @Test fun `short daily reading stays fully visible`() {
        assertFalse(TodayContentPolicy.needsCollapsedPreview("نص قصير", "Short translation"))
    }

    @Test fun `extreme daily reading uses collapsed preview`() {
        assertTrue(TodayContentPolicy.needsCollapsedPreview(
            "نص ".repeat(300),
            "translation ".repeat(300),
        ))
    }
}
