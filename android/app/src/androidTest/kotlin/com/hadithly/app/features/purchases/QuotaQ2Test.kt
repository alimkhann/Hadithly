package com.hadithly.app.features.purchases

import androidx.compose.ui.test.assertIsDisplayed
import androidx.compose.ui.test.junit4.v2.createComposeRule
import androidx.compose.ui.test.onNodeWithText
import androidx.compose.ui.test.onAllNodesWithText
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performScrollTo
import androidx.test.platform.app.InstrumentationRegistry
import com.hadithly.app.R
import com.hadithly.app.core.purchases.PurchaseManager
import com.hadithly.app.core.purchases.PendingPurchaseStore
import com.hadithly.app.core.theme.HadithlyTheme
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import org.junit.After
import org.junit.Assert.*
import org.junit.Rule
import org.junit.Test

class QuotaQ2Test {
    @get:Rule val compose = createComposeRule()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    @After fun close() { scope.cancel() }

    @Test fun pendingStorePinsOriginalAccountAcrossRelaunchAndFailsClosedOnCorruption() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val preferences = context.getSharedPreferences("q2-pending-test", android.content.Context.MODE_PRIVATE)
        preferences.edit().clear().commit()
        try {
            val first = PendingPurchaseStore(preferences)
            assertTrue(first.begin("original", "monthly", true))
            val relaunched = PendingPurchaseStore(preferences)
            assertTrue(relaunched.blocks("another"))
            assertFalse(relaunched.begin("another", "monthly", true))
            relaunched.clear("another")
            assertEquals("original", relaunched.pending?.ownerId)
            assertTrue(relaunched.begin("original", null, false))
            assertEquals("monthly", relaunched.pending?.productId)
            assertFalse(relaunched.begin("original", "annual", true))
            relaunched.clear("original")
            assertNull(relaunched.pending)
            preferences.edit().putString("pending.v1", "corrupt").commit()
            assertTrue(relaunched.unreadable)
            assertTrue(relaunched.blocks("original"))
        } finally { preferences.edit().clear().commit() }
    }
    @Test fun quotaCopyOwnDevicesAndRestoreFailureKeepReadingAvailable() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val purchases = PurchaseManager(context, "", scope)
        compose.setContent { HadithlyTheme { QuotaPaywallSheet(purchases, {}, {}) } }
        compose.onNodeWithText(context.getString(R.string.la2_allowance)).assertIsDisplayed()
        compose.onNodeWithText(context.getString(R.string.q2_devices)).assertIsDisplayed()
        compose.onNodeWithText("Weekly").assertDoesNotExist()
        assertFalse(purchases.state.value.configured)
        compose.onNodeWithTag("paywall.more").performClick()
        compose.onNodeWithTag("paywall.restore").assertIsDisplayed().performClick()
        compose.waitUntil(5_000) {
            compose.onAllNodesWithText("Sign in to your original Hadithly account before restoring.").fetchSemanticsNodes().isNotEmpty()
        }
        compose.onNodeWithText("Sign in to your original Hadithly account before restoring.").assertExists()
        compose.onNodeWithTag("paywall.keepReading").assertExists()
        compose.runOnIdle {
            assertEquals("Sign in to your original Hadithly account before restoring.", purchases.state.value.errorMessage)
            assertFalse(purchases.state.value.purchasing)
            assertFalse(purchases.state.value.hasProEntitlement)
        }
    }
}
