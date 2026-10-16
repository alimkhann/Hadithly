import RevenueCat
import SwiftUI

struct QuotaPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @State private var selected: String?
    @State private var reportedAvailability: Set<Bool> = []
    @State private var attemptedRevision: Int?
    @State private var attemptedUnlock = false
    @State private var didUnlock = false
    @State private var restoring = false
    let onUnlocked: () -> Void
    private var displayedPackages: [Package] {
        environment.purchases.packages.filter { option in
            option.packageType != .annual || localizedMonthlyEquivalent(for: option) != nil
        }
    }
    private var package: Package? { displayedPackages.first { $0.identifier == selected } }
    private var monthlyPackage: Package? { displayedPackages.first { $0.packageType == .monthly } }
    private var annualPackage: Package? { displayedPackages.first { $0.packageType == .annual } }
    private var annualSavingsPercent: Int? {
        guard let monthly = monthlyPackage?.storeProduct,
              let annual = annualPackage?.storeProduct else { return nil }
        return PaywallPricing.annualSavingsPercent(
            monthlyPrice: monthly.price,
            monthlyCurrencyCode: monthly.currencyCode,
            annualPrice: annual.price,
            annualCurrencyCode: annual.currencyCode
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 18) {
                    VStack(spacing: 10) {
                        Text("la2.more_translations").font(.title.bold())
                        Text("q1.quota_exhausted").font(.body).foregroundStyle(palette.textSecondary)
                        Text("la2.reading_free").font(.subheadline.weight(.medium))
                    }.multilineTextAlignment(.center)
                    Text("la2.allowance").font(.subheadline).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                    Text("q2.devices").font(.footnote).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                    if environment.purchases.isLoading { ProgressView() }
                    else if environment.purchases.hasProEntitlement {
                        Text("Hadithly Pro is active").font(.headline)
                    } else {
                        VStack(spacing: 10) {
                            ForEach(orderedPackages, id: \.identifier) { option in
                                offerRow(option)
                            }
                        }
                        if let package {
                            OnboardingPrimaryButton(package.packageType == .annual ? "la2.subscribe_annual" : "la2.subscribe_monthly") {
                                attemptedRevision = environment.purchases.operationRevision; attemptedUnlock = true
                                environment.analytics.record(.paywallResultPurchaseStarted)
                                Task {
                                    if await environment.purchases.purchase(package) {
                                        completeUnlock()
                                    }
                                }
                            }.disabled(environment.purchases.isPurchasing).accessibilityIdentifier("paywall.subscribe")
                        }
                    }
                    if environment.purchases.isPurchasing {
                        HStack { ProgressView(); Text("la2.checking") }.font(.subheadline)
                    }
                    outcomeNotice
                    if environment.purchases.outcome != .pending && environment.purchases.outcome != .cancelled,
                       let message = environment.purchases.errorMessage {
                        Text(message).font(.subheadline).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                    }
                    if !environment.purchases.isLoading && displayedPackages.isEmpty {
                        Button("la2.retry") { Task { await loadPlans() } }
                            .frame(minHeight: 44)
                            .accessibilityIdentifier("paywall.retryPlans")
                    }
                    Button("la2.keep_reading") { environment.analytics.record(.paywallResultDismissed); dismiss() }
                        .frame(minHeight: 44).accessibilityIdentifier("paywall.keepReading")
                    Text("la2.renewal").font(.footnote).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                }.padding(24).foregroundStyle(palette.textPrimary)
            }.background(palette.background.ignoresSafeArea())
                .toolbar { ToolbarItemGroup(placement: .topBarTrailing) {
                    Menu {
                        Button("la2.restore", action: restorePurchases)
                            .disabled(environment.purchases.isPurchasing)
                            .accessibilityIdentifier("paywall.restore")
                        if let url = environment.config.privacyPolicyURL {
                            Link("la2.privacy", destination: url)
                        }
                        if let url = environment.config.termsOfUseURL {
                            Link("la2.terms", destination: url)
                        }
                    } label: {
                        Label("q2.more", systemImage: "ellipsis")
                            .labelStyle(.iconOnly)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .accessibilityIdentifier("paywall.more")
                    Button("la2.close") { environment.analytics.record(.paywallResultDismissed); dismiss() }.frame(minHeight: 44)
                } }
        }.task { environment.analytics.record(.paywallResultShown); await loadPlans() }
        .onChange(of: environment.purchases.hasProEntitlement) { _, active in if active { completeUnlock() } }
        .onDisappear { environment.analytics.record(.paywallResultDismissed) }
            .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
            .interactiveDismissDisabled(environment.purchases.isPurchasing)
            .accessibilityIdentifier("paywall.quota")
    }
    @ViewBuilder private var outcomeNotice: some View {
        switch environment.purchases.outcome {
        case .cancelled: Text("la2.cancelled").font(.subheadline)
        case .pending: Text("la2.pending").font(.subheadline)
        case .syncing: Text("q2.wait").font(.subheadline)
        default: EmptyView()
        }
    }
    private func completeUnlock() {
        guard attemptedUnlock, !didUnlock, attemptedRevision == environment.purchases.operationRevision, environment.purchases.hasProEntitlement else { return }
        didUnlock = true
        if environment.purchases.outcome != .confirmed {
            environment.analytics.record(restoring ? .purchaseResultRestoreConfirmed : .purchaseResultConfirmed)
        }
        environment.analytics.record(.paywallResultConfirmed); onUnlocked(); dismiss()
    }
    private func loadPlans() async {
        let previousSelection = selected
        await environment.purchases.loadOffering()
        let packages = displayedPackages
        if !packages.isEmpty {
            selected = packages.first(where: { $0.identifier == previousSelection })?.identifier
                ?? packages.first(where: { $0.packageType == .annual })?.identifier
                ?? packages.first(where: { $0.packageType == .monthly })?.identifier
        }
        let available = !packages.isEmpty
        if reportedAvailability.insert(available).inserted {
            environment.analytics.record(available ? .paywallResultAvailable : .paywallResultUnavailable)
        }
        environment.analytics.flush()
    }

    private var orderedPackages: [Package] {
        displayedPackages.sorted { $0.packageType == .annual && $1.packageType != .annual }
    }

    private func localizedMonthlyEquivalent(for package: Package) -> String? {
        PaywallPricing.localizedAnnualMonthlyEquivalent(
            annualPrice: package.storeProduct.price,
            sdkLocalizedPrice: package.storeProduct.localizedPricePerMonth,
            priceFormatter: package.storeProduct.priceFormatter
        )
    }

    @ViewBuilder private func offerRow(_ option: Package) -> some View {
        let annual = option.packageType == .annual
        if let price = annual ? localizedMonthlyEquivalent(for: option) : option.storeProduct.localizedPriceString {
            PaywallPlanOption(annual: annual, isSelected: selected == option.identifier,
                price: price, savingsPercent: annualSavingsPercent, enabled: !environment.purchases.isPurchasing) {
                selected = option.identifier
                environment.analytics.record(annual ? .paywallResultSelectedAnnual : .paywallResultSelectedMonthly)
            }
        }
    }

    private func restorePurchases() {
        attemptedRevision = environment.purchases.operationRevision
        attemptedUnlock = true
        restoring = true
        Task { if await environment.purchases.restore() { completeUnlock() } }
    }
}

/// The production pricing choice, also rendered by the native prototype fixture.
struct PaywallPlanOption: View {
    let annual: Bool
    let isSelected: Bool
    let price: String
    let savingsPercent: Int?
    var enabled = true
    let onSelect: () -> Void
    @Environment(\.readerPalette) private var palette
    @Environment(\.locale) private var locale
    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                    Text(annual ? "la2.annual" : "la2.monthly").font(.headline)
                    Spacer()
                }
                if annual {
                    HStack(spacing: 8) {
                        Text("q2.recommended")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(palette.interactiveSoft, in: Capsule())
                        if let savings = savingsPercent {
                            Text(String(format: String(localized: "q2.savings_percent", locale: locale), savings))
                                .font(.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                    }
                }
                HStack(alignment: .firstTextBaseline, spacing: 5) {
                    Text(price).font(.title3.weight(.semibold)).monospacedDigit()
                    Text("q2.per_month").font(.caption).foregroundStyle(palette.textSecondary)
                    if annual {
                        Spacer()
                        Text("q2.billed_yearly").font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                .padding(.leading, 28)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(isSelected ? palette.surfaceElevated : palette.surface, in: RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).stroke(isSelected ? palette.interactive : palette.divider, lineWidth: isSelected ? 1.5 : 1))
        }
        .buttonStyle(.plain).disabled(!enabled)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier(annual ? "paywall.annual" : "paywall.monthly")
    }
}
