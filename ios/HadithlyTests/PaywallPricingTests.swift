import XCTest
@testable import Hadithly

final class PaywallPricingTests: XCTestCase {
    func testMonthlyEquivalentUsesSDKPriceOrCurrencyFormatterFallback() {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US")
        formatter.numberStyle = .currency
        formatter.currencyCode = "USD"
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2

        XCTAssertEqual(PaywallPricing.localizedAnnualMonthlyEquivalent(
            annualPrice: Decimal(string: "24.99")!, sdkLocalizedPrice: "$2.08", priceFormatter: formatter
        ), "$2.08")
        XCTAssertEqual(PaywallPricing.localizedAnnualMonthlyEquivalent(
            annualPrice: Decimal(string: "24.99")!, sdkLocalizedPrice: nil, priceFormatter: formatter
        ), "$2.08")
        XCTAssertNil(PaywallPricing.localizedAnnualMonthlyEquivalent(
            annualPrice: Decimal(string: "24.99")!, sdkLocalizedPrice: nil, priceFormatter: nil
        ))
    }

    func testAnnualSavingsUsesActualTwelveMonthlyPeriods() {
        XCTAssertEqual(PaywallPricing.annualSavingsPercent(
            monthlyPrice: Decimal(string: "2.99")!, monthlyCurrencyCode: "USD",
            annualPrice: Decimal(string: "24.99")!, annualCurrencyCode: "USD"
        ), 30)
    }

    func testNoSavingsOrMixedCurrenciesDoNotProduceBadge() {
        XCTAssertNil(PaywallPricing.annualSavingsPercent(
            monthlyPrice: Decimal(string: "2.99")!, monthlyCurrencyCode: "USD",
            annualPrice: Decimal(string: "35.88")!, annualCurrencyCode: "USD"
        ))
        XCTAssertNil(PaywallPricing.annualSavingsPercent(
            monthlyPrice: Decimal(string: "2.99")!, monthlyCurrencyCode: "USD",
            annualPrice: Decimal(string: "24.99")!, annualCurrencyCode: "EUR"
        ))
        XCTAssertNil(PaywallPricing.annualSavingsPercent(
            monthlyPrice: 0, monthlyCurrencyCode: "USD",
            annualPrice: Decimal(string: "24.99")!, annualCurrencyCode: "USD"
        ))
    }
}
