import SwiftUI
import ClerkKit
import ConvexMobile

/// S1 Settings root, native style: grouped list sections with short headers,
/// value-trailing rows, and monochrome symbols. Hierarchy comes from
/// luminance and section breaks, not accent color. Reading controls live in
/// their destinations and reuse the F2 preference contracts; the admin queue
/// no longer ships in the consumer app (E4 owns the secured exception tool).
struct SettingsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @Environment(UserLibraryModel.self) private var library
    @Environment(\.readerPalette) private var palette

    @State private var isSigningOut = false
    @State private var subscriptionTier: String?

    var body: some View {
        List {
            Group {
            if clerk.session != nil {
                Section {
                    NavigationLink(value: SettingsDestination.profile) {
                        HStack(spacing: 12) {
                            profileBadge
                            VStack(alignment: .leading, spacing: 2) {
                                Text(accountName)
                                    .font(.headline)
                                    .foregroundStyle(Theme.textPrimary)
                                if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                                    Text(email)
                                        .font(.caption)
                                        .foregroundStyle(Theme.textSecondary)
                                }
                            }
                        }
                    }
                    .accessibilityIdentifier(SettingsDestination.profile.accessibilityID)
                }
            } else {
                Section {
                    Button { showSignIn = true } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle").font(.system(size: 32, weight: .light))
                                .foregroundStyle(palette.textSecondary).accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Sign in").font(.headline).foregroundStyle(palette.textPrimary)
                                Text("Sync bookmarks and notes across devices.").font(.subheadline).foregroundStyle(palette.textSecondary)
                            }
                            Spacer(minLength: 4)
                            Image(systemName: "chevron.right").font(.caption.weight(.semibold)).foregroundStyle(palette.textSecondary).accessibilityHidden(true)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.signin")
                }
            }

            Section("Reading") {
                SettingsLinkRow(destination: .appearance)
                SettingsLinkRow(
                    destination: .appLanguage,
                    value: languageName(for: environment.preferences.preferences.uiLocale)
                )
                SettingsLinkRow(
                    destination: .hadithTranslation,
                    value: languageName(for: environment.preferences.preferences.translationLocale)
                )
                SettingsLinkRow(destination: .readingAndType)
            }

            Section("Library") {
                SettingsLinkRow(destination: .offlineStorage)
                SettingsLinkRow(destination: .notifications)
                SettingsLinkRow(
                    destination: .subscription,
                    value: SettingsSubscription.displayName(tier: subscriptionTier)
                )
            }

            Section("Support") {
                SettingsLinkRow(destination: .privacyAndData)
                SettingsLinkRow(destination: .helpAndSupport)
                SettingsLinkRow(destination: .aboutAndLegal)
            }

            if clerk.session != nil {
                Section {
                    Button {
                        Task { await signOut() }
                    } label: {
                        if isSigningOut {
                            ProgressView()
                                .frame(maxWidth: .infinity)
                        } else {
                            Text("Sign out")
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(isSigningOut)
                    .accessibilityIdentifier("settings.signout")
                }
            }

            }
            .listRowBackground(palette.surface)

        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .toolbarBackground(palette.background, for: .navigationBar)
        .navigationDestination(for: SettingsDestination.self) { destination in
            switch destination {
            case .profile: ProfileView()
            case .appearance: AppearanceView()
            case .appLanguage: AppLanguageView()
            case .hadithTranslation: TranslationLanguageView()
            case .readingAndType: ReadingTypeView()
            case .offlineStorage: OfflineStorageView()
            case .notifications: NotificationsView()
            case .subscription: SubscriptionView()
            case .privacyAndData: PrivacyDataView(showSignIn: $showSignIn)
            case .helpAndSupport: HelpSupportView()
            case .aboutAndLegal: AboutLegalView()
            }
        }
        .appNavigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .toolbar(.visible, for: .navigationBar)
        .task {
            library.refresh()
            await loadSubscriptionTier()
        }
    }

    private var accountName: String {
        let full = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? (clerk.user?.username ?? "Account") : full
    }

    @ViewBuilder
    private var profileBadge: some View {
        if let urlString = clerk.user?.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    Image(systemName: "person.crop.circle.fill")
                        .font(.title)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .frame(width: 44, height: 44)
            .clipShape(Circle())
        } else {
            Image(systemName: "person.crop.circle.fill")
                .font(.title)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 44, height: 44)
        }
    }

    private func languageName(for code: String) -> String? {
        SupportedLanguages.all.first(where: { $0.code == code })?.name
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        try? await Clerk.shared.auth.signOut()
        environment.handleSignOut()
    }

    private func loadSubscriptionTier() async {
        guard clerk.session != nil else {
            subscriptionTier = nil
            return
        }
        struct TierRow: Decodable { var subscriptionTier: String? }
        subscriptionTier = try? await environment.convex
            .subscribe(to: "users:getCurrentUser", yielding: TierRow.self)
            .values
            .first(where: { _ in true })?.subscriptionTier
    }
}

/// One native row: monochrome symbol, title, live trailing value, chevron.
private struct SettingsLinkRow: View {
    let destination: SettingsDestination
    var value: String? = nil

    var body: some View {
        NavigationLink(value: destination) {
            HStack(spacing: 12) {
                Image(systemName: destination.systemImage)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 26)
                Text(LocalizedStringKey(destination.title))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .accessibilityIdentifier(destination.accessibilityID)
    }
}
