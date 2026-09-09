import SwiftUI

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
    @Environment(\.dismiss) private var dismiss
    @State private var expandedVolumes: Set<String> = []
    @State private var jumpText = ""
    @State private var jumpError: String?

    var body: some View {
        NavigationStack {
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
                        VStack(spacing: 8) {
                            jumpField
                            ForEach(model.volumes) { volume in
                                if let chapters = volume.chapters, !chapters.isEmpty {
                                    volumeDisclosure(volume, chapters: chapters)
                                } else {
                                    volumeRow(volume)
                                }
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 12)
                    }
                }
            }
            .background(palette.background)
            .navigationTitle(model.collectionName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
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
    /// inline error and keeps the sheet open.
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
                    .foregroundStyle(Theme.accent)
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
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
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

    /// A volume with source-provided chapters: the header carries the same
    /// volume info as before, and each chapter row jumps straight to its
    /// first hadith. Chapters render only when the source provided them —
    /// Hadithly never synthesizes one.
    private func volumeDisclosure(_ volume: OutlineVolume, chapters: [OutlineChapter]) -> some View {
        let isSelected = volume.volumeId == model.selectedVolumeId
        return DisclosureGroup(isExpanded: expansionBinding(for: volume.volumeId)) {
            VStack(spacing: 4) {
                Button {
                    model.selectVolume(volume.volumeId)
                    dismiss()
                } label: {
                    HStack {
                        Text("Open \(volume.title) from the start")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reader.volume.\(volume.volumeId)")
                ForEach(chapters) { chapter in
                    chapterRow(volume: volume, chapter: chapter)
                }
            }
            .padding(.top, 4)
        } label: {
            // The identifier sits on the label subtree only: an identifier
            // on the DisclosureGroup itself propagates into the expanded
            // content and stomps the chapter rows' own identifiers.
            volumeLabel(volume, isSelected: isSelected)
                .accessibilityIdentifier("reader.contents.volume.\(volume.volumeId)")
        }
        .tint(palette.textSecondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(isSelected ? Theme.accentSoft : palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func chapterRow(volume: OutlineVolume, chapter: OutlineChapter) -> some View {
        Button {
            model.selectChapter(volumeId: volume.volumeId, chapter: chapter)
            dismiss()
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(chapter.title)
                        .font(.subheadline)
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                    if arabicVisible,
                       let arabic = chapter.arabicTitle,
                       !arabic.isEmpty,
                       arabic != chapter.title {
                        Text(arabic)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(chapter.title), \(chapter.hadithCount) hadiths")
        .accessibilityIdentifier("reader.contents.chapter.\(volume.volumeId).\(chapter.firstProviderHadithId)")
    }

    private func volumeRow(_ volume: OutlineVolume) -> some View {
        let isSelected = volume.volumeId == model.selectedVolumeId
        return Button {
            model.selectVolume(volume.volumeId)
            dismiss()
        } label: {
            volumeLabel(volume, isSelected: isSelected)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(isSelected ? Theme.accentSoft : palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("reader.volume.\(volume.volumeId)")
    }

    private func volumeLabel(_ volume: OutlineVolume, isSelected: Bool) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(volume.title)
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
                    .foregroundStyle(Theme.accent)
            }
        }
    }
}

/// Reader settings (R4): visibility, theme, Arabic face and size with a live
/// preview, and the translation language. Direct controls, close to the text;
/// account and global settings stay in the Settings tab.
struct ReaderSettingsSheet: View {
    let model: ReaderModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(AppEnvironment.self) private var environment

    private var preferences: ReaderPreferences { environment.preferences.preferences }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    visibilityCard
                    themeCard
                    typeCard
                    languageCard
                }
                .padding(16)
            }
            .background(palette.background)
            .navigationTitle("Reader settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }

    // MARK: Visibility

    private var visibilityCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Show on page", systemImage: "eye")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: 10) {
                visibilityPill(
                    title: "Arabic",
                    isOn: preferences.arabicVisible,
                    identifier: "reader.visibility.arabic"
                ) {
                    _ = environment.preferences.setVisibility(
                        arabic: !preferences.arabicVisible,
                        translation: nil
                    )
                }
                visibilityPill(
                    title: "Translation",
                    isOn: preferences.translationVisible,
                    identifier: "reader.visibility.translation"
                ) {
                    _ = environment.preferences.setVisibility(
                        arabic: nil,
                        translation: !preferences.translationVisible
                    )
                }
            }

            Text("At least one text layer stays visible.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func visibilityPill(
        title: String,
        isOn: Bool,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            action()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
                Text(title)
            }
            .font(.subheadline.weight(.medium))
            .foregroundStyle(isOn ? Theme.accent : palette.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(isOn ? Theme.accentSoft : palette.surfaceElevated)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title) visibility, \(isOn ? "on" : "off")")
        .accessibilityHint(isOn ? "Turns off unless it is the last visible layer" : "Shows this layer")
        .accessibilityIdentifier(identifier)
    }

    // MARK: Theme

    private var themeCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Color theme", systemImage: "circle.lefthalf.filled")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            HStack(spacing: 8) {
                ForEach(ReaderTheme.allCases, id: \.self) { theme in
                    themeButton(theme)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func themeButton(_ theme: ReaderTheme) -> some View {
        let isSelected = preferences.theme == theme
        let swatch = ReaderPalette.resolved(theme, systemDark: true)
        return Button {
            environment.preferences.setTheme(theme)
        } label: {
            VStack(spacing: 6) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(swatch.background)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(
                                isSelected ? Theme.accent : palette.divider,
                                lineWidth: isSelected ? 2 : 1
                            )
                    )
                    .frame(height: 34)
                Text(theme == .system ? "System" : theme == .light ? "Light" : theme == .paper ? "Paper" : "Dark")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(isSelected ? Theme.accent : palette.textSecondary)
            }
            .frame(maxWidth: .infinity)
            .padding(6)
            .background(isSelected ? Theme.accentSoft : Color.clear)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Color theme \(theme == .system ? "System" : theme == .light ? "Light" : theme == .paper ? "Paper" : "Dark")")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("reader.theme.\(theme.rawValue)")
    }

    // MARK: Arabic type

    private var typeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Arabic type", systemImage: "textformat.size")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)

            Text("بِسْمِ اللَّهِ الرَّحْمَٰنِ الرَّحِيمِ")
                .font(Theme.arabic(preferences.arabicFontSize, preferences.arabicFont))
                .lineSpacing(preferences.arabicFontSize * 0.75)
                .multilineTextAlignment(.center)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(palette.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .accessibilityLabel("Arabic type preview")
                .accessibilityIdentifier("reader.typePreview")

            sizeStepper

            ForEach(ArabicFont.allCases, id: \.rawValue) { font in
                fontRow(font)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private var sizeStepper: some View {
        HStack(spacing: 12) {
            Button {
                environment.preferences.setArabicFontSize(
                    ArabicTypeSize.stepDown(from: preferences.arabicFontSize)
                )
            } label: {
                Text("A")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(palette.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(preferences.arabicFontSize <= ReaderPreferences.minArabicFontSize)
            .accessibilityLabel("Smaller Arabic type")
            .accessibilityIdentifier("reader.sizeSmaller")

            Text("\(Int(preferences.arabicFontSize)) pt")
                .font(.caption.monospacedDigit())
                .foregroundStyle(palette.textSecondary)

            Button {
                environment.preferences.setArabicFontSize(
                    ArabicTypeSize.stepUp(from: preferences.arabicFontSize)
                )
            } label: {
                Text("A")
                    .font(.title3.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(palette.surfaceElevated)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(preferences.arabicFontSize >= ReaderPreferences.maxArabicFontSize)
            .accessibilityLabel("Larger Arabic type")
            .accessibilityIdentifier("reader.sizeLarger")
        }
    }

    private func fontRow(_ font: ArabicFont) -> some View {
        let isSelected = preferences.arabicFont == font
        return Button {
            environment.preferences.setArabicFont(font)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("بِسْمِ اللَّهِ")
                        .font(Theme.arabic(20, font))
                        .foregroundStyle(palette.textPrimary)
                    Text(font.displayName)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                }
                Spacer()
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(isSelected ? Theme.accentSoft : palette.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Arabic font \(font.displayName)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityIdentifier("reader.font.\(font.rawValue)")
    }

    // MARK: Language

    private var languageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Translation language", systemImage: "globe")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            Text("AI translations are labeled and grounded in cited sources.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)

            ForEach(SupportedLanguages.all) { language in
                Button {
                    environment.preferences.setTranslationLocale(language.code)
                    model.setLanguage(language.code)
                } label: {
                    HStack {
                        Text(language.name)
                            .font(.subheadline)
                            .foregroundStyle(palette.textPrimary)
                        Spacer()
                        if model.language == language.code {
                            Image(systemName: "checkmark")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 11)
                    .background(model.language == language.code ? Theme.accentSoft : palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("reader.language.\(language.code)")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}

/// Citations behind an AI translation. Every AI translation is labeled and
/// grounded; this sheet shows where its claims come from.
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
                            .foregroundStyle(Theme.accent)
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

                    Text("This translation was generated by AI (\(translation.aiModel ?? "model unavailable")). It is not an authoritative rendering; verify important meanings against a qualified source.")
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
                        .padding(.top, 4)
                }
                .padding(20)
            }
            .background(palette.background)
            .navigationTitle("AI sources")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
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
                            .foregroundStyle(Theme.accent)
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

/// Contextual contribution flow for the hadith currently on screen. The
/// proposal is reviewed by AI first and is never published without an admin.
struct TranslationSubmissionSheet: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    let model: ReaderModel
    let hadith: ReaderHadith
    let existingTranslation: ReaderTranslation?

    @Environment(\.dismiss) private var dismiss
    @State private var content: String
    @State private var result: TranslationSubmissionResult?
    @State private var isSubmitting = false
    @State private var errorMessage: String?
    @FocusState private var isFocused: Bool

    init(
        model: ReaderModel,
        hadith: ReaderHadith,
        existingTranslation: ReaderTranslation?,
        initialContent: String
    ) {
        self.model = model
        self.hadith = hadith
        self.existingTranslation = existingTranslation
        _content = State(initialValue: initialContent)
    }

    var body: some View {
        NavigationStack {
            Group {
                if let result {
                    verdict(result)
                } else if model.canContribute {
                    submissionForm
                } else {
                    signInNotice
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(palette.background)
            .navigationTitle(result == nil ? "Suggest a translation" : "AI review")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(result == nil ? "Cancel" : "Done") { dismiss() }
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }

    private var submissionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(hadith.referenceDisplay)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                    Text(languageName)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                }

                Text("Write the clearest faithful rendering you can. AI checks meaning and terminology; an admin decides whether it is published.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)

                TextEditor(text: $content)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(minHeight: 230)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityIdentifier("submission.editor")

                if let errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("submission.error")
                }

                Button {
                    Task { await submit() }
                } label: {
                    HStack(spacing: 8) {
                        if isSubmitting { ProgressView().tint(.black) }
                        Text(isSubmitting ? "Reviewing…" : "Submit for AI review")
                            .font(.subheadline.weight(.semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(canSubmit ? Theme.accent : palette.surfaceElevated)
                    .foregroundStyle(canSubmit ? .black : palette.textSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }
                .buttonStyle(.plain)
                .disabled(!canSubmit)
                .accessibilityIdentifier("submission.submit")
            }
            .padding(20)
        }
        .scrollDismissesKeyboard(.interactively)
        .onAppear { isFocused = content.isEmpty }
    }

    private var signInNotice: some View {
        VStack(spacing: 12) {
            Image(systemName: "person.crop.circle.badge.questionmark")
                .font(.title2)
                .foregroundStyle(palette.textSecondary)
            Text("Sign in to contribute a translation.")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            Text("You can sign in from Settings, then return to this hadith.")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
        .accessibilityIdentifier("submission.signInRequired")
    }

    private func verdict(_ submission: TranslationSubmissionResult) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: verdictIcon(for: submission))
                        .font(.title2)
                        .foregroundStyle(Theme.accent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(verdictTitle(for: submission))
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                        Text(verdictMessage(for: submission))
                            .font(.subheadline)
                            .foregroundStyle(palette.textSecondary)
                    }
                }

                if submission.aiReview.reviewNotes.isEmpty {
                    Text("The review found no specific meaning or terminology issues.")
                        .font(.caption)
                        .foregroundStyle(palette.textSecondary)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Review notes")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(palette.textPrimary)
                        ForEach(Array(submission.aiReview.reviewNotes.enumerated()), id: \.offset) { _, note in
                            Text("• \(note)")
                                .font(.caption)
                                .foregroundStyle(palette.textSecondary)
                        }
                    }
                }

                Text("Reviewed by \(submission.aiReview.model). AI review is advisory; only an admin can publish a contribution.")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary.opacity(0.8))

                if submission.status == "rejected" {
                    Button("Revise proposal") {
                        result = nil
                        errorMessage = nil
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("submission.revise")
                }
            }
            .padding(24)
        }
        .accessibilityIdentifier("submission.verdict")
    }

    private var canSubmit: Bool {
        !isSubmitting && !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var languageName: String {
        SupportedLanguages.all.first { $0.code == model.language }?.name ?? model.language
    }

    private func submit() async {
        let proposal = content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !proposal.isEmpty else { return }
        isSubmitting = true
        errorMessage = nil
        defer { isSubmitting = false }
        do {
            result = try await model.submitTranslation(
                for: hadith,
                proposedContent: proposal,
                replacing: existingTranslation
            )
            isFocused = false
        } catch {
            errorMessage = ReaderModels.errorMessage(of: error)
        }
    }

    private func verdictIcon(for submission: TranslationSubmissionResult) -> String {
        switch submission.status {
        case "rejected": "exclamationmark.triangle"
        case "needs_admin": "person.crop.circle.badge.exclamationmark"
        default: "checkmark.circle"
        }
    }

    private func verdictTitle(for submission: TranslationSubmissionResult) -> String {
        switch submission.status {
        case "rejected": "Please revise this translation"
        case "needs_admin": "Sent for careful admin review"
        default: "AI review passed"
        }
    }

    private func verdictMessage(for submission: TranslationSubmissionResult) -> String {
        switch submission.status {
        case "rejected":
            "The AI review found meaning or terminology concerns, so this version will not be published."
        case "needs_admin":
            "The AI found uncertainty that needs a human decision. Your proposal is waiting for an admin."
        default:
            "Your proposal is waiting for admin approval. It is not public yet."
        }
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
                            .foregroundStyle(Theme.accent)
                        Text("Report sent privately")
                            .font(.headline)
                            .foregroundStyle(palette.textPrimary)
                        Text("An admin can review the translation and your note.")
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
                                .background(canSubmit ? Theme.accent : palette.surfaceElevated)
                                .foregroundStyle(canSubmit ? .black : palette.textSecondary)
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
                        .foregroundStyle(Theme.accent)
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
