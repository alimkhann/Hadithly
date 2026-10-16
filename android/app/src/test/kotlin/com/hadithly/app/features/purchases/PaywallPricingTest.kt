package com.hadithly.app.features.purchases

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.Locale

class PaywallPricingTest {
    @Test fun fallbackMonthlyEquivalentUsesAnnualPriceCurrencyAndLocale() {
        assertEquals("$2.08", PaywallPricing.formatAnnualMonthlyEquivalent(24_990_000, "USD", Locale.US))
        assertEquals("2,08 €", PaywallPricing.formatAnnualMonthlyEquivalent(24_990_000, "EUR", Locale.GERMANY))
        assertNull(PaywallPricing.formatAnnualMonthlyEquivalent(24_990_000, "invalid", Locale.US))
    }

    @Test fun calculatesSavingsFromTheCurrentMonthlyAndAnnualStorePrices() {
        assertEquals(30, PaywallPricing.annualSavingsPercent(2_990_000, "USD", 24_990_000, "USD"))
        assertEquals(17, PaywallPricing.annualSavingsPercent(2_990_000, "USD", 29_880_000, "USD"))
    }

    @Test fun omitsSavingsWhenThereIsNoDiscountOrCurrenciesCannotBeCompared() {
        assertNull(PaywallPricing.annualSavingsPercent(2_990_000, "USD", 35_880_000, "USD"))
        assertNull(PaywallPricing.annualSavingsPercent(2_990_000, "USD", 24_990_000, "EUR"))
        assertNull(PaywallPricing.annualSavingsPercent(0, "USD", 24_990_000, "USD"))
        assertNull(PaywallPricing.annualSavingsPercent(2_990_000, null, 24_990_000, "USD"))
    }
}
