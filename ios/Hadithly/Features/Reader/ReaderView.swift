import ClerkKit
import SwiftUI

/// The reader: a quiet dark page. Chrome (top bar, floating pills) hides on
/// tap; swiping turns pages. No edge-swipe back — closing is an explicit
/// action that returns to the Library tab.
struct ReaderView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppEnvironment.self) private var environment
    @Environment(Clerk.self) private var clerk
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.colorScheme) private var systemColorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let collectionSlug: String
    let collectionName: String
    var openVolumeId: String?
    var openHadithNumber: String?
    var openPosition: ReadingPosition?
    var targetSource: ReaderTargetSource = .collection

    @State private var model: ReaderModel?
    @State private var showIndex = false
    @State private var showSettings = false
    @State private var showQuotaPaywall = false
    @State private var hasAutoPresentedQuotaPaywall = false
    @State private var lastTurn: ReaderPageTurn?

    private var pagingPolicy: ReaderPagingPolicy {
        ReaderPagingPolicy(preferences: environment.preferences.preferences)
    }

    private var readerTheme: ReaderTheme {
        environment.preferences.preferences.theme
    }

    private var palette: ReaderPalette {
        ReaderPalette.resolved(readerTheme, systemDark: systemColorScheme == .dark)
    }

    private var arabicFontSizeBinding: Binding<Double> {
        Binding(
            get: { environment.preferences.preferences.arabicFontSize },
            set: { environment.preferences.setArabicFontSize($0) }
        )
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
        .environment(\.readerTheme, readerTheme)
        .environment(\.readerPalette, palette)
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
        .task {
            if model == nil {
                model = ReaderModel(
                    convex: environment.convex,
                    collectionSlug: collectionSlug,
                    collectionName: collectionName,
                    language: environment.preferences.preferences.translationLocale,
                    isSignedIn: { clerk.session != nil },
                    library: environment.library,
                    openVolumeId: openVolumeId,
                    openHadithNumber: openHadithNumber,
                    openPosition: openPosition,
                    targetSource: targetSource,
                    currentPreferences: { environment.preferences.preferences },
                    widthClass: horizontalSizeClass == .regular ? .regular : .compact
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
                ReaderSettingsSheet(model: model)
                    .presentationDetents([.medium, .large])
            }
        }
        .sheet(isPresented: $showQuotaPaywall) {
            QuotaPaywallView {
                Task {
                    try? await Task.sleep(for: .seconds(1))
                    model?.retryTranslationsAfterPurchase()
                }
            }
            .presentationDetents([.large])
        }
        .onChange(of: model?.hasQuotaFailure ?? false, initial: true) { _, exceeded in
            guard exceeded, !hasAutoPresentedQuotaPaywall else { return }
            hasAutoPresentedQuotaPaywall = true
            showQuotaPaywall = true
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
                .tint(palette.textSecondary)
            Text("Opening \(collectionName)…")
                .font(.subheadline)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityIdentifier("reader.loading")
    }

    private func failureView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .font(.title)
                .foregroundStyle(palette.textSecondary)
            Text("Could not open this collection")
                .font(.headline)
                .foregroundStyle(palette.textPrimary)
            Text(message)
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
                .lineLimit(3)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func readingView(_ model: ReaderModel) -> some View {
        ZStack {
            palette.background.ignoresSafeArea()

            ReaderPageView(
                model: model,
                hadiths: model.currentPageHadiths,
                arabicFontSize: arabicFontSizeBinding.wrappedValue,
                preferences: environment.preferences.preferences,
                restoration: model.restoredPosition,
                restorationGeneration: model.restorationGeneration,
                landingHadithNumber: model.landingHadithNumber,
                currentPageIndex: model.pageIndex,
                pageCount: model.pages.count + (model.hasNextPage && model.pageIndex == model.pages.count - 1 ? 1 : 0),
                palette: palette,
                onTurn: { turnPage(model, turn: $0) },
                onShowPaywall: { showQuotaPaywall = true }
            )
            .id(model.pageIndex)
            .transition(pageTurnTransition)
            .onTapGesture {
                withAnimation(.easeInOut(duration: 0.2)) {
                    model.chromeVisible.toggle()
                }
            }

            // Compact progress (R4): a thin bar at the top stays visible
            // while the chrome is hidden, matching the quiet reading state.
            if !model.chromeVisible, let fraction = model.compactProgressFraction {
                ReaderCompactProgressBar(fraction: fraction, palette: palette)
                    .transition(.opacity)
            }

            if model.chromeVisible {
                chromeOverlay(model)
                    .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : .spring(response: 0.38, dampingFraction: 0.92), value: model.pageIndex)
        .animation(.easeInOut(duration: 0.2), value: model.chromeVisible)
        .statusBarHidden(!model.chromeVisible)
        .overlay {
            WindowSwipeRecognizer(
                pageDirection: pagingPolicy.pageDirection,
                isEnabled: { !showIndex && !showSettings },
                onTurn: { turnPage(model, turn: $0) }
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .accessibilityAction(named: "Previous page") {
            turnPage(model, turn: .previous)
        }
        .accessibilityAction(named: "Next page") {
            turnPage(model, turn: .next)
        }
        // The visual reader has no permanent controls, so VoiceOver needs an
        // equally direct way to reveal close, contents, and type controls.
        .accessibilityAction(
            named: model.chromeVisible ? "Hide reader controls" : "Show reader controls"
        ) {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.chromeVisible.toggle()
            }
        }
        // A layout-affecting preference change (font, size, visibility,
        // translation locale) invalidates the raw offset; the semantic
        // anchor restores the exact position against the new signature.
        .onChange(of: environment.preferences.preferences.layoutProjection) { _, _ in
            model.reanchorAfterLayoutChange()
        }
    }

    private var pageTurnTransition: AnyTransition {
        if reduceMotion {
            return .opacity
        }
        return switch (lastTurn, pagingPolicy.pageDirection) {
        case (.next, .ltr), (.previous, .rtl):
            .asymmetric(
                insertion: .move(edge: .trailing).combined(with: .opacity),
                removal: .move(edge: .leading).combined(with: .opacity)
            )
        case (.previous, .ltr), (.next, .rtl):
            .asymmetric(
                insertion: .move(edge: .leading).combined(with: .opacity),
                removal: .move(edge: .trailing).combined(with: .opacity)
            )
        case (.none, _):
            .opacity
        }
    }

    private func turnPage(_ model: ReaderModel, turn: ReaderPageTurn) {
        if turn == .next {
            guard model.hasNextPage else { return }
            lastTurn = .next
            model.pageIndex += 1
        } else {
            guard model.hasPreviousPage else { return }
            lastTurn = .previous
            model.pageIndex -= 1
        }
    }

    private func chromeOverlay(_ model: ReaderModel) -> some View {
        VStack {
            ReaderTopBar(
                title: collectionName,
                subtitle: model.currentVolumeTitle,
                palette: palette,
                onClose: { dismiss() },
                onIndex: { showIndex = true },
                onSettings: { showSettings = true }
            )

            Spacer()

            ReaderBottomPills(model: model, palette: palette)
        }
        .transition(.opacity)
    }
}

// MARK: - Compact progress

/// The thin top progress indicator shown while the reader chrome is hidden.
/// Non-interactive and skipped by assistive tech; the expanded pill carries
/// the accessible reading-position description.
private struct ReaderCompactProgressBar: View {
    let fraction: Double
    let palette: ReaderPalette

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.divider.opacity(0.6))
                Capsule()
                    .fill(Theme.accent.opacity(0.8))
                    .frame(width: max(8, proxy.size.width * fraction))
            }
            .frame(height: 3)
        }
        .frame(height: 3)
        .padding(.horizontal, 24)
        .padding(.top, 6)
        .accessibilityHidden(true)
    }
}

// MARK: - Top bar

private struct ReaderTopBar: View {
    let title: String
    let subtitle: String?
    let palette: ReaderPalette
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
                    .foregroundStyle(palette.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(palette.textSecondary)
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
            palette.background
                .opacity(0.96)
                .ignoresSafeArea(edges: .top)
        )
    }

    private func chromeButton(_ systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.body)
                .foregroundStyle(palette.textSecondary)
                .frame(width: 44, height: 44)
                .background(palette.surface)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

// MARK: - Bottom pills

/// Expanded progress (R4): shown with the revealed chrome; the compact thin
/// bar replaces it while reading quietly.
private struct ReaderBottomPills: View {
    let model: ReaderModel
    let palette: ReaderPalette

    var body: some View {
        HStack(spacing: 8) {
            if let volumeTitle = model.currentVolumeTitle {
                pill(volumeTitle)
                    .accessibilityIdentifier("reader.volumePill")
            }
            if let total = model.totalPages {
                pill("Page \(model.currentPageNumber) of \(total)")
                    .accessibilityIdentifier("reader.pagePill")
                    .accessibilityLabel("Page \(model.currentPageNumber) of \(total)")
            } else {
                pill("Page \(model.currentPageNumber)")
            }
        }
        .padding(.bottom, 12)
    }

    private func pill(_ text: String) -> some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(palette.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(palette.surface.opacity(0.96))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(palette.divider, lineWidth: 1))
    }
}

// MARK: - One reader page

private struct ReaderAnchorFrame: Equatable {
    let minY: CGFloat
    let height: CGFloat
}

private struct ReaderAnchorFramesKey: PreferenceKey {
    static var defaultValue: [String: ReaderAnchorFrame] = [:]

    static func reduce(value: inout [String: ReaderAnchorFrame], nextValue: () -> [String: ReaderAnchorFrame]) {
        value.merge(nextValue(), uniquingKeysWith: { _, next in next })
    }
}

struct ReaderPageView: View {
    let model: ReaderModel
    let hadiths: [ReaderHadith]
    let arabicFontSize: Double
    let preferences: ReaderPreferences
    let restoration: ReadingPosition?
    let restorationGeneration: Int
    let landingHadithNumber: String?
    let currentPageIndex: Int
    let pageCount: Int
    let palette: ReaderPalette
    let onTurn: (ReaderPageTurn) -> Void
    let onShowPaywall: () -> Void

    @State private var appliedRestorationKey: String?
    @State private var chapterOpenings: Set<Int> = []

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    if hadiths.isEmpty {
                        VStack {
                            ProgressView()
                                .tint(palette.textSecondary)
                                .padding(.top, 120)
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(hadiths.enumerated()), id: \.element.internalId) { index, hadith in
                                if index > 0 {
                                    ReaderHadithDivider(palette: palette)
                                }
                                if chapterOpenings.contains(index) {
                                    ReaderChapterHeader(
                                        title: hadith.chapterName ?? "",
                                        palette: palette
                                    )
                                }
                                HadithBlock(
                                    model: model,
                                    hadith: hadith,
                                    translationState: model.translations[hadith.internalId],
                                    language: model.language,
                                    arabicFontSize: arabicFontSize,
                                    preferences: preferences,
                                    palette: palette,
                                    onRetry: { model.retryTranslation(for: hadith) },
                                    onShowPaywall: onShowPaywall
                                )
                                .id(hadith.internalId)
                                .background(GeometryReader { geometry in
                                    let frame = geometry.frame(in: .named("reader.page"))
                                    Color.clear.preference(
                                        key: ReaderAnchorFramesKey.self,
                                        value: [
                                            hadith.internalId: ReaderAnchorFrame(
                                                minY: frame.minY,
                                                height: frame.height
                                            ),
                                        ]
                                    )
                                })
                            }

                            ReaderEndNavigation(
                                policy: ReaderPagingPolicy(preferences: preferences),
                                currentPageIndex: currentPageIndex,
                                pageCount: pageCount,
                                palette: palette,
                                onTurn: onTurn
                            )
                            .padding(.top, 40)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 80)
                    }
                }
                .coordinateSpace(name: "reader.page")
                .onPreferenceChange(ReaderAnchorFramesKey.self) { frames in
                    let targetId = restoration?.anchor.providerHadithId ?? landingHadithNumber
                    if let targetId,
                       let target = hadiths.first(where: { $0.providerHadithId == targetId }),
                       let frame = frames[target.internalId] {
                        let key = "\(restorationGeneration):\(target.internalId):\(restoration?.normalizedOffset ?? 0):\(viewport.size.height)"
                        if appliedRestorationKey != key {
                            appliedRestorationKey = key
                            let anchorY = ReaderScrollRestoration.anchorY(
                                normalizedOffset: restoration?.normalizedOffset ?? 0,
                                itemHeight: frame.height,
                                viewportHeight: viewport.size.height
                            )
                            proxy.scrollTo(target.internalId, anchor: UnitPoint(x: 0.5, y: anchorY))
                            return
                        }
                    }

                    let indexed = hadiths.enumerated().compactMap { index, hadith in
                        frames[hadith.internalId].map { (index, $0) }
                    }
                    guard let leading = indexed.last(where: { $0.1.minY <= 0 }) ?? indexed.first else { return }
                    model.captureStableScroll(
                        hadiths: hadiths,
                        leadingIndex: leading.0,
                        rawPageOffset: max(0, -leading.1.minY),
                        normalizedOffset: max(0, -leading.1.minY) / max(1, leading.1.height)
                    )
                }
            }
        }
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.2)) {
                model.chromeVisible.toggle()
            }
        }
        .onAppear { chapterOpenings = ReaderChapterBoundaries.openingIndices(in: hadiths) }
        .onChange(of: hadiths) { _, updated in
            chapterOpenings = ReaderChapterBoundaries.openingIndices(in: updated)
        }
        .accessibilityIdentifier("reader.page")
    }
}

/// A restrained hairline between hadiths (R4): no cards, no ornament.
private struct ReaderHadithDivider: View {
    let palette: ReaderPalette

    var body: some View {
        Rectangle()
            .fill(palette.divider)
            .frame(height: 0.5)
            .padding(.vertical, 20)
            .accessibilityHidden(true)
    }
}

/// The strong, source-provided chapter opening (R4). Never invented: rendered
/// only when the provider data carries a chapter name.
private struct ReaderChapterHeader: View {
    let title: String
    let palette: ReaderPalette

    var body: some View {
        VStack(spacing: 10) {
            Rectangle()
                .fill(palette.divider)
                .frame(height: 0.5)
            VStack(spacing: 4) {
                Text("Chapter")
                    .font(.caption2)
                    .textCase(.uppercase)
                    .foregroundStyle(palette.textSecondary)
                Text(title)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(palette.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Chapter \(title)")
        .accessibilityIdentifier("reader.chapterHeader")
    }
}

private struct ReaderEndNavigation: View {
    let policy: ReaderPagingPolicy
    let currentPageIndex: Int
    let pageCount: Int
    let palette: ReaderPalette
    let onTurn: (ReaderPageTurn) -> Void

    var body: some View {
        HStack(spacing: 12) {
            ForEach(policy.endControlOrder, id: \.self) { turn in
                if let destination = policy.destination(
                    from: currentPageIndex,
                    pageCount: pageCount,
                    turn: turn
                ) {
                    let pointsLeft = switch policy.pageDirection {
                    case .ltr: turn == .previous
                    case .rtl: turn == .next
                    }
                    Button {
                        onTurn(turn)
                    } label: {
                        HStack(spacing: 8) {
                            if pointsLeft {
                                Image(systemName: "chevron.left")
                            }
                            Text("Page \(destination + 1)")
                                .frame(maxWidth: .infinity)
                            if !pointsLeft {
                                Image(systemName: "chevron.right")
                            }
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(palette.textSecondary)
                        .padding(.horizontal, 14)
                        .frame(minHeight: 48)
                        .background(palette.surface)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(turn == .previous ? "Previous page" : "Next page")
                    .accessibilityIdentifier(
                        turn == .previous ? "reader.previousPage" : "reader.nextPage"
                    )
                }
            }
        }
        .environment(\.layoutDirection, .leftToRight)
    }
}

// MARK: - One hadith

private struct HadithBlock: View {
    let model: ReaderModel
    let hadith: ReaderHadith
    let translationState: ReaderModel.TranslationState?
    let language: String
    let arabicFontSize: Double
    let preferences: ReaderPreferences
    let palette: ReaderPalette
    let onRetry: () -> Void
    let onShowPaywall: () -> Void

    @State private var citationsTranslation: ReaderTranslation?
    @State private var isEditingNote = false
    @State private var isSubmittingTranslation = false
    @State private var reportedTranslation: ReaderTranslation?

    var body: some View {
        VStack(spacing: 16) {
            referenceLabel

            if preferences.arabicVisible {
                Text(hadith.arabicText)
                    .font(Theme.arabic(arabicFontSize, preferences.arabicFont))
                    .lineSpacing(arabicFontSize * 0.75)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .environment(\.layoutDirection, .rightToLeft)
                    .accessibilityIdentifier("reader.arabic")
            }

            if let narrator = hadith.narrator, !narrator.isEmpty {
                Text(narrator)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if preferences.translationVisible {
                translationSection
                    .environment(
                        \.layoutDirection,
                        LocaleFallback.isRTL(preferences.translationLocale) ? .rightToLeft : .leftToRight
                    )
            }

            contributionRow

            Text(hadith.authenticity.displayLabel)
                .font(.caption2)
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("reader.authenticity")

            HadithActionRow(
                palette: palette,
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

    /// The quiet reference label that replaces the numbered medallion (R4):
    /// a small muted line above the Arabic, matching the minimal reference
    /// treatment in the Sajda middle-of-page reference.
    private var referenceLabel: some View {
        HStack(spacing: 6) {
            Text(hadith.referenceDisplay)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(palette.textSecondary)
                .accessibilityIdentifier("reader.reference")
            Spacer(minLength: 0)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var translationSection: some View {
        if language == "en" {
            if let english = hadith.englishText, !english.isEmpty {
                translationText(english)
            } else {
                Text("No English translation available yet.")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
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
                    .tint(palette.textSecondary)
                Text("AI translation…")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
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
                actionTitle: "See plans",
                action: onShowPaywall
            )

        case .failed(.failed):
            Button(action: onRetry) {
                Text("AI translation unavailable · retry")
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
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
                .foregroundStyle(palette.textPrimary.opacity(0.92))
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
                    .foregroundStyle(palette.textSecondary)
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
                .foregroundStyle(palette.textSecondary)
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
                    .foregroundStyle(palette.textSecondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func quietNotice(
        icon: String,
        text: String,
        actionTitle: String?,
        action: (() -> Void)? = nil
    ) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(palette.textSecondary)
            Text(text)
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(.center)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader.quotaPaywall")
            } else if actionTitle != nil {
                Text("Sign-in lives on the Settings tab.")
                    .font(.caption2)
                    .foregroundStyle(palette.textSecondary.opacity(0.7))
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
        .foregroundStyle(palette.textSecondary.opacity(0.8))
        .buttonStyle(.plain)
        .padding(.top, 2)
    }
}

// MARK: - Per-hadith actions

/// The quiet action row under each hadith: bookmark (amber), favorite (pink),
/// and a note. Nothing else on the page uses color.
struct HadithActionRow: View {
    var palette: ReaderPalette = .dark
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
                tint: palette.textSecondary,
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
                .foregroundStyle(filled ? tint : palette.textSecondary.opacity(0.75))
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
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @State private var content: String = ""
    @FocusState private var isFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $content)
                    .focused($isFocused)
                    .font(.body)
                    .foregroundStyle(palette.textPrimary)
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
                        .foregroundStyle(palette.textSecondary)
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
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
    }
}

extension ReaderTranslation: Identifiable {
    var id: String { translationId }
}

#if DEBUG
/// Deterministic fixture for the R3 paging tests and the R4 typography,
/// theme, and visibility screenshot and accessibility matrix. R3_* variables
/// keep their paging meaning; R4_* variables select the reader chrome to
/// render: theme, font, size, and whether the revealed chrome shows.
struct ReaderPagingTestFixtureView: View {
    @State private var pageIndex: Int
    private let preferences: ReaderPreferences
    private let longContent: Bool
    private let pageCount = 3
    private let palette: ReaderPalette
    private let showChrome: Bool

    init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        var preferences = ReaderPreferences()
        preferences.translationLocale = environment["R3_TRANSLATION_LOCALE"] ?? "en"
        preferences.arabicVisible = environment["R3_ARABIC_VISIBLE"] != "false"
        preferences.translationVisible = environment["R3_TRANSLATION_VISIBLE"] != "false"
        preferences.readingDirection = ReadingDirection(
            rawValue: environment["R3_READING_DIRECTION"] ?? "auto"
        ) ?? .auto
        preferences.theme = ReaderTheme(rawValue: environment["R4_THEME"] ?? "") ?? .dark
        preferences.arabicFont = ArabicFont(decoding: environment["R4_FONT"])
        if let size = Double(environment["R4_SIZE"] ?? "") {
            preferences.arabicFontSize = size
        }
        self.preferences = preferences
        longContent = environment["R3_LONG_CONTENT"] == "true"
        showChrome = environment["R4_CHROME"] == "true"
        palette = ReaderPalette.resolved(
            preferences.theme,
            systemDark: environment["R4_SYSTEM_DARK"] != "light"
        )
        _pageIndex = State(initialValue: Int(environment["R3_INITIAL_PAGE"] ?? "1") ?? 1)
    }

    private var policy: ReaderPagingPolicy {
        ReaderPagingPolicy(preferences: preferences)
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 24) {
                    if showChrome {
                        Text("Page \(pageIndex + 1) of \(pageCount)")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(palette.textSecondary)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 7)
                            .background(palette.surface.opacity(0.96))
                            .clipShape(Capsule())
                            .overlay(Capsule().strokeBorder(palette.divider, lineWidth: 1))
                            .accessibilityIdentifier("r4.progressPill")
                    } else if let fraction = compactProgress {
                        ReaderCompactProgressBar(fraction: fraction, palette: palette)
                            .accessibilityIdentifier("r4.compactProgress")
                    }

                    Text("Page \(pageIndex + 1)")
                        .font(.headline)
                        .foregroundStyle(palette.textPrimary)
                        .accessibilityIdentifier("r3.page")

                    ReaderChapterHeader(title: "Kitab al-Iman", palette: palette)
                        .accessibilityIdentifier("r4.chapterHeader")

                    if preferences.arabicVisible {
                        Text("إنما الأعمال بالنيات")
                            .font(Theme.arabic(preferences.arabicFontSize, preferences.arabicFont))
                            .lineSpacing(preferences.arabicFontSize * 0.75)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(palette.textPrimary)
                            .environment(\.layoutDirection, .rightToLeft)
                            .accessibilityIdentifier("r3.arabic")
                    }

                    if preferences.translationVisible {
                        Text(
                            LocaleFallback.isRTL(preferences.translationLocale)
                                ? "اعمال کا دار و مدار نیتوں پر ہے"
                                : "Actions are judged by intentions."
                        )
                        .font(.body)
                        .foregroundStyle(palette.textPrimary)
                        .environment(
                            \.layoutDirection,
                            LocaleFallback.isRTL(preferences.translationLocale) ? .rightToLeft : .leftToRight
                        )
                        .accessibilityIdentifier("r3.translation")
                    }

                    if longContent {
                        ForEach(0..<80, id: \.self) { line in
                            Text("Long page line \(line)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .foregroundStyle(palette.textPrimary)
                                .accessibilityIdentifier("r3.long.\(line)")
                        }
                    }

                    Text("End of page")
                        .foregroundStyle(palette.textSecondary)
                        .accessibilityIdentifier("r3.end")

                    ReaderEndNavigation(
                        policy: policy,
                        currentPageIndex: pageIndex,
                        pageCount: pageCount,
                        palette: palette,
                        onTurn: turnPage
                    )
                }
                .padding(22)
            }
            .id(pageIndex)
            .accessibilityIdentifier("r3.scroll")
        }
        .environment(\.readerPalette, palette)
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: preferences.theme))
        .overlay {
            WindowSwipeRecognizer(
                pageDirection: policy.pageDirection,
                isEnabled: { true },
                onTurn: turnPage
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .accessibilityAction(named: "Previous page") { turnPage(.previous) }
        .accessibilityAction(named: "Next page") { turnPage(.next) }
        .accessibilityIdentifier("r3.surface")
    }

    private var compactProgress: Double? {
        Double(pageIndex + 1) / Double(pageCount)
    }

    private func turnPage(_ turn: ReaderPageTurn) {
        guard let destination = policy.destination(
            from: pageIndex,
            pageCount: pageCount,
            turn: turn
        ) else { return }
        pageIndex = destination
    }
}
#endif

/// A window-level pan recognizer that turns reader pages. SwiftUI gesture
/// arbitration between a vertical ScrollView and horizontal swipe never
/// resolves reliably, so the recognizer observes all touches simultaneously
/// (never canceling them) and only reacts to horizontal-dominant drags.
/// Vertical scrolling inside a page is untouched.
private struct WindowSwipeRecognizer: UIViewRepresentable {
    var pageDirection: HorizontalDirection
    var isEnabled: () -> Bool
    var onTurn: (ReaderPageTurn) -> Void

    func makeCoordinator() -> ReaderPagingPanHandler {
        ReaderPagingPanHandler(
            pageDirection: pageDirection,
            isEnabled: isEnabled,
            onTurn: onTurn
        )
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            if let window = view.window { context.coordinator.installIfNeeded(on: window) }
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.pageDirection = pageDirection
        context.coordinator.onTurn = onTurn
        if let window = uiView.window { context.coordinator.installIfNeeded(on: window) }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: ReaderPagingPanHandler) {
        coordinator.uninstall()
    }
}
