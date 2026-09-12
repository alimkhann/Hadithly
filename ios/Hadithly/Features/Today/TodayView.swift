import ClerkKit
import ConvexMobile
import SwiftUI
import UIKit

struct DailyTranslation: Codable, Equatable {
    let text: String
    let language: String
    let source: String
    let sourceLabel: String
    let isAI: Bool
}

struct DailyHadith: Codable, Identifiable, Equatable {
    let _id: String
    let provider: String
    let canonicalId: String
    let providerHadithId: String
    let collectionSlug: String
    let collectionName: String
    let volumeId: String?
    let arabicText: String
    let englishText: String?
    let translation: DailyTranslation?
    let referenceDisplay: String
    let authenticity: ReaderAuthenticity

    var id: String { _id }
    var ref: HadithRef {
        HadithRef(hadithId: _id, collectionSlug: collectionSlug, collectionName: collectionName,
                  volumeId: volumeId, hadithNumber: providerHadithId, arabicText: arabicText,
                  englishText: translation?.text, referenceDisplay: referenceDisplay)
    }
    var readerHadith: ReaderHadith {
        ReaderHadith(_id: _id, provider: provider, canonicalId: canonicalId, providerHadithId: providerHadithId,
                     collectionSlug: collectionSlug, volumeId: volumeId, chapterId: nil, arabicText: arabicText,
                     englishText: englishText, narrator: nil, referenceDisplay: referenceDisplay,
                     collectionName: collectionName, chapterName: nil, authenticity: authenticity)
    }
}

struct ReaderOpenTarget: Identifiable, Equatable {
    let slug: String
    let name: String
    var volumeId: String?
    var hadithNumber: String?
    var source: ReaderTargetSource = .collection
    var position: ReadingPosition?
    var id: String { "\(slug)-\(volumeId ?? "-")-\(hadithNumber ?? "-")" }
}

/// Home is a preview, not a second reader: long readings expand into a bounded
/// native scroller instead of pushing the Library out of reach.
enum TodayContentPolicy {
    static let collapsedCharacterLimit = 680
    static let expandedScrollHeight: CGFloat = 420
    static func needsCollapsedPreview(arabic: String, translation: String?) -> Bool {
        arabic.count + (translation?.count ?? 0) > collapsedCharacterLimit
    }
}

private struct CachedDailyHadith: Codable { let hadith: DailyHadith }
private enum DailyHadithCache {
    private static func key(locale: String, timezone: String) -> String {
        let formatter = DateFormatter(); formatter.timeZone = TimeZone(identifier: timezone)
        formatter.dateFormat = "yyyy-MM-dd"
        return "today.daily-hadith.cache.v1.\(formatter.string(from: .now)).\(timezone).\(locale)"
    }
    static func load(locale: String, timezone: String) -> DailyHadith? {
        guard let data = UserDefaults.standard.data(forKey: key(locale: locale, timezone: timezone)) else { return nil }
        return try? JSONDecoder().decode(CachedDailyHadith.self, from: data).hadith
    }
    static func save(_ hadith: DailyHadith, locale: String, timezone: String) {
        guard let data = try? JSONEncoder().encode(CachedDailyHadith(hadith: hadith)) else { return }
        UserDefaults.standard.set(data, forKey: key(locale: locale, timezone: timezone))
    }
}

struct TodayView: View {
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @Environment(UserLibraryModel.self) private var library
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var dailyHadith: DailyHadith?
    @State private var isLoadingDaily = false
    @State private var loadFailed = false
    @State private var isOffline = false
    @State private var openTarget: ReaderOpenTarget?
    @State private var noteTarget: DailyHadith?
    @State private var showingDailySource = false

    private var preferences: ReaderPreferences { environment.preferences.preferences }
    private var readerPalette: ReaderPalette {
        ReaderPalette.resolved(preferences.theme, systemDark: systemColorScheme == .dark)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                header
                if library.continueReading != nil { continueReadingSection }
                dailySection
                libraryShelf
            }
            .padding(16)
        }
        .background(Theme.background)
        .navigationTitle("Today")
        .navigationBarTitleDisplayMode(.large)
        .task(id: preferences.translationLocale) {
            library.refresh()
            ReaderPrefetch.warmEntry(convex: environment.convex,
                                     target: ReaderPrefetchTargets.entryTarget(progress: library.continueReading))
            await loadDailyHadith()
        }
        .refreshable { await loadDailyHadith() }
        .fullScreenCover(item: $openTarget) { target in
            ReaderView(collectionSlug: target.slug, collectionName: target.name,
                       openVolumeId: target.volumeId, openHadithNumber: target.hadithNumber,
                       openPosition: target.position, targetSource: target.source)
        }
        .sheet(item: $noteTarget) { hadith in
            TodayNoteEditor(
                initialContent: library.notes.first(where: { $0.hadith?.hadithId == hadith._id })?.noteContent,
                onSave: { content in library.saveNote(hadith.ref, content: content); noteTarget = nil }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $showingDailySource) {
            if let dailyHadith {
                HadithSourceSheet(hadith: dailyHadith.readerHadith)
                    .environment(\.readerPalette, readerPalette)
                    .environment(\.readerTheme, preferences.theme)
                    .presentationDetents([.medium])
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(greeting).font(.title3.weight(.semibold)).foregroundStyle(Theme.textPrimary)
            Text(Date.now.formatted(date: .complete, time: .omitted)).font(.subheadline).foregroundStyle(Theme.textSecondary)
        }
    }

    private var greeting: String {
        guard let username = clerk.user?.username?.trimmingCharacters(in: .whitespacesAndNewlines), !username.isEmpty else {
            return "As-salamu alaykum"
        }
        return "As-salamu alaykum, \(username)"
    }

    private var continueReadingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Continue reading")
            ForEach(library.progress.filter { $0.hadith != nil }.sorted { $0.updatedAt > $1.updatedAt }.prefix(3)) { entry in
                if let hadith = entry.hadith {
                    Button {
                        openTarget = ReaderOpenTarget(slug: entry.collectionSlug, name: hadith.collectionName,
                                                       volumeId: hadith.volumeId, hadithNumber: hadith.hadithNumber,
                                                       source: .continueReading, position: entry.position)
                    } label: { ContinueReadingCard(hadith: hadith) }
                        .buttonStyle(.plain).accessibilityIdentifier("today.continueCard")
                }
            }
        }
    }

    private var dailySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Daily hadith")
            if let hadith = dailyHadith {
                DailyHadithCard(hadith: hadith, preferences: preferences, palette: readerPalette,
                                offline: isOffline, isBookmarked: library.isBookmarked(hadithId: hadith._id),
                                hasNote: library.notes.contains(where: { $0.hadith?.hadithId == hadith._id }),
                                onOpen: { openDaily(hadith) }, onBookmark: { library.toggleBookmark(hadith.ref) },
                                onNote: { noteTarget = hadith }, onCopy: { copy(hadith) }, onSource: { showingDailySource = true })
                    .accessibilityIdentifier("today.dailyCard")
            } else if isLoadingDaily {
                homeShell { HStack(spacing: 10) { ProgressView().tint(Theme.textSecondary); Text("Bringing today's hadith…").foregroundStyle(Theme.textSecondary) } }
            } else if loadFailed {
                homeShell { VStack(alignment: .leading, spacing: 8) { Text("Today's hadith could not load").font(.subheadline.weight(.medium)); Text("Pull down to try again.").font(.caption).foregroundStyle(Theme.textSecondary) } }
            } else {
                homeShell { VStack(alignment: .leading, spacing: 8) { Text("No eligible hadith is cached yet").font(.subheadline.weight(.medium)); Text("Open a collection in the Library and Today will prepare one from verified content.").font(.caption).foregroundStyle(Theme.textSecondary) } }
            }
        }
    }

    private var libraryShelf: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Library")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(Array(ReaderModels.collections.enumerated()), id: \.element.slug) { index, collection in
                        Button { openTarget = ReaderOpenTarget(slug: collection.slug, name: collection.name) } label: {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(String(format: "%02d", index + 1)).font(.caption.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                                Text(collection.name).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary).multilineTextAlignment(.leading).lineLimit(2)
                                Spacer(minLength: 0)
                                Text("Open").font(.caption.weight(.semibold)).foregroundStyle(Theme.accent)
                            }
                            .frame(width: 142, height: 148, alignment: .leading).padding(14)
                            .background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain).accessibilityIdentifier("today.library.\(collection.slug)")
                    }
                }
            }
        }
    }

    private func sectionTitle(_ title: LocalizedStringKey) -> some View { Text(title).font(.headline.weight(.semibold)).foregroundStyle(Theme.textPrimary) }
    private func homeShell<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content().frame(maxWidth: .infinity, alignment: .leading).padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16))
    }
    private func openDaily(_ hadith: DailyHadith) {
        openTarget = ReaderOpenTarget(slug: hadith.collectionSlug, name: hadith.collectionName,
                                      volumeId: hadith.volumeId, hadithNumber: hadith.providerHadithId, source: .today)
    }
    private func copy(_ hadith: DailyHadith) {
        var parts: [String] = []
        if preferences.arabicVisible { parts.append(hadith.arabicText) }
        if preferences.translationVisible, let text = hadith.translation?.text, !text.isEmpty { parts.append(text) }
        var source = "— \(hadith.collectionName) · Hadith \(hadith.providerHadithId) · \(hadith.authenticity.sourceName)"
        if preferences.translationVisible, hadith.translation?.isAI == true { source += " · AI translation" }
        UIPasteboard.general.string = parts.isEmpty ? source : parts.joined(separator: "\n\n") + "\n\n\(source)"
    }
    private func loadDailyHadith() async {
        isLoadingDaily = dailyHadith == nil
        defer { isLoadingDaily = false }
        do {
            let result: DailyHadith? = try await environment.convex.action(
                "actions/daily:getDailyHadith",
                with: ["timezone": TimeZone.current.identifier, "translationLocale": preferences.translationLocale]
            )
            dailyHadith = result
            if let result { DailyHadithCache.save(result, locale: preferences.translationLocale, timezone: TimeZone.current.identifier) }
            loadFailed = false; isOffline = false
        } catch {
            if let cached = DailyHadithCache.load(locale: preferences.translationLocale, timezone: TimeZone.current.identifier) { dailyHadith = cached; isOffline = true; loadFailed = false }
            else { loadFailed = true }
        }
    }
}

private struct ContinueReadingCard: View {
    let hadith: HadithRef
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "book").foregroundStyle(Theme.accent).frame(width: 38, height: 38).background(Theme.accentSoft).clipShape(Circle())
            VStack(alignment: .leading, spacing: 3) { Text(hadith.collectionName).font(.subheadline.weight(.medium)).foregroundStyle(Theme.textPrimary); Text(hadith.referenceDisplay).font(.caption2).foregroundStyle(Theme.textSecondary) }
            Spacer(); Image(systemName: "chevron.right").font(.caption).foregroundStyle(Theme.textSecondary)
        }.padding(16).background(Theme.surface).clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

private struct DailyHadithCard: View {
    let hadith: DailyHadith; let preferences: ReaderPreferences; let palette: ReaderPalette
    let offline: Bool; let isBookmarked: Bool; let hasNote: Bool
    let onOpen: () -> Void; let onBookmark: () -> Void; let onNote: () -> Void; let onCopy: () -> Void; let onSource: () -> Void
    @State private var expanded = false
    private var shouldCollapse: Bool { TodayContentPolicy.needsCollapsedPreview(arabic: hadith.arabicText, translation: hadith.translation?.text) }

    var body: some View {
        Group { if expanded && shouldCollapse { ScrollView { readingUnit }.frame(maxHeight: TodayContentPolicy.expandedScrollHeight) } else { readingUnit } }
            .padding(18).background(palette.surface).clipShape(RoundedRectangle(cornerRadius: 18))
            .contentShape(RoundedRectangle(cornerRadius: 18)).onTapGesture { onOpen() }.contextMenu { menuContents }
            .accessibilityElement(children: .contain).accessibilityAction(named: "Open in reader") { onOpen() }
            .accessibilityAction(named: isBookmarked ? "Remove Bookmark" : "Bookmark") { onBookmark() }
            .accessibilityAction(named: hasNote ? "Edit Note" : "Add Note") { onNote() }
            .accessibilityAction(named: "Copy") { onCopy() }
    }
    private var readingUnit: some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text(hadith.referenceDisplay).font(.caption.weight(.semibold)).foregroundStyle(palette.textPrimary); Spacer(); if offline { Text("Offline").font(.caption2.weight(.medium)).foregroundStyle(palette.textSecondary) } }
            Button(action: onSource) {
                HStack(spacing: 7) {
                    Circle().fill(ReaderGradeDot.color(for: ReaderGradeKind(normalizedGrade: hadith.authenticity.normalizedGrade), palette: palette)).frame(width: 8, height: 8)
                    Text(ReaderSourceLabel.headerText(for: hadith.readerHadith)).font(.caption.weight(.semibold)).foregroundStyle(palette.textPrimary)
                }
            }.buttonStyle(.plain).accessibilityIdentifier("today.authenticity")
            if preferences.arabicVisible { Text(hadith.arabicText).font(Theme.arabic(preferences.arabicFontSize, preferences.arabicFont)).lineSpacing(preferences.arabicFontSize * 0.75).foregroundStyle(palette.textPrimary).frame(maxWidth: .infinity, alignment: .leading).environment(\.layoutDirection, .rightToLeft).lineLimit(expanded || !shouldCollapse ? nil : 7) }
            if preferences.translationVisible {
                if let translation = hadith.translation {
                    Text(translation.text).font(.body).lineSpacing(5).foregroundStyle(palette.textPrimary).environment(\.layoutDirection, LocaleFallback.isRTL(translation.language) ? .rightToLeft : .leftToRight).lineLimit(expanded || !shouldCollapse ? nil : 7)
                    Text(translation.sourceLabel).font(.caption2).foregroundStyle(palette.textSecondary)
                } else { Text("No \(preferences.translationLocale) translation is available yet.").font(.caption).foregroundStyle(palette.textSecondary) }
            }
            if shouldCollapse { Button(expanded ? "Show less" : "Read more") { expanded.toggle() }.font(.caption.weight(.semibold)).foregroundStyle(Theme.accent).accessibilityIdentifier("today.expand") }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var menuContents: some View {
        Button(action: onBookmark) { Label(isBookmarked ? "Remove Bookmark" : "Bookmark", systemImage: isBookmarked ? "bookmark.fill" : "bookmark") }
        Button(action: onNote) { Label(hasNote ? "Edit Note" : "Add Note", systemImage: "square.and.pencil") }
        Button(action: onCopy) { Label("Copy", systemImage: "doc.on.doc") }
        if let url = ReaderShare.canonicalURL(collectionSlug: hadith.collectionSlug, providerHadithId: hadith.providerHadithId) { ShareLink(item: url) { Label("Share", systemImage: "square.and.arrow.up") } }
    }
}

private struct TodayNoteEditor: View {
    let initialContent: String?; let onSave: (String) -> Void
    @Environment(\.dismiss) private var dismiss; @State private var content = ""
    var body: some View {
        NavigationStack { TextEditor(text: $content).padding().navigationTitle("Note").toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }; ToolbarItem(placement: .confirmationAction) { Button("Save") { onSave(content) } } }.onAppear { content = initialContent ?? "" } }
    }
}
