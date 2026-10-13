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
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .listRowBackground(palette.surface)
        .listRowSeparatorTint(palette.divider)
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
                Text(title)
                    .foregroundStyle(Theme.textPrimary)
                if let footnote {
                    Text(footnote)
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
            .accessibilityLabel(configuration.isOn ? "On" : "Off")
        }
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
                Picker("", selection: Binding(
                    get: { environment.preferences.preferences.appTheme },
                    set: { environment.preferences.setTheme($0) }
                )) {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        Text(Self.label(theme))
                            .tag(theme)
                            .accessibilityIdentifier("settings.appearance.\(theme.rawValue)")
                    }
                }
                .labelsHidden()
                .pickerStyle(.inline)
                Toggle("Use a separate reader appearance", isOn: Binding(
                    get: { environment.preferences.preferences.usesSeparateReaderTheme },
                    set: { environment.preferences.setSeparateReaderTheme($0) }
                ))
                if environment.preferences.preferences.usesSeparateReaderTheme {
                    Picker("Reader appearance", selection: Binding(
                        get: { environment.preferences.preferences.readerTheme },
                        set: { environment.preferences.setReaderTheme($0) }
                    )) {
                        ForEach(ReaderTheme.allCases, id: \.self) { theme in
                            Text(Self.label(theme)).tag(theme)
                        }
                    }
                    .pickerStyle(.inline)
                }
            } header: {
                Text("App appearance")
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
    @State private var panel: Panel?

    private enum Panel: String, Identifiable { case appearance = "Appearance", arabic = "Arabic type", translation = "Translation"; var id: String { rawValue } }

    private var store: PreferencesStore { environment.preferences }

    var body: some View {
        let preferences = store.preferences
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                sectionLabel("READER SETTINGS")
                settingRow(.arabic, subtitle: "\(preferences.arabicFont.displayName) · \(Int(preferences.arabicFontSize)) pt")
                settingRow(.translation, subtitle: "\(preferences.translationLocale.uppercased()) · \(Int(preferences.translationFontSize)) pt")
                settingRow(.appearance, subtitle: preferences.theme.rawValue.capitalized)

                sectionLabel("DISPLAY")
                HStack(spacing: 10) {
                    displayPill(
                        "Arabic",
                        isOn: preferences.arabicVisible,
                        identifier: "settings.visibility.arabic"
                    ) { store.setVisibility(arabic: !preferences.arabicVisible) }
                    displayPill(
                        "Translation",
                        isOn: preferences.translationVisible,
                        identifier: "settings.visibility.translation"
                    ) { store.setVisibility(translation: !preferences.translationVisible) }
                }
                Text("At least one text layer stays visible.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)

                sectionLabel("READING DIRECTION")
                HStack(spacing: 8) {
                    ForEach(ReadingDirection.allCases, id: \.self) { direction in
                        directionPill(direction, selected: preferences.readingDirection == direction)
                    }
                }

                sectionLabel("SAVED")
                SettingsToggleRow(
                    title: "Confirm before removing",
                    footnote: "Ask before removing saved items",
                    isOn: Binding(
                        get: { environment.savedSafety.confirmsRemoval },
                        set: { environment.savedSafety.confirmsRemoval = $0 }
                    ),
                    accessibilityID: "settings.confirmSavedRemoval"
                )
                .padding(16)
                .background(palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 18))
            }
            .padding(20)
            .padding(.bottom, 28)
        }
        .background(palette.background)
        .navigationTitle("Reading & type")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(palette.background, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .sheet(item: $panel) { panel in
            ReaderSheetChrome(
                title: panel.rawValue,
                subtitle: nil,
                palette: palette,
                grabberIdentifier: "settings.reading.grabber",
                closeIdentifier: "settings.reading.close",
                titleIdentifier: "settings.reading.title",
                onClose: { self.panel = nil }
            ) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) { panelView(panel) }
                        .padding(20)
                        .padding(.bottom, 24)
                }
            }
        }
    }

    private func settingRow(_ panel: Panel, subtitle: String) -> some View {
        Button { self.panel = panel } label: {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(panel.rawValue).font(.title3.weight(.medium)).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(.body).foregroundStyle(palette.textSecondary)
                }
                Spacer(minLength: 12)
                Image(systemName: "chevron.right").font(.title3.weight(.medium)).foregroundStyle(palette.textSecondary.opacity(0.7))
            }
            .frame(minHeight: 70)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder private func panelView(_ panel: Panel) -> some View {
        switch panel {
        case .appearance:
            ForEach(ReaderTheme.allCases, id: \.self) { theme in
                themeRow(theme, selected: store.preferences.readerTheme == theme)
            }
        case .arabic:
            previewCard(Text("إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ").font(Theme.arabic(store.preferences.arabicFontSize, store.preferences.arabicFont)))
            typeStepper
            ForEach(ArabicFont.allCases, id: \.self) { font in fontRow(font) }
        case .translation:
            previewCard(Text("Actions are judged by intentions.").font(.system(size: store.preferences.translationFontSize)))
            translationStepper
            sectionLabel("LANGUAGE")
            ForEach(SupportedLanguages.all) { language in languageRow(language) }
        }
    }

    private func sectionLabel(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textSecondary)
            .padding(.top, 8)
    }

    private func displayPill(_ title: String, isOn: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: isOn ? "checkmark.circle.fill" : "circle")
                .font(.body.weight(.medium))
                .foregroundStyle(isOn ? palette.textPrimary : palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(isOn ? palette.surfaceElevated : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(isOn ? Color.clear : palette.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }

    private func directionPill(_ direction: ReadingDirection, selected: Bool) -> some View {
        Button { store.setReadingDirection(direction) } label: {
            Text(Self.directionLabel(direction))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(selected ? palette.textPrimary : palette.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(selected ? palette.surfaceElevated : Color.clear)
                .clipShape(Capsule())
                .overlay(Capsule().strokeBorder(selected ? Color.clear : palette.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.readingDirection.\(direction.rawValue)")
    }

    private func themeRow(_ theme: ReaderTheme, selected: Bool) -> some View {
        let swatch = ReaderPalette.resolved(theme, systemDark: true)
        return Button { store.setReaderTheme(theme) } label: {
            HStack(spacing: 12) {
                RoundedRectangle(cornerRadius: 7).fill(swatch.background).frame(width: 34, height: 34).overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(palette.divider, lineWidth: 1))
                Text(theme.rawValue.capitalized).font(.title3.weight(.medium))
                Spacer()
                if selected { Image(systemName: "checkmark").font(.title3.weight(.semibold)) }
            }
            .foregroundStyle(palette.textPrimary)
            .padding(.horizontal, 18)
            .frame(maxWidth: .infinity, minHeight: 62)
            .background(palette.surfaceElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.appearance.\(theme.rawValue)")
    }

    private func previewCard<Content: View>(_ content: Content) -> some View {
        content
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(20)
            .background(palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private var typeStepper: some View {
        HStack(spacing: 0) {
            Button { store.setArabicFontSize(ArabicTypeSize.stepDown(from: store.preferences.arabicFontSize)) } label: { Text("A").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 60) }
                .disabled(store.preferences.arabicFontSize <= ReaderPreferences.minArabicFontSize)
                .accessibilityIdentifier("settings.arabicSize.smaller")
            Divider().overlay(palette.divider)
            Button { store.setArabicFontSize(ArabicTypeSize.stepUp(from: store.preferences.arabicFontSize)) } label: { Text("A").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 60) }
                .disabled(store.preferences.arabicFontSize >= ReaderPreferences.maxArabicFontSize)
                .accessibilityIdentifier("settings.arabicSize.larger")
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textPrimary)
        .background(palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .accessibilityIdentifier("settings.arabicSize")
    }

    private var translationStepper: some View {
        HStack(spacing: 0) {
            Button { store.setTranslationFontSize(max(14, store.preferences.translationFontSize - 2)) } label: { Text("A").font(.subheadline.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 60) }
            Divider().overlay(palette.divider)
            Button { store.setTranslationFontSize(min(22, store.preferences.translationFontSize + 2)) } label: { Text("A").font(.title3.weight(.semibold)).frame(maxWidth: .infinity, minHeight: 60) }
        }
        .buttonStyle(.plain)
        .foregroundStyle(palette.textPrimary)
        .background(palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 18))
    }

    private func fontRow(_ font: ArabicFont) -> some View {
        let selected = store.preferences.arabicFont == font
        return Button { store.setArabicFont(font) } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("إِنَّمَا الْأَعْمَالُ").font(Theme.arabic(24, font))
                    Text(font.displayName).font(.body).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").font(.title3.weight(.semibold)) }
            }
            .foregroundStyle(palette.textPrimary)
            .frame(minHeight: 68)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.arabicFont.\(font.rawValue)")
    }

    private func languageRow(_ language: ReadingLanguage) -> some View {
        let selected = store.preferences.translationLocale == language.code
        return Button { store.setTranslationLocale(language.code) } label: {
            HStack(spacing: 12) {
                Text(language.flag).font(.title2)
                VStack(alignment: .leading, spacing: 3) {
                    Text(language.name).font(.title3.weight(.medium))
                    Text(language.code.uppercased()).font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if selected { Image(systemName: "checkmark").font(.title3.weight(.semibold)) }
            }
            .foregroundStyle(palette.textPrimary)
            .frame(minHeight: 64)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier("settings.language.\(language.code)")
    }

    private static func directionLabel(_ direction: ReadingDirection) -> String {
        switch direction {
        case .auto: "Automatic"
        case .rtl: "Right to left"
        case .ltr: "Left to right"
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
                    Text(lastError)
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
                    Text(clearNotice)
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
            if case .downloading(let fraction) = status {
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
                return "Not downloaded · \(OfflineModels.format(bytes: Int64(manifest.byteSize)))"
            }
            return "Not downloaded"
        case .queued:
            return "Waiting to download…"
        case .downloading(let fraction):
            return "Downloading… \(Int(fraction * 100))%"
        case .paused:
            return "Paused — resumes where it stopped."
        case .verifying:
            return "Checking the file…"
        case .failed(let reason):
            return reason
        case .active(_, let updateAvailable, let stalePack):
            var parts: [String] = ["Downloaded"]
            if updateAvailable { parts.append("update available") }
            if stalePack { parts.append("translation outdated") }
            if let pack = store.packManifest(for: slug, locale: locale),
               store.registry.record(for: slug).activePacks[locale] == nil
            {
                parts.append("\(OfflineModels.format(bytes: Int64(pack.byteSize))) translation available")
            }
            return parts.joined(separator: " · ")
        case .appUpdateRequired(let minimum):
            return "Needs Hadithly \(minimum) or newer."
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
                    onNotice("Deleted the \(name) files. Your saved items and positions stay.")
                } label: { Image(systemName: "trash") }
                .accessibilityIdentifier("settings.offline.\(slug).delete")
            }
        case .appUpdateRequired:
            EmptyView()
        }
    }

    private func report(_ result: OfflineEnqueueResult) {
        if case .blocked(let reason) = result {
            onNotice(reason)
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
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    @State private var status: SubscriptionStatus?
    @State private var isRestoring = false

    var body: some View {
        SettingsList("Subscription") {
            if clerk.session != nil {
                Section {
                    LabeledContent("Plan", value: SettingsSubscription.displayName(tier: status?.subscriptionTier))
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
                        Text(isRestoring ? "Restoring…" : "Restore purchases")
                    }
                    .disabled(isRestoring)
                    .accessibilityIdentifier("settings.subscription.restore")
                    Link("Manage subscription", destination: status?.store == "play_store" ? URL(string: "https://play.google.com/store/account/subscriptions")! : SettingsLinks.appleSubscriptions)
                    Text("q2.manage")
                        .font(.footnote)
                    if let message = environment.purchases.errorMessage { Text(message).font(.footnote) }
                }
            } else {
                Section {
                    Text("Sign in to see your subscription. Purchases stay attached to your Hadithly account across devices.")
                        .foregroundStyle(Theme.textSecondary)
                        .accessibilityIdentifier("settings.subscription.signedOut")
                }
            }
        }
        .task(id: clerk.user?.id) { status = nil; await observeStatus() }
    }

    private func observeStatus() async {
        guard let accountID = clerk.user?.id else { return }
        do {
            for try await value in environment.convex.subscribe(to: "subscriptions:getStatus", yielding: SubscriptionStatus.self).values {
                guard !Task.isCancelled, clerk.user?.id == accountID else { return }
                status = value
            }
        } catch { if !Task.isCancelled, clerk.user?.id == accountID { status = nil } }
    }

    private func loadStatus() async {
        guard clerk.session != nil else { return }
        status = try? await environment.convex
            .subscribe(to: "subscriptions:getStatus", yielding: SubscriptionStatus.self)
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
    @State private var crashConsent = CrashReporting.shared.hasConsent

    var body: some View {
        SettingsList("Privacy & data") {
            Section {
                Toggle("la2.usage", isOn: Binding(get: { environment.analytics.sharing },
                    set: { environment.analytics.setSharing($0) }))
                    .accessibilityIdentifier("settings.usageStatistics")
            } footer: { Text("la2.usage_explanation") }
            Section {
                Toggle("Send crash reports", isOn: $crashConsent)
                    .accessibilityIdentifier("settings.crashReports")
                    .onChange(of: crashConsent) { _, enabled in CrashReporting.shared.setConsent(enabled) }
            } footer: {
                Text("Optional. Sends redacted failures and build information to Sentry. No reading text or account details. Reports expire after 30 days. Turning off clears pending reports on this device.")
            }
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
