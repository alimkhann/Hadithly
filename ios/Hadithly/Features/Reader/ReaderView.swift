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
    @State private var showSearch = false
    @State private var showSavedShortcut = false
    @State private var showBookmarkPlacement = false
    @State private var showQuotaPaywall = false
    @State private var hasAutoPresentedQuotaPaywall = false
    @State private var pageDragOffset: CGFloat = 0
    @State private var horizontalDragging = false
    @State private var pageScrollFraction: Double = 1
    /// Latest viewport width, for the drag-settle target. Written from the
    /// GeometryReader; the gesture may outlive any single body evaluation.
    @State private var dragViewportWidth: CGFloat = 0

    private var pagingPolicy: ReaderPagingPolicy {
        ReaderPagingPolicy(preferences: environment.preferences.preferences)
    }

    private var readerTheme: ReaderTheme {
        environment.preferences.preferences.theme
    }

    private var palette: ReaderPalette {
        ReaderPalette.resolved(readerTheme, systemDark: systemColorScheme == .dark)
    }

    /// Once the reader root ignores safe areas, an inner GeometryReader sees
    /// zero insets. Reader chrome still needs the window's real inset so it
    /// clears the Dynamic Island and home indicator while page content stays
    /// genuinely edge-to-edge.
    private var windowSafeAreaInsets: UIEdgeInsets {
        let activeScene = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }
        let window = activeScene?.windows.first(where: \.isKeyWindow)
            ?? activeScene?.windows.first
        return window?.safeAreaInsets ?? .zero
    }

    /// Chrome fade+scale (round 7, ~200ms ease-out): applied ONLY to the
    /// overlay chrome layers — the page underneath never animates. Nil
    /// under Reduce Motion so the chrome snaps.
    private var chromeAnimation: Animation? {
        reduceMotion ? nil : .easeOut(duration: 0.2)
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
            readerSheet {
                if let model {
                    CollectionOutlineSheet(
                        model: model,
                        arabicVisible: environment.preferences.preferences.arabicVisible,
                        translationVisible: environment.preferences.preferences.translationVisible
                    )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
                }
            }
        }
        .sheet(isPresented: $showSettings) {
            readerSheet {
                if let model {
                    ReaderSettingsSheet(model: model)
                        .presentationDetents([.medium, .large])
                        .presentationDragIndicator(.hidden)
                }
            }
        }
        .sheet(isPresented: $showSearch) {
            readerSheet {
                if let model {
                    ReaderSearchSheet(
                        collectionSlug: model.collectionSlug,
                        collectionName: model.collectionName,
                        search: { text in await model.searchEnglish(text: text) },
                        onOpen: { result in
                            showSearch = false
                            model.jumpToReference(result.providerHadithId)
                        }
                    )
                    // Search opens at medium with large available.
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.hidden)
                }
            }
        }
        .sheet(isPresented: $showSavedShortcut) {
            readerSheet {
                ReaderSavedShortcutSheet(
                    onOpen: { ref in
                        showSavedShortcut = false
                        if let number = ref.hadithNumber, !number.isEmpty {
                            model?.jumpToHadith(volumeId: ref.volumeId, hadithNumber: number)
                        }
                    },
                    onEdit: {
                        showSavedShortcut = false
                        dismiss()
                        NotificationCenter.default.post(name: .hadithlyOpenSavedTab, object: nil)
                    }
                )
                // Bookmarks & Notes opens at medium with large available.
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.hidden)
            }
        }
        // Bookmark placement is a centered modal dialog (round 7), rendered
        // as an overlay in readingView — not a bottom sheet.
        .sheet(isPresented: $showQuotaPaywall) {
            readerSheet {
                QuotaPaywallView {
                    Task {
                        try? await Task.sleep(for: .seconds(1))
                        model?.retryTranslationsAfterPurchase()
                    }
                }
                .presentationDetents([.large])
            }
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
        GeometryReader { viewport in
            ZStack {
                palette.background.ignoresSafeArea()

                pageStrip(model, viewportWidth: viewport.size.width)

                // Chrome fade+scale (round 7): both chrome layers stay in
                // the hierarchy and crossfade in place — fade + slight
                // scale, ~200ms ease-out, snap under Reduce Motion. The
                // page underneath never moves, fades, or re-lays-out.
                ReaderFocusedProgressBar(
                    fraction: pageScrollFraction,
                    palette: palette,
                    topInset: windowSafeAreaInsets.top
                )
                .opacity(model.chromeVisible ? 0 : 1)
                .scaleEffect(model.chromeVisible ? 0.92 : 1)
                .animation(chromeAnimation, value: model.chromeVisible)
                .allowsHitTesting(false)

                chromeOverlay(
                    model,
                    topInset: windowSafeAreaInsets.top,
                    bottomInset: windowSafeAreaInsets.bottom
                )
                    .opacity(model.chromeVisible ? 1 : 0)
                    .scaleEffect(model.chromeVisible ? 1 : 0.96)
                    .animation(chromeAnimation, value: model.chromeVisible)
                    .allowsHitTesting(model.chromeVisible)
                    .accessibilityHidden(!model.chromeVisible)

                // Bookmark placement (round 7): a centered modal dialog
                // over a dimmed backdrop, not a bottom sheet. Same options
                // and actions; backdrop tap cancels.
                if showBookmarkPlacement, let hadith = positionedHadith(model) {
                    Color.black.opacity(0.4).ignoresSafeArea()
                        .onTapGesture { showBookmarkPlacement = false }
                        .accessibilityIdentifier("reader.bookmarkPlacement.backdrop")
                    ReaderBookmarkPlacementDialog(
                        pageFirst: model.currentPageHadiths.first,
                        positioned: hadith,
                        onChoose: { target in
                            model.toggleBookmark(target)
                            showBookmarkPlacement = false
                        },
                        onCancel: { showBookmarkPlacement = false }
                    )
                }
            }
        }
        .overlay {
            WindowSwipeRecognizer(
                pageDirection: pagingPolicy.pageDirection,
                isEnabled: { !showIndex && !showSettings && !showSearch && !showSavedShortcut && !showBookmarkPlacement },
                onTurn: { _ in },
                onProgress: { dragProgress(model, offset: $0) },
                onRelease: { dragReleased(model, turn: $0) }
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
            toggleChrome(model)
        }
        // A menu never survives a focus change: any scroll or page turn
        // collapses the chrome in the model, and the menu closes here.
        .onChange(of: model.chromeVisible) { _, visible in
            if !visible, showReaderMenu {
                showReaderMenu = false
            }
        }
        // A layout-affecting preference change (font, size, visibility,
        // translation locale) invalidates the raw offset; the semantic
        // anchor restores the exact position against the new signature.
        .onChange(of: environment.preferences.preferences.layoutProjection) { _, _ in
            model.reanchorAfterLayoutChange()
        }
        // The reader deliberately owns the whole display in both modes.
        // Safe-area insets must never reserve an empty band above or below
        // the page; status and reader chrome are overlays on that content.
        .ignoresSafeArea()
        // The status bar hides with focused chrome. The page itself remains
        // full-bleed in both states, so this system-chrome change never
        // resizes or repositions reading content.
        .statusBarHidden(!model.chromeVisible)
    }

    /// A sheet is presented in a new hosting hierarchy, so it must receive
    /// the reader palette explicitly. Without this bridge every reader sheet
    /// falls back to the environment's dark default even when the page is
    /// Light or Paper.
    @ViewBuilder
    private func readerSheet<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .environment(\.readerTheme, readerTheme)
            .environment(\.readerPalette, palette)
            .preferredColorScheme(ReaderPalette.preferredColorScheme(for: readerTheme))
            .presentationBackground(palette.background)
    }

    // MARK: - Axis-locked drag paging (R6 round 3, note 1)

    /// Whether a logical turn has a drag target: a loaded neighbor page or
    /// a cross-volume jump. Directions without a target clamp at rest.
    private func stripTargets(_ model: ReaderModel) -> (previous: Bool, next: Bool) {
        let atLoadedPage = model.pages.indices.contains(model.pageIndex)
            && !model.pages[model.pageIndex].isPlaceholder
        let previous = model.hasPreviousPage || (atLoadedPage && model.previousVolume != nil)
        let next = model.hasNextPage || (atLoadedPage && model.nextVolume != nil)
        return (previous, next)
    }

    /// The three-page strip: the loaded previous/current/next pages
    /// rendered together so the neighbor is visible mid-gesture, with
    /// cancel-back when the finger releases short. Cross-volume targets
    /// show a quiet loading slot until their first page arrives. Every slot
    /// keeps a stable identity across page turns (no `.id`, no removal
    /// transition): the center page never rebuilds on a turn, so the
    /// header/corner slot cannot pop in late and shift content. Scroll
    /// position is driven explicitly instead — cached offset for revisits,
    /// top for first visits (see ReaderPageView).
    private func pageStrip(_ model: ReaderModel, viewportWidth: CGFloat) -> some View {
        let targets = stripTargets(model)
        let slots = ReaderDragStrip.slots(
            hasPrevious: targets.previous,
            hasNext: targets.next,
            pageDirection: pagingPolicy.pageDirection
        )
        let baseOffset = slots.left == nil ? 0 : -viewportWidth
        return HStack(spacing: 0) {
            if let left = slots.left {
                stripSlot(model, turn: left, viewportWidth: viewportWidth)
            }
            ReaderPageView(
                model: model,
                hadiths: model.currentPageHadiths,
                arabicFontSize: arabicFontSizeBinding.wrappedValue,
                preferences: environment.preferences.preferences,
                restoration: model.restoredPosition,
                restorationGeneration: model.restorationGeneration,
                landingHadithNumber: model.landingHadithNumber,
                scrollRestore: model.scrollRestoreSnapshot,
                scrollRestoreGeneration: model.scrollRestoreGeneration,
                currentPageIndex: model.pageIndex,
                pageCount: model.pages.count + (model.hasNextPage && model.pageIndex == model.pages.count - 1 ? 1 : 0),
                palette: palette,
                onTurn: { turnPage(model, turn: $0) },
                onTap: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    toggleChrome(model)
                },
                onShowPaywall: { showQuotaPaywall = true },
                onScrollFraction: { pageScrollFraction = $0 }
            )
            .frame(width: viewportWidth)
            .scrollDisabled(horizontalDragging)
            if let right = slots.right {
                stripSlot(model, turn: right, viewportWidth: viewportWidth)
            }
        }
        .offset(x: baseOffset + pageDragOffset)
        // The reading page, unlike its controls, intentionally owns the
        // entire display. This is constant across focused/unfocused chrome;
        // toggling never changes the scroll view's geometry or shifts text.
        .ignoresSafeArea(edges: [.top, .bottom])
        // The strip is wider than the screen while a neighbor slot is
        // attached: pin the layout width to the viewport (leading edge,
        // so the drag offset math holds) and clip the overflow. Without
        // this the ZStack grows to the strip width and pushes the chrome
        // circles and progress bars off-screen.
        .frame(width: viewportWidth, alignment: .leading)
        .clipped()
        .contentShape(Rectangle())
        .onChange(of: viewportWidth, initial: true) { _, width in
            dragViewportWidth = width
        }
    }

    private func stripSlot(_ model: ReaderModel, turn: ReaderPageTurn, viewportWidth: CGFloat) -> some View {
        let index = turn == .previous ? model.pageIndex - 1 : model.pageIndex + 1
        return Group {
            if model.pages.indices.contains(index),
               !model.pages[index].isPlaceholder,
               !model.pages[index].items.isEmpty {
                ReaderNeighborContent(
                    model: model,
                    hadiths: model.pages[index].items,
                    arabicFontSize: arabicFontSizeBinding.wrappedValue,
                    preferences: environment.preferences.preferences,
                    palette: palette,
                    // The swipe preview starts at the remembered offset for
                    // this page (when one is cached), so the preview and the
                    // landing show the identical position with no top-flash.
                    initialSnapshot: model.pageScrollCache[index],
                    onShowPaywall: { showQuotaPaywall = true }
                )
            } else {
                VStack {
                    ProgressView()
                        .tint(palette.textSecondary)
                        .padding(.top, 120)
                        .accessibilityIdentifier("reader.neighborLoading")
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(width: viewportWidth)
    }

    /// Gesture-driven progress: clamped to the available drag targets so a
    /// swipe with no neighbor goes nowhere. Any horizontal movement locks
    /// the vertical scroll out until release (axis lock, vice versa).
    private func dragProgress(_ model: ReaderModel, offset: CGFloat) {
        _ = model
        let clamped: CGFloat
        if offset > 0, !stripTargets(model).previous {
            clamped = 0
        } else if offset < 0, !stripTargets(model).next {
            clamped = 0
        } else {
            clamped = offset
        }
        pageDragOffset = clamped
        let dragging = abs(clamped) > 8
        if dragging != horizontalDragging {
            horizontalDragging = dragging
        }
    }

    /// Release: a committed turn first animates the strip onto the fully
    /// revealed neighbor, then swaps the page index with the offset reset —
    /// the incoming page is pixel-identical to the neighbor just shown, so
    /// the swap is invisible and nothing ever flickers. Anything short
    /// springs back in place. No haptic: page settle is silent (round 5).
    private func dragReleased(_ model: ReaderModel, turn: ReaderPageTurn?) {
        horizontalDragging = false
        guard let turn else {
            if pageDragOffset != 0 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.9)) {
                    pageDragOffset = 0
                }
            }
            return
        }
        let slots = ReaderDragStrip.slots(
            hasPrevious: stripTargets(model).previous,
            hasNext: stripTargets(model).next,
            pageDirection: pagingPolicy.pageDirection
        )
        let width = max(1, dragViewportWidth)
        if !reduceMotion,
           let target = ReaderDragStrip.commitDragOffset(viewportWidth: width, turn: turn, slots: slots) {
            withAnimation(.easeOut(duration: 0.22)) {
                pageDragOffset = target
            } completion: {
                turnPage(model, turn: turn)
                pageDragOffset = 0
            }
        } else {
            pageDragOffset = 0
            turnPage(model, turn: turn)
        }
    }

    /// Toggling the chrome flips the model; only the overlay chrome layers
    /// animate (fade + slight scale via chromeAnimation), so the page never
    /// moves, shifts, or re-lays-out. (VoiceOver uses the same path through
    /// the accessibility action, without the tap haptic.)
    private func toggleChrome(_ model: ReaderModel) {
        model.chromeVisible.toggle()
    }

    private func turnPage(_ model: ReaderModel, turn: ReaderPageTurn) {
        if turn == .next {
            if model.hasNextPage {
                model.pageIndex += 1
            } else if let next = model.nextVolume {
                // An outward swipe past the last page advances to the next
                // volume's first page — the same jump path as the pills.
                model.switchToVolume(next.volumeId, edge: .first)
            }
        } else {
            if model.hasPreviousPage {
                model.pageIndex -= 1
            } else if let previous = model.previousVolume {
                // Before the first page goes to the previous volume's last
                // page — the same jump path as the pills.
                model.switchToVolume(previous.volumeId, edge: .last)
            }
        }
    }

    private func chromeOverlay(
        _ model: ReaderModel,
        topInset: CGFloat,
        bottomInset: CGFloat
    ) -> some View {
        VStack(spacing: 0) {
            // Unfocused (Sajda `208 page` + `11 juz` style): TWO pills side
            // by side, bold number + lighter suffix. The Page pill fills by
            // intra-page scroll; the Volume pill fills by page fraction
            // within the volume. Neutral, never green, never mid-screen.
            ReaderUnfocusedProgressPills(
                pageNumber: model.pageIndex + 1,
                pageFill: ReaderProgressBars.pagePillFillFraction(pageScrollFraction),
                volumeNumber: ReaderProgressBars.volumePosition(
                    selectedVolumeId: model.selectedVolumeId,
                    volumes: model.volumes
                ),
                volumeCount: model.volumes.count,
                volumeFill: ReaderProgressBars.volumePillFillFraction(
                    pageIndex: model.pageIndex,
                    totalPages: model.totalPages,
                    intraPageFraction: pageScrollFraction
                ),
                palette: palette
            )
            .padding(.top, topInset + 8)
            Spacer()
            if showReaderMenu {
                ReaderMenuStack(
                    bookmarked: positionedHadith(model).map { model.isBookmarked($0) } ?? false,
                    positionedReference: positionedHadith(model)?.referenceDisplay ?? "",
                    palette: palette,
                    onContents: {
                        ReaderHapticDispatcher.trigger(.menuItemTap)
                        showReaderMenu = false
                        showIndex = true
                    },
                    onSaved: {
                        ReaderHapticDispatcher.trigger(.menuItemTap)
                        showReaderMenu = false
                        showSavedShortcut = true
                    },
                    onSettings: {
                        ReaderHapticDispatcher.trigger(.menuItemTap)
                        showReaderMenu = false
                        showSettings = true
                    },
                    onBookmark: { menuBookmark(model) },
                    onSearch: {
                        ReaderHapticDispatcher.trigger(.menuItemTap)
                        showReaderMenu = false
                        showSearch = true
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            HStack {
                ReaderBottomCircles(
                    menuOpen: showReaderMenu,
                    palette: palette,
                    onClose: { dismiss() },
                    onMenu: {
                        ReaderHapticDispatcher.trigger(.menuToggle)
                        withAnimation(.easeInOut(duration: 0.2)) { showReaderMenu.toggle() }
                    }
                )
            }
            .padding(.horizontal, 24)
            .padding(.bottom, bottomInset + 16)
        }
    }

    /// The menu bookmark acts on the positioned (R2 anchor) hadith: when it
    /// is already bookmarked the button removes it (the model plays the
    /// remove haptic); otherwise the placement sheet opens with a tap
    /// haptic and the model plays add/remove on choice.
    private func menuBookmark(_ model: ReaderModel) {
        guard positionedHadith(model) != nil else { return }
        if positionedHadith(model).map({ model.isBookmarked($0) }) == true,
           let hadith = positionedHadith(model) {
            model.toggleBookmark(hadith)
        } else {
            ReaderHapticDispatcher.trigger(.menuItemTap)
            // The menu closes first so its cards never ghost behind the
            // modal's dimmed backdrop.
            showReaderMenu = false
            showBookmarkPlacement = true
        }
    }

    private func positionedHadith(_ model: ReaderModel) -> ReaderHadith? {
        let target = model.restoredPosition?.anchor.providerHadithId ?? model.landingHadithNumber
        return model.currentPageHadiths.first { $0.providerHadithId == target } ?? model.currentPageHadiths.first
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

/// The two bottom circles (R6 round 3): back is a chevron-left circle, the
/// menu circle toggles the stack. Factored out so the UI fixture renders
/// the production row.
struct ReaderBottomCircles: View {
    let menuOpen: Bool
    let palette: ReaderPalette
    let onClose: () -> Void
    let onMenu: () -> Void

    var body: some View {
        HStack {
            ReaderChromeCircle("chevron.left", label: "Close reader", palette: palette, action: onClose)
                .accessibilityIdentifier("reader.close")
            Spacer()
            ReaderChromeCircle(
                menuOpen ? "xmark" : "line.3.horizontal",
                label: menuOpen ? "Close reader menu" : "Open reader menu",
                palette: palette,
                action: onMenu
            )
            .accessibilityIdentifier("reader.menu")
        }
    }
}

/// The bottom menu stack (R6 round 3, Sajda order, no excess): Contents,
/// Bookmarks & Notes, Settings, then a bottom row of Bookmark plus
/// functional Search. Anchored bottom-right like the Sajda menu — inset
/// from the leading edge at roughly the trailing two-thirds width, tighter
/// padding and heights. The bookmark button keeps default contrast when
/// active: ONLY its icon turns amber, never the whole card.
private struct ReaderMenuStack: View {
    let bookmarked: Bool
    let positionedReference: String
    let palette: ReaderPalette
    let onContents: () -> Void
    let onSaved: () -> Void
    let onSettings: () -> Void
    let onBookmark: () -> Void
    let onSearch: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            Spacer(minLength: 0)
            VStack(spacing: 6) {
                menuCard(title: "Contents", subtitle: "Volumes and chapters", image: "list.bullet", action: onContents)
                    .accessibilityIdentifier("reader.menu.contents")
                menuCard(
                    title: "Bookmarks & Notes",
                    subtitle: "Your private saved reading",
                    image: "bookmark",
                    action: onSaved
                )
                .accessibilityIdentifier("reader.menu.saved")
                menuCard(title: "Settings", subtitle: "Type, appearance, and text", image: "textformat.size", action: onSettings)
                    .accessibilityIdentifier("reader.menu.settings")
                // Round 5, fix 6: the bottom row is icon-only (no text
                // labels), equal size — Bookmark plus functional Search.
                HStack(spacing: 8) {
                    menuIconButton(
                        image: bookmarked ? "bookmark.fill" : "bookmark",
                        tint: bookmarked ? Theme.bookmark : palette.textSecondary,
                        label: bookmarked ? "Remove bookmark for positioned hadith" : "Bookmark positioned hadith",
                        identifier: "reader.menu.bookmark",
                        action: onBookmark
                    )
                    menuIconButton(
                        image: "magnifyingglass",
                        tint: palette.textSecondary,
                        label: "Search",
                        identifier: "reader.menu.search",
                        action: onSearch
                    )
                }
            }
            .frame(maxWidth: 280)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("reader.menuStack")
    }

    /// One equal-size icon-only menu button for the bottom row.
    private func menuIconButton(
        image: String,
        tint: Color,
        label: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: image)
                .font(.title3)
                .foregroundStyle(tint)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(palette.surface.opacity(0.98))
                .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .accessibilityLabel(label)
        .accessibilityIdentifier(identifier)
    }

    private func menuCard(title: String, subtitle: String, image: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.headline).foregroundStyle(palette.textPrimary)
                    Text(subtitle).font(.caption).foregroundStyle(palette.textSecondary).lineLimit(1)
                }
                Spacer()
                Image(systemName: image).font(.title3).foregroundStyle(palette.textSecondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 52)
            .background(palette.surface.opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Progress (R6 round 3, note 6)

/// Focused: ONE thin narrow progress capsule just below the notch —
/// 88×4pt, centered, neutral. Always rendered in focused mode: the track
/// uses the secondary text color (visible on all four reader themes) and
/// the fill never collapses below a 10pt nub, so the capsule stays visible
/// even at zero scroll. Non-interactive and skipped by assistive tech.
private struct ReaderFocusedProgressBar: View {
    let fraction: Double
    let palette: ReaderPalette
    /// The full-bleed reader passes its system inset so this chrome sits
    /// below the Dynamic Island while text remains underneath it.
    var topInset: CGFloat = 0

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// Fixed bar size: ~1/4 of a phone width, 4pt thick.
    static let barWidth: CGFloat = 88
    static let barHeight: CGFloat = 4
    /// Minimum fill width so the capsule reads at zero scroll.
    static let minFillWidth: CGFloat = 10

    private var clampedFraction: Double { min(1, max(0, fraction)) }

    var body: some View {
        VStack {
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(palette.textSecondary.opacity(0.55))
                Capsule()
                    .fill(palette.textPrimary.opacity(0.95))
                    .frame(width: max(Self.minFillWidth, Self.barWidth * clampedFraction))
                    // The fill glides to the new fraction on a page switch
                    // (~250ms ease-out, snap under Reduce Motion) instead
                    // of jumping instantly.
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: clampedFraction)
            }
            .frame(width: Self.barWidth, height: Self.barHeight)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.top, topInset + 6)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .accessibilityIdentifier("reader.focusedProgress")
    }
}

/// Unfocused: TWO pills side by side (Sajda `208 page` + `11 juz` style —
/// bold number, lighter suffix). The Page pill fills by intra-page scroll;
/// the Volume pill fills by page fraction within the volume. Neutral —
/// no green, no full-width, never mid-screen. The container carries the
/// accessible position; the pills themselves stay silent.
private struct ReaderUnfocusedProgressPills: View {
    let pageNumber: Int
    /// Intra-page scroll fraction (0 top, 1 bottom) behind the Page pill.
    let pageFill: Double
    /// 1-based volume position behind the Volume pill. Nil hides it.
    let volumeNumber: Int?
    let volumeCount: Int
    /// Page fraction within the volume behind the Volume pill.
    let volumeFill: Double?
    let palette: ReaderPalette

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 8) {
            progressPill(number: "\(pageNumber)", suffix: "page", fill: pageFill)
            if let volumeNumber {
                progressPill(number: "\(volumeNumber)", suffix: "volume", fill: volumeFill ?? 0)
            }
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier("reader.unfocusedProgress")
    }

    private func progressPill(number: String, suffix: String, fill: Double) -> some View {
        // The fill occupies the FULL pill height (no vertical margins) and
        // glides horizontally to the fraction; the outer capsule clip keeps
        // the ends round at every value. The fill glides to the new
        // fraction on a page switch (~250ms ease-out, snap under Reduce
        // Motion) instead of jumping instantly.
        let clamped = min(1, max(0, fill))
        return ZStack {
            // Opaque track: the pills float over full-bleed page content,
            // so the track must fully occlude text scrolling beneath.
            Capsule()
                .fill(palette.surface)
            GeometryReader { proxy in
                Capsule()
                    .fill(palette.textSecondary.opacity(0.35))
                    .frame(width: proxy.size.width * clamped, height: proxy.size.height)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
                    .animation(reduceMotion ? nil : .easeOut(duration: 0.25), value: clamped)
            }
            .clipShape(Capsule())
            HStack(spacing: 4) {
                Text(number)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(palette.textPrimary)
                Text(suffix)
                    .font(.caption)
                    .foregroundStyle(palette.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .center)
        }
        .frame(width: 104, height: 30)
        .clipShape(Capsule())
        .overlay(Capsule().strokeBorder(palette.divider, lineWidth: 1))
        .accessibilityHidden(true)
    }

    private var accessibilityText: String {
        var parts: [String] = ["Page \(pageNumber)"]
        if let volumeNumber, volumeCount > 0 {
            parts.append("Volume \(volumeNumber) of \(volumeCount)")
        }
        return parts.joined(separator: ", ")
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

/// Scroll offset snapshot for the focused progress bar: the content height
/// and the content-top offset in the page coordinate space.
private struct ReaderScrollState: Equatable {
    let contentHeight: CGFloat
    let minY: CGFloat
}

private struct ReaderScrollStateKey: PreferenceKey {
    static var defaultValue: ReaderScrollState? = nil

    static func reduce(value: inout ReaderScrollState?, nextValue: () -> ReaderScrollState?) {
        value = nextValue() ?? value
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
    /// Round 5, fix 4b: transient per-page offset restore when navigating
    /// back to one of the last two pages. Takes precedence over the
    /// semantic restoration/landing target; nil starts at the top.
    let scrollRestore: PageScrollSnapshot?
    let scrollRestoreGeneration: Int
    let currentPageIndex: Int
    let pageCount: Int
    let palette: ReaderPalette
    let onTurn: (ReaderPageTurn) -> Void
    /// Direct page tap only. Buttons and long-press context actions keep
    /// their own gestures; vertical scrolls and horizontal paging do not
    /// invoke this closure.
    let onTap: () -> Void
    let onShowPaywall: () -> Void
    /// When set, the page reports its vertical scroll fraction (0 top, 1
    /// bottom) for the focused progress bar. Only the centered strip page
    /// passes this; neighbor slots stay silent.
    var onScrollFraction: ((Double) -> Void)? = nil

    @State private var appliedRestorationKey: String?
    @State private var chapterOpenings: Set<Int> = []
    /// Round 8: the page index the view last scrolled to top for. The
    /// center page keeps a stable identity across turns (no re-key), so a
    /// first visit must scroll to top explicitly; revisits and R2 targets
    /// are claimed by the restoration block before this is consulted.
    @State private var topResetPage: Int?

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
        return ReaderVolumeRange.cornerText(
            volumeTitle: localizedVolumeTitle(title, preferences: preferences),
            pages: model.pages
        )
    }

    /// Fixed header slot (round 7): the corner label (other pages) or the
    /// volume-start header (first page) reserves its space synchronously,
    /// so the page appears with its header already laid out — zero layout
    /// shift when the text arrives. Placeholders use the same fonts but
    /// carry no identifiers, so element queries only ever match real
    /// content (the corner never exists on page 0 and vice versa).
    @ViewBuilder
    private var headerSlot: some View {
        if ReaderVolumeHeader.showsHeader(pageIndex: currentPageIndex) {
            if let volume = selectedVolume {
                ReaderVolumeHeaderView(
                    volume: volume,
                    palette: palette,
                    arabicVisible: preferences.arabicVisible,
                    translationVisible: preferences.translationVisible,
                    volumeNumber: model.volumes.firstIndex(where: { $0.volumeId == volume.volumeId }).map { $0 + 1 }
                )
            } else {
                ReaderVolumeHeaderPlaceholder(palette: palette)
            }
        } else if let corner = volumeCornerText {
            ReaderVolumeCornerLabel(text: corner, palette: palette)
        } else {
            Text(verbatim: " ")
                .font(.caption2.weight(.medium))
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityHidden(true)
        }
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
                            headerSlot
                            ForEach(Array(hadiths.enumerated()), id: \.element.internalId) { index, hadith in
                                if chapterOpenings.contains(index) {
                                    VStack(spacing: 12) {
                                        ReaderChapterHeader(
                                            title: ReaderChapterLine.displayTitle(
                                                title: hadith.chapterName ?? "",
                                                arabicTitle: ReaderChapterLine.arabicTitle(
                                                    forChapterId: hadith.chapterId,
                                                    in: model.volumes,
                                                    volumeId: model.selectedVolumeId
                                                ),
                                                arabicVisible: preferences.arabicVisible,
                                                translationVisible: preferences.translationVisible
                                            ),
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
                                onFollow: { model.followPill($0) },
                                arabicVisible: preferences.arabicVisible,
                                translationVisible: preferences.translationVisible
                            )
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 22)
                        .padding(.top, 20)
                        .padding(.bottom, 80)
                        .background(
                            GeometryReader { content in
                                Color.clear.preference(
                                    key: ReaderScrollStateKey.self,
                                    value: ReaderScrollState(
                                        contentHeight: content.size.height,
                                        minY: content.frame(in: .named("reader.page")).minY
                                    )
                                )
                            }
                        )
                    }
                }
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "reader.page")
                .onPreferenceChange(ReaderScrollStateKey.self) { state in
                    guard let onScrollFraction, let state else { return }
                    let scrolled = max(0, -state.minY)
                    let raw = ReaderProgressBars.scrollFraction(
                        contentHeight: state.contentHeight,
                        viewportHeight: viewport.size.height,
                        scrolled: scrolled
                    )
                    onScrollFraction((raw * 200).rounded() / 200)
                }
                .onPreferenceChange(ReaderAnchorFramesKey.self) { frames in
                    let targetId = scrollRestore?.providerHadithId
                        ?? restoration?.anchor.providerHadithId ?? landingHadithNumber
                    let targetOffset = scrollRestore?.normalizedOffset
                        ?? restoration?.normalizedOffset ?? 0
                    if let targetId,
                       let target = hadiths.first(where: { $0.providerHadithId == targetId }),
                       let frame = frames[target.internalId] {
                        let key = "\(scrollRestoreGeneration):\(restorationGeneration):\(target.internalId):\(targetOffset):\(viewport.size.height)"
                        if appliedRestorationKey != key {
                            appliedRestorationKey = key
                            let anchorY = ReaderScrollRestoration.anchorY(
                                normalizedOffset: targetOffset,
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
                    // First visit to a page: scroll to the very top exactly
                    // once — but ONLY when no restore/landing target exists
                    // for this page at all (checked against the hadiths, not
                    // the frames, so a revisit whose frames haven't landed
                    // yet can never be yanked to top before its restore
                    // claims it below). The stable view identity keeps the
                    // old offset otherwise, which would show mid-content of
                    // the new page.
                    let restoreTargetId = scrollRestore?.providerHadithId
                        ?? restoration?.anchor.providerHadithId ?? landingHadithNumber
                    let hasRestoreTarget = restoreTargetId.flatMap { id in
                        hadiths.first(where: { $0.providerHadithId == id })
                    } != nil
                    if !hasRestoreTarget, topResetPage != currentPageIndex, let first = hadiths.first {
                        topResetPage = currentPageIndex
                        proxy.scrollTo(first.internalId, anchor: .top)
                        return
                    }
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
        .onTapGesture(perform: onTap)
        .onAppear { chapterOpenings = ReaderChapterBoundaries.openingIndices(in: hadiths) }
        .onChange(of: hadiths) { _, updated in
            chapterOpenings = ReaderChapterBoundaries.openingIndices(in: updated)
        }
        // A volume switch can keep the page index: force the top-reset path
        // to re-arm so a stale offset from the previous volume never sticks.
        // (Restoration/revisit targets still claim first in the handler.)
        .onChange(of: model.selectedVolumeId) { _, _ in topResetPage = nil }
        .accessibilityIdentifier("reader.page")
    }
}

/// A pre-rendered neighbor page for the drag strip (R6 round 3): the same
/// hadith blocks and chapter lines as the current page, but passive — no
/// restoration, no scroll capture, no pills, no scrolling of its own. The
/// blocks stay actionable (context menu, source sheet) on real data. When
/// the reader visited this page recently, the preview starts at the
/// remembered offset so it matches the landing exactly.
private struct ReaderNeighborContent: View {
    let model: ReaderModel
    let hadiths: [ReaderHadith]
    let arabicFontSize: Double
    let preferences: ReaderPreferences
    let palette: ReaderPalette
    /// Remembered offset for this page, when one is cached. Applied the
    /// moment the preview lays out — before any gesture reveals it.
    var initialSnapshot: PageScrollSnapshot? = nil
    let onShowPaywall: () -> Void

    @State private var chapterOpenings: Set<Int> = []
    @State private var appliedPreviewKey: String?

    /// One hadith row with scroll-anchor tracking, so the remembered
    /// offset can target the same anchor the landing restores.
    private func neighborRow(_ hadith: ReaderHadith) -> some View {
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
            let frame = geometry.frame(in: .named("reader.neighbor"))
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
                    VStack(spacing: 28) {
                        ForEach(Array(hadiths.enumerated()), id: \.element.internalId) { index, hadith in
                            if chapterOpenings.contains(index) {
                                VStack(spacing: 12) {
                                    ReaderChapterHeader(
                                        title: ReaderChapterLine.displayTitle(
                                            title: hadith.chapterName ?? "",
                                            arabicTitle: ReaderChapterLine.arabicTitle(
                                                forChapterId: hadith.chapterId,
                                                in: model.volumes,
                                                volumeId: model.selectedVolumeId
                                            ),
                                            arabicVisible: preferences.arabicVisible,
                                            translationVisible: preferences.translationVisible
                                        ),
                                        arabicTitle: ReaderChapterLine.arabicTitle(
                                            forChapterId: hadith.chapterId,
                                            in: model.volumes,
                                            volumeId: model.selectedVolumeId
                                        ),
                                        arabicVisible: preferences.arabicVisible,
                                        palette: palette
                                    )
                                    neighborRow(hadith)
                                }
                                .padding(.top, 12)
                            } else {
                                neighborRow(hadith)
                            }
                        }
                    }
                    .padding(.horizontal, 22)
                    .padding(.top, 20)
                    .padding(.bottom, 80)
                }
                .scrollDisabled(true)
                .scrollIndicators(.hidden)
                .coordinateSpace(name: "reader.neighbor")
                .onPreferenceChange(ReaderAnchorFramesKey.self) { frames in
                    guard let snapshot = initialSnapshot,
                          let target = hadiths.first(where: { $0.providerHadithId == snapshot.providerHadithId }),
                          let frame = frames[target.internalId]
                    else { return }
                    let key = "\(target.internalId):\(snapshot.normalizedOffset):\(viewport.size.height)"
                    guard appliedPreviewKey != key else { return }
                    appliedPreviewKey = key
                    let anchorY = ReaderScrollRestoration.anchorY(
                        normalizedOffset: snapshot.normalizedOffset,
                        itemHeight: frame.height,
                        viewportHeight: viewport.size.height
                    )
                    proxy.scrollTo(target.internalId, anchor: UnitPoint(x: 0.5, y: anchorY))
                }
            }
        }
        .onAppear {
            chapterOpenings = ReaderChapterBoundaries.openingIndices(in: hadiths)
            appliedPreviewKey = nil
        }
        .onChange(of: hadiths) { _, updated in
            chapterOpenings = ReaderChapterBoundaries.openingIndices(in: updated)
            appliedPreviewKey = nil
        }
        .onChange(of: initialSnapshot) { _, _ in
            appliedPreviewKey = nil
        }
        .accessibilityIdentifier("reader.neighborPage")
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
            // Single line always: appending the `: first–last` range once
            // the volume is fully cached must not change the slot height.
            .lineLimit(1)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityIdentifier("reader.volumeCorner")
    }
}

/// Volume-start header (R6 slice A): the ACTUAL volume name as the big
/// centered title (`firstChapterTitle`, else the first source-provided
/// chapter title, else the outline title) with a small quiet "Volume N"
/// eyebrow above it and the localized count line beneath. First page of a
/// volume only; the corner label yields to it there. The eyebrow is hidden
/// from assistive tech so the header label keeps its stable
/// "<title>, <count> hadiths" shape.
private struct ReaderVolumeHeaderView: View {
    let volume: OutlineVolume
    let palette: ReaderPalette
    var arabicVisible: Bool = true
    var translationVisible: Bool = true
    /// 1-based position in outline order for the quiet eyebrow. Nil hides it.
    var volumeNumber: Int? = nil

    private var prefs: ReaderPreferences {
        var preferences = ReaderPreferences()
        preferences.arabicVisible = arabicVisible
        preferences.translationVisible = translationVisible
        return preferences
    }

    private var title: String {
        localizedVolumeTitle(
            ReaderVolumeHeaderTitle.actualTitle(
                volume: volume,
                arabicVisible: arabicVisible,
                translationVisible: translationVisible
            ),
            preferences: prefs
        )
    }

    var body: some View {
        VStack(spacing: 6) {
            if let volumeNumber {
                Text(String(localized: "Volume \(volumeNumber)"))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(palette.textSecondary.opacity(0.8))
                    .accessibilityHidden(true)
            }
            Text(title)
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
        .accessibilityLabel("\(title), \(volume.hadithCount) hadiths")
        .accessibilityIdentifier("reader.volumeHeader")
    }
}

/// Identifier-free stand-in with the exact font stack of
/// ReaderVolumeHeaderView, so the first-page slot keeps its height before
/// the volume arrives. Hidden from assistive tech and element queries.
private struct ReaderVolumeHeaderPlaceholder: View {
    let palette: ReaderPalette

    var body: some View {
        VStack(spacing: 6) {
            Text(verbatim: " ")
                .font(.caption2.weight(.semibold))
            Text(verbatim: " ")
                .font(.title2.weight(.semibold))
            Text(verbatim: " ")
                .font(.footnote)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 8)
        .accessibilityHidden(true)
    }
}

/// Volume titles follow the visible layers (R6 round 3): Arabic-only mode
/// renders the localized volume name (`Volume %lld`) instead of the
/// backend English title; every other mode keeps the outline title.
func localizedVolumeTitle(_ title: String, preferences: ReaderPreferences) -> String {
    ReaderVolumeTitle.displayTitle(
        title: title,
        arabicVisible: preferences.arabicVisible,
        translationVisible: preferences.translationVisible
    ) { number in
        String(localized: "Volume \(number)")
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
    /// Visible layers for the neighbor-volume titles: Arabic-only mode
    /// renders the localized volume name. Defaults keep the outline title.
    var arabicVisible: Bool = true
    var translationVisible: Bool = true

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
        let label = pill.crossesVolume
            ? localizedVolumeTitle(pill.label, preferences: pillPreferences)
            : pill.label
        return Button {
            onFollow(pill)
        } label: {
            HStack(spacing: 2) {
                if turn == .previous {
                    chevron(turn)
                }
                Text(label)
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
            turn == .previous ? "Previous page, \(label)" : "Next page, \(label)"
        )
        .accessibilityIdentifier(
            turn == .previous ? "reader.previousPage" : "reader.nextPage"
        )
    }

    private var pillPreferences: ReaderPreferences {
        var preferences = ReaderPreferences()
        preferences.arabicVisible = arabicVisible
        preferences.translationVisible = translationVisible
        return preferences
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

    /// The narrator line in every visibility mode. Arabic-only mode shows
    /// the provider Arabic narrator (`narratorAr`), RTL-aligned between the
    /// header and the Arabic block, and hides when it is absent. Mixed and
    /// translation-only modes keep the English narrator line beside the
    /// translation.
    @ViewBuilder
    private func narratorView(arabicAligned: Bool) -> some View {
        if let line = ReaderNarratorLine.text(
            narrator: hadith.narrator,
            narratorAr: hadith.narratorAr,
            arabicVisible: preferences.arabicVisible,
            translationVisible: preferences.translationVisible
        ) {
            Text(line)
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
        // The open tick fires only when the menu actually presents (after
        // the 0.5s hold): a touch-down that becomes a swipe or scroll must
        // never tick.
        .onLongPressGesture(minimumDuration: 0.5) {
            ReaderHapticDispatcher.trigger(.contextMenuOpen)
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
    /// bookmark when bookmarked, pink heart when favorited, green note when
    /// a note exists). Tapping opens the source sheet; copy/share payloads
    /// keep the full source line unchanged (`ReaderShare`). The markers are
    /// non-interactive indicators — actions remain the long-press context
    /// menu, the VoiceOver custom actions below, and the bottom menu.
    ///
    /// The seven R5 actions live here as VoiceOver custom actions: the
    /// screen-reader equivalent of the long-press menu. Share presents the
    /// system share sheet programmatically with the same canonical URL the
    /// menu's ShareLink carries.
    private var headerRow: some View {
        let kind = ReaderGradeKind(normalizedGrade: hadith.authenticity.normalizedGrade)
        let bookmarked = model.isBookmarked(hadith)
        let favorited = model.isFavorite(hadith)
        let hasNote = model.noteContent(for: hadith) != nil
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
            ForEach(ReaderSavedMarkers.visible(bookmarked: bookmarked, favorited: favorited, hasNote: hasNote), id: \.self) { marker in
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
                case .note:
                    Image(systemName: "square.and.pencil")
                        .font(.caption2)
                        .foregroundStyle(.green)
                        .accessibilityIdentifier("reader.savedNote")
                        .accessibilityLabel("Has note")
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
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .frame(minHeight: 160)
                    .padding(1)
                    .background(palette.surface)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(16)
            .background(palette.background.ignoresSafeArea())
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
                        ReaderFocusedProgressBar(fraction: fraction, palette: palette)
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
/// Deterministic round-3 fixture: the menu stack, search sheet, saved
/// shortcut, and bookmark placement with no network. Launch with
/// `-R6Round3Fixture` and `R6_SCREEN=menu|search|saved|placement`.
/// - search: `R6_SEARCH_STUB=results` returns two canned Sunnah.now rows
///   after typing; anything else renders the quiet empty state.
/// - menu: `R6_MENU_BOOKMARKED=true` renders the filled amber bookmark.
/// - saved: an in-memory guest library seeds one bookmark (two months
///   ago) and one note (just now) for the shortcut rows.
/// Tapping a search result or shortcut row records the navigation target
/// in `r6.opened` instead of opening a network reader.
struct ReaderR6Round3FixtureView: View {
    @State private var openedReference: String?
    private let screen: String
    private let searchStub: String
    private let menuBookmarked: Bool
    private let library: UserLibraryModel

    init() {
        let environment = ProcessInfo.processInfo.environment
        screen = environment["R6_SCREEN"] ?? "menu"
        searchStub = environment["R6_SEARCH_STUB"] ?? "empty"
        menuBookmarked = environment["R6_MENU_BOOKMARKED"] == "true"
        let provider = ClerkConvexAuthProvider()
        let convex = ConvexClientWithAuth(
            deploymentUrl: "https://example.invalid",
            authProvider: provider
        )
        let store = GuestDataStore(inMemory: true)
        let twoMonthsAgo = Calendar.current.date(byAdding: .month, value: -2, to: .now) ?? .now
        store.addBookmark(draft: GuestBookmarkDraft(
            hadithId: "saved-57",
            createdAt: twoMonthsAgo,
            collectionName: "Sahih al-Bukhari",
            referenceDisplay: "Sahih al-Bukhari · Hadith 57",
            volumeId: "2",
            hadithNumber: "57"
        ))
        store.saveNote(
            hadithId: "saved-59",
            content: "Fixture note",
            collectionName: "Sahih al-Bukhari",
            referenceDisplay: "Sahih al-Bukhari · Hadith 59",
            volumeId: "2",
            hadithNumber: "59"
        )
        let library = UserLibraryModel(convex: convex, guestData: store, isSignedIn: { false })
        library.refresh()
        self.library = library
    }

    var body: some View {
        ZStack {
            ReaderPalette.dark.background.ignoresSafeArea()
            VStack {
                switch screen {
                case "search":
                    ReaderSearchSheet(
                        collectionSlug: "bukhari",
                        collectionName: "Sahih al-Bukhari",
                        search: searchStubResults,
                        onOpen: { openedReference = $0.referenceDisplay }
                    )
                case "saved":
                    ReaderSavedShortcutSheet(
                        onOpen: { openedReference = $0.referenceDisplay },
                        onEdit: { openedReference = "EDIT_SAVED" }
                    )
                case "placement":
                    placementScreen
                default:
                    menuScreen
                }
                if let openedReference {
                    Text(openedReference)
                        .foregroundStyle(ReaderPalette.dark.textSecondary)
                        .accessibilityIdentifier("r6.opened")
                }
            }
        }
        .environment(\.readerPalette, ReaderPalette.dark)
        .environment(\.readerTheme, ReaderTheme.dark)
        .environment(library)
        .preferredColorScheme(.dark)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("r6.screen")
    }

    private var menuScreen: some View {
        VStack(spacing: 8) {
            ReaderMenuStack(
                bookmarked: menuBookmarked,
                positionedReference: "Sahih al-Bukhari · Hadith 57",
                palette: ReaderPalette.dark,
                onContents: { openedReference = "CONTENTS" },
                onSaved: { openedReference = "SAVED" },
                onSettings: { openedReference = "SETTINGS" },
                onBookmark: { openedReference = "BOOKMARK" },
                onSearch: { openedReference = "SEARCH" }
            )
            .padding(.horizontal, 20)
            ReaderBottomCircles(
                menuOpen: true,
                palette: ReaderPalette.dark,
                onClose: { openedReference = "CLOSE" },
                onMenu: { openedReference = "MENU" }
            )
            .padding(.horizontal, 24)
        }
    }

    private var placementScreen: some View {
        ReaderBookmarkPlacementSheet(
            pageFirst: nil,
            positioned: ReaderR6Round3FixtureHadith.hadith57,
            onChoose: { openedReference = $0.referenceDisplay },
            onCancel: { openedReference = "CANCEL" }
        )
    }

    private func searchStubResults(_ text: String) async -> [EnglishSearchResult] {
        guard searchStub == "results" else { return [] }
        return [
            EnglishSearchResult(
                hadithId: "row-57",
                canonicalId: "sunnah_now:bukhari:57",
                collectionSlug: "bukhari",
                providerHadithId: "57",
                referenceDisplay: "Sahih al-Bukhari · Hadith 57",
                snippet: "Deeds are judged by \(text)."
            ),
            EnglishSearchResult(
                hadithId: "row-58",
                canonicalId: "sunnah_now:bukhari:58",
                collectionSlug: "bukhari",
                providerHadithId: "58",
                referenceDisplay: "Sahih al-Bukhari · Hadith 58",
                snippet: "None of you believes until he loves for his brother what \(text)."
            ),
        ]
    }
}

/// One fixture hadith for the placement screen (same shape as the R6A
/// page fixture, backend-owned Sunnah.now source truth).
enum ReaderR6Round3FixtureHadith {
    static var hadith57: ReaderHadith {
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
            narratorAr: "عن عمر بن الخطاب رضي الله عنه",
            referenceDisplay: "Sahih al-Bukhari · Hadith 57",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "sahih",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.now",
                sourceUrl: "https://sunnah.now",
                verificationMethod: "manual_collection_mapping"
            )
        )
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
        seeded.seedNotesForUITest(notedIds: ["fixture-59"])
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
            narratorAr: "عن عمر بن الخطاب رضي الله عنه",
            referenceDisplay: "Sahih al-Bukhari · Hadith 57",
            collectionName: "Sahih al-Bukhari",
            chapterName: nil,
            authenticity: ReaderAuthenticity(
                kind: "collection_scope",
                normalizedGrade: "sahih",
                claimScope: "collection",
                sourceLabel: "Documented Sahih collection",
                sourceName: "Sunnah.now",
                sourceUrl: "https://sunnah.now/bukhari/about",
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
                sourceName: "Sunnah.now",
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
                sourceName: "Sunnah.now",
                sourceUrl: "https://sunnah.now/bukhari/59",
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
                sourceName: "Sunnah.now",
                sourceUrl: "https://sunnah.now/bukhari/about",
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
                sourceName: "Sunnah.now",
                sourceUrl: "https://sunnah.now/bukhari/about",
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
                            ReaderVolumeHeaderView(
                                volume: selectedVolume,
                                palette: palette,
                                arabicVisible: preferences.arabicVisible,
                                translationVisible: preferences.translationVisible,
                                volumeNumber: volumes.firstIndex(where: { $0.volumeId == selectedVolume.volumeId }).map { $0 + 1 }
                            )
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
    var onProgress: (CGFloat) -> Void = { _ in }
    var onRelease: ((ReaderPageTurn?) -> Void)? = nil

    func makeCoordinator() -> ReaderPagingPanHandler {
        ReaderPagingPanHandler(
            pageDirection: pageDirection,
            isEnabled: isEnabled,
            onTurn: onTurn,
            onProgress: onProgress,
            onRelease: onRelease
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
        context.coordinator.onProgress = onProgress
        context.coordinator.onRelease = onRelease
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
