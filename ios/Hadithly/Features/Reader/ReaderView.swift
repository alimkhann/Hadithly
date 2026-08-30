import ClerkKit
import SwiftUI

/// The reader: a quiet dark page. Chrome (top bar, floating pills) hides on
/// tap; swiping turns pages. No edge-swipe back — closing is an explicit
/// action that returns to the Library tab.
struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk

    let collectionSlug: String
    let collectionName: String
    var openVolumeId: String?
    var openHadithNumber: String?

    @State private var model: ReaderModel?
    @State private var showIndex = false
    @State private var showSettings = false
    @State private var lastTurn: PageTurn = .none
    @AppStorage("reader.arabicFontSize") private var arabicFontSize: Double = 26

    private enum PageTurn {
        case none
        case forward
        case back
    }

    var body: some View {
        Group {
            if let model {
                readerContent(model)
            } else {
                Theme.background.ignoresSafeArea()
            }
        }
        .background(Theme.background.ignoresSafeArea())
        .task {
            if model == nil {
                model = ReaderModel(
                    convex: environment.convex,
                    collectionSlug: collectionSlug,
                    collectionName: collectionName,
                    language: UserDefaults.standard.string(forKey: "user.preferredLanguage") ?? "en",
                    isSignedIn: { clerk.session != nil },
                    library: environment.library,
                    openVolumeId: openVolumeId,
                    openHadithNumber: openHadithNumber
                )
                model?.start()
            }
        }
        .onDisappear {
            model?.saveCurrentProgress()
            model?.stop()
        }
        .sheet(isPresented: $showIndex) {
            if let model {
                CollectionOutlineSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showSettings) {
            if let model {
                ReaderSettingsSheet(model: model, arabicFontSize: $arabicFontSize)
                    .presentationDetents([.medium])
            }
        }
    }

    @ViewBuilder
    private func readerContent(_ model: ReaderModel) -> some View {
        switch model.phase {
        case .loadingOutline:
            loadingView
        case .failed(let message):
            failureView(message)
        case .reading:
            readingView(model)
        }
    }

    private var loadingView: some View {
        VStack(spacing: 12) {
            ProgressView()
                .tint(Theme.textSecondary)
            Text("Opening \(collectionName)…")
                .font(.subheadline)
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reader.loading")
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(Theme.textSecondary)
            Text("Could not open this collection")
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readingView(_ model: ReaderModel) -> some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ReaderPageView(
                model: model,
                hadiths: model.currentPageHadiths,
                arabicFontSize: arabicFontSize
            )
            .id(model.pageIndex)
            .transition(pageTurnTransition)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.chromeVisible.toggle()
                }
            }

            if model.chromeVisible {
                chromeOverlay(model)
                    .transition(.opacity)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.92), value: model.pageIndex)
        .animation(.easeInOut(duration: 0.2), value: model.chromeVisible)
        .statusBarHidden(!model.chromeVisible)
        .overlay {
            WindowSwipeRecognizer(
                isEnabled: { !showIndex && !showSettings },
                onSwipe: { forward in turnPage(model, forward: forward) }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
    }

    private var pageTurnTransition: AnyTransition {
        switch lastTurn {
        case .forward:
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case .back:
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case .none:
            .opacity
        }
    }

    private func turnPage(_ model: ReaderModel, forward: Bool) {
        if forward {
            guard model.hasNextPage else { return }
            lastTurn = .forward
            model.pageIndex += 1
        } else {
            guard model.hasPreviousPage else { return }
            lastTurn = .back
            model.pageIndex -= 1
        }
    }

    private func chromeOverlay(_ model: ReaderModel) -> some View {
        VStack {
            ReaderTopBar(
                title: collectionName,
                subtitle: model.currentVolumeTitle,
                onClose: { dismiss() },
                onIndex: { showIndex = true },
                onSettings: { showSettings = true }
            )

            Spacer()

            ReaderBottomPills(model: model)
        }
        .transition(.opacity)
    }
}

// MARK: - Top bar

private struct ReaderTopBar: View {
    let title: String
    let subtitle: String?
    let onClose: () -> Void
    let onIndex: () -> Void
    let onSettings: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            chromeButton("chevron.down", label: "Close reader", action: onClose)
                .accessibilityIdentifier("reader.close")

            VStack(spacing: 1) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)

            chromeButton("list.bullet", label: "Contents", action: onIndex)
                .accessibilityIdentifier("reader.index")
            chromeButton("textformat.size", label: "Reader settings", action: onSettings)
                .accessibilityIdentifier("reader.settings")
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background(
            Theme.background
                .opacity(0.96)
                .ignoresSafeArea(edges: .top)
        )
    }

    private func chromeButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 38, height: 38)
                .background(Theme.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Bottom pills

private struct ReaderBottomPills: View {
    let model: ReaderModel

    var body: some View {
        HStack(spacing: 8) {
            if let volumeTitle = model.currentVolumeTitle {
                pill(volumeTitle)
                    .accessibilityIdentifier("reader.volumePill")
            }
            if let total = model.totalPages {
                pill("Page \(model.currentPageNumber) of \(total)")
                    .accessibilityIdentifier("reader.pagePill")
            } else {
                pill("Page \(model.currentPageNumber)")
            }
        }
        .padding(.bottom, 12)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.surface.opacity(0.96))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(Theme.surfaceElevated, lineWidth: 1))
    }
}

// MARK: - One reader page

struct ReaderPageView: View {
    let model: ReaderModel
    let hadiths: [ReaderHadith]
    let arabicFontSize: Double

    var body: some View {
        ScrollView {
            if hadiths.isEmpty {
                VStack {
                    ProgressView()
                        .tint(Theme.textSecondary)
                        .padding(.top, 120)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(spacing: 40) {
                    ForEach(hadiths) { hadith in
                        HadithBlock(
                            model: model,
                            hadith: hadith,
                            translationState: model.translations[hadith.internalId],
                            language: model.language,
                            arabicFontSize: arabicFontSize,
                            onRetry: { model.retryTranslation(for: hadith) }
                        )
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 20)
                .padding(.bottom, 80)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.chromeVisible.toggle()
            }
        }
        .accessibilityIdentifier("reader.page")
    }
}

// MARK: - One hadith

private struct HadithBlock: View {
    let model: ReaderModel
    let hadith: ReaderHadith
    let translationState: ReaderModel.TranslationState?
    let language: String
    let arabicFontSize: Double
    let onRetry: () -> Void

    @State private var citationsTranslation: ReaderTranslation?
    @State private var isEditingNote = false
    @State private var isSubmittingTranslation = false
    @State private var reportedTranslation: ReaderTranslation?

    var body: some View {
        VStack(spacing: 16) {
            hadithMedallion

            Text(hadith.arabicText)
                .font(Theme.arabic(arabicFontSize))
                .lineSpacing(arabicFontSize * 0.75)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("reader.arabic")

            if let narrator = hadith.narrator, !narrator.isEmpty {
                Text(narrator)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            translationSection

            contributionRow

            Text(hadith.referenceDisplay)
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)

            HadithActionRow(
                isBookmarked: model.isBookmarked(hadith),
                isFavorite: model.isFavorite(hadith),
                hasNote: model.noteContent(for: hadith) != nil,
                onBookmark: { model.toggleBookmark(hadith) },
                onFavorite: { model.toggleFavorite(hadith) },
                onNote: { isEditingNote = true }
            )
        }
        .padding(.vertical, 8)
        .sheet(item: $citationsTranslation) { translation in
            TranslationCitationsSheet(translation: translation)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $isEditingNote) {
            NoteEditorSheet(
                initialContent: model.noteContent(for: hadith),
                onSave: { content in
                    model.saveNote(hadith, content: content)
                    isEditingNote = false
                }
            )
            .presentationDetents([.medium])
        }
        .sheet(isPresented: $isSubmittingTranslation) {
            TranslationSubmissionSheet(
                model: model,
                hadith: hadith,
                existingTranslation: activeTranslation,
                initialContent: displayedTranslation ?? ""
            )
            .presentationDetents([.large])
        }
        .sheet(item: $reportedTranslation) { translation in
            TranslationReportSheet(
                model: model,
                translation: translation,
                referenceDisplay: hadith.referenceDisplay
            )
            .presentationDetents([.medium])
        }
    }

    private var hadithMedallion: some View {
        Text(hadith.providerHadithId)
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(Theme.accent)
            .frame(minWidth: 40, minHeight: 40)
            .background(Circle().fill(Theme.accentSoft))
            .overlay(Circle().strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
    }

    @ViewBuilder
    private var translationSection: some View {
        if language == "en" {
            if let english = hadith.englishText, !english.isEmpty {
                translationText(english)
            } else {
                Text("No English translation available yet.")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            aiTranslationSection
        }
    }

    @ViewBuilder
    private var aiTranslationSection: some View {
        switch translationState {
        case .none, .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .tint(Theme.textSecondary)
                Text("AI translation…")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(.vertical, 6)

        case .loaded(let translation):
            translationText(translation.translation, storedTranslation: translation)
            if !translation.glossaryNotes.isEmpty {
                glossaryNotes(translation.glossaryNotes)
            }

        case .failed(.requiresSignIn):
            quietNotice(
                icon: "person.crop.circle.badge.questionmark",
                text: "Sign in to get AI translations in your language.",
                actionTitle: "Sign in"
            )

        case .failed(.quotaExceeded):
            quietNotice(
                icon: "sparkles",
                text: "You've used your free AI translations for this month. Reading continues as usual.",
                actionTitle: nil
            )

        case .failed(.failed):
            Button(action: onRetry) {
                Text("AI translation unavailable · retry")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }
            .buttonStyle(.plain)
        }
    }

    private func translationText(
        _ text: String,
        storedTranslation: ReaderTranslation? = nil
    ) -> some View {
        VStack(spacing: 10) {
            if let storedTranslation, storedTranslation.source == "gemini_ai" {
                aiBadge
            } else if storedTranslation?.source == "community" {
                communityBadge
            }
            Text(text)
                .font(.system(size: 16, weight: .regular))
                .lineSpacing(7)
                .multilineTextAlignment(.leading)
                .foregroundStyle(Theme.textPrimary.opacity(0.92))
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier(
                    storedTranslation?.source == "gemini_ai"
                        ? "reader.aiTranslation"
                        : "reader.translation"
                )
        }
    }

    private var aiBadge: some View {
        Button {
            if case .loaded(let translation) = translationState {
                citationsTranslation = translation
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.caption2)
                Text("AI")
                    .font(.caption2.weight(.bold))
                Text("· sources")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Theme.accentSoft)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("AI translation, view cited sources")
        .accessibilityIdentifier("reader.aiBadge")
    }

    private var communityBadge: some View {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.shield")
                .font(.caption2)
            Text("Community")
                .font(.caption2.weight(.bold))
            Text("· admin approved")
                .font(.caption2)
                .foregroundStyle(Theme.textSecondary)
        }
        .foregroundStyle(Theme.accent)
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(Theme.accentSoft)
        .clipShape(Capsule())
        .accessibilityIdentifier("reader.communityBadge")
    }

    private func glossaryNotes(_ notes: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(notes, id: \.self) { note in
                Text("· \(note)")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quietNotice(icon: String, text: String, actionTitle: String?) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.textSecondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            if actionTitle != nil {
                Text("Sign-in lives on the Settings tab.")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary.opacity(0.7))
            }
        }
        .padding(.vertical, 8)
    }

    private var activeTranslation: ReaderTranslation? {
        guard case .loaded(let translation) = translationState else { return nil }
        return translation
    }

    private var displayedTranslation: String? {
        if language == "en" {
            return hadith.englishText
        }
        return activeTranslation?.translation
    }

    private var contributionRow: some View {
        HStack(spacing: 18) {
            Button {
                isSubmittingTranslation = true
            } label: {
                Label("Suggest translation", systemImage: "text.bubble")
            }
            .accessibilityIdentifier("reader.suggestTranslation")

            if let activeTranslation {
                Button {
                    reportedTranslation = activeTranslation
                } label: {
                    Label("Report", systemImage: "flag")
                }
                .accessibilityIdentifier("reader.reportTranslation")
            }
        }
        .font(.caption)
        .foregroundStyle(Theme.textSecondary.opacity(0.8))
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Per-hadith actions

/// The quiet action row under each hadith: bookmark (amber), favorite (pink),
/// and a note. Nothing else on the page uses color.
struct HadithActionRow: View {
    let isBookmarked: Bool
    let isFavorite: Bool
    let hasNote: Bool
    let onBookmark: () -> Void
    let onFavorite: () -> Void
    let onNote: () -> Void

    var body: some View {
        HStack(spacing: 26) {
            actionButton(
                "bookmark",
                filled: isBookmarked,
                tint: Theme.bookmark,
                label: isBookmarked ? "Remove bookmark" : "Bookmark",
                action: onBookmark
            )
            .accessibilityIdentifier("reader.bookmark")

            actionButton(
                "heart",
                filled: isFavorite,
                tint: Theme.favorite,
                label: isFavorite ? "Remove favorite" : "Favorite",
                action: onFavorite
            )
            .accessibilityIdentifier("reader.favorite")

            actionButton(
                "square.and.pencil",
                filled: hasNote,
                tint: Theme.textSecondary,
                label: hasNote ? "Edit note" : "Add note",
                action: onNote
            )
            .accessibilityIdentifier("reader.note")
        }
    }

    private func actionButton(
        _ systemImage: String,
        filled: Bool,
        tint: Color,
        label: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: filled ? "\(systemImage).fill" : systemImage)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(filled ? tint : Theme.textSecondary.opacity(0.75))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Note editor

private struct NoteEditorSheet: View {
    let initialContent: String?
    let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $content)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(Theme.textPrimary)
                    .scrollContentBackground(.hidden)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 160)
                    .padding(1)
                    .background(Theme.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
            .background(Theme.background)
            .navigationTitle("Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(Theme.textSecondary)
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let trimmed = content.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmed.isEmpty else { return }
                        onSave(trimmed)
                        dismiss()
                    }
                    .foregroundStyle(Theme.accent)
                    .accessibilityIdentifier("note.save")
                }
            }
            .onAppear {
                content = initialContent ?? ""
                isFocused = true
            }
        }
        .preferredColorScheme(.dark)
    }
}

extension ReaderTranslation: Identifiable {
    var id: String { translationId }
}

/// A window-level pan recognizer that turns reader pages. SwiftUI gesture
/// arbitration between a vertical ScrollView and horizontal swipe never
/// resolves reliably, so the recognizer observes all touches simultaneously
/// (never canceling them) and only reacts to horizontal-dominant drags.
/// Vertical scrolling inside a page is untouched.
private struct WindowSwipeRecognizer: UIViewRepresentable {
    var isEnabled: () -> Bool
    var onSwipe: (Bool) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(isEnabled: isEnabled, onSwipe: onSwipe)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        context.coordinator.hostView = view
        DispatchQueue.main.async {
            if let window = view.window {
                context.coordinator.installIfNeeded(on: window)
            }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.onSwipe = onSwipe
        context.coordinator.hostView = uiView
        if let window = uiView.window {
            context.coordinator.installIfNeeded(on: window)
        }
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        var isEnabled: () -> Bool
        var onSwipe: (Bool) -> Void
        weak var hostView: UIView?
        private var pan: UIPanGestureRecognizer?

        init(isEnabled: @escaping () -> Bool, onSwipe: @escaping (Bool) -> Void) {
            self.isEnabled = isEnabled
            self.onSwipe = onSwipe
        }

        func installIfNeeded(on window: UIView) {
            guard pan == nil else { return }
            let recognizer = UIPanGestureRecognizer(
                target: self,
                action: #selector(handlePan(_:))
            )
            recognizer.delegate = self
            recognizer.cancelsTouchesInView = false
            window.addGestureRecognizer(recognizer)
            pan = recognizer
        }

        @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
            guard recognizer.state == .ended, isEnabled() else { return }
            let translation = recognizer.translation(in: recognizer.view)
            guard abs(translation.x) > abs(translation.y) * 1.4,
                  abs(translation.x) > 55 else { return }
            onSwipe(translation.x < 0)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
