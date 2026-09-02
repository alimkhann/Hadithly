import RevenueCat
import SwiftUI

/// The only subscription entry point in the app. ReaderView presents this
/// sheet after the backend reports that the signed-in user exhausted AI quota.
struct QuotaPaywallView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment

    let onUnlocked: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "sparkles")
                        .font(.system(size: 30, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .accessibilityHidden(true)

                    VStack(spacing: 8) {
                        Text("More AI translations")
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("You reached this month’s free AI limit. Reading, saved items, and existing translations stay free.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    if environment.purchases.hasProEntitlement {
                        activeAccess
                    } else if environment.purchases.isLoading {
                        ProgressView()
                            .tint(Theme.textSecondary)
                    } else {
                        packageButtons
                    }

                    if let message = environment.purchases.errorMessage {
                        Text(message)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                            .multilineTextAlignment(.center)
                    }

                    Button("Restore purchases") {
                        Task {
                            if await environment.purchases.restore() {
                                unlockAndDismiss()
                            }
                        }
                    }
                    .font(.footnote.weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
                    .disabled(environment.purchases.isPurchasing)

                    HStack(spacing: 18) {
                        if let privacyURL = environment.config.privacyPolicyURL {
                            Link("Privacy Policy", destination: privacyURL)
                        }
                        if let termsURL = environment.config.termsOfUseURL {
                            Link("Terms of Use", destination: termsURL)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)

                    Text("Subscriptions renew automatically unless cancelled at least 24 hours before the end of the current period. Manage or cancel in your store account.")
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary.opacity(0.75))
                        .multilineTextAlignment(.center)
                }
                .padding(.horizontal, 24)
                .padding(.vertical, 28)
            }
            .background(Theme.background.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Close") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .task { await environment.purchases.loadOffering() }
        .interactiveDismissDisabled(environment.purchases.isPurchasing)
        .accessibilityIdentifier("paywall.quota")
    }

    @ViewBuilder
    private var packageButtons: some View {
        VStack(spacing: 12) {
            ForEach(environment.purchases.packages, id: \.identifier) { package in
                Button {
                    Task {
                        if await environment.purchases.purchase(package) {
                            unlockAndDismiss()
                        }
                    }
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(title(for: package))
                                .font(.headline)
                            Text(package.storeProduct.localizedPriceString)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        Spacer()
                        if environment.purchases.isPurchasing {
                            ProgressView().tint(Theme.textPrimary)
                        } else {
                            Image(systemName: "arrow.right")
                        }
                    }
                    .foregroundStyle(Theme.textPrimary)
                    .padding(16)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.surfaceElevated, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .disabled(environment.purchases.isPurchasing)
            }
        }
    }

    private var activeAccess: some View {
        VStack(spacing: 10) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundStyle(Theme.accent)
            Text("Hadithly Pro is active")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Button("Continue reading") { unlockAndDismiss() }
                .buttonStyle(.borderedProminent)
                .tint(Theme.accent)
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func title(for package: Package) -> String {
        switch package.packageType {
        case .annual: "Yearly"
        case .sixMonth: "Six months"
        case .threeMonth: "Three months"
        case .twoMonth: "Two months"
        case .monthly: "Monthly"
        case .weekly: "Weekly"
        case .lifetime: "Lifetime"
        default: package.storeProduct.localizedTitle
        }
    }

    private func unlockAndDismiss() {
        onUnlocked()
        dismiss()
    }
}
