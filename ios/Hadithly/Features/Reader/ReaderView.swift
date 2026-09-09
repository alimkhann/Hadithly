import ClerkConvex
import ClerkKit
import ConvexMobile
import SwiftUI
import UIKit

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
    @State private var showReaderMenu = false
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
                CollectionOutlineSheet(
                    model: model,
                    arabicVisible: environment.preferences.preferences.arabicVisible
                )
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
                toggleChrome(model, withHaptic: true)
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
            toggleChrome(model, withHaptic: false)
        }
        // A layout-affecting preference change (font, size, visibility,
        // translation locale) invalidates the raw offset; the semantic
        // anchor restores the exact position against the new signature.
        .onChange(of: environment.preferences.preferences.layoutProjection) { _, _ in
            model.reanchorAfterLayoutChange()
        }
    }

    private func toggleChrome(_ model: ReaderModel, withHaptic: Bool) {
        if withHaptic {
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        }
        withAnimation(.easeInOut(duration: 0.2)) {
            model.chromeVisible.toggle()
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
            if model.hasNextPage {
                lastTurn = .next
                model.pageIndex += 1
            } else if let next = model.nextVolume {
                // An outward swipe past the last page advances to the next
                // volume's first page — the same jump path as the pills.
                lastTurn = .next
                model.switchToVolume(next.volumeId, edge: .first)
            }
        } else {
            if model.hasPreviousPage {
                lastTurn = .previous
                model.pageIndex -= 1
            } else if let previous = model.previousVolume {
                // Before the first page goes to the previous volume's last
                // page — the same jump path as the pills.
                lastTurn = .previous
                model.switchToVolume(previous.volumeId, edge: .last)
            }
        }
    }

    private func chromeOverlay(_ model: ReaderModel) -> some View {
        VStack {
            Spacer()
            if showReaderMenu {
                ReaderMenuStack(
                    location: model.currentVolumeTitle ?? collectionName,
                    palette: palette,
                    onContents: {
                        showReaderMenu = false
                        showIndex = true
                    },
                    onSettings: {
                        showReaderMenu = false
                        showSettings = true
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            HStack {
                ReaderChromeCircle("chevron.down", label: "Close reader", palette: palette) { dismiss() }
                    .accessibilityIdentifier("reader.close")
                Spacer()
                ReaderChromeCircle(
                    showReaderMenu ? "xmark" : "line.3.horizontal",
                    label: showReaderMenu ? "Close reader menu" : "Open reader menu",
                    palette: palette
                ) {
                    withAnimation(.easeInOut(duration: 0.2)) { showReaderMenu.toggle() }
                }
                .accessibilityIdentifier("reader.menu")
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 16)
        }
        .transition(.opacity)
    }
}

private struct ReaderChromeCircle: View {
    let image: String
    let label: String
    let palette: ReaderPalette
    let action: () -> Void

    init(_ image: String, label: String, palette: ReaderPalette, action: @escaping () -> Void) {
        self.image = image
        self.label = label
        self.palette = palette
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.title3.weight(.medium))
                .foregroundStyle(palette.textPrimary)
                .frame(width: 52, height: 52)
                .background(palette.surface.opacity(0.98))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct ReaderMenuStack: View {
    let location: String
    let palette: ReaderPalette
    let onContents: () -> Void
    let onSettings: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            menuCard(title: location, subtitle: "Current location", image: "mappin.and.ellipse", action: {})
            menuCard(title: "Contents", subtitle: "Volumes and chapters", image: "list.bullet", action: onContents)
            menuCard(title: "Reader settings", subtitle: "Type, appearance, and text", image: "textformat.size", action: onSettings)
        }
    }

    private func menuCard(title: String, subtitle: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(palette.textSecondary)
                }
                Spacer()
                Image(systemName: image).font(.title3).foregroundStyle(palette.textSecondary)
            }
            .padding(18)
            .background(palette.surface.opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .buttonStyle(.plain)
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
                    .fill(palette.textSecondary.opacity(0.8))
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

    /// The selected volume backing this page, for the volume-start header.
    private var selectedVolume: OutlineVolume? {
        guard let id = model.selectedVolumeId else { return nil }
        return model.volumes.first { $0.volumeId == id }
    }

    /// Page-top corner text: the volume title, plus the `: first–last`
    /// hadith-number range only when the volume is fully cached and the
    /// range is computable. Nil when no volume is selected.
    private var volumeCornerText: String? {
        guard let title = model.currentVolumeTitle else { return nil }
        return ReaderVolumeRange.cornerText(volumeTitle: title, pages: model.pages)
    }

    /// One hadith row with its scroll-anchor tracking. Factored out so the
    /// chapter group (header + first hadith) and plain hadiths share it.
    private func hadithRow(_ hadith: ReaderHadith) -> some View {
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

    var body: some View {
        GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    if hadiths.isEmpty {
                        VStack {
                            ProgressView("Loading page")
                                .tint(palette.textSecondary)
                                .padding(.top, 120)
                                .accessibilityIdentifier("reader.pageLoading")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        // Slice A (R6): whitespace separates hadiths — no divider
                        // hairlines. The corner label yields to the volume
                        // header on the volume's first page. Rhythm: 28pt
                        // between hadiths, generous space above chapter
                        // lines (28 + 12 top padding), tight 12pt from a
                        // chapter line to its first hadith.
                        VStack(spacing: 28) {
                            if ReaderVolumeHeader.showsCornerLabel(pageIndex: currentPageIndex),
                               let corner = volumeCornerText {
                                ReaderVolumeCornerLabel(text: corner, palette: palette)
                            }
                            if ReaderVolumeHeader.showsHeader(pageIndex: currentPageIndex),
                               let volume = selectedVolume {
                                ReaderVolumeHeaderView(volume: volume, palette: palette)
                            }
                            ForEach(Array(hadiths.enumerated()), id: \.element.internalId) { index, hadith in
                                if chapterOpenings.contains(index) {
                                    VStack(spacing: 12) {
                                        ReaderChapterHeader(
                                            title: hadith.chapterName ?? "",
                                            arabicTitle: ReaderChapterLine.arabicTitle(
                                                forChapterId: hadith.chapterId,
                                                in: model.volumes,
                                                volumeId: model.selectedVolumeId
                                            ),
                                            arabicVisible: preferences.arabicVisible,
                                            palette: palette
                                        )
                                        hadithRow(hadith)
                                    }
                                    .padding(.top, 12)
                                } else {
                                    hadithRow(hadith)
                                }
                            }

                            ReaderVolumePills(
                                policy: ReaderPagingPolicy(preferences: preferences),
                                state: model.pillState,
                                palette: palette,
                                onFollow: { model.followPill($0) }
                            )
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 80)
                    }
                }
                .scrollIndicators(.hidden)
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
        .onAppear { chapterOpenings = ReaderChapterBoundaries.openingIndices(in: hadiths) }
        .onChange(of: hadiths) { _, updated in
            chapterOpenings = ReaderChapterBoundaries.openingIndices(in: updated)
        }
        .accessibilityIdentifier("reader.page")
    }
}

/// Page-top corner label (R6 slice A): the localized volume title at the
/// leading top corner, quiet secondary style, with the `: first–last`
/// hadith-number range appended only when the volume is fully cached and
/// the range is computable (`ReaderVolumeRange`).
private struct ReaderVolumeCornerLabel: View {
    let text: String
    let palette: ReaderPalette

    var body: some View {
        Text(text)
            .font(.caption2.weight(.medium))
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reader.volumeCorner")
    }
}

/// Volume-start header (R6 slice A): the volume title with a localized/// count line beneath (String Catalog plurals). First page of a volume
/// only; the corner label yields to it there.
private struct ReaderVolumeHeaderView: View {
    let volume: OutlineVolume
    let palette: ReaderPalette

    var body: some View {
        VStack(spacing: 6) {
            Text(volume.title)
                .font(.title2.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
            Text("\(volume.hadithCount) hadiths")
                .font(.footnote)
                .foregroundStyle(palette.textSecondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(volume.title), \(volume.hadithCount) hadiths")
        .accessibilityIdentifier("reader.volumeHeader")
    }
}

/// The quiet, name-only chapter line (R6 slice A). Never the word
/// "Chapter", never invented: rendered only for source-provided chapter
/// transitions. Near-body size in the primary text color; the Arabic
/// title stays a smaller secondary second line only when it differs.
/// Generous space above (from the page spacing plus its own top padding),
/// tight gap to the first hadith below (from the chapter group's spacing).
private struct ReaderChapterHeader: View {
    let title: String
    let arabicTitle: String?
    let arabicVisible: Bool
    let palette: ReaderPalette

    var body: some View {
        VStack(spacing: 4) {
            Text(title)
                .font(.callout.weight(.semibold))
                .foregroundStyle(palette.textPrimary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle = ReaderChapterLine.arabicSubtitle(
                title: title,
                arabicTitle: arabicTitle,
                arabicVisible: arabicVisible
            ) {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("reader.chapterHeader")
    }

    private var accessibilityText: String {
        if let subtitle = ReaderChapterLine.arabicSubtitle(
            title: title,
            arabicTitle: arabicTitle,
            arabicVisible: arabicVisible
        ) {
            return "\(title), \(subtitle)"
        }
        return title
    }
}

/// End-of-page navigation (R6 round 2): TWO bottom pills in the Sajda
/// `209 Page` style — LEFT is the previous page (`‹ Page 4`), RIGHT is the
/// next page (`Page 6 ›`). Each pill carries one snug internal chevron
/// pointing the logical way with a 44pt target. The stack keeps the
/// ambient layout direction, so in RTL the previous pill sits on the
/// right with mirrored chevrons while the labels stay logical. At a
/// volume edge the outward pill names the neighboring volume's full
/// title and jumps across; the absolute ends show no outward pill.
struct ReaderVolumePills: View {
    let policy: ReaderPagingPolicy
    let state: ReaderPagePills.State
    let palette: ReaderPalette
    let onFollow: (ReaderPagePills.Pill) -> Void

    var body: some View {
        HStack(spacing: 12) {
            if let previous = state.previous {
                pagePill(previous)
            } else {
                // Keeps the next pill pinned to the trailing edge when the
                // previous pill is absent at the absolute start.
                Color.clear.frame(maxWidth: .infinity)
            }
            if let next = state.next {
                pagePill(next)
            } else {
                Color.clear.frame(maxWidth: .infinity)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.pagePills")
        .environment(
            \.layoutDirection,
            policy.pageDirection == .rtl ? .rightToLeft : .leftToRight
        )
    }

    private func pagePill(_ pill: ReaderPagePills.Pill) -> some View {
        let turn = pill.turn
        return Button {
            onFollow(pill)
        } label: {
            HStack(spacing: 2) {
                if turn == .previous {
                    chevron(turn)
                }
                Text(pill.label)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(palette.textSecondary)
                    .lineLimit(1)
                if turn == .next {
                    chevron(turn)
                }
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(palette.surface.opacity(0.96))
            .clipShape(Capsule())
            .overlay(Capsule().strokeBorder(palette.divider, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, minHeight: 48)
        .accessibilityLabel(
            turn == .previous ? "Previous page, \(pill.label)" : "Next page, \(pill.label)"
        )
        .accessibilityIdentifier(
            turn == .previous ? "reader.previousPage" : "reader.nextPage"
        )
    }

    private func chevron(_ turn: ReaderPageTurn) -> some View {
        Image(systemName: ReaderPagePills.chevronImage(for: turn, pageDirection: policy.pageDirection))
            .font(.caption.weight(.semibold))
            .foregroundStyle(palette.textSecondary)
            .frame(width: 24, height: 44)
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
    @State private var showingSource = false

    /// Round-2 narrator placement for these preferences: above the Arabic
    /// block in Arabic-only mode, beside the translation otherwise.
    private var narratorPlacement: ReaderNarratorPlacement {
        ReaderNarratorPlacement.placement(
            arabicVisible: preferences.arabicVisible,
            translationVisible: preferences.translationVisible
        )
    }

    /// The narrator line in every visibility mode. Arabic-aligned (RTL)
    /// between the header and the Arabic block in Arabic-only mode;
    /// leading-edge beside the translation otherwise.
    @ViewBuilder
    private func narratorView(arabicAligned: Bool) -> some View {
        if ReaderNarratorLine.shouldShow(
            narrator: hadith.narrator,
            arabicVisible: preferences.arabicVisible,
            translationVisible: preferences.translationVisible
        ) {
            Text(hadith.narrator ?? "")
                .font(.caption)
                .foregroundStyle(palette.textSecondary)
                .multilineTextAlignment(arabicAligned ? .trailing : .leading)
                .frame(
                    maxWidth: .infinity,
                    alignment: arabicAligned ? .trailing : .leading
                )
                .environment(
                    \.layoutDirection,
                    arabicAligned || LocaleFallback.isRTL(preferences.translationLocale)
                        ? .rightToLeft : .leftToRight
                )
                .accessibilityIdentifier("reader.narrator")
        }
    }

    var body: some View {
        // Slice A (R6) with the round-2 narrator correction: a quiet block.
        // One header per hadith at the top — the grade dot, the bracketed
        // `[Collection – n]` label, and the saved-state mini markers —
        // tappable for the source sheet. The narrator shows in every mode:
        // in Arabic-only mode it sits between the header and the Arabic
        // block, aligned to the Arabic direction; otherwise it keeps its
        // leading-edge line beside the translation. There is no bottom
        // label, no bare-number marker, no overflow button, and no
        // dividers.
        VStack(alignment: .leading, spacing: 14) {
            headerRow

            if narratorPlacement == .aboveArabic {
                narratorView(arabicAligned: true)
            }

            if preferences.arabicVisible {
                Text(hadith.arabicText)
                    .font(Theme.arabic(arabicFontSize, preferences.arabicFont))
                    .lineSpacing(arabicFontSize * 0.75)
                    .multilineTextAlignment(.leading)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .environment(\.layoutDirection, .rightToLeft)
                    .accessibilityIdentifier("reader.arabic")
            }

            if narratorPlacement == .belowArabic {
                narratorView(arabicAligned: false)
            }

            if preferences.translationVisible {
                translationSection
                    .environment(
                        \.layoutDirection,
                        LocaleFallback.isRTL(preferences.translationLocale) ? .rightToLeft : .leftToRight
                    )
            }
        }
        // R5 context menu unchanged: the only sighted path to actions is
        // long-press. VoiceOver custom actions on the header are the
        // screen-reader equivalent (see headerRow).
        .contextMenu {
            Text(hadith.referenceDisplay)
            hadithMenuContents
        }
        .sheet(isPresented: $showingSource) {
            HadithSourceSheet(hadith: hadith)
                .presentationDetents([.medium])
        }
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

    /// One header per hadith at the top: the grade dot, the bracketed
    /// `[Collection – n]` label, and the saved-state mini markers (amber
    /// bookmark when bookmarked, pink heart when favorited). Tapping opens
    /// the source sheet; copy/share payloads keep the full source line
    /// unchanged (`ReaderShare`). The markers are non-interactive
    /// indicators — actions remain the long-press context menu, the
    /// VoiceOver custom actions below, and the bottom menu (later).
    ///
    /// The seven R5 actions live here as VoiceOver custom actions: the
    /// screen-reader equivalent of the long-press menu. Share presents the
    /// system share sheet programmatically with the same canonical URL the
    /// menu's ShareLink carries.
    private var headerRow: some View {
        let kind = ReaderGradeKind(normalizedGrade: hadith.authenticity.normalizedGrade)
        let bookmarked = model.isBookmarked(hadith)
        let favorited = model.isFavorite(hadith)
        return HStack(spacing: 7) {
            Button {
                showingSource = true
            } label: {
                HStack(spacing: 7) {
                    Circle()
                        .fill(ReaderGradeDot.color(for: kind, palette: palette))
                        .frame(width: 8, height: 8)
                    Text(ReaderSourceLabel.headerText(for: hadith))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(palette.textPrimary)
                        .multilineTextAlignment(.leading)
                }
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("reader.hadithLabel")
            .accessibilityLabel("\(ReaderSourceLabel.text(for: hadith)), \(kind.accessibilityName)")
            .accessibilityHint("Shows source details")
            .accessibilityAction(named: bookmarked ? "Remove Bookmark" : "Bookmark") {
                model.toggleBookmark(hadith)
            }
            .accessibilityAction(named: favorited ? "Remove Favorite" : "Favorite") {
                model.toggleFavorite(hadith)
            }
            .accessibilityAction(named: model.noteContent(for: hadith) != nil ? "Edit Note" : "Add Note") {
                isEditingNote = true
            }
            .accessibilityAction(named: "Copy") {
                copyHadith()
            }
            .accessibilityAction(named: "Share") {
                shareHadith()
            }
            .accessibilityAction(named: "Suggest Translation") {
                isSubmittingTranslation = true
            }
            .modifier(HadithReportAction(
                translation: activeTranslation,
                reportedTranslation: $reportedTranslation
            ))
            ForEach(ReaderSavedMarkers.visible(bookmarked: bookmarked, favorited: favorited), id: \.self) { marker in
                switch marker {
                case .bookmark:
                    Image(systemName: "bookmark.fill")
                        .font(.caption2)
                        .foregroundStyle(Color(red: 0.96, green: 0.62, blue: 0.04))
                        .accessibilityIdentifier("reader.savedBookmark")
                        .accessibilityLabel("Bookmarked")
                case .favorite:
                    Image(systemName: "heart.fill")
                        .font(.caption2)
                        .foregroundStyle(.pink)
                        .accessibilityIdentifier("reader.savedFavorite")
                        .accessibilityLabel("Favorited")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
    }

    private func shareHadith() {
        guard let url = ReaderShare.canonicalURL(for: hadith) else { return }
        guard let scene = UIApplication.shared.connectedScenes.first(
            where: { $0.activationState == .foregroundActive }
        ) as? UIWindowScene,
        let presenter = scene.windows.first(where: { $0.isKeyWindow })?.rootViewController
        else { return }
        var top = presenter
        while let presented = top.presentedViewController { top = presented }
        let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
        if let popover = activity.popoverPresentationController {
            popover.sourceView = top.view
            popover.sourceRect = CGRect(
                x: top.view.bounds.midX,
                y: top.view.bounds.midY,
                width: 0,
                height: 0
            )
            popover.permittedArrowDirections = []
        }
        top.present(activity, animated: true)
    }

    /// One code path for the long-press context menu and the overflow Menu:
    /// bookmark and favorite toggle with state-reflecting labels, note adds
    /// or edits, copy takes the visible text, share sends only the canonical
    /// URL, and the secondary contributions stay below a divider. Report
    /// appears only when a loaded non-English translation exists — the same
    /// gating the old inline row used.
    @ViewBuilder
    private var hadithMenuContents: some View {
        Button {
            model.toggleBookmark(hadith)
        } label: {
            Label(
                model.isBookmarked(hadith) ? "Remove Bookmark" : "Bookmark",
                systemImage: model.isBookmarked(hadith) ? "bookmark.fill" : "bookmark"
            )
        }
        .accessibilityIdentifier("reader.bookmark")

        Button {
            model.toggleFavorite(hadith)
        } label: {
            Label(
                model.isFavorite(hadith) ? "Remove Favorite" : "Favorite",
                systemImage: model.isFavorite(hadith) ? "heart.fill" : "heart"
            )
        }
        .accessibilityIdentifier("reader.favorite")

        Button {
            isEditingNote = true
        } label: {
            Label(
                model.noteContent(for: hadith) != nil ? "Edit Note" : "Add Note",
                systemImage: "square.and.pencil"
            )
        }
        .accessibilityIdentifier("reader.note")

        Button {
            copyHadith()
        } label: {
            Label("Copy", systemImage: "doc.on.doc")
        }
        .accessibilityIdentifier("reader.copy")

        if let url = ReaderShare.canonicalURL(for: hadith) {
            ShareLink(item: url) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .accessibilityIdentifier("reader.share")
        }

        Divider()

        if let translation = activeTranslation {
            Button {
                reportedTranslation = translation
            } label: {
                Label("Report Translation", systemImage: "flag")
            }
            .accessibilityIdentifier("reader.reportTranslation")
        }

        Button {
            isSubmittingTranslation = true
        } label: {
            Label("Suggest Translation", systemImage: "text.bubble")
        }
        .accessibilityIdentifier("reader.suggestTranslation")
    }

    private func copyHadith() {
        UIPasteboard.general.string = ReaderShare.copyText(
            for: hadith,
            arabicVisible: preferences.arabicVisible,
            translationVisible: preferences.translationVisible,
            translationText: displayedTranslation,
            translationIsAI: activeTranslation?.source == "gemini_ai"
        )
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
                .frame(maxWidth: .infinity, alignment: .leading)
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
}

/// Conditionally exposes the Report custom action on the source label:
/// VoiceOver must not advertise Report when no loaded non-English
/// translation exists to report.
private struct HadithReportAction: ViewModifier {
    let translation: ReaderTranslation?
    @Binding var reportedTranslation: ReaderTranslation?

    func body(content: Content) -> some View {
        if let translation {
            content.accessibilityAction(named: "Report Translation") {
                reportedTranslation = translation
            }
        } else {
            content
        }
    }
}

// MARK: - Source sheet

/// The small source sheet behind the grade-dot label (R6 slice A): source
/// name, scope/grade text, and the source URL when present. The source
/// name left the page but stays one tap away; copy/share keep the full
/// source line unchanged.
struct HadithSourceSheet: View {
    @Environment(\.readerPalette) private var palette
    @Environment(\.readerTheme) private var readerTheme
    @Environment(\.openURL) private var openURL
    @Environment(\.dismiss) private var dismiss

    let hadith: ReaderHadith

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 12) {
                Text(hadith.authenticity.sourceName)
                    .font(.headline)
                    .foregroundStyle(palette.textPrimary)
                    .accessibilityIdentifier("reader.sourceSheet.name")
                Text(hadith.authenticity.displayLabel)
                    .font(.subheadline)
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityIdentifier("reader.sourceSheet.scope")
                if let url = sourceURL {
                    Button {
                        openURL(url)
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "link")
                                .font(.caption)
                            Text(url.host ?? hadith.authenticity.sourceUrl)
                                .font(.footnote)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .foregroundStyle(Theme.accent)
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("reader.sourceSheet.url")
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(20)
            .background(palette.background)
            .navigationTitle(ReaderSourceLabel.text(for: hadith))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
        .accessibilityIdentifier("reader.sourceSheet")
    }

    private var sourceURL: URL? {
        let raw = hadith.authenticity.sourceUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return nil }
        return URL(string: raw)
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
/// R5 contents fixture: renders the real CollectionOutlineSheet against a
/// seeded outline (one volume with source-provided chapters, one without)
/// with no network. Launch with `-R5ContentsFixture`. Chapter rows, the
/// jump field, and its inline validation error all render; well-formed
/// jumps and chapter taps dismiss the sheet (the landing itself travels the
/// backend-backed R2 target path, proven live elsewhere).
struct ReaderContentsTestFixtureView: View {
    @State private var model: ReaderModel
    @State private var showSheet = true

    init() {
        let provider = ClerkConvexAuthProvider()
        let convex = ConvexClientWithAuth(
            deploymentUrl: "https://example.invalid",
            authProvider: provider
        )
        let seeded = ReaderModel(
            convex: convex,
            collectionSlug: "bukhari",
            collectionName: "Sahih al-Bukhari",
            language: "en",
            isSignedIn: { false }
        )
        seeded.seedForUITest(
            volumes: [
                OutlineVolume(
                    volumeId: "1",
                    title: "Volume 1",
                    firstChapterTitle: "Revelation",
                    hadithCount: 7,
                    chapters: [
                        OutlineChapter(
                            chapterId: "1",
                            title: "Revelation",
                            arabicTitle: "كتاب بدء الوحي",
                            hadithCount: 5,
                            firstProviderHadithId: "1"
                        ),
                        OutlineChapter(
                            chapterId: "2",
                            title: "Belief",
                            hadithCount: 2,
                            firstProviderHadithId: "6"
                        ),
                    ]
                ),
                OutlineVolume(
                    volumeId: "2",
                    title: "Volume 2",
                    hadithCount: 51
                ),
            ],
            selectedVolumeId: "1"
        )
        _model = State(initialValue: seeded)
    }

    var body: some View {
        ZStack {
            ReaderPalette.dark.background.ignoresSafeArea()
            if showSheet {
                Text("Sheet open")
                    .foregroundStyle(ReaderPalette.dark.textSecondary)
                    .accessibilityIdentifier("r5.sheetOpen")
            } else {
                Text("Sheet dismissed")
                    .foregroundStyle(ReaderPalette.dark.textSecondary)
                    .accessibilityIdentifier("r5.dismissed")
            }
        }
        .environment(\.readerPalette, ReaderPalette.dark)
        .environment(\.readerTheme, ReaderTheme.dark)
        .sheet(isPresented: $showSheet) {
            CollectionOutlineSheet(model: model, arabicVisible: true)
        }
    }
}
#endif

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

                    ReaderChapterHeader(
                        title: "Kitab al-Iman",
                        arabicTitle: nil,
                        arabicVisible: preferences.arabicVisible,
                        palette: palette
                    )
                        .accessibilityIdentifier("r4.chapterHeader")

                    if preferences.arabicVisible {
                        Text("إنما الأعمال بالنيات")
                            .font(Theme.arabic(preferences.arabicFontSize, preferences.arabicFont))
                            .lineSpacing(preferences.arabicFontSize * 0.75)
                            .multilineTextAlignment(.leading)
                            .foregroundStyle(palette.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
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

                    ReaderVolumePills(
                        policy: policy,
                        state: ReaderPagePills.state(
                            pageIndex: pageIndex,
                            hasPreviousPage: pageIndex > 0,
                            hasNextPage: pageIndex < pageCount - 1,
                            atLoadedPage: true,
                            volumes: [],
                            selectedVolumeId: nil
                        ),
                        palette: palette,
                        onFollow: { turnPage($0.turn) }
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

#if DEBUG
/// Deterministic slice-A fixture: the quiet page with no network. Launch
/// with `-R6AReaderFixture`. Three volumes in outline order: Volume 1
/// (one page, hadith 55), Volume 2 (two pages — 57/58 then 59 — with the
/// volume header, a sahih block, a quiet name-only chapter line with its
/// Arabic subtitle, a daif block with no source URL, the corner label
/// with its fully-cached range, and a hasan block), and Volume 3 (one
/// page, hadith 61). The two bottom pills and the window swipe turn pages
/// and cross volumes through the production pill state. The first visit
/// to another volume shows the reader loading state for
/// `R6A_VOLUME_DELAY` seconds (default 0.6). All blocks, headers, and
/// pills are the real production views.
///
/// Environment overrides (all default to the fully-loaded mixed page):
/// - `R6A_ARABIC_VISIBLE=false` hides the Arabic layer.
/// - `R6A_TRANSLATION_VISIBLE=false` hides the translation layer (the
///   narrator stays: it shows in every mode).
/// - `R6A_FULL_CACHE=false` leaves the volume partially cached, so the
///   corner label stays title-only.
/// - `R6A_START_VOLUME=1` starts on Volume 1 (default 2).
/// - `R6A_INITIAL_PAGE=1` starts on the second page (corner label).
/// - `R6A_PAGE_DIRECTION=rtl` mirrors the pills and swipe (default ltr).
/// - `R6A_VOLUME_DELAY=1.5` stretches the cross-volume loading state.
struct ReaderR6ATestFixtureView: View {
    @State private var model: ReaderModel
    @State private var selectedVolumeId: String
    @State private var pageIndex: Int
    @State private var loadingVolumeId: String?
    @State private var visitedVolumes: Set<String>

    private let preferences: ReaderPreferences
    private let palette = ReaderPalette.dark
    private let policy: ReaderPagingPolicy
    private let fullyCached: Bool
    private let volumeDelay: Double

    private var volumes: [OutlineVolume] {
        [
            OutlineVolume(volumeId: "1", title: "Volume 1", hadithCount: 1),
            OutlineVolume(
                volumeId: "2",
                title: "Volume 2",
                hadithCount: 3,
                chapters: [
                    OutlineChapter(
                        chapterId: "42",
                        title: "Belief",
                        arabicTitle: "كتاب الإيمان",
                        hadithCount: 2,
                        firstProviderHadithId: "58"
                    ),
                ]
            ),
            OutlineVolume(volumeId: "3", title: "Volume 3", hadithCount: 1),
        ]
    }

    private var selectedVolume: OutlineVolume {
        volumes.first { $0.volumeId == selectedVolumeId } ?? volumes[1]
    }

    /// Pages per volume, in outline order.
    private var volumeHadiths: [String: [[ReaderHadith]]] {
        [
            "1": [[hadith55]],
            "2": [[hadith57, hadith58], [hadith59]],
            "3": [[hadith61]],
        ]
    }

    private var pageCount: Int {
        volumeHadiths[selectedVolumeId]?.count ?? 1
    }

    private var currentHadiths: [ReaderHadith] {
        guard let pages = volumeHadiths[selectedVolumeId],
              pages.indices.contains(pageIndex)
        else { return [] }
        return pages[pageIndex]
    }

    private var pillState: ReaderPagePills.State {
        ReaderPagePills.state(
            pageIndex: pageIndex,
            hasPreviousPage: pageIndex > 0,
            hasNextPage: pageIndex < pageCount - 1,
            atLoadedPage: loadingVolumeId == nil,
            volumes: volumes,
            selectedVolumeId: selectedVolumeId
        )
    }

    init() {
        let environment = ProcessInfo.processInfo.environment
        var preferences = ReaderPreferences()
        preferences.arabicVisible = environment["R6A_ARABIC_VISIBLE"] != "false"
        preferences.translationVisible = environment["R6A_TRANSLATION_VISIBLE"] != "false"
        self.preferences = preferences
        fullyCached = environment["R6A_FULL_CACHE"] != "false"
        volumeDelay = Double(environment["R6A_VOLUME_DELAY"] ?? "") ?? 0.6
        policy = ReaderPagingPolicy(
            pageDirection: environment["R6A_PAGE_DIRECTION"] == "rtl" ? .rtl : .ltr
        )
        let startVolume = environment["R6A_START_VOLUME"] ?? "2"
        _selectedVolumeId = State(initialValue: ["1", "2", "3"].contains(startVolume) ? startVolume : "2")
        _pageIndex = State(initialValue: max(0, Int(environment["R6A_INITIAL_PAGE"] ?? "0") ?? 0))
        _loadingVolumeId = State(
            initialValue: environment["R6A_LOADING_FIXTURE"] == "true" ? startVolume : nil
        )
        _visitedVolumes = State(initialValue: [startVolume])
        let provider = ClerkConvexAuthProvider()
        let convex = ConvexClientWithAuth(
            deploymentUrl: "https://example.invalid",
            authProvider: provider
        )
        let seeded = ReaderModel(
            convex: convex,
            collectionSlug: "bukhari",
            collectionName: "Sahih al-Bukhari",
            language: "en",
            isSignedIn: { false }
        )
        seeded.seedSavedStateForUITest(
            bookmarkedIds: ["fixture-57"],
            favoritedIds: ["fixture-59"]
        )
        seeded.seedForUITest(
            volumes: [
                OutlineVolume(
                    volumeId: "2",
                    title: "Volume 2",
                    hadithCount: 3,
                    chapters: [
                        OutlineChapter(
                            chapterId: "42",
                            title: "Belief",
                            arabicTitle: "كتاب الإيمان",
                            hadithCount: 2,
                            firstProviderHadithId: "58"
                        ),
                    ]
                ),
            ],
            selectedVolumeId: "2"
        )
        _model = State(initialValue: seeded)
    }

    private var hadith57: ReaderHadith {
        ReaderHadith(
            _id: "fixture-57",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:57",
            providerHadithId: "57",
            collectionSlug: "bukhari",
            volumeId: "2",
            chapterId: nil,
            arabicText: "نَصّ الحديث الأول",
            englishText: "Deeds are judged by intentions.",
            narrator: "Narrated by Umar ibn al-Khattab",
            referenceDisplay: "Sahih al-Bukhari · Hadith 57",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "sahih",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.com",
                sourceUrl: "https://sunnah.com/bukhari/about",
                verificationMethod: "manual_collection_mapping"
            )
        )
    }

    private var hadith58: ReaderHadith {
        ReaderHadith(
            _id: "fixture-58",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:58",
            providerHadithId: "58",
            collectionSlug: "bukhari",
            volumeId: "2",
            chapterId: "42",
            arabicText: "نَصّ الحديث الثاني",
            englishText: "None of you truly believes until he loves for his brother what he loves for himself.",
            narrator: nil,
            referenceDisplay: "Sahih al-Bukhari · Hadith 58",
            collectionName: "Sahih al-Bukhari",
            chapterName: "Belief",
            authenticity: ReaderAuthenticity(
                kind: "hadith_grade",
                normalizedGrade: "daif",
                claimScope: "hadith",
                sourceLabel: "Source-provided grade",
                sourceName: "Sunnah.com",
                sourceUrl: "",
                verificationMethod: "source_provided"
            )
        )
    }

    private var hadith59: ReaderHadith {
        ReaderHadith(
            _id: "fixture-59",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:59",
            providerHadithId: "59",
            collectionSlug: "bukhari",
            volumeId: "2",
            chapterId: "42",
            arabicText: "نَصّ الحديث الثالث",
            englishText: "Purity is half of faith.",
            narrator: "Narrated by Anas",
            referenceDisplay: "Sahih al-Bukhari · Hadith 59",
            collectionName: "Sahih al-Bukhari",
            chapterName: "Belief",
            authenticity: ReaderAuthenticity(
                kind: "hadith_grade",
                normalizedGrade: "hasan",
                claimScope: "hadith",
                sourceLabel: "Source-provided grade",
                sourceName: "Sunnah.com",
                sourceUrl: "https://sunnah.com/bukhari/59",
                verificationMethod: "source_provided"
            )
        )
    }

    private var hadith55: ReaderHadith {
        ReaderHadith(
            _id: "fixture-55",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:55",
            providerHadithId: "55",
            collectionSlug: "bukhari",
            volumeId: "1",
            chapterId: nil,
            arabicText: "نَصّ الحديث في المجلد الأول",
            englishText: "The reward of deeds depends upon the intentions.",
            narrator: "Narrated by Aisha",
            referenceDisplay: "Sahih al-Bukhari · Hadith 55",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "sahih",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.com",
                sourceUrl: "https://sunnah.com/bukhari/about",
                verificationMethod: "manual_collection_mapping"
            )
        )
    }

    private var hadith61: ReaderHadith {
        ReaderHadith(
            _id: "fixture-61",
            provider: "sunnah_now",
            canonicalId: "sunnah_now:bukhari:61",
            providerHadithId: "61",
            collectionSlug: "bukhari",
            volumeId: "3",
            chapterId: nil,
            arabicText: "نَصّ الحديث في المجلد الثالث",
            englishText: "Make things easy and do not make them difficult.",
            narrator: "Narrated by Anas bin Malik",
            referenceDisplay: "Sahih al-Bukhari · Hadith 61",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "hasan",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.com",
                sourceUrl: "https://sunnah.com/bukhari/about",
                verificationMethod: "manual_collection_mapping"
            )
        )
    }

    /// Volume pages for the corner label, through the production rule.
    /// Fully cached by default (the real `: first–last` range renders);
    /// `R6A_FULL_CACHE=false` leaves the last page open so the corner
    /// stays title-only.
    private func cachedPages(for volumeId: String) -> [ReaderPageResult] {
        let groups = volumeHadiths[volumeId] ?? []
        return groups.enumerated().map { index, hadiths in
            let isLast = index == groups.count - 1
            return ReaderPageResult(
                items: hadiths, page: index + 1, pageSize: 10,
                totalPages: groups.count, hasMore: isLast ? !fullyCached : true,
                contentVersion: nil, paginationVersion: nil, pageKey: nil
            )
        }
    }

    /// Follows one bottom pill: an in-volume page turn, or a cross-volume
    /// jump to the neighbor's first/last page. A first-visit volume shows
    /// the reader loading state for `volumeDelay` seconds, like the
    /// production fetch.
    private func follow(_ pill: ReaderPagePills.Pill) {
        switch pill.target {
        case .page(let index):
            guard volumeHadiths[selectedVolumeId]?.indices.contains(index) == true else { return }
            pageIndex = index
        case .volumeFirst(let volumeId):
            goToVolume(volumeId, edge: .first)
        case .volumeLast(let volumeId):
            goToVolume(volumeId, edge: .last)
        }
    }

    private func goToVolume(_ volumeId: String, edge: ReaderModel.VolumeEdge) {
        guard volumeId != selectedVolumeId else { return }
        guard visitedVolumes.contains(volumeId) else {
            loadingVolumeId = volumeId
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(volumeDelay))
                visitedVolumes.insert(volumeId)
                loadingVolumeId = nil
                selectedVolumeId = volumeId
                let count = volumeHadiths[volumeId]?.count ?? 1
                pageIndex = edge == .first ? 0 : max(0, count - 1)
            }
            return
        }
        selectedVolumeId = volumeId
        let count = volumeHadiths[volumeId]?.count ?? 1
        pageIndex = edge == .first ? 0 : max(0, count - 1)
    }

    private func turnPage(_ turn: ReaderPageTurn) {
        guard loadingVolumeId == nil else { return }
        let pill = turn == .previous ? pillState.previous : pillState.next
        guard let pill else { return }
        follow(pill)
    }

    var body: some View {
        ZStack {
            palette.background.ignoresSafeArea()
            if loadingVolumeId != nil {
                VStack {
                    ProgressView("Loading page")
                        .tint(palette.textSecondary)
                        .padding(.top, 120)
                        .accessibilityIdentifier("reader.pageLoading")
                }
                .frame(maxWidth: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 28) {
                        if pageIndex == 0 {
                            ReaderVolumeHeaderView(volume: selectedVolume, palette: palette)
                        } else {
                            ReaderVolumeCornerLabel(
                                text: ReaderVolumeRange.cornerText(
                                    volumeTitle: selectedVolume.title,
                                    pages: cachedPages(for: selectedVolumeId)
                                ),
                                palette: palette
                            )
                        }
                        ForEach(currentHadiths, id: \.internalId) { hadith in
                            if let chapterName = hadith.chapterName, !chapterName.isEmpty {
                                VStack(spacing: 12) {
                                    ReaderChapterHeader(
                                        title: chapterName,
                                        arabicTitle: ReaderChapterLine.arabicTitle(
                                            forChapterId: hadith.chapterId,
                                            in: volumes,
                                            volumeId: selectedVolumeId
                                        ),
                                        arabicVisible: preferences.arabicVisible,
                                        palette: palette
                                    )
                                    block(hadith)
                                }
                                .padding(.top, 12)
                            } else {
                                block(hadith)
                            }
                        }
                        ReaderVolumePills(
                            policy: policy,
                            state: pillState,
                            palette: palette,
                            onFollow: follow
                        )
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 80)
                }
            }
        }
        .accessibilityIdentifier("r6a.page")
        .environment(\.readerPalette, palette)
        .environment(\.readerTheme, ReaderTheme.dark)
        .preferredColorScheme(.dark)
        .overlay {
            WindowSwipeRecognizer(
                pageDirection: policy.pageDirection,
                isEnabled: { loadingVolumeId == nil },
                onTurn: turnPage
            )
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
        }
        .accessibilityAction(named: "Previous page") { turnPage(.previous) }
        .accessibilityAction(named: "Next page") { turnPage(.next) }
    }

    private func block(_ hadith: ReaderHadith) -> some View {
        HadithBlock(
            model: model,
            hadith: hadith,
            translationState: nil,
            language: "en",
            arabicFontSize: 26,
            preferences: preferences,
            palette: palette,
            onRetry: {},
            onShowPaywall: {}
        )
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

    func makeUIView(context: Context) -> ReaderPagingHostView {
        let view = ReaderPagingHostView()
        view.isUserInteractionEnabled = false
        view.onWindowAvailable = { [weak handler = context.coordinator] window in
            handler?.installIfNeeded(on: window)
        }
        return view
    }

    func updateUIView(_ uiView: ReaderPagingHostView, context: Context) {
        context.coordinator.isEnabled = isEnabled
        context.coordinator.pageDirection = pageDirection
        context.coordinator.onTurn = onTurn
        if let window = uiView.window { context.coordinator.installIfNeeded(on: window) }
    }

    static func dismantleUIView(_ uiView: ReaderPagingHostView, coordinator: ReaderPagingPanHandler) {
        uiView.onWindowAvailable = nil
        coordinator.uninstall()
    }
}

/// UIKit calls this after the representable actually joins a window. That is
/// the first reliable point to install the reader-wide recognizer, rather
/// than waiting for a later SwiftUI state change such as a pill tap.
private final class ReaderPagingHostView: UIView {
    var onWindowAvailable: ((UIWindow) -> Void)?

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if let window { onWindowAvailable?(window) }
    }
}
