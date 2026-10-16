import SwiftUI

/// Opens the Saved tab. Posted by the reader shortcut sheet's EDIT
/// affordance after dismissing the reader; the tab view selects Saved.
extension Notification.Name {
    static let hadithlyOpenSavedTab = Notification.Name("hadithlyOpenSavedTab")
}

/// Native sheet navigation shared by the reader's Contents, Search and Saved.
struct ReaderSheetChrome<Content: View>: View {
    let title: String
    let subtitle: String?
    let palette: ReaderPalette
    let closeIdentifier: String
    let titleIdentifier: String?
    let onClose: () -> Void
    var leadingActionTitle: String? = nil
    var leadingActionIdentifier: String? = nil
    var leadingAction: (() -> Void)? = nil
    @ViewBuilder let content: () -> Content
    @Environment(\.locale) private var locale

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 6)
                }
                content().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(palette.background)
            .navigationTitle(AppLocalization.string(title, locale: locale))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Text(AppLocalization.string(title, locale: locale)).font(.headline)
                        .foregroundStyle(palette.textPrimary).accessibilityIdentifier(titleIdentifier ?? "")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose).foregroundStyle(palette.interactive)
                        .accessibilityIdentifier(closeIdentifier)
                }
                if let leadingAction, let leadingActionTitle {
                    ToolbarItem(placement: .topBarLeading) {
                        Button(LocalizedStringKey(leadingActionTitle), action: leadingAction)
                            .foregroundStyle(palette.interactive).accessibilityIdentifier(leadingActionIdentifier ?? "")
                    }
                }
            }
        }
        .presentationDragIndicator(.visible)
    }
}

/// Uppercase section label for grouped sheet rows.
struct ReaderSheetSectionLabel: View {
    let text: String
    let palette: ReaderPalette

    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(palette.textSecondary.opacity(0.8))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

/// Volume index for the current collection, served from the cached outline.
/// Volumes expand to their source-provided chapters (R5, Sajda contents
/// sheet); outlines cached before R5 carry no chapters and keep rendering
/// exactly as before. Opening or dismissing this sheet never touches the
/// reader's pages, so the exact scroll position is preserved.
struct CollectionOutlineSheet: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    let model: ReaderModel
    let arabicVisible: Bool
    var translationVisible: Bool = true
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var expandedVolumes: Set<String> = []
    @State private var jumpText = ""
    @State private var jumpError: String?

    private var prefs: ReaderPreferences {
        var preferences = ReaderPreferences()
        preferences.arabicVisible = arabicVisible
        preferences.translationVisible = translationVisible
        return preferences
    }

    var body: some View {
        ReaderSheetChrome(
            title: "Contents",
            subtitle: model.collectionName,
            palette: palette,

            closeIdentifier: "reader.contents.close",
            titleIdentifier: "reader.contents.title",
            onClose: { dismiss() }
        ) {
            Group {
                if model.volumes.isEmpty {
                    ContentSkeleton(kind: .rows, label: "Building the index…")
                        .padding(20)
                } else {
                    List {
                        Section {
                            jumpField.listRowBackground(palette.surface)
                        } footer: {
                            Text(jumpError ?? "Jump to a hadith number, e.g. 57.")
                                .accessibilityIdentifier(jumpError == nil ? "reader.contents.jumpHint" : "reader.contents.jumpError")
                        }
                        Section("Volumes") {
                            ForEach(model.volumes) { volume in
                                Group {
                                    if let chapters = volume.chapters, !chapters.isEmpty { volumeDisclosure(volume, chapters: chapters) }
                                    else { volumeRow(volume) }
                                }.listRowBackground(palette.surface)
                            }
                        }
                    }
                    .listStyle(.insetGrouped)
                    .scrollContentBackground(.hidden)
                }
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
        .onAppear {
            if let selected = model.selectedVolumeId {
                expandedVolumes.insert(selected)
            }
        }
    }

    /// Jump-to-reference: a well-formed hadith number dismisses and
    /// navigates through the same path as canonical links (stale numbers
    /// land on the first volume's start); malformed input shows a quiet
    /// inline error and keeps the sheet open. Plain row, no card.
    private var jumpField: some View {
        HStack {
            TextField("Hadith number", text: $jumpText)
                .keyboardType(.numbersAndPunctuation)
                .accessibilityIdentifier("reader.contents.jump")
                .accessibilityLabel("Jump to hadith number")
                .onSubmit { submitJump() }
                .onChange(of: jumpText) { _, _ in jumpError = nil }
            Button("Go", action: submitJump)
                .buttonStyle(.borderless).disabled(jumpText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("reader.contents.jumpGo")
        }
    }

    private func submitJump() {
        let input = jumpText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard ReaderShare.isValidReferenceNumber(input) else {
            jumpError = "Enter a hadith number like 57 or 4.5."
            return
        }
        jumpError = nil
        dismiss()
        model.jumpToReference(input)
    }

    private func expansionBinding(for volumeId: String) -> Binding<Bool> {
        Binding(
            get: { expandedVolumes.contains(volumeId) },
            set: {
                let expanded = $0
                withAnimation(reducedMotion ? nil : .easeInOut(duration: InterfaceMotion.step)) {
                    if expanded { expandedVolumes.insert(volumeId) }
                    else { expandedVolumes.remove(volumeId) }
                }
            }
        )
    }

    /// A volume with source-provided chapters: plain rows (Sajda contents
    /// density) — the volume row carries title, first-chapter subtitle,
    /// count, and a rotating chevron; the expanded chapters are plain rows
    /// with hadith counts and minimal dividers. Chapters render only when
    /// the source provided them — Hadithly never synthesizes one.
    private func volumeDisclosure(_ volume: OutlineVolume, chapters: [OutlineChapter]) -> some View {
        DisclosureGroup(isExpanded: expansionBinding(for: volume.volumeId)) {
            Button {
                model.selectVolume(volume.volumeId); dismiss()
            } label: {
                Label("Open from the start", systemImage: "book")
            }
            .accessibilityIdentifier("reader.volume.\(volume.volumeId)")
            ForEach(chapters) { chapter in chapterRow(volume: volume, chapter: chapter) }
        } label: {
            volumeLabel(volume, isSelected: volume.volumeId == model.selectedVolumeId)
                .accessibilityIdentifier("reader.contents.volume.\(volume.volumeId)")
        }
        .tint(palette.interactive)
    }

    private func chapterRow(volume: OutlineVolume, chapter: OutlineChapter) -> some View {
        let display = ReaderChapterLine.displayTitle(title: chapter.title, arabicTitle: chapter.arabicTitle,
            arabicVisible: arabicVisible, translationVisible: translationVisible)
        return Button {
            model.selectChapter(volumeId: volume.volumeId, chapter: chapter); dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(display).foregroundStyle(palette.textPrimary)
                    if let subtitle = ReaderChapterLine.arabicSubtitle(title: display, arabicTitle: chapter.arabicTitle, arabicVisible: arabicVisible) {
                        Text(subtitle).font(.caption).foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                Text("\(chapter.hadithCount)").font(.subheadline.monospacedDigit()).foregroundStyle(palette.textSecondary)
            }
            .frame(minHeight: 44).contentShape(Rectangle())
        }
        .accessibilityIdentifier("reader.contents.chapter.\(volume.volumeId).\(chapter.firstProviderHadithId)")
    }

    private func volumeRow(_ volume: OutlineVolume) -> some View {
        let isSelected = volume.volumeId == model.selectedVolumeId
        return Button {
            model.selectVolume(volume.volumeId)
            dismiss()
        } label: {
            volumeLabel(volume, isSelected: isSelected, showsChevron: true)
                .padding(.vertical, 4)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.volume.\(volume.volumeId)")
    }

    private func volumeLabel(_ volume: OutlineVolume, isSelected: Bool, showsChevron: Bool = false) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(localizedVolumeTitle(volume.title, preferences: prefs))
                    .font(.subheadline.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(palette.textPrimary)
                if let chapter = volume.firstChapterTitle, !chapter.isEmpty {
                    Text(chapter)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            Text("\(volume.hadithCount)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.textSecondary)
            if isSelected {
                Image(systemName: "checkmark")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.interactive)
            } else if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary.opacity(0.6))
            }
        }
    }
}

struct ReaderSettingsSheet: View {
    let onLanguage: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var path: [ReaderPreferencePanel] = []

    var body: some View {
        NavigationStack(path: $path) {
            SettingsList("Settings") {
                ReaderPreferenceSections(prefix: "reader", onLanguage: onLanguage)
            }
            .navigationDestination(for: ReaderPreferencePanel.self) { panel in
                ReaderPreferenceDetail(panel: panel, prefix: "reader", onLanguage: onLanguage)
                    .toolbar { closeControl }
            }
            .toolbar { closeControl }
        }
        .tint(palette.interactive)
        .presentationDetents(path.isEmpty && !dynamicTypeSize.isAccessibilitySize ? [.height(480), .large] : [.large])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }

    private var closeControl: some ToolbarContent {
        ToolbarItem(placement: .confirmationAction) {
            Button("Done") { dismiss() }
                .accessibilityIdentifier("reader.settings.close")
        }
    }
}

/// Source and permission citations for a materialized translation.
struct TranslationCitationsSheet: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.dismiss) private var dismiss
    let translation: ReaderTranslation

    var body: some View {
        NavigationStack {
            ScrollView { TranslationSourceDetails(translation: translation).padding(20) }
                .background(palette.background)
                .navigationTitle("Sources")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Done") { dismiss() } } }
        }
    }
}

struct TranslationSourceDetails: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.openURL) private var openURL
    let translation: ReaderTranslation
    var showsTranslation = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if showsTranslation {
                Text(translation.translation).font(.subheadline).foregroundStyle(palette.textPrimary).lineSpacing(5)
            }

            if let reference = translation.sourceReferenceUrl, let url = URL(string: reference) {
                Button {
                    openURL(url)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "book")
                        Text(verbatim: reference)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .font(.footnote)
                    .foregroundStyle(palette.interactive)
                }
                .buttonStyle(.plain)
            }

            Divider().overlay(palette.divider)

            if translation.citations.isEmpty {
                Text("No external sources were cited for this translation.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            } else {
                ForEach(Array(translation.citations.enumerated()), id: \.offset) { index, citation in
                    citationRow(index: index + 1, citation: citation)
                }
            }

            if translation.source == "gemini_ai" {
            Text("This translation was generated by AI (\(translation.aiModel ?? "model unavailable")). It is not an authoritative rendering; verify important meanings against a qualified source.")
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
                .padding(.top, 4)
                .accessibilityIdentifier("translation.sources.ai")
            } else {
                Text("e3.community_sources_message").font(.caption2).foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("translation.sources.community")
            }
        }

    }

    private func citationRow(index: Int, citation: ReaderCitation) -> some View {
        Button {
            if let url = URL(string: citation.url) {
                openURL(url)
            }
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text("\(index)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .frame(width: 20)
                VStack(alignment: .leading, spacing: 2) {
                    Text(citation.title ?? citation.url)
                        .font(.footnote)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if let domain = citation.domain {
                        Text(domain)
                            .font(.caption2)
                            .foregroundStyle(palette.interactive)
                    }
                }
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary)
            }
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }

}

/// Private report path for the currently displayed stored translation.
struct TranslationReportSheet: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    let model: ReaderModel
    let translation: ReaderTranslation
    let referenceDisplay: String

    @Environment(\.dismiss) private var dismiss
    @State private var reason = ""
    @State private var isSubmitting = false
    @State private var wasSubmitted = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            Group {
                if wasSubmitted {
                    VStack(spacing: 12) {
                        Image(systemName: "checkmark.circle")
                            .font(.title2)
                            .foregroundStyle(palette.interactive)
                        Text("Report sent privately")
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                        Text("e3.report_saved_detail")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .padding(32)
                    .accessibilityIdentifier("report.confirmation")
                } else {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(referenceDisplay)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                        Text("Describe a meaning, wording, or attribution concern. Reports are private and are not votes or ratings.")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                        TextEditor(text: $reason)
                            .focused($isFocused)
                            .font(.body)
                            .foregroundStyle(palette.textPrimary)
                            .scrollContentBackground(.hidden)
                            .padding(10)
                            .frame(minHeight: 130)
                            .background(palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .accessibilityIdentifier("report.editor")
                        if let errorMessage {
                            Text(errorMessage)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                        Button {
                            Task { await submit() }
                        } label: {
                            Text(isSubmitting ? "Sending…" : "Send private report")
                                .font(.subheadline.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 13)
                                .background(canSubmit ? palette.interactive : palette.surfaceElevated)
                                .foregroundStyle(canSubmit ? palette.onInteractive : palette.textSecondary)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .buttonStyle(.plain)
                        .disabled(!canSubmit)
                        .accessibilityIdentifier("report.submit")
                    }
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .navigationTitle("Report translation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(wasSubmitted ? "Done" : "Cancel") { dismiss() }
                        .foregroundStyle(palette.interactive)
                }
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
        .onAppear { isFocused = true }
    }

    private var canSubmit: Bool {
        !isSubmitting && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func submit() async {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            try await model.reportTranslation(translation, reason: trimmed)
            isFocused = false
            wasSubmitted = true
        } catch {
            errorMessage = ReaderModels.errorMessage(of: error)
        }
    }
}

// MARK: - English-text search (R6 round 3)

/// Functional search over the cached Sunnah.now English text through the
/// public `hadiths:searchEnglish` query. Same-collection only, so tapping a
/// result navigates to the exact hadith through the R2 jump path. The query
/// deploys after this client task, so failures degrade to a quiet error
/// state instead of blocking the sheet.
struct ReaderSearchSheet: View {
    let collectionSlug: String
    let collectionName: String
    /// Injected for tests: production passes the model's query call.
    let search: (String) async -> [EnglishSearchResult]
    let onOpen: (EnglishSearchResult) -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @State private var query = ""
    @State private var results: [EnglishSearchResult] = []
    @State private var isLoading = false
    @State private var didFail = false
    @State private var generation = 0
    @State private var searchPresented = true
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ReaderSheetChrome(
            title: "Search",
            subtitle: collectionName,
            palette: palette,

            closeIdentifier: "reader.search.close",
            titleIdentifier: "reader.search.title",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if isLoading {
                    loadingState
                } else if didFail {
                    failureState
                } else if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    hintState
                } else if results.isEmpty {
                    emptyState
                } else {
                    resultsList
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            // The content fills all allocated vertical space so the initial
            // and empty states center within the full detent height — no
            // dead blank region below short content.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
        .onChange(of: query) { _, _ in scheduleSearch() }
        .searchable(text: $query, isPresented: $searchPresented, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search English text")
        .onSubmit(of: .search) { scheduleSearch() }
        .onDisappear { searchTask?.cancel() }
    }

    private var resultsList: some View {
        List {
            Section {
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button { onOpen(result) } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(result.referenceDisplay).font(.subheadline.weight(.semibold)).foregroundStyle(palette.textPrimary)
                            Text(result.snippet).font(.subheadline).foregroundStyle(palette.textSecondary).lineLimit(3)
                        }.padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .accessibilityLabel("\(result.referenceDisplay), Sunnah.now English text")
                    .accessibilityIdentifier("reader.search.result.\(index)")
                }
            } header: { Text("Sunnah.now English (\(results.count))").accessibilityIdentifier("reader.search.section") }
        }.listStyle(.plain).scrollContentBackground(.hidden)
    }

    private var loadingState: some View {
        ContentSkeleton(kind: .rows, label: "Searching cached English…")
            .padding(.vertical, 12)
            .accessibilityIdentifier("reader.search.loading")
    }

    private var hintState: some View {
        QuietEmptyState(title: "Search this collection", message: "Find a word or phrase in the available English text.", symbol: "magnifyingglass")
            .accessibilityIdentifier("reader.search.hint")
    }
    private var emptyState: some View {
        QuietEmptyState(title: "No results", message: "Try another word or a shorter phrase.", symbol: "magnifyingglass")
            .accessibilityIdentifier("reader.search.empty")
    }
    private var failureState: some View {
        VStack {
            QuietEmptyState(title: "Search is unavailable", message: "Try again when you are connected. You can keep reading.", symbol: "wifi.exclamationmark")
            Button("Try again") { scheduleSearch() }.buttonStyle(.bordered).padding(.bottom, 24)
        }.accessibilityIdentifier("reader.search.error")
    }

    private func scheduleSearch() {
        searchTask?.cancel()
        generation += 1
        let current = generation
        let text = query
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            isLoading = false
            didFail = false
            results = []
            return
        }
        isLoading = true
        didFail = false
        searchTask = Task { @MainActor in
            do { try await Task.sleep(for: .seconds(0.4)) } catch { return }
            guard !Task.isCancelled, current == generation else { return }
            let rows = await search(text)
            guard !Task.isCancelled, current == generation else { return }
            // An empty page from a non-blank query is a genuine no-match;
            // the query call itself degrades to [] on failure, and the
            // sheet cannot tell them apart — both render the quiet empty
            // state rather than an alarming error.
            results = rows
            isLoading = false
        }
    }
}

// MARK: - Reader Bookmarks & Notes shortcut (R6 round 3)

/// A quiet reader shortcut over the private saved list: segmented
/// Bookmarks/Favorites/Notes tabs with reference + relative-time rows.
/// Tapping a row navigates to the exact hadith; EDIT opens the Saved tab
/// destination. Full folders and filters stay H3 in the Saved tab — this
/// sheet never duplicates them.
struct ReaderSavedShortcutSheet: View {
    typealias Tab = SavedContentFilter
    let onOpen: (HadithRef) -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(UserLibraryModel.self) private var library
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reducedMotion
    @State private var tab: Tab = .bookmarks
    @State private var folderId: String?
    @State private var pendingRemoval: SavedFacetRemoval?
    @State private var undoNotice: SavedUndoNotice?

    private var entries: [SavedItemEntry] {
        library.savedItems.filter { item in
            let matches = switch tab {
            case .all: true
            case .bookmarks: item.bookmarkCreatedAt != nil
            case .favorites: item.favoriteCreatedAt != nil
            case .notes: item.noteContent != nil
            }
            return matches && (folderId == nil || item.folderId == folderId)
        }.sorted { $0.sortDate > $1.sortDate }
    }

    var body: some View {
        ReaderSheetChrome(
            title: "Bookmarks & Notes",
            subtitle: "Your private saved reading",
            palette: palette,

            closeIdentifier: "reader.savedShortcut.close",
            titleIdentifier: "reader.savedShortcut.title",
            onClose: { dismiss() },
            leadingActionTitle: "Edit",
            leadingActionIdentifier: "reader.savedShortcut.edit",
            leadingAction: onEdit
        ) {
            VStack(alignment: .leading, spacing: 10) {
                if !library.folders.isEmpty { folderControl }
                if library.savedItems.isEmpty && library.loadState == .loading {
                    ContentSkeleton(kind: .rows, label: "Loading saved items").padding(.top, 16)
                } else if library.savedItems.isEmpty && library.loadState == .failed {
                    VStack(spacing: 12) {
                        Text("Saved items could not load").font(.subheadline).foregroundStyle(palette.textSecondary)
                        Button("Retry") { library.refresh() }.buttonStyle(.bordered)
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if entries.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(entries) { entry in
                                SharedSavedItemRow(item: entry, folders: library.folders, folderName: library.folders.first(where: { $0.id == entry.folderId })?.name, showsFolder: folderId == nil, onOpen: onOpen, onRemove: requestRemoval, onMove: { library.assignFolder(hadithId: entry.hadithId, folderId: $0) }, onSuggestTranslation: onOpen)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            // The content fills all allocated vertical space so the empty
            // state centers within the full detent height — no dead blank
            // region below short content.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .safeAreaInset(edge: .bottom) {
            SavedFilterBar(selection: $tab, identifier: "reader.savedShortcut.filter")
                .frame(maxWidth: 340).padding(.horizontal, 20).padding(.vertical, 8)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let notice = undoNotice {
                SavedUndoBanner(notice: notice, onExpire: { undoNotice = nil })
            } else if let deletion = library.lastFolderDeletion {
                SavedUndoBanner(notice: SavedUndoNotice(id: deletion.undoID, message: "Folder \(deletion.name) deleted", undo: library.undoDeleteFolder, deadline: deletion.undoDeadline), onExpire: { library.clearFolderDeletion() })
            }
        }
        .animation(reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: InterfaceMotion.reveal), value: undoNotice?.id)
        .animation(reducedMotion ? nil : .timingCurve(0.22, 1, 0.36, 1, duration: InterfaceMotion.reveal), value: library.lastFolderDeletion?.undoID)
        .confirmationDialog("Remove saved item?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            if let removal = pendingRemoval {
            Button("Remove", role: .destructive) { performRemoval(removal); pendingRemoval = nil }
            Button("Remove and don't ask again", role: .destructive) { environment.savedSafety.confirmsRemoval = false; performRemoval(removal); pendingRemoval = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }

    private var folderControl: some View {
        Menu {
            Picker("Folder", selection: $folderId) {
                Text("All folders").tag(String?.none)
                ForEach(library.folders) { folder in Text(folder.name).tag(Optional(folder.id)) }
            }
            if !library.folders.isEmpty {
                Menu("Delete folder") {
                    ForEach(library.folders) { folder in
                        Button(folder.name, role: .destructive) {
                            if folderId == folder.id { folderId = nil }
                            library.deleteFolder(folder)
                        }
                    }
                }
            }
        } label: {
            Label(library.folders.first(where: { $0.id == folderId })?.name ?? String(localized: "All folders"), systemImage: "folder")
                .font(.subheadline).frame(minHeight: 44)
        }
        .tint(palette.textSecondary)
    }

    /// Sajda bookmarks-tab rows: a tinted icon, the reference title with
    /// its relative stamp, a chevron, and minimal dividers. Notes keep one
    /// content line so they stay distinguishable.
    private func requestRemoval(_ removal: SavedFacetRemoval) { if environment.savedSafety.confirmsRemoval { pendingRemoval = removal } else { performRemoval(removal) } }

    private func performRemoval(_ removal: SavedFacetRemoval) {
        switch removal {
        case .bookmark(let item, let ref): if let date = item.bookmarkCreatedAt { library.toggleBookmark(ref); undoNotice = SavedUndoNotice(message: "Bookmark removed") { library.restoreBookmark(ref, createdAt: date); undoNotice = nil } }
        case .favorite(let item, let ref): if let date = item.favoriteCreatedAt { library.toggleFavorite(ref); undoNotice = SavedUndoNotice(message: "Favorite removed") { library.restoreFavorite(ref, createdAt: date); undoNotice = nil } }
        case .note(let item, let ref): if let content = item.noteContent { library.deleteNote(ref); undoNotice = SavedUndoNotice(message: "Note deleted") { library.restoreNote(ref, content: content, createdAt: item.createdAt, updatedAt: item.updatedAt); undoNotice = nil } }
        }
    }

    private var emptyState: some View {
        QuietEmptyState(title: folderId == nil ? tab.emptyTitle : "This folder is empty",
            message: folderId == nil ? tab.emptyMessage : "Move saved hadiths into this folder from their menu.", symbol: folderId == nil ? tab.symbol : "folder")
            .accessibilityIdentifier("reader.savedShortcut.empty")
    }

}

// MARK: - Native bookmark placement

struct ReaderBookmarkPlacementDialog: View {
    let pageFirst: ReaderHadith?
    let positioned: ReaderHadith
    let onChoose: (ReaderHadith) -> Void
    let onCancel: () -> Void
    @State private var presented = false
    @State private var completed = false

    var body: some View {
        Color.clear.frame(width: 0, height: 0)
            .confirmationDialog("Add bookmark", isPresented: $presented, titleVisibility: .visible) {
                if let target = ReaderBookmarkTarget.resolve(placement: .pageStart, pageFirst: pageFirst, positioned: positioned) {
                    Button("Start of page") { finish { onChoose(target) } }
                }
                Button("Current hadith \(positioned.referenceDisplay)") { finish { onChoose(positioned) } }
                Button("Cancel", role: .cancel) { finish(onCancel) }
            }
            .onAppear { presented = true }
            // SwiftUI dismisses its presentation binding before a chosen action.
            // Defer outside-tap cancellation until that action has completed.
            .onChange(of: presented) { _, shown in
                if !shown { Task { @MainActor in await Task.yield(); finish(onCancel) } }
            }
    }
    private func finish(_ action: () -> Void) {
        guard !completed else { return }
        completed = true
        action()
    }

}

struct ReaderStoredTranslationView: View {
    let text: String
    let translation: ReaderTranslation?
    let palette: ReaderPalette

    var body: some View {
        VStack(spacing: 10) {
            Text(text)
                .font(.system(size: 16, weight: .regular)).lineSpacing(7)
                .multilineTextAlignment(.leading).foregroundStyle(palette.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(translation?.source == "gemini_ai" ? "reader.aiTranslation" : "reader.translation")
        }
    }
}
