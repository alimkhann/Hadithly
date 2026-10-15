import SwiftUI

/// Opens the Saved tab. Posted by the reader shortcut sheet's EDIT
/// affordance after dismissing the reader; the tab view selects Saved.
extension Notification.Name {
    static let hadithlyOpenSavedTab = Notification.Name("hadithlyOpenSavedTab")
}

/// Shared Sajda sheet chrome (R6 round 3): grabber, title row with an X
/// close circle, grouped card rows, uppercase section labels. Theme-aware
/// through the reader palette; every sheet passes its own identifiers.
struct ReaderSheetChrome<Content: View>: View {
    let title: String
    let subtitle: String?
    let palette: ReaderPalette
    let grabberIdentifier: String
    let closeIdentifier: String
    let titleIdentifier: String?
    let onClose: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(palette.textSecondary.opacity(0.45))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .accessibilityIdentifier(grabberIdentifier)
                .accessibilityLabel("Sheet handle")
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityIdentifier(titleIdentifier ?? "")
                    if let subtitle, !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                }
                Spacer()
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.callout.weight(.semibold))
                        .foregroundStyle(palette.textSecondary)
                        .frame(width: 44, height: 44)
                        .background(palette.surfaceElevated)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                .accessibilityIdentifier(closeIdentifier)
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            content()
        }
        // Reader palette to the sheet edges, so Light/Paper readers never
        // get system-background margins around the sheet content.
        .background(palette.background.ignoresSafeArea())
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
            grabberIdentifier: "reader.contents.grabber",
            closeIdentifier: "reader.contents.close",
            titleIdentifier: "reader.contents.title",
            onClose: { dismiss() }
        ) {
            Group {
                if model.volumes.isEmpty {
                    VStack(spacing: 10) {
                        ProgressView()
                            .tint(palette.textSecondary)
                        Text("Building the index…")
                            .font(.caption)
                            .foregroundStyle(palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 4) {
                            jumpField
                            ReaderSheetSectionLabel(text: "VOLUMES", palette: palette)
                                .padding(.top, 8)
                            ForEach(model.volumes) { volume in
                                if let chapters = volume.chapters, !chapters.isEmpty {
                                    volumeDisclosure(volume, chapters: chapters)
                                } else {
                                    volumeRow(volume)
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 4)
                        .padding(.bottom, 16)
                    }
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
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TextField("Hadith number", text: $jumpText)
                    .keyboardType(.numbersAndPunctuation)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("reader.contents.jump")
                    .accessibilityLabel("Jump to hadith number")
                    .onSubmit { submitJump() }
                    .onChange(of: jumpText) { _, _ in jumpError = nil }
                Button("Go") { submitJump() }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(palette.interactive)
                    .frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("reader.contents.jumpGo")
            }
            if let jumpError {
                Text(jumpError)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("reader.contents.jumpError")
            } else {
                Text("Jump to a hadith number, e.g. 57.")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary.opacity(0.7))
            }
            Divider().overlay(palette.divider.opacity(0.6))
        }
        .padding(.vertical, 4)
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
                if $0 { expandedVolumes.insert(volumeId) }
                else { expandedVolumes.remove(volumeId) }
            }
        )
    }

    /// A volume with source-provided chapters: plain rows (Sajda contents
    /// density) — the volume row carries title, first-chapter subtitle,
    /// count, and a rotating chevron; the expanded chapters are plain rows
    /// with hadith counts and minimal dividers. Chapters render only when
    /// the source provided them — Hadithly never synthesizes one.
    private func volumeDisclosure(_ volume: OutlineVolume, chapters: [OutlineChapter]) -> some View {
        let isSelected = volume.volumeId == model.selectedVolumeId
        return DisclosureGroup(isExpanded: expansionBinding(for: volume.volumeId)) {
            VStack(spacing: 0) {
                Button {
                    model.selectVolume(volume.volumeId)
                    dismiss()
                } label: {
                    HStack {
                        Text("Open \(localizedVolumeTitle(volume.title, preferences: prefs)) from the start")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reader.volume.\(volume.volumeId)")
                ForEach(chapters) { chapter in
                    chapterRow(volume: volume, chapter: chapter)
                }
            }
            .padding(.top, 2)
        } label: {
            // The identifier sits on the label subtree only: an identifier
            // on the DisclosureGroup itself propagates into the expanded
            // content and stomps the chapter rows' own identifiers. The
            // DisclosureGroup renders its own rotating chevron; the plain
            // row below adds one explicitly.
            volumeLabel(volume, isSelected: isSelected)
                .contentShape(Rectangle())
                .accessibilityIdentifier("reader.contents.volume.\(volume.volumeId)")
        }
        .tint(palette.textSecondary)
        .padding(.vertical, 10)
    }

    private func chapterRow(volume: OutlineVolume, chapter: OutlineChapter) -> some View {
        let display = ReaderChapterLine.displayTitle(
            title: chapter.title,
            arabicTitle: chapter.arabicTitle,
            arabicVisible: arabicVisible,
            translationVisible: translationVisible
        )
        return Button {
            model.selectChapter(volumeId: volume.volumeId, chapter: chapter)
            dismiss()
        } label: {
            VStack(spacing: 0) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(display)
                            .font(.subheadline)
                            .foregroundStyle(palette.textPrimary)
                            .multilineTextAlignment(.leading)
                        if let subtitle = ReaderChapterLine.arabicSubtitle(
                            title: display,
                            arabicTitle: chapter.arabicTitle,
                            arabicVisible: arabicVisible
                        ) {
                            Text(subtitle)
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Text("\(chapter.hadithCount)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(palette.textSecondary)
                }
                .padding(.vertical, 10)
                Divider().overlay(palette.divider.opacity(0.6))
            }
            // Plain rows have no background fill: the explicit content
            // shape keeps the whole row (including spacer gaps) tappable.
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(display), \(chapter.hadithCount) hadiths")
        .accessibilityIdentifier("reader.contents.chapter.\(volume.volumeId).\(chapter.firstProviderHadithId)")
    }

    private func volumeRow(_ volume: OutlineVolume) -> some View {
        let isSelected = volume.volumeId == model.selectedVolumeId
        return Button {
            model.selectVolume(volume.volumeId)
            dismiss()
        } label: {
            volumeLabel(volume, isSelected: isSelected, showsChevron: true)
                .padding(.vertical, 10)
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
    @Environment(\.readerTheme) private var readerTheme
    let translation: ReaderTranslation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(translation.translation)
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                        .lineSpacing(5)

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
                .padding(20)
            }
            .background(palette.background)
            .navigationTitle(translation.source == "gemini_ai" ? Text("AI sources") : Text("e3.translation_sources"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(palette.interactive)
                }
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
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
    @FocusState private var isFocused: Bool

    var body: some View {
        ReaderSheetChrome(
            title: "Search",
            subtitle: collectionName,
            palette: palette,
            grabberIdentifier: "reader.search.grabber",
            closeIdentifier: "reader.search.close",
            titleIdentifier: "reader.search.title",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                searchField
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
        .onAppear { isFocused = true }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.callout)
                .foregroundStyle(palette.textSecondary)
            TextField("Search English text", text: $query)
                .font(.body)
                .foregroundStyle(palette.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("reader.search.field")
                .accessibilityLabel("Search cached English text")
            if !query.isEmpty {
                Button {
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.callout)
                        .foregroundStyle(palette.textSecondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
                .accessibilityIdentifier("reader.search.clear")
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
        .background(palette.surfaceElevated)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var resultsList: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {                ReaderSheetSectionLabel(
                    text: "SUNNAH.NOW ENGLISH (\(results.count))",
                    palette: palette
                )
                .accessibilityIdentifier("reader.search.section")
                ForEach(Array(results.enumerated()), id: \.element.id) { index, result in
                    Button {
                        onOpen(result)
                    } label: {
                        VStack(spacing: 0) {
                            HStack(alignment: .top, spacing: 12) {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(result.snippet.isEmpty ? result.referenceDisplay : result.snippet)
                                        .font(.subheadline)
                                        .foregroundStyle(palette.textPrimary)
                                        .multilineTextAlignment(.leading)
                                        .lineLimit(4)
                                    Text("\(result.referenceDisplay) · Sunnah.now English")
                                        .font(.caption)
                                        .foregroundStyle(palette.textSecondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(palette.textSecondary)
                                    .padding(.top, 4)
                            }
                            .padding(.vertical, 12)
                            Divider().overlay(palette.divider.opacity(0.6))
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(result.referenceDisplay), Sunnah.now English text")
                    .accessibilityIdentifier("reader.search.result.\(index)")
                }
            }
            .padding(.vertical, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var loadingState: some View {
        HStack(spacing: 10) {
            ProgressView()
                .tint(palette.textSecondary)
            Text("Searching cached English…")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 12)
        .accessibilityIdentifier("reader.search.loading")
    }

    private var hintState: some View {
        Text("Search the cached Sunnah.now English text of this collection.")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("reader.search.hint")
    }

    private var emptyState: some View {
        Text("No matches in the cached English text.")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("reader.search.empty")
    }

    private var failureState: some View {
        Text("Search is unavailable right now. Reading continues as usual.")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 8)
            .accessibilityIdentifier("reader.search.error")
    }

    /// Debounced search: waits 0.4 s after the last keystroke, then runs
    /// one query per generation. Blank text clears without a backend call.
    private func scheduleSearch() {
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
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(0.4))
            guard current == generation else { return }
            let rows = await search(text)
            guard current == generation else { return }
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
    enum Tab: String, CaseIterable {
        case all
        case bookmarks
        case favorites
        case notes

        var title: String {
            switch self {
            case .all: "All"
            case .bookmarks: "Bookmarks"
            case .favorites: "Favorites"
            case .notes: "Notes"
            }
        }

        var identifier: String { "reader.savedShortcut.tab.\(rawValue)" }
    }

    let onOpen: (HadithRef) -> Void
    let onEdit: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(UserLibraryModel.self) private var library
    @Environment(AppEnvironment.self) private var environment
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
            grabberIdentifier: "reader.savedShortcut.grabber",
            closeIdentifier: "reader.savedShortcut.close",
            titleIdentifier: "reader.savedShortcut.title",
            onClose: { dismiss() }
        ) {
            VStack(alignment: .leading, spacing: 10) {
                segmentedControl
                folderControl
                if entries.isEmpty {
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
                editButton
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 16)
            // The content fills all allocated vertical space so the empty
            // state centers within the full detent height — no dead blank
            // region below short content.
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .overlay(alignment: .bottom) {
            if let notice = undoNotice {
                SavedUndoBanner(notice: notice, onExpire: { undoNotice = nil })
            } else if let deletion = library.lastFolderDeletion {
                SavedUndoBanner(notice: SavedUndoNotice(message: "Folder \(deletion.name) deleted", undo: library.undoDeleteFolder), onExpire: { library.clearFolderDeletion() })
            }
        }
        .confirmationDialog("Remove saved item?", isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })) {
            if let removal = pendingRemoval {
            Button("Remove", role: .destructive) { performRemoval(removal); pendingRemoval = nil }
            Button("Remove and don't ask again", role: .destructive) { environment.savedSafety.confirmsRemoval = false; performRemoval(removal); pendingRemoval = nil }
            }
            Button("Cancel", role: .cancel) {}
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }

    private var segmentedControl: some View {
        HStack(spacing: 4) {
            ForEach(Tab.allCases, id: \.self) { candidate in
                Button {
                    tab = candidate
                } label: {
                    Text(candidate.title)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(
                            tab == candidate ? palette.textPrimary : palette.textSecondary
                        )
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            tab == candidate
                                ? palette.surfaceElevated : Color.clear
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(tab == candidate ? .isSelected : [])
                .accessibilityIdentifier(candidate.identifier)
            }
        }
        .padding(4)
        .background(palette.surface)
        .clipShape(Capsule())
    }

    private var folderControl: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button { folderId = nil } label: {
                    Text("All folders")
                        .font(.subheadline.weight(folderId == nil ? .semibold : .regular))
                        .foregroundStyle(folderId == nil ? palette.interactive : palette.textSecondary)
                }
                .buttonStyle(.bordered)
                .tint(folderId == nil ? palette.interactive : palette.textSecondary)
                ForEach(library.folders) { folder in
                    Button(folder.name) { folderId = folder.id }
                        .buttonStyle(.bordered)
                        .tint(folderId == folder.id ? palette.interactive : palette.textSecondary)
                        .contextMenu { Button("Delete folder", role: .destructive) { if folderId == folder.id { folderId = nil }; library.deleteFolder(folder) } }
                        .accessibilityAction(named: "Delete folder") { if folderId == folder.id { folderId = nil }; library.deleteFolder(folder) }
                }
            }
        }
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
        Text("Nothing here yet. While reading, use the menu bookmark or a hadith note.")
            .font(.caption)
            .foregroundStyle(palette.textSecondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.vertical, 16)
            .accessibilityIdentifier("reader.savedShortcut.empty")
    }

    private var editButton: some View {
        HStack {
            Spacer()
            Button(action: onEdit) {
                Text("EDIT")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(palette.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Edit saved items in the Saved tab")
            .accessibilityIdentifier("reader.savedShortcut.edit")
        }
        .padding(.top, 4)
    }
}

// MARK: - Bookmark placement (R6 round 3)

/// Shared bookmark-placement rows (round 7): the legacy bottom sheet
/// (fixture) and the centered modal dialog (production) render the same
/// title, options, identifiers, and actions.
struct ReaderBookmarkPlacementOptions: View {
    let pageFirst: ReaderHadith?
    let positioned: ReaderHadith
    let palette: ReaderPalette
    let onChoose: (ReaderHadith) -> Void
    let onCancel: () -> Void

    var body: some View {
        // NOTE: the rows must live in an explicit VStack. Without one the
        // TupleView overlays title + rows and only the last row (Cancel)
        // is visible — the round-7 dialog shipped exactly that bug.
        VStack(alignment: .leading, spacing: 0) {
        Text("Add bookmark")
            .font(.headline)
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 12)
            .padding(.bottom, 4)
            .accessibilityIdentifier("reader.bookmarkPlacement.title")
        placementOption(
            title: "Start of page",
            identifier: "reader.bookmarkPlacement.pageStart"
        ) {
            if let target = ReaderBookmarkTarget.resolve(
                placement: .pageStart,
                pageFirst: pageFirst,
                positioned: positioned
            ) {
                onChoose(target)
            }
        }
        placementOption(
            title: "Current hadith \(positioned.referenceDisplay)",
            identifier: "reader.bookmarkPlacement.currentHadith"
        ) {
            if let target = ReaderBookmarkTarget.resolve(
                placement: .currentHadith,
                pageFirst: pageFirst,
                positioned: positioned
            ) {
                onChoose(target)
            }
        }
        placementOption(title: "Cancel", identifier: "reader.bookmarkPlacement.cancel", onCancel)
        }
    }

    private func placementOption(
        title: String,
        identifier: String,
        _ action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 0) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textSecondary.opacity(0.6))
                }
                .padding(.vertical, 13)
                Divider().overlay(palette.divider.opacity(0.6))
            }
            // No background fill on the plain row: the explicit content
            // shape keeps spacer gaps tappable (XCUITest taps row centers).
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}

/// Centered modal dialog for bookmark placement (round 7): the same
/// options as the legacy sheet, rendered as a floating card over a dimmed
/// backdrop instead of a bottom sheet. Reader palette throughout.
struct ReaderBookmarkPlacementDialog: View {
    let pageFirst: ReaderHadith?
    let positioned: ReaderHadith
    let onChoose: (ReaderHadith) -> Void
    let onCancel: () -> Void

    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme

    var body: some View {
        ReaderBookmarkPlacementOptions(
            pageFirst: pageFirst,
            positioned: positioned,
            palette: palette,
            onChoose: onChoose,
            onCancel: onCancel
        )
        .padding(20)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.3), radius: 24, y: 8)
        .frame(maxWidth: 340)
        .padding(.horizontal, 32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reader.bookmarkPlacement.dialog")
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }
}

/// Sajda `Add bookmark` style: stacked pill options for where the menu
/// bookmark lands — the start of the page or the current (positioned)
/// hadith — plus Cancel. Kept for the round-3 fixture; production renders
/// the centered ReaderBookmarkPlacementDialog instead.
struct ReaderBookmarkPlacementSheet: View {
    let pageFirst: ReaderHadith?
    let positioned: ReaderHadith
    let onChoose: (ReaderHadith) -> Void
    let onCancel: () -> Void

    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(palette.textSecondary.opacity(0.45))
                .frame(width: 40, height: 5)
                .padding(.top, 10)
                .accessibilityIdentifier("reader.bookmarkPlacement.grabber")
            ReaderBookmarkPlacementOptions(
                pageFirst: pageFirst,
                positioned: positioned,
                palette: palette,
                onChoose: onChoose,
                onCancel: onCancel
            )
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
        .background(palette.background)
        // The content fills all allocated vertical space so the short
        // option list sits in the full detent height with no dead blank
        // region below it.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }
}

struct ReaderStoredTranslationView: View {
    let text: String
    let translation: ReaderTranslation?
    let palette: ReaderPalette
    let onShowSources: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            if let translation, ["gemini_ai", "community"].contains(translation.source) {
                Button(action: onShowSources) {
                    HStack(spacing: 5) {
                        Image(systemName: translation.source == "community" ? "checkmark.shield" : "sparkles").font(.caption2)
                        Text(translation.source == "community" ? "Community" : "AI").font(.caption2.weight(.bold))
                        Text("· sources").font(.caption2).foregroundStyle(palette.textSecondary)
                    }
                    .foregroundStyle(palette.interactive)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(palette.interactiveSoft).clipShape(Capsule())
                    .frame(minHeight: 44)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier(translation.source == "community" ? "reader.communityBadge" : "reader.aiBadge")
            }
            Text(text)
                .font(.system(size: 16, weight: .regular)).lineSpacing(7)
                .multilineTextAlignment(.leading).foregroundStyle(palette.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true).frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityIdentifier(translation?.source == "gemini_ai" ? "reader.aiTranslation" : "reader.translation")
        }
    }
}
