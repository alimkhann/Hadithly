import SwiftUI
import ClerkKit

enum ContinueWidgetRoute {
    static func target(from entries: [ProgressEntry]) -> ReaderOpenTarget? {
        guard let entry = entries
            .filter({ $0.hadith != nil && $0.position != nil })
            .max(by: { $0.updatedAt < $1.updatedAt }),
              let hadith = entry.hadith,
              let position = entry.position
        else { return nil }
        return ReaderOpenTarget(
            slug: entry.collectionSlug, name: hadith.collectionName,
            volumeId: hadith.volumeId, hadithNumber: hadith.hadithNumber,
            source: .continueReading, position: position
        )
    }
}

/// Four tabs: Today / Library / Saved / Settings.
/// There is no Community tab by design — translation contributions happen
/// contextually in the reader (Phase 4), not through social features.
struct MainTabsView: View {
    @Binding var showSignIn: Bool

    @Environment(AppEnvironment.self) private var environment

    @State private var linkTarget: ReaderOpenTarget?
    @State private var selection = 0
    @State private var continueRequestPending = false

    var body: some View {
        TabView(selection: $selection) {
            NavigationStack {
                TodayView()
            }
            .tabItem { Label("Today", systemImage: "sun.max") }
            .tag(0)

            NavigationStack {
                LibraryView()
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }
            .tag(1)

            NavigationStack {
                SavedView()
            }
            .tabItem { Label("Saved", systemImage: "bookmark") }
            .tag(2)

            NavigationStack {
                SettingsView(showSignIn: $showSignIn)
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(3)
        }
        .tint(Theme.accent)
        .fullScreenCover(item: $linkTarget) { target in
            ReaderView(
                collectionSlug: target.slug,
                collectionName: target.name,
                openVolumeId: target.volumeId,
                openHadithNumber: target.hadithNumber,
                openPosition: target.position,
                targetSource: target.source
            )
        }
        .task {
            environment.library.refresh()
            writeContinueWidget()
            consumePendingLink()
        }
        .onChange(of: environment.links.pendingLink) { _, newValue in
            // consumePending clears the queue, so the nil transition must
            // not re-trigger a consume that would close the reader cover.
            guard newValue != nil else { return }
            consumePendingLink()
        }
        .onChange(of: environment.links.pendingContinueRequest) { _, newValue in
            guard newValue != nil else { return }
            consumeContinueWidget()
        }
        .onChange(of: environment.library.progress) { _, _ in
            writeContinueWidget()
            resolveContinueWidgetRequest()
        }
        .onChange(of: environment.widgetProgress.progressSummaries) { _, _ in
            writeContinueWidget()
        }
        .onChange(of: environment.preferences.preferences) { _, _ in
            writeContinueWidget()
        }
        // The reader shortcut sheet's EDIT affordance dismisses the reader
        // and lands here on the Saved tab.
        .onReceive(NotificationCenter.default.publisher(for: .hadithlyOpenSavedTab)) { _ in
            selection = 2
        }
    }

    /// A canonical link queued before (or while) the tabs appear lands in
    /// the reader exactly once; signed-out readers keep full access.
    private func consumePendingLink() {
        guard let link = environment.links.consumePending() else { return }
        linkTarget = ReaderOpenTarget(
            slug: link.collectionSlug,
            name: link.collectionName,
            hadithNumber: link.providerHadithId,
            source: .canonicalLink
        )
    }

    private func consumeContinueWidget() {
        guard environment.links.consumeContinueRequest() else { return }
        continueRequestPending = true
        environment.library.refresh()
        resolveContinueWidgetRequest()
    }

    private func resolveContinueWidgetRequest() {
        guard continueRequestPending,
              let target = ContinueWidgetRoute.target(from: environment.library.progress)
        else { return }
        linkTarget = target
        continueRequestPending = false
    }

    private func writeContinueWidget() {
        guard let entry = environment.library.continueReading, let hadith = entry.hadith else {
            WidgetSnapshotStore.saveContinue(nil)
            return
        }
        let preferences = environment.preferences.preferences
        let summary = environment.widgetProgress.progressSummaries[entry.collectionSlug]
        let ordinal = Double(hadith.hadithNumber ?? "")
        let total = summary?.totalHadiths
        let fraction = ordinal.flatMap { read in total.map { max(0, min(1, read / $0)) } }
        let progressLabel = (ordinal != nil && total != nil) ? "Hadith \(Int(ordinal!)) of \(Int(total!))" : "Resume reading"
        let visibleText = preferences.translationVisible ? hadith.englishText : nil
        let fallbackText = preferences.arabicVisible ? hadith.arabicText : ""
        WidgetSnapshotStore.saveContinue(WidgetContinueSnapshot(
            reference: hadith.referenceDisplay,
            arabicExcerpt: WidgetContinueSnapshot.boundedExcerpt(hadith.arabicText),
            translationExcerpt: WidgetContinueSnapshot.boundedExcerpt(visibleText ?? fallbackText),
            arabicVisible: preferences.arabicVisible,
            translationVisible: preferences.translationVisible,
            progressFraction: fraction,
            progressLabel: progressLabel,
            locale: preferences.uiLocale,
            updatedAt: entry.updatedAt
        ))
    }
}

#Preview {
    MainTabsView(showSignIn: .constant(false))
        .preferredColorScheme(.dark)
}
