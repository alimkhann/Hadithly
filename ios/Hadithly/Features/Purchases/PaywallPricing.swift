import Foundation

/// Pure comparison of the real monthly and annual store amounts.
enum PaywallPricing {
    static func localizedAnnualMonthlyEquivalent(
        annualPrice: Decimal,
        sdkLocalizedPrice: String?,
        priceFormatter: NumberFormatter?
    ) -> String? {
        if let sdkLocalizedPrice, !sdkLocalizedPrice.isEmpty { return sdkLocalizedPrice }
        guard let priceFormatter else { return nil }
        let monthlyPrice = annualPrice / 12
        return priceFormatter.string(from: NSDecimalNumber(decimal: monthlyPrice))
    }

    static func annualSavingsPercent(
        monthlyPrice: Decimal,
        monthlyCurrencyCode: String?,
        annualPrice: Decimal,
        annualCurrencyCode: String?
    ) -> Int? {
        guard monthlyPrice > 0,
              annualPrice >= 0,
              let monthlyCurrencyCode,
              let annualCurrencyCode,
              monthlyCurrencyCode.caseInsensitiveCompare(annualCurrencyCode) == .orderedSame else { return nil }

        let twelveMonths = monthlyPrice * 12
        guard annualPrice < twelveMonths else { return nil }
        let percent = ((twelveMonths - annualPrice) / twelveMonths) * 100
        let rounded = Int(NSDecimalNumber(decimal: percent).doubleValue.rounded(.toNearestOrAwayFromZero))
        return rounded > 0 ? rounded : nil
    }
}
