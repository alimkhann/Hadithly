import SwiftUI
import ClerkKit
import ConvexMobile

/// Settings: account, reading preferences, and the daily hadith notification.
struct SettingsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @Environment(UserLibraryModel.self) private var library
    @Environment(PushNotificationManager.self) private var push

    @State private var isSigningOut = false
    @State private var isDeletingAccount = false
    @State private var showDeleteConfirmation = false
    @State private var deletionError: String?
    @State private var showAdminReview = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if clerk.session != nil {
                    AccountCard(
                        showSignIn: $showSignIn,
                        isSigningOut: $isSigningOut,
                        isDeletingAccount: $isDeletingAccount,
                        showDeleteConfirmation: $showDeleteConfirmation,
                        onSignOut: signOut
                    )
                } else {
                    GuestCard(showSignIn: $showSignIn)
                }

                ReadingCard()

                NotificationCard()

                if environment.canModerate {
                    AdminModerationCard {
                        showAdminReview = true
                    }
                }

                #if DEBUG
                GuestDataDebugCard()
                #endif
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .task { library.refresh() }
        .sheet(isPresented: $showAdminReview) {
            AdminReviewSheet()
                .presentationDetents([.large])
        }
        .confirmationDialog(
            "Delete account permanently?",
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account and data", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes your synced bookmarks, favorites, notes, reading progress, submissions, and sign-in. It cannot be undone. Store subscriptions are not cancelled automatically.")
        }
        .alert(
            "Account deletion failed",
            isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )
        ) {
            Button("OK") { deletionError = nil }
        } message: {
            Text(deletionError ?? "Please try again.")
        }
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        try? await Clerk.shared.auth.signOut()
        environment.handleSignOut()
    }

    private func deleteAccount() async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await environment.deleteAccount()
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

private struct AdminModerationCard: View {
    let openReview: () -> Void

    var body: some View {
        Button(action: openReview) {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.shield")
                    .font(.title3)
                    .foregroundStyle(Theme.accent)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Translation review")
                        .font(.headline)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Approve AI-reviewed contributions")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(16)
            .background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("settings.translationReview")
    }
}

// MARK: - Account

private struct AccountCard: View {
    @Binding var showSignIn: Bool
    @Binding var isSigningOut: Bool
    @Binding var isDeletingAccount: Bool
    @Binding var showDeleteConfirmation: Bool
    let onSignOut: () async -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @State private var showUsernameEditor = false
    @State private var usernameInput = ""
    @State private var usernameError: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Account", systemImage: "person.crop.circle")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if let user = clerk.user {
                Text([user.firstName, user.lastName].compactMap { $0 }.joined(separator: " "))
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                if let email = user.primaryEmailAddress?.emailAddress {
                    Text(email)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }

                Button {
                    usernameInput = user.username ?? ""
                    showUsernameEditor = true
                } label: {
                    HStack {
                        Text("Username")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                        Spacer()
                        Text(user.username ?? "Not set")
                            .font(.footnote)
                            .foregroundStyle(Theme.textPrimary)
                        Image(systemName: "pencil")
                            .font(.footnote)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.username")

                if let usernameError {
                    Text(usernameError)
                        .font(.caption)
                        .foregroundStyle(Theme.destructive)
                }
            }

            if let summary = environment.lastSyncSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                Task { await onSignOut() }
            } label: {
                if isSigningOut {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                } else {
                    Text("Sign out")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
            }
            .buttonStyle(.plain)
            .background(Theme.surfaceElevated)
            .foregroundStyle(Theme.textPrimary)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .padding(.top, 4)
            .accessibilityIdentifier("settings.signout")

            Link(
                "Manage subscription",
                destination: URL(string: "https://apps.apple.com/account/subscriptions")!
            )
            .font(.footnote.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .frame(maxWidth: .infinity)

            Button(role: .destructive) {
                showDeleteConfirmation = true
            } label: {
                if isDeletingAccount {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                } else {
                    Text("Delete account")
                        .font(.footnote.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(.red)
            .disabled(isSigningOut || isDeletingAccount)
            .accessibilityIdentifier("settings.deleteAccount")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .alert("Set your username", isPresented: $showUsernameEditor) {
            TextField("Username", text: $usernameInput)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Save") {
                Task { await saveUsername() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Start with a letter; use letters, numbers, and underscores.")
        }
    }

    private func saveUsername() async {
        let cleaned = usernameInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.count >= 3 else {
            usernameError = "Usernames need at least 3 characters."
            return
        }
        do {
            _ = try await clerk.user?.update(.init(username: cleaned))
            usernameError = nil
        } catch {
            usernameError = "That username is not available."
        }
    }
}

private struct GuestCard: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reading as a guest", systemImage: "person.crop.circle.badge.questionmark")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            Text("Everything you need to read works without an account. Sign in to carry your bookmarks, favorites, and notes across devices.")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)

            if let summary = environment.lastSyncSummary {
                Text(summary)
                    .font(.footnote)
                    .foregroundStyle(Theme.textSecondary)
            }

            Button {
                showSignIn = true
            } label: {
                Text("Sign in")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Theme.accent)
                    .foregroundStyle(.black)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .padding(.top, 4)
            .accessibilityIdentifier("settings.signin")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

// MARK: - Reading preferences

/// Temporary minimal control surface for the F2 preference contracts. S1 owns
/// the final Settings screen; R4 owns the full reader typography UI.
private struct ReadingCard: View {
    @Environment(AppEnvironment.self) private var environment

    private var store: PreferencesStore { environment.preferences }

    var body: some View {
        let preferences = store.preferences
        VStack(alignment: .leading, spacing: 12) {
            Label(String(localized: "Reading"), systemImage: "textformat")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Arabic type size"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Slider(
                    value: Binding(
                        get: { store.preferences.arabicFontSize },
                        set: { store.setArabicFontSize($0) }
                    ),
                    in: 18...40,
                    step: 1
                ) {
                    Text(String(localized: "Arabic type size"))
                } minimumValueLabel: {
                    Text("A")
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                } maximumValueLabel: {
                    Text("A")
                        .font(.title3)
                        .foregroundStyle(Theme.textSecondary)
                }
                .tint(Theme.accent)
                Text("\(Int(preferences.arabicFontSize)) pt")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Text("نَعْبُدُكَ وَإِيَّاكَ نَسْتَعِينُ")
                    .font(Theme.arabic(preferences.arabicFontSize))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .accessibilityIdentifier("settings.arabicSize")

            languageSection(
                title: String(localized: "Hadith translation"),
                selection: preferences.translationLocale,
                accessibilityPrefix: "settings.language"
            ) { store.setTranslationLocale($0) }

            languageSection(
                title: String(localized: "App language"),
                selection: preferences.uiLocale,
                accessibilityPrefix: "settings.uiLanguage"
            ) { store.setUILocale($0) }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Reading direction"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(ReadingDirection.allCases, id: \.self) { direction in
                    optionRow(
                        label: Self.directionLabel(direction),
                        selected: preferences.readingDirection == direction
                    ) {
                        store.setReadingDirection(direction)
                    }
                    .accessibilityIdentifier("settings.readingDirection.\(direction.rawValue)")
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                Text(String(localized: "Arabic text"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Toggle(String(localized: "Arabic text"), isOn: Binding(
                    get: { store.preferences.arabicVisible },
                    set: { store.setVisibility(arabic: $0) }
                ))
                .tint(Theme.accent)
                .accessibilityIdentifier("settings.visibility.arabic")

                Text(String(localized: "Translation"))
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Toggle(String(localized: "Translation"), isOn: Binding(
                    get: { store.preferences.translationVisible },
                    set: { store.setVisibility(translation: $0) }
                ))
                .tint(Theme.accent)
                .accessibilityIdentifier("settings.visibility.translation")
            }

            Text("\(SupportedLanguages.all.count) languages available")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func languageSection(
        title: String,
        selection: String,
        accessibilityPrefix: String,
        onSelect: @escaping (String) -> Void
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            ForEach(SupportedLanguages.all) { language in
                optionRow(
                    label: language.name,
                    selected: selection == language.code
                ) {
                    onSelect(language.code)
                }
                .accessibilityIdentifier("\(accessibilityPrefix).\(language.code)")
            }
        }
    }

    private func optionRow(
        label: String,
        selected: Bool,
        onSelect: @escaping () -> Void
    ) -> some View {
        Button(action: onSelect) {
            HStack {
                Text(label)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(selected ? Theme.accentSoft : Theme.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private static func directionLabel(_ direction: ReadingDirection) -> String {
        switch direction {
        case .auto: return String(localized: "Automatic")
        case .rtl: return String(localized: "Right to left")
        case .ltr: return String(localized: "Left to right")
        }
    }
}

// MARK: - Daily hadith notification

private struct NotificationCard: View {
    @Environment(Clerk.self) private var clerk
    @Environment(AppEnvironment.self) private var environment
    @Environment(PushNotificationManager.self) private var push

    @AppStorage("notifications.dailyEnabled") private var enabled = false
    @AppStorage("notifications.dailyTime") private var dailyTime = defaultTime
    @State private var isRegistering = false
    @State private var statusLine: String?

    private static let defaultTime = "08:00"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Daily hadith", systemImage: "bell")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            if clerk.session != nil {
                Toggle(isOn: Binding(
                    get: { enabled },
                    set: { newValue in
                        Task { await setEnabled(newValue) }
                    }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send me a hadith every day")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                        if let statusLine {
                            Text(statusLine)
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                }
                .tint(Theme.accent)
                .disabled(isRegistering)
                .accessibilityIdentifier("settings.notificationsToggle")

                if enabled {
                    DatePicker(
                        "Time",
                        selection: Binding(
                            get: { Self.time(from: dailyTime) ?? referenceTime },
                            set: { newValue in setDailyTime(newValue) }
                        ),
                        displayedComponents: .hourAndMinute
                    )
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                    .tint(Theme.accent)
                    .accessibilityIdentifier("settings.notificationsTime")
                }
            } else {
                Text("Sign in to receive the daily hadith on this device.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var referenceTime: Date {
        Self.time(from: Self.defaultTime) ?? .now
    }

    private static func time(from string: String) -> Date? {
        let parts = string.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return Calendar.current.date(
            bySettingHour: parts[0],
            minute: parts[1],
            second: 0,
            of: .now
        )
    }

    private static func string(from date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 8, parts.minute ?? 0)
    }

    private func setEnabled(_ newValue: Bool) async {
        isRegistering = true
        defer { isRegistering = false }
        if newValue {
            let granted = await push.requestAuthorizationAndRegister()
            guard granted else {
                statusLine = "Notifications are not allowed in system settings."
                enabled = false
                return
            }
            statusLine = pushStateLine
        } else {
            statusLine = nil
        }
        enabled = newValue
        await savePreferences(enabled: newValue)
    }

    private func setDailyTime(_ date: Date) {
        dailyTime = Self.string(from: date)
        Task { await savePreferences(enabled: enabled) }
    }

    private func savePreferences(enabled: Bool) async {
        let tzOffsetMinutes = Double(-TimeZone.current.secondsFromGMT() / 60)
        try? await environment.convex.mutation(
            "library:setDailyNotification",
            with: [
                "enabled": enabled as ConvexEncodable?,
                "dailyTime": dailyTime as ConvexEncodable?,
                "tzOffsetMinutes": tzOffsetMinutes as ConvexEncodable?,
            ]
        )
    }

    private var pushStateLine: String? {
        switch push.state {
        case .registered: return "This device is registered."
        case .notAuthorized: return "Notifications are not allowed in system settings."
        case .failed(let message): return message
        case .unknown: return nil
        }
    }
}

#if DEBUG
/// Development-only helpers to exercise guest mode and the sign-in merge.
private struct GuestDataDebugCard: View {
    @Environment(GuestDataStore.self) private var guestData

    /// A real hadith from the dev deployment, used to seed a mergeable item.
    private let sampleHadithId = "jn7fxd3z54153q9j13kmhgzkv18df2zd"

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Debug · guest data", systemImage: "ladybug")
                .font(.headline)
                .foregroundStyle(Theme.textSecondary)

            Text("Local guest items: \(guestData.itemCount)")
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 8) {
                Button("Seed bookmark") {
                    guestData.addBookmark(hadithId: sampleHadithId)
                }
                .buttonStyle(.bordered)

                Button("Seed note") {
                    guestData.addNote(hadithId: sampleHadithId, content: "Guest note written on-device.")
                }
                .buttonStyle(.bordered)
            }
            .tint(Theme.accent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
#endif
