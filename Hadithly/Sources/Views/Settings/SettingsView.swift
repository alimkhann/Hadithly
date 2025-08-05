import SwiftUI

struct SettingsView: View {
    @StateObject private var viewModel = SettingsViewModel()
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var localizationManager: LocalizationManager
    @StateObject private var themeManager = ThemeManager.shared

    var body: some View {
        NavigationView {
            List {
                // Language Settings
                Section(localizationManager.localizedString(.language)) {
                    Picker(localizationManager.localizedString(.language), selection: $settings.selectedLanguage) {
                        ForEach(Language.allCases, id: \.self) { language in
                            Text(language.displayName).tag(language)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }

                // Notification Settings
                Section(localizationManager.localizedString(.notifications)) {
                    Toggle(localizationManager.localizedString(.dailyNotifications), isOn: $settings.notificationsEnabled)

                    if settings.notificationsEnabled {
                        DatePicker(localizationManager.localizedString(.notificationTime), selection: $settings.notificationTime, displayedComponents: .hourAndMinute)
                    }
                }

                // Display Settings
                Section(localizationManager.localizedString(.display)) {
                    HStack {
                        Text(localizationManager.localizedString(.fontSize))
                        Spacer()
                        Slider(value: $settings.fontSize, in: 12...24, step: 1)
                        Text("\(Int(settings.fontSize))")
                            .font(.caption)
                    }

                    Picker(localizationManager.localizedString(.theme), selection: $settings.theme) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.displayName).tag(theme)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())

                    Toggle(localizationManager.localizedString(.showArabicText), isOn: $settings.showArabicText)

                    Toggle(localizationManager.localizedString(.pureArabicMode), isOn: $settings.pureArabicMode)
                }

                // Data Management
                Section(localizationManager.localizedString(.dataManagement)) {
                    Button(localizationManager.localizedString(.exportData)) {
                        viewModel.exportData()
                    }
                    .foregroundColor(.blue)

                    Button(localizationManager.localizedString(.importData)) {
                        viewModel.importData()
                    }
                    .foregroundColor(.blue)

                    Button(localizationManager.localizedString(.clearAllData)) {
                        viewModel.showClearDataAlert = true
                    }
                    .foregroundColor(.red)
                }

                // About
                Section(localizationManager.localizedString(.about)) {
                    HStack {
                        Text(localizationManager.localizedString(.version))
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    Link(localizationManager.localizedString(.privacyPolicy), destination: URL(string: "https://hadithly.app/privacy")!)

                    Link(localizationManager.localizedString(.termsOfService), destination: URL(string: "https://hadithly.app/terms")!)
                }
            }
            .navigationTitle(localizationManager.localizedString(.settings))
            .navigationBarTitleDisplayMode(.large)
            .onChange(of: settings.selectedLanguage) { _, _ in
                settings.save()
                // Update UI language and RTL support
                localizationManager.currentLanguage = settings.selectedLanguage
                updateRTLSupport()
            }
            .onChange(of: settings.notificationsEnabled) { _, _ in
                settings.save()
                viewModel.updateNotifications()
            }
            .onChange(of: settings.notificationTime) { _, _ in
                settings.save()
                viewModel.updateNotifications()
            }
            .onChange(of: settings.fontSize) { _, _ in
                settings.save()
            }
            .onChange(of: settings.theme) { _, _ in
                settings.save()
                themeManager.applyTheme(settings.theme)
            }
            .onChange(of: settings.showArabicText) { _, _ in
                settings.save()
            }
            .onChange(of: settings.pureArabicMode) { _, _ in
                settings.save()
                updateRTLSupport()
            }
            .alert(localizationManager.localizedString(.clearDataWarning), isPresented: $viewModel.showClearDataAlert) {
                Button(localizationManager.localizedString(.cancel), role: .cancel) { }
                Button(localizationManager.localizedString(.confirm), role: .destructive) {
                    viewModel.clearAllData()
                }
            } message: {
                Text(localizationManager.localizedString(.clearDataMessage))
            }
        }
        .onAppear {
            settings.load()
            themeManager.applyTheme(settings.theme)
            updateRTLSupport()
        }
    }

    private func updateRTLSupport() {
        // Enable RTL when Arabic is selected or pure Arabic mode is on
        let shouldUseRTL = settings.selectedLanguage == .arabic || settings.pureArabicMode

        DispatchQueue.main.async {
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                windowScene.windows.forEach { window in
                    window.semanticContentAttribute = shouldUseRTL ? .forceRightToLeft : .forceLeftToRight
                }
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppSettings())
        .environmentObject(LocalizationManager.shared)
}
