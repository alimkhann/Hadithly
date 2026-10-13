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
    private var package: Package? { environment.purchases.packages.first { $0.identifier == selected } }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    VStack(spacing: 12) {
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
                        VStack(spacing: 12) {
                            ForEach(environment.purchases.packages, id: \.identifier) { option in
                                Button {
                                    selected = option.identifier
                                    environment.analytics.record(option.packageType == .annual ? .paywallResultSelectedAnnual : .paywallResultSelectedMonthly)
                                } label: {
                                    HStack(spacing: 12) {
                                        Image(systemName: selected == option.identifier ? "largecircle.fill.circle" : "circle").accessibilityHidden(true)
                                        Text(option.packageType == .annual ? "la2.annual" : "la2.monthly").font(.headline)
                                        Spacer()
                                        Text(option.storeProduct.localizedPriceString).font(.headline).monospacedDigit()
                                    }.padding(18).frame(maxWidth: .infinity, minHeight: 56)
                                        .background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 16))
                                }.buttonStyle(.plain).disabled(environment.purchases.isPurchasing)
                                    .accessibilityAddTraits(selected == option.identifier ? .isSelected : [])
                                    .accessibilityIdentifier(option.packageType == .annual ? "paywall.annual" : "paywall.monthly")
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
                        if environment.purchases.packages.isEmpty {
                            Button("la2.retry") { Task { await loadPlans() } }.frame(minHeight: 44)
                        }
                    }
                    Button("la2.keep_reading") { environment.analytics.record(.paywallResultDismissed); dismiss() }
                        .frame(minHeight: 44).accessibilityIdentifier("paywall.keepReading")
                    Button("la2.restore") {
                        attemptedRevision = environment.purchases.operationRevision; attemptedUnlock = true; restoring = true
                        Task { if await environment.purchases.restore() { completeUnlock() } }
                    }.frame(minHeight: 44).disabled(environment.purchases.isPurchasing).accessibilityIdentifier("paywall.restore")
                    HStack(spacing: 24) {
                        if let url = environment.config.privacyPolicyURL { Link("la2.privacy", destination: url).frame(minHeight: 44) }
                        if let url = environment.config.termsOfUseURL { Link("la2.terms", destination: url).frame(minHeight: 44) }
                    }.font(.footnote)
                    Text("la2.renewal").font(.footnote).foregroundStyle(palette.textSecondary).multilineTextAlignment(.center)
                }.padding(24).foregroundStyle(palette.textPrimary)
            }.background(palette.background.ignoresSafeArea())
                .toolbar { ToolbarItem(placement: .topBarTrailing) {
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
        await environment.purchases.loadOffering()
        selected = environment.purchases.packages.first(where: { $0.packageType == .monthly })?.identifier
        let available = !environment.purchases.packages.isEmpty
        if reportedAvailability.insert(available).inserted {
            environment.analytics.record(available ? .paywallResultAvailable : .paywallResultUnavailable)
        }
        environment.analytics.flush()
    }
}
