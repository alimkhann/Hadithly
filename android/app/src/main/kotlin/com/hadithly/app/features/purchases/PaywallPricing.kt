package com.hadithly.app.features.purchases

import java.math.BigDecimal
import java.math.MathContext
import java.math.RoundingMode
import java.text.NumberFormat
import java.util.Currency
import java.util.Locale
import com.revenuecat.purchases.models.StoreProduct

/** Compares current store prices without assuming a fixed regional tier. */
internal object PaywallPricing {
    fun localizedAnnualMonthlyEquivalent(product: StoreProduct, locale: Locale): String? {
        product.formattedPricePerMonth(locale)?.takeIf(String::isNotBlank)?.let { return it }
        return formatAnnualMonthlyEquivalent(product.price.amountMicros, product.price.currencyCode, locale)
    }

    internal fun formatAnnualMonthlyEquivalent(amountMicros: Long, currencyCode: String, locale: Locale): String? {
        if (amountMicros <= 0) return null
        return runCatching {
            val formatter = NumberFormat.getCurrencyInstance(locale).apply { currency = Currency.getInstance(currencyCode) }
            val monthlyAmount = BigDecimal.valueOf(amountMicros)
                .movePointLeft(6)
                .divide(BigDecimal.valueOf(12), MathContext.DECIMAL128)
            formatter.format(monthlyAmount)
        }.getOrNull()
    }

    fun annualSavingsPercent(
        monthlyAmountMicros: Long,
        monthlyCurrencyCode: String?,
        annualAmountMicros: Long,
        annualCurrencyCode: String?,
    ): Int? {
        if (monthlyAmountMicros <= 0 || annualAmountMicros < 0) return null
        if (monthlyCurrencyCode.isNullOrBlank() || annualCurrencyCode.isNullOrBlank()) return null
        if (!monthlyCurrencyCode.equals(annualCurrencyCode, ignoreCase = true)) return null

        val twelveMonthlyPayments = BigDecimal.valueOf(monthlyAmountMicros).multiply(BigDecimal.valueOf(12))
        val annual = BigDecimal.valueOf(annualAmountMicros)
        if (annual >= twelveMonthlyPayments) return null
        val percent = twelveMonthlyPayments.subtract(annual)
            .multiply(BigDecimal.valueOf(100))
            .divide(twelveMonthlyPayments, 0, RoundingMode.HALF_UP)
            .intValueExact()
        return percent.takeIf { it > 0 }
    }
}
