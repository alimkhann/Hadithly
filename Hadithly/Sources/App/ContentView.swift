import SwiftUI

struct ContentView: View {
    @State private var selectedTab = 0
    @EnvironmentObject var localizationManager: LocalizationManager
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        TabView(selection: $selectedTab) {
            HomeView()
                .tabItem {
                    Image(systemName: "house.fill")
                    Text(localizationManager.localizedString(.home))
                }
                .tag(0)

            SearchView()
                .tabItem {
                    Image(systemName: "magnifyingglass")
                    Text(localizationManager.localizedString(.search))
                }
                .tag(1)

            LibraryView()
                .tabItem {
                    Image(systemName: "book.fill")
                    Text(localizationManager.localizedString(.library))
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Image(systemName: "gear")
                    Text(localizationManager.localizedString(.settings))
                }
                .tag(3)
        }
        .accentColor(.green)
        .onChange(of: settings.selectedLanguage) { _, _ in
            // Update UI language when display language changes
            localizationManager.currentLanguage = settings.selectedLanguage
            updateRTLSupport()
        }
        .onChange(of: settings.pureArabicMode) { _, _ in
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
    ContentView()
        .modelContainer(PersistenceController.preview.container)
        .environmentObject(AppSettings())
        .environmentObject(LocalizationManager.shared)
}