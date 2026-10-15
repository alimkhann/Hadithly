import SwiftUI

enum ReaderPreferencePanel: String, Hashable {
    case arabic = "Arabic type"
    case translation = "Translation"
    case appearance = "Appearance"
}

struct ReaderPreferenceSections: View {
    let prefix: String
    var onLanguage: (String) -> Void = { _ in }
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.readerPalette) private var palette

    private var store: PreferencesStore { environment.preferences }

    var body: some View {
        Section("Reader settings") {
            link(.arabic, value: "\(store.preferences.arabicFont.displayName) · \(Int(store.preferences.arabicFontSize)) pt")
            link(.translation, value: "\(store.preferences.translationLocale.uppercased()) · \(Int(store.preferences.translationFontSize)) pt")
            link(.appearance, value: store.preferences.theme.rawValue.capitalized)
        }
        .listRowBackground(palette.surface)
        Section {
            visibilityToggle("Arabic", arabic: true)
            visibilityToggle("Translation", arabic: false)
        } header: {
            Text("Show on page")
        } footer: {
            Text("At least one text layer stays visible.")
        }
        .listRowBackground(palette.surface)
    }

    private func link(_ panel: ReaderPreferencePanel, value: String) -> some View {
        Group {
            if prefix == "reader" {
                NavigationLink(value: panel) { row(panel, value: value) }
            } else {
                NavigationLink {
                    ReaderPreferenceDetail(panel: panel, prefix: prefix, onLanguage: onLanguage)
                } label: { row(panel, value: value) }
            }
        }
        .accessibilityIdentifier("\(prefix).settings.\(panel == .arabic ? "arabic" : panel == .appearance ? "appearance" : "translation")")
    }

    private func row(_ panel: ReaderPreferencePanel, value: String) -> some View {
        HStack {
            Text(LocalizedStringKey(panel.rawValue))
            Spacer()
            Text(value).font(.subheadline).foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.trailing)
        }
        .foregroundStyle(palette.textPrimary)
    }

    private func visibilityToggle(_ title: String, arabic: Bool) -> some View {
        Toggle(LocalizedStringKey(title), isOn: Binding(
            get: { arabic ? store.preferences.arabicVisible : store.preferences.translationVisible },
            set: { value in
                if !store.setVisibility(arabic: arabic ? value : nil, translation: arabic ? nil : value) {
                    ReaderHapticDispatcher.trigger(.layersRejected)
                }
            }
        ))
        .tint(palette.textSecondary)
        .foregroundStyle(palette.textPrimary)
        .accessibilityIdentifier("\(prefix).visibility.\(arabic ? "arabic" : "translation")")
    }
}

struct ReaderPreferenceDetail: View {
    let panel: ReaderPreferencePanel
    let prefix: String
    var onLanguage: (String) -> Void = { _ in }
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.readerPalette) private var palette

    private var store: PreferencesStore { environment.preferences }
    private var preferences: ReaderPreferences { store.preferences }

    var body: some View {
        SettingsList(panel.rawValue) {
            switch panel {
            case .appearance:
                Section {
                    ForEach(ReaderTheme.allCases, id: \.self) { theme in
                        choice(theme.rawValue.capitalized, selected: preferences.theme == theme,
                               identifier: "\(prefix).theme.\(theme.rawValue)") {
                            store.setSeparateReaderTheme(true)
                            store.setReaderTheme(theme)
                        }
                    }
                }
                .listRowBackground(palette.surface)
            case .arabic:
                Section("Preview") {
                    Text("إِنَّمَا الْأَعْمَالُ بِالنِّيَّاتِ")
                        .font(Theme.arabic(preferences.arabicFontSize, preferences.arabicFont))
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .accessibilityLabel("Arabic type preview")
                        .accessibilityIdentifier("\(prefix).typePreview")
                    Stepper(onIncrement: preferences.arabicFontSize < ReaderPreferences.maxArabicFontSize ? {
                        store.setArabicFontSize(ArabicTypeSize.stepUp(from: preferences.arabicFontSize))
                    } : nil, onDecrement: preferences.arabicFontSize > ReaderPreferences.minArabicFontSize ? {
                        store.setArabicFontSize(ArabicTypeSize.stepDown(from: preferences.arabicFontSize))
                    } : nil) {
                        sizeLabel(preferences.arabicFontSize)
                    }
                    .accessibilityLabel("Arabic type size")
                    .accessibilityIdentifier("\(prefix).arabicSize")
                }
                .listRowBackground(palette.surface)
                Section("Arabic font") {
                    ForEach(ArabicFont.allCases, id: \.self) { font in
                        choice(font.displayName, selected: preferences.arabicFont == font,
                               identifier: "\(prefix).font.\(font.rawValue)") { store.setArabicFont(font) }
                    }
                }
                .listRowBackground(palette.surface)
            case .translation:
                Section("Preview") {
                    Text("Actions are judged by intentions.")
                        .font(.system(size: preferences.translationFontSize))
                        .padding(.vertical, 8)
                    Stepper(value: Binding(
                        get: { preferences.translationFontSize },
                        set: { store.setTranslationFontSize($0) }
                    ), in: 14...22, step: 2) {
                        sizeLabel(preferences.translationFontSize)
                    }
                    .accessibilityLabel("Translation type size")
                    .accessibilityIdentifier("\(prefix).translationSize")
                }
                .listRowBackground(palette.surface)
                Section {
                    ForEach(SupportedLanguages.all) { language in
                        choice(language.name, selected: preferences.translationLocale == language.code,
                               identifier: "\(prefix).language.\(language.code)") {
                            store.setTranslationLocale(language.code)
                            onLanguage(language.code)
                        }
                    }
                } header: {
                    Text("Language")
                } footer: {
                    Text("AI translations are labeled and grounded in cited sources.")
                }
                .listRowBackground(palette.surface)
            }
        }
        .foregroundStyle(palette.textPrimary)
        .tint(palette.interactive)
    }

    private func sizeLabel(_ size: Double) -> some View {
        HStack {
            Text("Text size")
            Text("\(Int(size)) pt").foregroundStyle(palette.textSecondary)
        }
    }

    private func choice(_ title: String, selected: Bool, identifier: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(LocalizedStringKey(title)).foregroundStyle(palette.textPrimary)
                Spacer()
                if selected {
                    Image(systemName: "checkmark").font(.body.weight(.semibold))
                        .foregroundStyle(palette.interactive)
                }
            }
            .frame(minHeight: 28)
            .contentShape(Rectangle())
        }
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
}

#if DEBUG
struct ReaderSettingsFixtureView: View {
    @Environment(AppEnvironment.self) private var environment
    @State private var showingSettings = false

    var body: some View {
        NavigationStack {
            if ProcessInfo.processInfo.environment["READER_SETTINGS_CONTEXT"] == "global" {
                SettingsView(showSignIn: .constant(false))
            } else {
                Color.clear
                    .toolbar {
                        Button("Open reader settings") { showingSettings = true }
                    }
            }
        }
        .sheet(isPresented: $showingSettings) {
            ReaderSettingsSheet(onLanguage: { _ in })
        }
        .task {
            let values = ProcessInfo.processInfo.environment
            let theme = ReaderTheme(rawValue: values["READER_SETTINGS_THEME"] ?? "dark") ?? .dark
            environment.preferences.setTheme(theme)
            environment.preferences.setSeparateReaderTheme(false)
            environment.preferences.setUILocale(values["READER_SETTINGS_LOCALE"] ?? "en")
            environment.preferences.setTranslationLocale("en")
            environment.preferences.setArabicFont(.system)
            environment.preferences.setArabicFontSize(26)
            environment.preferences.setTranslationFontSize(16)
            _ = environment.preferences.setVisibility(arabic: true, translation: true)
            showingSettings = values["READER_SETTINGS_CONTEXT"] != "global"
        }
    }
}
#endif
