import SwiftUI

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var localizationManager: LocalizationManager
    @State private var selectedTab = 0

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Daily Hadith Card
                    DailyHadithCard(hadith: viewModel.dailyHadith)

                    // Quick Actions
                    QuickActionsView(selectedTab: $selectedTab)

                    // Recent Collections
                    RecentCollectionsView()

                    // Holiday Section (if applicable)
                    if let holidayHadith = viewModel.holidayHadith {
                        HolidayHadithCard(hadith: holidayHadith)
                    }
                }
                .padding()
            }
            .navigationTitle(localizationManager.localizedString(.home))
            .navigationBarTitleDisplayMode(.large)
            .refreshable {
                await viewModel.loadDailyHadith()
            }
        }
        .task {
            await viewModel.loadDailyHadith()
        }
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

struct DailyHadithCard: View {
    let hadith: Hadith?
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "sun.max.fill")
                    .foregroundColor(.orange)
                Text(localizationManager.localizedString(.dailyHadith))
                    .font(.headline)
                Spacer()
                Text(localizationManager.localizedString(.today))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            if let hadith = hadith {
                VStack(alignment: .leading, spacing: 12) {
                    // Arabic Text (if enabled)
                    if settings.showArabicText {
                        Text(hadith.arabicText)
                            .font(.title2)
                            .multilineTextAlignment(.trailing)
                            .environment(\.layoutDirection, .rightToLeft)
                    }

                    // Selected Language Text
                    if !settings.pureArabicMode {
                        Text(hadith.text(for: settings.selectedLanguage))
                            .font(.body)
                            .multilineTextAlignment(settings.selectedLanguage.isRTL ? .trailing : .leading)
                    }

                    // Reference
                    HStack {
                        Text(hadith.reference)
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Spacer()
                        Text(hadith.grade)
                            .font(.caption)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.green.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
            } else {
                ProgressView()
                    .frame(maxWidth: .infinity, minHeight: 100)
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
        .shadow(radius: 2)
    }
}

struct QuickActionsView: View {
    @Binding var selectedTab: Int
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizationManager.localizedString(.quickActions))
                .font(.headline)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 2), spacing: 12) {
                QuickActionButton(title: localizationManager.localizedString(.search), icon: "magnifyingglass", color: .blue) {
                    selectedTab = 1 // Navigate to search tab
                }

                QuickActionButton(title: localizationManager.localizedString(.library), icon: "book.fill", color: .green) {
                    selectedTab = 2 // Navigate to library tab
                }

                QuickActionButton(title: localizationManager.localizedString(.random), icon: "shuffle", color: .purple) {
                    // Get random hadith - will be implemented in Phase 2
                }

                QuickActionButton(title: localizationManager.localizedString(.settings), icon: "gear", color: .orange) {
                    selectedTab = 3 // Navigate to settings tab
                }
            }
        }
    }
}

struct QuickActionButton: View {
    let title: String
    let icon: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundColor(color)
                Text(title)
                    .font(.caption)
                    .foregroundColor(.primary)
            }
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(8)
        }
    }
}

struct RecentCollectionsView: View {
    let collections = ["Sahih Bukhari", "Sahih Muslim", "Sunan Abu-Dawood", "Jami' at-Tirmidhi"]
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(localizationManager.localizedString(.collections))
                .font(.headline)

            ForEach(collections, id: \.self) { collection in
                HStack {
                    Image(systemName: "book.closed.fill")
                        .foregroundColor(.green)
                    Text(collection)
                        .font(.body)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .foregroundColor(.secondary)
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(8)
            }
        }
    }
}

struct HolidayHadithCard: View {
    let hadith: Hadith
    @EnvironmentObject var localizationManager: LocalizationManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(systemName: "star.fill")
                    .foregroundColor(.yellow)
                Text(localizationManager.localizedString(.holidayHadith))
                    .font(.headline)
                Spacer()
            }

            Text(hadith.englishText)
                .font(.body)
                .lineLimit(3)
        }
        .padding()
        .background(Color.yellow.opacity(0.1))
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.yellow, lineWidth: 1)
        )
    }
}

#Preview {
    HomeView()
        .environmentObject(AppSettings())
        .environmentObject(LocalizationManager.shared)
}
