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
    @State private var showAdminReview = false
    @AppStorage("reader.arabicFontSize") private var arabicFontSize: Double = 26
    @AppStorage("user.preferredLanguage") private var preferredLanguage = "en"

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if clerk.session != nil {
                    AccountCard(showSignIn: $showSignIn, isSigningOut: $isSigningOut, onSignOut: signOut)
                } else {
                    GuestCard(showSignIn: $showSignIn)
                }

                ReadingCard(arabicFontSize: $arabicFontSize, preferredLanguage: $preferredLanguage)

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
    }

    private func signOut() async {
        isSigningOut = true
        defer { isSigningOut = false }
        try? await Clerk.shared.auth.signOut()
        environment.handleSignOut()
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
    let onSignOut: () async -> Void

    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

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
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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

private struct ReadingCard: View {
    @Binding var arabicFontSize: Double
    @Binding var preferredLanguage: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Reading", systemImage: "textformat")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Arabic type size")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Slider(
                    value: $arabicFontSize,
                    in: 18...40,
                    step: 1
                ) {
                    Text("Arabic type size")
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
                Text("\(Int(arabicFontSize)) pt")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Text("نَعْبُدُكَ وَإِيَّاكَ نَسْتَعِينُ")
                    .font(Theme.arabic(arabicFontSize))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .accessibilityIdentifier("settings.arabicSize")

            VStack(alignment: .leading, spacing: 8) {
                Text("Translation language")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                ForEach(SupportedLanguages.all) { language in
                    Button {
                        preferredLanguage = language.code
                    } label: {
                        HStack {
                            Text(language.name)
                                .font(.subheadline)
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                            if preferredLanguage == language.code {
                                Image(systemName: "checkmark")
                                    .font(.caption.weight(.semibold))
                                    .foregroundStyle(Theme.accent)
                            }
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 11)
                        .background(preferredLanguage == language.code ? Theme.accentSoft : Theme.surfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("settings.language.\(language.code)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
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
