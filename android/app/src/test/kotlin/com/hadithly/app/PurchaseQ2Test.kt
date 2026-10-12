package com.hadithly.app

import com.hadithly.app.core.purchases.PurchaseAccountGate
import com.hadithly.app.core.purchases.PurchaseManager
import com.hadithly.app.core.purchases.PurchaseOperationQueue
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import com.revenuecat.purchases.PackageType
import org.junit.Assert.*
import org.junit.Test

class PurchaseQ2Test {
    @Test fun identityAndCallbackRevisionsPreventCrossAccountAccess() {
        val gate = PurchaseAccountGate()
        val a = gate.bind("a")
        assertFalse(gate.accepts(a, "a"))
        gate.identified(a)
        assertTrue(gate.accepts(a, "a"))
        assertFalse(gate.accepts(a, "b"))
        val b = gate.bind("b")
        gate.identified(a)
        assertFalse(gate.accepts(b, "b"))
        gate.identified(b)
        assertTrue(gate.accepts(b, "b"))
        assertFalse(gate.accepts(a, "b"))
        gate.bind(null)
        assertFalse(gate.accepts(b, null))
    }
    @Test fun sdkIdentityWaitsForStoreOperationBeforeSwitching() = runBlocking {
        val queue = PurchaseOperationQueue()
        val started = CompletableDeferred<Unit>()
        val storeResult = CompletableDeferred<Unit>()
        var sdkAccount = "original"
        val purchase = launch { queue.run { started.complete(Unit); storeResult.await(); assertEquals("original", sdkAccount) } }
        started.await()
        val identity = launch { queue.run { sdkAccount = "next" } }
        yield()
        assertEquals("original", sdkAccount)
        storeResult.complete(Unit)
        purchase.join(); identity.join()
        assertEquals("next", sdkAccount)
    }
    @Test fun onlyProMonthlyAndAnnualPackagesAreAllowed() {
        assertTrue(PurchaseManager.allowedProduct("hadithly_pro_monthly:monthly", PackageType.MONTHLY))
        assertTrue(PurchaseManager.allowedProduct("hadithly_pro_annual:annual", PackageType.ANNUAL))
        assertFalse(PurchaseManager.allowedProduct("hadithly_pro_weekly:weekly", PackageType.WEEKLY))
        assertFalse(PurchaseManager.allowedProduct("hadithly_pro_annual:annual", PackageType.MONTHLY))
        assertFalse(PurchaseManager.allowedProduct("accidental_pro", PackageType.MONTHLY))
    }
}
