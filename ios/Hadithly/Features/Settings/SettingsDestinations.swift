import ClerkKit
import ConvexMobile
import LocalAuthentication
import PhotosUI
import SwiftUI

// MARK: - Shared pieces (native)

// Monochrome: interactive elements resolve to white; semantic colors
// (red destructive, amber bookmark, pink favorite, emerald grade dots and
// success) keep their meaning. No other hue is used for chrome.
private var settingsTint: Color { Theme.accent }

/// Subscription fields decoded from the identity-scoped `users:getCurrentUser`
/// row. Unknown row fields are ignored by synthesis.
private struct SubscriptionStatus: Decodable {
    var subscriptionTier: String?
    var entitlementExpiresAt: Double?
    var phase: String?
    var store: String?
}

/// Native grouped-list container shared by every destination.
struct SettingsList<Content: View>: View {
    @Environment(\.readerPalette) private var palette
    let title: String
    let content: Content
    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }
    var body: some View {
        List {
            content
                .listRowBackground(palette.surface)
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(palette.background)
        .appNavigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let footnote: String?
    @Binding var isOn: Bool
    var accessibilityID: String

    var body: some View {
        Toggle(isOn: $isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(LocalizedStringKey(title))
                    .foregroundStyle(Theme.textPrimary)
                if let footnote {
                    Text(LocalizedStringKey(footnote))
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .toggleStyle(SettingsToggleStyle())
        .accessibilityIdentifier(accessibilityID)
    }
}

/// Neutral, palette-aware switch that never turns its full track white.
private struct SettingsToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack {
            configuration.label
            Spacer(minLength: 12)
            Button { configuration.isOn.toggle() } label: {
                Capsule()
                    .fill(configuration.isOn ? Theme.surfaceElevated : Theme.surface)
                    .overlay(Capsule().stroke(Theme.textSecondary.opacity(0.35), lineWidth: 1))
                    .frame(width: 50, height: 30)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(configuration.isOn ? Theme.textPrimary : Theme.textSecondary)
                            .frame(width: 24, height: 24)
                            .padding(3)
                    }
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text(LocalizedStringKey(configuration.isOn ? "On" : "Off")))
        }
    }
}

private struct SettingsLinkRow: View {
    let title: LocalizedStringKey
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
    @Environment(\.locale) private var uiLocale
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
            } header: {
                Text("Username")
            } footer: {
                Text("Start with a letter; use letters, numbers, and underscores.")
            }

            if let notice {
                Section {
                    ProfileStatusNotice(source: notice)
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
        return full.isEmpty ? (clerk.user?.username ?? AppLocalization.string("Account", locale: uiLocale)) : full
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
            notice = ProfileNotice.nameSaved.rawValue
        } catch {
            notice = ProfileNotice.nameFailed.rawValue
        }
    }

    private func saveUsername() async {
        let cleaned = usernameInput
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        guard cleaned.count >= 3 else {
            notice = ProfileNotice.tooShort.rawValue
            return
        }
        isSaving = true
        defer { isSaving = false }
        do {
            _ = try await clerk.user?.update(.init(username: cleaned))
            notice = ProfileNotice.usernameSaved.rawValue
        } catch {
            notice = ProfileNotice.usernameFailure(code: (error as? ClerkAPIError)?.code).rawValue
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
            Section("App appearance") {
                Picker("App appearance", selection: Binding(get: { environment.preferences.preferences.appTheme }, set: { environment.preferences.setTheme($0) })) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Text(Self.label(theme)).tag(theme).accessibilityIdentifier("settings.appearance.\(theme.rawValue)")
                    }
                }.pickerStyle(.inline).labelsHidden()
            }
            Section {
                Toggle("Use a separate reader appearance", isOn: Binding(get: { environment.preferences.preferences.usesSeparateReaderTheme }, set: { environment.preferences.setSeparateReaderTheme($0) }))
                    .accessibilityIdentifier("settings.appearance.separateReader")
            }
            if environment.preferences.preferences.usesSeparateReaderTheme {
                Section("Reader appearance") {
                    Picker("Reader appearance", selection: Binding(get: { environment.preferences.preferences.readerTheme }, set: { environment.preferences.setReaderTheme($0) })) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            Text(Self.label(theme)).tag(theme).accessibilityIdentifier("settings.readerAppearance.\(theme.rawValue)")
                        }
                    }.pickerStyle(.inline).labelsHidden()
                }
            }
        }
    }

    private static func label(_ theme: ReaderTheme) -> LocalizedStringKey {
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
    @Environment(\.layoutDirection) private var layoutDirection
    let title: String
    let selection: String
    let accessibilityPrefix: String
    let onSelect: (String) -> Void
    let footer: LocalizedStringKey

    var body: some View {
        SettingsList(title) {
            Section {
                Picker("", selection: Binding(
                    get: { selection },
                    set: onSelect
                )) {
                    ForEach(SupportedLanguages.all) { language in
                        Text("\(language.flag)  \(language.name)")
                            .tag(language.code)
                            .accessibilityIdentifier("\(accessibilityPrefix).\(language.code)")
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
            } footer: {
                Text(footer)
            }
        }
        .id(layoutDirection)
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
    @Environment(\.readerPalette) private var palette

    var body: some View {
        SettingsList("Reading & type") {
            ReaderPreferenceSections(prefix: "settings")
            Section("Reading direction") {
                Picker("Reading direction", selection: Binding(
                    get: { environment.preferences.preferences.readingDirection },
                    set: { environment.preferences.setReadingDirection($0) }
                )) {
                    Text("Automatic").tag(ReadingDirection.auto)
                    Text("Right to left").tag(ReadingDirection.rtl)
                    Text("Left to right").tag(ReadingDirection.ltr)
                }
                .pickerStyle(.inline)
                .labelsHidden()
            }
            Section("Saved") {
                Toggle(isOn: Binding(
                        get: { environment.savedSafety.confirmsRemoval },
                        set: { environment.savedSafety.confirmsRemoval = $0 }
                    )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Confirm before removing")
                        Text("Ask before removing saved items")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                .tint(palette.textSecondary)
                .accessibilityIdentifier("settings.confirmSavedRemoval")
            }
        }
    }
}

// MARK: - Offline storage (O2 download management)

struct OfflineStorageView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var cacheSize: String = "…"
    @State private var clearNotice: String?
    @State private var actionNotice: String?
    @State private var showLearnMore = false

    private var locale: String {
        environment.preferences.preferences.translationLocale
    }

    var body: some View {
        SettingsList("Offline storage") {
            Section {
                LabeledContent("Downloads", value: OfflineModels.format(bytes: environment.offline.offlineBytes()))
                if let free = environment.offline.freeBytes() {
                    LabeledContent("Free", value: OfflineModels.format(bytes: free))
                }
                Toggle("Wi-Fi only", isOn: Binding(
                    get: { environment.offline.registry.wifiOnly },
                    set: { environment.offline.setWifiOnly($0) }
                ))
                .accessibilityIdentifier("settings.offline.wifiOnly")
                Button("How offline works") {
                    showLearnMore = true
                }
                .accessibilityIdentifier("settings.offline.learnMore")
                if let actionNotice {
                    Text(actionNotice)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
                if let lastError = environment.offline.lastError {
                    OfflineStatusNotice(source: lastError)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Offline collections")
            } footer: {
                Text("Base Arabic files plus a translation pack for your language. Every file is checksummed and licensed before it activates. The previous copy stays readable until the replacement and your saved positions check out.")
            }

            Section("Collections") {
            ForEach(Array(ReaderModels.collections.enumerated()), id: \.element.slug) { index, collection in
                    OfflineCollectionRow(
                        slug: collection.slug,
                        name: collection.name,
                        position: index + 1,
                        locale: locale,
                        onNotice: { actionNotice = $0 }
                    )
                }
            }

            Section {
                LabeledContent("Used", value: cacheSize)
                Button("Clear temporary cache") {
                    clearCache()
                }
                .accessibilityIdentifier("settings.offline.clearCache")
                if let clearNotice {
                    OfflineStatusNotice(source: clearNotice)
                        .font(.caption)
                        .foregroundStyle(Theme.textSecondary)
                }
            } header: {
                Text("Temporary cache")
            } footer: {
                Text("Clearing never deletes bookmarks, favorites, notes, reading progress, or downloaded collections.")
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
        .task {
            await environment.offline.refresh(translationLocale: locale)
        }
        .sheet(isPresented: $showLearnMore) {
            NavigationStack {
                List {
                    Section {
                        Text("Hadithly ships versioned offline collections: a base Arabic dump plus translation packs, each checksummed and licensed. Downloads validate before activating and keep your Saved items and reading positions intact.")
                        Text("Deleting a download removes files only. Your bookmarks, notes, and positions stay.")
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Theme.background)
                .navigationTitle("How offline works")
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

/// One collection's download state and actions. Base and translation-pack
/// rows share the same state machine; deleting either removes files only.
struct OfflineCollectionRow: View {
    @Environment(\.locale) private var uiLocale
    @Environment(AppEnvironment.self) private var environment
    let slug: String
    let name: String
    let position: Int
    let locale: String
    let onNotice: (String) -> Void
    @State private var displayedProgress = 0.0

    var body: some View {
        let store = environment.offline
        let status = store.status(for: slug, translationLocale: locale)
        HStack(spacing: 12) {
            CollectionCover(position: position).frame(width: 40, height: 58)
            VStack(alignment: .leading, spacing: 6) {
            Text(name).foregroundStyle(Theme.textPrimary)
            Text(statusLine(for: status, store: store)).font(.caption).foregroundStyle(Theme.textSecondary)
            if case .downloading = status {
                ProgressView(value: displayedProgress)
                    .accessibilityIdentifier("settings.offline.\(slug).progress")
            } else if case .queued(let fraction) = status, fraction > 0 {
                ProgressView(value: displayedProgress)
                    .accessibilityIdentifier("settings.offline.\(slug).progress")
            }
            }
            Spacer()
            actionButtons(for: status, store: store)
        }
        .onChange(of: fraction(status)) { _, next in withAnimation(.easeOut(duration: 0.25)) { displayedProgress = next } }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("settings.offline.\(slug).row")
    }

    private func fraction(_ status: OfflineCollectionStatus) -> Double {
        switch status { case .downloading(let value), .queued(let value): value; default: 0 }
    }

    private func statusLine(for status: OfflineCollectionStatus, store: OfflineStore) -> String {
        switch status {
        case .notInstalled:
            if let manifest = store.baseManifest(for: slug) {
                return AppLocalization.string("Not downloaded", locale: uiLocale) + " · " + OfflineModels.format(bytes: Int64(manifest.byteSize))
            }
            return AppLocalization.string("Not downloaded", locale: uiLocale)
        case .queued:
            return AppLocalization.string("Waiting to download…", locale: uiLocale)
        case .downloading(let fraction):
            return AppLocalization.format("Downloading… %lld%%", locale: uiLocale, Int(fraction * 100))
        case .paused:
            return AppLocalization.string("Paused — resumes where it stopped.", locale: uiLocale)
        case .verifying:
            return AppLocalization.string("Checking the file…", locale: uiLocale)
        case .failed(let reason):
            return OfflineCopy.message(reason, locale: uiLocale)
        case .active(_, let updateAvailable, let stalePack):
            var parts: [String] = [AppLocalization.string("Downloaded", locale: uiLocale)]
            if updateAvailable { parts.append(AppLocalization.string("update available", locale: uiLocale)) }
            if stalePack { parts.append(AppLocalization.string("translation outdated", locale: uiLocale)) }
            if let pack = store.packManifest(for: slug, locale: locale),
               store.registry.record(for: slug).activePacks[locale] == nil
            {
                parts.append(AppLocalization.format("%@ translation available", locale: uiLocale, OfflineModels.format(bytes: Int64(pack.byteSize))))
            }
            return parts.joined(separator: " · ")
        case .appUpdateRequired(let minimum):
            return AppLocalization.format("Needs Hadithly %@ or newer.", locale: uiLocale, minimum)
        }
    }

    @ViewBuilder
    private func actionButtons(for status: OfflineCollectionStatus, store: OfflineStore) -> some View {
        switch status {
        case .notInstalled:
            Button("Download") {
                report(store.enqueue(slug: slug, kind: "base", locale: locale))
            }
            .accessibilityIdentifier("settings.offline.\(slug).download")
        case .queued, .downloading:
            HStack {
                Button("Pause") { store.pause(slug: slug) }
                    .accessibilityIdentifier("settings.offline.\(slug).pause")
                Button("Cancel") { store.cancel(slug: slug) }
                    .accessibilityIdentifier("settings.offline.\(slug).cancel")
            }
        case .paused:
            HStack {
                Button("Resume") { store.retry(slug: slug) }
                    .accessibilityIdentifier("settings.offline.\(slug).resume")
                Button("Cancel") { store.cancel(slug: slug) }
                    .accessibilityIdentifier("settings.offline.\(slug).cancel")
            }
        case .verifying:
            Text("Checking…")
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
        case .failed:
            HStack {
                Button("Retry") { store.retry(slug: slug) }
                    .accessibilityIdentifier("settings.offline.\(slug).retry")
                Button("Cancel") { store.cancel(slug: slug) }
                    .accessibilityIdentifier("settings.offline.\(slug).cancel")
            }
        case .active(_, let updateAvailable, _):
            HStack {
                if updateAvailable {
                    Button("Update") { store.update(slug: slug, translationLocale: locale) }
                        .accessibilityIdentifier("settings.offline.\(slug).update")
                } else if store.packManifest(for: slug, locale: locale) != nil,
                          store.registry.record(for: slug).activePacks[locale] == nil
                {
                    Button("Download translation") {
                        report(store.enqueue(slug: slug, kind: "pack", locale: locale))
                    }
                    .accessibilityIdentifier("settings.offline.\(slug).downloadPack")
                }
                Button(role: .destructive) {
                    store.delete(slug: slug)
                    onNotice(OfflineCopy.removed(name, locale: uiLocale))
                } label: { Image(systemName: "trash") }
                .accessibilityIdentifier("settings.offline.\(slug).delete")
            }
        case .appUpdateRequired:
            EmptyView()
        }
    }

    private func report(_ result: OfflineEnqueueResult) {
        if case .blocked(let reason) = result {
            onNotice(OfflineCopy.message(reason, locale: uiLocale))
        }
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
                                RuntimeStatusNotice(source: statusLine, fallback: "Could not register this device. Check your connection and try again.")
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
        let previous = enabled
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
        guard await savePreferences(enabled: newValue) else {
            enabled = previous
            return
        }
        enabled = newValue
    }

    private func setDailyTime(_ date: Date) {
        let previous = dailyTime
        dailyTime = Self.string(from: date)
        Task {
            guard await savePreferences(enabled: enabled) else {
                dailyTime = previous
                return
            }
        }
    }

    private func savePreferences(enabled: Bool) async -> Bool {
        let tzOffsetMinutes = Double(-TimeZone.current.secondsFromGMT() / 60)
        let prefs = environment.preferences.preferences
        do {
            try await environment.convex.mutation(
                "library:setDailyNotification",
                with: [
                "enabled": enabled as ConvexEncodable?,
                "dailyTime": dailyTime as ConvexEncodable?,
                "timezone": TimeZone.current.identifier as ConvexEncodable?,
                "uiLocale": prefs.uiLocale as ConvexEncodable?,
                "translationLocale": prefs.translationLocale as ConvexEncodable?,
                "tzOffsetMinutes": tzOffsetMinutes as ConvexEncodable?,
                ]
            )
            return true
        } catch {
            statusLine = "Could not save notification settings. Please try again."
            return false
        }
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
    @Environment(\.locale) private var locale
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @State private var status: SubscriptionStatus?
    @State private var isLoading = true
    @State private var loadFailed = false
    @State private var isRestoring = false

    var body: some View {
        SettingsList("Subscription") {
            if clerk.session != nil {
                Section {
                    if isLoading && status == nil {
                        ContentSkeleton(kind: .compact, label: "Loading subscription")
                    } else if loadFailed && status == nil {
                        Text("Subscription details could not load").foregroundStyle(Theme.textSecondary)
                        Button("Try again") { Task { await loadStatus() } }
                    } else {
                        LabeledContent("Plan", value: AppLocalization.string(SettingsSubscription.displayName(tier: status?.subscriptionTier), locale: locale))
                    }
                    if let expires = status?.entitlementExpiresAt, expires > 0 {
                        LabeledContent(
                            status?.phase == "grace" ? "Grace ends" : "Access until",
                            value: Date(timeIntervalSince1970: expires / 1000).formatted(date: .abbreviated, time: .omitted)
                        )
                    }
                    if status?.subscriptionTier == "pro" {
                        Label("Pro is active for this account", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                } footer: {
                    Text("q2.quota")
                }

                Section {
                    Button {
                        Task {
                            isRestoring = true
                            defer { isRestoring = false }
                            _ = await environment.purchases.restore()
                            await loadStatus()
                        }
                    } label: {
                        Text(isRestoring ? LocalizedStringKey("Restoring…") : LocalizedStringKey("la2.restore"))
                    }
                    .disabled(isRestoring)
                    .accessibilityIdentifier("settings.subscription.restore")
                    Link("Manage subscription", destination: status?.store == "play_store" ? URL(string: "https://play.google.com/store/account/subscriptions")! : SettingsLinks.appleSubscriptions)
                    Text("q2.manage")
                        .font(.footnote)
                    if let message = environment.purchases.errorMessage { RuntimeStatusNotice(source: message).font(.footnote) }
                }
            } else {
                Section {
                    Text("Sign in to see your subscription. Purchases stay attached to your Hadithly account across devices.")
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("settings.subscription.signedOut")
                }
            }
        }
        .task(id: clerk.user?.id) { status = nil; isLoading = true; loadFailed = false; await observeStatus() }
    }

    private func observeStatus() async {
        guard let accountID = clerk.user?.id else { return }
        do {
            for try await value in environment.convex.subscribe(to: "subscriptions:getStatus", yielding: SubscriptionStatus.self).values {
                guard !Task.isCancelled, clerk.user?.id == accountID else { return }
                status = value
                isLoading = false
                loadFailed = false
            }
        } catch { if !Task.isCancelled, clerk.user?.id == accountID { isLoading = false; loadFailed = true } }
    }

    private func loadStatus() async {
        guard clerk.session != nil else { return }
        isLoading = status == nil
        defer { isLoading = false }
        do {
        let fetched = try await environment.convex
            .subscribe(to: "subscriptions:getStatus", yielding: SubscriptionStatus.self)
            .values
            .first(where: { _ in true })
        if let fetched { status = fetched; loadFailed = false }
        else { loadFailed = true }
        } catch { loadFailed = true }
    }
}

// MARK: - Privacy & data (export + deletion)

struct AccountDeletionWarning: View {
    var body: some View {
        Text(LocalizedStringKey(SettingsDeletionCopy.subscriptionWarning))
            .accessibilityIdentifier("settings.deletionSubscriptionWarning")
    }
}

struct AccountDeletionConfirmation: ViewModifier {
    @Environment(\.locale) private var locale
    @Binding var isPresented: Bool
    let onDelete: () -> Void

    func body(content: Content) -> some View {
        content.confirmationDialog(LocalizedStringKey(SettingsDeletionCopy.title), isPresented: $isPresented, titleVisibility: .visible) {
            Button("Delete account and data", role: .destructive, action: onDelete)
                .accessibilityIdentifier("settings.confirmDeletion")
            Button("Cancel", role: .cancel) {}
                .accessibilityIdentifier("settings.cancelDeletion")
        } message: {
            Text(verbatim: AppLocalization.string(SettingsDeletionCopy.message, locale: locale) + "\n\n" + AppLocalization.string(SettingsDeletionCopy.subscriptionWarning, locale: locale))
        }
    }
}

#if DEBUG
struct AccountDeletionCopyAuditFixture: View {
    @State private var showConfirmation = false
    @State private var deletionRequests = 0
    var body: some View {
        Form {
            AccountDeletionWarning()
            Button("Delete account") { showConfirmation = true }
                .accessibilityIdentifier("deletionAudit.present")
            Text(String(deletionRequests)).accessibilityIdentifier("deletionAudit.requests")
        }
        .modifier(AccountDeletionConfirmation(isPresented: $showConfirmation) { deletionRequests += 1 })
    }
}
#endif

struct PrivacyDataView: View {
    @Environment(\.locale) private var locale
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @Binding var showSignIn: Bool

    @State private var showExportConfirm = false
    @State private var pendingExportContext: LibraryWriteContext?
    @State private var isExporting = false
    @State private var exportTask: Task<Void, Never>?
    @State private var preparedExport: LibraryPreparedExport?
    private var exportURL: URL? { preparedExport?.url }
    @State private var exportError: String?
    @State private var showDeleteConfirmation = false
    @State private var pendingDeletionSession: LibrarySyncSession?
    @State private var isDeletingAccount = false
    @State private var deletionError: String?
    @State private var crashConsent = CrashReporting.shared.hasConsent

    var body: some View {
        SettingsList("Privacy & data") {
            Section {
                Toggle("la2.usage", isOn: Binding(get: { environment.analytics.sharing },
                    set: { environment.analytics.setSharing($0) }))
                    .accessibilityIdentifier("settings.usageStatistics")
            } footer: { Text("Share basic app statistics to help improve Hadithly. Your reading text, notes and account details are never included. Turning this off clears pending statistics.") }
            Section {
                Toggle("Send crash reports", isOn: $crashConsent)
                    .accessibilityIdentifier("settings.crashReports")
                    .onChange(of: crashConsent) { _, enabled in CrashReporting.shared.setConsent(enabled) }
            } footer: {
                Text("Crash reports help us fix problems. They never include your reading text, notes or account details. Turning this off clears pending reports on this device.")
            }
            Section {
                if clerk.session?.status == .active {
                    Button {
                        do {
                            pendingExportContext = try environment.librarySync.captureWriteContext()
                            showExportConfirm = true
                        } catch { exportError = "Export failed. Please try again." }
                    } label: {
                        Text(LocalizedStringKey(isExporting ? "Preparing…" : "Export my data"))
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
                        RuntimeStatusNotice(source: exportError)
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
                Text("Download your profile, settings, saved items, folders, reading progress and contributions. Guest data stays on this device.")
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

            if clerk.session?.status == .active {
                Section {
                    Button(role: .destructive) {
                        pendingDeletionSession = currentLibrarySession()
                        showDeleteConfirmation = pendingDeletionSession != nil
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
                    AccountDeletionWarning()
                }
            }
        }
        .onChange(of: clerk.session?.id) { _, _ in clearExportPresentation() }
        .onDisappear {
            exportTask?.cancel()
            discardPreparedExport()
        }
        .confirmationDialog(
            "Export your data?",
            isPresented: $showExportConfirm,
            titleVisibility: .visible
        ) {
            Button("Export after device check") {
                guard let captured = pendingExportContext else { return }
                pendingExportContext = nil
                exportTask = Task { await exportWithReauth(captured) }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The file contains only your portable data. Confirm with Face ID, Touch ID, or your device passcode when asked.")
        }
        .modifier(AccountDeletionConfirmation(isPresented: $showDeleteConfirmation) {
            guard let captured = pendingDeletionSession else { return }
            pendingDeletionSession = nil
            Task { await deleteAccount(captured) }
        })
        .alert(
            "Account deletion failed",
            isPresented: Binding(
                get: { deletionError != nil },
                set: { if !$0 { deletionError = nil } }
            )
        ) {
            Button("OK") { deletionError = nil }
        } message: {
            RuntimeStatusNotice(source: deletionError ?? "Please try again.")
        }
    }

    private func clearExportPresentation() {
        exportTask?.cancel(); exportTask = nil
        discardPreparedExport()
        exportError = nil; showExportConfirm = false; pendingExportContext = nil
        showDeleteConfirmation = false; pendingDeletionSession = nil; deletionError = nil
    }

    private func discardPreparedExport() {
        if let preparedExport { try? environment.librarySync.discardPreparedExport(preparedExport) }
        preparedExport = nil
    }

    /// Device reauthentication precedes the export whenever the device can
    /// enforce it; the query itself additionally requires a valid Clerk
    /// session, so an expired sign-in forces a fresh sign-in first.
    private func exportWithReauth(_ captured: LibraryWriteContext) async {
        isExporting = true
        defer { isExporting = false }
        do {
            try Task.checkCancellation()
            if let preparedExport { try? environment.librarySync.discardPreparedExport(preparedExport) }
            preparedExport = nil
            let context = LAContext()
            var authError: NSError?
            if context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &authError) {
                do {
                    _ = try await context.evaluatePolicy(
                        .deviceOwnerAuthentication,
                        localizedReason: AppLocalization.string("Confirm it is you before exporting your data.", locale: locale)
                    )
                } catch {
                    exportError = "Export cancelled: device check did not pass."
                    return
                }
            }
            let capability = try environment.librarySync.capability(for: captured)
            guard let server = try await environment.convex
                .subscribe(to: "users:exportCurrentUserData", with: ["capability": capability], yielding: LibraryExportValue.self)
                .values.first(where: { _ in true }) else {
                exportError = "Export is unavailable right now."
                return
            }
            try Task.checkCancellation()
            _ = try environment.librarySync.capability(for: captured)
            preparedExport = try await environment.librarySync.preparePortableExport(server: server, context: captured, fileName: SettingsExport.fileName())
            exportError = nil
        } catch is CancellationError { }
        catch {
            exportError = "Export failed. Please try again."
        }
    }

    private func deleteAccount(_ captured: LibrarySyncSession) async {
        isDeletingAccount = true
        defer { isDeletingAccount = false }
        do {
            try await environment.deleteAccount(captured)
        } catch {
            deletionError = error.localizedDescription
        }
    }
}

// MARK: - Help & support

struct HelpSupportView: View {
    @Environment(\.locale) private var locale
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
                    subtitle: AppLocalization.string("Include the collection and hadith number", locale: locale),
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

    }
}

enum ProfileNotice: String, CaseIterable {
    case nameSaved = "Name saved."
    case nameFailed = "Could not save your name. Please try again."
    case tooShort = "Usernames need at least 3 characters."
    case usernameSaved = "Username saved."
    case unavailable = "That username is not available."
    case retry = "This action could not be completed. Please try again."

    static func usernameFailure(code: String?) -> Self {
        switch code {
        case "form_username_in_use", "form_identifier_exists": return .unavailable
        default: return .retry
        }
    }
}

struct ProfileStatusNotice: View {
    let source: String
    var body: some View {
        Group {
            if ProfileNotice(rawValue: source) != nil {
                Text(LocalizedStringKey(source))
            } else {
                RuntimeStatusNotice(source: source)
            }
        }
        .font(.footnote)
        .foregroundStyle(Theme.textSecondary)
        .accessibilityIdentifier("settings.profile.notice")
    }
}

#if DEBUG
struct ProfileNoticeCopyAuditFixture: View {
    @State private var index = 0
    @State private var name = "Original %lld %@ اسم"
    private let notices = ProfileNotice.allCases.map(\.rawValue)
    var body: some View {
        SettingsList("Profile") {
            Section {
                TextField("First name", text: $name).accessibilityIdentifier("profileAudit.name")
                ProfileStatusNotice(source: notices[index])
                Button("Next fixture notice") { index = (index + 1) % notices.count }
                    .accessibilityIdentifier("profileAudit.next")
            }
        }
    }
}
#endif

enum OfflineCopy {
    static let keys: [String] = [
        "Temporary cache cleared.",
        "Deleted the %@ files. Your saved items and positions stay.",
        "Not downloaded",
        "Waiting to download…",
        "Downloading… %lld%%",
        "Paused — resumes where it stopped.",
        "Checking the file…",
        "Downloaded",
        "update available",
        "translation outdated",
        "%@ translation available",
        "Needs Hadithly %@ or newer.",
        "You're offline. Showing your downloaded content.",
        "Could not check for updates. Your downloads keep working offline.",
        "Pick a translation language first.",
        "No offline file is published for this collection yet.",
        "Update Hadithly to download this collection.",
        "The server offers an older file than your installed copy. Your copy stays active.",
        "Not enough storage: need %@, %@ free.",
        "You're offline. Reconnect and retry — your installed copy still works.",
        "Could not reach the server. Try again when you are online.",
        "The download link is invalid. Try again.",
        "The download was interrupted. Your installed copy still works.",
        "The new file is missing %lld of your saved hadiths. Your copy stays active.",
        "The file failed its checksum. Your installed copy still works.",
        "This file needs a newer Hadithly. Update the app and try again.",
        "This translation does not match the installed Arabic file.",
        "This file's license could not be verified.",
        "This file failed validation. Your installed copy still works.",
        "Download failed."
    ]
    static func removed(_ name: String, locale: Locale) -> String {
        AppLocalization.format("Deleted the %@ files. Your saved items and positions stay.", locale: locale, "\u{2068}" + name + "\u{2069}")
    }
    static func message(_ source: String, locale: Locale) -> String {
        if keys.contains(source), !source.contains("%@"), !source.contains("%lld") {
            return AppLocalization.string(source, locale: locale)
        }
        if source.hasPrefix("Could not check for updates ("), source.hasSuffix("). Your downloads keep working offline.") {
            return AppLocalization.string("Could not check for updates. Your downloads keep working offline.", locale: locale)
        }
        let storage = #"^Not enough storage: need ([0-9.]+ [A-Z]+), ([0-9.]+ [A-Z]+) free\.$"#
        if let values = captures(storage, source), values.count == 2 {
            return AppLocalization.format("Not enough storage: need %@, %@ free.", locale: locale, values[0], values[1])
        }
        if let values = captures(#"^The new file is missing ([0-9]+) of your saved hadiths\. Your copy stays active\.$"#, source),
           let count = Int(values[0]) {
            return AppLocalization.format("The new file is missing %lld of your saved hadiths. Your copy stays active.", locale: locale, count)
        }
        return AppLocalization.string("Download failed.", locale: locale)
    }
    private static func captures(_ pattern: String, _ source: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: source, range: NSRange(source.startIndex..., in: source)) else { return nil }
        return (1..<match.numberOfRanges).compactMap { Range(match.range(at: $0), in: source).map { String(source[$0]) } }
    }
}

struct OfflineStatusNotice: View {
    @Environment(\.locale) private var locale
    let source: String
    var body: some View {
        Text(OfflineCopy.message(source, locale: locale)).font(.caption).foregroundStyle(Theme.textSecondary)
            .accessibilityIdentifier("settings.offline.notice")
    }
}

#if DEBUG
struct OfflineNoticeCopyAuditFixture: View {
    @Environment(\.locale) private var locale
    @State private var index = 0
    @State private var callbacks = 0
    private let name = "Original %lld %@ اسم"
    var body: some View {
        SettingsList("Offline storage") {
            Section {
                Text(name).accessibilityIdentifier("offlineAudit.name")
                Text(rendered).font(.caption).foregroundStyle(Theme.textSecondary).accessibilityIdentifier("offlineAudit.notice")
                Button("Next fixture notice") { index = (index + 1) % OfflineCopy.keys.count }
                    .accessibilityIdentifier("offlineAudit.next")
                Button("Local callback") { callbacks += 1 }.accessibilityIdentifier("offlineAudit.callback")
                Text(String(callbacks)).accessibilityIdentifier("offlineAudit.callbacks")
            }
        }
    }
    private var rendered: String {
        let key = OfflineCopy.keys[index]
        switch index {
        case 0: return OfflineCopy.message(key, locale: locale)
        case 1: return OfflineCopy.removed(name, locale: locale)
        case 4: return AppLocalization.format(key, locale: locale, 42)
        case 10: return AppLocalization.format(key, locale: locale, "12 MB")
        case 11: return AppLocalization.format(key, locale: locale, "2.0")
        case 18: return OfflineCopy.message("Not enough storage: need 12 MB, 8 MB free.", locale: locale)
        case 23: return OfflineCopy.message("The new file is missing 2 of your saved hadiths. Your copy stays active.", locale: locale)
        default: return OfflineCopy.message(key, locale: locale)
        }
    }
}
#endif
