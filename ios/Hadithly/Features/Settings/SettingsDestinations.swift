import ClerkKit
import ConvexMobile
import LocalAuthentication
import PhotosUI
import SwiftUI

// MARK: - Shared pieces (native)

// Monochrome: interactive elements resolve to white; semantic colors
// (red destructive, amber bookmark, pink favorite, emerald grade dots and
// success) keep their meaning. No other hue is used for chrome.
private let settingsTint = Color.white

/// Subscription fields decoded from the identity-scoped `users:getCurrentUser`
/// row. Unknown row fields are ignored by synthesis.
private struct SubscriptionStatus: Decodable {
    var subscriptionTier: String?
    var entitlementExpiresAt: Double?
    var aiGenerationsThisMonth: Double?
    var aiGenerationLimit: Double?
}

/// Portable export document from `users:exportCurrentUserData`. Mirrors the
/// backend shape loosely: every collection defaults empty so a future field
/// addition cannot break decoding.
private struct ExportDocument: Codable {
    var generatedAt: Double = 0
    var account: ExportAccount?
    var readerPreferences: ReaderPreferences?
    var savedFolders: [ExportFolder] = []
    var savedItems: [ExportItem] = []
    var readingProgress: [ExportProgress] = []
    var legacy: ExportLegacy?
    var submissions: [ExportSubmission] = []

    struct ExportAccount: Codable {
        var email: String?
        var displayName: String?
        var subscriptionTier: String?
        var createdAt: Double?
    }
    struct ExportFolder: Codable {
        var name: String?
        var createdAt: Double?
        var updatedAt: Double?
    }
    struct ExportHadithRef: Codable {
        var hadithId: String?
        var canonicalId: String?
        var collectionSlug: String?
        var providerHadithId: String?
        var referenceDisplay: String?
        var missing: Bool?
    }
    struct ExportItem: Codable {
        var hadith: ExportHadithRef?
        var bookmarkCreatedAt: Double?
        var favoriteCreatedAt: Double?
        var noteContent: String?
        var noteUpdatedAt: Double?
        var folderName: String?
        var updatedAt: Double?
    }
    struct ExportProgress: Codable {
        var collectionSlug: String?
        var hadith: ExportHadithRef?
        var updatedAt: Double?
    }
    struct ExportLegacyNote: Codable {
        var hadith: ExportHadithRef?
        var content: String?
        var updatedAt: Double?
    }
    struct ExportLegacyRef: Codable {
        var hadith: ExportHadithRef?
        var createdAt: Double?
    }
    struct ExportLegacy: Codable {
        var bookmarks: [ExportLegacyRef] = []
        var favorites: [ExportLegacyRef] = []
        var notes: [ExportLegacyNote] = []
    }
    struct ExportSubmission: Codable {
        var language: String?
        var proposedContent: String?
        var status: String?
        var createdAt: Double?
    }
}

/// Native grouped-list container shared by every destination.
private struct SettingsList<Content: View>: View {
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        List {
            content
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

private func settingsCheckRow(
    label: String,
    selected: Bool,
    onSelect: @escaping () -> Void
) -> some View {
    Button(action: onSelect) {
        HStack {
            Text(label)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            if selected {
                Image(systemName: "checkmark")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(settingsTint)
            }
        }
    }
    .buttonStyle(.plain)
}

private struct SettingsToggleRow: View {
    let title: String
    let footnote: String?
    @Binding var isOn: Bool
    var accessibilityID: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                if let footnote {
                    Text(footnote)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .tint(settingsTint)
        .accessibilityIdentifier(accessibilityID)
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let subtitle: String?
    let systemImage: String
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 26)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.textPrimary)
                    if let subtitle {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
    }
}

// MARK: - Profile

struct ProfileView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var usernameInput = ""
    @State private var notice: String?
    @State private var isSaving = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isUploadingPhoto = false

    var body: some View {
        SettingsList("Profile") {
            Section {
                HStack(spacing: 14) {
                    avatar
                    VStack(alignment: .leading, spacing: 2) {
                        Text(displayName)
                            .font(.headline)
                            .foregroundStyle(Theme.textPrimary)
                        if let email = clerk.user?.primaryEmailAddress?.emailAddress {
                            Text(email)
                                .font(.footnote)
                                .foregroundStyle(Theme.textSecondary)
                        }
                        if clerk.user?.hasImage != true {
                            Text("Avatar is set by your sign-in method.")
                                .font(.caption2)
                                .foregroundStyle(Theme.textSecondary)
                        }
                    }
                    Spacer()
                    PhotosPicker(selection: $photoItem, matching: .images) {
                        Image(systemName: "photo.badge.plus")
                            .font(.title3)
                            .foregroundStyle(settingsTint)
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadingPhoto)
                    .accessibilityIdentifier("settings.profile.changePhoto")
                    .onChange(of: photoItem) { _, item in
                        Task { await uploadPhoto(item) }
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Name") {
                TextField("First name", text: $firstName)
                TextField("Last name", text: $lastName)
                Button {
                    Task { await saveName() }
                } label: {
                    if isSaving {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text("Save name").frame(maxWidth: .infinity)
                    }
                }
                .disabled(isSaving)
                .accessibilityIdentifier("settings.profile.saveName")
            }

            Section {
                LabeledContent("Username", value: clerk.user?.username ?? "Not set")
                TextField("Username", text: $usernameInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button {
                    Task { await saveUsername() }
                } label: {
                    Text("Save username").frame(maxWidth: .infinity)
                }
                .disabled(isSaving)
                .accessibilityIdentifier("settings.profile.saveUsername")
            } footer: {
                Text("Start with a letter; use letters, numbers, and underscores.")
            }

            if let summary = environment.lastSyncSummary {
                Section {
                    Text(summary)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }

            if let notice {
                Section {
                    Text(notice)
                        .font(.footnote)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .task {
            firstName = clerk.user?.firstName ?? ""
            lastName = clerk.user?.lastName ?? ""
            usernameInput = clerk.user?.username ?? ""
        }
    }

    private var displayName: String {
        let full = [clerk.user?.firstName, clerk.user?.lastName]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return full.isEmpty ? (clerk.user?.username ?? "Account") : full
    }

    @ViewBuilder
    private var avatar: some View {
        if let urlString = clerk.user?.imageUrl, let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    initialsBadge
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .accessibilityIdentifier("settings.profile.avatar")
        } else {
            initialsBadge
                .frame(width: 56, height: 56)
                .clipShape(Circle())
        }
    }

    private var initialsBadge: some View {
        ZStack {
            Theme.surfaceElevated
            Text(initials)
                .font(.title3.weight(.semibold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var initials: String {
        let parts = displayName.split(separator: " ")
        let letters = parts.prefix(2).compactMap { $0.first.map(String.init) }
        return letters.joined().uppercased()
    }

    private func saveName() async {
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await clerk.user?.update(.init(
                firstName: firstName.trimmingCharacters(in: .whitespacesAndNewlines),
                lastName: lastName.trimmingCharacters(in: .whitespacesAndNewlines)
            ))
            notice = "Name saved."
        } catch {
            notice = "Could not save your name. Please try again."
        }
    }

    private func saveUsername() async {
        let cleaned = usernameInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.count >= 3 else {
            notice = "Usernames need at least 3 characters."
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await clerk.user?.update(.init(username: cleaned))
            notice = "Username saved."
        } catch {
            notice = "That username is not available."
        }
    }

    private func uploadPhoto(_ item: PhotosPickerItem?) async {
        guard let item else { return }
        isUploadingPhoto = true
        defer { isUploadingPhoto = false }
        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                notice = "Could not read that photo."
                return
            }
            _ = try await clerk.user?.setProfileImage(imageData: data)
            notice = "Profile photo updated."
        } catch {
            notice = "Could not update your photo. Please try again."
        }
    }
}

// MARK: - Appearance

struct AppearanceView: View {
    @Environment(AppEnvironment.self) private var environment

    var body: some View {
        SettingsList("Appearance") {
            Section {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    settingsCheckRow(
                        label: Self.label(theme),
                        selected: environment.preferences.preferences.theme == theme
                    ) {
                        environment.preferences.setTheme(theme)
                    }
                    .accessibilityIdentifier("settings.appearance.\(theme.rawValue)")
                }
            } footer: {
                Text("Applies across the app. The reader previews each theme live.")
            }
        }
    }

    private static func label(_ theme: ReaderTheme) -> String {
        switch theme {
        case .system: "System"
        case .light: "Light"
        case .paper: "Paper"
        case .dark: "Dark"
        }
    }
}

// MARK: - Languages

private struct LanguageListView: View {
    @Environment(AppEnvironment.self) private var environment
    let title: String
    let selection: String
    let accessibilityPrefix: String
    let onSelect: (String) -> Void
    let footer: String

    var body: some View {
        SettingsList(title) {
            Section {
                ForEach(SupportedLanguages.all) { language in
                    settingsCheckRow(
                        label: language.name,
                        selected: selection == language.code
                    ) {
                        onSelect(language.code)
                    }
                    .accessibilityIdentifier("\(accessibilityPrefix).\(language.code)")
                }
            } footer: {
                Text(footer)
            }
        }
    }
}

struct AppLanguageView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        LanguageListView(
            title: "App language",
            selection: environment.preferences.preferences.uiLocale,
            accessibilityPrefix: "settings.uiLanguage",
            onSelect: { environment.preferences.setUILocale($0) },
            footer: "\(SupportedLanguages.all.count) languages available"
        )
    }
}

struct TranslationLanguageView: View {
    @Environment(AppEnvironment.self) private var environment
    var body: some View {
        LanguageListView(
            title: "Hadith translation",
            selection: environment.preferences.preferences.translationLocale,
            accessibilityPrefix: "settings.language",
            onSelect: { environment.preferences.setTranslationLocale($0) },
            footer: "\(SupportedLanguages.all.count) languages available"
        )
    }
}

// MARK: - Reading & type (F2 controls)

struct ReadingTypeView: View {
    @Environment(AppEnvironment.self) private var environment

    private var store: PreferencesStore { environment.preferences }

    var body: some View {
        let preferences = store.preferences
        SettingsList("Reading & type") {
            Section("Arabic type") {
                ForEach(ArabicFont.allCases, id: \.self) { font in
                    settingsCheckRow(
                        label: font.displayName,
                        selected: preferences.arabicFont == font
                    ) {
                        store.setArabicFont(font)
                    }
                    .accessibilityIdentifier("settings.arabicFont.\(font.rawValue)")
                }
            }

            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Slider(
                        value: Binding(
                            get: { store.preferences.arabicFontSize },
                            set: { store.setArabicFontSize($0) }
                        ),
                        in: 18...40,
                        step: 1
                    ) {
                        Text("Arabic type size")
                    } minimumValueLabel: {
                        Text("A").font(.caption).foregroundStyle(Theme.textSecondary)
                    } maximumValueLabel: {
                        Text("A").font(.title3).foregroundStyle(Theme.textSecondary)
                    }
                    .tint(settingsTint)
                    HStack {
                        Text("Size")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                        Text("\(Int(preferences.arabicFontSize)) pt")
                            .font(.subheadline.monospacedDigit())
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Text("نَعْبُدُكَ وَإِيَّاكَ نَسْتَعِينُ")
                        .font(Theme.arabic(preferences.arabicFontSize, preferences.arabicFont))
                        .foregroundStyle(Theme.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .accessibilityIdentifier("settings.arabicSize")
            }

            Section("Reading direction") {
                ForEach(ReadingDirection.allCases, id: \.self) { direction in
                    settingsCheckRow(
                        label: Self.directionLabel(direction),
                        selected: preferences.readingDirection == direction
                    ) {
                        store.setReadingDirection(direction)
                    }
                    .accessibilityIdentifier("settings.readingDirection.\(direction.rawValue)")
                }
            }

            Section {
                SettingsToggleRow(
                    title: "Arabic text",
                    footnote: nil,
                    isOn: Binding(
                        get: { store.preferences.arabicVisible },
                        set: { store.setVisibility(arabic: $0) }
                    ),
                    accessibilityID: "settings.visibility.arabic"
                )
                SettingsToggleRow(
                    title: "Translation",
                    footnote: nil,
                    isOn: Binding(
                        get: { store.preferences.translationVisible },
                        set: { store.setVisibility(translation: $0) }
                    ),
                    accessibilityID: "settings.visibility.translation"
                )
            } footer: {
                Text("At least one layer stays visible.")
            }

            Section("Saved") {
                SettingsToggleRow(
                    title: "Confirm before removing",
                    footnote: "Ask before removing saved items",
                    isOn: Binding(
                        get: { environment.savedSafety.confirmsRemoval },
                        set: { environment.savedSafety.confirmsRemoval = $0 }
                    ),
                    accessibilityID: "settings.confirmSavedRemoval"
                )
            }
        }
    }

    private static func directionLabel(_ direction: ReadingDirection) -> String {
        switch direction {
        case .auto: "Automatic"
        case .rtl: "Right to left"
        case .ltr: "Left to right"
        }
    }
}

// MARK: - Offline storage (locked until O2, no dead rows)

struct OfflineStorageView: View {
    @State private var cacheSize: String = "…"
    @State private var clearNotice: String?
    @State private var showLearnMore = false

    var body: some View {
        SettingsList("Offline storage") {
            Section {
                Button("How offline will work") {
                    showLearnMore = true
                }
                .accessibilityIdentifier("settings.offline.learnMore")
            } header: {
                Text("Offline collections")
            } footer: {
                Text("Full offline downloads arrive in the next update (O2). Reading, Saved items, and positions already work offline from your recent pages.")
            }

            Section {
                LabeledContent("Used", value: cacheSize)
                Button("Clear temporary cache") {
                    clearCache()
                }
                .accessibilityIdentifier("settings.offline.clearCache")
                if let clearNotice {
                    Text(clearNotice)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Temporary cache")
            } footer: {
                Text("Clearing never deletes bookmarks, favorites, notes, or reading progress.")
            }

            Section {
                Button("Open app settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        UIApplication.shared.open(url)
                    }
                }
                .accessibilityIdentifier("settings.offline.systemSettings")
            } footer: {
                Text("See Hadithly's total device storage from the system settings page.")
            }
        }
        .task { await refreshSize() }
        .sheet(isPresented: $showLearnMore) {
            NavigationStack {
                List {
                    Section {
                        Text("Hadithly will ship versioned offline collections: a base Arabic dump plus translation packs, each checksummed and licensed. Downloads validate before activating and keep your Saved items and reading positions intact.")
                        Text("Until then, your recent pages stay readable offline automatically.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle("How offline will work")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }

    private func refreshSize() async {
        let bytes = await Task.detached { Self.temporaryBytes() }.value
        cacheSize = Self.format(bytes: bytes)
    }

    private func clearCache() {
        URLCache.shared.removeAllCachedResponses()
        let fileManager = FileManager.default
        for directory in [fileManager.temporaryDirectory] {
            for url in (try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )) ?? [] {
                try? fileManager.removeItem(at: url)
            }
        }
        clearNotice = "Temporary cache cleared."
        Task { await refreshSize() }
    }

    private nonisolated static func temporaryBytes() -> Int {
        let fileManager = FileManager.default
        var total = 0
        for directory in [fileManager.temporaryDirectory] {
            guard let urls = try? fileManager.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: [.fileSizeKey]
            ) else { continue }
            for url in urls {
                total += (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            }
        }
        return total
    }

    private static func format(bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return "\(bytes / 1024) KB" }
        return String(format: "%.1f MB", Double(bytes) / 1024 / 1024)
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @Environment(Clerk.self) private var clerk
    @Environment(AppEnvironment.self) private var environment
    @Environment(PushNotificationManager.self) private var push

    @AppStorage("notifications.dailyEnabled") private var enabled = false
    @AppStorage("notifications.dailyTime") private var dailyTime = "08:00"
    @State private var isRegistering = false
    @State private var statusLine: String?

    var body: some View {
        SettingsList("Notifications") {
            if clerk.session != nil {
                Section {
                    Toggle(isOn: Binding(
                        get: { enabled },
                        set: { newValue in
                            Task { await setEnabled(newValue) }
                        }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Daily hadith")
                                .foregroundStyle(Theme.textPrimary)
                            if let statusLine {
                                Text(statusLine)
                                    .font(.caption)
                                    .foregroundStyle(Theme.textSecondary)
                            }
                        }
                    }
                    .tint(settingsTint)
                    .disabled(isRegistering)
                    .accessibilityIdentifier("settings.notificationsToggle")

                    if enabled {
                        DatePicker(
                            "Time",
                            selection: Binding(
                                get: { Self.time(from: dailyTime) ?? .now },
                                set: { newValue in setDailyTime(newValue) }
                            ),
                            displayedComponents: .hourAndMinute
                        )
                        .tint(settingsTint)
                        .accessibilityIdentifier("settings.notificationsTime")
                    }
                } footer: {
                    Text("One quiet reminder with the selected translation.")
                }
            } else {
                Section {
                    Text("Sign in to receive the daily hadith on this device.")
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("settings.notifications.signedOut")
                }
            }
        }
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
        case .registered: "This device is registered."
        case .notAuthorized: "Notifications are not allowed in system settings."
        case .failed(let message): message
        case .unknown: nil
        }
    }
}

// MARK: - Subscription

struct SubscriptionView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @State private var status: SubscriptionStatus?
    @State private var isRestoring = false
    @State private var showPaywall = false

    var body: some View {
        SettingsList("Subscription") {
            if clerk.session != nil {
                Section {
                    LabeledContent("Plan", value: SettingsSubscription.displayName(tier: status?.subscriptionTier))
                    if let line = SettingsSubscription.quotaLine(
                        used: status?.aiGenerationsThisMonth,
                        limit: status?.aiGenerationLimit
                    ) {
                        LabeledContent("AI translations", value: line)
                    }
                    if let expires = status?.entitlementExpiresAt, expires > 0 {
                        LabeledContent(
                            "Renews",
                            value: Date(timeIntervalSince1970: expires / 1000).formatted(date: .abbreviated, time: .omitted)
                        )
                    }
                    if environment.purchases.hasProEntitlement {
                        Label("Pro is active on this device", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                } footer: {
                    Text("Pro unlocks 100 AI translations per rolling week. Reading, saved items, and existing translations stay free.")
                }

                Section {
                    Button("View plans") { showPaywall = true }
                        .accessibilityIdentifier("settings.subscription.plans")
                    Button {
                        Task {
                            isRestoring = true
                            defer { isRestoring = false }
                            _ = await environment.purchases.restore()
                            await loadStatus()
                        }
                    } label: {
                        Text(isRestoring ? "Restoring…" : "Restore purchases")
                    }
                    .disabled(isRestoring)
                    .accessibilityIdentifier("settings.subscription.restore")
                    Link("Manage subscription", destination: SettingsLinks.appleSubscriptions)
                }
            } else {
                Section {
                    Text("Sign in to see your subscription. Purchases stay attached to your Hadithly account across devices.")
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("settings.subscription.signedOut")
                }
            }
        }
        .task { await loadStatus() }
        .sheet(isPresented: $showPaywall) {
            QuotaPaywallView {}
        }
    }

    private func loadStatus() async {
        guard clerk.session != nil else { return }
        status = try? await environment.convex
            .subscribe(to: "users:getCurrentUser", yielding: SubscriptionStatus.self)
            .values
            .first(where: { _ in true })
    }
}

// MARK: - Privacy & data (export + deletion)

struct PrivacyDataView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @Binding var showSignIn: Bool

    @State private var showExportConfirm = false
    @State private var isExporting = false
    @State private var exportURL: URL?
    @State private var exportError: String?
    @State private var showDeleteConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deletionError: String?

    var body: some View {
        SettingsList("Privacy & data") {
            Section {
                if clerk.session != nil {
                    Button {
                        showExportConfirm = true
                    } label: {
                        Text(isExporting ? "Preparing…" : "Export my data")
                    }
                    .disabled(isExporting)
                    .accessibilityIdentifier("settings.export")
                    if let exportURL {
                        ShareLink(item: exportURL) {
                            Label("Share export file", systemImage: "square.and.arrow.up")
                        }
                        .accessibilityIdentifier("settings.export.share")
                    }
                    if let exportError {
                        Text(exportError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                } else {
                    Button("Sign in") { showSignIn = true }
                        .accessibilityIdentifier("settings.signin")
                }
            } header: {
                Text("Your data")
            } footer: {
                Text("Export your profile, preferences, Saved items, folders, reading progress, and your own contributions as JSON. Guest data never leaves this device.")
            }

            Section("Policies") {
                SettingsLinkRow(
                    title: "Privacy Policy",
                    subtitle: nil,
                    systemImage: "lock.shield",
                    destination: SettingsLinks.privacy
                )
                SettingsLinkRow(
                    title: "Terms of Use",
                    subtitle: nil,
                    systemImage: "doc.text",
                    destination: SettingsLinks.terms
                )
                SettingsLinkRow(
                    title: "How deletion works",
                    subtitle: "hadithly.app",
                    systemImage: "trash",
                    destination: SettingsLinks.deleteAccountInfo
                )
                .accessibilityIdentifier("settings.deletionInfo")
            }

            if clerk.session != nil {
                Section {
                    Button(role: .destructive) {
                        showDeleteConfirmation = true
                    } label: {
                        if isDeletingAccount {
                            ProgressView().frame(maxWidth: .infinity)
                        } else {
                            Text("Delete account")
                        }
                    }
                    .foregroundStyle(.red)
                    .disabled(isDeletingAccount)
                    .accessibilityIdentifier("settings.deleteAccount")
                } footer: {
                    Text(SettingsDeletionCopy.subscriptionWarning)
                }
            }
        }
        .confirmationDialog(
            "Export your data?",
            isPresented: $showExportConfirm,
            titleVisibility: .visible
        ) {
            Button("Export after device check") {
                Task { await exportWithReauth() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file contains only your portable data. Confirm with Face ID, Touch ID, or your device passcode when asked.")
        }
        .confirmationDialog(
            SettingsDeletionCopy.title,
            isPresented: $showDeleteConfirmation,
            titleVisibility: .visible
        ) {
            Button("Delete account and data", role: .destructive) {
                Task { await deleteAccount() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(SettingsDeletionCopy.message) \(SettingsDeletionCopy.subscriptionWarning)")
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

    /// Device reauthentication precedes the export whenever the device can
    /// enforce it; the query itself additionally requires a valid Clerk
    /// session, so an expired sign-in forces a fresh sign-in first.
    private func exportWithReauth() async {
        isExporting = true
        defer { isExporting = false }
        let context = LAContext()
        var authError: NSError?
        if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
            do {
                _ = try await context.evaluatePolicy(
                    .deviceOwnerAuthentication,
                    localizedReason: "Confirm it is you before exporting your data."
                )
            } catch {
                exportError = "Export cancelled: device check did not pass."
                return
            }
        }
        do {
            guard let document = try await environment.convex
                .subscribe(to: "users:exportCurrentUserData", yielding: ExportDocument.self)
                .values
                .first(where: { _ in true })
            else {
                exportError = "Export is unavailable right now."
                return
            }
            for fragment in SettingsExport.forbiddenFragments {
                let json = String(data: (try? JSONEncoder().encode(document)) ?? Data(), encoding: .utf8) ?? ""
                assert(!json.contains(fragment), "Export leaked \(fragment)")
            }
            let data = try JSONEncoder().encode(document)
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(SettingsExport.fileName())
            try data.write(to: url, options: .atomic)
            exportURL = url
            exportError = nil
        } catch {
            exportError = "Export failed. Please try again."
        }
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

// MARK: - Help & support

struct HelpSupportView: View {
    var body: some View {
        SettingsList("Help & support") {
            Section {
                SettingsLinkRow(
                    title: "FAQ & guides",
                    subtitle: "hadithly.app",
                    systemImage: "book.pages",
                    destination: SettingsLinks.support
                )
                SettingsLinkRow(
                    title: "Contact support",
                    subtitle: SettingsLinks.supportEmail,
                    systemImage: "envelope",
                    destination: URL(string: "mailto:\(SettingsLinks.supportEmail)?subject=Hadithly%20support")!
                )
                .accessibilityIdentifier("settings.help.contact")
                SettingsLinkRow(
                    title: "Report a translation issue",
                    subtitle: "Include the collection and hadith number",
                    systemImage: "exclamationmark.bubble",
                    destination: URL(string: "mailto:\(SettingsLinks.supportEmail)?subject=Translation%20issue")!
                )
                ShareLink(item: URL(string: "https://hadithly.app")!) {
                    HStack(spacing: 12) {
                        Image(systemName: "square.and.arrow.up")
                            .foregroundStyle(Theme.textPrimary)
                            .frame(width: 26)
                        Text("Share Hadithly")
                            .foregroundStyle(Theme.textPrimary)
                        Spacer()
                    }
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("settings.help.share")
            }
        }
    }
}

// MARK: - About & legal

struct AboutLegalView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showLicenses = false

    var body: some View {
        SettingsList("About & legal") {
            Section {
                LabeledContent("Version", value: SettingsLinks.appVersion)
                Text("A quiet reader for the seven major hadith collections. Arabic text is licensed from its sources; AI translations are always labeled.")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            } header: {
                Text("Hadithly")
            }

            Section("Legal") {
                Button("Font licenses") { showLicenses = true }
                    .accessibilityIdentifier("settings.about.licenses")
                if let privacyURL = environment.config.privacyPolicyURL {
                    Link("Privacy Policy", destination: privacyURL)
                } else {
                    Link("Privacy Policy", destination: SettingsLinks.privacy)
                }
                if let termsURL = environment.config.termsOfUseURL {
                    Link("Terms of Use", destination: termsURL)
                } else {
                    Link("Terms of Use", destination: SettingsLinks.terms)
                }
            }
        }
        .sheet(isPresented: $showLicenses) {
            NavigationStack {
                List {
                    Section {
                        Text("Arabic reading faces — Amiri, Scheherazade New, and Noto Naskh Arabic — are licensed under the SIL Open Font License 1.1 (https://openfontlicense.org). Full license records live in docs/FONT_LICENSES.md.")
                        Text("Hadith source identity, authenticity scope, and license records travel with every text. A technically accessible source is not automatically reusable.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle("Licenses")
                .navigationBarTitleDisplayMode(.inline)
            }
        }
    }
}
